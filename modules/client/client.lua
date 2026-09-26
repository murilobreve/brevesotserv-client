local musicFilename = 'sounds/startup'
local musicChannel = nil

-- settings are only flushed on a clean exit by default; keep them on disk
-- periodically and on logout so a crash or forced close loses nothing
local AUTOSAVE_INTERVAL = 60 * 1000
local autosaveEvent = nil

local function hasStartupMusic()
    for _, ext in ipairs({ '.ogg', '.wav' }) do
        if g_resources.fileExists('/' .. musicFilename .. ext) then
            return true
        end
    end
    return false
end

if g_sounds and hasStartupMusic() then
    musicChannel = g_sounds.getChannel(SoundChannels.Music)
end

function saveClientData()
    if Keybind and Keybind.save then
        Keybind.save()
    else
        g_settings.save()
    end
end

local function onGameStartMusic()
    musicChannel:stop(3)
end

local function onGameEndMusic()
    g_sounds.stopAll()
    musicChannel:enqueue(musicFilename, 3)
end

function setMusic(filename)
    musicFilename = filename

    if musicChannel and not g_game.isOnline() then
        musicChannel:stop()
        musicChannel:enqueue(musicFilename, 3)
    end
end

function startup()
    if musicChannel then
        musicChannel:enqueue(musicFilename, 3)
        connect(g_game, {
            onGameStart = onGameStartMusic,
            onGameEnd = onGameEndMusic
        })
    end

    -- Check for startup errors
    local errtitle = nil
    local errmsg = nil

    if g_graphics.getRenderer():lower():match('gdi generic') then
        errtitle = tr('Graphics card driver not detected')
        errmsg = tr(
            'No graphics card detected, everything will be drawn using the CPU,\nthus the performance will be really bad.\nPlease update your graphics driver to have a better performance.')
    end

    -- Show entergame
    if errmsg or errtitle then
        local msgbox = displayErrorBox(errtitle, errmsg)
        msgbox.onOk = function()
            EnterGame.firstShow()
        end
    else
        EnterGame.firstShow()
    end
end

function init()
    connect(g_app, {
        onRun = startup
    })
    connect(g_game, {
        onGameEnd = saveClientData
    })

    if musicChannel then
        g_sounds.preload(musicFilename)
    end

    autosaveEvent = cycleEvent(saveClientData, AUTOSAVE_INTERVAL)
end

function terminate()
    disconnect(g_app, {
        onRun = startup
    })
    disconnect(g_game, {
        onGameEnd = saveClientData
    })

    if musicChannel then
        disconnect(g_game, {
            onGameStart = onGameStartMusic,
            onGameEnd = onGameEndMusic
        })
    end

    if autosaveEvent then
        removeEvent(autosaveEvent)
        autosaveEvent = nil
    end
end
