-- Mythos Voz settings window and the one-time onboarding. Audio settings go
-- to the engine at once; everything is saved in the g_settings node 'voice'
-- (voice.lua). The push-to-talk keys are Keybind actions of the 'Voz'
-- category, so they also show in Options > Hotkeys.

VoiceSettings = {}
local VS = VoiceSettings
local S = VoiceState

local ONBOARD_DELAY_MS = 2000
local RULES_URL = 'https://mythosot.com.br/?subtopic=voz'
local PRESETS = { { 'normal', 'Normal' }, { 'eco', 'Economy' }, { 'high', 'High' } }
local MOUSE = { { 0, 'No side button' }, { 3, 'Mouse 4' }, { 4, 'Mouse 5' } }
-- built with pairs: a corelib without one of these constants must not stop
-- the module from loading ([nil] = true raises)
local MODIFIER_KEYS = {}
for _, key in pairs({ KeyShift, KeyControl, KeyCtrlCmd, KeyAltOpt, KeyMeta }) do
    MODIFIER_KEYS[key] = true
end

local window, onboard, onboardEvent
local onboardKey -- the key picked in the onboarding, set when voice is turned on
local stylesLoaded = false

-- the two windows' styles, read the first time one of them opens
local function loadStyles()
    if not stylesLoaded then
        stylesLoaded = true
        g_ui.importStyle('/game_voice/voiceonboard')
        g_ui.importStyle('/game_voice/voicesettings')
    end
end

-- tr formats under pcall: a bad translation never raises
local function fmt(text, ...)
    return tr(text, ...)
end

-- key capture -------------------------------------------------------------------

-- the chat modes a push-to-talk key is saved for (see applyTalkKey)
local function keyModes(chatKey)
    return chatKey and { CHAT_MODE.OFF } or { CHAT_MODE.ON, CHAT_MODE.OFF }
end

local function sameKey(a, b)
    return type(a) == 'string' and a:lower() == b
end

-- fields of an action bar button (game_actionbar's ApiJson mappings) that
-- only qualify its action (useObject, chatText, passiveAbility,
-- specialAction or multiActions)
local SLOT_QUALIFIERS = { useType = true, upgradeTier = true, sendAutomatically = true }

local function filled(v)
    if type(v) == 'string' then
        return v ~= ''
    elseif type(v) == 'number' then
        return v ~= 0
    elseif type(v) == 'table' then
        for _, inner in pairs(v) do
            if filled(inner) then
                return true
            end
        end
        return false
    end
    return v ~= nil and v ~= false
end

-- the key of an action bar button runs something only when the button holds
-- an action: the bar's default F1-F12 on empty buttons are free. A hotkey of
-- the bar that is not a button's (a custom action) always counts as taken.
local function barKeyRuns(bars, entry)
    local action = type(entry.actionsetting) == 'table' and entry.actionsetting.action
    local bar, button = tostring(action or ''):match('^TriggerActionButton_(%d+)%.(%d+)$')
    if not bar or not bars.getMapping then
        return true
    end
    local mapping = bars.getMapping(tonumber(bar), tonumber(button))
    local setting = type(mapping) == 'table' and mapping.actionsetting
    if type(setting) ~= 'table' then
        return false
    end
    for key, value in pairs(setting) do
        if not SLOT_QUALIFIERS[key] and filled(value) then
            return true
        end
    end
    return false
end

-- true when the game would run something else on this key as well: another
-- Keybind action, a hotkey of the current preset, the hotkeys manager or an
-- action bar button that holds an action. The other modules are asked under
-- pcall: a change in them must not break the key capture.
function VS.keyTaken(combo, slot, chatKey)
    local lower = combo:lower()
    -- the browser page keeps F11 for its full screen
    if g_platform.isBrowser() and lower == 'f11' then
        return true
    end
    for _, mode in ipairs(keyModes(chatKey)) do
        if Keybind.isKeyComboUsed(combo, KEY_CATEGORY, KEY_TALK[slot], mode) then
            return true
        end
        local hotkeys = Keybind.hotkeys[mode] and Keybind.hotkeys[mode][Keybind.currentPreset] or {}
        for _, hotkey in ipairs(hotkeys) do
            if sameKey(hotkey.primary, lower) or sameKey(hotkey.secondary, lower) then
                return true
            end
        end
    end
    local manager = modules.game_hotkeys
    if manager and manager.isHotkeyUsedByManager then
        local ok, used = pcall(manager.isHotkeyUsedByManager, combo)
        if ok and used then
            return true
        end
    end
    local bars = modules.game_actionbar and modules.game_actionbar.ApiJson
    if bars and bars.hasCurrentHotkeySet and bars.getHotkeyEntries then
        local ok, used = pcall(function()
            if not bars.hasCurrentHotkeySet() then
                return false
            end
            for _, chat in ipairs(chatKey and { 'chatOff' } or { 'chatOn', 'chatOff' }) do
                for _, entry in ipairs(bars.getHotkeyEntries(chat)) do
                    if type(entry) == 'table' and sameKey(entry.keysequence, lower) and barKeyRuns(bars, entry) then
                        return true
                    end
                end
            end
            return false
        end)
        if ok and used then
            return true
        end
    end
    return false
end

-- keys that do nothing in the chat (Home and End move its cursor) and that
-- the game leaves free on a new profile, in the order they are offered:
-- Insert on desktop and browser
VS.FREE_KEYS = { 'Insert', 'Pause' }

-- the first of FREE_KEYS nothing else runs on, for a push-to-talk slot; nil
-- when they are all taken
function VS.freeKey(slot)
    for _, key in ipairs(VS.FREE_KEYS) do
        if not VS.keyTaken(key, slot, false) then
            return key
        end
    end
    return nil
end

-- sets the key of a push-to-talk slot in the current preset: both chat
-- modes, or only "chat off" for a key that types in the chat
local function applyTalkKey(slot, combo, chatKey)
    local action = KEY_TALK[slot]
    local preset = Keybind.currentPreset
    for _, mode in ipairs(keyModes(chatKey)) do
        Keybind.setPrimaryActionKey(KEY_CATEGORY, action, preset, combo, mode)
    end
end

-- the client sends a key's press right after its down (PlatformWindow::
-- processKeyDown): the box keeps the keyboard until then and eats it. Let
-- go on the down, that press would reach the window, and Escape or Enter
-- there closes it (UIWindow:onKeyPress): the settings window with the key
-- unchanged, the onboarding as seen for good with voice off. The release a
-- frame later only matters if a press never came.
local function eatPress(widget)
    widget.onKeyPress = nil
    if not widget:isDestroyed() then
        widget:ungrabKeyboard()
    end
    return true
