-- Advanced filter of the Hunts TP list: a list of steps run from top to
-- bottom over the monsters the simple filters let through (huntboard.lua
-- calls advancedApply after its own filters and sort):
--   filter: keep the monsters whose field is at least / at most / equal to /
--           between values ("HP at most 5000", "XP rate at least 2")
--   sort:   sort by a field, then by a second one, each up or down
--   top:    keep only the first N of the list as it is at that step
-- "Keep the first 20 by XP per health, then sort those by XP rate" is two
-- steps. Ready-made filters build steps for the character's own level and
-- vocation; the player saves up to 5 of his own (g_settings).

local SETTINGS_KEY = 'huntboard-advanced'
local MAX_SAVED = 5

-- base vocation of the client's ids (1 knight .. 5 monk, +10 promoted) ->
-- the elements its attacks deal (the "my element" field takes the one the
-- monster takes the most damage from)
local VOCATION_ELEMENTS = {
    [1] = { 'physical' },
    [2] = { 'physical', 'holy' },
    [3] = { 'fire', 'energy', 'death', 'ice', 'earth' },
    [4] = { 'ice', 'earth', 'fire', 'energy' },
    [5] = { 'physical', 'holy' },
}
local ELEMENT_NAMES = {
    physical = 'Physical', earth = 'Earth', fire = 'Fire', death = 'Death',
    energy = 'Energy', holy = 'Holy', ice = 'Ice',
}

local function myLevel()
    local player = g_game.getLocalPlayer()
    return player and player:getLevel() or 1
end

local function myElements()
    local player = g_game.getLocalPlayer()
    local vocation = player and player:getVocation() or 0
    return VOCATION_ELEMENTS[vocation % 10] or { 'physical' }
end

local function taken(m, element)
    return m.taken and (m.taken[element] or 100) or nil
end

