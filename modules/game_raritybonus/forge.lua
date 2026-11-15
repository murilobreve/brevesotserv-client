-- Roleta de Raridade (forge.otui): three tabs, the rare items on the left
-- (worn on top, the backpack's below; a hover shows an item's card, a click
-- picks it).
--   Roll: one line per bonus slot of the item's grade (a lock keeps one
--     bonus, an empty slot shows as empty), the price against what the
--     player has and the Roll button. The roll plays in three stages, named
--     under the wheel: how many bonuses come out, then for each the wheel
--     spins for its type (one slice per bonus the item can get) and the
--     disc at the wheel's centre swings to its value.
--   Upgrade: the item, its next grade, the chance and the price; a bar fills
--     while it forges, then the result (success or failure) with an OK.
--   My bonuses: the totals of what is worn.
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

-- the slices' colours, by what the bonus is (its icon): attack and weapon
-- skills, magic, plain defence, life, mana, speed and gains, and each
-- element in its own colour. A slice at an even place takes a darker shade,
-- so two neighbours of one colour still read as two slices
local SLICE_COLORS = {
    attack = '#8f3524', magic = '#5a45a0', defense = '#3f5a78', life = '#8c2f58', mana = '#2a4f9a', utility = '#8a6a26',
    fire = '#a8451c', earth = '#2f7038', energy = '#7a2f96', ice = '#1f7a94', holy = '#978628', death = '#3d3a47',
    phys = '#5b6470',
}
local ICON_FAMILY = {
    crit = 'attack', sword = 'attack', axe = 'attack', club = 'attack', fist = 'attack', bow = 'attack',
    wand = 'magic', shield = 'defense', life = 'life', mana = 'mana',
    wings = 'utility', boots = 'utility', backpack = 'utility',
}
local function sliceColor(iconName, index)
    -- shield_fire, flame_ice...: the element after the underscore
    local family = ICON_FAMILY[iconName] or iconName:match('_(%a+)$')
    local color = SLICE_COLORS[family] or SLICE_COLORS.magic
    if index % 2 == 1 then
        return color
    end
    local r, g, b = color:match('#(%x%x)(%x%x)(%x%x)')
    return string.format('#%02x%02x%02x', math.floor(tonumber(r, 16) * 0.74), math.floor(tonumber(g, 16) * 0.74),
        math.floor(tonumber(b, 16) * 0.74))
end

-- the Roll's pace: first how many bonuses come out (COUNT_MS), then for
-- each the wheel's spin (SPIN_MS) and its value's swing on the disc at the
-- wheel's centre (SWING_MS); HOLD_MS is the stop between them
local COUNT_MS, SPIN_MS, SWING_MS, HOLD_MS = 1600, 2400, 2000, 450
local WHEEL = 292 -- the wheel's pictures (tools/gerar-roleta-forja.py)
-- the icons sit near the rim, upright: the sizes they come in (images/forge/
-- bonus/s16 to s40) and, for a size, how far from the centre they sit
local ICON_SIZES = { 40, 36, 32, 28, 24, 20, 16 }
local function iconRadiusFor(size)
    return math.min(116, 136 - size / 2)
end
local iconRadius = 116
-- '  ·  ' in Latin-1, the fonts' charset
local DOT = '  \183  '

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
            w:setBackgroundColor('#b296f530')
            w:setBorderColor('#b296f5')
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
    -- how many bonuses it has shows as its slots, under the head
    local info = g.label .. DOT .. tr(entry.slot or '')
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
-- Roll: the wheel, its disc and the stages
-- ---------------------------------------------------------------------------

-- the wheel's picture and one name per slice, for this pool
-- the icons are not children of the wheel: the engine doesn't compose a
-- turned widget inside a turned parent, so each frame puts them back on
-- their slice, at the wheel's angle
local wheelIcons = {}
local wheelWedges = {}
local WHEEL_X, WHEEL_Y = 2, 10 -- the wheel's place inside wheelHolder

local function setWheel(rot)
    page().rollPage.wheelBox.wheelHolder.wheel:setRotation(rot % 360)
    for _, wedge in ipairs(wheelWedges) do
        wedge:setRotation((wedge.angle + rot) % 360)
    end
    for _, icon in ipairs(wheelIcons) do
        local a = icon.angle + rot
        local rad = math.rad(a)
        local size = icon:getWidth()
        icon:setMarginLeft(math.floor(WHEEL_X + WHEEL / 2 + iconRadius * math.sin(rad) - size / 2 + 0.5))
        icon:setMarginTop(math.floor(WHEEL_Y + WHEEL / 2 - iconRadius * math.cos(rad) - size / 2 + 0.5))
    end
