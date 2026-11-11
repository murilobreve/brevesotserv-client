-- Mythos Voz (game_voice): voice chat for parties, guilds and public rooms.
-- This file glues the pieces together: opcode 142 with canary, the engine
-- (full with g_voice, lite over HTTP.webSocket, mock for developers), the
-- push-to-talk keys, game-sound ducking and the session of voice_state.lua.
--
-- Nothing shows and nothing runs until canary answers the hi with cfg on:
-- a server without voice costs one small opcode per login. The locale, the
-- keybinds, the panel and the engine are all made on first use.

local OPCODE = VoiceState.OPCODE
local ST = VoiceState.ST
local PREFS_NODE = 'voice'
local MOCK_KEY = 'voice-mock' -- g_settings.setValue('voice-mock', 'true'), then log in again
local TX_LIMIT_MS = 60000     -- push-to-talk held longer than this: released, with a notice
local HINT_GAP_MS = 10000
local SAVE_DELAY_MS = 1000
local DUCK_GAIN = 0.7         -- game sounds at 70% while someone talks

KEY_CATEGORY = 'Voz'
KEY_TALK = { [0] = 'Falar na party', [1] = 'Falar na guild', [2] = 'Falar na sala/evento' }
local KEY_MUTE, KEY_DEAFEN, KEY_PANEL = 'Silenciar microfone', 'Ensurdecer', 'Abrir/fechar Voz'
local PRESET_IDS = { normal = 0, eco = 1, high = 2 }

local session, engine, engineName
local prefs
local timers = {}
local saveEvent
local keybindsOn, localeOn = false, false
local txSlot, txKey, txGuard = -1, nil, nil
local hintAt = {}
local ducked
local testing = false

-- small helpers ---------------------------------------------------------------

local function engineCall(method, ...)
    local f = engine and engine[method]
    if f then
        return f(engine, ...)
    end
end

-- for the settings window: nil when there is no engine (yet) or no such call
function callEngine(method, ...)
    return engineCall(method, ...)
end

-- the mic test ends with the session; the engine is told, since a socket
-- the relay closed does not end the test there
local function stopTest()
    if testing then
        testing = false
        engineCall('startLocalTest', false)
    end
end

local function buildTag()
    local version = g_app.getVersion and g_app.getVersion() or ''
    local commit = g_app.getBuildCommit and g_app.getBuildCommit() or ''
    return (version .. ' ' .. commit:sub(1, 7)):gsub('^%s+', ''):sub(1, 40)
end

local function clientTag()
    return g_platform.isBrowser() and 'web' or 'win'
end

function notify(text)
    modules.game_textmessage.displayGameMessage(text)
end

-- a hint about a key press, at most once per HINT_GAP_MS for each kind
local function hint(kind, text)
    local now = g_clock.millis()
    if not hintAt[kind] or now - hintAt[kind] >= HINT_GAP_MS then
        hintAt[kind] = now
        notify(text)
    end
end

function getSession()
    return session
end

function getEngineName()
    return engineName
end

-- lite has no audio: no talking, no volumes, no microphone test
function hasAudio()
    return engineName == 'full' or engineName == 'mock'
end

-- engine ----------------------------------------------------------------------

local function pickEngine(mock)
    if mock then
        return 'mock'
    elseif EngineFull.available() then
        return 'full'
    elseif EngineLite.available() then
        return 'lite'
    end
    return nil
end

local function onEngineEvent(kind, s, a, b)
    if not session then
        return
    end
    if kind == 'state' then
        session:onEngineState(s, a)
    elseif kind == 'ctl' then
        session:onControl(s)
    elseif kind == 'spk' then
        session:onSpeaking(a, b == 1 or b == true)
    elseif kind == 'talk' then
        session:onTalk(a)
    elseif kind == 'level' then
        VoiceSettings.onLevel(a)
    elseif kind == 'mic' and s == 'denied' then
        notify(tr('Voice: the microphone was blocked. You can still listen.'))
    elseif kind == 'mic' and s == 'encoder' then
        notify(tr('Voice: your voice could not be encoded. You can still listen.'))
    elseif kind == 'devices' then
        VoiceSettings.refreshDevices()
    end
