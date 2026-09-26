-- this is the first file executed when the application starts
-- we have to load the first modules form here

-- =====================================================================
-- CONFIGURACAO DO SERVIDOR (edite apenas este bloco para trocar o IP)
-- =====================================================================
local SERVER_HOST     = "http://25.18.172.192/login.php" -- URL do login.php
local SERVER_PORT     = 80                                -- porta HTTP do login
local CLIENT_VERSION  = 1525                              -- versao do client (15.25)
-- =====================================================================

Services = {
    status = SERVER_HOST, --./client_entergame | ./client_topmenu
    --websites = "http://SEU-SITE/?subtopic=accountmanagement", --./client_entergame "Forgot password and/or email"
    --getCoinsUrl = "http://SEU-SITE/?subtopic=shop&step=terms", --./game_market
    clientAssets = {
        enabled = true,
        repository = "dudantas/tibia-client",
        installSounds = true,
        strictManifestSha256 = true,
        allowRawFallbackHashMismatch = false,
        allowMissingPackedRawFallback = true,
        preferArchive = true,
        fallbackToArchiveOnManifestFailure = false,
        installArchiveExtras = true,
        archiveExtraPrefixes = { "bin" },
        installPackagedFiles = true
    }, -- ./client_assets
}

-- Um unico servidor: a tela de login ja abre apontando para ele
-- (campos de IP/porta/versao ficam ocultos).
Servers_init = {
    [SERVER_HOST] = {
        port = SERVER_PORT,
        protocol = CLIENT_VERSION,
        httpLogin = true,
        useAuthenticator = false
    }
}

g_app.setName("OTClient - Redemption");
g_app.setCompactName("otclient");
g_app.setOrganizationName("otcr");

g_app.hasUpdater = function()
    return false
end

-- setup logger
g_logger.setLogFile(g_resources.getWorkDir() .. g_app.getCompactName() .. '.log')
g_logger.info("Operating system: " .. g_platform.getOSName())

-- print first terminal message
g_logger.info(g_app.getName() .. ' ' .. g_app.getVersion() .. ' rev ' .. g_app.getBuildRevision() .. ' (' ..
    g_app.getBuildCommit() .. ') built on ' .. g_app.getBuildDate() .. ' for arch ' ..
    g_app.getBuildArch())

-- setup lua debugger
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    require("lldebugger").start()
    g_logger.debug("Started LUA debugger.")
else
    g_logger.debug("LUA debugger not started (not launched with VSCode local-lua).")
end

-- add data directory to the search path
if not g_resources.addSearchPath(g_resources.getWorkDir() .. 'data', true) then
    g_logger.fatal('Unable to add data directory to the search path.')
end

-- add modules directory to the search path
if not g_resources.addSearchPath(g_resources.getWorkDir() .. 'modules', true) then
    g_logger.fatal('Unable to add modules directory to the search path.')
end

g_html.addGlobalStyle('/data/styles/html.css')
g_html.addGlobalStyle('/data/styles/custom.css')

-- try to add mods path too
g_resources.addSearchPath(g_resources.getWorkDir() .. 'mods', true)

-- setup directory for saving configurations
g_resources.setupUserWriteDir(('%s/'):format(g_app.getCompactName()))

-- search all packages
g_resources.searchAndAddPackages('/', '.otpkg', true)

-- load settings
g_configs.loadSettings('/config.otml')

g_modules.discoverModules()

-- libraries modules 0-99
g_modules.autoLoadModules(99)
g_modules.ensureModuleLoaded('corelib')
g_modules.ensureModuleLoaded('gamelib')
g_modules.ensureModuleLoaded('modulelib')
g_modules.ensureModuleLoaded("startup")

g_modules.autoLoadModules(999)
g_modules.ensureModuleLoaded('game_shaders') -- pre load

local function loadModules()
    -- client modules 100-499
    g_modules.autoLoadModules(499)
    g_modules.ensureModuleLoaded('client')

    -- game modules 500-999
    g_modules.autoLoadModules(999)
    g_modules.ensureModuleLoaded('game_interface')

    -- mods 1000-9999
    g_modules.autoLoadModules(9999)
    g_modules.ensureModuleLoaded('client_mods')

    local script = '/' .. g_app.getCompactName() .. 'rc.lua'

    if g_resources.fileExists(script) then
        dofile(script)
    end

    -- uncomment the line below so that modules are reloaded when modified. (Note: Use only mod dev)
    -- g_modules.enableAutoReload()
end

loadModules()