end

-- turns `box` into a key catcher; done(combo, chatKey) or failed(text)
local function captureKey(box, slot, done, failed)
    box:setText(tr('Press a key...'))
    box:focus()
    box:grabKeyboard()
    box.onKeyPress = nil
    box.onKeyDown = function(widget, keyCode, modifiers)
        if MODIFIER_KEYS[keyCode] then
            return true -- waits for the key that goes with it
        end
        widget.onKeyDown = nil
        widget.onKeyPress = eatPress
        scheduleEvent(function()
            if widget.onKeyPress == eatPress then
                eatPress(widget)
            end
        end, 1)
        -- Escape cancels; so does a key the client has no name for (nil),
        -- which would otherwise clear the binding
        local combo = keyCode ~= KeyEscape and determineKeyComboDesc(keyCode, modifiers)
        if not combo or combo == '' then
            failed(nil)
            return true
        end
        local chatKey = S.isChatKey(keyCode, modifiers)
        if chatKey and Keybind.chatMode == CHAT_MODE.ON then
            failed(tr('This key types in the chat. Pick another one (Insert, Ctrl+..., Alt+...) or turn the chat off.'))
        elseif VS.keyTaken(combo, slot, chatKey) then
            local free = VS.freeKey(slot)
            failed(free and fmt('%s is already used by another action. Try %s.', combo, free) or
                fmt('%s is already used by another action.', combo))
        else
            done(combo, chatKey)
        end
        return true
    end
end

-- the onboarding ------------------------------------------------------------------

function VS.scheduleOnboarding()
    if onboard or onboardEvent then
        return
    end
    onboardEvent = scheduleEvent(function()
        onboardEvent = nil
        VS.showOnboarding()
    end, ONBOARD_DELAY_MS)
end

-- the browser forwards the mouse side buttons only with the full engine
local function browserMouse()
    return g_platform.isBrowser() and getEngineName() == 'full'
end

