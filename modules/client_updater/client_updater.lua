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

Updater = {}

local DEFAULT_BASE = 'https://raw.githubusercontent.com/murilobreve/mythos-client/main/'
local LOCAL_INFO = 'versao.json'
local CHECK_TIMEOUT = 8

local box
local downloads = {}
local cancelled = false
local localInfo

local function pt()
  return (g_settings.get('locale') or 'pt') == 'pt'
end

local function txt(ptText, enText)
  return pt() and ptText or enText
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
  local eg = enterGame()
  if eg then
    eg.show()
  end
  if message then
    log(message)
    displayErrorBox(txt('Atualização', 'Update'),
      txt('Não foi possível baixar a nova versão agora. Você pode jogar normalmente; o client tenta de novo na próxima vez que abrir.',
        'The new version could not be downloaded right now. You can play as usual; the client tries again next time it opens.'))
  end
end

local function setStatus(done, total, percent)
  if not box then
    return
  end
  local text = txt('Baixando a nova versão do Mythos', 'Downloading the new Mythos version') ..
    string.format('\n%d / %d  (%d%%)', done, total, math.floor(percent or 0))
  box.content:setText(text)
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
    setStatus(index - 1, total, (index - 1) * 100 / total)
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
      setStatus(index - 1, total, ((index - 1) + (progress or 0) / 100) * 100 / total)
    end)
  end

  nextFile()
end

local function onManifest(manifest, err)
  if err or type(manifest) ~= 'table' or type(manifest.files) ~= 'table' then
    log('no update information: ' .. tostring(err))
    return
  end
  local remote = tonumber(manifest.versao) or 0
  if remote <= localInfo.versao then
    log(string.format('up to date (version %d)', localInfo.versao))
    return
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
  log(string.format('version %d -> %d, %d files to download', localInfo.versao, remote, #changed))
  if #changed == 0 then
    return
  end

  local eg = enterGame()
  if eg then
    eg.hide()
  end
  box = displayCancelBox(txt('Atualização', 'Update'), '')
  setStatus(0, #changed, 0)
  connect(box, { onCancel = function()
    cancelled = true
    box = nil
    giveUp()
  end })
  downloadAll(changed, manifest)
end

local versionLabel

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
  local url = baseUrl() .. localInfo.canal .. '/manifest.json?t=' .. os.time()
  local oldTimeout = HTTP.timeout
  HTTP.timeout = CHECK_TIMEOUT
  HTTP.getJSON(url, onManifest)
  HTTP.timeout = oldTimeout
end

function Updater.terminate()
  cancelled = true
  closeBox()
  if versionLabel then
    versionLabel:destroy()
    versionLabel = nil
  end
end

function Updater.getVersion()
  return localInfo and localInfo.versao or nil
end
