-- Quests: the quests of the server (data-otservbr-global/scripts/quests/
-- mythos_quests/quests_window.lua), each a cave of the official map with its
-- own monsters and a chest at the far end that gives one reward of the
-- player's choice, once per character. The list shows each quest's level and
-- whether the player did it; the card shows the cave's monsters, the rewards
-- of the player's vocation and a button that takes him to the entrance (from
-- a protection zone or out of combat, at the quest's level). Opened from the
-- Mythos bar (Hunts section).
-- Talks to the server through extended opcode QUEST_OPCODE with JSON payloads.

local QUEST_OPCODE = 141

local window
local panelButton
local toolbarButton
local state -- last "state" from the server
local selectedKey
local filter = 'all'
local rows = {} -- quest key -> row of the list
local messageEvent

-- ---------------------------------------------------------------- helpers

-- the fonts draw one glyph per byte (Latin-1); the server's JSON is UTF-8
local function latin1(text)
    return (tostring(text):gsub('[\194\195][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        return string.char((a - 194) * 64 + b)
    end))
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

local function isPortuguese()
    local locales = modules.client_locales
    local locale = locales and locales.getCurrentLocale and locales.getCurrentLocale()
    return locale ~= nil and locale.name == 'pt'
end

-- the server sends both languages of its own texts
local function nameOf(quest)
    return isPortuguese() and quest.name or quest.nameEn
end

local function textOf(quest)
    return isPortuguese() and quest.text or quest.textEn
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
        protocol:sendExtendedJSONOpcode(QUEST_OPCODE, data)
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

local function canGo(quest)
    return (state and state.level or 0) >= (quest.level or 0)
end

local function isOpen(quest)
    return canGo(quest) and not quest.done
end

local function statusOf(quest)
    if quest.done then
        return tr('Done'), '#7fd35a'
    end
    if not canGo(quest) then
        return tr('Level %d', quest.level), '#ff7a6b'
    end
    return tr('To do'), '#e0c060'
end

