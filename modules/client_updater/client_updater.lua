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
local DEFAULT_INTERVAL = 10 * 60      -- seconds between checks while open
local REMIND_EVERY = 30 * 60          -- seconds between in-game reminders

local box
local downloads = {}
local cancelled = false
local localInfo
local versionLabel
local checkEvent
local status = 'off'                  -- off checking uptodate available updating error
local remoteVersion
local lastManifest
local remindedAt = {}                 -- version -> os.time() of the last in-game notice

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
  available = '#e0b04a',
  updating = '#8b6bff',
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

local function giveUp(message)
  closeBox()
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
  box.content:setText(txt('Baixando a nova versão do Mythos', 'Downloading the new Mythos version') ..
    string.format('\n%d / %d  (%d%%)', done, total, math.floor(percent or 0)))
end

local function install(changed, manifest)
  for _, entry in ipairs(changed) do
    if not g_resources.installDownloadedFileInWorkDir(entry.download, entry.path) then
      -- files already installed stay; the next start finishes the job
      return giveUp('could not install ' .. entry.path)
    end
  end
  log(string.format('updated to version %d (%d files)', manifest.versao, #changed))
  if box then
    box.content:setText(txt('Mythos atualizado! Reiniciando...', 'Mythos updated! Restarting...'))
  end
  scheduleEvent(function() g_app.restart() end, 1200)
end

local function downloadAll(changed, manifest)
  local base = baseUrl()
  local total = #changed
  local index = 0

  local function nextFile()
    if cancelled then
      return
    end
    index = index + 1
    if index > total then
      return install(changed, manifest)
    end
    local entry = changed[index]
    entry.download = string.format('mythos_update_%d_%d', manifest.versao, index)
    table.insert(downloads, entry.download)
    setProgress(index - 1, total, (index - 1) * 100 / total)
    HTTP.download(base .. 'objects/' .. entry.sha256, entry.download, function(path, checksum, err)
      if cancelled then
        return
      end
      if err then
        return giveUp('download failed for ' .. entry.path .. ': ' .. tostring(err))
      end
      local ok, contents = pcall(g_resources.readFileContents, '/downloads/' .. entry.download)
      if not ok or g_crypt.sha256(contents) ~= entry.sha256 then
        return giveUp('wrong contents for ' .. entry.path)
      end
      nextFile()
    end, function(progress)
      setProgress(index - 1, total, ((index - 1) + (progress or 0) / 100) * 100 / total)
    end)
  end

  nextFile()
end

local function startUpdate(manifest)
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

  cancelled = false
  downloads = {}
  setStatus('updating')
  local eg = enterGame()
  if eg then
    eg.hide()
  end
  box = displayCancelBox(txt('Atualização', 'Update'), '')
  setProgress(0, #changed, 0)
  connect(box, { onCancel = function()
    cancelled = true
    box = nil
    giveUp()
  end })
  downloadAll(changed, manifest)
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
  local url = baseUrl() .. localInfo.canal .. '/manifest.json?t=' .. os.time()
  local oldTimeout = HTTP.timeout
  HTTP.timeout = CHECK_TIMEOUT
  HTTP.getJSON(url, function(manifest, err)
    if err or type(manifest) ~= 'table' or type(manifest.files) ~= 'table' then
      log('no update information: ' .. tostring(err))
      setStatus(remoteVersion and remoteVersion > localInfo.versao and 'available' or 'error')
      return
    end
    lastManifest = manifest
    remoteVersion = tonumber(manifest.versao) or 0
    if remoteVersion <= localInfo.versao then
      log(string.format('up to date (version %d)', localInfo.versao))
      setStatus('uptodate')
      return
    end
    if autoInstall and not g_game.isOnline() then
      return startUpdate(manifest)
    end
    log(string.format('version %d is out (running %d)', remoteVersion, localInfo.versao))
    setStatus('available')
    remindInGame()
  end)
  HTTP.timeout = oldTimeout
end

-- "Update now" on the login screen
function Updater.update()
  if g_game.isOnline() then
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
  connect(g_game, { onGameEnd = renderStatus, onGameStart = remindInGame })
end

function Updater.terminate()
  cancelled = true
  closeBox()
  if checkEvent then
    removeEvent(checkEvent)
    checkEvent = nil
  end
  disconnect(g_game, { onGameEnd = renderStatus, onGameStart = remindInGame })
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
