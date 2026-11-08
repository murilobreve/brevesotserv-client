-- Salão dos Bosses: the bosses fought from a lever, each in its lever room
-- (copied from the official map). The window (bosses.otui): filters (name or
-- quest, an item of the loot, the state, the kind of equipment, experience,
-- quest, level, party, favourites), the list sorted as the player picks (a
-- dot for the state), and the boss picked: its numbers, its rarest and
-- strongest loot and the party; the button takes the player to the lever
-- room (from a protection zone or out of combat) whatever those say: the
-- lever is what refuses. The rows are made once and only hidden or moved.
-- When the team pulls a lever the server rolls the boss's tier and every
-- member sees the roulette over the map for a few seconds before the arena
-- ("rareRoll", scripts/rarity/boss_tiers.lua).
-- Talks to data-otservbr-global/scripts/custom/boss_portal.lua through
-- extended opcode BOSS_OPCODE with JSON payloads.

local BOSS_OPCODE = 133

local window
local panelButton
local toolbarButton
local state -- last "state" from the server
local receivedAt = 0 -- os.time() when it came: the waits count down from there
local selectedName
local subtab = 'loot'
local filters = { states = {}, cats = {}, xpMin = 0, mine = false, party = false, fav = false }
local sortDesc = true
local favorites = {}
local lootCache = {} -- boss name -> its loot (server "loot")
local itemQuery = '' -- the item searched in the loot
local itemFound -- set of boss names whose loot has it (server "search")
local rows = {} -- boss name -> row of the list
local tickEvent
local messageEvent
local searchEvent
local ticks = 0
local roulette -- the roulette over the map
local rouletteEvent
local quietCombo = false -- filling the quest combo must not rebuild the list
local REFRESH_SECONDS = 15 -- the open window asks for the arenas again

local TIER_COLORS = { pale = '#c9d6e3', ashen = '#a7adb5', obsidian = '#a98bff', deathlord = '#ff6b6b', normal = '#3a3342' }
local CATS = {
    { 'weapon', 'Arma' }, { 'armor', 'Armadura' }, { 'helmet', 'Elmo' }, { 'legs', 'Calça' },
    { 'boots', 'Botas' }, { 'shield', 'Escudo' }, { 'jewel', 'Joia' },
}
local SORTS = {
    { 'xp', 'Experiência' }, { 'hp', 'Vida' }, { 'ready', 'Libera primeiro' },
    { 'level', 'Nível mínimo' }, { 'name', 'Nome' }, { 'fav', 'Favoritos primeiro' },
}

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

-- 3250000 -> "3,25 mi", 75000 -> "75.000"
local function shortNumber(value)
    value = tonumber(value) or 0
    if value >= 1000000 then
        return (string.format('%.2f', value / 1000000):gsub('%.', ',')) .. ' mi'
    end
    return formatNumber(value)
end

-- 12.5 -> "12,5%", 0.05 -> "0,05%"
local function percent(chance)
    chance = tonumber(chance) or 0
    local text
    if chance >= 10 then
        text = string.format('%d', math.floor(chance + 0.5))
    elseif chance >= 1 then
        text = string.format('%.1f', chance)
    else
        text = string.format('%.2f', chance)
    end
    text = text:gsub('%.?0+$', '') ~= '' and text or text
    return (text:gsub('%.', ',')) .. '%'
end

