-- Mythos updater. On start it reads the file list published in the public
-- murilobreve/mythos-client repository (<channel>/manifest.json), compares it
-- with the client folder and downloads only the files that changed, so a
-- new version costs players a few kilobytes and the VPS no bandwidth at all.
--
-- versao.json, next to the .exe, says which build this is:
--   { "canal": "directx", "versao": 12 }
-- Without it (a client run from the source tree) the updater stays off.
-- The repository keeps every file under objects/<sha256>, so a download URL
-- never changes content and GitHub's cache can never serve a mixed version.
-- Nothing here can stop the game: any failure just leaves the current files.
--
-- While the client is open it checks again every half hour. The login
-- screen shows the state (up to date / new version / updating) and a player
-- in game gets a message when a new version comes out; it installs the next
-- time the client opens, or from the login screen's "Update now".
-- Those periodic checks read only <channel>/versao.json, a few bytes with
-- the published number; the commit and the file list (~200 KB) are read
-- again only when that number went up, and never twice for the same commit.

Updater = {}

local DEFAULT_BASE = 'https://raw.githubusercontent.com/murilobreve/mythos-client/main/'
local LOCAL_INFO = 'versao.json'
local CHECK_TIMEOUT = 8
local DOWNLOAD_TIMEOUT = 20            -- seconds to connect for each file (2 by default)
local DEFAULT_INTERVAL = 30 * 60      -- seconds between checks while open
local REMIND_EVERY = 30 * 60          -- seconds between in-game reminders
-- each check answer has a deadline of its own (connection and transfer):
-- the client has one HTTP thread for everything (VIP status, players
-- online, account creation, crash reports), and an answer that stops
-- halfway (a captive portal, a bad Wi-Fi) held all of it for up to 30
-- minutes. A cancelled request frees that thread at once.
local SMALL_DEADLINE = 15             -- seconds: the commit, the published number
local MANIFEST_DEADLINE = 60          -- seconds: the file list
-- a check that failed (offline, GitHub busy: 429 / 5xx) tries again after
-- these many seconds, then only at the next periodic check
local CHECK_RETRY_WAIT = { 60, 5 * 60 }
-- the server keeps which build each player runs, so the staff see who is
-- behind (data-otservbr-global/scripts/custom/client_version.lua)
local REPORT_OPCODE = 139

local box
local downloads = {}
-- each update gets its own number: callbacks of a cancelled one see a newer
-- number and stop, so "Update now" right after a cancel never runs two
local generation = 0
local localInfo
local versionLabel
local checkEvent
local status = 'off'                  -- off checking uptodate available updating error
local remoteVersion
local lastManifest
local remindedAt = {}                 -- version -> os.time() of the last in-game notice
local currentOperation                -- the HTTP download running now
local restartPending = false          -- installed while in game: restart after logout
local repairing = false               -- the download puts back files of this same version