function VS.showOnboarding()
    local s = getSession()
    if onboard or not s or not s:isVisible() then
        return
    end
    loadStyles()
    onboard = g_ui.createWidget('VoiceOnboardWindow', rootWidget)
    onboardKey = nil
    local box, status, keyHint = onboard.keyBox, onboard.keyStatus, onboard.keyHint
    local current = talkKey(0)
    -- no key yet: a free one is offered (Insert on a new profile), so a new
    -- player need not guess which key the game leaves free
    if current == '' then
        -- under pcall: the window shows even if a key check breaks
        local ok, free = pcall(VS.freeKey, 0)
        if ok and free then
            onboardKey = { combo = free, chatKey = false, suggested = true }
            keyHint:setText(fmt('Suggested: %s. Click the box to pick another key.', free))
        end
    end
    local function shown()
        return onboardKey and onboardKey.combo or (current ~= '' and current or tr('Click here'))
    end
    box:setText(shown())
    box.onClick = function()
        status:setText('')
        captureKey(box, 0, function(combo, chatKey)
            onboardKey = { combo = combo, chatKey = chatKey }
            box:setText(combo)
            keyHint:setText('')
        end, function(text)
            status:setText(text or '')
            box:setText(shown())
        end)
    end
    -- the browser: a mouse side button can be the push-to-talk too
    local mouse = onboard.mouseCheck
    mouse:setVisible(browserMouse())
    mouse:setChecked(getPrefs().pttMouse == 3)
    onboard:raise()
    onboard:focus()
end

function VS.closeOnboarding(turnOn)
    local mouse
    if onboard then
        onboard.keyBox:ungrabKeyboard()
        if browserMouse() then -- the box shows only there
            mouse = onboard.mouseCheck:isChecked()
        end
        onboard:destroy()
        onboard = nil
    end
    -- a key the player picked is kept either way; the suggested one only
    -- when voice is turned on
    if onboardKey and (turnOn or not onboardKey.suggested) then
        applyTalkKey(0, onboardKey.combo, onboardKey.chatKey)
    end
    onboardKey = nil
    -- the side button, only when the box changed it (Mouse 5 set before stays)
    local button = getPrefs().pttMouse
    if mouse == true and button ~= 3 then
        setPref('pttMouse', 3)
    elseif mouse == false and button == 3 then
        setPref('pttMouse', 0)
    end
    -- also sends the engine the settings again: the background push-to-talk
    -- follows the party key
    setPref('onboarded', true)
    if turnOn then
        setWant(true)
    end
end

function VS.openRules()
    g_platform.openUrl(RULES_URL)
end

-- the settings window ----------------------------------------------------------

local function sliderLabel(id, text, value)
    window:recursiveGetChildById(id):setText(fmt(text, value))
end

local function fillCombo(combo, options, current, onPick)
    combo.onOptionChange = nil
    combo:clearOptions()
    for _, option in ipairs(options) do
        combo:addOption(option[2], option[1])
    end
    combo:setCurrentOptionByData(current, true)
    combo.onOptionChange = function(widget, text, data)
        onPick(data)
    end
end