-- the monsters of a quest, the strongest first
local function strongestFirst(quest)
    local list = {}
    for _, monster in ipairs(quest.monsters or {}) do
        list[#list + 1] = monster
    end
    table.sort(list, function(a, b)
        if (a.experience or 0) ~= (b.experience or 0) then
            return (a.experience or 0) > (b.experience or 0)
        end
        return a.name < b.name
    end)
    return list
end

local function findQuest(key)
    for _, quest in ipairs(state and state.quests or {}) do
        if quest.key == key then
            return quest
        end
    end
end

-- the rewards the player picks from at the chest: his vocation's
local function rewardsFor(quest)
    local vocation = state and state.vocation or 'none'
    local list = {}
    for _, reward in ipairs(quest.rewards or {}) do
        if vocation == 'none' or reward.voc == '' or reward.voc == vocation then
            list[#list + 1] = reward
        end
    end
    return list
end

local function shown(quest)
    if filter == 'open' and not isOpen(quest) then
        return false
    end
    if filter == 'done' and not quest.done then
        return false
    end
    local query = window.search:getText():lower()
    if query ~= '' then
        local text = (nameOf(quest) .. ' ' .. table.concat((function()
            local names = {}
            for _, monster in ipairs(quest.monsters or {}) do
                names[#names + 1] = monster.name
            end
            for _, reward in ipairs(quest.rewards or {}) do
                names[#names + 1] = reward.name
            end
            for _, item in ipairs(quest.prize and quest.prize.items or {}) do
                names[#names + 1] = item.name
            end
            return names
        end)(), ' ')):lower()
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
    local quest = findQuest(selectedKey)
    card:setVisible(quest ~= nil)
    if not quest then
        return
    end
    card:setText(tr('Quest'))
    card.name:setText(nameOf(quest))
    card.level:setText(quest.prize and tr('Level %d challenge', quest.level) or tr('Level %d quest', quest.level))
    card.text:setText(textOf(quest))

    card.monsters:destroyChildren()
    local count = 0
    for index, monster in ipairs(strongestFirst(quest)) do
        if index > 3 then
            break
        end
        local line = g_ui.createWidget('QuestMonster', card.monsters)
        line.creature:setOutfit(outfitOf(monster.outfit))
        line.name:setText(monster.name)
        line.info:setText(tr('%d in the cave  -  %s XP each', monster.count, formatNumber(monster.experience)))
        count = index
    end
    -- as tall as its lines (34 each, 4 between), so the note below has room
    card.monsters:setHeight(math.max(1, count) * 38 - 4)

    card.rewards:destroyChildren()
    local cells = 0
    local extras = {}
    if quest.prize then
        -- a challenge: the same prize for every vocation, all of it
        card.rewardsTitle:setText(tr('Reward: all of this, for every vocation'))
        for _, item in ipairs(quest.prize.items or {}) do
            local cell = g_ui.createWidget('QuestReward', card.rewards)
            cell.item:setItemId(item.id)
            cell.count:setText(item.count > 1 and tostring(item.count) or '')
            cell:setTooltip(string.format('%dx %s', item.count, (item.name:gsub('^%l', string.upper))))
            cells = cells + 1
        end
        if (quest.prize.gold or 0) > 0 then
            extras[#extras + 1] = tr('+ %s gold in the bank', formatNumber(quest.prize.gold))
        end
        if (quest.prize.rarityXp or 0) > 0 then
            extras[#extras + 1] = tr('+ %d Rarity XP', quest.prize.rarityXp)
        end
    else
        card.rewardsTitle:setText(tr('Reward: pick one at the chest'))
        for _, reward in ipairs(rewardsFor(quest)) do
            local cell = g_ui.createWidget('QuestReward', card.rewards)
            cell.item:setItemId(reward.id)
            cell.count:setText('')
            local name = reward.name:gsub('^%l', string.upper)
            cell:setTooltip(reward.level > 0 and tr('%s (level %d)', name, reward.level) or name)
            cells = cells + 1
        end
    end
    -- as many lines of 38 px cells (4 between) as the rewards need
    local perLine = math.max(1, math.floor((card.rewards:getWidth() + 4) / 42))
    local lines = math.max(1, math.ceil(cells / perLine))
    card.rewards:setHeight(lines * 42 - 4)
    -- the gold and the Rarity XP of a prize, under its items
    card.prizeText:setText(table.concat(extras, '   '))
    card.prizeText:setHeight(#extras > 0 and 14 or 0)
    card.prizeText:setMarginTop(#extras > 0 and 3 or 0)

    if quest.steps and quest.steps > 0 then
        setStat(card.steps, tr('Way to the chest'), tr('about %d steps', quest.steps))
        card.steps:setVisible(true)
    else
        card.steps:setVisible(false)
    end
    -- the guards of a challenge's chest
    if quest.guards and (quest.guards.count or 0) > 0 then
        setStat(card.guards, tr('Guarding the chest'), string.format('%d x %s', quest.guards.count, quest.guards.name), '#ffb36b')
        card.guards:setVisible(true)
        card.guards:setHeight(20)
    else
        card.guards:setVisible(false)
        card.guards:setHeight(0)
    end

    if quest.done then
        card.note:setText(tr('You took the reward of this quest. The cave stays open for hunting.'))
        card.note:setColor('#7fd35a')
    elseif not canGo(quest) then
        card.note:setText(tr('This quest asks for level %d.', quest.level))
        card.note:setColor('#ff7a6b')
    else
        card.note:setText(tr('From a protection zone, or out of combat, the button takes you to the entrance of the cave. The chest is at its far end; the Voltar portals take you back to the temple.'))
        card.note:setColor('#b4afc3')
    end
    card.go:setEnabled(canGo(quest))
end

local function selectQuest(key)
    selectedKey = key
    renderCard()
end

local function updateStatuses()
    if not state then
        return
    end
    local open = 0
    for _, quest in ipairs(state.quests) do
        if isOpen(quest) then
            open = open + 1
        end
        local row = rows[quest.key]
        if row then
            local status, color = statusOf(quest)
            row.status:setText(status)
            row.status:setColor(color)
        end
    end
    if window then
        window.summary:setText(tr('%d quests, %d for you to do. Each one is a cave of the official map with a chest at its far end.', #state.quests, open))
    end
    local panel = modules.game_brevespanel
    if panel and panel.setFeatureState then
        panel.setFeatureState('quests', open > 0 and tostring(open) or nil, '#7fd35a')
    end
end

function refreshList()
    if not window or not state then
        return
    end
    local list = window.list
    list:destroyChildren()
    rows = {}
    local first, firstKey, keep
    local index = 0
    for _, quest in ipairs(state.quests) do
        if shown(quest) then
            index = index + 1
            local row = g_ui.createWidget(index % 2 == 0 and 'QuestRowEven' or 'QuestRow', list)
            local main = strongestFirst(quest)[1]
            if main then
                row.creature:setOutfit(outfitOf(main.outfit))
            end
            row.name:setText(nameOf(quest))
            local total = 0
            for _, monster in ipairs(quest.monsters or {}) do
                total = total + (monster.count or 0)
            end
            row.info:setText(quest.prize and tr('Level %d - %d monsters - challenge', quest.level, total)
                or tr('Level %d - %d monsters', quest.level, total))
            row.onFocusChange = function(widget, focused)
                if focused then
                    selectQuest(quest.key)
                end
            end
            row.onDoubleClick = function()
                selectQuest(quest.key)
                goSelected()
                return true
            end
            rows[quest.key] = row
            if not first then
                first, firstKey = row, quest.key
            end
            if quest.key == selectedKey then
                keep = row
            end
        end
    end
    updateStatuses()
    local focus = keep or first
    if focus then
        list:focusChild(focus, KeyboardFocusReason)
        list:ensureChildVisible(focus)
        selectQuest(focus == keep and selectedKey or firstKey)
    else
        selectQuest(nil)
    end
end

function setFilter(which)
    filter = which
    window.allTab:setChecked(which == 'all')
    window.openTab:setChecked(which == 'open')
    window.doneTab:setChecked(which == 'done')
    refreshList()
end

function goSelected()
    local quest = findQuest(selectedKey)
    if not quest then
        return
    end
    send({ action = 'go', key = quest.key })
end

-- ---------------------------------------------------------------- server

local handlers = {}

function handlers.state(data)
    state = data
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

local function onQuestOpcode(protocol, opcode, data)
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

function show()
    if not window then
        return
    end
    window:show()
    window:raise()
    window:focus()
    setOn(true)
    refreshList()
    send({ action = 'open' })
end

function hide()
    if not window then
        return
    end
    window:hide()
    setOn(false)
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
        panelButton = modules.game_brevespanel.addFeature('quests', toggle)
    end
    if not panelButton and not toolbarButton and modules.game_mainpanel then
        toolbarButton = modules.game_mainpanel.addToggleButton('questsButton', tr('Quests'),
            '/game_brevespanel/images/quests', toggle, false, 24)
    end
    -- ask once, quietly, so the bar row can show how many are left to do
    scheduleEvent(function()
        if g_game.isOnline() and not state then
            send({ action = 'open' })
        end
    end, 4500)
end

local function onGameEnd()
    hide()
    state = nil
    selectedKey = nil
    rows = {}
    if window then
        window.list:destroyChildren()
    end
end

-- a level up can open a quest: the bar row counts again
local function onLevelChange(localPlayer, level, levelPercent, oldLevel)
    if state and level ~= state.level then
        state.level = level
        if window and window:isVisible() then
            refreshList()
        else
            updateStatuses()
        end
    end
end

function init()
    window = g_ui.displayUI('quests')
    window:hide()
    window:setText(tr('Quests'))
    window.allTab:setChecked(true)
    window.card:setVisible(false)

    ProtocolGame.registerExtendedJSONOpcode(QUEST_OPCODE, onQuestOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    connect(LocalPlayer, { onLevelChange = onLevelChange })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    disconnect(LocalPlayer, { onLevelChange = onLevelChange })
    ProtocolGame.unregisterExtendedJSONOpcode(QUEST_OPCODE)
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