end

-- the background push-to-talk key (Windows) is the party key: sent again on
-- each state change and each press too, since a key changed in the options
-- raises no event (the engine ignores a value it already has)
local function syncGlobalKey()
    if not g_platform.isBrowser() then
        engineCall('setGlobalPtt', prefs.globalPtt and VoiceState.virtualKey(talkKey(0)) or 0)
    end
end

-- the settings the engine keeps, sent once when it is made and on change
function applyEnginePrefs()
    engineCall('setMode', prefs.mode == 'vad')
    engineCall('setVadThreshold', prefs.vadDb)
    engineCall('setPreset', PRESET_IDS[prefs.preset] or 0)
    engineCall('setInputGain', prefs.inGain / 100)
    engineCall('setOutputVolume', prefs.outVol / 100)
    engineCall('setSelfMuted', prefs.selfMuted)
    engineCall('setDeafened', prefs.deafened)
    engineCall('setInputDevice', prefs.inDevice)
    engineCall('setOutputDevice', prefs.outDevice)
    if g_platform.isBrowser() then
        engineCall('setPttMouse', prefs.pttMouse, prefs.pttMouse > 0 and 0 or -1)
    end
    syncGlobalKey()
end

local function ensureEngine()
    if engine then
        return
    end
    local info = { cl = clientTag(), build = buildTag() }
    if engineName == 'full' then
        engine = EngineFull.create(onEngineEvent, info)
    elseif engineName == 'lite' then
        engine = EngineLite.create(onEngineEvent, info)
    else
        local player = g_game.getLocalPlayer()
        info.self = player and { cid = player:getId(), name = player:getName() } or nil
        engine = EngineMock.create(onEngineEvent, info)
    end
    applyEnginePrefs()
end

-- opcode 142 ------------------------------------------------------------------

local function send142(msg)
    if engineName == 'mock' then
        -- canary stand-in: answers on the next frame, like the network would
        local reply = EngineMock.reply(msg)
        if reply then
            addEvent(function()
                if session then
                    session:onOpcode(reply)
                end
            end)
        end
        return
    end
    local protocol = g_game.getProtocolGame()
    local buffer = json.encode(msg)
    if protocol and #buffer <= VoiceState.MAX_OPCODE_BYTES then
        protocol:sendExtendedOpcode(OPCODE, buffer)
    end
end

local function onOpcode(protocol, opcode, buffer)
    local data = VoiceState.decode(buffer, VoiceState.MAX_OPCODE_BYTES)
    if data and session then
        session:onOpcode(data)
    end
end

-- preferences -----------------------------------------------------------------

local function savePrefsNow()
    saveEvent = nil
    g_settings.setNode(PREFS_NODE, VoiceState.serializePrefs(prefs))
end

-- a slider sends many changes: saved once they stop
local function savePrefs()
    if not saveEvent then
        saveEvent = scheduleEvent(savePrefsNow, SAVE_DELAY_MS)
    end
end

function getPrefs()
    return prefs
end

function setPref(key, value)
    prefs[key] = value
    savePrefs()
    applyEnginePrefs()
    if key == 'overheadIcon' and not value then
        VoiceUI.clearHeads()
    elseif key == 'ducking' and not value then
        duck(false)
    end
end

-- the locale and the keybinds, made the first time voice is offered -----------

local function ensureLocale()
    if localeOn then
        return
    end
    localeOn = true
    local ok, translation = pcall(dofile, '/game_voice/voice_locale.lua')
    -- merged straight into the installed table (installLocale would log every
    -- client string this short list lacks), and only where pt.lua has no text:
    -- "Other" or "None" mean something else in other windows
    local locales = modules.client_locales
    local pt = locales and locales.getInstalledLocales()['pt']
    if ok and type(translation) == 'table' and pt and type(pt.translation) == 'table' then
        for english, portuguese in pairs(translation) do
            if pt.translation[english] == nil then
                pt.translation[english] = portuguese
            end
        end
    end
end

-- push-to-talk ----------------------------------------------------------------