-- the devices the engine offers ('' is the system default)
local function deviceOptions(list)
    local options = { { '', tr('Default') } }
    if type(list) == 'table' then
        for i = 1, math.min(#list, 32) do
            if type(list[i]) == 'string' then
                options[#options + 1] = { list[i], S.latin1(list[i]) }
            end
        end
    end
    return options
end

function VS.refreshDevices()
    if not window then
        return
    end
    local inputs, outputs = callEngine('getInputDevices'), callEngine('getOutputDevices')
    local prefs = getPrefs()
    fillCombo(window.audio.inDevice, deviceOptions(inputs), prefs.inDevice, function(id)
        setPref('inDevice', id)
    end)
    fillCombo(window.audio.outDevice, deviceOptions(outputs), prefs.outDevice, function(id)
        setPref('outDevice', id)
    end)
    -- the browser can pick the output only where setSinkId exists (the list comes empty)
    window.audio.inDevice:setEnabled(type(inputs) == 'table' and #inputs > 0)
    window.audio.outDevice:setEnabled(type(outputs) == 'table' and #outputs > 0)
end

local function keyRow(row, slot, label)
    row.label:setText(label)
    -- the tooltip has the key whole: a combo longer than the box is cut
    local function show()
        local key = talkKey(slot)
        row.value:setText(key ~= '' and key or '-')
        row.value:setTooltip(key)
    end
    show()
    row.change.onClick = function()
        local status = window.keys.keyStatus
        status:setText('')
        captureKey(row.value, slot, function(combo, chatKey)
            applyTalkKey(slot, combo, chatKey)
            show()
            applyEnginePrefs() -- the background push-to-talk follows the talk key
        end, function(text)
            status:setText(text or '')
            show()
        end)
    end
end

local function check(id, key)
    local box = window.keys[id]
    box:setChecked(getPrefs()[key])
    box.onCheckChange = function(widget, checked)
        setPref(key, checked)
    end
end

local function slider(id, labelId, text, key)
    local bar = window.audio[id]
    bar:setValue(getPrefs()[key])
    sliderLabel(labelId, text, getPrefs()[key])
    bar.onValueChange = function(widget, value)
        sliderLabel(labelId, text, value)
        setPref(key, value)
    end
end

local function setMode(mode)
    setPref('mode', mode)
    window.audio.modePtt:setChecked(mode == 'ptt')
    window.audio.modeVad:setChecked(mode == 'vad')
    window.audio.vad:setEnabled(mode == 'vad' and hasAudio())
end

function VS.show()
    local s = getSession()
    if not s or not s:isVisible() then
        return
    end
    if window then
        window:raise()
        window:focus()
        return
    end
    loadStyles()
    window = g_ui.createWidget('VoiceSettingsWindow', rootWidget)
    local prefs = getPrefs()
    local audio, keys = window.audio, window.keys
    local audioOk = hasAudio()

    audio.enabled:setChecked(s:optedIn())
    -- only a change by the player: VS.onState sets the box back to what the
    -- session did (a refused setWant), and that must not send a want
    audio.enabled.onCheckChange = function(widget, checked)
        local session = getSession()
        if session and checked ~= session:optedIn() then
            setWant(checked)
        end
    end
    audio.modePtt.onClick = function() setMode('ptt') end
    audio.modeVad.onClick = function() setMode('vad') end
    setMode(prefs.mode)
    slider('vad', 'vadLabel', 'Activation level: %d dB', 'vadDb')
    slider('inGain', 'inGainLabel', 'Microphone volume: %d%%', 'inGain')
    slider('outVol', 'outVolLabel', 'Voice volume: %d%%', 'outVol')
    local presets = {}
    for _, p in ipairs(PRESETS) do
        presets[#presets + 1] = { p[1], tr(p[2]) }
    end
    fillCombo(audio.preset, presets, prefs.preset, function(id) setPref('preset', id) end)
    VS.refreshDevices()
    for _, id in ipairs({ 'modeVad', 'vad', 'inGain', 'outVol', 'preset' }) do
        audio[id]:setEnabled(audioOk and (id ~= 'vad' or prefs.mode == 'vad'))
    end

    -- under "Push-to-talk key": one key; it talks in the party, else the
    -- guild, else the room or event, else near you
    keyRow(keys.keyParty, 0, tr('Talk'))
    -- the browser's side buttons reach the page only (phase 4 forwards them)
    local browserFull = browserMouse()
    keys.mouseLabel:setVisible(browserFull)
    keys.mouse:setVisible(browserFull)
    if not browserFull then
        keys.autoParty:addAnchor(AnchorTop, 'keyStatus', AnchorBottom) -- no gap where the row was
    else
        local mouse = {}
        for _, m in ipairs(MOUSE) do
            mouse[#mouse + 1] = { m[1], tr(m[2]) }
        end
        fillCombo(keys.mouse, mouse, prefs.pttMouse, function(button) setPref('pttMouse', button) end)
    end
    check('autoParty', 'autoParty')
    check('autoGuild', 'autoGuild')
    check('autoNear', 'autoNear')
    check('overheadIcon', 'overheadIcon')
    check('ducking', 'ducking')
    -- polling the key with the game in the background: the Windows engine only
    keys.globalPtt:setVisible(getEngineName() == 'full' and not g_platform.isBrowser())
    check('globalPtt', 'globalPtt')
    keys.liteNote:setText(audioOk and '' or
        tr('Audio settings need the new client. In presence mode you see who is in the rooms.'))
    window.testButton:setVisible(audioOk)
    VS.onState()
    if audioOk then
        callEngine('setMeter', true)
    end
    window:raise()
    window:focus()
end

function VS.hide()
    if not window then
        return
    end
    callEngine('setMeter', false)
    window:destroy()
    window = nil
end

function VS.toggle()
    if window then
        VS.hide()
    else
        VS.show()
    end
end

function VS.destroy()
    removeEvent(onboardEvent)
    onboardEvent = nil
    if onboard then
        onboard:destroy()
        onboard = nil
    end
    VS.hide()
end

function VS.onState()
    if window then
        window.testButton:setText(isTesting() and tr('Stop test') or tr('Test microphone'))
        local s = getSession()
        window.audio.enabled:setChecked(s ~= nil and s:optedIn())
    end
end

-- the level meter under the activation slider, 10 times a second while open
function VS.onLevel(db)
    if not window then
        return
    end
    local meter = window.audio.meter
    db = S.num(db, -60, 0, -60) -- NaN would reach setWidth as a huge negative
    meter.fill:setWidth(math.floor(meter:getWidth() * (db + 60) / 60))
    meter.fill:setBackgroundColor(db >= getPrefs().vadDb and '#78d04c' or '#6f688a')
end
