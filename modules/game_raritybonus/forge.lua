-- Forja de Raridade (forge.otui), the way Tibia's own forge is laid out: a
-- small window with three tabs and the rare items on the left (worn on top,
-- the backpack's below; a hover lists an item's bonuses, a click picks it).
--   Roll: one line per bonus of the item, with a box to keep it (the seal),
--     then for every bonus rolled again a wheel that spins for its type (one
--     slice per bonus the item can get) and a needle that swings over a
--     meter, from the bonus's lowest to its highest roll, for its value.
--   Upgrade: the item, its next grade, the chance and the price; a bar fills
--     while it forges, then the result (success or failure) with an OK.
--   My bonuses: the totals of what is worn, with their limits.
-- The server (scripts/rarity/bonus_window.lua, extended opcode 123) rolls;
-- the window only shows. raritybonus.lua routes the opcode here.

Forge = {}

local OPCODE = 123
local ANSWER_TIMEOUT = 8000

local GRADES = {
    uncommon  = { label = 'Communis',    color = '#5fc36e', pips = 1 },
    rare      = { label = 'Rarus',       color = '#5a9bff', pips = 2 },
    epic      = { label = 'Praeclarus',  color = '#b77cff', pips = 3 },
    legendary = { label = 'Legendarius', color = '#f0a33c', pips = 4 },
    mythic    = { label = 'Mythicus',    color = '#f2eeff', pips = 5 },
}

-- where a roll fell in its range: name and colour
local QUALITY = {
    { 0.999, 'Perfect', '#ffd75f' },
    { 0.85, 'Excellent', '#6fb2ff' },
    { 0.6, 'Good', '#7fd36a' },
    { 0.3, 'Fair', '#e2e2e2' },
    { 0, 'Weak', '#9a9a9a' },
}

