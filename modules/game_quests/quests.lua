-- Quests: the quests of the server (data-otservbr-global/scripts/quests/
-- mythos_quests/quests_window.lua): the harder versions of the map's quests
-- (Pits of Inferno and Inquisition, Infernal and Abissal: a chest that gives
-- one reward of the player's choice and a prize, once per character) and the
-- quests of the teleport room, with what their scripts give. (Until
-- 2026-11-27 the list also had 24 caves with a chest at the far end; they
-- are hunts of the Hunts tab now.)
-- The window is laid out as Tibia's Quest Log (quests.otui): the list in a
-- captioned panel with, under it, a box that chooses which quests show, the
-- search and "show completed"; the chosen quest in the panel at the right,
-- captioned with its name: its picture, its facts as "name: value" lines,
-- its reward and its monsters, and the button that takes the player to it
-- (from a protection zone or out of combat, at the quest's level). One of
-- the three pages of the teleports (Hunts, Bosses, Quests: game_brevespanel
-- attachHub).
-- At the chest, the rewards to pick from come as cards with their pictures
-- (chest.otui).
-- Talks to the server through extended opcode QUEST_OPCODE with JSON payloads.

local QUEST_OPCODE = 141

local window
local panelButton
local toolbarButton
local state -- last "state" from the server
local selectedKey
local rows = {} -- quest key -> row of the list
local ui = {} -- the window's widgets, by id
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
        -- this client shows the quest chest in its window (chest.otui); the
        -- server gives the others the Tibia window
        data.chest = 1
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

-- The same colours in every window of ours for "can I do this?", Tibia's
-- own: green at or above the recommended level, orange between the entry
-- level and it, red below the entry level.
local READY, RISKY, LOCKED = '#60f860', '#f7a55f', '#f75f5f'

local function recommended(quest)
    return math.max(tonumber(quest.suggested) or 0, quest.level or 0)
end

local function readiness(quest)
    local level = state and state.level or 0
    if level < (quest.level or 0) then
        return LOCKED
    end
    return level >= recommended(quest) and READY or RISKY
end

-- the list's word at the right of a quest: only what is not the normal case
-- (done, a level too low, a challenge)
local function statusOf(quest)
    -- a quest of the teleport room has no level and nothing to mark
    if quest.wall then
        return '', '#909090'
    end
    if quest.done then
        return tr('Done'), READY
    end
    if not canGo(quest) then
        return tr('Level %d', quest.level), LOCKED
    end
    return '', '#909090'
end

-- the chosen quest's state in words, and its colour
local function stateOf(quest)
    if quest.done then
        return tr('Done'), READY
    end
    if not canGo(quest) then
        return tr('Opens at level %d', quest.level), LOCKED
    end
    if readiness(quest) == RISKY then
        return tr('Below recommended'), RISKY
    end
    return tr('To do'), READY
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

-- A sign of the teleport room may name several quests ("A / B / C"): the
-- first is the quest's name, the others go under it.
local function wallNames(quest)
    local parts = {}
    for part in (nameOf(quest) .. '/'):gmatch('([^/]+)/') do
        part = part:gsub('^%s+', ''):gsub('%s+$', '')
        if part ~= '' then
            parts[#parts + 1] = part
        end
    end
    local first = table.remove(parts, 1) or nameOf(quest)
    return first, parts
end

-- the picture of a quest of the teleport room: what it gives, or a closed
-- chest when the scripts do not tell
local UNKNOWN_REWARD = 2472

local function wallItem(quest)
    local reward = quest.rewards and quest.rewards[1]
    return reward and reward.id or UNKNOWN_REWARD
end

local function noteOf(quest)
    return (isPortuguese() and quest.text or quest.textEn) or ''
end

-- which quests the list shows, as the Quest Log's box under its list: all,
-- the harder versions of the map's quests, or the quests of the teleport room
local GROUPS = {
    { key = 'all', label = 'All quests' },
    { key = 'versions', label = 'Harder versions' },
    { key = 'wall', label = 'Quests of the teleport room' },
}

local function groupKey()
    local option = ui.group:getCurrentOption()
    return option and option.data or 'all'
end

local function shown(quest)
    local group = groupKey()
    if (group == 'versions' and quest.wall) or (group == 'wall' and not quest.wall) then
        return false
    end
    if quest.done and not ui.showDone:isChecked() then
        return false
    end
    local query = ui.search:getText():lower()
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
    ui.message:setText(text or '')
    ui.message:setColor(ok and READY or LOCKED)
    messageEvent = scheduleEvent(function()
        messageEvent = nil
        if window then
            ui.message:setText('')
        end
    end, 8000)
end

-- ---------------------------------------------------------------- rendering

local DOT = ' \183 '

local function titleCase(name)
    return (tostring(name or ''):gsub('^%l', string.upper))
end

-- a name that fits its place: the whole of it is in the tooltip
local function fitted(text, most)
    if #text > most then
        return text:sub(1, most - 2):gsub('[%s,]+$', '') .. '...'
    end
    return text
end

local function setHead(head, title, extra, color)
    head.title:setText(title or '')
    head.extra:setText(extra or '')
    head.extra:setColor(color or '#909090')
end

-- as tall as its cells: two a line, 36 px each and 4 between
local function fitGrid(grid)
    local lines = math.max(1, math.ceil(grid:getChildCount() / 2))
    grid:setHeight(lines * 40 - 4)
end

-- a cell of a grid of the chosen quest: an item, its name and one fact
local function addItemCell(grid, id, name, sub, color, tip)
    local cell = g_ui.createWidget('QuestCell', grid)
    cell.frame.item:setItemId(id)
    cell.name:setText(fitted(name, 18))
    cell.sub:setText(sub or '')
    cell.sub:setColor(color or '#909090')
    cell:setTooltip(tip or name)
    return cell
end

-- the odds that the reward comes out a rarity item (the server's
-- state.rarity: RarityConfig.questReward), for a quest whose rewards may
local function hasRareReward(quest)
    for _, reward in ipairs(quest.rewards or {}) do
        if reward.rare then
            return true
        end
    end
    return false
end

local function renderRarity(body, quest)
    -- the quest's own odds (a harder version), else the server's for all
    local rarity = quest.rarity or (state and state.rarity)
    local has = rarity ~= nil and hasRareReward(quest) and RarityOdds ~= nil
    body.rarityHead:setVisible(has)
    body.rarityBar:setVisible(has)
    if not has then
        return
    end
    local parts = RarityOdds.parts(rarity.grades, rarity.chance)
    setHead(body.rarityHead, tr('Chance to come out a rarity item'), RarityOdds.percent(rarity.chance), '#c0c0c0')
    body.rarityBar:setOdds(parts)
    -- the bar says it; each grade's chance is in its tooltip
    local lines = {}
    for _, part in ipairs(parts) do
        if part.chance > 0 then
            lines[#lines + 1] = part.label .. ' ' .. RarityOdds.percent(part.chance)
        end
    end
    body.rarityBar:setTooltip(table.concat(lines, '\n'))
    body.rarityHead:setTooltip(table.concat(lines, '\n'))
end

-- the reward a pick of the chest asks a level for: green when the player
-- has it, red when not
local function addPick(grid, reward)
    local name = titleCase(reward.name)
    local level = reward.level or 0
    if level > 0 then
        local has = (state and state.level or 0) >= level
        return addItemCell(grid, reward.id, name, tr('Level %d', level), has and READY or LOCKED,
            tr('%s (level %d)', name, level))
    end
    -- no level to say: the name alone, in the middle of the cell
    local cell = addItemCell(grid, reward.id, name, '', nil, name)
    cell.name:setMarginTop(11)
    return cell
end

-- the facts of the chosen quest beside its picture, a line each as "name:
-- value" (the Cyclopedia's way): its state, its levels, its numbers
local function renderFacts(facts, quest)
    facts:destroyChildren()
    local function fact(key, value, color, tip)
        if facts:getChildCount() >= 5 then
            return
        end
        local line = g_ui.createWidget('QuestFact', facts)
        line.key:setText(key .. ':')
        line.value:setText(value)
        line.value:setColor(color or '#c0c0c0')
        if tip then
            line:setTooltip(tip)
            line:setPhantom(false)
        end
    end
    if quest.wall then
        local _, others = wallNames(quest)
        fact(tr('Kind'), tr('Quest of the teleport room'))
        if #others > 0 then
            fact(tr('Also'), fitted(table.concat(others, ', '), 34), nil, table.concat(others, '\n'))
        end
        return
    end
    local text, color = stateOf(quest)
    fact(tr('State'), text, color)
    fact(tr('Recommended level'), tostring(recommended(quest)), readiness(quest) == RISKY and RISKY or nil)
    if recommended(quest) > (quest.level or 0) then
        fact(tr('Opens at level'), tostring(quest.level), not canGo(quest) and LOCKED or nil)
    end
    local total = 0
    for _, monster in ipairs(quest.monsters or {}) do
        total = total + (monster.count or 0)
    end
    if total > 0 then
        fact(tr('Monsters'), formatNumber(total))
    end
    -- a quest that asks for its bosses before the chest opens
    if quest.bosses and (quest.bosses.total or 0) > 0 then
        local left = quest.bosses.left or 0
        fact(tr('Bosses defeated'), string.format('%d / %d', quest.bosses.total - left, quest.bosses.total),
            left > 0 and RISKY or READY, tr('The chest opens when every boss of the quest is defeated.'))
    end
end

local function renderCard()
    local detail = ui.detail
    local quest = findQuest(selectedKey)
    for _, child in ipairs(detail:getChildren()) do
        child:setVisible(quest ~= nil)
    end
    if not quest then
        detail:setText(tr('No quest selected'))
        ui.bodyScroll:setVisible(false)
        return
    end
    local body = detail.body

    -- the panel's caption is the quest (the first name of a sign that has
    -- several), as the Quest Log's right panel
    local title = quest.wall and wallNames(quest) or nameOf(quest)
    detail:setText(fitted(title, 46))

    local main = strongestFirst(quest)[1]
    detail.picture.creature:setVisible(not quest.wall and main ~= nil)
    detail.picture.item:setVisible(quest.wall == true)
    if quest.wall then
        detail.picture.item:setItemId(wallItem(quest))
    elseif main then
        detail.picture.creature:setOutfit(outfitOf(main.outfit))
    end

    renderFacts(detail.facts, quest)

    -- the note of the sign (a quest of the teleport room), under the picture
    local note = quest.wall and noteOf(quest) or ''
    detail.note:setText(note)
    detail.note:setHeight(note ~= '' and 14 or 0)
    detail.note:setMarginTop(note ~= '' and 6 or 0)

    -- the reward: what the player picks at the chest, then what comes with it
    body.picks:destroyChildren()
    body.prize:destroyChildren()
    local picks = rewardsFor(quest)
    for _, reward in ipairs(picks) do
        addPick(body.picks, reward)
    end
    if quest.prize then
        for _, item in ipairs(quest.prize.items or {}) do
            local name = titleCase(item.name)
            addItemCell(body.prize, item.id, name, string.format('%dx', item.count or 1), nil,
                string.format('%dx %s', item.count or 1, name))
        end
        if (quest.prize.gold or 0) > 0 then
            addItemCell(body.prize, 3043, tr('Gold in the bank'), '+' .. formatNumber(quest.prize.gold), nil,
                tr('+ %s gold in the bank', formatNumber(quest.prize.gold)))
        end
        if (quest.prize.rarityXp or 0) > 0 then
            local cell = addItemCell(body.prize, 0, 'Rarity XP', '+' .. formatNumber(quest.prize.rarityXp), nil,
                tr('+ %d Rarity XP', quest.prize.rarityXp))
            cell.frame.item:setVisible(false)
            cell.frame.icon:setImageSource('/game_bosses/images/star_on')
            cell.frame.icon:setVisible(true)
        end
    end
    local hasPicks, hasPrize = #picks > 0, body.prize:getChildCount() > 0
    body.pickHead:setVisible(hasPicks)
    body.picks:setVisible(hasPicks)
    body.prizeHead:setVisible(hasPrize)
    body.prize:setVisible(hasPrize)
    body.prizeHead:setMarginTop(hasPicks and 10 or 0)
    if quest.wall then
        setHead(body.pickHead, tr('Reward of the quest'), #picks == 1 and tr('1 item') or tr('%d items', #picks))
    elseif hasPrize then
        -- a harder version: one item to pick, and the prize on top
        local left = quest.bosses and (quest.bosses.total or 0) > 0 and (quest.bosses.left or 0) or 0
        setHead(body.pickHead, #picks > 1 and tr('Pick one at the chest') or tr('From the chest'),
            left > 0 and tr('%d bosses left', left) or '', RISKY)
        setHead(body.prizeHead, hasPicks and tr('And you also get') or tr('Reward'),
            hasPicks and '' or tr('the same for every vocation'))
    else
        setHead(body.pickHead, tr('Reward'), #picks > 1 and tr('pick 1 at the chest') or '')
    end
    fitGrid(body.picks)
    fitGrid(body.prize)

    renderRarity(body, quest)
    body.rarityHead:setMarginTop((hasPicks or hasPrize) and 10 or 0)

    -- the monsters of the cave: the four strongest
    body.monsters:destroyChildren()
    local monsters = strongestFirst(quest)
    for index, monster in ipairs(monsters) do
        if index > 4 then
            break
        end
        local cell = g_ui.createWidget('QuestCell', body.monsters)
        cell.frame.item:setVisible(false)
        cell.frame.creature:setVisible(true)
        cell.frame.creature:setOutfit(outfitOf(monster.outfit))
        cell.name:setText(fitted(monster.name, 18))
        cell.sub:setText(string.format('%dx', monster.count) .. DOT .. formatNumber(monster.experience) .. ' XP')
        cell:setTooltip(tr('%s: %d in the cave, %s XP each', monster.name, monster.count, formatNumber(monster.experience)))
    end
    local hasMonsters = #monsters > 0
    body.monstersHead:setVisible(hasMonsters)
    body.monsters:setVisible(hasMonsters)
    setHead(body.monstersHead, tr('Monsters'), #monsters > 4 and tr('the %d strongest of %d', 4, #monsters) or '')
    fitGrid(body.monsters)

    -- a quest of the teleport room with no reward to show
    local nothing = quest.wall and not hasPicks
    body.nothing:setVisible(nothing)
    body.nothing:setText(nothing and tr('The reward of this quest is not listed.') or '')

    -- back to the top; the bar scrolls only when there is more than fits
    ui.bodyScroll:setValue(0)

    detail.go:setEnabled(canGo(quest))
    detail.go:setTooltip(tr('From a protection zone or out of combat. The Voltar portals in the cave take you back to the temple.'))
end

local function selectQuest(key)
    selectedKey = key
    renderCard()
end

local function updateStatuses()
    if not state then
        return
    end
    local open, done, versions = 0, 0, 0
    for _, quest in ipairs(state.quests) do
        -- the quests of the teleport room are not counted: nothing says
        -- which of them the character did
        if not quest.wall then
            versions = versions + 1
            if quest.done then
                done = done + 1
            elseif isOpen(quest) then
                open = open + 1
            end
        end
        local row = rows[quest.key]
        if row then
            local status, color = statusOf(quest)
            row.status:setText(status)
            row.status:setColor(color)
        end
    end
    if window then
        -- as the Quest Log's "Quests completed: N", of those that are marked
        ui.summary:setText(tr('Completed: %d of %d', done, versions))
    end
    local panel = modules.game_brevespanel
    if panel and panel.setFeatureState then
        panel.setFeatureState('quests', open > 0 and tostring(open) or nil, '#7fd35a')
    end
end

-- one row of the list
local function addRow(list, quest, even)
    local row = g_ui.createWidget(even and 'QuestRowEven' or 'QuestRow', list)
    if quest.wall then
        -- the item the quest gives, in the monster's place
        row.frame.creature:setVisible(false)
        row.frame.item:setItemId(wallItem(quest))
        row.frame.item:setVisible(true)
        local title, others = wallNames(quest)
        row.name:setText(title)
        -- under the name: the other quests of the sign, its note, or what
        -- the quest gives
        local info = #others > 0 and ('+ ' .. table.concat(others, ', ')) or noteOf(quest)
        if info == '' then
            local names = {}
            for _, item in ipairs(quest.rewards or {}) do
                names[#names + 1] = titleCase(item.name)
            end
            info = table.concat(names, ', ')
        end
        row.info:setText(fitted(info, 46))
        if info == '' then
            row.name:setMarginTop(12)
        end
    else
        local main = strongestFirst(quest)[1]
        if main then
            row.frame.creature:setOutfit(outfitOf(main.outfit))
        end
        row.name:setText(nameOf(quest))
        -- the level the quest really asks for, in the readiness colour
        row.info:setText(tr('Level %d', recommended(quest)))
        row.info:setColor(readiness(quest))
    end
    row.onFocusChange = function(widget, focused)
        -- the chosen row in white, as Tibia's lists
        widget.name:setColor(focused and '#ffffff' or '#c0c0c0')
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
    return row
end

function refreshList()
    if not window or not ui.list then
        return
    end
    -- the list did not come yet (the window asks for it when it opens)
    if not state then
        ui.empty:setText(tr('Loading the quests...'))
        ui.empty:setVisible(true)
        renderCard()
        return
    end
    local list = ui.list
    list:destroyChildren()
    rows = {}
    local first, firstKey, keep
    local count = 0
    for _, quest in ipairs(state.quests) do
        if shown(quest) then
            count = count + 1
            local row = addRow(list, quest, count % 2 == 0)
            if not first then
                first, firstKey = row, quest.key
            end
            if quest.key == selectedKey then
                keep = row
            end
        end
    end
    updateStatuses()
    ui.empty:setVisible(first == nil)
    ui.empty:setText(tr('No quest found.'))
    local focus = keep or first
    if focus then
        list:focusChild(focus, KeyboardFocusReason)
        list:ensureChildVisible(focus)
        selectQuest(focus == keep and selectedKey or firstKey)
    else
        selectQuest(nil)
    end
end

function clearSearch()
    if ui.search then
        ui.search:setText('')
    end
end

function goSelected()
    local quest = findQuest(selectedKey)
    if not quest then
        return
    end
    send({ action = 'go', key = quest.key })
end

-- ---------------------------------------------------------------- the chest

-- the reward chest at the end of a quest: the rewards of the player's
-- vocation, each a card with its picture; he picks one (chest.otui)
local chestWindow
local chestOffer -- the last "chest" from the server
local chosenId
local CARD_W, CARD_H, CARD_GAP, CARDS_PER_ROW = 150, 196, 10, 4

-- the first stats of a reward's card (game_itemcard), in the player's
-- language, a line each: a list ("fire -10%, earth +10%") shows its first
-- part (the whole card is on the mouse)
local function statsOf(card)
    local itemcard = modules.game_itemcard
    local lines = {}
    for index, stat in ipairs(card and card.stats or {}) do
        if index > 3 then
            break
        end
        local label = itemcard and itemcard.translate and itemcard.translate(stat.label) or stat.label
        local value = stat.value or ''
        local first = value:match('^([^,]+),')
        if first then
            value = first .. '...'
        end
        lines[#lines + 1] = value ~= '' and (label .. ' ' .. value) or label
    end
    return table.concat(lines, '\n')
end

-- the whole card of a reward, beside the chest window (not over the others)
local function showItemCard(reward)
    local itemcard = modules.game_itemcard
    if reward.card and chestWindow and itemcard and itemcard.showFor then
        itemcard.showFor(reward.card, chestWindow)
    end
end

-- the reward under the mouse (by where the mouse is: a click changes the
-- hover states for a moment)
local shownReward
local function rewardUnderMouse()
    if not chestWindow or not chestOffer then
        return nil
    end
    local mouse = g_window.getMousePosition()
    for index, child in ipairs(chestWindow.rewards:getChildren()) do
        if child:containsPoint(mouse) then
            return chestOffer.rewards[index]
        end
    end
    return nil
end

-- the card of the reward under the mouse, or none; `again` shows it even if
-- it was shown (a click takes it off)
local function refreshItemCard(again)
    local reward = rewardUnderMouse()
    if not reward then
        if shownReward then
            local itemcard = modules.game_itemcard
            if itemcard and itemcard.hide then
                itemcard.hide()
            end
        end
        shownReward = nil
    elseif again or reward ~= shownReward then
        shownReward = reward
        showItemCard(reward)
    end
end

local function hideItemCard()
    local itemcard = modules.game_itemcard
    if itemcard and itemcard.hide then
        itemcard.hide()
    end
end

function closeChest()
    if chestWindow then
        hideItemCard()
        chestWindow:destroy()
        chestWindow = nil
    end
    chestOffer, chosenId, shownReward = nil, nil, nil
end

local function choose(id)
    chosenId = id
    if chestWindow then
        chestWindow.pickButton:setEnabled(id ~= nil)
        chestWindow.result:setText('')
    end
end

function pickChosen()
    if not chestOffer or not chosenId or not chestWindow then
        return
    end
    -- until the server answers
    chestWindow.pickButton:setEnabled(false)
    send({ action = 'pick', key = chestOffer.key, id = chosenId })
end

local function showChest(data)
    closeChest()
    chestOffer = data
    chestWindow = g_ui.displayUI('chest')
    chestWindow:setText(nameOf(data))
    chestWindow.subtitle:setText(tr('Pick your reward: one per character.'))
    chestWindow.hint:setText('')
    local rewards = data.rewards or {}
    local perRow = math.max(1, math.min(#rewards, CARDS_PER_ROW))
    local rowsOf = math.max(1, math.ceil(#rewards / perRow))
    chestWindow.rewards:setSize({
        width = perRow * CARD_W + (perRow - 1) * CARD_GAP,
        height = rowsOf * CARD_H + (rowsOf - 1) * CARD_GAP,
    })
    for _, reward in ipairs(rewards) do
        local card = g_ui.createWidget('QuestChestCard', chestWindow.rewards)
        card.item:setItemId(reward.id)
        card.name:setText((reward.name:gsub('^%l', string.upper)))
        card.level:setText((reward.level or 0) > 0 and tr('Level %d', reward.level) or tr('Any level'))
        card.stats:setText(statsOf(reward.card))
        card.onFocusChange = function(widget, focused)
            if focused then
                choose(reward.id)
            end
        end
        -- the click took the card off: back while the mouse stays on it
        card.onMouseRelease = function()
            scheduleEvent(function()
                refreshItemCard(true)
            end, 40)
            return false
        end
        card.onDoubleClick = function()
            choose(reward.id)
            pickChosen()
            return true
        end
        -- all of it, as a look shows it
        card.onHoverChange = function()
            scheduleEvent(function()
                refreshItemCard(false)
            end, 40)
        end
    end
    -- the odds that the reward comes out a rarity item
    local rarity = data.rarity
    local rare = false
    for _, reward in ipairs(rewards) do
        rare = rare or reward.rare
    end
    local oddsHeight = 0
    if rarity and rare and RarityOdds then
        local parts = RarityOdds.parts(rarity.grades, rarity.chance)
        chestWindow.rarityTitle:setText(tr('%s chance to come out a rarity item', RarityOdds.percent(rarity.chance)))
        chestWindow.rarityBar:setOdds(parts)
        local first, second = {}, {}
        for index, part in ipairs(parts) do
            table.insert(index <= 3 and first or second, part)
        end
        chestWindow.rarityText:setColoredText(RarityOdds.legend(first) .. '\n' .. RarityOdds.legend(second))
        oddsHeight = 10 + 14 + 3 + 8 + 3 + 28
    else
        for _, id in ipairs({ 'rarityTitle', 'rarityBar', 'rarityText' }) do
            chestWindow[id]:setVisible(false)
            chestWindow[id]:setHeight(0)
            chestWindow[id]:setMarginTop(0)
        end
    end
    -- room for the title, the cards, the hint, the odds and the buttons
    chestWindow:setSize({
        width = math.max(420, chestWindow.rewards:getWidth() + 32),
        height = chestWindow.rewards:getHeight() + 136 + oddsHeight,
    })
    choose(nil)
    chestWindow:raise()
    chestWindow:focus()
end

-- ---------------------------------------------------------------- server

local handlers = {}

function handlers.chest(data)
    showChest(data)
end

function handlers.chestResult(data)
    if not chestWindow then
        return
    end
    if data.ok then
        closeChest()
        showMessage(data.text, true)
    else
        chestWindow.result:setText(data.text or '')
        chestWindow.pickButton:setEnabled(chosenId ~= nil)
    end
end

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
    if modules.game_brevespanel and modules.game_brevespanel.attachHub then
        modules.game_brevespanel.attachHub(window, 'quests', hide)
    end
    if not panelButton and not toolbarButton and modules.game_mainpanel then
        toolbarButton = modules.game_mainpanel.addToggleButton('questsButton', tr('Quests'),
            '/game_brevespanel/images/quests', toggle, false, 24)
    end
    -- ask once, quietly, so the bar row can show how many are left to do;
    -- each client at its own moment (g_game.spreadDelay): a login rush
    scheduleEvent(function()
        if g_game.isOnline() and not state then
            send({ action = 'open' })
        end
    end, g_game.spreadDelay and g_game.spreadDelay(4000, 10000) or 4500)
end

local function onGameEnd()
    hide()
    closeChest()
    state = nil
    selectedKey = nil
    rows = {}
    if window then
        ui.list:destroyChildren()
        renderCard()
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
    for _, id in ipairs({ 'search', 'summary', 'message', 'group', 'showDone', 'list', 'listScroll', 'empty', 'detail',
        'bodyScroll' }) do
        ui[id] = window:recursiveGetChildById(id)
    end
    for _, group in ipairs(GROUPS) do
        ui.group:addOption(tr(group.label), group.key)
    end
    renderCard()

    ProtocolGame.registerExtendedJSONOpcode(QUEST_OPCODE, onQuestOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    connect(LocalPlayer, { onLevelChange = onLevelChange })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    closeChest()
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
        ui = {}
    end
end