local function tpCount(m)
    return m.tp > 0 and (m.tpHunts and #m.tpHunts or 1) or 0
end

-- every field a step can use: label, a monster's value, how a typed value
-- reads ("2" for a rate means 2x), and whether bigger is better (the default
-- direction of a sort)
local FIELDS = {
    { key = 'hp', label = 'Health', value = function(m) return m.hpNow end, desc = false },
    { key = 'perKill', label = 'XP per kill', value = function(m) return m.perKill end, desc = true },
    { key = 'gold', label = 'Gold per kill', value = function(m) return m.goldPerKill end, desc = true },
    { key = 'xp', label = 'XP rate (x)', value = function(m) return m.xp / 10 end, desc = true },
    { key = 'loot', label = 'Loot rate (x)', value = function(m) return m.loot / 10 end, desc = true },
    { key = 'combined', label = 'XP + loot rate (x)', value = function(m) return (m.xp + m.loot) / 10 end, desc = true },
    { key = 'rare', label = 'Rare monster rate (x)', value = function(m) return (m.rare or 10) / 10 end, desc = true },
    { key = 'xpPerHp', label = 'XP per health', value = function(m) return m.hpNow and m.hpNow > 0 and m.perKill / m.hpNow or 0 end, desc = true },
    { key = 'goldPerHp', label = 'Gold per health', value = function(m) return m.hpNow and m.hpNow > 0 and (m.goldPerKill or 0) / m.hpNow or 0 end, desc = true },
    { key = 'level', label = 'Hunt level', value = function(m) return m.lvl end, desc = false },
    { key = 'levelGap', label = 'Hunt level minus mine', value = function(m) return m.lvl and m.lvl - myLevel() end, desc = false },
    { key = 'myElement', label = 'Damage from my element (%)', value = function(m)
        local best
        for _, element in ipairs(myElements()) do
            local value = taken(m, element)
            if value and (not best or value > best) then
                best = value
            end
        end
        return best
    end, desc = true },
    { key = 'damage', label = 'Its damage (x)', value = function(m) return m.dmgMult or 1 end, desc = false },
    { key = 'exp', label = 'Base experience', value = function(m) return m.exp end, desc = true },
    { key = 'tp', label = 'Hunt teleports', value = tpCount, desc = true },
    { key = 'boss', label = 'Boss (1 yes, 0 no)', value = function(m) return m.boss == 1 and 1 or 0 end, desc = false },
}
for _, element in ipairs({ 'physical', 'earth', 'fire', 'death', 'energy', 'holy', 'ice' }) do
    FIELDS[#FIELDS + 1] = {
        key = 'el:' .. element,
        label = 'Damage from ' .. ELEMENT_NAMES[element]:lower() .. ' (%)',
        value = function(m) return taken(m, element) end,
        desc = true,
    }
end
local FIELD = {}
for _, field in ipairs(FIELDS) do
    FIELD[field.key] = field
end

local KINDS = {
    { key = 'filter', label = 'Keep only' },
    { key = 'sort', label = 'Sort by' },
    { key = 'top', label = 'Keep the first' },
}
local OPS = {
    { key = 'ge', label = 'at least' },
    { key = 'le', label = 'at most' },
    { key = 'eq', label = 'equal to' },
    { key = 'between', label = 'between' },
}
local DIRS = {
    { key = 'desc', label = 'biggest' },
    { key = 'asc', label = 'smallest' },
}
local DIRS2 = {
    { key = 'none', label = '-' },
    { key = 'desc', label = 'biggest' },
    { key = 'asc', label = 'smallest' },
}

-- ---------------------------------------------------------------- state

local advWindow
local steps = {} -- { kind, field, op, v1, v2, field2, dir, dir2, n }
local saved = {} -- { { name, steps } }
local filling = false
local editEvent

local function copySteps(list)
    local out = {}
    for i, step in ipairs(list or {}) do
        local copy = {}
        for k, v in pairs(step) do
            copy[k] = v
        end
        out[i] = copy
    end
    return out
end

-- "6000", "6.000", "6k", "1,5kk", "2.5": a number or nil
local function readNumber(text)
    text = tostring(text or ''):lower():gsub('%s', '')
    if text == '' then
        return nil
    end
    local digits, suffix = text:match('^(%-?[%d%.,]+)(k*)$')
    if not digits then
        return nil
    end
    local value
    if suffix ~= '' then
        value = tonumber((digits:gsub(',', '.')))
        if value then
            value = value * (1000 ^ #suffix)
        end
    elseif digits:find(',') and not digits:find('%.') and not digits:match(',%d%d%d$') then
        value = tonumber((digits:gsub(',', '.'))) -- "1,5"
    elseif digits:match('%.%d%d%d$') or digits:match(',%d%d%d$') then
        value = tonumber((digits:gsub('[%.,]', ''))) -- "6.000", "6,000"
    else
        value = tonumber(digits)
    end
    return value
end

local function load()
    local text = g_settings.get(SETTINGS_KEY)
    local ok, data = pcall(function()
        return text and text ~= '' and json.decode(text) or nil
    end)
    if ok and type(data) == 'table' then
        steps = type(data.steps) == 'table' and data.steps or {}
        saved = type(data.saved) == 'table' and data.saved or {}
    end
end

local function store()
    local ok, text = pcall(json.encode, { steps = steps, saved = saved })
    if ok and text then
        g_settings.set(SETTINGS_KEY, text)
    end
end

-- ---------------------------------------------------------------- running

local function valueOf(fieldKey, m)
    local field = FIELD[fieldKey]
    if not field then
        return nil
    end
    local ok, value = pcall(field.value, m)
    return ok and value or nil
end

local function passes(step, m)
    local value = valueOf(step.field, m)
    if value == nil then
        return false
    end
    local a, b = tonumber(step.v1), tonumber(step.v2)
    if step.op == 'ge' then
        return not a or value >= a
    elseif step.op == 'le' then
        return not a or value <= a
    elseif step.op == 'eq' then
        return not a or math.abs(value - a) < 0.0001
    elseif step.op == 'between' then
        if a and b and a > b then
            a, b = b, a
        end
        return (not a or value >= a) and (not b or value <= b)
    end
    return true
end

local function compare(fieldKey, dir, a, b)
    local va, vb = valueOf(fieldKey, a), valueOf(fieldKey, b)
    if va == vb then
        return nil
    end
    if va == nil then
        return false
    elseif vb == nil then
        return true
    end
    if dir == 'asc' then
        return va < vb
    end
    return va > vb
end

-- whether a step does anything yet (a filter with no value is skipped)
local function active(step)
    if step.kind == 'filter' then
        return FIELD[step.field] ~= nil and (tonumber(step.v1) ~= nil or tonumber(step.v2) ~= nil)
    elseif step.kind == 'sort' then
        return FIELD[step.field] ~= nil
    elseif step.kind == 'top' then
        return (tonumber(step.n) or 0) > 0
    end
    return false
end

function advancedActiveCount()
    local count = 0
    for _, step in ipairs(steps) do
        if active(step) then
            count = count + 1
        end
    end
    return count
end

-- the list after every step; also how many monsters each step left
function advancedApply(list)
    local counts = {}
    for i, step in ipairs(steps) do
        if active(step) then
            if step.kind == 'filter' then
                local kept = {}
                for _, m in ipairs(list) do
                    if passes(step, m) then
                        kept[#kept + 1] = m
                    end
                end
                list = kept
            elseif step.kind == 'sort' then
                local field2 = step.dir2 ~= 'none' and FIELD[step.field2] and step.field2 or nil
                table.sort(list, function(a, b)
                    local first = compare(step.field, step.dir, a, b)
                    if first ~= nil then
                        return first
                    end
                    if field2 then
                        local second = compare(field2, step.dir2, a, b)
                        if second ~= nil then
                            return second
                        end
                    end
                    return a.lname < b.lname
                end)
            elseif step.kind == 'top' then
                local n = math.floor(tonumber(step.n) or 0)
                if #list > n then
                    local kept = {}
                    for j = 1, n do
                        kept[j] = list[j]
                    end
                    list = kept
                end
            end
        end
        counts[i] = #list
    end
    return list, counts
end

-- ---------------------------------------------------------------- presets

-- ready-made filters, built when picked (the character's level and
-- vocation at that moment)
local PRESETS = {
    {
        label = 'Best XP for my level',
        build = function(level)
            return {
                { kind = 'filter', field = 'level', op = 'between', v1 = math.floor(level * 0.55), v2 = math.floor(level * 1.1) },
                { kind = 'sort', field = 'perKill', dir = 'desc', field2 = 'xp', dir2 = 'desc' },
            }
        end,
    },
    {
        label = 'Easy kills, best XP rate',
        build = function(level)
            return {
                { kind = 'filter', field = 'level', op = 'le', v1 = level },
                { kind = 'sort', field = 'xpPerHp', dir = 'desc' },
                { kind = 'top', n = 20 },
                { kind = 'sort', field = 'xp', dir = 'desc', field2 = 'perKill', dir2 = 'desc' },
            }
        end,
    },
    {
        label = 'Gold farm',
        build = function(level)
            return {
                { kind = 'filter', field = 'level', op = 'le', v1 = math.floor(level * 1.1) },
                { kind = 'sort', field = 'goldPerHp', dir = 'desc' },
                { kind = 'top', n = 25 },
                { kind = 'sort', field = 'gold', dir = 'desc', field2 = 'loot', dir2 = 'desc' },
            }
        end,
    },
    {
        label = 'Weak to my element',
        build = function(level)
            return {
                { kind = 'filter', field = 'myElement', op = 'ge', v1 = 110 },
                { kind = 'filter', field = 'level', op = 'le', v1 = math.floor(level * 1.1) },
                { kind = 'sort', field = 'perKill', dir = 'desc', field2 = 'xp', dir2 = 'desc' },
            }
        end,
    },
    {
        label = 'Safe solo hunt',
        build = function(level)
            return {
                { kind = 'filter', field = 'level', op = 'le', v1 = math.floor(level * 0.8) },
                { kind = 'filter', field = 'boss', op = 'eq', v1 = 0 },
                { kind = 'filter', field = 'damage', op = 'le', v1 = 1.2 },
                { kind = 'sort', field = 'xpPerHp', dir = 'desc', field2 = 'xp', dir2 = 'desc' },
            }
        end,
    },
    {
        label = 'Best rates right now',
        build = function(level)
            return {
                { kind = 'filter', field = 'level', op = 'le', v1 = math.floor(level * 1.2) },
                { kind = 'filter', field = 'combined', op = 'ge', v1 = 3 },
                { kind = 'sort', field = 'combined', dir = 'desc', field2 = 'perKill', dir2 = 'desc' },
            }
        end,
    },
}

-- ---------------------------------------------------------------- window

local function changed()
    store()
    if onAdvancedChanged then
        onAdvancedChanged()
    end
end

local function fillCombo(combo, entries, selected)
    combo:clearOptions()
    for _, entry in ipairs(entries) do
        combo:addOption(tr(entry.label), entry.key)
    end
    if selected then
        combo:setCurrentOptionByData(selected, true)
    end
end

local renderSteps

local function showKind(row, step)
    local filter, sort, top = step.kind == 'filter', step.kind == 'sort', step.kind == 'top'
    row.field:setVisible(filter or sort)
    row.op:setVisible(filter or sort)
    row.value1:setVisible(filter or top)
    row.value2:setVisible(filter and step.op == 'between')
    row.andLabel:setVisible(filter and step.op == 'between')
    row.thenLabel:setVisible(sort)
    row.field2:setVisible(sort)
    row.dir2:setVisible(sort)
    row.hint:setVisible(top)
    if top then
        row.value1:breakAnchors()
        row.value1:addAnchor(AnchorLeft, 'kind', AnchorRight)
        row.value1:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        row.value1:setMarginLeft(6)
        row.hint:setText(tr('monsters of the list at this point'))
    else
        row.value1:breakAnchors()
        row.value1:addAnchor(AnchorLeft, 'op', AnchorRight)
        row.value1:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        row.value1:setMarginLeft(6)
    end
end

local function bindRow(row, index)
    local step = steps[index]
    row.number:setText(tostring(index))
    row.andLabel:setText(tr('and'))
    row.thenLabel:setText(tr('then by'))
    fillCombo(row.kind, KINDS, step.kind)
    fillCombo(row.field, FIELDS, step.field)
    fillCombo(row.field2, FIELDS, step.field2 or 'perKill')
    fillCombo(row.dir2, DIRS2, step.dir2 or 'none')
    if step.kind == 'sort' then
        fillCombo(row.op, DIRS, step.dir or 'desc')
    else
        fillCombo(row.op, OPS, step.op or 'ge')
    end
    row.value1:setText(step.kind == 'top' and tostring(step.n or '') or tostring(step.v1 or ''))
    row.value2:setText(tostring(step.v2 or ''))
    row.value1:setTooltip(tr('A number: 6000, 6.000, 6k, 1,5kk; a rate as 2 or 1.5.'))
    showKind(row, step)

    row.kind.onOptionChange = function(_, _, key)
        if filling or step.kind == key then
            return
        end
        step.kind = key
        step.field = step.field or 'perKill'
        if key == 'sort' then
            step.dir = FIELD[step.field] and (FIELD[step.field].desc and 'desc' or 'asc') or 'desc'
            step.dir2 = step.dir2 or 'none'
        elseif key == 'filter' then
            step.op = step.op or 'ge'
        elseif key == 'top' then
            step.n = step.n or 20
        end
        renderSteps()
        changed()
    end
    row.field.onOptionChange = function(_, _, key)
        if filling then
            return
        end
        step.field = key
        if step.kind == 'sort' then
            step.dir = FIELD[key].desc and 'desc' or 'asc'
            filling = true
            row.op:setCurrentOptionByData(step.dir, true)
            filling = false
        end
        changed()
    end
    row.op.onOptionChange = function(_, _, key)
        if filling then
            return
        end
        if step.kind == 'sort' then
            step.dir = key
        else
            step.op = key
            showKind(row, step)
        end
        changed()
    end
    row.field2.onOptionChange = function(_, _, key)
        if filling then
            return
        end
        step.field2 = key
        if step.dir2 == 'none' then
            step.dir2 = FIELD[key].desc and 'desc' or 'asc'
            filling = true
            row.dir2:setCurrentOptionByData(step.dir2, true)
            filling = false
        end
        changed()
    end
    row.dir2.onOptionChange = function(_, _, key)
        if filling then
            return
        end
        step.dir2 = key
        changed()
    end
    row.value1.onTextChange = function(_, text)
        if filling then
            return
        end
        local value = readNumber(text)
        row.value1:setColor((text == '' or value) and '#e6e2ee' or '#ff7a6b')
        if step.kind == 'top' then
            step.n = value and math.floor(value) or nil
        else
            step.v1 = value
        end
        onAdvancedEdited()
    end
    row.value2.onTextChange = function(_, text)
        if filling then
            return
        end
        local value = readNumber(text)
        row.value2:setColor((text == '' or value) and '#e6e2ee' or '#ff7a6b')
        step.v2 = value
        onAdvancedEdited()
    end
    row.remove:setTooltip(tr('Remove this step'))
    row.remove.onClick = function()
        table.remove(steps, index)
        renderSteps()
        changed()
    end
    row.up:setEnabled(index > 1)
    row.down:setEnabled(index < #steps)
    row.up.onClick = function()
        steps[index], steps[index - 1] = steps[index - 1], steps[index]
        renderSteps()
        changed()
    end
    row.down.onClick = function()
        steps[index], steps[index + 1] = steps[index + 1], steps[index]
        renderSteps()
        changed()
    end
end

renderSteps = function()
    if not advWindow then
        return
    end
    filling = true
    advWindow.steps:destroyChildren()
    for index = 1, #steps do
        local row = g_ui.createWidget('AdvStepRow', advWindow.steps)
        bindRow(row, index)
    end
    filling = false
    advWindow.emptySteps:setVisible(#steps == 0)
end

local function fillSaved()
    local entries = {}
    for i, entry in ipairs(saved) do
        entries[#entries + 1] = { key = i, label = entry.name }
    end
    advWindow.savedBox:clearOptions()
    if #entries == 0 then
        advWindow.savedBox:addOption(tr('(none saved)'), 0)
    else
        for _, entry in ipairs(entries) do
            advWindow.savedBox:addOption(entry.label, entry.key)
        end
    end
    advWindow.savedUse:setEnabled(#entries > 0)
    advWindow.savedDelete:setEnabled(#entries > 0)
end

local PREVIEW_ROWS = 8
local BASE_COLUMNS = { level = true, hp = true, perKill = true, gold = true, xp = true, loot = true }

local function thousands(value)
    local text = tostring(math.floor((tonumber(value) or 0) + 0.5))
    while true do
        local replaced, count = text:gsub('^(-?%d+)(%d%d%d)', '%1.%2')
        text = replaced
        if count == 0 then
            return text
        end
    end
end

-- how a field reads in the preview: "x2.5" for rates, "120%" for damage
-- taken, "0.84" for the per-health ones, thousands for the rest
local function showValue(key, value)
    if value == nil then
        return '-'
    end
    if key == 'xp' or key == 'loot' or key == 'combined' or key == 'rare' or key == 'damage' then
        return string.format('x%.1f', value)
    elseif key == 'myElement' or key:find('^el:') then
        return string.format('%d%%', value)
    elseif key == 'xpPerHp' or key == 'goldPerHp' then
        return string.format('%.2f', value)
    elseif key == 'boss' then
        return value == 1 and tr('yes') or tr('no')
    end
    return thousands(value)
end

-- the result: how many are left after the steps and per step, and the
-- first monsters of the list with the numbers the steps look at
function advancedShowResult(total, counts, final, list)
    if not advWindow or not advWindow:isVisible() then
        return
    end
    advWindow.result:setText(tr('%d of %d monsters', final, total))
    for i, row in ipairs(advWindow.steps:getChildren()) do
        local count = counts and counts[i]
        row.number:setTooltip(count and tr('%d monsters left after this step', count) or tr('This step does nothing yet'))
        row.number:setColor(count and '#e2a443' or '#75688f')
    end
    -- the fields the steps use that the base columns do not show
    local extra, seen = {}, {}
    for _, step in ipairs(steps) do
        for _, key in ipairs({ step.field, step.kind == 'sort' and step.dir2 ~= 'none' and step.field2 or nil }) do
            if key and FIELD[key] and not BASE_COLUMNS[key] and not seen[key] and #extra < 2 then
                seen[key] = true
                extra[#extra + 1] = key
            end
        end
    end
    local panel = advWindow.preview
    panel:destroyChildren()
    list = list or {}
    if #list == 0 then
        local row = g_ui.createWidget('AdvPreviewRow', panel)
        row:setColor('#75688f')
        row:setText(tr('No monster passes these steps.'))
        return
    end
    for i = 1, math.min(PREVIEW_ROWS, #list) do
        local m = list[i]
        local parts = {
            string.format('#%d  %s', i, m.name),
            tr('Lvl') .. ' ' .. showValue('level', valueOf('level', m)),
            tr('HP') .. ' ' .. showValue('hp', valueOf('hp', m)),
            tr('XP/kill') .. ' ' .. showValue('perKill', valueOf('perKill', m)),
            tr('Gold/kill') .. ' ' .. showValue('gold', valueOf('gold', m)),
            tr('XP rate') .. ' ' .. showValue('xp', valueOf('xp', m)),
            tr('Loot rate') .. ' ' .. showValue('loot', valueOf('loot', m)),
        }
        for _, key in ipairs(extra) do
            parts[#parts + 1] = tr(FIELD[key].label) .. ': ' .. showValue(key, valueOf(key, m))
        end
        local row = g_ui.createWidget('AdvPreviewRow', panel)
        row:setText(table.concat(parts, '   '))
        row:setColor(i == 1 and '#ffe066' or (i == 2 and '#f0f0f0' or (i == 3 and '#ffc08a' or '#cbc0e0')))
    end
    if #list > PREVIEW_ROWS then
        local row = g_ui.createWidget('AdvPreviewRow', panel)
        row:setColor('#75688f')
        row:setText(tr('... and %d more in the list.', #list - PREVIEW_ROWS))
    end
end

function onAdvancedEdited()
    if editEvent then
        removeEvent(editEvent)
    end
    editEvent = scheduleEvent(function()
        editEvent = nil
        changed()
    end, 300)
end

local function addStep(step)
    steps[#steps + 1] = step
    renderSteps()
    changed()
    advWindow.stepScroll:setValue(advWindow.stepScroll:getMaximum())
end

function openAdvanced()
    if not advWindow then
        advWindow = g_ui.displayUI('advanced')
        fillCombo(advWindow.presetBox, (function()
            local list = {}
            for i, preset in ipairs(PRESETS) do
                list[i] = { key = i, label = preset.label }
            end
            return list
        end)())
        advWindow.presetUse.onClick = function()
            local option = advWindow.presetBox:getCurrentOption()
            local preset = option and PRESETS[option.data]
            if preset then
                steps = preset.build(myLevel())
                renderSteps()
                changed()
            end
        end
        advWindow.savedUse.onClick = function()
            local option = advWindow.savedBox:getCurrentOption()
            local entry = option and saved[option.data]
            if entry then
                steps = copySteps(entry.steps)
                renderSteps()
                changed()
            end
        end
        advWindow.savedDelete.onClick = function()
            local option = advWindow.savedBox:getCurrentOption()
            if option and saved[option.data] then
                table.remove(saved, option.data)
                store()
                fillSaved()
            end
        end
        advWindow.saveButton.onClick = function()
            local name = advWindow.saveName:getText():trim()
            if name == '' then
                name = tr('Filter %d', #saved + 1)
            end
            for i, entry in ipairs(saved) do
                if entry.name:lower() == name:lower() then
                    table.remove(saved, i)
                    break
                end
            end
            if #saved >= MAX_SAVED then
                table.remove(saved, 1)
            end
            saved[#saved + 1] = { name = name, steps = copySteps(steps) }
            store()
            fillSaved()
            advWindow.savedBox:setCurrentOptionByData(#saved, true)
            advWindow.saveName:setText('')
        end
        advWindow.saveButton:setTooltip(tr('Up to %d filters; one with the same name is replaced.', MAX_SAVED))
        advWindow.clearButton.onClick = function()
            steps = {}
            renderSteps()
            changed()
        end
        advWindow.addFilter.onClick = function()
            addStep({ kind = 'filter', field = 'hp', op = 'le' })
        end
        advWindow.addSort.onClick = function()
            addStep({ kind = 'sort', field = 'xp', dir = 'desc', field2 = 'perKill', dir2 = 'none' })
        end
        advWindow.addTop.onClick = function()
            addStep({ kind = 'top', n = 20 })
        end
    end
    fillSaved()
    renderSteps()
    advWindow:show()
    advWindow:raise()
    advWindow:focus()
    changed()
end

function closeAdvanced()
    if advWindow then
        advWindow:hide()
    end
end

function advancedClear()
    steps = {}
    store()
    if advWindow then
        renderSteps()
    end
end

function advancedInit()
    load()
end

function advancedTerminate()
    if editEvent then
        removeEvent(editEvent)
        editEvent = nil
    end
    if advWindow then
        advWindow:destroy()
        advWindow = nil
    end
end