-- with the version up to date, each start (and "Verificar" / "Procurar de
-- novo") also compares the client folder with the manifest, so a file the
-- antivirus took away or a copy cut short is downloaded again instead of
-- waiting for the next version. A file whose size and time did not change
-- since it was last found intact is not read again (STAMPS_FILE).
local STAMPS_FILE = '/updater_stamps.txt' -- in the player's settings folder
local VERIFY_SLICE_MS = 25                -- the check gives the screen a frame after this long
-- files the player may edit (the server address, the public settings): put
-- back only when they are missing, never over his changes
local USER_FILES = { ['servidor.ini'] = true, ['config.ini'] = true }
-- a start repairs by itself at most this often (seconds): a file that still
-- differs after the restart must not restart the client on every start.
-- "Verificar" and "Procurar de novo" always repair.
local REPAIR_FILE = '/updater_repair.txt'
local REPAIR_COOLDOWN = 60 * 60
local filesChecked = false            -- the last check found every file intact
local lastSha                         -- the commit lastManifest was read from
local failedChecks = 0                -- checks failed in a row
local retryCheckEvent
local retryEvent                      -- a file download waiting to try again

-- the fonts draw one glyph per byte (Latin-1); this file is UTF-8
local function latin1(text)
  return (tostring(text):gsub('[\194\195][\128-\191]', function(pair)
    local a, b = pair:byte(1, 2)
    return string.char((a - 194) * 64 + b)
  end))
end

local function pt()
  return (g_settings.get('locale') or 'pt') == 'pt'
end

local function txt(ptText, enText, ...)
  local text = pt() and ptText or enText
  if select('#', ...) > 0 then
    text = string.format(text, ...)
  end
  return latin1(text)
end

local function log(msg)
  g_logger.info('[Updater] ' .. msg)
end

local function baseUrl()
  local base = os.getenv and os.getenv('MYTHOS_UPDATE_URL') or nil
  base = base and base ~= '' and base or DEFAULT_BASE
  if base:sub(-1) ~= '/' then
    base = base .. '/'
  end
  return base
end

-- raw.githubusercontent.com keeps main/ in its cache for 5 minutes and
-- ignores query strings, so a client opened right after a publish saw the
-- old version. The API says which commit main is on; the files of that
-- exact commit are never stale. Without the API (offline, rate limit, or a
-- test URL) it falls back to main/.
local REF_URL = 'https://api.github.com/repos/murilobreve/mythos-client/git/ref/heads/main'
local COMMIT_BASE = 'https://raw.githubusercontent.com/murilobreve/mythos-client/%s/'
local filesBase -- base of the version being checked or downloaded

-- HTTP.getJSON with a deadline for the whole answer (the native timeout
-- covers only the connection); callback(nil, err) when it runs out
local function getJSONWithin(url, seconds, callback)
  local done, watchdog = false, nil
  local oldTimeout = HTTP.timeout
  HTTP.timeout = CHECK_TIMEOUT
  local operation = HTTP.getJSON(url, function(data, err)
    if done then
      return
    end
    done = true
    if watchdog then
      removeEvent(watchdog)
      watchdog = nil
    end
    callback(data, err)
  end)
  HTTP.timeout = oldTimeout
  if not done then
    watchdog = scheduleEvent(function()
      watchdog = nil
      if done then
        return
      end
      done = true
      if operation then
        HTTP.cancel(operation)
      end
      callback(nil, 'no answer in ' .. seconds .. 's')
    end, seconds * 1000)
  end
end

-- callback(base, sha): sha is nil when the files come from main/
local function resolveBase(callback)
  local custom = os.getenv and os.getenv('MYTHOS_UPDATE_URL') or nil
  if custom and custom ~= '' then
    return callback(baseUrl())
  end
  getJSONWithin(REF_URL, SMALL_DEADLINE, function(ref, err)
    local sha = not err and type(ref) == 'table' and type(ref.object) == 'table' and ref.object.sha
    if type(sha) == 'string' and sha:match('^%x+$') and #sha >= 40 then
      log('checking commit ' .. sha:sub(1, 7))
      callback(string.format(COMMIT_BASE, sha), sha)
    else
      log('commit unknown (' .. tostring(err) .. '), checking main')
      callback(baseUrl())
    end
  end)
end

local function checkInterval()
  local env = os.getenv and tonumber(os.getenv('MYTHOS_UPDATE_INTERVAL') or '') or nil
  return math.max(5, env or DEFAULT_INTERVAL)
end

local function readLocalInfo()
  if not g_resources.fileExistsInWorkDir(LOCAL_INFO) then
    return nil
  end
  local ok, data = pcall(function()
    return json.decode(g_resources.readFileContentsFromWorkDir(LOCAL_INFO))
  end)
  if not ok or type(data) ~= 'table' or not data.canal then
    return nil
  end
  data.versao = tonumber(data.versao) or 0
  return data
end

local function enterGame()
  return modules.client_entergame and modules.client_entergame.EnterGame or nil
end

-- ---------------------------------------------------------------- state

local STATUS_COLORS = {
  checking = '#6b6b6b',
  verifying = '#6b6b6b',
  uptodate = '#5fbf6a',
  available = '#e2a443',
  updating = '#9b7bff',
  error = '#c0574f',
}

local function renderStatus()
  local panel = rootWidget and rootWidget:recursiveGetChildById('updateStatus')
  if not panel then
    return
  end
  if status == 'off' or not localInfo then
    panel:setVisible(false)
    return
  end
  local text, action
  if status == 'checking' then
    text = txt('Procurando atualização...', 'Checking for updates...')
  elseif status == 'verifying' then
    text = txt('Conferindo os arquivos do client...', 'Checking the client files...')
  elseif status == 'uptodate' then
    text = txt('Client atualizado (versão %d)', 'Client up to date (version %d)', localInfo.versao)
    -- check again on demand; a new version found this way installs right
    -- away, and every file is read again and put back if it is broken
    action = { txt('Verificar', 'Check'), function() Updater.check(true, true) end }
  elseif status == 'available' then
    text = txt('Nova versão %d disponível', 'New version %d available', remoteVersion or 0)
    action = { txt('Atualizar agora', 'Update now'), function() Updater.update() end }
  elseif status == 'updating' then
    text = txt('Atualizando para a versão %d...', 'Updating to version %d...', remoteVersion or 0)
  else
    text = txt('Sem conexão com a atualização (versão %d)', 'Could not check for updates (version %d)', localInfo.versao)
    action = { txt('Tentar de novo', 'Try again'), function() Updater.check(false) end }
  end
  panel:setVisible(true)
  panel:getChildById('updateDot'):setBackgroundColor(STATUS_COLORS[status] or '#6b6b6b')
  panel:getChildById('updateText'):setText(text)
  local link = panel:getChildById('updateAction')
  link:setVisible(action ~= nil)
  if action then
    link:setText(action[1])
    link.onClick = action[2]
  end
end

-- safe start (init.lua): the last start crashed while loading the modules,
-- so only the client modules and this updater are loaded. A new version
-- installs by itself (and restarts); otherwise the player chooses.
local safeBox
local function showSafeBox()
  if not MYTHOS_SAFE_START or safeBox or status == 'updating' or status == 'checking' or status == 'verifying' then
    log('safe box skipped: ' .. tostring(status) .. ' ' .. tostring(MYTHOS_SAFE_START))
    return
  end
  log('safe start: showing the choice')
  local eg = enterGame()
  if eg then
    eg.hide()
  end
  local function tryAgain()
    g_app.restart()
  end
  local buttons = {
    { text = txt('Abrir o jogo mesmo assim', 'Open the game anyway'), callback = tryAgain },
  }
  -- with no version info (a client run from the source tree) there is
  -- nothing to look for: the box would close on a blank screen
  if localInfo then
    buttons[#buttons + 1] = { text = txt('Procurar de novo', 'Check again'), callback = function()
      safeBox:destroy()
      safeBox = nil
      Updater.check(true, true)
    end }
  end
  buttons[#buttons + 1] = { text = txt('Sair', 'Quit'), callback = function() g_app.exit() end }
  local checked = status == 'uptodate' and filesChecked
  safeBox = displayGeneralBox(txt('Mythos', 'Mythos'),
    txt('O Mythos fechou sozinho da última vez que abriu, por isso desta vez abriu só o atualizador.\n\n'
      .. (checked and 'Os arquivos do client foram conferidos e estão inteiros. ' or '')
      .. 'Ainda não há uma versão nova com a correção. Avise a equipe e tente de novo mais tarde.',
      'Mythos closed by itself the last time it opened, so this time it opened only the updater.\n\n'
      .. (checked and 'The client files were checked and are intact. ' or '')
      .. 'There is no new version with a fix yet. Tell the team and try again later.'),
    buttons, tryAgain, function() g_app.exit() end)
end

local function setStatus(newStatus)
  status = newStatus
  renderStatus()
  if MYTHOS_SAFE_START and (newStatus == 'uptodate' or newStatus == 'error' or newStatus == 'available') then
    showSafeBox()
  end
end

local function remindInGame()
  if not g_game.isOnline() or not remoteVersion or not localInfo or remoteVersion <= localInfo.versao then
    return
  end
  local now = os.time()
  if remindedAt[remoteVersion] and now - remindedAt[remoteVersion] < REMIND_EVERY then
    return
  end
  remindedAt[remoteVersion] = now
  local text = txt('Nova versão do Mythos (%d) disponível. Ela instala sozinha da próxima vez que você abrir o client.',
    'A new Mythos version (%d) is out. It installs by itself the next time you open the client.', remoteVersion)
  log('in-game notice for version ' .. remoteVersion)
  -- red text in the middle of the game screen, also kept in the Server Log
  if modules.game_textmessage and modules.game_textmessage.displayBroadcastMessage then
    modules.game_textmessage.displayBroadcastMessage(text)
  end
end

-- ---------------------------------------------------------------- download

local function closeBox()
  if box then
    box:destroy()
    box = nil
  end
end

-- a manifest path the updater may write or delete: inside the client folder
local function validPath(path)
  return type(path) == 'string' and path ~= '' and not path:find('\\', 1, true) and not path:find(':', 1, true)
    and path:sub(1, 1) ~= '/' and not ('/' .. path .. '/'):find('/%.%.?/')
end

-- files an older version shipped and this one no longer does
local function removeStale(manifest)
  if type(manifest.removed) ~= 'table' or not g_resources.removeFileInWorkDir then
    return
  end
  local removed = 0
  for _, path in ipairs(manifest.removed) do
    if validPath(path) and manifest.files[path] == nil and g_resources.fileExistsInWorkDir(path) then
      if g_resources.removeFileInWorkDir(path) then
        removed = removed + 1
      else
        log('could not remove ' .. path)
      end
    end
  end
  if removed > 0 then
    log(string.format('removed %d files the new version no longer has', removed))
  end
end

local function giveUp(message)
  closeBox()
  -- a cancelled update must not keep downloading in the background
  if currentOperation then
    HTTP.cancel(currentOperation)
    currentOperation = nil
  end
  if retryEvent then
    removeEvent(retryEvent)
    retryEvent = nil
  end
  for _, name in ipairs(downloads) do
    pcall(g_resources.deleteFile, '/downloads/' .. name)
  end
  downloads = {}
  setStatus(remoteVersion and remoteVersion > localInfo.versao and 'available' or 'error')
  local eg = enterGame()
  if eg and not g_game.isOnline() and not MYTHOS_SAFE_START then
    eg.show()
  end
  if message then
    log(message)
    if repairing then
      displayErrorBox(txt('Atualização', 'Update'),
        txt('Não foi possível baixar agora os arquivos do client que faltam ou estão com defeito. O client tenta de novo na próxima vez que abrir.',
          'The missing or damaged client files could not be downloaded right now. The client tries again next time it opens.'))
    else
      displayErrorBox(txt('Atualização', 'Update'),
        txt('Não foi possível baixar a nova versão agora. Você pode jogar normalmente; o client tenta de novo na próxima vez que abrir.',
          'The new version could not be downloaded right now. You can play as usual; the client tries again next time it opens.'))
    end
  end
end

local function setProgress(done, total, percent)
  if not box then
    return
  end
  percent = math.max(0, math.min(100, percent or 0))
  box.content:setText(txt('Baixando arquivo %d de %d (%d%%)', 'Downloading file %d of %d (%d%%)',
    math.min(done + 1, total), total, math.floor(percent)))
  local track = box.track
  track.fill:setWidth(math.floor((track:getWidth() - 4) * percent / 100))
end

-- the download window: logo, versions, a progress bar and Cancel
local function openBox(onCancel)
  if not pcall(g_ui.importStyle, '/client_updater/client_updater') then
    -- an old style set: fall back to the plain box
    box = displayCancelBox(txt('Atualização', 'Update'), '')
    box.track = { fill = { setWidth = function() end }, getWidth = function() return 0 end }
    connect(box, { onCancel = onCancel })
    return
  end
  box = g_ui.createWidget('UpdaterWindow', rootWidget)
  box:setText(txt('Atualização', 'Update'))
  if repairing then
    box.versions:setText(txt('Reparando os arquivos da versão %d', 'Repairing the files of version %d', localInfo.versao))
  else
    box.versions:setText(txt('Versão %d para %d', 'Version %d to %d', localInfo.versao, remoteVersion or 0))
  end
  box.cancelButton:setText(txt('Cancelar', 'Cancel'))
  box.cancelButton.onClick = function()
    local current = box
    box = nil
    onCancel()
    if current then
      current:destroy()
    end
  end
  box.onEscape = box.cancelButton.onClick
  box:show()
  box:raise()
  box:focus()
  -- nothing under it (the character list) can be clicked while it downloads
  box:lock()
end

local function install(changed, manifest)
  local staleRemoved = false
  for _, entry in ipairs(changed) do
    -- versao.json goes last, after the old files are gone
    if entry.path == LOCAL_INFO and not staleRemoved then
      removeStale(manifest)
      staleRemoved = true
    end
    if not g_resources.installDownloadedFileInWorkDir(entry.download, entry.path) then
      -- files already installed stay; the next start finishes the job
      return giveUp('could not install ' .. entry.path)
    end
  end
  if not staleRemoved then
    removeStale(manifest)
  end
  if repairing then
    log(string.format('repaired %d files of version %d', #changed, localInfo.versao))
    -- written only now, before the restart: a file that still differs after
    -- it must not restart the client again (REPAIR_COOLDOWN), while a
    -- download that failed is tried again on the next start, as the box says
    pcall(g_resources.writeFileContents, REPAIR_FILE, string.format('%d %d', localInfo.versao, os.time()))
  else
    log(string.format('updated to version %d (%d files)', manifest.versao, #changed))
  end
  -- never restart under a player in game: it waits for the logout
  if g_game.isOnline() or g_game.isLogging() then
    restartPending = true
    closeBox()
    log('installed while in game: restarting after the logout')
    if modules.game_textmessage and modules.game_textmessage.displayBroadcastMessage then
      modules.game_textmessage.displayBroadcastMessage(txt('Nova versão do Mythos instalada. O client reinicia quando você sair do jogo.',
        'A new Mythos version is installed. The client restarts when you leave the game.'))
    end
    return
  end
  if box then
    if repairing then
      box.content:setText(txt('Arquivos reparados. Reiniciando...', 'Files repaired. Restarting...'))
    else
      box.content:setText(txt('Mythos atualizado. Reiniciando...', 'Mythos updated. Restarting...'))
    end
    box.track.fill:setWidth(box.track:getWidth() - 4)
    if box.cancelButton then
      box.cancelButton:setEnabled(false)
    end
  end
  scheduleEvent(function() g_app.restart() end, 1200)
end

-- a download that stops receiving data never ends by itself (the timeout
-- only covers the connection), so each file has a watchdog: no progress for
-- STALL_SECONDS and it is cancelled and tried again, up to FILE_TRIES times.
-- Each new try waits longer (RETRY_WAIT): on launch day many players behind
-- one address (CGNAT) hit GitHub's limit together, and three tries in the
-- same second all failed. "Too many requests" (429) and GitHub's own
-- failures (5xx) get more tries (BUSY_WAIT).
local STALL_SECONDS = 20
local RETRY_WAIT = { 5, 15, 45 }       -- seconds before the 2nd, 3rd and 4th try
local FILE_TRIES = #RETRY_WAIT + 1
local BUSY_WAIT = { 5, 15, 45, 90, 90 }
local BUSY_TRIES = #BUSY_WAIT + 1

local function serverBusy(reason)
  local code = tonumber(tostring(reason):match('http_status::(%d+)'))
  return code ~= nil and (code == 429 or code >= 500)
end

local function downloadAll(changed, manifest, myGeneration)
  local base = filesBase or baseUrl()
  local total = #changed
  local index = 0
  local nextFile

  local function fetch(entry, attempt)
    local operation, watchdog
    local finished = false
    local lastProgress = -1
    local function stopWatchdog()
      if watchdog then
        removeEvent(watchdog)
        watchdog = nil
      end
    end
    local function retry(reason)
      if finished or myGeneration ~= generation then
        return
      end
      finished = true
      stopWatchdog()
      local busy = serverBusy(reason)
      local tries = busy and BUSY_TRIES or FILE_TRIES
      if attempt >= tries then
        return giveUp('download failed for ' .. entry.path .. ': ' .. reason)
      end
      local wait = (busy and BUSY_WAIT or RETRY_WAIT)[attempt] or RETRY_WAIT[#RETRY_WAIT]
      log(string.format('%s: %s, trying again in %ds (%d/%d)', entry.path, reason, wait, attempt + 1, tries))
      if box then
        -- short: the label is 348 px and does not wrap (305 px at 3311 files)
        box.content:setText(txt('Arquivo %d de %d: nova tentativa em %d s (%d/%d)',
          'File %d of %d: trying again in %d s (%d/%d)', index, total, wait, attempt + 1, tries))
      end
      retryEvent = scheduleEvent(function()
        retryEvent = nil
        if myGeneration == generation then
          fetch(entry, attempt + 1)
        end
      end, wait * 1000)
    end
    local function arm()
      stopWatchdog()
      watchdog = scheduleEvent(function()
        watchdog = nil
        if operation then
          HTTP.cancel(operation)
        end
        retry('no data for ' .. STALL_SECONDS .. 's')
      end, STALL_SECONDS * 1000)
    end

    -- a fresh file name per try: a cancelled download may still write its own
    entry.download = string.format('mythos_update_%d_%d_%d', manifest.versao, index, attempt)
    table.insert(downloads, entry.download)
    -- the last tries go through main/, in case the commit address misbehaves
    local from = (attempt >= FILE_TRIES) and baseUrl() or base
    local oldTimeout = HTTP.timeout
    HTTP.timeout = DOWNLOAD_TIMEOUT
    arm()
    operation = HTTP.download(from .. 'objects/' .. entry.sha256, entry.download, function(path, checksum, err)
      if currentOperation == operation then
        currentOperation = nil
      end
      if finished or myGeneration ~= generation then
        return
      end
      if err then
        return retry(tostring(err))
      end
      local ok, contents = pcall(g_resources.readFileContents, '/downloads/' .. entry.download)
      if not ok or g_crypt.sha256(contents) ~= entry.sha256 then
        return retry('wrong contents')
      end
      finished = true
      stopWatchdog()
      nextFile()
    end, function(progress, speed)
      if finished or myGeneration ~= generation then
        return
      end
      -- the progress event also repeats while nothing arrives: only real
      -- progress keeps the watchdog quiet. The percentage is a whole number
      -- (1% of a big file takes a while on a slow line) and stays 0 when the
      -- size is unknown, so bytes arriving (speed) count too
      progress = tonumber(progress) or 0
      if progress > lastProgress or (tonumber(speed) or 0) > 0 then
        lastProgress = math.max(progress, lastProgress)
        arm()
      end
      setProgress(index - 1, total, ((index - 1) + progress / 100) * 100 / total)
    end)
    currentOperation = operation
    HTTP.timeout = oldTimeout
  end

  nextFile = function()
    if myGeneration ~= generation then
      return
    end
    index = index + 1
    if index > total then
      return install(changed, manifest)
    end
    local entry = changed[index]
    setProgress(index - 1, total, (index - 1) * 100 / total)
    fetch(entry, 1)
  end

  nextFile()
end

-- one bad path and the whole manifest is refused, before any download
local function manifestPathsValid(manifest)
  for path in pairs(manifest.files) do
    if not validPath(path) then
      log('manifest refused: bad path ' .. tostring(path))
      return false
    end
  end
  return true
end

-- changed: the files to download, already found by verifyFiles (a repair of
-- this same version); otherwise every file is compared with the manifest
local function startUpdate(manifest, changed)
  if not manifestPathsValid(manifest) then
    setStatus('error')
    return
  end
  if type(manifest.removed) == 'string' then
    manifest.removed = { manifest.removed }
  end

  repairing = changed ~= nil
  if not changed then
    changed = {}
    for path, info in pairs(manifest.files) do
      local sha = type(info) == 'table' and info.sha256 or info
      if type(sha) == 'string' and g_resources.fileSha256InWorkDir(path) ~= sha then
        table.insert(changed, { path = path, sha256 = sha })
      end
    end
  end
  -- versao.json last: if anything fails before it, the next start sees the
  -- old version number and tries again
  table.sort(changed, function(a, b)
    if (a.path == LOCAL_INFO) ~= (b.path == LOCAL_INFO) then
      return b.path == LOCAL_INFO
    end
    return a.path < b.path
  end)
  if repairing then
    log(string.format('version %d: %d files missing or broken, downloading them again', localInfo.versao, #changed))
  else
    log(string.format('version %d -> %d, %d files to download', localInfo.versao, manifest.versao, #changed))
  end
  if #changed == 0 then
    setStatus('uptodate')
    return
  end

  generation = generation + 1
  local myGeneration = generation
  downloads = {}
  setStatus('updating')
  local eg = enterGame()
  if eg then
    eg.hide()
  end
  if CharacterList and CharacterList.isVisible and CharacterList.isVisible() then
    CharacterList.hide()
  end
  openBox(function()
    generation = generation + 1
    box = nil
    giveUp()
  end)
  setProgress(0, #changed, 0)
  downloadAll(changed, manifest, myGeneration)
end

-- ---------------------------------------------------------------- repair

-- path -> { stamp, sha256 } of the files found intact the last time
local function loadStamps()
  local stamps = {}
  local ok, text = pcall(g_resources.readFileContents, STAMPS_FILE)
  if ok and type(text) == 'string' then
    for path, stamp, sha in text:gmatch('([^\t\n]+)\t([^\t\n]+)\t(%x+)\n') do
      stamps[path] = { stamp = stamp, sha256 = sha }
    end
  end
  return stamps
end

local function saveStamps(stamps)
  local lines = {}
  for path, entry in pairs(stamps) do
    lines[#lines + 1] = path .. '\t' .. entry.stamp .. '\t' .. entry.sha256 .. '\n'
  end
  table.sort(lines)
  pcall(g_resources.writeFileContents, STAMPS_FILE, table.concat(lines))
end

-- the manifest's files that are missing or differ from it, checked a slice
-- per frame (hashing every file takes a few seconds on a slow disk), then
-- done(changed). full: every file is read again (the player asked, or the
-- safe start); otherwise only a file whose stamp changed since it was last
-- found intact. Stops (done(nil)) when the player enters the game meanwhile.
local function verifyFiles(manifest, full, myGeneration, done)
  local stampOf = g_resources.fileStampInWorkDir -- nil in an older .exe
  local paths = {}
  for path in pairs(manifest.files) do
    if path ~= LOCAL_INFO then
      paths[#paths + 1] = path
    end
  end
  table.sort(paths)
  local known = loadStamps()
  local stamps, dirty = {}, false
  local changed = {}
  local index = 0

  local function finish(result)
    if not result then
      -- stopped by the game: the files not reached yet keep their stamps
      for i = index + 1, #paths do
        stamps[paths[i]] = stamps[paths[i]] or known[paths[i]]
      end
    end
    -- what is not in this manifest any more goes from the file too
    for path in pairs(known) do
      if not stamps[path] then
        dirty = true
        break
      end
    end
    if dirty and stampOf then
      saveStamps(stamps)
    end
    done(result)
  end

  local function step()
    if myGeneration ~= generation then
      return
    end
    if g_game.isOnline() or g_game.isLogging() then
      return finish(nil)
    end
    local started = g_clock.millis()
    while index < #paths do
      index = index + 1
      local path = paths[index]
      local info = manifest.files[path]
      local sha = type(info) == 'table' and info.sha256 or info
      local size = type(info) == 'table' and tonumber(info.size) or nil
      if type(sha) == 'string' then
        local stamp
        if stampOf then
          stamp = stampOf(path)
        else
          stamp = g_resources.fileExistsInWorkDir(path) and '?' or ''
        end
        local fileSize = tonumber(stamp:match('^(%d+):') or '')
        if stamp == '' then
          table.insert(changed, { path = path, sha256 = sha })
        elseif USER_FILES[path] then
          -- left as the player has it
        elseif size and fileSize and size ~= fileSize then
          table.insert(changed, { path = path, sha256 = sha })
        elseif stampOf or full then
          local last = known[path]
          if not full and last and last.stamp == stamp and last.sha256 == sha then
            stamps[path] = last
          elseif g_resources.fileSha256InWorkDir(path) == sha then
            stamps[path] = { stamp = stamp, sha256 = sha }
            dirty = true
          else
            table.insert(changed, { path = path, sha256 = sha })
          end
        end
      end
      if g_clock.millis() - started >= VERIFY_SLICE_MS then
        scheduleEvent(step, 1)
        return
      end
    end
    finish(changed)
  end

  step()
end

-- the version is up to date: put back what is missing or broken. asked:
-- the player clicked for it (no cooldown)
local function repair(manifest, full, asked)
  -- only against the manifest of this same version: an older one (a stale
  -- main/ cache, a test build made with -SemEnviar) would put the previous
  -- version's files over the newer ones
  if (tonumber(manifest.versao) or 0) ~= localInfo.versao then
    setStatus('uptodate')
    return
  end
  if not manifestPathsValid(manifest) then
    setStatus('error')
    return
  end
  local myGeneration = generation
  local started = g_clock.millis()
  filesChecked = false
  setStatus('verifying')
  verifyFiles(manifest, full, myGeneration, function(changed)
    if myGeneration ~= generation then
      return
    end
    if not changed then
      log('file check stopped: the game started')
      setStatus('uptodate')
      return
    end
    log(string.format('file check (%s): %d to repair, %d ms', full and 'full' or 'quick', #changed, g_clock.millis() - started))
    filesChecked = #changed == 0
    if #changed == 0 or g_game.isOnline() or g_game.isLogging() then
      setStatus('uptodate')
      return
    end
    if not asked then
      local ok, text = pcall(g_resources.readFileContents, REPAIR_FILE)
      local version, at = tostring(ok and text or ''):match('^(%d+) (%d+)')
      if tonumber(version) == localInfo.versao and os.time() - (tonumber(at) or 0) < REPAIR_COOLDOWN then
        log('repaired by itself less than an hour ago: not again until "Verificar"')
        setStatus('uptodate')
        return
      end
    end
    startUpdate(manifest, changed)
  end)
end

-- ---------------------------------------------------------------- checks

-- a manifest read now, or the one already read from this same commit
local function onManifest(manifest, base, autoInstall, verifyAll)
  failedChecks = 0
  lastManifest = manifest
  filesBase = base
  remoteVersion = tonumber(manifest.versao) or 0
  if remoteVersion < localInfo.versao then
    log(string.format('manifest %d older than this client %d (stale cache or a test build): files not checked',
      remoteVersion, localInfo.versao))
    setStatus('uptodate')
    return
  end
  if remoteVersion == localInfo.versao then
    log(string.format('up to date (version %d)', localInfo.versao))
    if autoInstall and not g_game.isOnline() and not g_game.isLogging() then
      return repair(manifest, verifyAll or MYTHOS_SAFE_START, verifyAll)
    end
    setStatus('uptodate')
    return
  end
  -- in game, or entering it: only report it. At the character list (an
  -- autologin is faster than this check) the update goes ahead, and the
  -- locked update window keeps the player from entering meanwhile
  if autoInstall and not g_game.isOnline() and not g_game.isLogging() then
    return startUpdate(manifest)
  end
  log(string.format('version %d is out (running %d)', remoteVersion, localInfo.versao))
  setStatus('available')
  remindInGame()
end

local function checkFailed(err, autoInstall)
  log('no update information: ' .. tostring(err))
  setStatus(remoteVersion and remoteVersion > localInfo.versao and 'available' or 'error')
  failedChecks = failedChecks + 1
  local wait = CHECK_RETRY_WAIT[failedChecks]
  if wait and not retryCheckEvent then
    log(string.format('checking again in %ds', wait))
    retryCheckEvent = scheduleEvent(function()
      retryCheckEvent = nil
      Updater.check(autoInstall)
    end, wait * 1000)
  end
end

-- the commit, then its file list (not again when the commit did not change)
local function fullCheck(autoInstall, verifyAll)
  resolveBase(function(base, sha)
    -- a check that was already on its way when an update started
    if status == 'updating' or status == 'verifying' then
      return
    end
    if sha and sha == lastSha and lastManifest then
      log('same commit as the last check: file list not downloaded again')
      return onManifest(lastManifest, base, autoInstall, verifyAll)
    end
    local url = base .. localInfo.canal .. '/manifest.json?t=' .. os.time()
    getJSONWithin(url, MANIFEST_DEADLINE, function(manifest, err)
      if status == 'updating' or status == 'verifying' then
        return
      end
      if err or type(manifest) ~= 'table' or type(manifest.files) ~= 'table' then
        return checkFailed(err, autoInstall)
      end
      lastSha = sha
      onManifest(manifest, base, autoInstall, verifyAll)
    end)
  end)
end

-- autoInstall: download right away (client start, "Update now"); otherwise
-- only report the new version (the periodic check while the client is open).
-- With autoInstall and the version up to date, the files are checked too:
-- verifyAll reads every one of them again (the player asked).
function Updater.check(autoInstall, verifyAll)
  if not localInfo or status == 'updating' or status == 'verifying' then
    return
  end
  if retryCheckEvent then
    removeEvent(retryCheckEvent)
    retryCheckEvent = nil
  end
  -- the periodic check, once a file list was read: only the published
  -- number (<channel>/versao.json, from tools/publicar-atualizacao.ps1).
  -- main/ may be 5 minutes old, which is fine for a version that installs
  -- on the next start; a higher number, or none (an older publication),
  -- checks the commit and the file list as the start does
  if not autoInstall and lastManifest and (status == 'uptodate' or status == 'available') then
    local known = math.max(localInfo.versao, remoteVersion or 0)
    getJSONWithin(baseUrl() .. localInfo.canal .. '/versao.json?t=' .. os.time(), SMALL_DEADLINE, function(info, err)
      if status == 'updating' or status == 'verifying' then
        return
      end
      local number = not err and type(info) == 'table' and tonumber(info.versao) or nil
      if number and number <= known then
        if remoteVersion and remoteVersion > localInfo.versao then
          remindInGame()
        end
        return
      end
      if number then
        log(string.format('version %d published (running %d)', number, localInfo.versao))
      else
        log('published number unknown (' .. tostring(err) .. '), checking the commit')
      end
      fullCheck(false)
    end)
    return
  end
  if status ~= 'available' then
    setStatus('checking')
  end
  fullCheck(autoInstall, verifyAll)
end

local function onGameEnd()
  if restartPending then
    log('restarting for the version installed during the game')
    scheduleEvent(function() g_app.restart() end, 500)
    return
  end
  renderStatus()
end

-- "Update now" on the login screen
function Updater.isUpdating()
  return status == 'updating'
end

function Updater.update()
  if g_game.isOnline() or g_game.isLogging() then
    return
  end
  if lastManifest and (tonumber(lastManifest.versao) or 0) > localInfo.versao then
    return startUpdate(lastManifest)
  end
  Updater.check(true)
end

local function showVersion()
  -- small "v12" in the corner of the login screen: players and bug reports
  -- say which build they run (the game window covers it once in game)
  versionLabel = g_ui.createWidget('UILabel', rootWidget)
  versionLabel:setText('v' .. localInfo.versao)
  versionLabel:setColor('#8a80b0')
  versionLabel:setPhantom(true)
  versionLabel:resizeToText()
  versionLabel:addAnchor(AnchorRight, 'parent', AnchorRight)
  versionLabel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  versionLabel:setMarginRight(8)
  versionLabel:setMarginBottom(4)
end

-- the build this client runs, for the server (REPORT_OPCODE): the staff
-- see who is behind, and a build below the server's minimum is told to
-- update. Also from the browser and a client without versao.json (versao
-- 0). A few seconds after entering, once the server's first packets are in.
local reportEvent
local function reportVersion()
  if reportEvent then
    removeEvent(reportEvent)
  end
  reportEvent = scheduleEvent(function()
    reportEvent = nil
    local protocol = g_game.isOnline() and g_game.getProtocolGame() or nil
    if not protocol or not protocol.sendExtendedJSONOpcode then
      return
    end
    local canal = localInfo and localInfo.canal or ''
    if canal == '' and g_platform.isBrowser and g_platform.isBrowser() then
      canal = 'browser'
    end
    local commit = g_app.getBuildCommit and g_app.getBuildCommit() or ''
    pcall(protocol.sendExtendedJSONOpcode, protocol, REPORT_OPCODE, {
      action = 'version',
      canal = canal,
      versao = localInfo and localInfo.versao or 0,
      commit = tostring(commit):sub(1, 12),
      status = status,
      remote = remoteVersion,
    })
  end, 3000)
end

local function onGameStart()
  remindInGame()
  reportVersion()
end

function Updater.init()
  connect(g_game, { onGameStart = onGameStart })
  localInfo = readLocalInfo()
  if not localInfo then
    -- a client run from the source tree has no updater: just offer the choice
    if MYTHOS_SAFE_START then
      status = 'error'
      scheduleEvent(showSafeBox, 100)
    end
    return
  end
  if MYTHOS_SAFE_START then
    log('safe start: looking for a version that fixes the crash')
    local eg = enterGame()
    if eg then
      eg.hide()
    end
  end
  -- the leftovers (*.old, *.part) of the last update; only in a client the
  -- updater manages: the walk deletes those names in every folder below
  pcall(g_resources.cleanupOldFilesInWorkDir)
  showVersion()
  Updater.check(true)
  checkEvent = cycleEvent(function() Updater.check(false) end, checkInterval() * 1000)
  -- the login screen comes back after a logout: show the latest state there
  connect(g_game, { onGameEnd = onGameEnd })
end

function Updater.terminate()
  generation = generation + 1
  closeBox()
  if checkEvent then
    removeEvent(checkEvent)
    checkEvent = nil
  end
  removeEvent(retryCheckEvent)
  removeEvent(retryEvent)
  removeEvent(reportEvent)
  retryCheckEvent, retryEvent, reportEvent = nil, nil, nil
  disconnect(g_game, { onGameEnd = onGameEnd, onGameStart = onGameStart })
  if versionLabel then
    versionLabel:destroy()
    versionLabel = nil
  end
end

function Updater.getVersion()
  return localInfo and localInfo.versao or nil
end

function Updater.getStatus()
  return status, remoteVersion
end
