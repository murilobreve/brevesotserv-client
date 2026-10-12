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
-- While the client is open it checks again every few minutes. The login
-- screen shows the state (up to date / new version / updating) and a player
-- in game gets a message when a new version comes out; it installs the next
-- time the client opens, or from the login screen's "Update now".

Updater = {}

local DEFAULT_BASE = 'https://raw.githubusercontent.com/murilobreve/mythos-client/main/'
local LOCAL_INFO = 'versao.json'
local CHECK_TIMEOUT = 8
local DOWNLOAD_TIMEOUT = 20            -- seconds to connect for each file (2 by default)
local DEFAULT_INTERVAL = 10 * 60      -- seconds between checks while open
local REMIND_EVERY = 30 * 60          -- seconds between in-game reminders

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

local function resolveBase(callback)
  local custom = os.getenv and os.getenv('MYTHOS_UPDATE_URL') or nil
  if custom and custom ~= '' then
    return callback(baseUrl())
  end
  HTTP.getJSON(REF_URL, function(ref, err)
    local sha = not err and type(ref) == 'table' and type(ref.object) == 'table' and ref.object.sha
    if type(sha) == 'string' and sha:match('^%x+$') and #sha >= 40 then
      log('checking commit ' .. sha:sub(1, 7))
      callback(string.format(COMMIT_BASE, sha))
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
  elseif status == 'uptodate' then
    text = txt('Client atualizado (versão %d)', 'Client up to date (version %d)', localInfo.versao)
    -- check again on demand; a new version found this way installs right away
    action = { txt('Verificar', 'Check'), function() Updater.check(true) end }
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

local function setStatus(newStatus)
  status = newStatus
  renderStatus()
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
  for _, name in ipairs(downloads) do
    pcall(g_resources.deleteFile, '/downloads/' .. name)
  end
  downloads = {}
  setStatus(remoteVersion and remoteVersion > localInfo.versao and 'available' or 'error')
  local eg = enterGame()
  if eg and not g_game.isOnline() then
    eg.show()
  end
  if message then
    log(message)
    displayErrorBox(txt('Atualização', 'Update'),
      txt('Não foi possível baixar a nova versão agora. Você pode jogar normalmente; o client tenta de novo na próxima vez que abrir.',
        'The new version could not be downloaded right now. You can play as usual; the client tries again next time it opens.'))
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
  box.versions:setText(txt('Versão %d para %d', 'Version %d to %d', localInfo.versao, remoteVersion or 0))
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
  log(string.format('updated to version %d (%d files)', manifest.versao, #changed))
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
    box.content:setText(txt('Mythos atualizado. Reiniciando...', 'Mythos updated. Restarting...'))
    box.track.fill:setWidth(box.track:getWidth() - 4)
    if box.cancelButton then
      box.cancelButton:setEnabled(false)
    end
  end
  scheduleEvent(function() g_app.restart() end, 1200)
end

-- a download that stops receiving data never ends by itself (the timeout
-- only covers the connection), so each file has a watchdog: no progress for
-- STALL_SECONDS and it is cancelled and tried again, up to FILE_TRIES times
local STALL_SECONDS = 20
local FILE_TRIES = 3

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
      if attempt >= FILE_TRIES then
        return giveUp('download failed for ' .. entry.path .. ': ' .. reason)
      end
      log(string.format('%s: %s, trying again (%d/%d)', entry.path, reason, attempt + 1, FILE_TRIES))
      fetch(entry, attempt + 1)
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
    -- the last try goes through main/, in case the commit address misbehaves
    local from = (attempt == FILE_TRIES) and baseUrl() or base
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

local function startUpdate(manifest)
  -- one bad path and the whole manifest is refused, before any download
  for path in pairs(manifest.files) do
    if not validPath(path) then
      log('manifest refused: bad path ' .. tostring(path))
      setStatus('error')
      return
    end
  end
  if type(manifest.removed) == 'string' then
    manifest.removed = { manifest.removed }
  end

  local changed = {}
  for path, info in pairs(manifest.files) do
    local sha = type(info) == 'table' and info.sha256 or info
    if type(sha) == 'string' and g_resources.fileSha256InWorkDir(path) ~= sha then
      table.insert(changed, { path = path, sha256 = sha })
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
  log(string.format('version %d -> %d, %d files to download', localInfo.versao, manifest.versao, #changed))
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

-- ---------------------------------------------------------------- checks

-- autoInstall: download right away (client start, "Update now"); otherwise
-- only report the new version (the periodic check while the client is open)
function Updater.check(autoInstall)
  if not localInfo or status == 'updating' then
    return
  end
  if status ~= 'available' then
    setStatus('checking')
  end
  local oldTimeout = HTTP.timeout
  HTTP.timeout = CHECK_TIMEOUT
  resolveBase(function(base)
  local url = base .. localInfo.canal .. '/manifest.json?t=' .. os.time()
  local outerTimeout = HTTP.timeout
  HTTP.timeout = CHECK_TIMEOUT
  HTTP.getJSON(url, function(manifest, err)
    -- a check that was already on its way when an update started
    if status == 'updating' then
      return
    end
    if err or type(manifest) ~= 'table' or type(manifest.files) ~= 'table' then
      log('no update information: ' .. tostring(err))
      setStatus(remoteVersion and remoteVersion > localInfo.versao and 'available' or 'error')
      return
    end
    lastManifest = manifest
    filesBase = base
    remoteVersion = tonumber(manifest.versao) or 0
    if remoteVersion <= localInfo.versao then
      log(string.format('up to date (version %d)', localInfo.versao))
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
  end)
  HTTP.timeout = outerTimeout
  end)
  HTTP.timeout = oldTimeout
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

function Updater.init()
  pcall(g_resources.cleanupOldFilesInWorkDir)
  localInfo = readLocalInfo()
  if not localInfo then
    return
  end
  showVersion()
  Updater.check(true)
  checkEvent = cycleEvent(function() Updater.check(false) end, checkInterval() * 1000)
  -- the login screen comes back after a logout: show the latest state there
  connect(g_game, { onGameEnd = onGameEnd, onGameStart = remindInGame })
end

function Updater.terminate()
  generation = generation + 1
  closeBox()
  if checkEvent then
    removeEvent(checkEvent)
    checkEvent = nil
  end
  disconnect(g_game, { onGameEnd = onGameEnd, onGameStart = remindInGame })
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
