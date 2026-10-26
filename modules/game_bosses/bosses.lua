-- Bosses: the bosses fought from a lever, each in its lever room (copied from
-- the official map). The list shows the quest, the level and the player's
-- wait for every boss; the button takes the player to the lever room, from a
-- protection zone or out of a fight. Opened from the Mythos bar.
-- Talks to data-otservbr-global/scripts/custom/boss_portal.lua through
-- extended opcode BOSS_OPCODE with JSON payloads.

local BOSS_OPCODE = 133

local window
local panelButton
local toolbarButton
local state -- last "state" from the server
local receivedAt = 0 -- os.time() when it came: the waits count down from there
local selectedName
local filter = 'all'
local rows = {} -- boss name -> row of the list
local tickEvent
local messageEvent

-- ---------------------------------------------------------------- helpers

-- the fonts draw one glyph per byte (Latin-1); this file and the server's JSON are UTF-8
local function latin1(text)
    return (tostring(text):gsub('[\194\195][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        return string.char((a - 194) * 64 + b)
    end))
end

local function tr(text, ...)
    if select('#', ...) > 0 then
        text = string.format(text, ...)
    end
    return latin1(text)
end

local function convertStrings(value)
    if type(value) == 'string' then
        return latin1(value)
    elseif type(value) == 'table' then
        for k, v in pairs(value) do
            value[k] = convertStrings(v)
        end
    end
    return value
end

