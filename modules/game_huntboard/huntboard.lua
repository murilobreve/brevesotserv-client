-- Hunt Board: per-monster experience/loot rates that re-roll every few hours,
-- with a TP to each monster's hunt (the Hunts TP list: one place for the hunt
-- teleport rooms of every town), the hourly/daily/monthly hunting leaderboard
-- and the online coin reward.
-- Talks to the server scripts in data-otservbr-global/scripts/huntboard
-- through extended opcode HUNT_OPCODE with JSON payloads.

local HUNT_OPCODE = 121
local PAGE_SIZE = 40
-- the server ignores a request that comes within 300 ms of the previous one
-- (huntboard/02_events.lua), so requests leave at least this far apart
local SEND_INTERVAL = 350

-- The filters panel: which monsters (showBox), which rates (rateBox), an
-- element the monster is weak to or does not resist (elementBox), the sort,
-- and ranges of XP and gold per kill and of the recommended level.
local SHOWS = {
    { key = 'tp', label = 'Hunts with TP' },
    { key = 'all', label = 'All monsters' },
    { key = 'noBosses', label = 'All, no bosses' },
}

local RATE_FILTERS = {
    { key = 'any', label = 'Any rate' },
    { key = 'xp', label = 'Boosted XP (1.5x+)' },
    { key = 'loot', label = 'Boosted loot (1.5x+)' },
    { key = 'both', label = 'Double boost (2x+ both)' },
    { key = 'jackpot', label = 'Jackpot' },
    { key = 'nerfed', label = 'Below 1x' },
}

local SORTS = {
    { key = 'combined', label = 'Best combined rate' },
    { key = 'xp', label = 'Highest XP rate' },
    { key = 'loot', label = 'Highest loot rate' },
    { key = 'perKill', label = 'Most XP per kill' },
    { key = 'gold', label = 'Most gold per kill' },
    { key = 'xpPerHp', label = 'Most XP per health' },
    { key = 'level', label = 'Lowest recommended level' },
    { key = 'exp', label = 'Base experience' },
    { key = 'hp', label = 'Most health' },
    { key = 'tp', label = 'Most hunts with TP' },
    { key = 'name', label = 'Name' },
}
-- sorts whose first rows get no medal colour
local NO_MEDALS = { name = true, level = true }

-- the "My level" button: the hunts of the daily task's level window
-- (hunt_tasks/00_config.lua, daily.levelWindow) and the wiki's "near my level"
local MY_LEVEL = { 0.55, 1.1 }

local PERIOD_LABELS = { hour = 'Hourly', day = 'Daily', month = 'Monthly' }
local MEDALS = {
    { text = '#ffe066' },
    { text = '#f0f0f0' },
    { text = '#ffc08a' },
}

local window
local filtersShown = false -- the filter panel and the detail columns (setFiltersShown)
local quickReady = false -- the level of the player went into the list once
local updateQuickBar
local toolbarButton -- old single button, when game_brevespanel is missing
local sectionButtons = {} -- rates / board rows in the Mythos panel
local toast
local toastEvent
local tickEvent

local currentTab = 'rates'
local currentPeriod = 'hour'
local rates = { monsters = {}, nextAt = 0, interval = 7200, max = 100, lootMax = 30, rareMax = 40, slot = -1 }
local filtered = {}
local currentSort = 'combined'
local sortDesc = true -- the biggest first; a second click on a column title reverses it
local page = 1
local boards = {}
local timeOffset = 0 -- server time - local time
local online = { minutes = 0, goal = 60, amount = 1 }
local filterEvent
local ratesEvent
local sendQueue = {}
local sendEvent
local lastSendAt = 0
local tpReadyAt = 0 -- os.time() when the next hunt teleport is allowed
local tpButtons = {} -- the TP buttons of the page on screen
local tpMessageEvent

-- ---------------------------------------------------------------- helpers