-- a picture for each bonus on its slice of the wheel (images/forge/bonus,
-- cut from the client's imbuement icons): the element ones by their
-- element, the rest by kind
local BONUS_ICONS = {
    critical_chance = 'crit', critical_damage = 'crit', perfect_shot = 'crit', executioner = 'crit', onslaught = 'crit',
    spell_damage = 'flame_phys', physical_resist = 'shield_phys', reflect = 'shield_phys',
    life_leech = 'life', max_health = 'life', health_regen = 'life', mending = 'life', emergency_heal = 'life',
    ally_heal = 'life', vital_barrier = 'life', vanguard = 'life',
    mana_leech = 'mana', max_mana = 'mana', mana_regen = 'mana',
    melee_skill = 'sword', sword_skill = 'sword', attack = 'sword', axe_skill = 'axe', cleave = 'axe',
    club_skill = 'club', fist_skill = 'fist', distance_skill = 'bow', hit_chance = 'bow', long_shot = 'bow',
    shoot_range = 'bow', splinter = 'bow', magic_level = 'wand', magic_level_pct = 'wand', wand_damage = 'wand',
    amplification = 'wand', transcendence = 'wand', armor = 'shield', defense = 'shield', dodge = 'shield',
    speed = 'wings', attack_speed = 'wings', cooldown_reduction = 'wings', cooldown_chance = 'wings',
    momentum = 'boots', tier_momentum = 'boots', loot = 'backpack', rarity_find = 'backpack', experience = 'backpack',
}
for _, element in ipairs({ 'fire', 'ice', 'energy', 'earth', 'holy', 'death' }) do
    BONUS_ICONS[element .. '_resist'] = 'shield_' .. element
    BONUS_ICONS[element .. '_pierce'] = 'flame_' .. element
    BONUS_ICONS[element .. '_spell_damage'] = 'flame_' .. element
end

-- the Roll's pace: the wheel's spin, the needle's swing, the stop between
-- first how many bonuses come out (COUNT_MS), then for each the wheel
-- (SPIN_MS) and the needle (SWING_MS)
local COUNT_MS, SPIN_MS, SWING_MS, HOLD_MS = 1600, 2400, 2000, 450
local WHEEL = 232
-- the icons sit near the rim, upright towards it
local ICON_RADIUS = 90
-- '  ·  ' in Latin-1, the fonts' charset
local DOT = '  \183  '
local METER_ZONES = { 0.30, 0.30, 0.25, 0.13, 0.02 }

local window
local data -- the last summary from the server
local items, bySlot = {}, {}
local totalsByKey = {}
local selected -- slotId of the item shown
local tab = 'roll'
local seals = {} -- slotId -> bonus key kept on the next roll
local deltas = {} -- after a roll: bonus index -> change (number or 'new')
local deltaSlot
local rarityXp, gold = 0, 0
local confirmBox
local answerEvent
local pendingData -- a refresh that came in while an animation runs

local roll -- { phase = 'wait'|'show', slot, before, lock, pool, after, order, k, stage, t, ... }
local asc -- { phase = 'forging', slot, offer, fromKey, pct, answer }
local result -- the Upgrade's result screen
local wheelRot = 0
local wheelSlices = 0
local tickEvent

-- ---------------------------------------------------------------------------
-- small helpers, shared with raritybonus.lua
-- ---------------------------------------------------------------------------

function Forge.send(request)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(OPCODE, request)
    end
end

-- 12 -> "12", 14.4 -> "14.4"
function Forge.number(value)
    value = tonumber(value) or 0
    if math.floor(value) == value then
        return tostring(math.floor(value))
    end
    return string.format('%.1f', value)
end
local number = Forge.number

-- 25000000 -> "25kk", 3500000 -> "3.5kk", 800000 -> "800k"
function Forge.formatGold(value)
    value = tonumber(value) or 0
    if value >= 1000000 then
        local kk = value / 1000000
        return (math.floor(kk) == kk and string.format('%dkk', kk) or string.format('%.1fkk', math.floor(kk * 10) / 10))
    elseif value >= 1000 then
        return string.format('%dk', math.floor(value / 1000))
    end
    return tostring(value)
end
local formatGold = Forge.formatGold

function Forge.titleCase(text)
    return ((text or ''):gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

-- the item's name without the grade and element words the server adds
local SUFFIXES = {
    communis = true, rarus = true, praeclarus = true, legendarius = true, mythicus = true,
    igneus = true, terrenus = true, fulmineus = true, glacialis = true, sacer = true, mortifer = true, corporalis = true,
}
local function titleCase(text)
    local words = {}
    for word in (text or ''):gmatch('%S+') do
        table.insert(words, word)
    end
    while #words > 1 and SUFFIXES[words[#words]:lower()] do
        table.remove(words)
    end
    return Forge.titleCase(table.concat(words, ' '))
end

-- a tooltip in lines of about `width` letters
function Forge.wrapTip(text, width)
    width = width or 56
    local paragraphs = {}
    for paragraph in (text .. '\n'):gmatch('(.-)\n') do
        local lines, line = {}, ''
        for word in paragraph:gmatch('%S+') do
            if line ~= '' and #line + 1 + #word > width then
                table.insert(lines, line)
                line = word
            else
                line = line == '' and word or (line .. ' ' .. word)
            end
        end
        table.insert(lines, line)
        table.insert(paragraphs, table.concat(lines, '\n'))
    end
    return table.concat(paragraphs, '\n')
end

-- what a bonus does: the server's sentence, translated
local function describe(key)
    local entry = totalsByKey[key or '']
    if type(entry) ~= 'table' or type(entry.desc) ~= 'string' or entry.desc == '' then
        return nil
    end
    local args = type(entry.descArgs) == 'table' and entry.descArgs or {}
    return Forge.wrapTip(tr(entry.desc, unpack(args)))
end

function Forge.confirm(title, message, callback)
    if confirmBox then
        confirmBox:destroy()
    end
    local function close()
        if confirmBox then
            confirmBox:destroy()
            confirmBox = nil
        end
    end
    confirmBox = displayGeneralBox(title, message, {
        { text = tr('Yes'), callback = function() close(); callback() end },
        { text = tr('No'), callback = close },
        anchor = AnchorHorizontalCenter,
    }, function() close(); callback() end, close)
end

function Forge.xp()
    return rarityXp
end

local function plus(value, unit)
    return '+' .. number(value) .. (unit or '')
end

local function bonusText(bonus)
    return plus(bonus.value, bonus.unit) .. ' ' .. tr(bonus.label or '')
end

-- 0 (lowest roll) to 1 (top) for a bonus, or nil when the server sent none
local function qualityOf(bonus)
    if bonus.perfect then
        return 1
    end
    local q = tonumber(bonus.quality)
    if q then
        return math.max(0, math.min(1, q))
    end
    local min, max, value = tonumber(bonus.min), tonumber(bonus.max), tonumber(bonus.value)
    if min and max and value and max > min then
        return math.max(0, math.min(1, (value - min) / (max - min)))
    end
    return nil
end

local function quality(q, perfect)
    if perfect then
        return QUALITY[1]
    end
    for i = 2, #QUALITY do
        if (q or 0) >= QUALITY[i][1] then
            return QUALITY[i]
        end
    end
    return QUALITY[#QUALITY]
end

local function grade(key)
    return GRADES[key] or GRADES.uncommon
end

-- the item as the inventory shows it: its grade's shader and, from the
-- tooltip the server sends ("#rarity:<grade>" and the element tags), the
-- rarity frame with its gems. `gradeKey` shows it at another grade (the
-- Upgrade's next one)
local function setItem(widget, entry, gradeKey)
    local item = Item.create(entry.itemId or 0, 1)
    if entry.shader and entry.shader ~= '' then
        item:setShader(entry.shader)
    end
    local tooltip = entry.tooltip
    if gradeKey then
        tooltip = '#rarity:' .. gradeKey .. ((tooltip or ''):match('(\n.*)$') or '')
    end
    if tooltip and item.setTooltip then
        item:setTooltip(tooltip)
    end
    widget:setItem(item)
    if ItemsDatabase and ItemsDatabase.setItemRarityFrame then
        ItemsDatabase.setItemRarityFrame(widget, item)
    end
end

-- the game's item card (game_itemcard) on hover, as in the inventory
local function itemCard()
    local itemcard = modules.game_itemcard
    return itemcard and itemcard.showFor and itemcard or nil
end

local function hideCard()
    local itemcard = itemCard()
    if itemcard then
        itemcard.hide()
    end
end

local function hoverCard(widget, entry)
    widget.onHoverChange = function(w, hovered)
        local itemcard = itemCard()
        if not itemcard or type(entry.card) ~= 'table' then
            return
        end
        if hovered then
            itemcard.showFor(entry.card, w)
        else
            itemcard.hide()
        end
    end
end

-- the bottom bar has room for about 50 letters: a longer message is cut
-- there and shown whole on hover
local STATUS_MAX = 46
local function setStatus(text, color)
    if window then
        local status = window.bottomBar.status
        text = text or ''
        status:setText(#text > STATUS_MAX and (text:sub(1, STATUS_MAX - 3) .. '...') or text)
        status:setTooltip(#text > STATUS_MAX and Forge.wrapTip(text) or nil)
        status:setColor(color or '#7fd35a')
    end
end

local function sameKey(list, key)
    for _, bonus in ipairs(list or {}) do
        if bonus.key == key then
            return bonus
        end
    end
end

local function stopTick()
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
end

local function busy()
    return roll ~= nil or (asc ~= nil and asc.phase == 'forging')
end

local function page()
    return window.body.right
end

-- ---------------------------------------------------------------------------
-- the items on the left
-- ---------------------------------------------------------------------------

local function itemTip(entry)
    local lines = { titleCase(entry.name) .. ' (' .. grade(entry.rarity).label .. ')' }
    for _, bonus in ipairs(entry.bonuses or {}) do
        table.insert(lines, bonusText(bonus))
    end
    if entry.bag then
        table.insert(lines, tr('(in the backpack)'))
    end
    return table.concat(lines, '\n')
end

local function pickItem(slot)
    if busy() then
        return
    end
    if confirmBox and slot ~= selected then
        confirmBox:destroy()
        confirmBox = nil
    end
    if slot ~= selected then
        setStatus('')
        deltas, deltaSlot = {}, nil
    end
    selected = slot
    result = nil
    Forge.refresh()
end

local function fillGrid(grid, list)
    grid:destroyChildren()
    for _, entry in ipairs(list) do
        local w = g_ui.createWidget('ForgeSlot', grid)
        setItem(w.item, entry)
        if entry.slotId == selected then
            w:setBackgroundColor('#4a4a4a')
            w:setBorderColor('#d8d8d8')
        end
        if type(entry.card) == 'table' then
            hoverCard(w, entry)
        else
            w:setTooltip(itemTip(entry))
        end
        w.onClick = function() pickItem(entry.slotId) end
    end
end

local function fillItems()
    local left = window.body.left
    local worn, bag = {}, {}
    for _, entry in ipairs(items) do
        table.insert(entry.bag and bag or worn, entry)
    end
    fillGrid(left.wornGrid, worn)
    left.wornGrid:setHeight(math.max(1, math.ceil(#worn / 3)) * 40 - 4)
    hideCard()
    fillGrid(left.bagGrid, bag)
    -- the scrollbar only when the backpack's items need it
    left.bagScroll:setVisible(math.ceil(#bag / 3) * 40 - 4 > left.bagGrid:getHeight())
    -- the count beside the title: the narrow column has no room for words
    left.bagNote:setText('(' .. #bag .. ')')
end

local function fillHead(entry)
    local head = page().head
    local g = grade(entry.rarity)
    setItem(head.itemBox.item, entry)
    hoverCard(head.itemBox, entry)
    head.name:setText(titleCase(entry.name))
    local max = math.max(1, tonumber(entry.maxBonuses) or #(entry.bonuses or {}))
    local info = g.label .. DOT .. tr('%d of %d bonuses', #(entry.bonuses or {}), max) .. DOT .. tr(entry.slot or '')
    if entry.bag then
        info = info .. DOT .. tr('in the backpack')
    end
    head.info:setText(info)
    head.info:setColor(g.color)
    local tip = {}
    if (tonumber(entry.level) or 0) > 0 then
        table.insert(tip, tr('Level %d', entry.level))
    end
    if entry.finder then
        table.insert(tip, tr('Found by you: +20%'))
    end
    head.info:setTooltip(#tip > 0 and table.concat(tip, '\n') or nil)
end

-- ---------------------------------------------------------------------------
-- Roll: the wheel and the meter
-- ---------------------------------------------------------------------------

-- the wheel's picture and one name per slice, for this pool
-- the icons are not children of the wheel: the engine doesn't compose a
-- turned widget inside a turned parent, so each frame puts them back on
-- their slice, at the wheel's angle
local wheelIcons = {}
local WHEEL_X, WHEEL_Y = 2, 10 -- the wheel's place inside wheelHolder

local function setWheel(rot)
    page().rollPage.wheelBox.wheelHolder.wheel:setRotation(rot % 360)
    for _, icon in ipairs(wheelIcons) do
        local a = icon.angle + rot
        local rad = math.rad(a)
        local size = icon:getWidth()
        icon:setMarginLeft(math.floor(WHEEL_X + WHEEL / 2 + ICON_RADIUS * math.sin(rad) - size / 2 + 0.5))
        icon:setMarginTop(math.floor(WHEEL_Y + WHEEL / 2 - ICON_RADIUS * math.cos(rad) - size / 2 + 0.5))
    end
end

-- the wheel's picture and one icon per slice, for this pool
local function buildWheel(pool)
    local holder = page().rollPage.wheelBox.wheelHolder
    local n = math.max(2, math.min(40, #pool))
    for _, icon in ipairs(wheelIcons) do
        icon:destroy()
    end
    wheelIcons = {}
    holder.wheel:setImageSource('/game_raritybonus/images/forge/wheel/wheel_' .. n)
    wheelSlices = #pool
    local seg = 360 / math.max(1, #pool)
    -- as big as the slice allows at that radius, from the icons scaled
    -- ahead with a smooth filter (images/forge/bonus/s16, s20, s24): scaled
    -- or turned here they came out pixelated, so they stay upright
    local room = ICON_RADIUS * math.rad(seg) * 0.85
    local size = room >= 24 and 24 or room >= 20 and 20 or 16
    for i, entry in ipairs(pool) do
        -- a bonus with no picture of its own (a vocation's spell) takes the wand
        local icon = g_ui.createWidget('ForgeWheelIcon', holder)
        icon:setImageSource('/game_raritybonus/images/forge/bonus/s' .. size .. '/' .. (BONUS_ICONS[entry.key or ''] or 'wand'))
        icon:setSize({ width = size, height = size })
        icon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        icon:addAnchor(AnchorTop, 'parent', AnchorTop)
        icon.angle = (i - 0.5) * seg
        icon.key = entry.key
        table.insert(wheelIcons, icon)
    end
    -- the pointer over the icons
    holder.pointer:raise()
    setWheel(wheelRot)
end

-- the winning slice's icon stays lit, the others dim
local function lightSlice(key)
    for _, icon in ipairs(wheelIcons) do
        icon:setOpacity((key == nil or icon.key == key) and 1 or 0.3)
    end
end

-- the angle that brings `key`'s slice under the pointer, 5 turns on
local function wheelTarget(from, pool, key)
    local n = math.max(1, #pool)
    local idx = 1
    for i, entry in ipairs(pool) do
        if entry.key == key then
            idx = i
        end
    end
    local seg = 360 / n
    local center = (idx - 0.5) * seg
    local base = from - (from % 360)
    return base + 360 * 5 + (360 - center) + (math.random() - 0.5) * seg * 0.6
end

local function layoutMeter()
    local meter = page().rollPage.wheelBox.meter
    local width = meter:getWidth()
    if width < 40 then
        width = 200
    end
    local legend = page().rollPage.wheelBox.legend
    for i = 1, 4 do
        local w = math.floor(width * METER_ZONES[i] + 0.5) - 1
        meter['z' .. i]:setWidth(w)
        legend['l' .. i]:setWidth(i < 4 and w + 1 or w)
    end
    return width
end

local function setNeedle(frac)
    local meter = page().rollPage.wheelBox.meter
    local width = layoutMeter()
    meter.needle:setVisible(frac ~= nil)
    if frac then
        meter.needle:setMarginLeft(math.floor(math.max(0, math.min(1, frac)) * (width - 3) + 0.5))
    end
end

-- ---------------------------------------------------------------------------
-- Roll: the lines and the price
-- ---------------------------------------------------------------------------

local function lockable(entry)
    return entry and (tonumber(entry.lockCost) or 0) > 0 and #(entry.bonuses or {}) >= 2
end

local function fillRows(entry)
    local rp = page().rollPage
    rp.rows:destroyChildren()
    local showing = roll and roll.phase == 'show' and roll.slot == entry.slotId
    local list = showing and roll.after or (roll and roll.slot == entry.slotId and roll.before) or entry.bonuses or {}
    local lock = seals[entry.slotId]
    local canLock = lockable(entry) and not busy()
    if showing and roll.stage == 'count' and roll.t < 1 then
        -- while the count is drawn every slot waits: the lines don't give
        -- the number away before it shows
        local padded = {}
        for i = 1, math.max(#list, tonumber(roll.max) or #list) do
            padded[i] = list[i] or { pad = true }
        end
        list = padded
    end
    for i, bonus in ipairs(list) do
        local row = g_ui.createWidget('ForgeRow', rp.rows)
        local isSealed = lock ~= nil and bonus.key == lock and (not roll or bonus.locked or not showing)
        local pos, done, now, wait = nil, false, false, false
        if roll and roll.slot == entry.slotId then
            if showing then
                for p, idx in ipairs(roll.order) do
                    if idx == i then
                        pos = p
                    end
                end
                if pos then
                    done = pos < roll.k or (pos == roll.k and roll.stage == 'value' and roll.t >= 1)
                    now = pos == roll.k and not done
                    wait = pos > roll.k
                end
            elseif not isSealed then
                -- the server rolls: every line not kept waits
                wait = true
            end
        end
        if bonus.pad then
            wait = true
        end
        local q = qualityOf(bonus)
        local look = quality(q, bonus.perfect)
        local text, color
        if now then
            local typeKnown = roll.stage == 'value' or roll.t >= 1
            text = typeKnown and tr('%s: drawing the value...', tr(bonus.label or '')) or tr('Bonus %d: spinning the wheel...', i)
            color = '#e2c46a'
            row:setBackgroundColor('#3a3326')
        elseif wait then
            text = tr('Bonus %d: waiting', i)
            color = '#707070'
        else
            text = bonusText(bonus)
            color = look[3]
            if roll and pos == roll.k and done then
                row:setBackgroundColor('#ffffff18')
            end
        end
        row.text:setText(text)
        row.text:setColor(color)
        row.seal:setChecked(isSealed)
        row.seal:setEnabled(canLock)
        row.seal:setTooltip(lockable(entry) and tr('Keep this bonus on the next roll') or tr('Keeping a bonus needs an item with 2 or more bonuses'))
        row.seal.onCheckChange = function(widget, checked)
            if busy() then
                return
            end
            if checked then
                seals[entry.slotId] = bonus.key
            elseif seals[entry.slotId] == bonus.key then
                seals[entry.slotId] = nil
            end
            deltas, deltaSlot = {}, nil
            Forge.refresh()
        end
        local hidden = now or wait
        row.range:setText((hidden or not bonus.min) and '' or '(' .. number(bonus.min) .. (bonus.unit or '') .. ' - ' .. number(bonus.max) .. (bonus.unit or '') .. ')')
        if isSealed and roll then
            row.quality:setText(tr('kept'))
            row.quality:setColor('#c9a24a')
        else
            row.quality:setText(hidden and '' or (q and tr(look[2]) or ''))
            row.quality:setColor(look[3])
        end
        local d = (not roll and deltaSlot == entry.slotId) and deltas[i] or nil
        if d == 'new' then
            row.delta:setText(tr('new'))
            row.delta:setColor('#c9a4ff')
        elseif d then
            row.delta:setText(math.abs(d) < 0.05 and '=' or ((d > 0 and '+' or '-') .. number(math.abs(math.floor(d * 10 + 0.5) / 10))))
            row.delta:setColor(d > 0.05 and '#7fd36a' or d < -0.05 and '#ff7a6a' or '#8c8c8c')
        else
            row.delta:setText('')
        end
        local tip = describe(bonus.key)
        row.text:setTooltip(tip)
        row:setTooltip(tip)
        row.text.onClick = function()
            if row.seal:isEnabled() then
                row.seal:setChecked(not row.seal:isChecked())
            end
        end
    end
    rp.rows:setHeight(math.max(1, #list) * 22)
    local max = math.max(1, tonumber(entry.maxBonuses) or #list)
    -- the slots left empty, and why: each roll draws how many bonuses
    -- come out first; known once the roll's count is shown
    local countKnown = not showing or roll.stage ~= 'count' or roll.t >= 1
    local empty = countKnown and (max - #list) or 0
    local justRolled = (showing and countKnown) or (not roll and deltaSlot == entry.slotId and next(deltas) ~= nil)
    if empty <= 0 then
        rp.emptySlots:setText('')
    elseif justRolled then
        rp.emptySlots:setText(empty == 1 and tr('%d of %d bonuses came out: 1 slot stays empty.', #list, max)
            or tr('%d of %d bonuses came out: %d slots stay empty.', #list, max, empty))
    else
        rp.emptySlots:setText(empty == 1 and tr('+ 1 empty slot (each roll draws 1 to %d bonuses)', max)
            or tr('+ %d empty slots (each roll draws 1 to %d bonuses)', empty, max))
    end
end

local function fillWheelBox(entry)
    local box = page().rollPage.wheelBox
    local pool = (roll and roll.slot == entry.slotId and roll.pool) or entry.pool or {}
    if wheelSlices ~= #pool or box.poolSlot ~= entry.slotId or box.poolSize ~= #pool then
        buildWheel(pool)
        box.poolSlot, box.poolSize = entry.slotId, #pool
    end
    local names = {}
    for _, p in ipairs(pool) do
        table.insert(names, tr(p.label or ''))
    end
    local showing = roll and roll.phase == 'show' and roll.slot == entry.slotId
    if not roll then
        box.caption:setText(tr('Can roll on this item (%d bonuses):', #pool))
        box.caption:setColor('#c8c8c8')
        box.sub:setText(table.concat(names, ', '))
        box.meterTitle:setText(tr('The value lands on this bar: further right, better'))
        box.meterValue:setText('')
        box.meterMin:setText(tr('min.'))
        box.meterMax:setText(tr('max.'))
        setNeedle(nil)
        lightSlice(nil)
        return
    end
    if not showing then
        box.caption:setText(tr('Rolling...'))
        box.caption:setColor('#e2c46a')
        box.sub:setText(tr('For each bonus: the wheel spins for the type, then the needle for the value.'))
        box.meterTitle:setText(tr('Value: after the wheel'))
        box.meterValue:setText('')
        setNeedle(nil)
        return
    end
    local spinning = roll.t < 1
    if roll.stage == 'count' then
        local max = math.max(1, tonumber(roll.max) or #roll.after)
        local shown = spinning and (math.floor((g_clock.millis() - roll.startedAt) / 90) % max + 1) or #roll.after
        box.caption:setText(spinning and tr('How many bonuses? %d...', shown) or tr('%d of %d bonuses came out!', #roll.after, max))
        box.caption:setColor(spinning and '#e2c46a' or '#ffd75f')
        local odds = {}
        for i, pct in ipairs(roll.counts or {}) do
            table.insert(odds, i .. ' = ' .. number(pct) .. '%')
        end
        local text = tr('First the roll draws how many bonuses the item gets (1 to %d). Slots left over stay empty.', max)
        if #odds > 0 then
            text = text .. '\n' .. tr('Odds: %s', table.concat(odds, ', '))
        end
        box.sub:setText(text)
        box.meterTitle:setText(tr('Value: after the wheel'))
        box.meterValue:setText('')
        setNeedle(nil)
        lightSlice(nil)
        return
    end
    local cur = roll.after[roll.order[roll.k]]
    box.sub:setText(tr('bonus %d of %d', roll.k, #roll.order) .. DOT .. (roll.stage == 'type' and tr('the wheel picks the type') or tr('the needle picks the value')))
    if roll.stage == 'type' then
        box.caption:setText(spinning and tr('Bonus %d: spinning the wheel...', roll.order[roll.k]) or tr('Type: %s!', tr(cur.label or '')))
        box.caption:setColor('#e2c46a')
        box.meterTitle:setText(tr('Value: after the wheel'))
        box.meterValue:setText('')
        box.meterMin:setText(tr('min.'))
        box.meterMax:setText(tr('max.'))
        setNeedle(nil)
        lightSlice(not spinning and cur.key or nil)
        return
    end
    lightSlice(cur.key)
    local q = qualityOf(cur) or 1
    local frac = q
    if spinning then
        local t = roll.t
        frac = math.max(0, math.min(1, q + (1 - t) ^ 2 * 0.9 * math.cos(2 * math.pi * 2.6 * t)))
    end
    local min, max = tonumber(cur.min), tonumber(cur.max)
    local shown = cur.value
    if spinning and min and max then
        shown = math.floor((min + frac * (max - min)) * 10 + 0.5) / 10
    end
    local look = spinning and quality(frac) or quality(q, cur.perfect)
    box.meterTitle:setText(tr(cur.label or ''))
    box.meterValue:setText(plus(shown, cur.unit))
    box.meterValue:setColor(look[3])
    box.meterMin:setText(min and plus(min, cur.unit) or '')
    box.meterMax:setText(max and tr('%s = Perfect', plus(max, cur.unit)) or '')
    setNeedle(frac)
    if spinning then
        box.caption:setText(tr('%s: how much?', tr(cur.label or '')))
        box.caption:setColor('#e2c46a')
    else
        box.caption:setText(tr('Rolled: %s (%s)!', bonusText(cur), tr(look[2])))
        box.caption:setColor(look[3])
    end
end

local function fillRoll(entry)
    local rp = page().rollPage
    fillRows(entry)
    fillWheelBox(entry)
    local lock = seals[entry.slotId]
    local sealed = sameKey(entry.bonuses, lock)
    local max = math.max(1, tonumber(entry.maxBonuses) or 1)
    if roll then
        rp.hint:setText(tr('For each bonus: the wheel spins for the type, then the needle for the value. A kept bonus stays.'))
        rp.hint:setColor('#e2c46a')
    elseif deltaSlot == entry.slotId and next(deltas) then
        rp.hint:setText(tr('Done: green went up, red went down, new = a different bonus.'))
        rp.hint:setColor('#a8a8a8')
    elseif sealed then
        rp.hint:setText(tr('%s stays at %s. The other bonuses are rolled again.', tr(sealed.label or ''), plus(sealed.value, sealed.unit)))
        rp.hint:setColor('#a8a8a8')
    elseif lockable(entry) then
        rp.hint:setText(tr('Tick a bonus to keep it. Everything else is rolled again (1 to %d bonuses).', max))
        rp.hint:setColor('#a8a8a8')
    else
        rp.hint:setText(tr('The bonuses are rolled again (1 to %d bonuses).', max))
        rp.hint:setColor('#a8a8a8')
    end
    local bar = rp.costBar
    local cost = tonumber(entry.rerollCost) or 0
    local lockGold = sealed and (tonumber(entry.lockCost) or 0) or 0
    bar.costXp:setText(tr('%d Rarity XP', cost))
    bar.costXp:setColor(rarityXp >= cost and '#c9a4ff' or '#ff7a6a')
    bar.costGoldIcon:setVisible(lockGold > 0)
    bar.costGold:setVisible(lockGold > 0)
    bar.costGold:setText(tr('%s (seal)', formatGold(lockGold)))
    bar.costGold:setColor(gold >= lockGold and '#e2c46a' or '#ff7a6a')
    bar.skipButton:setVisible(roll ~= nil and roll.phase == 'show')
    bar.rollButton:setVisible(not (roll and roll.phase == 'show'))
    if roll then
        bar.rollButton:setText(tr('Rolling...'))
        bar.rollButton:setEnabled(false)
    elseif rarityXp < cost then
        bar.rollButton:setText(tr('Missing %d XP', cost - rarityXp))
        bar.rollButton:setEnabled(false)
    else
        bar.rollButton:setText((deltaSlot == entry.slotId and next(deltas)) and tr('Roll again') or tr('Roll'))
        bar.rollButton:setEnabled(cost > 0 and gold >= lockGold)
    end
    local names = {}
    for _, p in ipairs(entry.pool or {}) do
        table.insert(names, tr(p.label or ''))
    end
    bar.rollButton:setTooltip(Forge.wrapTip(tr('Can roll on this item: %s', table.concat(names, ', '))))
end

-- ---------------------------------------------------------------------------
-- Upgrade
-- ---------------------------------------------------------------------------

local function fillUp(entry)
    local up = page().upPage
    local res = up.result
    res:setVisible(result ~= nil and result.slot == entry.slotId)
    if res:isVisible() then
        local g = grade(result.grade)
        res.title:setText(result.win and tr('Success!') or tr('Failed'))
        res.title:setColor(result.win and '#7fd36a' or '#ff7a6a')
        setItem(res.box.item, entry, result.grade)
        hoverCard(res.box, entry)
        res.glow:setVisible(result.win)
        res.glow:setImageColor(g.color)
        res.grade:setText(titleCase(entry.name) .. DOT .. g.label)
        res.grade:setColor(g.color)
        res.text:setText(result.text)
        res.lines:destroyChildren()
        for _, line in ipairs(result.lines or {}) do
            local l = g_ui.createWidget('ForgeResultLine', res.lines)
            l:setText(line.text)
            l:setColor(line.color)
        end
        return
    end
    local offer = (asc and asc.slot == entry.slotId and asc.offer) or entry.upgrade
    local has = offer ~= nil
    for _, id in ipairs({ 'pair', 'path', 'chance', 'explain', 'upCostBar' }) do
        up[id]:setVisible(has)
    end
    up.maxText:setVisible(not has)
    if not has then
        up.maxText:setText(tr('This item is already at the highest grade (%s). Use the Roll tab to roll its bonuses again.', grade(entry.rarity).label))
        up.forgeBar:setVisible(false)
        up.forgePct:setVisible(false)
        return
    end
    local from, to = grade(entry.rarity), grade(offer.to)
    setItem(up.pair.fromBox.item, entry)
    hoverCard(up.pair.fromBox, entry)
    setItem(up.pair.toBox.item, entry, offer.to)
    up.path:setText(from.label .. '  >  ' .. to.label)
    up.path:setColor(to.color)
    up.chance:setText(tr('Success chance: %d%%', tonumber(offer.chance) or 0))
    local forging = asc ~= nil and asc.phase == 'forging' and asc.slot == entry.slotId
    up.forgeBar:setVisible(forging)
    up.forgePct:setVisible(forging)
    up.explain:setVisible(not forging)
    if forging then
        local width = up.forgeBar:getWidth() - 2
        up.forgeBar.fill:setWidth(math.max(0, math.floor(width * asc.pct / 100)))
        up.forgePct:setText(tr('Forging... %d%%', asc.pct))
    else
        up.explain:setText(tr('If it works: the item goes up a grade and its bonuses are rolled again at the new grade.') .. '\n' ..
            tr('If it fails: the item stays as it is. The cost is spent anyway.'))
    end
    local bar = up.upCostBar
    local needGold, needXp = tonumber(offer.gold) or 0, tonumber(offer.xp) or 0
    bar.upGold:setText(formatGold(needGold))
    bar.upGold:setColor(gold >= needGold and '#e2c46a' or '#ff7a6a')
    bar.upXp:setText(tr('%d Rarity XP', needXp))
    bar.upXp:setColor(rarityXp >= needXp and '#c9a4ff' or '#ff7a6a')
    bar.upButton:setText(forging and tr('Forging...') or tr('Upgrade'))
    bar.upButton:setEnabled(not busy() and gold >= needGold and rarityXp >= needXp)
end

-- ---------------------------------------------------------------------------
-- My bonuses
-- ---------------------------------------------------------------------------

local function fillTotals()
    local tp = page().totalsPage
    tp.list:destroyChildren()
    -- the scrollbar only when the lines need it
    tp.listScroll:setVisible(#((data and data.totals) or {}) * 21 > tp.list:getHeight())
    for _, t in ipairs((data and data.totals) or {}) do
        local row = g_ui.createWidget('ForgeTotalRow', tp.list)
        local unit = t.unit or ''
        local cap = not t.perItem and tonumber(t.cap) or nil
        if cap and cap <= 0 then
            cap = nil
        end
        local sum = tonumber(t.total) or 0
        local full = cap and (t.capped or sum >= cap)
        row.name:setText(tr(t.label or ''))
        row.name:setColor(full and '#e2c46a' or '#d0d0d0')
        row.total:setText(plus(sum, unit))
        row.total:setColor(full and '#e2c46a' or '#e6e6e6')
        row.cap:setText(cap and (number(cap) .. unit) or '-')
        local lines = { tr(t.label or '') }
        for _, src in ipairs(t.sources or {}) do
            local it = items[tonumber(src.item) or 0]
            table.insert(lines, titleCase(src.name or (it and it.name) or '') .. '  ' .. plus(src.value, unit))
        end
        local desc = describe(t.key)
        if desc then
            table.insert(lines, '')
            table.insert(lines, desc)
        end
        row:setTooltip(table.concat(lines, '\n'))
    end
end

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

function Forge.refresh()
    if not window then
        return
    end
    local bar = window.bottomBar
    bar.xpLabel:setText(tr('Rarity XP: %d', rarityXp))
    window.tabs.tabRoll:setOn(tab == 'roll')
    window.tabs.tabUp:setOn(tab == 'up')
    window.tabs.tabTotals:setOn(tab == 'totals')
    fillItems()
    local right = page()
    local entry = bySlot[selected]
    right.empty:setVisible(entry == nil and tab ~= 'totals')
    right.head:setVisible(entry ~= nil and tab ~= 'totals')
    right.rollPage:setVisible(entry ~= nil and tab == 'roll')
    right.upPage:setVisible(entry ~= nil and tab == 'up')
    right.totalsPage:setVisible(tab == 'totals')
    if tab == 'totals' then
        fillTotals()
        return
    end
    if not entry then
        return
    end
    fillHead(entry)
    if tab == 'roll' then
        fillRoll(entry)
    else
        fillUp(entry)
    end
end

function forgeTab(name)
    if busy() then
        return
    end
    tab = name
    result = nil
    Forge.refresh()
end

-- ---------------------------------------------------------------------------
-- Roll: the animation
-- ---------------------------------------------------------------------------

local function finishRoll()
    stopTick()
    if not roll then
        return
    end
    local before, after, slot = roll.before or {}, roll.after or {}, roll.slot
    local lock = roll.lock
    deltas, deltaSlot = {}, slot
    for i, bonus in ipairs(after) do
        if bonus.key ~= lock then
            local old = before[i]
            deltas[i] = (old and old.key == bonus.key) and ((tonumber(bonus.value) or 0) - (tonumber(old.value) or 0)) or 'new'
        end
    end
    if roll.wheelTo then
        wheelRot = roll.wheelTo % 360
    end
    roll = nil
    local pending = Forge.pendingMessage
    Forge.pendingMessage = nil
    if pending and pending[1] then
        setStatus(pending[1], pending[2])
    end
    local d = pendingData
    pendingData = nil
    if d then
        Forge.apply(d)
    else
        Forge.refresh()
    end
end

local function startStage(stage)
    roll.stage, roll.t, roll.startedAt = stage, 0, g_clock.millis()
    if stage == 'type' then
        local cur = roll.after[roll.order[roll.k]]
        roll.wheelFrom = roll.wheelTo or wheelRot
        roll.wheelTo = wheelTarget(roll.wheelFrom, roll.pool, cur.key)
    end
end

local function rollTick()
    tickEvent = nil
    if not roll or not window then
        return
    end
    local now = g_clock.millis()
    if roll.phase == 'wait' then
        -- the server rolls: the wheel turns steadily
        wheelRot = wheelRot + 9
        setWheel(wheelRot)
        tickEvent = scheduleEvent(rollTick, 30)
        return
    end
    local len = roll.stage == 'count' and COUNT_MS or roll.stage == 'type' and SPIN_MS or SWING_MS
    local el = now - roll.startedAt
    local t = math.min(1, el / len)
    if roll.stage == 'type' then
        local e = 1 - (1 - t) ^ 3
        setWheel(roll.wheelFrom + (roll.wheelTo - roll.wheelFrom) * e)
    end
    local changed = (t >= 1) ~= (roll.t >= 1)
    roll.t = t
    if el >= len + HOLD_MS then
        if roll.stage == 'count' then
            roll.k = 1
            startStage('type')
        elseif roll.stage == 'type' then
            startStage('value')
        elseif roll.k < #roll.order then
            roll.k = roll.k + 1
            startStage('type')
        else
            finishRoll()
            return
        end
        changed = true
    end
    local entry = bySlot[roll.slot]
    if entry then
        if changed then
            fillRoll(entry)
        else
            fillWheelBox(entry)
        end
    end
    tickEvent = scheduleEvent(rollTick, 30)
end

-- the server's answer: the new bonuses, then the wheel and the needle for
-- each bonus rolled
local function showRoll(after)
    roll.after = after
    roll.order = {}
    for i, bonus in ipairs(after) do
        if bonus.key ~= roll.lock then
            table.insert(roll.order, i)
        end
    end
    if #roll.order == 0 or roll.skip then
        finishRoll()
        return
    end
    roll.phase = 'show'
    -- first how many bonuses came out; no line is being rolled yet
    roll.k = 0
    roll.wheelTo = wheelRot
    startStage('count')
    local entry = bySlot[roll.slot]
    if entry then
        fillRoll(entry)
    end
end

function forgeRoll()
    local entry = bySlot[selected]
    if not entry or busy() then
        return
    end
    local cost = tonumber(entry.rerollCost) or 0
    local lock = seals[selected]
    local again = deltaSlot == selected and next(deltas) ~= nil
    local slot, itemId = selected, entry.itemId
    local function go()
        local now = bySlot[slot]
        if not now or now.itemId ~= itemId then
            setStatus(tr('The item changed: pick it and try again.'), '#ff7a6a')
            return
        end
        selected = slot
        deltas, deltaSlot = {}, nil
        roll = { phase = 'wait', slot = slot, before = now.bonuses or {}, lock = lock, pool = now.pool or {},
            max = now.maxBonuses, counts = now.counts }
        setStatus(tr('Rolling...'), '#e2c46a')
        Forge.send({ action = 'rerollItem', slot = now.bag and nil or slot, fid = now.fid, lock = lock })
        Forge.expectAnswer()
        Forge.refresh()
        stopTick()
        rollTick()
    end
    if again then
        go()
        return
    end
    local lines, kept = {}, nil
    for _, bonus in ipairs(entry.bonuses or {}) do
        if bonus.key == lock then
            kept = bonusText(bonus)
        else
            table.insert(lines, bonusText(bonus))
        end
    end
    local text
    if kept then
        text = tr('Roll %s for %d Rarity XP and %s gold?\n\nKept, with its value: %s\n\nRolled again:\n%s\n\nThe new ones can be better or worse, and there is no way back.', titleCase(entry.name), cost, formatGold(entry.lockCost), kept, table.concat(lines, '\n'))
    else
        text = tr('Roll %s for %d Rarity XP?\n\nEvery bonus it has now is rolled again:\n%s\n\nThe new ones can be better or worse, and there is no way back.', titleCase(entry.name), cost, table.concat(lines, '\n'))
    end
    Forge.confirm(tr('Roll'), text, go)
end

function forgeSkip()
    if roll and roll.phase == 'show' then
        finishRoll()
    elseif roll then
        roll.skip = true
    end
end

-- ---------------------------------------------------------------------------
-- Upgrade: the bar and the result
-- ---------------------------------------------------------------------------

local function upResult(answer)
    local entry = bySlot[asc.slot] or {}
    local res = answer.result or {}
    local win = res.code == 'rerolled' and res.upgrade
    local r = { slot = asc.slot, win = win, shader = entry.shader }
    if win then
        r.grade = res.rarity or asc.offer.to
        r.text = tr('%s is now %s. Its bonuses were rolled again:', titleCase(res.name or entry.name), grade(r.grade).label)
        r.lines = {}
        for _, line in ipairs(res.rolled or {}) do
            local look = quality(tonumber(line.quality), line.perfect)
            table.insert(r.lines, { text = line.text or '', color = look[3] })
        end
    else
        r.grade = asc.fromKey
        r.text = tr('%s stays %s, as it was. Spent: %s gold and %d Rarity XP.', titleCase(entry.name or res.name), grade(asc.fromKey).label, formatGold(res.gold or asc.offer.gold), tonumber(res.xp or asc.offer.xp) or 0)
        r.lines = {}
    end
    return r
end

local function upTick()
    tickEvent = nil
    if not asc or asc.phase ~= 'forging' or not window then
        return
    end
    asc.pct = math.min(100, math.floor((g_clock.millis() - asc.startedAt) / 18))
    if asc.pct >= 100 and asc.answer then
        local d = asc.answer
        result = upResult(d)
        asc = nil
        local pending = Forge.pendingMessage
        Forge.pendingMessage = nil
        if pending and pending[1] then
            setStatus(pending[1], pending[2])
        end
        pendingData = nil
        Forge.apply(d)
        return
    end
    local entry = bySlot[asc.slot]
    if entry and tab == 'up' then
        fillUp(entry)
    end
    tickEvent = scheduleEvent(upTick, 30)
end

function forgeUpgrade()
    local entry = bySlot[selected]
    local up = entry and entry.upgrade
    if not up or busy() then
        return
    end
    local slot, itemId = selected, entry.itemId
    local function go()
        local now = bySlot[slot]
        if not now or now.itemId ~= itemId or not now.upgrade then
            setStatus(tr('The item changed: pick it and try again.'), '#ff7a6a')
            return
        end
        selected = slot
        result = nil
        asc = { phase = 'forging', slot = slot, offer = up, fromKey = now.rarity, pct = 0, startedAt = g_clock.millis() }
        setStatus(tr('Forging...'), '#e2c46a')
        Forge.send({ action = 'upgradeItem', slot = now.bag and nil or slot, fid = now.fid })
        Forge.expectAnswer()
        Forge.refresh()
        stopTick()
        upTick()
    end
    Forge.confirm(tr('Upgrade'), tr('Upgrade %s to %s?\n\nPrice: %s gold and %d Rarity XP, paid even if it fails.\nChance: %d%%.\n\nOn success the item becomes %s and rolls its bonuses again at that grade. On a failure it stays exactly as it is.', titleCase(entry.name), up.label or '', formatGold(up.gold), tonumber(up.xp) or 0, tonumber(up.chance) or 0, up.label or ''), go)
end

function forgeCloseResult()
    result = nil
    Forge.refresh()
end

-- ---------------------------------------------------------------------------
-- the server's answers
-- ---------------------------------------------------------------------------

local function messageOf(d)
    local res = d.result
    if type(res) ~= 'table' then
        return d.message and tr(d.message) or nil
    end
    local code = res.code
    if code == 'rerolled' and res.upgrade then
        return tr('Upgrade! %s: %s. (-%s gold, -%d Rarity XP)', titleCase(res.name), table.concat(res.bonuses or {}, ', '), formatGold(res.gold), tonumber(res.cost) or 0)
    elseif code == 'rerolled' then
        local text = tr('%s rolled: %s. (-%d Rarity XP)', titleCase(res.name), table.concat(res.bonuses or {}, ', '), tonumber(res.cost) or 0)
        if res.perfect then
            text = text .. ' ' .. tr('Perfect roll!')
        end
        if (tonumber(res.gold) or 0) > 0 then
            text = text .. ' ' .. tr('(-%s gold for the seal)', formatGold(res.gold))
        end
        return text
    elseif code == 'upgradeFailed' then
        return tr('The upgrade to %s failed (%d%% chance): %s stays as it was. (-%s gold, -%d Rarity XP)', res.to or '', tonumber(res.chance) or 0, titleCase(res.name), formatGold(res.gold), tonumber(res.xp) or 0)
    elseif code == 'xp' then
        return tr('You need %d Rarity XP and have %d. Kill Pale, Ashen, Obsidian and Lord of Death monsters to earn more.', tonumber(res.cost) or 0, tonumber(res.balance) or 0)
    elseif code == 'gone' then
        return tr('That item is no longer equipped or in your backpack.')
    elseif code == 'gold' then
        return tr('You need %s gold in your backpack and bank.', formatGold(res.gold))
    elseif code == 'bought' then
        return res.currency == 'coins' and tr('+%d Rarity XP! (-%d Mythos Coins)', tonumber(res.xp) or 0, tonumber(res.price) or 0)
            or tr('+%d Rarity XP! (-%d Hunt Points)', tonumber(res.xp) or 0, tonumber(res.price) or 0)
    elseif code == 'coins' then
        return tr('This pack costs %d Mythos Coins and you have %d.', tonumber(res.price) or 0, tonumber(res.have) or 0)
    elseif code == 'points' then
        return tr('This pack costs %d Hunt Points and you have %d.', tonumber(res.price) or 0, tonumber(res.have) or 0)
    elseif code == 'pack' then
        return tr('This pack is not sold any more.')
    end
    return d.message and tr(d.message) or nil
end

-- a summary from the server becomes the window's data
-- the server's UTF-8 to Latin-1, the fonts' charset (as game_itemcard does)
local function latin1(value)
    if type(value) == 'string' then
        return (value:gsub('[\194\195][\128-\191]', function(pair)
            local a, b = pair:byte(1, 2)
            return string.char((a - 194) * 64 + b)
        end))
    elseif type(value) == 'table' then
        for k, v in pairs(value) do
            value[k] = latin1(v)
        end
    end
    return value
end

function Forge.apply(d)
    data = d
    if not d.cardsReady then
        d.cardsReady = true
        for _, entry in ipairs(d.items or {}) do
            if type(entry.card) == 'table' then
                latin1(entry.card)
            end
        end
    end
    rarityXp = tonumber(d.rarityXp) or rarityXp
    gold = tonumber(d.gold) or gold
    items, bySlot, totalsByKey = d.items or {}, {}, {}
    for _, entry in ipairs(items) do
        bySlot[entry.slotId] = entry
        if seals[entry.slotId] and not sameKey(entry.bonuses, seals[entry.slotId]) then
            seals[entry.slotId] = nil
        end
    end
    for _, t in ipairs(d.totals or {}) do
        totalsByKey[t.key or ''] = t
    end
    if not bySlot[selected] then
        selected = items[1] and items[1].slotId or nil
    end
    Forge.refresh()
end

-- every 'bonuses' answer: an animation may be waiting for it
function Forge.onBonuses(d)
    local res = type(d.result) == 'table' and d.result or nil
    if answerEvent and res then
        removeEvent(answerEvent)
        answerEvent = nil
    end
    local message = messageOf(d)
    local color = d.ok == false and '#ff6464' or '#7fd35a'
    rarityXp = tonumber(d.rarityXp) or rarityXp
    gold = tonumber(d.gold) or gold
    if res and roll and roll.phase == 'wait' then
        if res.code == 'rerolled' and not res.upgrade then
            Forge.pendingMessage = { message, color }
            pendingData = d
            -- the new bonuses as the window shows them (finder's share in)
            local after
            for _, entry in ipairs(d.items or {}) do
                if entry.slotId == roll.slot then
                    after = entry.bonuses
                end
            end
            if not after then
                after = {}
                for _, line in ipairs(res.rolled or {}) do
                    table.insert(after, {
                        key = line.key, label = line.label, unit = line.unit, quality = line.quality, perfect = line.perfect,
                        min = line.min, max = line.max, value = tonumber((line.text or ''):match('^%+(%-?[%d%.]+)')) or 0,
                    })
                end
            end
            showRoll(after)
            return
        end
        -- refused (no XP, too fast, gone...): the wheel stops
        stopTick()
        roll = nil
        setStatus(message, color)
        Forge.apply(d)
        return
    end
    if res and asc and asc.phase == 'forging' then
        if (res.code == 'rerolled' and res.upgrade) or res.code == 'upgradeFailed' then
            Forge.pendingMessage = { message, color }
            asc.answer = d
            pendingData = d
            return
        end
        stopTick()
        asc = nil
        setStatus(message, color)
        Forge.apply(d)
        return
    end
    if busy() then
        -- a refresh while the wheel or the bar moves: after them
        pendingData = d
        return
    end
    if message then
        setStatus(message, color)
    end
    Forge.apply(d)
end

-- the Rarity XP balance changed (a kill, the Store)
function Forge.onXp(xp)
    rarityXp = tonumber(xp) or rarityXp
    if window and window:isVisible() and not busy() then
        Forge.refresh()
    end
end

-- no answer to a roll or an upgrade: stop waiting and ask again
function Forge.expectAnswer()
    if answerEvent then
        removeEvent(answerEvent)
    end
    answerEvent = scheduleEvent(function()
        answerEvent = nil
        local stuck = (roll and roll.phase == 'wait') or (asc and asc.phase == 'forging' and not asc.answer)
        if not stuck then
            return
        end
        stopTick()
        roll, asc = nil, nil
        setStatus(tr('No answer from the server. Try again.'), '#ff6464')
        Forge.send({ action = 'open' })
    end, ANSWER_TIMEOUT)
end

function Forge.showBank(d)
    if not window then
        return
    end
    local bank = tonumber(d.bank)
    local backpack = tonumber(d.backpack)
    local amount = bank and backpack and (bank + backpack) or tonumber(d.gold) or gold
    local bar = window.bottomBar
    bar.bankBox:setText(tr('Gold: %s', formatMoney(math.floor(amount), '.')))
    local tooltip = bank and backpack
        and tr('Bank: %s gold\nBackpack: %s gold\nThe gold prices (seal, Upgrade) are paid from the backpack and the bank.', formatMoney(bank, '.'), formatMoney(backpack, '.'))
        or tr('Your gold, backpack and bank.')
    bar.bankBox:setTooltip(tooltip)
    bar.goldIcon:setTooltip(tooltip)
end

function Forge.window()
    return window
end

function Forge.busy()
    return busy()
end

function Forge.create()
    window = g_ui.displayUI('forge')
    window:hide()
end

function Forge.reset()
    stopTick()
    if answerEvent then
        removeEvent(answerEvent)
        answerEvent = nil
    end
    roll, asc, result, pendingData = nil, nil, nil, nil
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
    -- the next character starts clean: a seal left from this one would be
    -- charged on its item in the same slot with the same bonus
    seals, deltas, deltaSlot, selected, tab = {}, {}, nil, nil, 'roll'
end

function Forge.destroy()
    Forge.reset()
    wheelIcons, wheelSlices = {}, 0
    if window then
        window:destroy()
        window = nil
    end
end

function Forge.closeConfirm()
    hideCard()
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
end