-- how rare a drop is, by its colour (the item grades' colours)
local function rareColor(chance)
    chance = tonumber(chance) or 100
    if chance < 0.1 then
        return '#e8e4ff'
    elseif chance < 0.5 then
        return '#e2a443'
    elseif chance < 2 then
        return '#af78ea'
    elseif chance < 10 then
        return '#4f8fe8'
    end
    return '#a59d92'
end

local function titleCase(text)
    return ((text or ''):gsub("(%a)([%w']*)", function(first, rest)
        local word = first .. rest
        if word == 'of' or word == 'the' then
            return word
        end
        return first:upper() .. rest
    end))
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

-- players in the arena now
local function busy(boss)
    return tonumber(boss.busy) or 0
end

-- seconds until the arena's time runs out, or nil
local function busyLeft(boss)
    if not boss.busyLeft then
        return nil
    end
    return math.max(0, boss.busyLeft - (os.time() - receivedAt))
end

-- the boss's state for the player: key, text, colour, background, border
local function statusOf(boss)
    if not canFight(boss) then
        return 'level', tr('Nível %d', boss.level), '#ff9c8a', '#2a1515', '#5a2a2a'
    end
    local left = waitLeft(boss)
    if left > 0 then
        return 'wait', formatWait(left), '#e8c77a', '#2a2219', '#5c4a2c'
    end
    if busy(boss) > 0 then
        return 'busy', tr('Em luta'), '#ffb36b', '#2a1d10', '#5a3d1e'
    end
    return 'ready', tr('Pronto'), '#9fd99a', '#152015', '#2f4a2f'
end

local function isReady(boss)
    return canFight(boss) and waitLeft(boss) == 0 and busy(boss) == 0
end

local function paintPill(pill, boss)
    local _, text, color, back, border = statusOf(boss)
    pill:setText(text)
    pill:setColor(color)
    pill:setBackgroundColor(back)
    pill:setBorderColor(border)
end

-- the list's state mark: a coloured dot, its text in the tooltip
local function paintDot(dot, boss)
    local key, text, color = statusOf(boss)
    if dot.stateKey ~= key or dot.stateText ~= text then
        dot.stateKey, dot.stateText = key, text
        dot:setImageColor(color)
        dot:setTooltip(text)
    end
end

-- what would stop the lever now, one line each
local function warningsOf(boss)
    local lines = {}
    if busy(boss) > 0 then
        local left = busyLeft(boss)
        lines[#lines + 1] = left and tr('Um time está lutando agora: a alavanca libera quando a sala esvaziar (em até %s).', formatWait(left))
            or tr('Um time está lutando agora: a alavanca libera quando a sala esvaziar.')
    end
    local wait = waitLeft(boss)
    if wait > 0 then
        lines[#lines + 1] = tr('Você já fez esse boss: a alavanca libera para você em %s.', formatWait(wait))
    end
    if not canFight(boss) then
        lines[#lines + 1] = tr('A alavanca pede nível %d de todo o time.', boss.level)
    end
    return lines
end

-- the party members the lever would refuse: { name, text, colour }
local function teamOf(boss)
    local list = {}
    for _, member in ipairs(boss.team or {}) do
        local memberWait = math.max(0, (tonumber(member[2]) or 0) - (os.time() - receivedAt))
        if memberWait > 0 then
            list[#list + 1] = { member[1], tr('espera %s', formatWait(memberWait)), '#e8c77a' }
        elseif member[3] == 1 then
            list[#list + 1] = { member[1], tr('não tem o nível %d', boss.level), '#ff9c8a' }
        end
    end
    return list
end

local function findBoss(name)
    for _, boss in ipairs(state and state.bosses or {}) do
        if boss.name == name then
            return boss
        end
    end
end

local function showMessage(text, ok)
    if not window then
        return
    end
    if messageEvent then
        removeEvent(messageEvent)
    end
    window.message:setText(text or '')
    window.message:setColor(ok and '#9fd99a' or '#ff9c8a')
    messageEvent = scheduleEvent(function()
        messageEvent = nil
        if window then
            window.message:setText('')
        end
    end, 8000)
end

local function catsOf(boss)
    local set = {}
    for key in (boss.cats or ''):gmatch('[^,]+') do
        set[key] = true
    end
    return set
end

local function loadFavorites()
    favorites = {}
    local saved = g_settings.getNode('bossFavorites')
    if type(saved) == 'table' then
        for name, on in pairs(saved) do
            if on then
                favorites[name] = true
            end
        end
    end
end

local function saveFavorites()
    g_settings.setNode('bossFavorites', favorites)
end

-- ---------------------------------------------------------------- the wheel

-- the 100 ticks around a wheel (BossWheel), 1% each
local function buildWheel(wheel)
    if wheel.ticks then
        return
    end
    wheel.ticks = {}
    wheel.angle = 0
    local c, radius = 120, 108
    for i = 0, 99 do
        local angle = (i + 0.5) * 3.6
        local rad = math.rad(angle)
        local tick = g_ui.createWidget('UIWidget', wheel)
        tick:setImageSource('/game_bosses/images/tick')
        tick:setSize({ width = 6, height = 18 })
        tick:setPhantom(true)
        tick:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        tick:addAnchor(AnchorTop, 'parent', AnchorTop)
        tick:setMarginLeft(math.floor(c + radius * math.sin(rad) - 3 + 0.5))
        tick:setMarginTop(math.floor(c - radius * math.cos(rad) - 9 + 0.5))
        tick:setRotation(angle)
        wheel.ticks[i + 1] = tick
    end
    wheel.needle:raise()
end

-- the slices of the wheel: each tier as big as its chance, the rest normal.
-- Returns { key, from, to } in ticks (0..100)
local function paintWheel(wheel, tiers)
    buildWheel(wheel)
    local slices, at = {}, 0
    for _, tier in ipairs(tiers or {}) do
        local size = math.max(1, math.floor((tonumber(tier.chance) or 0) + 0.5))
        slices[#slices + 1] = { key = tier.key, from = at, to = math.min(100, at + size) }
        at = math.min(100, at + size)
    end
    slices[#slices + 1] = { key = 'normal', from = at, to = 100 }
    for i, tick in ipairs(wheel.ticks) do
        local color = TIER_COLORS.normal
        for _, slice in ipairs(slices) do
            if i - 1 >= slice.from and i - 1 < slice.to then
                color = TIER_COLORS[slice.key] or color
                break
            end
        end
        tick:setImageColor(color)
    end
    return slices
end

-- turns the needle 5 times and stops it inside the slice of `key`
local function spinWheel(wheel, slices, key, duration, onDone)
    local slice
    for _, s in ipairs(slices) do
        if s.key == key then
            slice = s
        end
    end
    slice = slice or slices[#slices]
    local land = (slice.from + (slice.to - slice.from) * (0.2 + math.random() * 0.6)) * 3.6
    local from = wheel.angle or 0
    local target = (math.floor(from / 360) + 5) * 360 + land
    local t0 = g_clock.millis()
    if wheel.spinEvent then
        removeEvent(wheel.spinEvent)
    end
    local function step()
        wheel.spinEvent = nil
        if wheel:isDestroyed() then
            return
        end
        local p = math.min(1, (g_clock.millis() - t0) / duration)
        local eased = 1 - (1 - p) ^ 3
        wheel.angle = from + (target - from) * eased
        wheel.needle:setRotation(wheel.angle % 360)
        if p >= 1 then
            if onDone then
                onDone()
            end
            return
        end
        wheel.spinEvent = scheduleEvent(step, 16)
    end
    step()
end

local function tierName(tiers, key)
    for _, tier in ipairs(tiers or {}) do
        if tier.key == key then
            return tier.name
        end
    end
    return tr('Normal')
end

local function multiplier(value)
    return tr('×') .. (tostring(tonumber(value) or 1):gsub('%.', ','))
end

-- ---------------------------------------------------------------- Hall

local function bossLoot(boss)
    return lootCache[boss.name]
end

local function passes(boss)
    local query = window.pages.hall.filters.search:getText():lower()
    if query ~= '' and not (boss.name .. ' ' .. (boss.quest or '')):lower():find(query, 1, true) then
        return false
    end
    if itemQuery ~= '' and itemFound and not itemFound[boss.name] then
        return false
    end
    if next(filters.states) and not filters.states[(statusOf(boss))] then
        return false
    end
    if next(filters.cats) then
        local cats, any = catsOf(boss), false
        for key in pairs(filters.cats) do
            any = any or cats[key]
        end
        if not any then
            return false
        end
    end
    if (boss.experience or 0) < filters.xpMin then
        return false
    end
    local option = window.pages.hall.filters.quest:getCurrentOption()
    if option and option.data and option.data ~= '' and boss.quest ~= option.data then
        return false
    end
    if filters.mine and not canFight(boss) then
        return false
    end
    if filters.party and #teamOf(boss) > 0 then
        return false
    end
    if filters.fav and not favorites[boss.name] then
        return false
    end
    return true
end

local function sortKey()
    local option = window.pages.hall.middle.sort:getCurrentOption()
    return option and option.data or 'xp'
end

local SORT_VALUE = {
    xp = function(b) return b.experience or 0 end,
    hp = function(b) return b.health or 0 end,
    ready = function(b) return -(waitLeft(b) + (busy(b) > 0 and (busyLeft(b) or 1800) or 0)) end,
    rare = function(b) return -(tonumber(b.rare) or 100) end,
    level = function(b) return b.level or 0 end,
    fav = function(b) return favorites[b.name] and 1 or 0 end,
}

local function sortedBosses()
    local list = {}
    for _, boss in ipairs(state and state.bosses or {}) do
        if passes(boss) then
            list[#list + 1] = boss
        end
    end
    local value = SORT_VALUE[sortKey()]
    table.sort(list, function(a, b)
        if value then
            local va, vb = value(a), value(b)
            if va ~= vb then
                if sortDesc then
                    return va > vb
                end
                return va < vb
            end
        end
        if not value and not sortDesc then
            return a.name:lower() > b.name:lower()
        end
        return a.name:lower() < b.name:lower()
    end)
    return list
end

local renderDetail

local function chipStyle(widget, on)
    widget:setOn(on and true or false)
end

-- the chips are made once; a click only flips their state (a chip must never
-- be destroyed inside its own click)
local chipSets = nil

local function buildChips()
    local f = window.pages.hall.filters
    chipSets = {}
    local function add(parent, text, autoSize, isOn, onClick)
        local chip = g_ui.createWidget('BossChip', parent)
        chip:setText(tr(text))
        if not autoSize then
            chip:setTextAutoResize(false)
        end
        chip.activeFn = isOn
        chip.onClick = function()
            onClick()
            refreshList()
        end
        chipSets[#chipSets + 1] = chip
    end
    f.states:destroyChildren()
    for _, entry in ipairs({ { 'ready', 'Pronto' }, { 'wait', 'Esperando' }, { 'busy', 'Em luta' } }) do
        add(f.states, entry[2], true, function() return filters.states[entry[1]] end, function()
            filters.states[entry[1]] = not filters.states[entry[1]] or nil
        end)
    end
    f.cats:destroyChildren()
    for _, entry in ipairs(CATS) do
        add(f.cats, entry[2], false, function() return filters.cats[entry[1]] end, function()
            filters.cats[entry[1]] = not filters.cats[entry[1]] or nil
        end)
    end
    f.xps:destroyChildren()
    for _, entry in ipairs({ { 0, 'Qualquer' }, { 50000, '50 mil' }, { 70000, '70 mil' }, { 1000000, '1 milhão' } }) do
        add(f.xps, entry[2], false, function() return filters.xpMin == entry[1] end, function()
            filters.xpMin = entry[1]
        end)
    end
    f.toggles:destroyChildren()
    for _, entry in ipairs({ { 'mine', 'Só o que meu nível alcança' }, { 'party', 'Minha party toda pode entrar' }, { 'fav', 'Só favoritos' } }) do
        add(f.toggles, entry[2], true, function() return filters[entry[1]] end, function()
            filters[entry[1]] = not filters[entry[1]]
        end)
    end
end

local function fillFilters()
    local f = window.pages.hall.filters
    if not chipSets then
        buildChips()
    end
    for _, chip in ipairs(chipSets) do
        chipStyle(chip, chip.activeFn())
    end
    local active = (f.search:getText() ~= '' and 1 or 0) + (itemQuery ~= '' and 1 or 0) + (filters.xpMin > 0 and 1 or 0)
        + (filters.mine and 1 or 0) + (filters.party and 1 or 0) + (filters.fav and 1 or 0)
    for _ in pairs(filters.states) do active = active + 1 end
    for _ in pairs(filters.cats) do active = active + 1 end
    local option = f.quest:getCurrentOption()
    if option and option.data and option.data ~= '' then
        active = active + 1
    end
    f.clear:setText(tr('Limpar (%d)', active))
end

local function fillQuests()
    local combo = window.pages.hall.filters.quest
    local names, seen = {}, {}
    for _, boss in ipairs(state and state.bosses or {}) do
        if boss.quest and boss.quest ~= '' and not seen[boss.quest] then
            seen[boss.quest] = true
            names[#names + 1] = boss.quest
        end
    end
    table.sort(names)
    if combo.questCount == #names then
        return
    end
    local current = combo:getCurrentOption()
    quietCombo = true
    combo:clearOptions()
    combo:addOption(tr('Todas as quests'), '')
    for _, name in ipairs(names) do
        combo:addOption(name, name)
    end
    combo.questCount = #names
    if current and current.data and current.data ~= '' then
        combo:setCurrentOption(current.text, true)
    end
    quietCombo = false
end

local function fillRow(row, boss)
    -- what never changes is set once, when the row is made
    if not row.filled then
        row.filled = true
        row.frame.creature:setOutfit(outfitOf(boss.outfit))
        row.name:setText(boss.name)
        local tail = tr(' · %s XP · %s vida', shortNumber(boss.experience), shortNumber(boss.health))
        local quest = boss.quest or ''
        local room = 42 - #tail
        if #quest > room then
            quest = quest:sub(1, math.max(4, room - 2)):gsub('%s+$', '') .. '...'
        end
        row.info:setText(quest .. tail)
        row.star.onClick = function()
            favorites[boss.name] = not favorites[boss.name] or nil
            saveFavorites()
            row.star:setImageSource(favorites[boss.name] and '/game_bosses/images/star_on' or '/game_bosses/images/star')
            if filters.fav or sortKey() == 'fav' then
                addEvent(refreshList)
            end
        end
    end
    paintDot(row.status, boss)
    local fav = favorites[boss.name] and true or false
    if row.fav ~= fav then
        row.fav = fav
        row.star:setImageSource(fav and '/game_bosses/images/star_on' or '/game_bosses/images/star')
    end
end

local rebuilding = false

function refreshList()
    if not window or not state or quietCombo then
        return
    end
    local middle = window.pages.hall.middle
    local list = middle.list
    -- the rows are made once per boss and kept: a filter or a new order only
    -- hides them or moves them, which costs far less than making them again
    rebuilding = true
    local bosses = sortedBosses()
    local shown = {}
    local keep
    for index, boss in ipairs(bosses) do
        local row = rows[boss.name]
        if not row or row:isDestroyed() then
            row = g_ui.createWidget('BossRow', list)
            local name = boss.name
            row.onFocusChange = function(widget, focused)
                if focused and not rebuilding then
                    selectedName = name
                    renderDetail()
                end
            end
            row.onDoubleClick = function()
                selectedName = name
                goSelected()
                return true
            end
            rows[name] = row
        end
        fillRow(row, boss)
        shown[boss.name] = true
        row:setVisible(true)
        if list:getChildIndex(row) ~= index then
            list:moveChildToIndex(row, index)
        end
        if boss.name == selectedName then
            keep = row
        end
    end
    for name, row in pairs(rows) do
        if not shown[name] and not row:isDestroyed() then
            row:setVisible(false)
        end
    end
    middle.count:setText(tr('%d de %d bosses', #bosses, #state.bosses))
    middle.empty:setText(tr('Nenhum boss com esses filtros.'))
    middle.empty:setVisible(#bosses == 0)
    local focus = keep or (bosses[1] and rows[bosses[1].name])
    if focus then
        if list:getFocusedChild() ~= focus then
            list:focusChild(focus, KeyboardFocusReason)
            list:ensureChildVisible(focus)
        end
        if not keep then
            selectedName = bosses[1].name
        end
    end
    rebuilding = false
    fillFilters()
    renderDetail()
end

function clearFilters()
    filters = { states = {}, cats = {}, xpMin = 0, mine = false, party = false, fav = false }
    local f = window.pages.hall.filters
    f.search:setText('')
    f.itemSearch:setText('')
    itemQuery, itemFound = '', nil
    f.quest:setCurrentIndex(1, true)
    refreshList()
end

function flipSort()
    sortDesc = not sortDesc
    window.pages.hall.middle.dir:setText(sortDesc and 'v' or '^')
    refreshList()
end

-- an item of the loot: the server says which bosses drop it
function searchItem(text)
    text = (text or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if searchEvent then
        removeEvent(searchEvent)
        searchEvent = nil
    end
    if #text < 3 then
        itemQuery, itemFound = '', nil
        refreshList()
        return
    end
    searchEvent = scheduleEvent(function()
        searchEvent = nil
        itemQuery = text
        send({ action = 'search', item = text })
    end, 350)
end

local function setSubtab(name)
    subtab = name
    renderDetail()
end

renderDetail = function()
    if not window then
        return
    end
    local d = window.pages.hall.detail
    local boss = findBoss(selectedName)
    for _, child in ipairs(d:getChildren()) do
        child:setVisible(boss ~= nil)
    end
    if not boss then
        return
    end
    local key = statusOf(boss)
    local aura = key == 'ready' and '#9fd99a' or key == 'busy' and '#ffb36b' or key == 'wait' and '#e8c77a' or '#ff9c8a'
    d.pedestal.aura:setImageColor(aura)
    d.pedestal.creature:setOutfit(outfitOf(boss.outfit))
    paintPill(d.status, boss)
    d.name:setText(boss.name)
    d.quest:setText(tr('%s · nível %s · espera %s', boss.quest or '', boss.level > 0 and tostring(boss.level) or tr('livre'), formatWait(boss.wait or 0)))
    d.stats:destroyChildren()
    for _, stat in ipairs({ { 'EXPERIÊNCIA', shortNumber(boss.experience) }, { 'VIDA', shortNumber(boss.health) },
        { 'JOGADORES', boss.players > 1 and tr('%d ou mais', boss.players) or tr('1 a 5') } }) do
        local tile = g_ui.createWidget('BossStatTile', d.stats)
        tile.key:setText(tr(stat[1]))
        tile.value:setText(stat[2])
    end
    d.subtabs:destroyChildren()
    for _, entry in ipairs({ { 'loot', 'Loot' }, { 'party', 'Sua party' } }) do
        local tab = g_ui.createWidget('BossTab', d.subtabs)
        tab:setText(tr(entry[2]))
        tab:setOn(subtab == entry[1])
        tab.onClick = function() addEvent(function() setSubtab(entry[1]) end) end
    end
    d.loot:setVisible(subtab == 'loot')
    d.party:setVisible(subtab == 'party')

    -- the loot: asked once per boss
    local loot = bossLoot(boss)
    local l = d.loot
    l.strong:destroyChildren()
    l.strongTitle:setText(tr('Mais raros e mais fortes'))
    l.lootWait:setText(tr('Carregando o loot...'))
    l.lootWait:setVisible(loot == nil)
    l.strongTitle:setVisible(loot ~= nil and subtab == 'loot')
    if not loot then
        if not lootCache[boss.name .. '#asked'] then
            lootCache[boss.name .. '#asked'] = true
            send({ action = 'loot', name = boss.name })
        end
    else
        local all, pool = {}, {}
        for _, item in ipairs(loot) do
            all[#all + 1] = item
            if not item.name:lower():find('coin', 1, true) then
                pool[#pool + 1] = item
            end
        end
        -- equipment first, then single pieces, then the rest; rarest first in each
        local function group(item)
            if item.kind then return 0 end
            if (item.max or 1) <= 1 then return 1 end
            return 2
        end
        table.sort(pool, function(a, b)
            local ga, gb = group(a), group(b)
            if ga ~= gb then return ga < gb end
            return (a.chance or 0) < (b.chance or 0)
        end)
        for i = 1, math.min(10, #pool) do
            local item = pool[i]
            local card = g_ui.createWidget('BossStrongItem', l.strong)
            card.frame.item:setItemId(item.id)
            local color = rareColor(item.chance)
            card.frame:setBorderColor(color .. '99')
            local label = titleCase(item.name)
            if #label > 18 then
                label = label:sub(1, 16):gsub('%s+$', '') .. '...'
            end
            card.name:setText(label)
            card.chance:setText(percent(item.chance))
            card.chance:setColor(color)
            card:setTooltip(titleCase(item.name))
        end
    end

    -- the party: who the lever would refuse, and why
    local p = d.party
    p.rows:destroyChildren()
    local mine = g_ui.createWidget('BossPartyRow', p.rows)
    local _, text, color = statusOf(boss)
    mine.name:setText(tr('Você'))
    mine.text:setText(text)
    mine.dot:setImageColor(color)
    for _, member in ipairs(teamOf(boss)) do
        local row = g_ui.createWidget('BossPartyRow', p.rows)
        row.name:setText(member[1])
        row.text:setText(member[2])
        row.dot:setImageColor(member[3])
    end
    local warnings = warningsOf(boss)
    local team = teamOf(boss)
    if #team > 0 then
        warnings[#warnings + 1] = tr('Quem está acima não passa pela alavanca agora.')
    end
    if #warnings > 0 then
        p.note:setText(table.concat(warnings, '\n'))
        p.note:setColor('#ffb36b')
    else
        p.note:setText(tr('Ninguém da sua party está impedido. De uma área protegida, ou fora de combate, você vai à sala da alavanca; puxem juntos nos pisos marcados.'))
        p.note:setColor('#9fd99a')
    end

    d.wiki:setText(tr('Ver na Wiki'))
    local ready = isReady(boss)
    d.go:setText(ready and tr('Ir para a sala do boss') or busy(boss) > 0 and tr('Ir para a sala (ocupada agora)') or tr('Ir para a sala do boss'))
    d.go:setEnabled(true)
end

-- ---------------------------------------------------------------- Rare boss

local function tiersOf()
    return state and state.rare or {}
end

-- the roulette over the map: the server rolled the boss's tier at the pull
-- of the lever; the team sees it for `ms` before the arena
local function showRoulette(data)
    if not roulette then
        roulette = g_ui.createWidget('BossRoulette', rootWidget)
        roulette:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        roulette:addAnchor(AnchorTop, 'parent', AnchorTop)
        roulette:setMarginTop(70)
    end
    if rouletteEvent then
        removeEvent(rouletteEvent)
        rouletteEvent = nil
    end
    local ms = math.max(2500, tonumber(data.ms) or 4000)
    local tiers = data.tiers or {}
    roulette.title:setText(tr('A ROLETA DO BOSS'))
    roulette.boss:setText(data.boss or '')
    roulette.wheel.creature:setOutfit(outfitOf(data.outfit))
    roulette.result:setText('')
    roulette.effects:setText(tr('O boss pode surgir raro...'))
    roulette:setBorderColor('#6b5631')
    roulette:show()
    roulette:raise()
    local slices = paintWheel(roulette.wheel, tiers)
    local key = data.result or 'normal'
    spinWheel(roulette.wheel, slices, key, ms - 600, function()
        if not roulette then
            return
        end
        if key == 'normal' then
            roulette.result:setText(tr('Normal'))
            roulette.result:setColor('#d6cfc2')
            roulette.effects:setText(tr('Um boss comum, com o loot de sempre.'))
        else
            local color = TIER_COLORS[key] or '#ece6dc'
            roulette.result:setText(data.name or tierName(tiers, key))
            roulette.result:setColor(color)
            roulette:setBorderColor(color)
            local parts = {}
            if data.health then
                parts[#parts + 1] = tr('Vida %s', multiplier(data.health))
            end
            if data.damage then
                parts[#parts + 1] = tr('Dano %s', multiplier(data.damage))
            end
            parts[#parts + 1] = tr('itens raros em cada reward bag')
            roulette.effects:setText(table.concat(parts, tr('  ·  ')))
        end
        rouletteEvent = scheduleEvent(function()
            rouletteEvent = nil
            if roulette then
                roulette:hide()
            end
        end, 2600)
    end)
end

-- ---------------------------------------------------------------- pages

function showPage()
    refreshList()
end

-- the waits count down without asking the server again
local function updateStatuses()
    if not state then
        return
    end
    local ready = 0
    for _, boss in ipairs(state.bosses) do
        if isReady(boss) then
            ready = ready + 1
        end
        local row = rows[boss.name]
        if row and not row:isDestroyed() then
            paintDot(row.status, boss)
        end
    end
    if window then
        window.summary:setText(tr('%d bosses · %d prontos para você', #state.bosses, ready))
        local boss = findBoss(selectedName)
        if boss then
            paintPill(window.pages.hall.detail.status, boss)
        end
    end
    local panel = modules.game_brevespanel
    if panel and panel.setFeatureState then
        panel.setFeatureState('bosses', ready > 0 and tostring(ready) or nil, '#7fd35a')
    end
end

function goSelected()
    if not findBoss(selectedName) then
        return
    end
    send({ action = 'go', name = selectedName })
end

-- the boss's page in the Wiki: loot, health, damage, weaknesses
function openWiki()
    local wiki = modules.game_wiki
    if not selectedName or not wiki or not wiki.show then
        return
    end
    wiki.show('m:' .. selectedName)
end

-- ---------------------------------------------------------------- server

local handlers = {}

function handlers.state(data)
    state = data
    receivedAt = os.time()
    if window and window:isVisible() then
        fillQuests()
        -- the rows are kept: only their state and the order change
        refreshList()
    end
    updateStatuses()
end

function handlers.message(data)
    showMessage(data.text, data.ok)
    if data.went then
        hide()
    end
end

function handlers.loot(data)
    if type(data.name) == 'string' then
        lootCache[data.name] = data.items or {}
        if window and window:isVisible() and data.name == selectedName then
            renderDetail()
        end
    end
end

function handlers.search(data)
    if (data.item or ''):lower() ~= itemQuery then
        return
    end
    itemFound = {}
    for _, name in ipairs(data.bosses or {}) do
        itemFound[name] = true
    end
    refreshList()
end

function handlers.rareRoll(data)
    showRoulette(data)
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
    -- the arenas fill and empty: the open window asks again now and then
    ticks = ticks + 1
    if ticks % REFRESH_SECONDS == 0 and window and window:isVisible() then
        send({ action = 'open' })
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
    if not tickEvent then
        tickEvent = cycleEvent(tick, 1000)
    end
    fillQuests()
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
    loadFavorites()
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
    rows, lootCache = {}, {}
    itemQuery, itemFound = '', nil
    if roulette then
        roulette:hide()
    end
    if window then
        window.pages.hall.middle.list:destroyChildren()
    end
end

function init()
    window = g_ui.displayUI('bosses')
    window:hide()
    window:setText(tr('Salão dos Bosses'))
    window.closeX:setTooltip(tr('Fechar'))
    local f = window.pages.hall.filters
    f.filtersTitle:setText(tr('FILTROS'))
    f.searchLabel:setText(tr('Boss ou quest'))
    f.itemLabel:setText(tr('Deixa cair o item'))
    f.stateLabel:setText(tr('Estado para você'))
    f.catLabel:setText(tr('Equipamento que dá'))
    f.xpLabel:setText(tr('Experiência mínima'))
    f.questLabel:setText(tr('Quest'))
    f.quest:addOption(tr('Todas as quests'), '')
    local m = window.pages.hall.middle
    m.sortLabel:setText(tr('Ordenar'))
    for _, entry in ipairs(SORTS) do
        m.sort:addOption(tr(entry[2]), entry[1])
    end
    m.dir:setText('v')
    m.dir:setTooltip(tr('Inverter a ordem'))

    ProtocolGame.registerExtendedJSONOpcode(BOSS_OPCODE, onBossOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedJSONOpcode(BOSS_OPCODE)
    for _, event in ipairs({ tickEvent, messageEvent, searchEvent, rouletteEvent }) do
        removeEvent(event)
    end
    tickEvent, messageEvent, searchEvent, rouletteEvent = nil, nil, nil, nil
    if panelButton then
        panelButton:destroy()
        panelButton = nil
    end
    if toolbarButton then
        toolbarButton:destroy()
        toolbarButton = nil
    end
    if roulette then
        roulette:destroy()
        roulette = nil
    end
    if window then
        window:destroy()
        window = nil
    end
end