local function onAnyKeyUp(widget, keyCode)
    -- the key came up with another modifier held than when it went down
    if txSlot >= 0 and keyCode == txKey then
        releaseTalk()
    end
    return false
end

function releaseTalk(slot)
    if txSlot < 0 or (slot and slot ~= txSlot) then
        return
    end
    txSlot, txKey = -1, nil
    engineCall('setTransmit', -1)
    disconnect(rootWidget, { onKeyUp = onAnyKeyUp })
    removeEvent(txGuard)
    txGuard = nil
end

function pressTalk(slot, keyCode)
    if not session or session.state ~= ST.ONLINE then
        return
    end
    syncGlobalKey()
    if not hasAudio() then
        hint('lite', tr('Voice: presence mode cannot talk. Update the client or use Chrome, Edge or Firefox.'))
        return
    end
    if not session.rooms[slot] then
        hint('room', tr('Voice: join a room first.'))
        return
    end
    if prefs.selfMuted or prefs.deafened then
        hint('muted', tr('Voice: your microphone is muted.'))
        return
    end
    if txSlot == slot then
        return
    end
    releaseTalk()
    txSlot, txKey = slot, keyCode
    engineCall('setTransmit', slot)
    if keyCode then
        connect(rootWidget, { onKeyUp = onAnyKeyUp }, true)
    end
    txGuard = scheduleEvent(function()
        txGuard = nil
        releaseTalk()
        notify(tr('Voice: you talked for 60 seconds without a break; the key was released.'))
    end, TX_LIMIT_MS)
end

-- the hold-to-talk button of touch screens: the first room joined
function touchSlot()
    for slot = 0, 2 do
        if session and session.rooms[slot] then
            return slot
        end
    end
    return 0
end

local function registerKeybinds()
    if keybindsOn then
        return
    end
    keybindsOn = true
    for slot = 0, 2 do
        local action = KEY_TALK[slot]
        Keybind.new(KEY_CATEGORY, action, '', '')
        Keybind.bind(KEY_CATEGORY, action, {
            { type = KEY_DOWN, callback = function(widget, keyCode) pressTalk(slot, keyCode) end },
            { type = KEY_UP, callback = function() releaseTalk(slot) end },
        })
    end
    Keybind.new(KEY_CATEGORY, KEY_MUTE, '', '')
    Keybind.bind(KEY_CATEGORY, KEY_MUTE, { { type = KEY_DOWN, callback = function() toggleSelfMute() end } })
    Keybind.new(KEY_CATEGORY, KEY_DEAFEN, '', '')
    Keybind.bind(KEY_CATEGORY, KEY_DEAFEN, { { type = KEY_DOWN, callback = function() toggleDeafen() end } })
    Keybind.new(KEY_CATEGORY, KEY_PANEL, '', '')
    Keybind.bind(KEY_CATEGORY, KEY_PANEL, { { type = KEY_DOWN, callback = function() VoiceUI.toggle() end } })
end

local function unregisterKeybinds()
    if not keybindsOn then
        return
    end
    keybindsOn = false
    for slot = 0, 2 do
        Keybind.delete(KEY_CATEGORY, KEY_TALK[slot])
    end
    Keybind.delete(KEY_CATEGORY, KEY_MUTE)
    Keybind.delete(KEY_CATEGORY, KEY_DEAFEN)
    Keybind.delete(KEY_CATEGORY, KEY_PANEL)
end

-- the key of a push-to-talk slot, as the player sees it ('' if none)
function talkKey(slot)
    if not keybindsOn then
        return ''
    end
    local keys = Keybind.getKeybindKeys(KEY_CATEGORY, KEY_TALK[slot])
    return keys and tostring(keys.primary or '') or ''
end

-- game sounds lower while someone talks (edges only) ------------------------

function duck(on)
    if on and prefs.ducking and not ducked and g_sounds then
        ducked = {}
        for _, id in pairs(SoundChannels) do
            local channel = g_sounds.getChannel(id)
            if channel then
                local before = channel:getGain()
                channel:setGain(before * DUCK_GAIN)
                ducked[id] = { before, channel:getGain() }
            end
        end
    elseif not on and ducked then
        for id, gains in pairs(ducked) do
            local channel = g_sounds.getChannel(id)
            -- the player moved the volume meanwhile: theirs stays
            if channel and math.abs(channel:getGain() - gains[2]) < 0.001 then
                channel:setGain(gains[1])
            end
        end
        ducked = nil
    end