local function formatNumber(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    while true do
        local replaced, count = text:gsub('^(-?%d+)(%d%d%d)', '%1.%2')
        text = replaced
        if count == 0 then
            return text
        end
    end
end

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(BOSS_OPCODE, data)
    end
end

-- server outfit array: { type, head, body, legs, feet, addons, typeEx }
local function outfitOf(raw)
    raw = raw or {}
    return {
        type = raw[1] or 0,
        head = raw[2] or 0,
        body = raw[3] or 0,
        legs = raw[4] or 0,
        feet = raw[5] or 0,
        addons = raw[6] or 0,
        auxType = raw[7] or 0,
        mount = 0,
    }
end

local function waitLeft(boss)
    return math.max(0, (boss.cooldown or 0) - (os.time() - receivedAt))
end

local function formatWait(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.ceil(seconds % 3600 / 60)
    if minutes == 60 then
        hours, minutes = hours + 1, 0
    end
    if hours > 0 then
        return string.format('%dh%02d', hours, minutes)
    end
    return string.format('%d min', math.max(1, minutes))
end

local function canFight(boss)
    return boss.level == 0 or (state and state.level or 0) >= boss.level
end

local function statusOf(boss)
    if not canFight(boss) then
        return tr('Nível %d', boss.level), '#ff7a6b'
    end
    local left = waitLeft(boss)
    if left > 0 then
        return formatWait(left), '#e0c060'
    end
    return tr('Pronto'), '#7fd35a'
end

local function findBoss(name)
    for _, boss in ipairs(state and state.bosses or {}) do
        if boss.name == name then
            return boss
        end
    end
end

local function shown(boss)
    if filter == 'ready' and (waitLeft(boss) > 0 or not canFight(boss)) then
        return false
    end
    if filter == 'level' and not canFight(boss) then
        return false
    end
    local query = window.search:getText():lower()
    if query ~= '' then
        local text = (boss.name .. ' ' .. (boss.quest or '')):lower()
        if not text:find(query, 1, true) then
            return false
        end
    end
    return true
end

local function showMessage(text, ok)
    if not window then
        return
    end
    if messageEvent then
        removeEvent(messageEvent)
    end
    window.message:setText(text or '')
    window.message:setColor(ok and '#7fd35a' or '#ff7a6b')
    messageEvent = scheduleEvent(function()
        messageEvent = nil
        if window then
            window.message:setText('')
        end
    end, 8000)
end

-- ---------------------------------------------------------------- rendering

local function setStat(stat, key, value, color)
    stat.key:setText(key)
    stat.value:setText(value)
    stat.value:setColor(color or '#e6e0f2')
end

local function renderCard()
    local card = window.card
    local boss = findBoss(selectedName)
    card:setVisible(boss ~= nil)
    if not boss then
        return
    end
    card:setText(tr('Boss'))
    card.creature:setOutfit(outfitOf(boss.outfit))
    card.name:setText(boss.name)
    card.quest:setText(boss.quest or '')
    setStat(card.level, tr('Nível mínimo'), boss.level > 0 and tostring(boss.level) or tr('livre'),
        canFight(boss) and '#e6e0f2' or '#ff7a6b')
    setStat(card.health, tr('Vida'), formatNumber(boss.health))
    setStat(card.experience, tr('Experiência'), formatNumber(boss.experience))
    setStat(card.wait, tr('Espera entre lutas'), formatWait(boss.wait or 0))
    setStat(card.players, tr('Jogadores'), boss.players > 1 and tr('%d ou mais', boss.players) or tr('1 a 5'))
    local status, color = statusOf(boss)
    setStat(card.cooldown, tr('Sua espera'), status, color)
    card.note:setText(tr('Você vai para a sala da alavanca. Fique com o time nos pisos marcados e puxe a alavanca. O portal ao lado volta para o templo.'))
    card.go:setEnabled(canFight(boss))
end

local function selectBoss(name)
    selectedName = name
    renderCard()
end

-- the waits count down without asking the server again
local function updateStatuses()
    if not state then
        return
    end
    local ready = 0
    for _, boss in ipairs(state.bosses) do
        local status, color = statusOf(boss)
        if canFight(boss) and waitLeft(boss) == 0 then
            ready = ready + 1
        end
        local row = rows[boss.name]
        if row then
            row.status:setText(status)
            row.status:setColor(color)
        end
    end
    local boss = findBoss(selectedName)
    if boss and window then
        local status, color = statusOf(boss)
        setStat(window.card.cooldown, tr('Sua espera'), status, color)
    end
    if window then
        window.summary:setText(tr('%d bosses, %d prontos para você. Cada um na sala da alavanca do mapa oficial.', #state.bosses, ready))
    end
    local panel = modules.game_brevespanel
    if panel and panel.setFeatureState then
        panel.setFeatureState('bosses', ready > 0 and tostring(ready) or nil, '#7fd35a')
    end
end

function refreshList()
    if not window or not state then
        return
    end
    local list = window.list
    list:destroyChildren()
    rows = {}
    local first, firstName, keep
    local index = 0
    for _, boss in ipairs(state.bosses) do
        if shown(boss) then
            index = index + 1
            local row = g_ui.createWidget(index % 2 == 0 and 'BossRowEven' or 'BossRow', list)
            row.creature:setOutfit(outfitOf(boss.outfit))
            row.name:setText(boss.name)
            row.info:setText(tr('%s · %s', boss.quest or '', boss.level > 0 and tr('nível %d', boss.level) or tr('qualquer nível')))
            row.onFocusChange = function(widget, focused)
                if focused then
                    selectBoss(boss.name)
                end
            end
            row.onDoubleClick = function()
                selectBoss(boss.name)
                goSelected()
                return true
            end
            rows[boss.name] = row
            if not first then
                first, firstName = row, boss.name
            end
            if boss.name == selectedName then
                keep = row
            end
        end
    end
    updateStatuses()
    local focus = keep or first
    if focus then
        list:focusChild(focus, KeyboardFocusReason)
        list:ensureChildVisible(focus)
        selectBoss(focus == keep and selectedName or firstName)
    else
        selectBoss(nil)
    end
end

function setFilter(which)
    filter = which
    window.allTab:setChecked(which == 'all')
    window.readyTab:setChecked(which == 'ready')
    window.levelTab:setChecked(which == 'level')
    refreshList()
end

function goSelected()
    local boss = findBoss(selectedName)
    if not boss then
        return
    end
    if not canFight(boss) then
        showMessage(tr('%s pede nível %d.', boss.name, boss.level), false)
        return
    end
    send({ action = 'go', name = selectedName })
end

-- ---------------------------------------------------------------- server

local handlers = {}

function handlers.state(data)
    state = data
    receivedAt = os.time()
    if window and window:isVisible() then
        refreshList()
    else
        updateStatuses()
    end
end

function handlers.message(data)
    showMessage(data.text, data.ok)
    if data.went then
        hide()
    end
end

local function onBossOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    local handler = handlers[data.action]
    if handler then
        handler(convertStrings(data))
    end
end

-- ---------------------------------------------------------------- window

local function setOn(value)
    if panelButton then
        panelButton:setOn(value)
    end
    if toolbarButton then
        toolbarButton:setOn(value)
    end
end

local function tick()
    updateStatuses()
end

function show()
    if not window then
        return
    end
    window:show()
    window:raise()
    window:focus()
    setOn(true)
    if not tickEvent then
        tickEvent = cycleEvent(tick, 1000)
    end
    refreshList()
    send({ action = 'open' })
end

function hide()
    if not window then
        return
    end
    window:hide()
    setOn(false)
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
end

function toggle()
    if window and window:isVisible() then
        hide()
    else
        show()
    end
end

-- ---------------------------------------------------------------- lifecycle

local function onGameStart()
    if not panelButton and modules.game_brevespanel then
        panelButton = modules.game_brevespanel.addFeature('bosses', toggle)
    end
    if not panelButton and not toolbarButton and modules.game_mainpanel then
        toolbarButton = modules.game_mainpanel.addToggleButton('bossesButton', tr('Bosses'),
            '/game_brevespanel/images/bosses', toggle, false, 23)
    end
    -- ask once, quietly, so the bar row can show how many are ready
    scheduleEvent(function()
        if g_game.isOnline() and not state then
            send({ action = 'open' })
        end
    end, 4000)
end

local function onGameEnd()
    hide()
    state = nil
    selectedName = nil
    rows = {}
    if window then
        window.list:destroyChildren()
    end
end

function init()
    window = g_ui.displayUI('bosses')
    window:hide()
    window:setText(tr('Bosses'))
    window.levelTab:setText(tr('Meu nível'))
    window.allTab:setChecked(true)
    window.card:setVisible(false)

    ProtocolGame.registerExtendedJSONOpcode(BOSS_OPCODE, onBossOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedJSONOpcode(BOSS_OPCODE)
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    if messageEvent then
        removeEvent(messageEvent)
        messageEvent = nil
    end
    if panelButton then
        panelButton:destroy()
        panelButton = nil
    end
    if toolbarButton then
        toolbarButton:destroy()
        toolbarButton = nil
    end
    if window then
        window:destroy()
        window = nil
    end
end