local function formatNumber(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    while true do
        local replaced, count = text:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
        text = replaced
        if count == 0 then
            return text
        end
    end
end

local function formatShort(value)
    value = tonumber(value) or 0
    if value >= 1000000000 then
        return string.format('%.2fB', value / 1000000000)
    elseif value >= 1000000 then
        return string.format('%.2fM', value / 1000000)
    elseif value >= 100000 then
        return string.format('%.1fk', value / 1000)
    end
    return formatNumber(value)
end

-- The damage a monster takes from each element, in percent (100 = normal,
-- 0 = immune): the server sends the ones that are not 100, "ice:120,fire:80".
-- The colours are the monster wiki's.
local ELEMENTS = {
    physical = { 'Physical', '#b8bec6' },
    earth = { 'Earth', '#6cd13a' },
    fire = { 'Fire', '#ff6a2a' },
    death = { 'Death', '#a45ad6' },
    energy = { 'Energy', '#b56bff' },
    holy = { 'Holy', '#ffd84a' },
    ice = { 'Ice', '#52dcff' },
    lifedrain = { 'Life drain', '#e0485a' },
}
-- Every row has a column for each element a player deals, in the
-- Cyclopedia's order, under the element's icon in the list header
-- (huntboard.otui, ElementCells and ElementHead): the change in damage the
-- monster takes, "+10" green for a weakness, "-15" amber for a resistance,
-- "x" grey for an immunity, a faint dot for normal damage. Life drain, which
-- only monsters deal, is in the tooltip with the rest.
local ELEMENT_COLUMNS = { 'physical', 'earth', 'fire', 'death', 'energy', 'holy', 'ice' }
local IMMUNE_MARK = '\215' -- the multiplication sign of the fonts (cp1252)

-- the element filter: weak to it (takes more than 100%), or at least no
-- resistance (100% or more)
local ELEMENT_FILTERS = { { key = '', label = 'Any element' } }
for _, key in ipairs(ELEMENT_COLUMNS) do
    ELEMENT_FILTERS[#ELEMENT_FILTERS + 1] = { key = 'weak:' .. key, label = 'Weak to ' .. key }
end
for _, key in ipairs(ELEMENT_COLUMNS) do
    ELEMENT_FILTERS[#ELEMENT_FILTERS + 1] = { key = 'open:' .. key, label = 'No resistance to ' .. key }
end

-- what to hunt it with first (the biggest weakness first), then what not
-- to use: immunities, then the strongest resistances
local function elementOrder(a, b)
    local weakA, weakB = a.taken > 100, b.taken > 100
    if weakA ~= weakB then
        return weakA
    end
    if a.taken ~= b.taken then
        return weakA and a.taken > b.taken or (not weakA and a.taken < b.taken)
    end
    return a.key < b.key
end

-- the list for the tooltip and the damage taken by element key; nil when
-- the server sent none (an older server): nothing is said then
local function parseElements(text)
    if type(text) ~= 'string' then
        return nil
    end
    local list, taken = {}, {}
    for key, value in text:gmatch('(%a+):(%d+)') do
        if ELEMENTS[key] then
            value = tonumber(value)
            list[#list + 1] = { key = key, taken = value }
            taken[key] = value
        end
    end
    table.sort(list, elementOrder)
    return list, taken
end

local function elementChange(entry)
    if entry.taken == 0 then
        return tr('immune')
    end
    return string.format('%+d%%', entry.taken - 100)
end

-- The elements of a row as a few marks (huntboard.otui, ElementChip): the
-- weaknesses first, the biggest first, then a gap and what not to use, the
-- immunities and the strongest resistances first (the order of `list`).
-- An element the monster takes normal damage from has no mark.
local CHIP_ELEMENT = {}
for _, key in ipairs(ELEMENT_COLUMNS) do
    CHIP_ELEMENT[key] = true
end
local CHIP_STEP, CHIP_GAP = 17, 6

local function fillElementChips(holder, list)
    if not list then
        return
    end
    local x, weakDone = 0, false
    for _, entry in ipairs(list) do
        if CHIP_ELEMENT[entry.key] and entry.taken ~= 100 then
            local weak, immune = entry.taken > 100, entry.taken == 0
            if not weak and not weakDone then
                weakDone = true
                x = x > 0 and x + CHIP_GAP or 0
            end
            local chip = g_ui.createWidget('ElementChip', holder)
            chip:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            chip:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
            chip:setMarginLeft(x)
            chip.icon:setImageSource('/game_cyclopedia/images/bestiary/icons/monster-icon-' .. entry.key .. '-resist')
            local name = tr(ELEMENTS[entry.key][1])
            if weak then
                -- a big weakness stands out
                chip:setBorderColor(entry.taken >= 115 and '#7fd35a' or '#3f8a36')
                chip:setBackgroundColor('#16301a')
                chip:setTooltip(tr('%s: it takes %d%% more damage', name, entry.taken - 100))
            elseif immune then
                chip:setBorderColor('#4a4458')
                chip.icon:setOpacity(0.35)
                chip:setTooltip(tr('%s: immune', name))
            else
                chip:setBorderColor(entry.taken <= 60 and '#d9772e' or '#8a6a2a')
                chip:setBackgroundColor('#30220f')
                chip.icon:setOpacity(0.75)
                chip:setTooltip(tr('%s: it takes %d%% less damage', name, 100 - entry.taken))
            end
            x = x + CHIP_STEP
        end
    end
end

-- the tooltip's lines: what it is weak to, what it resists, what it is immune to
local function elementLines(list)
    local weak, resists, immune = {}, {}, {}
    for _, entry in ipairs(list) do
        local name = tr(ELEMENTS[entry.key][1])
        if entry.taken == 0 then
            immune[#immune + 1] = name
        elseif entry.taken > 100 then
            weak[#weak + 1] = name .. ' ' .. elementChange(entry)
        else
            resists[#resists + 1] = name .. ' ' .. elementChange(entry)
        end
    end
    local lines = {}
    if #weak > 0 then
        lines[#lines + 1] = tr('Weak to: %s', table.concat(weak, ', '))
    end
    if #resists > 0 then
        lines[#lines + 1] = tr('Resists: %s', table.concat(resists, ', '))
    end
    if #immune > 0 then
        lines[#lines + 1] = tr('Immune to: %s', table.concat(immune, ', '))
    end
    if #lines == 0 then
        lines[1] = tr('Takes normal damage from every element')
    end
    return table.concat(lines, '\n')
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    local secs = seconds % 60
    if days > 0 then
        return string.format('%dd %02dh %02dm', days, hours, minutes)
    end
    return string.format('%02d:%02d:%02d', hours, minutes, secs)
end

local function serverNow()
    return os.time() + timeOffset
end

-- from this experience rate (rounded) a monster counts as very strong: red
-- star with a "!", and the strong shader (the server's rates go up to 5x)
local RATE_ALERT = 4

-- inside this window XP is violet and loot gold, brighter the higher the
-- rate; red stays for real danger (the very strong monster on the map)
local function ramp(t, from, to)
    local function mix(k)
        return math.floor(from[k] + (to[k] - from[k]) * t + 0.5)
    end
    return string.format('#%02x%02x%02x', mix(1), mix(2), mix(3))
end

local function xpTone(tenths)
    return ramp(math.max(0, math.min(1, (tenths - 10) / 90)), { 120, 108, 140 }, { 196, 170, 255 })
end

-- loot goes from 1x to 3x (its own roll since 2026-10-31)
local function lootTone(tenths)
    return ramp(math.max(0, math.min(1, (tenths - 10) / 20)), { 138, 122, 85 }, { 235, 205, 130 })
end

-- rare monsters go from 1x to 4x: pale grey to the rare monsters' violet
local function rareTone(tenths)
    return ramp(math.max(0, math.min(1, (tenths - 10) / 30)), { 120, 128, 150 }, { 120, 220, 255 })
end

local function multText(tenths)
    return string.format('x%.1f', tenths / 10)
end

local function flushSendQueue()
    sendEvent = nil
    local wait = lastSendAt + SEND_INTERVAL - g_clock.millis()
    if wait > 0 then
        sendEvent = scheduleEvent(flushSendQueue, wait)
        return
    end

    local data = table.remove(sendQueue, 1)
    if not data then
        return
    end
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(HUNT_OPCODE, data)
        lastSendAt = g_clock.millis()
    end
    if #sendQueue > 0 then
        sendEvent = scheduleEvent(flushSendQueue, SEND_INTERVAL)
    end
end

local function send(data)
    -- a newer request of the same kind replaces one still waiting, so after
    -- Hourly, Monthly, Daily clicked quickly only Daily is sent after Hourly
    for i, queued in ipairs(sendQueue) do
        if queued.action == data.action then
            table.remove(sendQueue, i)
            break
        end
    end
    table.insert(sendQueue, data)
    if not sendEvent then
        flushSendQueue()
    end
end

local function clearSendQueue()
    if sendEvent then
        removeEvent(sendEvent)
        sendEvent = nil
    end
    sendQueue = {}
    -- the server forgets the cooldown on logout, so the next login starts fresh
    lastSendAt = 0
end

local function outfitOf(monster)
    return {
        type = monster.type,
        auxType = monster.typeEx,
        head = monster.head,
        body = monster.body,
        legs = monster.legs,
        feet = monster.feet,
        addons = monster.addons,
        mount = 0,
    }
end

local function setBar(bar, tenths, maxTenths, colorOf)
    maxTenths = math.max(maxTenths or rates.max or 100, 10)
    local inner = bar:getWidth() - 2
    local color = (colorOf or xpTone)(tenths)
    bar.fill:setWidth(math.max(1, math.floor(inner * math.min(tenths, maxTenths) / maxTenths)))
    bar.fill:setBackgroundColor(color .. 'b0')
    bar.mark:setMarginLeft(1 + math.floor(inner * 10 / maxTenths))
    bar.value:setText(multText(tenths))
end

-- ---------------------------------------------------------------- rates tab

-- A number typed in a range box: "6000", "6.000" and "6,000" (the marks
-- only group thousands), "6k", "1,5k", "2kk" and "2m" (Tibia's kk is a
-- million). nil when the box is empty, false when it is not a number.
local SUFFIXES = { [''] = 1, k = 1000, kk = 1000000, m = 1000000 }

local function parseAmount(text)
    text = (tostring(text or ''):lower():gsub('%s+', ''))
    if text == '' then
        return nil
    end
    local digits, suffix = text:match('^(%d[%d%.,]*)(%a*)$')
    local multiplier = digits and SUFFIXES[suffix]
    if not multiplier then
        return false
    end
    local value
    if multiplier > 1 then
        -- "1,5k" and "1.5k": here the mark is the decimal point
        value = tonumber((digits:gsub(',', '.')))
    else
        value = tonumber((digits:gsub('[%.,]', '')))
    end
    return value and math.floor(value * multiplier + 0.5) or false
end

local INPUT_COLOR, BAD_INPUT_COLOR = '#e6e2ee', '#ff7a6b'

-- the two boxes of a range; a box that is not a number turns red and is
-- left out
local function readRange(minEdit, maxEdit)
    local low, high = parseAmount(minEdit:getText()), parseAmount(maxEdit:getText())
    minEdit:setColor(low == false and BAD_INPUT_COLOR or INPUT_COLOR)
    maxEdit:setColor(high == false and BAD_INPUT_COLOR or INPUT_COLOR)
    return low or nil, high or nil
end

local function inRange(value, low, high)
    value = value or 0
    return (not low or value >= low) and (not high or value <= high)
end

local function comboKey(combo, default)
    local option = combo:getCurrentOption()
    return option and option.data or default
end

-- every choice of the filters panel, read once per filtering
local function readFilters(section)
    local filters = {
        search = window.ratesPanel.quickBar.searchEdit:getText():lower():trim(),
        show = comboKey(section.showBox, 'tp'),
        rate = comboKey(section.rateBox, 'any'),
    }
    local mode, element = comboKey(section.elementBox, ''):match('^(%a+):(%a+)$')
    if element then
        filters.element, filters.weak = element, mode == 'weak'
    end
    filters.xpMin, filters.xpMax = readRange(section.xpMin, section.xpMax)
    filters.goldMin, filters.goldMax = readRange(section.goldMin, section.goldMax)
    filters.levelMin, filters.levelMax = readRange(section.levelMin, section.levelMax)
    return filters
end

local function matchesFilter(monster, filters)
    if (filters.show == 'tp' and monster.tp <= 0) or (filters.show == 'noBosses' and monster.boss == 1) then
        return false
    end
    if filters.search ~= '' and not monster.lname:find(filters.search, 1, true) then
        return false
    end
    local rate = filters.rate
    if (rate == 'xp' and monster.xp < 15) or (rate == 'loot' and monster.loot < 15)
        or (rate == 'both' and (monster.xp < 20 or monster.loot < 20))
        or (rate == 'jackpot' and monster.xp < 35 and monster.loot < 25)
        or (rate == 'nerfed' and monster.xp >= 10 and monster.loot >= 10) then
        return false
    end
    if filters.element then
        -- an older server sends no elements: nothing to filter by
        local taken = monster.taken and (monster.taken[filters.element] or 100)
        if not taken or taken < 100 or (filters.weak and taken == 100) then
            return false
        end
    end
    if not inRange(monster.perKill, filters.xpMin, filters.xpMax)
        or not inRange(monster.goldPerKill, filters.goldMin, filters.goldMax) then
        return false
    end
    -- the level of a monster an older server does not send stays in
    if monster.lvl and not inRange(monster.lvl, filters.levelMin, filters.levelMax) then
        return false
    end
    return true
end

-- Every column of the list sorts (a click on its title, a second one
-- reverses it) and the panel's sort list holds the same keys.
-- key -> { a monster's value, biggest first by default, tie-break (biggest first) }
local SORT_SPECS = {
    combined = { function(m) return m.xp + m.loot end, true, function(m) return m.perKill end },
    xp = { function(m) return m.xp end, true, function(m) return m.perKill end },
    loot = { function(m) return m.loot end, true, function(m) return m.goldPerKill or 0 end },
    rare = { function(m) return m.rare end, true, function(m) return m.xp end },
    perKill = { function(m) return m.perKill end, true },
    gold = { function(m) return m.goldPerKill end, true },
    xpPerHp = { function(m) return m.xpPerHp end, true },
    level = { function(m) return m.lvl end, false },
    hp = { function(m) return m.hpNow end, true },
    spawns = { function(m) return m.spawns end, true },
    exp = { function(m) return m.exp end, true },
    name = { function(m) return m.lname end, false },
    tp = { function(m) return m.tp > 0 and (m.tpHunts and #m.tpHunts or 1) or 0 end, true },
}
-- an element's column: the damage the monster takes from it, the weakest first
for _, key in ipairs(ELEMENT_COLUMNS) do
    SORT_SPECS['el:' .. key] = { function(m) return m.taken and (m.taken[key] or 100) end, true }
    SORTS[#SORTS + 1] = { key = 'el:' .. key, label = 'Weakest to ' .. key }
end

local function sorterOf(key, desc)
    local spec = SORT_SPECS[key] or SORT_SPECS.combined
    local value, tie = spec[1], spec[3]
    return function(a, b)
        local va, vb = value(a), value(b)
        if va ~= vb then
            -- a number an older server does not send: always last
            if va == nil then
                return false
            elseif vb == nil then
                return true
            end
            if desc then
                return va > vb
            end
            return va < vb
        end
        if tie then
            local ta, tb = tie(a), tie(b)
            if ta ~= tb then
                return ta > tb
            end
        end
        return a.lname < b.lname
    end
end

-- the column titles that sort: { widget id, sort key, title, what it is }
local SORT_HEADS = {
    { 'sortName', 'name', 'Monster', 'Name of the monster.' },
    { 'sortLevel', 'level', 'Lvl', 'The level the Hunt Tasks recommend for the monster.' },
    { 'sortHp', 'hp', 'HP', 'Its health while this rate lasts.' },
    { 'sortXpKill', 'perKill', 'XP/kill', 'Experience per kill at this rate, before your own bonuses.' },
    { 'sortGoldKill', 'gold', 'Gold/kill', 'Gold per kill at this loot rate, at the prices Gersao pays.' },
    { 'sortXpRate', 'xp', 'XP rate', 'The experience rate of this roll.' },
    { 'sortLootRate', 'loot', 'Loot rate', 'The loot rate of this roll.' },
    { 'sortRareRate', 'rare', 'Rare', 'How much more often this monster comes back Pale, Ashen or Obsidian in this roll.' },
    { 'sortTp', 'tp', 'TP', 'The monsters with a hunt teleport first.' },
}

-- the titles show which column sorts and which way
local function updateSortHeads()
    if not window then
        return
    end
    local head = window.ratesPanel.rateHeader
    for _, entry in ipairs(SORT_HEADS) do
        local widget = head[entry[1]]
        if widget then
            local active = entry[2] == currentSort
            widget:setText(tr(entry[3]) .. (active and (sortDesc and ' v' or ' ^') or ''))
            widget:setColor(active and '#f3dcae' or '#9789b3')
        end
    end
end

-- a column picked: again on the same one reverses it
local function setSort(key, toggle)
    if toggle and key == currentSort then
        sortDesc = not sortDesc
    else
        currentSort = SORT_SPECS[key] and key or 'combined'
        sortDesc = SORT_SPECS[currentSort][2]
    end
    local box = window and window.ratesPanel.filterSection.sortBox
    if box then
        box:setCurrentOptionByData(currentSort, true)
    end
end

-- the buttons show the wait between two hunt teleports (30 s), and how
-- many hunts a monster with more than one has
local function updateTpButtons()
    local left = math.max(0, tpReadyAt - os.time())
    for _, button in ipairs(tpButtons) do
        if button.go then
            -- the simple view's one button says what it does
            if left > 0 then
                button:setText(tr('Wait %d seconds', left))
            elseif button.hunts > 1 then
                button:setText(tr('Choose the hunt (%d)', button.hunts))
            else
                button:setText(tr('Teleport to the hunt'))
            end
        elseif left > 0 then
            button:setText(left .. 's')
        elseif button.hunts > 1 then
            button:setText(string.format('%s (%d)', tr('TP'), button.hunts))
        else
            button:setText(tr('TP'))
        end
        button:setEnabled(left == 0)
    end
end

-- the fonts draw one glyph per byte (Latin-1); the server's texts are UTF-8
local function latin1(text)
    return (tostring(text):gsub('[\194\195][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        return string.char((a - 194) * 64 + b)
    end))
end

-- a refusal of the server, for a few seconds where the page count goes
local function showTpMessage(text)
    -- a TP asked from outside the list (the Hunter's Journey card)
    if not window or not window:isVisible() then
        if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
            modules.game_textmessage.displayFailureMessage(text)
        end
        return
    end
    local label = window.ratesPanel.pageLabel
    if tpMessageEvent then
        removeEvent(tpMessageEvent)
    end
    label:setText(text)
    label:setColor('#ff7a6b')
    tpMessageEvent = scheduleEvent(function()
        tpMessageEvent = nil
        if window then
            label:setText(label.pageText or '')
            label:setColor('#cbc0e0')
        end
    end, 6000)
end

local function teleportTo(name, option)
    if tpReadyAt > os.time() then
        return
    end
    send({ action = 'teleport', name = name, option = option })
end

-- a hunt teleport asked from another window (the Hunter's Journey card);
-- returns the seconds left to wait, 0 when it was sent
function teleportToHunt(name)
    local left = tpReadyAt - os.time()
    if left > 0 then
        return left
    end
    send({ action = 'teleport', name = name })
    return 0
end

-- a hunt of the menu: "2. Near Ventera  -  floor -4  -  346 spawns"
local function huntText(index, hunt)
    local z = tonumber(hunt[2]) or 7
    local floor = z == 7 and tr('ground floor') or tr('floor %+d', 7 - z)
    return string.format('%d. %s', index, tr('Near %s  -  %s', latin1(hunt[1] or '?'), floor))
end

-- a monster with more than one hunt: the player picks where to go
local function chooseHunt(monster)
    if tpReadyAt > os.time() then
        return
    end
    local menu = g_ui.createWidget('MythosComboBoxPopupMenu')
    menu:setGameMenu(true)
    for i, hunt in ipairs(monster.tpHunts) do
        menu:addOption(huntText(i, hunt), function()
            teleportTo(monster.name, i)
        end)
    end
    menu:display()
end

-- ---------------------------------------------------------------- simple view

-- The list as most players want it (the owner, 2026-11-19: "less information
-- right in front of the player"): each hunt is a name, its level and how
-- good it is in this roll; the chosen one shows the rest on the right, with
-- one button. The table with every column is behind "Table and filters".
local selectedName -- the hunt shown on the right
local cards = {} -- lname -> its row of the list

-- the colour of a level against the player's, and what it means
local function fitOf(lvl)
    local mine = g_game.getLocalPlayer() and g_game.getLocalPlayer():getLevel() or 0
    lvl = tonumber(lvl) or 0
    if lvl == 0 then
        return '#cbc0e0', ''
    elseif mine >= lvl then
        return '#7fd35a', tr('Good for your level')
    elseif mine >= lvl * 0.75 then
        return '#e2a443', tr('A little above your level')
    end
    return '#ff7a6b', tr('Far above your level')
end

local function tile(widget, key, value, color)
    widget.key:setText(key)
    widget.value:setText(value)
    widget.value:setColor(color or '#ece6dc')
end

local function showDetail(monster)
    local detail = window.ratesPanel.simplePanel.detail
    detail:setVisible(monster ~= nil)
    if not monster then
        return
    end
    selectedName = monster.lname
    for lname, card in pairs(cards) do
        card:setChecked(lname == selectedName)
    end
    detail.pedestal.creature:setOutfit(outfitOf(monster))
    detail.name:setText(monster.name)
    local color, fit = fitOf(monster.lvl)
    detail.level:setText(monster.lvl and tr('Level %d', monster.lvl) or '')
    detail.level:setColor(color)
    detail.fit:setText(fit)
    tile(detail.xpTile, tr('XP rate'), multText(monster.xp), xpTone(monster.xp))
    tile(detail.lootTile, tr('Loot rate'), multText(monster.loot), lootTone(monster.loot))
    tile(detail.rareTile, tr('Rare monsters'), multText(monster.rare), rareTone(monster.rare))
    tile(detail.killTile, tr('XP per kill'), formatNumber(monster.perKill))
    tile(detail.goldTile, tr('Gold per kill'), monster.goldPerKill and formatNumber(monster.goldPerKill) or '-', '#e2a443')
    tile(detail.spawnTile, tr('Health'), formatShort(monster.hpNow))
    -- up to four lines: tougher at this rate, weak to, resists, immune to
    local lines = {}
    if monster.dmgMult > 1 then
        -- the health only when the rate raises it (the server's
        -- strength.hp: 0 since 2026-11-19, the rate raises the damage only)
        if monster.hpMult > 1 then
            lines[#lines + 1] = { tr('Stronger at this rate: health x%.1f, damage x%.1f', monster.hpMult, monster.dmgMult), '#ef9a62' }
        else
            lines[#lines + 1] = { tr('Hits harder at this rate: damage x%.1f', monster.dmgMult), '#ef9a62' }
        end
    end
    local weak, resists, immune = {}, {}, {}
    for _, entry in ipairs(monster.elements or {}) do
        if CHIP_ELEMENT[entry.key] and entry.taken ~= 100 then
            local name = tr(ELEMENTS[entry.key][1])
            if entry.taken == 0 then
                immune[#immune + 1] = name
            elseif entry.taken > 100 then
                weak[#weak + 1] = name
            else
                resists[#resists + 1] = name
            end
        end
    end
    if #weak > 0 then
        lines[#lines + 1] = { tr('Weak to: %s', table.concat(weak, ', ')), '#7fd35a' }
    end
    if #resists > 0 then
        lines[#lines + 1] = { tr('Resists: %s', table.concat(resists, ', ')), '#e2a443' }
    end
    if #immune > 0 then
        lines[#lines + 1] = { tr('Immune to: %s', table.concat(immune, ', ')), '#a3abb5' }
    end
    for i = 1, 4 do
        local label = detail['line' .. i]
        label:setText(lines[i] and lines[i][1] or '')
        label:setColor(lines[i] and lines[i][2] or '#a59d92')
    end
    -- the one action
    local go = detail.go
    go:setVisible(monster.tp > 0)
    detail.goIcon:setVisible(monster.tp > 0)
    if monster.tp > 0 then
        go.go = true
        go.hunts = monster.tpHunts and #monster.tpHunts or 1
        go.onClick = function()
            if go.hunts > 1 then
                chooseHunt(monster)
            else
                teleportTo(monster.name)
            end
        end
        go:setTooltip(tr('Teleport to the %s hunt (every 30 seconds)', monster.name))
        local kept = {}
        for _, button in ipairs(tpButtons) do
            if button ~= go then
                kept[#kept + 1] = button
            end
        end
        kept[#kept + 1] = go
        tpButtons = kept
        updateTpButtons()
    end
end

local function renderCards(first, last)
    local panel = window.ratesPanel.simplePanel
    local list = panel.cardList
    list:destroyChildren()
    cards = {}
    local chosen
    for i = first, last do
        local monster = filtered[i]
        local card = g_ui.createWidget('HuntCard', list)
        card.frame.creature:setOutfit(outfitOf(monster))
        card.name:setText(monster.name)
        if monster.xp >= 25 or monster.loot >= 25 then
            card.name:setColor('#ffb020')
        end
        card.level:setText(monster.lvl and tr('Level %d', monster.lvl) or '')
        card.level:setColor((fitOf(monster.lvl)))
        card.xp:setText(tr('XP %s', multText(monster.xp)))
        card.xp:setColor(xpTone(monster.xp))
        card.loot:setText(tr('Loot %s', multText(monster.loot)))
        card.onClick = function()
            showDetail(monster)
        end
        cards[monster.lname] = card
        if monster.lname == selectedName then
            chosen = monster
        end
    end
    -- the hunt that was open stays; else the first of the page
    showDetail(chosen or filtered[first])
    panel.cardEmpty:setVisible(#filtered == 0)
    panel.cardEmpty:setText(#rates.monsters == 0 and tr('Loading monster rates...') or tr('No monster matches your filters.'))
    panel.cardScroll:setValue(0)
end

local function renderPage()
    if not window then
        return
    end
    local panel = window.ratesPanel
    local list = panel.rateList
    list:destroyChildren()
    tpButtons = {}

    local pages = math.max(1, math.ceil(#filtered / PAGE_SIZE))
    page = math.max(1, math.min(page, pages))
    local first = (page - 1) * PAGE_SIZE + 1
    local last = math.min(#filtered, page * PAGE_SIZE)
    if not filtersShown then
        renderCards(first, last)
    end
    for i = first, filtersShown and last or first - 1 do
        local monster = filtered[i]
        local row = g_ui.createWidget(i % 2 == 0 and 'RateRowEven' or 'RateRow', list)
        row.creature:setOutfit(outfitOf(monster))
        row.name:setText(monster.boss == 1 and (monster.name .. '  [boss]') or monster.name)
        if monster.xp >= 25 or monster.loot >= 25 then
            row.name:setColor('#ffb020')
        elseif monster.boss == 1 then
            row.name:setColor('#e07bff')
        end
        fillElementChips(row.elements, monster.elements)
        -- a column each: level, health (while this rate lasts), XP and gold
        -- per kill, the XP and loot rates
        row.level:setText(monster.lvl and tostring(monster.lvl) or '-')
        -- the same colours as the Quests and Bosses windows: green at or
        -- above the recommended level, orange not far below it, red below
        local mine = g_game.getLocalPlayer() and g_game.getLocalPlayer():getLevel() or 0
        local lvl = tonumber(monster.lvl) or 0
        row.level:setColor(lvl == 0 and '#cbc0e0' or mine >= lvl and '#7fd35a' or mine >= lvl * 0.75 and '#e2a443' or '#ff7a6b')
        row.health:setText(formatShort(monster.hpNow))
        row.health:setColor(monster.hpMult > 1 and '#ef9a62' or '#cbc0e0')
        row.perKill:setText(formatShort(monster.perKill))
        row.perKill:setColor(xpTone(monster.xp))
        row.goldKill:setText(monster.goldPerKill and formatShort(monster.goldPerKill) or '-')
        setBar(row.xpBar, monster.xp)
        setBar(row.lootBar, monster.loot, rates.lootMax, lootTone)
        setBar(row.rareBar, monster.rare, rates.rareMax, rareTone)
        local tooltip = tr('%s\nExperience: %s x %.1f = %s per kill (before your own bonuses)\nLoot: %.1fx the normal drop chances', monster.name,
            formatNumber(monster.exp), monster.xp / 10, formatNumber(monster.perKill), monster.loot / 10)
        if monster.goldPerKill then
            tooltip = tooltip .. '\n' .. tr('Gold: %s x %.1f = %s per kill (average, at the prices Gersao pays)',
                formatNumber(monster.gold), monster.loot / 10, formatNumber(monster.goldPerKill))
        end
        if monster.rare > 10 then
            tooltip = tooltip .. '\n' .. tr('Rare monsters: %.1fx more Pale, Ashen and Obsidian', monster.rare / 10)
        end
        if monster.lvl then
            tooltip = tooltip .. '\n' .. tr('Recommended level: %d', monster.lvl)
        end
        if monster.dmgMult > 1 then
            if monster.hpMult > 1 then
                tooltip = tooltip .. '\n' .. tr('Tougher while this rate lasts: health x%.2f, damage x%.2f', monster.hpMult, monster.dmgMult)
            else
                tooltip = tooltip .. '\n' .. tr('Hits harder while this rate lasts: damage x%.2f', monster.dmgMult)
            end
        end
        if monster.elements then
            tooltip = tooltip .. '\n' .. elementLines(monster.elements)
        end
        row:setTooltip(tooltip)
        row.tp:setVisible(monster.tp > 0)
        row.tpIcon:setVisible(monster.tp > 0)
        if monster.tp > 0 then
            row.tp.hunts = monster.tpHunts and #monster.tpHunts or 1
            if row.tp.hunts > 1 then
                row.tp:setTooltip(tr('%d hunts of %s: click to pick one (a TP every 30 seconds)', row.tp.hunts, monster.name))
                row.tp.onClick = function()
                    chooseHunt(monster)
                end
            else
                row.tp:setTooltip(tr('Teleport to the %s hunt (every 30 seconds)', monster.name))
                row.tp.onClick = function()
                    teleportTo(monster.name)
                end
            end
            tpButtons[#tpButtons + 1] = row.tp
        end
    end
    updateTpButtons()

    panel.rateEmpty:setVisible(filtersShown and #filtered == 0)
    panel.rateEmpty:setText(#rates.monsters == 0 and tr('Loading monster rates...') or tr('No monster matches your filters.'))
    -- a TP refusal on show keeps the label until it goes
    panel.pageLabel.pageText = tr('Page %d of %d  (%d of %d monsters)', page, pages, #filtered, #rates.monsters)
    if not tpMessageEvent then
        panel.pageLabel:setText(panel.pageLabel.pageText)
    end
    panel.prevPage:setEnabled(page > 1)
    panel.nextPage:setEnabled(page < pages)
    panel.rateScroll:setValue(0)
end

-- ---------------------------------------------------------------- quick bar

-- The list opens simple (the owner, 2026-11-19): the hunts of the player's
-- level, best rate first, with three orders and a name to search. "Filters"
-- opens the whole filter panel and the detail columns (health, elements);
-- the client remembers it open.
local FILTERS_KEY = 'huntboard-filters-shown'
local MINE_KEY = 'huntboard-my-level-off'

local function myLevelRange()
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end
    local level = player:getLevel()
    return tostring(math.floor(level * MY_LEVEL[1])), tostring(math.floor(level * MY_LEVEL[2]))
end

-- the chips show what the list is doing, whoever set it (a chip, the
-- filter panel, a column title)
updateQuickBar = function()
    if not window then
        return
    end
    local bar = window.ratesPanel.quickBar
    local section = window.ratesPanel.filterSection
    local low, high = section.levelMin:getText(), section.levelMax:getText()
    local mineLow, mineHigh = myLevelRange()
    bar.mineChip:setChecked(mineLow ~= nil and low == mineLow and high == mineHigh)
    bar.allChip:setChecked(low == '' and high == '')
    bar.sortBest:setChecked(currentSort == 'combined' and sortDesc)
    bar.sortXp:setChecked(currentSort == 'perKill' and sortDesc)
    bar.sortGold:setChecked(currentSort == 'gold' and sortDesc)
    bar.filtersButton:setText(filtersShown and tr('Simple view') or tr('Table and filters'))
end

local function setLevelRange(low, high)
    local section = window.ratesPanel.filterSection
    section.levelMin:setText(low or '')
    section.levelMax:setText(high or '')
end

function setFiltersShown(shown)
    filtersShown = shown and true or false
    if not window then
        return
    end
    local panel = window.ratesPanel
    panel.filterSection:setVisible(filtersShown)
    panel.filterSection:setHeight(filtersShown and 84 or 0)
    panel.filterSection:setMarginTop(filtersShown and 6 or 0)
    -- the table with every column goes with the filters; without them, the
    -- simple view (renderCards)
    panel.rateHeader:setVisible(filtersShown)
    panel.rateList:setVisible(filtersShown)
    panel.rateScroll:setVisible(filtersShown)
    panel.simplePanel:setVisible(not filtersShown)
end

function toggleFilters()
    setFiltersShown(not filtersShown)
    g_settings.set(FILTERS_KEY, filtersShown)
    updateQuickBar()
    renderPage()
end

local function applyFilters()
    if not window then
        return
    end
    local section = window.ratesPanel.filterSection
    local filters = readFilters(section)

    filtered = {}
    for _, monster in ipairs(rates.monsters) do
        if matchesFilter(monster, filters) then
            filtered[#filtered + 1] = monster
        end
    end
    table.sort(filtered, sorterOf(currentSort, sortDesc))
    -- the advanced filter's steps (advanced.lua) run over what is left
    local total, counts = #filtered, nil
    if advancedApply then
        filtered, counts = advancedApply(filtered)
        advancedShowResult(total, counts, #filtered, filtered)
    end
    local button = section.advancedButton
    if button then
        local count = advancedActiveCount and advancedActiveCount() or 0
        button:setText(count > 0 and tr('Advanced (%d)', count) or tr('Advanced'))
        button:setColor(count > 0 and '#7fd35a' or '#e6e2ee')
    end
    page = 1
    updateSortHeads()
    updateQuickBar()
    renderPage()
end

-- a step of the advanced filter changed
function onAdvancedChanged()
    applyFilters()
end

local RANGE_BOXES = { 'xpMin', 'xpMax', 'goldMin', 'goldMax', 'levelMin', 'levelMax' }

-- the panel's buttons, tooltips and the element icons of the list header
local function setupFilterPanel()
    local section = window.ratesPanel.filterSection
    local hint = tr('A number: 6000, 6.000, 6k or 1,5kk. Empty: no limit.')
    for _, id in ipairs(RANGE_BOXES) do
        section[id]:setTooltip(hint)
    end
    section.xpLabel:setTooltip(tr('Experience per kill at this rate, before your own bonuses: the XP/kill column.'))
    section.goldLabel:setTooltip(tr('Gold per kill at this loot rate, at the prices Gersao pays: the Gold/kill column.'))
    section.levelLabel:setTooltip(tr('The level the Hunt Tasks recommend for the monster.'))
    section.rateBox:setTooltip(tr('Jackpot: XP 3.5x+ or loot 2.5x+.'))
    section.elementBox:setTooltip(tr('Weak to: it takes more damage from the element. No resistance: it takes at least the normal damage.'))

    section.myLevel.onClick = function()
        local player = g_game.getLocalPlayer()
        if not player then
            return
        end
        local level = player:getLevel()
        section.levelMin:setText(tostring(math.floor(level * MY_LEVEL[1])))
        section.levelMax:setText(tostring(math.floor(level * MY_LEVEL[2])))
        onFilterChanged()
    end
    section.myLevel.onHoverChange = function(widget, hovered)
        local player = g_game.getLocalPlayer()
        if hovered and player then
            local level = player:getLevel()
            widget:setTooltip(tr('Monsters for your level: %d to %d.', math.floor(level * MY_LEVEL[1]), math.floor(level * MY_LEVEL[2])))
        end
    end
    local bar = window.ratesPanel.quickBar
    bar.mineChip:setTooltip(tr('The hunts for your level.'))
    bar.allChip:setTooltip(tr('The hunts of every level.'))
    bar.sortBest:setTooltip(tr('XP rate and loot rate together, the best first.'))
    bar.sortXp:setTooltip(tr('The most experience per kill first.'))
    bar.sortGold:setTooltip(tr('The most gold per kill first.'))
    bar.filtersButton:setTooltip(tr('The table with every column and every filter.'))
    bar.mineChip.onClick = function()
        setLevelRange(myLevelRange())
        g_settings.set(MINE_KEY, false)
        applyFilters()
    end
    bar.allChip.onClick = function()
        setLevelRange()
        g_settings.set(MINE_KEY, true)
        applyFilters()
    end
    for id, key in pairs({ sortBest = 'combined', sortXp = 'perKill', sortGold = 'gold' }) do
        bar[id].onClick = function()
            setSort(key, false)
            applyFilters()
        end
    end
    section.advancedButton.onClick = function()
        openAdvanced()
    end
    section.advancedButton:setTooltip(tr('Filters that stack like a spreadsheet: keep only, sort by, keep the first N... over what the filters here let through.'))
    section.clearButton.onClick = function()
        advancedClear()
        window.ratesPanel.quickBar.searchEdit:setText('')
        for _, id in ipairs(RANGE_BOXES) do
            section[id]:setText('')
        end
        section.showBox:setCurrentIndex(1, true)
        section.rateBox:setCurrentIndex(1, true)
        section.elementBox:setCurrentIndex(1, true)
        applyFilters()
    end

    local sortHint = tr('Click to sort, click again to reverse.')
    window.ratesPanel.rateHeader.elementHead:setTooltip(tr('Green: the monster takes more damage from the element.\nAmber: it resists it.\nGrey: it is immune.'))
    -- every other column title sorts too
    local titles = window.ratesPanel.rateHeader
    for _, entry in ipairs(SORT_HEADS) do
        local widget = titles[entry[1]]
        if widget then
            widget:setTooltip(tr(entry[4]) .. '\n' .. sortHint)
            widget.onClick = function()
                setSort(entry[2], true)
                applyFilters()
            end
        end
    end
    updateSortHeads()
end

-- ---------------------------------------------------------------- leaderboard tab

local function valueText(category, value)
    if category == 'kills' then
        return tr('%s kills', formatNumber(value))
    end
    return tr('%s xp', formatShort(value))
end

local function fillColumn(column, category, entries, mine)
    column.list:destroyChildren()
    for i, entry in ipairs(entries or {}) do
        local row = g_ui.createWidget(i % 2 == 0 and 'BoardRowEven' or 'BoardRow', column.list)
        row.position:setText(tostring(i))
        local medal = MEDALS[i]
        if medal then
            row.position:setColor(medal.text)
        end
        row.name:setText(entry.name)
        row.info:setText(tr('Level %d %s', entry.level or 0, entry.vocation or ''))
        row.value:setText(valueText(category, entry.value))
        if entry.me then
            row:setBackgroundColor('#7fd35a22')
            row.name:setColor('#7fd35a')
        end
    end
    column.empty:setVisible(#(entries or {}) == 0)
    if mine and (mine[category] or 0) > 0 then
        column.mine:setText(tr('You: #%d with %s', mine[category .. 'Rank'] or 0, valueText(category, mine[category])))
        column.mine:setColor('#7fd35a')
    else
        column.mine:setText(tr('You have not scored in this period yet.'))
        column.mine:setColor('#7a7a7a')
    end
end

local function renderBoard()
    if not window then
        return
    end
    local panel = window.boardPanel
    panel.hourTab:setChecked(currentPeriod == 'hour')
    panel.dayTab:setChecked(currentPeriod == 'day')
    panel.monthTab:setChecked(currentPeriod == 'month')

    local board = boards[currentPeriod]
    local rewards = board and board.rewards or {}
    local prizeParts = {}
    for position, coins in ipairs(rewards) do
        prizeParts[#prizeParts + 1] = string.format('#%d: %s', position, formatNumber(coins))
    end
    panel.prize:setText(#prizeParts > 0 and tr('Prize per category  %s Mythos Coins', table.concat(prizeParts, '  ')) or '')

    panel.killsColumn:setText(tr('Most Monsters Killed - %s', tr(PERIOD_LABELS[currentPeriod])))
    panel.expColumn:setText(tr('Most Experience - %s', tr(PERIOD_LABELS[currentPeriod])))
    if not board then
        fillColumn(panel.killsColumn, 'kills', {}, nil)
        fillColumn(panel.expColumn, 'experience', {}, nil)
        return
    end
    fillColumn(panel.killsColumn, 'kills', board.kills, board.me)
    fillColumn(panel.expColumn, 'experience', board.experience, board.me)

    panel.history:destroyChildren()
    for _, entry in ipairs(board.recent or {}) do
        local line = g_ui.createWidget('HistoryLine', panel.history)
        line:setText(tr('%s, %s: %s was #%d in %s with %s and won %s Mythos Coins', tr(PERIOD_LABELS[entry.period] or ''), entry.when or '',
            entry.name or '?', entry.position or 1, entry.category == 'kills' and tr('kills') or tr('experience'),
            valueText(entry.category, entry.value), formatNumber(entry.coins)))
        if entry.period == 'month' then
            line:setColor('#ffb020')
        elseif entry.period == 'day' then
            line:setColor('#3d9bff')
        end
    end
    if #(board.recent or {}) == 0 then
        local line = g_ui.createWidget('HistoryLine', panel.history)
        line:setText(tr('No period has closed yet.'))
        line:setColor('#7a7a7a')
    end
end

-- ---------------------------------------------------------------- timers

-- why the last online minute did not count (the board's onlineSkip), under
-- the bar: the coin counts only while hunting, for one character of the
-- account and a few accounts per connection
local ONLINE_SKIP_TEXTS = {
    idle = 'Counts only while you hunt (monster experience in the last %d min)',
    account = 'Another character of this account is counting',
    ip = 'Other accounts on this connection are already counting',
}

local function updateOnline()
    if not window then
        return
    end
    local bar = window.onlineBar
    local goal = math.max(1, online.goal)
    local minutes = math.min(online.minutes, goal)
    bar.fill:setWidth(math.max(1, math.floor((bar:getWidth() - 2) * minutes / goal)))
    bar.value:setText(tr('%d / %d min', minutes, goal))
    bar:setTooltip(tr('You get %d Mythos Coin(s) for every %d minutes hunting online.', online.amount, goal))
    local note = window.onlineNote
    if note then
        local text = ONLINE_SKIP_TEXTS[online.skip]
        note:setVisible(text ~= nil)
        if text then
            note:setText(tr(text, online.activeMinutes or 15))
        end
    end
end

local function tick()
    tickEvent = nil
    if not window or not window:isVisible() then
        return
    end
    local now = serverNow()
    if rates.nextAt > 0 then
        local left = rates.nextAt - now
        if left <= 0 then
            window.ratesPanel.countdown:setText(tr('Rolling new rates...'))
            if left < -5 and left > -20 and currentTab == 'rates' then
                rates.nextAt = 0
                send({ action = 'rates' })
            end
        else
            window.ratesPanel.countdown:setText(tr('New rates in %s', formatDuration(left)))
        end
    end
    updateTpButtons()
    local board = boards[currentPeriod]
    if board and board.endsAt then
        local left = board.endsAt - now
        window.boardPanel.ends:setText(left > 0 and tr('%s leaderboard ends in %s', tr(PERIOD_LABELS[currentPeriod]), formatDuration(left)) or tr('Paying the winners...'))
    end
    tickEvent = scheduleEvent(tick, 1000)
end

local function startTick()
    if tickEvent then
        removeEvent(tickEvent)
    end
    tickEvent = scheduleEvent(tick, 10)
end

-- ---------------------------------------------------------------- toast

local function hideToast()
    if toastEvent then
        removeEvent(toastEvent)
        toastEvent = nil
    end
    if toast then
        toast:destroy()
        toast = nil
    end
end

local function showToast(title, text, iconSetup, seconds)
    hideToast()
    local parent = modules.game_interface and modules.game_interface.getRootPanel() or rootWidget
    toast = g_ui.createWidget('HuntToast', parent)
    toast:addAnchor(AnchorTop, 'parent', AnchorTop)
    toast:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    toast:setMarginTop(40)
    toast.title:setText(title)
    toast.text:setText(text)
    if iconSetup then
        iconSetup(toast.icon)
    end
    toast.open.onClick = function()
        hideToast()
        if not window:isVisible() or currentTab ~= 'rates' then
            openSection('rates')
        end
    end
    toast.onClick = hideToast
    toastEvent = scheduleEvent(hideToast, (seconds or 12) * 1000)
end

-- ---------------------------------------------------------------- rate next to the monsters

-- the rates (tenths) of each monster, by lower-case name: { xp, loot, rare }
local rateByName = {}

-- the shader of a very strong monster (experience rate RATE_ALERT or more):
-- game_shaders' "Hunt - Strong", a red heartbeat. A rare tier's own shader
-- comes before it (Creature::setStrongShader).
local STRONG_SHADER = 'Hunt - Strong'

-- What a monster shows of its rates: icons above its name
-- (Creature::setBoostBadges), from 2x, no number: the colour says how near
-- the rate is to the highest (green, yellow, orange, red at the top):
--   experience  the letters XP and, from RATE_ALERT, the strong shader:
--               that rate also makes the monster tougher
--   loot        a loot bag
--   rare        crystals: the chance of a rare monster
local function labelCreature(creature)
    if not creature or not creature.setRateText or not creature:isMonster() then
        return
    end
    -- the number beside the health bar gave way to the icons above the name
    creature:setRateText('')
    -- clients from before the badges and the shader have neither
    if not creature.setBoostBadges then
        return
    end
    local entry = rateByName[creature:getName():lower()]
    if not entry then
        creature:setBoostBadges(0, 0, 0)
        creature:setStrongShader('')
        return
    end
    creature:setBoostBadges(entry.loot, entry.rare, entry.xp)
    creature:setStrongShader(math.floor(entry.xp / 10 + 0.5) >= RATE_ALERT and STRONG_SHADER or '')
end

local function labelAll()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), true)) do
        labelCreature(creature)
    end
end

-- ---------------------------------------------------------------- server messages

local handlers = {}

-- ---------------------------------------------------------------- NEW RATES

-- the roll of rates the player has seen: opened the list, or closed the
-- NEW RATES callout over the Teleports row of the Mythos bar
local SEEN_KEY = 'huntboard_rates_seen'

local function markRatesSeen()
    if rates.slot >= 0 and g_settings.getNumber(SEEN_KEY) ~= rates.slot then
        g_settings.set(SEEN_KEY, rates.slot)
        g_settings.save()
    end
end

-- once for every roll of the rates, until the player closes it or opens the list
local function pointNewRates()
    local panel = modules.game_brevespanel
    if not panel or not panel.point or rates.slot < 0 or #rates.monsters == 0 then
        return
    end
    if window and window:isVisible() and currentTab == 'rates' then
        markRatesSeen()
        panel.hidePoint('rates')
        return
    end
    if g_settings.getNumber(SEEN_KEY) == rates.slot then
        return
    end
    -- the tour and the Hunter's Journey card already point at the hunts
    local tour, journey = modules.game_tutorial, modules.game_journey
    if (tour and tour.isRunning and tour.isRunning()) or (journey and journey.isShowingCard and journey.isShowingCard()) then
        return
    end
    local best
    for _, monster in ipairs(rates.monsters) do
        if monster.tp > 0 and (not best or monster.xp + monster.loot > best.xp + best.loot) then
            best = monster
        end
    end
    panel.point('rates', tr('NEW RATES'), tr('Teleports to the hunts here'),
        best and tr('Best now: %s\nXP x%.1f  -  Loot x%.1f', best.name, best.xp / 10, best.loot / 10),
        markRatesSeen)
end

function handlers.rates(data)
    timeOffset = (data.now or os.time()) - os.time()
    rates.slot = data.slot or -1
    rates.nextAt = data.nextAt or 0
    rates.interval = data.interval or 7200
    rates.max = data.max or 100
    rates.lootMax = data.lootMax or 30
    rates.rareMax = data.rareMax or 40
    -- the top of each rate, for the colour of the icons on the monsters
    if Creature and Creature.setBoostMaxima then
        Creature.setBoostMaxima(rates.lootMax, rates.rareMax, rates.max)
    end
    local fields = data.fields or {}
    local index = {}
    for i, name in ipairs(fields) do
        index[name] = i
    end
    local monsters = {}
    for _, raw in ipairs(data.monsters or {}) do
        local monster = {}
        for name, i in pairs(index) do
            monster[name] = raw[i]
        end
        monster.name = tostring(monster.name or '?')
        monster.lname = monster.name:lower()
        monster.exp = tonumber(monster.exp) or 0
        monster.hp = tonumber(monster.hp) or 0
        monster.spawns = tonumber(monster.spawns) or 0
        -- how many hunts the TP goes to; with two or more, { town, floor, spawns } of each
        monster.tp = tonumber(monster.tp) or 0
        if type(monster.tpHunts) ~= 'table' or #monster.tpHunts < 2 then
            monster.tpHunts = nil
        end
        monster.xp = tonumber(monster.xp) or 10
        monster.loot = tonumber(monster.loot) or 10
        -- rare monsters rate (1x-4x); 1x with a server that does not send it
        monster.rare = tonumber(monster.rare) or 10
        monster.elements, monster.taken = parseElements(monster.elements)
        monster.perKill = math.floor(monster.exp * monster.xp / 10)
        -- the Hunt Tasks' recommended level; nil with a server that does not send it
        monster.lvl = tonumber(monster.lvl)
        if monster.lvl and monster.lvl <= 0 then
            monster.lvl = nil
        end
        -- gold per kill: the server's average at the normal loot rate (what
        -- Gersao pays for the items, the coins at their worth) times this
        -- monster's loot rate; nil with a server that does not send it
        monster.gold = tonumber(monster.gold)
        monster.goldPerKill = monster.gold and math.floor(monster.gold * monster.loot / 10 + 0.5) or nil
        -- a monster with an experience rate above 1x is tougher (server:
        -- huntboard strength)
        monster.hpMult, monster.dmgMult = 1, 1
        local strength = data.strength
        local rate = monster.xp / 10
        if strength and rate > 1 and (monster.boss ~= 1 or strength.bosses == 1) then
            monster.hpMult = 1 + (rate - 1) * (tonumber(strength.hp) or 0) / 100
            monster.dmgMult = 1 + (rate - 1) * (tonumber(strength.dmg) or 0) / 100
        end
        monster.hpNow = math.floor(monster.hp * monster.hpMult)
        monster.xpPerHp = monster.perKill / math.max(1, monster.hpNow)
        monsters[#monsters + 1] = monster
    end
    rates.monsters = monsters
    rateByName = {}
    for _, monster in ipairs(monsters) do
        rateByName[monster.lname] = { xp = monster.xp, loot = monster.loot, rare = monster.rare }
    end
    labelAll()
    if window then
        updateFooter()
        applyFilters()
    end
    pointNewRates()
    -- no best rate over the Teleports row (the owner, 2026-11-19): the row
    -- is the bar's gold one, and the window opens sorted by the best rate
    local panel = modules.game_brevespanel
    if panel and panel.setFeatureFlag then
        panel.setFeatureFlag('rates', nil)
    end
end

function handlers.board(data)
    timeOffset = (data.now or os.time()) - os.time()
    boards[data.period or 'hour'] = data
    online.minutes = data.online or online.minutes
    online.goal = data.onlineGoal or online.goal
    online.amount = data.onlineAmount or online.amount
    online.skip = data.onlineSkip -- nil: the last minute counted
    online.activeMinutes = data.onlineActiveMinutes or online.activeMinutes
    updateOnline()
    if data.period == currentPeriod then
        renderBoard()
    end
end

function handlers.ratesChanged(data)
    rates.nextAt = data.nextAt or rates.nextAt
    -- the labels on the monsters need the new rates too; the NEW RATES
    -- callout comes with them. Every client gets this notice in the same
    -- second, and the list is about 65 KB: each one asks a moment later, at
    -- random (soon when the window is open), not all at once
    if ratesEvent then
        removeEvent(ratesEvent)
    end
    local open = window and window:isVisible()
    ratesEvent = scheduleEvent(function()
        ratesEvent = nil
        if g_game.isOnline() then
            send({ action = 'rates' })
        end
    end, math.random(open and 200 or 1000, open and 2000 or 20000))
end

function handlers.coins(data)
    local text
    if data.reason == 'online' then
        online.minutes = 0
        updateOnline()
        text = tr('+%d Mythos Coin for playing 1 hour. Thanks for playing!', data.amount or 1)
    else
        text = tr('+%s Mythos Coins for winning the leaderboard!', formatNumber(data.amount or 0))
    end
    if data.balance then
        text = text .. '\n' .. tr('Balance: %s Mythos Coins', formatNumber(data.balance))
    end
    showToast(tr('Mythos Coins received'), text, function(icon)
        icon:setImageSource('/images/store/icon-tibiacoin')
        icon:setImageClip('0 0 0 0') -- whole image (an empty string is not a rect and threw)
    end, 8)
end

-- the server sends it under this name (old clients crashed on the toast)
handlers.coinsToast = handlers.coins

-- answer to a TP (and, on opening, the wait left)
function handlers.teleport(data)
    tpReadyAt = os.time() + (tonumber(data.wait) or 0)
    updateTpButtons()
    if not data.text then
        return
    end
    local text = latin1(data.text)
    if data.ok then
        hide()
        if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
            modules.game_textmessage.displayGameMessage(text)
        end
    else
        showTpMessage(text)
    end
end

local function onHuntOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    local handler = handlers[data.action]
    if handler then
        handler(data)
    end
end

-- ---------------------------------------------------------------- public (otui)

function onFilterChanged()
    if filterEvent then
        removeEvent(filterEvent)
    end
    filterEvent = scheduleEvent(function()
        filterEvent = nil
        applyFilters()
    end, 250)
end

function changePage(delta)
    page = page + delta
    renderPage()
end

-- with the Mythos panel, Hunt Rates and Leaderboard open as two windows
-- (the same window showing one section, without the tabs)
local SECTIONS = {
    rates = { title = 'Hunts TP', intro = 'Pick a hunt and teleport to it.' },
    board = { title = 'Leaderboard', intro = 'Top hunters of the hour, day and month' },
}

function updateFooter()
    if not window then
        return
    end
    -- no explanation at the foot of the window: the countdown and the
    -- columns' tooltips say it
    window.footer:setText('')
end

local function updateSectionButtons()
    local visible = window and window:isVisible()
    for tab, button in pairs(sectionButtons) do
        button:setOn(visible and currentTab == tab)
    end
end

function selectTab(tab)
    currentTab = tab
    window.ratesTab:setChecked(tab == 'rates')
    window.boardTab:setChecked(tab == 'board')
    window.ratesPanel:setVisible(tab == 'rates')
    window.boardPanel:setVisible(tab == 'board')
    local split = next(sectionButtons) ~= nil
    window.ratesTab:setVisible(not split)
    window.boardTab:setVisible(not split)
    window.sectionIntro:setVisible(split)
    if split then
        window:setText(tr(SECTIONS[tab].title))
        window.sectionIntro:setText(tr(SECTIONS[tab].intro))
    end
    -- the title bar holds the tabs of the hub (Hunts, Bosses, Quests,
    -- Ranking): the lit one says which this is
    if modules.game_brevespanel and modules.game_brevespanel.setHubCurrent then
        modules.game_brevespanel.setHubCurrent(window, tab == 'board' and 'board' or 'rates')
    end
    updateFooter()
    updateSectionButtons()
    if tab == 'board' then
        renderBoard()
        send({ action = 'board', period = currentPeriod })
    elseif window:isVisible() then
        -- the new rates are in front of the player: no NEW RATES callout
        markRatesSeen()
        if modules.game_brevespanel and modules.game_brevespanel.hidePoint then
            modules.game_brevespanel.hidePoint('rates')
        end
    end
end

function selectPeriod(period)
    currentPeriod = period
    renderBoard()
    send({ action = 'board', period = period })
end

function show()
    if not window then
        return
    end
    -- the first time a character opens it: the hunts of its level, unless
    -- the player chose every level before
    if not quickReady and g_game.getLocalPlayer() then
        quickReady = true
        setFiltersShown(g_settings.getBoolean(FILTERS_KEY))
        if not g_settings.getBoolean(MINE_KEY) then
            setLevelRange(myLevelRange())
        end
        applyFilters()
    end
    window:show()
    window:raise()
    window:focus()
    if toolbarButton then
        toolbarButton:setOn(true)
    end
    updateSectionButtons()
    startTick()
end

function hide()
    if not window then
        return
    end
    window:hide()
    if toolbarButton then
        toolbarButton:setOn(false)
    end
    updateSectionButtons()
end

function toggle()
    if not window then
        return
    end
    if window:isVisible() then
        hide()
        return
    end
    show()
    selectTab(currentTab)
    send({ action = 'open', period = currentPeriod })
end

-- open the window on one section, or close it when that section is showing
function openSection(tab)
    if not window then
        return
    end
    if window:isVisible() then
        if currentTab == tab then
            hide()
        else
            selectTab(tab)
            window:raise()
            window:focus()
        end
        return
    end
    currentTab = tab
    toggle()
end

function toggleRates()
    openSection('rates')
end

function toggleBoard()
    openSection('board')
end

-- ---------------------------------------------------------------- lifecycle

local function setupCombo(combo, options)
    combo:clearOptions()
    for _, option in ipairs(options) do
        combo:addOption(tr(option.label), option.key)
    end
    combo:setCurrentIndex(1, true)
    combo.onOptionChange = function()
        applyFilters()
    end
end

local function onGameStart()
    connect(Creature, { onAppear = labelCreature })
    if ratesEvent then
        removeEvent(ratesEvent)
    end
    -- each client at its own moment (g_game.spreadDelay): a login rush
    -- brings hundreds of clients in the same minute
    ratesEvent = scheduleEvent(function()
        ratesEvent = nil
        if g_game.isOnline() then
            send({ action = 'rates' })
        end
    end, g_game.spreadDelay and g_game.spreadDelay(4000, 10000) or 1000)
    if not next(sectionButtons) and modules.game_brevespanel then
        sectionButtons.rates = modules.game_brevespanel.addFeature('rates', toggleRates)
        sectionButtons.board = modules.game_brevespanel.addFeature('board', toggleBoard)
    end
    -- Hunts, Bosses and Quests as tabs in the title bar (the bar has one row for the three)
    if modules.game_brevespanel and modules.game_brevespanel.attachHub then
        modules.game_brevespanel.attachHub(window, currentTab == 'board' and 'board' or 'rates', hide)
    end
    if not next(sectionButtons) and not toolbarButton and modules.game_mainpanel then
        toolbarButton = modules.game_mainpanel.addToggleButton('huntBoardButton', tr('Hunt Board (rates & leaderboard)'),
            '/game_huntboard/images/button', toggle, false, 21)
    end
end

local function onGameEnd()
    disconnect(Creature, { onAppear = labelCreature })
    if ratesEvent then
        removeEvent(ratesEvent)
        ratesEvent = nil
    end
    clearSendQueue()
    rateByName = {}
    hide()
    hideToast()
    rates.monsters = {}
    rates.nextAt = 0
    boards = {}
    quickReady = false -- the next character has its own level
end

function init()
    window = g_ui.displayUI('huntboard')
    window:hide()

    local section = window.ratesPanel.filterSection
    setupCombo(section.showBox, SHOWS)
    setupCombo(section.rateBox, RATE_FILTERS)
    setupCombo(section.elementBox, ELEMENT_FILTERS)
    setupCombo(section.sortBox, SORTS)
    -- the panel's sort list and the column titles sort the same way
    section.sortBox.onOptionChange = function(_, _, key)
        setSort(key or 'combined', false)
        applyFilters()
    end
    advancedInit()
    setupFilterPanel()
    setFiltersShown(false)
    updateOnline()

    ProtocolGame.registerExtendedJSONOpcode(HUNT_OPCODE, onHuntOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    advancedTerminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    disconnect(Creature, { onAppear = labelCreature })
    ProtocolGame.unregisterExtendedJSONOpcode(HUNT_OPCODE)
    hideToast()
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    if filterEvent then
        removeEvent(filterEvent)
        filterEvent = nil
    end
    if ratesEvent then
        removeEvent(ratesEvent)
        ratesEvent = nil
    end
    clearSendQueue()
    if toolbarButton then
        toolbarButton:destroy()
        toolbarButton = nil
    end
    for _, button in pairs(sectionButtons) do
        button:destroy()
    end
    sectionButtons = {}
    if window then
        window:destroy()
        window = nil
    end
end