end

-- session events --------------------------------------------------------------

local function onSessionEvent(what, a, b, c)
    if what == 'cfg' then
        ensureLocale()
        registerKeybinds()
        VoiceUI.create()
        -- not for a panel that only tells of a ban
        if not prefs.onboarded and session.everOn then
            VoiceSettings.scheduleOnboarding()
        end
    elseif what == 'state' then
        if session.state ~= ST.ONLINE then
            releaseTalk()
            stopTest()
        end
        syncGlobalKey()
        VoiceUI.onState()
        VoiceSettings.onState()
    elseif what == 'speakers' then
        duck(a > 0)
        VoiceUI.onEvent(what, a, b, c)
    else
        VoiceUI.onEvent(what, a, b, c)
    end
end

local io = {
    now = function() return g_clock.millis() end,
    time = os.time,
    random = math.random,
    send142 = send142,
    connect = function(url, tok)
        ensureEngine()
        engine:connect(url, tok)
    end,
    disconnect = function() engineCall('disconnect') end,
    sendCtl = function(msg) engineCall('send', msg) end,
    schedule = function(name, ms)
        removeEvent(timers[name])
        timers[name] = scheduleEvent(function()
            timers[name] = nil
            if session then
                session:onTimer(name)
            end
        end, math.max(1, ms))
    end,
    cancel = function(name)
        removeEvent(timers[name])
        timers[name] = nil
    end,
    savePrefs = function() savePrefs() end,
    -- the state machine is past the change when it tells: an error in the
    -- panel is logged and never leaves the session half way
    emit = function(what, a, b, c)
        local ok, err = pcall(onSessionEvent, what, a, b, c)
        if not ok then
            g_logger.error('game_voice: ' .. tostring(what) .. ': ' .. tostring(err))
        end
    end,
    engine = engineCall,
}

-- player actions (panel buttons, keys, menus) ---------------------------------

function setWant(on)
    if session then
        session:setWant(on)
    end
end

function retryNow()
    if session then
        session:retryNow()
    end
end

function toggleSelfMute()
    if session and session:isVisible() then
        session:setSelfMuted(not prefs.selfMuted)
    end
end

function toggleDeafen()
    if session and session:isVisible() then
        session:setDeafened(not prefs.deafened)
    end
end

-- "Test microphone": the engine plays the microphone back locally
function toggleMicTest()
    if not hasAudio() then
        hint('lite', tr('Voice: presence mode cannot talk. Update the client or use Chrome, Edge or Firefox.'))
        return
    end
    testing = not testing
    engineCall('startLocalTest', testing)
    VoiceUI.onState()
    VoiceSettings.onState()
end

function isTesting()
    return testing
end

-- game ------------------------------------------------------------------------

local function onGameStart()
    local mock = g_settings.getValue(MOCK_KEY) == 'true'
    engineName = pickEngine(mock)
    if not engineName then
        return
    end
    -- the engine of another login (mock switched on or off) goes away
    if engine and engine.name ~= engineName then
        engine:terminate()
        engine = nil
    end
    session:gameStart(clientTag(), engineName == 'full' and 'full' or 'lite', g_game.getCharacterName())
end

local function onGameEnd()
    releaseTalk()
    stopTest()
    if session then -- nil only if init failed half way
        session:gameEnd()
    end
    duck(false)
    VoiceSettings.destroy()
    VoiceUI.destroy()
end

function init()
    prefs = VoiceState.normalizePrefs(g_settings.getNode(PREFS_NODE))
    session = VoiceState.new(io, prefs)
    ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
    onGameEnd()
    for name in pairs(timers) do
        io.cancel(name)
    end
    if saveEvent then
        removeEvent(saveEvent)
        savePrefsNow()
    end
    if engine then
        engine:terminate()
        engine = nil
    end
    unregisterKeybinds()
    session = nil
end