end

-- the wheel's picture and one icon per slice, for this pool
local function buildWheel(pool)
    local holder = page().rollPage.wheelBox.wheelHolder
    local n = math.max(2, math.min(40, #pool))
    for _, icon in ipairs(wheelIcons) do
        icon:destroy()
    end
    for _, wedge in ipairs(wheelWedges) do
        wedge:destroy()
    end
    wheelIcons, wheelWedges = {}, {}
    holder.wheel:setImageSource('/game_raritybonus/images/forge/wheel/lines_' .. n)
    wheelSlices = #pool
    local seg = 360 / math.max(1, #pool)
    -- the slices under the trim: one wedge per bonus, in its family's colour
    -- (the wheel has pictures for 2 to 40 slices)
    if #pool == n then
        for i, entry in ipairs(pool) do
            local wedge = g_ui.createWidget('ForgeWedge', holder)
            wedge:setImageSource('/game_raritybonus/images/forge/wheel/wedge_' .. n)
            wedge:setImageColor(sliceColor(BONUS_ICONS[entry.key or ''] or 'wand', i))
            wedge:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            wedge:addAnchor(AnchorTop, 'parent', AnchorTop)
            wedge:setMarginLeft(WHEEL_X)
            wedge:setMarginTop(WHEEL_Y)
            wedge.angle = (i - 1) * seg
            wedge.key = entry.key
            table.insert(wheelWedges, wedge)
        end
    end
    holder.wheel:raise()
    holder.hub:raise()
    -- the biggest size whose icon fits between the slice's two lines where
    -- its inner edge sits; the icons come scaled ahead with a smooth filter
    -- (scaled or turned here they came out pixelated), so they stay upright
    local size = ICON_SIZES[#ICON_SIZES]
    local half = math.tan(math.rad(seg / 2))
    for _, candidate in ipairs(ICON_SIZES) do
        if seg >= 180 or candidate <= 2 * (iconRadiusFor(candidate) - candidate / 2) * half * 1.05 then
            size = candidate
            break
        end
    end
    iconRadius = iconRadiusFor(size)
    for i, entry in ipairs(pool) do
        -- a bonus with no picture of its own (a vocation's spell) takes the wand
        local icon = g_ui.createWidget('ForgeWheelIcon', holder)
        icon:setImageSource('/game_raritybonus/images/forge/bonus/s' .. size .. '/' .. (BONUS_ICONS[entry.key or ''] or 'wand'))
        icon:setSize({ width = size, height = size })
        icon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        icon:addAnchor(AnchorTop, 'parent', AnchorTop)
        icon.angle = (i - 0.5) * seg
        icon.key = entry.key
        -- the slice says what it is, and its range, under the mouse
        local span = entry.min and (number(entry.min) .. (entry.unit or '') .. ' - ' .. number(entry.max) .. (entry.unit or '')) or ''
        icon:setTooltip(tr(entry.label or '') .. (span ~= '' and ('\n' .. span) or ''))
        table.insert(wheelIcons, icon)
    end
    -- the disc and the pointer over the icons
    holder.disc:raise()
    holder.pointer:raise()
    setWheel(wheelRot)
end

-- the winning slice's icon stays lit, the others dim
local function lightSlice(key)
    for _, icon in ipairs(wheelIcons) do
        icon:setOpacity((key == nil or icon.key == key) and 1 or 0.3)
    end
    for _, wedge in ipairs(wheelWedges) do
        wedge:setOpacity((key == nil or wedge.key == key) and 1 or 0.35)
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

-- the roll's stages under the wheel: the one running is lit
local STEPS = { count = 1, type = 2, value = 3 }
local function setSteps(box, stage, entry)
    local at = STEPS[stage] or 0
    local steps = box.steps
    steps.s1:setText('1  ' .. tr('How many'))
    steps.s2:setText('2  ' .. tr('Which bonus'))
    steps.s3:setText('3  ' .. tr('Value'))
    steps.a1:setText('>')
    steps.a2:setText('>')
    for i = 1, 3 do
        steps['s' .. i]:setColor(i == at and '#eee6d4' or '#6f6880')
    end
    local odds = {}
    for i, pct in ipairs((entry and entry.counts) or {}) do
        table.insert(odds, tr('%d: %s%%', i, number(pct)))
    end
    steps.s1:setTooltip(tr('How many bonuses the item gets') .. (#odds > 0 and ('\n' .. table.concat(odds, '\n')) or ''))
    steps.s2:setTooltip(tr('The wheel picks each bonus'))
    steps.s3:setTooltip(tr('Each value falls between the minimum and the maximum of its bonus'))
end

-- the disc at the wheel's centre: the number being drawn (nil hides it)
local function setDisc(box, big, small, color)
    local holder = box.wheelHolder
    holder.disc:setVisible(big ~= nil)
    holder.hub:setVisible(big == nil)
    if big then
        holder.disc.big:setText(big)
        holder.disc.big:setColor(color or '#eee6d4')
        holder.disc.small:setText(small or '')
    end
end

-- ---------------------------------------------------------------------------
-- Roll: the lines and the price
-- ---------------------------------------------------------------------------

local function lockable(entry)
    return entry and (tonumber(entry.lockCost) or 0) > 0 and #(entry.bonuses or {}) >= 2
end

local function fillRows(entry)
    local col = page().rollPage.bonusCol
    col.rows:destroyChildren()
    local showing = roll and roll.phase == 'show' and roll.slot == entry.slotId
    local list = showing and roll.after or (roll and roll.slot == entry.slotId and roll.before) or entry.bonuses or {}
    local lock = seals[entry.slotId]
    local canLock = lockable(entry) and not busy()
    -- one line per slot of the item's grade; while the count is drawn
    -- every slot waits, so the lines don't give the number away
    local max = math.max(1, #list, tonumber(entry.maxBonuses) or 0)
    local counting = showing and roll.stage == 'count' and roll.t < 1
    local lockTip = lockable(entry) and tr('Keep this bonus on the next roll: %s gold', formatGold(entry.lockCost))
        or tr('Keeping a bonus needs an item with 2 or more bonuses')
    for i = 1, max do
        local bonus = list[i]
        local row = g_ui.createWidget('ForgeRow', col.rows)
        if not bonus and not counting then
            -- an empty slot: a roll may fill it
            row.seal:setVisible(false)
            row.text:setText(tr('Empty'))
            row.text:setColor('#5f5870')
            row:setBackgroundColor('#00000000')
            row.delta:setText('')
            row.quality:setText('')
        else
            bonus = bonus or { pad = true }
            -- the bonus kept: the one ticked, or through a roll the one
            -- that roll was sent with
            local kept = lock
            if roll and roll.slot == entry.slotId then
                kept = roll.lock
            end
            local isSealed = kept ~= nil and bonus.key == kept
            local pos, done, now, wait = nil, false, false, bonus.pad == true or counting
            if roll and roll.slot == entry.slotId and not wait then
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
            local q = qualityOf(bonus)
            local look = quality(q, bonus.perfect)
            if now then
                local typeKnown = roll.stage == 'value' or roll.t >= 1
                row.text:setText(typeKnown and tr('%s: drawing the value...', tr(bonus.label or '')) or tr('Bonus %d: spinning the wheel...', i))
                row.text:setColor('#e2c46a')
                row:setBackgroundColor('#c9a24a26')
                row:setBorderColor('#8a6f33')
            elseif wait then
                row.text:setText(tr('Bonus %d: waiting', i))
                row.text:setColor('#6f6880')
            else
                row.text:setText(bonusText(bonus))
                row.text:setColor(look[3])
                if isSealed then
                    row:setBackgroundColor('#c9a24a26')
                    row:setBorderColor('#8a6f33')
                elseif roll and pos == roll.k and done then
                    row:setBackgroundColor('#ffffff18')
                end
            end
            local hidden = now or wait
            row.seal:setVisible(not hidden or isSealed)
            row.seal:setChecked(isSealed)
            row.seal:setEnabled(canLock)
            row.seal:setTooltip(lockTip)
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
            -- where the value fell in its range, in a word; a bonus kept
            -- through a roll says so instead
            if isSealed and roll then
                row.quality:setText(tr('kept'))
                row.quality:setColor('#e2c46a')
            elseif hidden or q == nil then
                row.quality:setText('')
            else
                row.quality:setText(tr(look[2]))
                row.quality:setColor(look[3])
            end
            local d = (not roll and deltaSlot == entry.slotId) and deltas[i] or nil
            if d == 'new' then
                row.delta:setText(tr('new'))
                row.delta:setColor('#c9a4ff')
            elseif d then
                row.delta:setText(math.abs(d) < 0.05 and '=' or ((d > 0 and '+' or '-') .. number(math.abs(math.floor(d * 10 + 0.5) / 10))))
                row.delta:setColor(d > 0.05 and '#7fd36a' or d < -0.05 and '#ff7a6a' or '#898293')
            else
                row.delta:setText('')
            end
            if not hidden then
                -- what the bonus does, its range and the jackpot
                -- (RarityConfig.jackpot), under the mouse
                local jackpot = tonumber(bonus.jackpot)
                local odds = tonumber(entry.jackpotOdds) or 0
                local rangeTip = ''
                if bonus.min ~= nil and q ~= nil then
                    rangeTip = number(bonus.min) .. (bonus.unit or '') .. ' - ' .. number(bonus.max) .. (bonus.unit or '') .. '  (' .. tr(look[2]) .. ')'
                    if jackpot and odds > 0 then
                        rangeTip = rangeTip .. '\n' .. tr('Jackpot: about 1 roll in %d that lands this bonus puts it above the range, up to %s. Items that drop have a better chance.', odds, number(jackpot) .. (bonus.unit or ''))
                    end
                end
                local tip = describe(bonus.key)
                if rangeTip ~= '' then
                    tip = (tip and tip ~= '') and (tip .. '\n\n' .. Forge.wrapTip(rangeTip)) or Forge.wrapTip(rangeTip)
                end
                row:setTooltip(tip)
                -- a click anywhere on the line keeps or frees the bonus
                row.onClick = function()
                    if row.seal:isEnabled() then
                        row.seal:setChecked(not row.seal:isChecked())
                    end
                end
            end
        end
    end
    col.rows:setHeight(max * 30 - 2)
    col.slotsCount:setText((counting and '?' or #list) .. ' / ' .. max)
end

local function fillWheelBox(entry)
    local box = page().rollPage.wheelBox
    local pool = (roll and roll.slot == entry.slotId and roll.pool) or entry.pool or {}
    if wheelSlices ~= #pool or box.poolSlot ~= entry.slotId or box.poolSize ~= #pool then
        buildWheel(pool)
        box.poolSlot, box.poolSize = entry.slotId, #pool
    end
    local showing = roll and roll.phase == 'show' and roll.slot == entry.slotId
    if not roll then
        -- the wheel shows them: each slice has its name under the mouse
        local names = {}
        for _, p in ipairs(pool) do
            table.insert(names, tr(p.label or ''))
        end
        box.caption:setText(tr('%d bonuses can come out', #pool))
        box.caption:setColor('#d1ccd9')
        box.caption:setTooltip(Forge.wrapTip(table.concat(names, ', ')))
        setDisc(box, nil)
        setSteps(box, nil, entry)
        lightSlice(nil)
        return
    end
    box.caption:setTooltip(nil)
    if not showing then
        box.caption:setText(tr('Rolling...'))
        box.caption:setColor('#e2c46a')
        setDisc(box, nil)
        setSteps(box, nil, entry)
        return
    end
    setSteps(box, roll.stage, entry)
    local spinning = roll.t < 1
    if roll.stage == 'count' then
        local max = math.max(1, tonumber(roll.max) or #roll.after)
        local shown = spinning and (math.floor((g_clock.millis() - roll.startedAt) / 90) % max + 1) or #roll.after
        box.caption:setText(spinning and tr('How many bonuses?') or tr('%d of %d bonuses came out!', #roll.after, max))
        box.caption:setColor(spinning and '#e2c46a' or '#ffd75f')
        setDisc(box, tostring(shown), tr('of %d bonuses', max), spinning and '#eee6d4' or '#ffd75f')
        lightSlice(nil)
        return
    end
    local cur = roll.after[roll.order[roll.k]]
    local which = tr('bonus %d of %d', roll.k, #roll.order)
    if roll.stage == 'type' then
        box.caption:setText(spinning and tr('Bonus %d: spinning the wheel...', roll.order[roll.k]) or tr('Type: %s!', tr(cur.label or '')))
        box.caption:setColor('#e2c46a')
        setDisc(box, '?', which)
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
    -- the number alone: the title font's "+" is so thin that the digits
    -- looked pushed to the right of the disc's centre
    setDisc(box, number(shown) .. (cur.unit or ''), tr(look[2]), look[3])
    if spinning then
        box.caption:setText(tr('%s: how much?', tr(cur.label or '')))
        box.caption:setColor('#e2c46a')
    else
        box.caption:setText(tr('Rolled: %s (%s)!', bonusText(cur), tr(look[2])))
        box.caption:setColor(look[3])
    end
end

local function fillRoll(entry)
    local col = page().rollPage.bonusCol
    fillRows(entry)
    fillWheelBox(entry)
    local sealed = sameKey(entry.bonuses, seals[entry.slotId])
    local bar = col.costBar
    local cost = tonumber(entry.rerollCost) or 0
    local lockGold = sealed and (tonumber(entry.lockCost) or 0) or 0
    local short = rarityXp < cost
    -- the wallet follows the roll's price as soon as it is paid
    window.bottomBar.xpLabel:setText(tr('Rarity XP: %d', rarityXp))
    bar.costXp:setText(tr('%d Rarity XP', cost))
    bar.costXp:setColor(short and '#ff7a6a' or '#c9a4ff')
    bar.haveXp:setText(tr('you have %d', rarityXp))
    bar.haveXp:setColor(short and '#ff7a6a' or '#898293')
    local width = bar.xpBar:getWidth()
    bar.xpBar.fill:setWidth(math.floor((width > 0 and width or 300) * math.min(1, cost > 0 and rarityXp / cost or 1)))
    -- the gold only when a bonus is kept
    bar.costGoldIcon:setVisible(lockGold > 0)
    bar.costGold:setVisible(lockGold > 0)
    bar.costGold:setText(tr('%s gold (keep)', formatGold(lockGold)))
    bar.costGold:setColor(gold >= lockGold and '#e2c46a' or '#ff7a6a')
    col.skipButton:setVisible(roll ~= nil and roll.phase == 'show')
    col.rollButton:setVisible(not (roll and roll.phase == 'show'))
    if roll then
        col.rollButton:setText(tr('Rolling...'))
        col.rollButton:setEnabled(false)
    elseif short then
        col.rollButton:setText(tr('Missing %d XP', cost - rarityXp))
        col.rollButton:setEnabled(false)
    elseif gold < lockGold then
        col.rollButton:setText(tr('Not enough gold to keep'))
        col.rollButton:setEnabled(false)
    else
        col.rollButton:setText((deltaSlot == entry.slotId and next(deltas)) and tr('Roll again') or tr('Roll'))
        col.rollButton:setEnabled(cost > 0)
    end
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
        up.maxText:setText(tr('Highest grade: %s', grade(entry.rarity).label))
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
    -- what success and failure do is in the confirmation of the upgrade
    up.explain:setVisible(false)
    if forging then
        local width = up.forgeBar:getWidth() - 2
        up.forgeBar.fill:setWidth(math.max(0, math.floor(width * asc.pct / 100)))
        up.forgePct:setText(tr('Forging... %d%%', asc.pct))
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
    local totals = (data and data.totals) or {}
    -- two columns, read down each: the grid fills across, so the second
    -- half of the list goes on the right
    local rows = math.ceil(#totals / 2)
    tp.listScroll:setVisible(rows * 22 > tp.list:getHeight())
    tp.none:setVisible(#totals == 0)
    for cell = 0, rows * 2 - 1 do
        local t = totals[(cell % 2) * rows + math.floor(cell / 2) + 1]
        if not t then
            g_ui.createWidget('UIWidget', tp.list)
        else
            local row = g_ui.createWidget('ForgeTotalRow', tp.list)
            local unit = t.unit or ''
            -- the server can have the total caps off (RarityConfig.capTotals):
            -- then no bonus brings one
            local cap = not t.perItem and tonumber(t.cap) or nil
            if cap and cap <= 0 then
                cap = nil
            end
            local sum = tonumber(t.total) or 0
            local full = cap and (t.capped or sum >= cap)
            row.name:setText(tr(t.label or ''))
            row.name:setColor(full and '#e2c46a' or '#d1ccd9')
            row.total:setText(plus(sum, unit) .. (cap and (' / ' .. number(cap) .. unit) or ''))
            row.total:setColor(full and '#e2c46a' or '#eee6d4')
            -- the items that give it, under the mouse
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
    -- no Upgrade tab for an item at the highest grade
    local canUpgrade = entry == nil or entry.upgrade ~= nil or (asc ~= nil and asc.slot == entry.slotId)
    window.tabs.tabUp:setVisible(canUpgrade)
    if not canUpgrade and tab == 'up' then
        tab = 'roll'
        window.tabs.tabRoll:setOn(true)
        window.tabs.tabUp:setOn(false)
    end
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
-- Rarity XP comes once per kill: an area spell brings many in one frame, so
-- the open window is redone once, on the next frame
local xpRefresh
function Forge.onXp(xp)
    rarityXp = tonumber(xp) or rarityXp
    if window and window:isVisible() and not xpRefresh then
        xpRefresh = scheduleEvent(function()
            xpRefresh = nil
            if window and window:isVisible() and not busy() then
                Forge.refresh()
            end
        end, 1)
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
    if xpRefresh then
        removeEvent(xpRefresh)
        xpRefresh = nil
    end
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
    wheelIcons, wheelWedges, wheelSlices = {}, {}, 0
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
