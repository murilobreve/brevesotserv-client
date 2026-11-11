-- Forja de Raridade: the rarity window (forge.otui), one page: the rarity
-- items worn on a paperdoll and, under it, the character's bonuses (each
-- total with the items that give it); the item picked with its bonuses as
-- cards (a click seals one for the next reforge); below, side by side, the
-- Reforge (the cards turn face down and are revealed one by one, each with
-- how it changed) and the Ascension (a dial whose lit arc is the chance; the
-- needle spins and stops in or out of it).
-- The server (scripts/rarity/bonus_window.lua, extended opcode 123) rolls;
-- the window only shows. raritybonus.lua routes the opcode here.

Forge = {}

local OPCODE = 123
local ANSWER_TIMEOUT = 8000

local GRADES = {
    uncommon  = { label = 'Communis',    color = '#63c08a', pips = 1 },
    rare      = { label = 'Rarus',       color = '#4f8fe8', pips = 2 },
    epic      = { label = 'Praeclarus',  color = '#af78ea', pips = 3 },
    legendary = { label = 'Legendarius', color = '#e2a443', pips = 4 },
    mythic    = { label = 'Mythicus',    color = '#e8e4ff', pips = 5 },
}
local GRADE_ORDER = { 'mythic', 'legendary', 'epic', 'rare', 'uncommon' }

-- a picture for each bonus (images/forge/bonus, cut from the client's
-- imbuement icons): the element ones by their element, the rest by kind
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

local function bonusIcon(widget, key)
    -- a bonus with no picture of its own (a vocation's spell) takes the wand
    local name = BONUS_ICONS[key or ''] or (key and key ~= '' and 'wand' or nil)
    widget:setVisible(name ~= nil)
    if name then
        widget:setImageSource('/game_raritybonus/images/forge/bonus/' .. name)
    end
end

-- where a roll fell in its range: name, colour, tag background
local QUALITY = {
    { 0.999, 'Perfect', '#f3d38a', '#3a2c12' },
    { 0.85, 'Excellent', '#8cc4ff', '#14243a' },
    { 0.6, 'Good', '#8fdc9a', '#15291a' },
    { 0.3, 'Fair', '#d6cfc2', '#252129' },
    { 0, 'Weak', '#b0a69a', '#211d24' },
}

-- the paperdoll, as the inventory: neck, head, backpack / left hand, armor,
-- right hand / ring, legs, ammo / -, feet, -
local DOLL = { 2, 1, 3, 6, 4, 5, 9, 7, 10, 0, 8, 0 }

local BAR = 120 -- the Arsenal's range bar

local window
local data -- the last summary from the server
local items, bySlot = {}, {}
local totalsByKey = {}
local selected -- slot id of the item shown
local locks = {} -- slot id -> bonus key sealed on the next reforge
local rarityXp, gold = 0, 0
local bonusDescs = {}
local confirmBox
local answerEvent
local pendingData -- a refresh that came in while an animation runs

local reforge -- { phase = 'rolling'|'reveal'|'done', slot, before, rolled, shown, ... }
local ascend -- { phase = 'waiting'|'spinning'|'win'|'lose', slot, ... }
local needleAngle = 0
local history = {} -- this session's Ascension tries: true = went up
local animEvent
local reelEvent -- the Reforge's reels (the cards' backs) while it rolls
-- the Reforge's pace: how long the reels run before the first card stops,
-- the time between two cards, how often a reel shows another bonus
local REEL_FIRST, REEL_STEP, REEL_TICK = 4200, 1950, 210
-- the last card turns this much later when a good bonus came out already
local REEL_SUSPENSE = 1500


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
-- ("dragon scale mail legendarius sacer" -> "Dragon Scale Mail"): the window
-- shows the grade apart
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
    local entry = bonusDescs[key or '']
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
    for _, entry in ipairs(QUALITY) do
        if (q or 0) >= entry[1] and entry ~= QUALITY[1] then
            return entry
        end
    end
    return QUALITY[#QUALITY]
end

local function grade(key)
    return GRADES[key] or GRADES.uncommon
end

local function setItem(widget, entry, shader)
    local item = Item.create(entry.itemId or 0, 1)
    local look = shader or entry.shader
    if look and look ~= '' then
        item:setShader(look)
    end
    widget:setItem(item)
end

local function setStatus(text, color)
    if window then
        window.status:setText(text or '')
        window.status:setColor(color or '#7fd35a')
    end
end

local function stopAnim()
    if animEvent then
        removeEvent(animEvent)
        animEvent = nil
    end
end

-- ---------------------------------------------------------------------------
-- Arsenal
-- ---------------------------------------------------------------------------

local function pickItem(slot)
    if reforge and (reforge.phase == 'rolling' or reforge.phase == 'reveal') then
        return
    end
    if ascend and (ascend.phase == 'waiting' or ascend.phase == 'spinning') then
        return
    end
    -- a confirm still open is about the item it names: another item picked
    -- closes it (its "Yes" would have spent on the new one)
    if confirmBox and slot ~= selected then
        confirmBox:destroy()
        confirmBox = nil
    end
    -- what the status line says is about the item that was shown
    if slot ~= selected then
        setStatus('')
    end
    selected = slot
    reforge, ascend = nil, nil
    Forge.refresh()
end

local function fillPips(panel, gradeKey)
    panel:destroyChildren()
    local g = grade(gradeKey)
    for n = 1, 5 do
        local pip = g_ui.createWidget('ForgePip', panel)
        if n <= g.pips then
            pip:setImageColor(g.color)
        else
            pip:setImageSource('/game_raritybonus/images/forge/pip_empty')
            pip:setImageColor('#4a4250')
        end
    end
end

local fillReforge, fillAscend -- below: they fill the two boxes under the cards

-- the character's bonuses, under the paperdoll: each total (and its limit)
-- and the items that give it, a click on an item picks it
local MINI_BAR = 262

local function fillMyBonuses()
    local p = window.pages.arsenal.left
    local list = p.bonusList
    list:destroyChildren()
    local totals = (data and data.totals) or {}
    local atLimit = 0
    for _, t in ipairs(totals) do
        local row = g_ui.createWidget('ForgeMiniTotal', list)
        -- a long name gives way to the total on its right
        local label = tr(t.label or '')
        if #label > 20 then
            label = label:sub(1, 18):gsub('%s+$', '') .. '..'
            row.name:setTooltip(tr(t.label or ''))
        end
        row.name:setText(label)
        bonusIcon(row.icon, t.key)
        local unit = t.unit or ''
        local cap = not t.perItem and tonumber(t.cap)
        if cap and cap <= 0 then
            cap = nil
        end
        local sum = tonumber(t.total) or 0
        local full = cap and (t.capped or sum >= cap)
        if full then
            atLimit = atLimit + 1
        end
        row.total:setText(cap and (plus(sum, unit) .. ' / ' .. number(cap) .. unit) or plus(sum, unit))
        row.total:setColor(full and '#f3d38a' or '#b9b0a3')
        row.track.fill:setWidth(cap and math.max(1, math.floor(MINI_BAR * math.min(1, sum / cap) + 0.5)) or 0)
        row.track.fill:setBackgroundColor(full and '#e8c77a' or '#8a7fa0')
        local tip = describe(t.key)
        if cap then
            local line = full and tr('At the limit: more of it adds nothing.') or tr('Limit: %s', number(cap) .. unit)
            tip = tip and (tip .. '\n\n' .. line) or line
        else
            tip = tip and (tip .. '\n\n' .. tr('(on each item)')) or tr('(on each item)')
        end
        row:setTooltip(tip)
        for _, src in ipairs(t.sources or {}) do
            local slot = tonumber(src.item) or 0
            local it = items[slot] and items[slot] or nil
            local chip = g_ui.createWidget('ForgeMiniChip', row.chips)
            if it then
                setItem(chip.item, it)
                chip:setBackgroundColor(it.slotId == selected and '#3a3140' or '#1f1a24')
                chip.onClick = function() pickItem(it.slotId) end
            end
            chip.value:setText(plus(src.value, unit))
            chip:setWidth(22 + chip.value:getTextSize().width + 4)
            chip:setTooltip(titleCase(src.name or (it and it.name) or ''))
        end
    end
    p.bonusesNote:setText(#totals == 0 and '' or atLimit > 0 and tr('%d at the limit', atLimit) or tr('%d bonuses', #totals))
    p.bonusesNote:setColor(atLimit > 0 and '#e8c77a' or '#8f877c')
end

local function fillArsenal()
    local p = window.pages.arsenal
    local doll = p.left.doll
    doll:destroyChildren()
    for _, slot in ipairs(DOLL) do
        local entry = slot > 0 and bySlot[slot]
        if entry then
            local g = grade(entry.rarity)
            local w = g_ui.createWidget('ForgeSlot', doll)
            setItem(w.item, entry)
            w.pip:setImageColor(g.color)
            if slot == selected then
                w:setBackgroundColor('#2a2430')
            end
            w:setTooltip(titleCase(entry.name) .. '\n' .. g.label)
            w.onClick = function() pickItem(slot) end
        end
    end
    local worn = doll:getChildCount()
    doll:setHeight(math.max(1, math.ceil(worn / 5)) * 54 - 6)
    p.left.wornNote:setText(worn == 1 and tr('1 item') or tr('%d items', worn))
    fillMyBonuses()

    local c = p.center
    local entry = bySlot[selected]
    for _, id in ipairs({ 'pedestal', 'badge', 'pips', 'name', 'info', 'cards', 'reforgeBox', 'ascendBox' }) do
        c[id]:setVisible(entry ~= nil)
    end
    c.empty:setVisible(entry == nil)
    if not entry then
        return
    end
    local g = grade(entry.rarity)
    c.pedestal.glow:setImageColor(g.color)
    setItem(c.pedestal.item, entry)
    c.badge:setText(g.label:upper())
    c.badge:setColor(g.color)
    fillPips(c.pips, entry.rarity)
    c.name:setText(titleCase(entry.name))
    local info = { tr(entry.slot or '') }
    if (tonumber(entry.level) or 0) > 0 then
        table.insert(info, tr('Level %d', entry.level))
    end
    local max = math.max(1, tonumber(entry.maxBonuses) or #(entry.bonuses or {}))
    table.insert(info, max == 1 and tr('1 bonus') or tr('1 to %d bonuses', max))
    -- the finder's +20%: on every value shown here, kept by any reforge
    if entry.finder then
        table.insert(info, tr('Found by you: +20%'))
    end
    c.info:setText(table.concat(info, '   '))
    fillReforge()
    fillAscend()
end

-- ---------------------------------------------------------------------------
-- Reforge
-- ---------------------------------------------------------------------------


-- seals a bonus of the item, or takes the seal off when it is the sealed one
local function toggleSeal(entry, bonus)
    locks[selected] = (locks[selected] == bonus.key) and nil or bonus.key
    if locks[selected] then
        setStatus(tr('%s sealed: the next reforge keeps it with this value and rolls the others, for %s gold more.', bonusText(bonus), formatGold(entry.lockCost)), '#e8c77a')
    else
        setStatus(tr('%s is no longer sealed.', bonusText(bonus)), '#ab9fc6')
    end
end

local function lockable(entry)
    return entry and (tonumber(entry.lockCost) or 0) > 0 and #(entry.bonuses or {}) >= 2
end

-- the range bar of a card: filled to `q` (0-1) in `color`, the marker on it
local METER_W = 98
local function setMeter(card, q, color)
    local x = math.floor(math.max(0, math.min(1, q or 0)) * (METER_W - 2) + 0.5)
    card.meter.fill:setWidth(x)
    card.meter.fill:setBackgroundColor(color)
    card.meter.mark:setMarginLeft(x)
end

local function fillCard(card, bonus, opts)
    card.delta:setVisible(false)
    card.back:setVisible(false)
    card.empty:setVisible(false)
    card.flash:setVisible(false)
    card.glow:setVisible(false)
    for _, id in ipairs({ 'number', 'track', 'grade', 'name', 'value', 'meter', 'rmin', 'rmax' }) do
        card[id]:setVisible(true)
    end
    card.number:setText(opts.locked and tr('SEALED') or tr('BONUS %d', opts.n))
    card.number:setColor(opts.locked and '#e8c77a' or '#8f877c')
    bonusIcon(card.icon, bonus.key)
    card.sealed:setVisible(false)
    local q = qualityOf(bonus)
    local look = quality(q, bonus.perfect)
    local frame = math.floor((q or 0) * 20 + 0.5)
    card.track.arc:setImageClip(string.format('%d 0 76 76', frame * 76))
    card.track.arc:setImageColor(look[3])
    card.track.arc:setVisible(q ~= nil)
    card.track.percent:setText(q and (math.floor(q * 100 + 0.5) .. '%') or '?')
    card.track.percent:setColor(look[3])
    card.grade:setText(q and tr(look[2]):upper() or '')
    card.name:setText(tr(bonus.label or ''))
    card.value:setText(plus(bonus.value, bonus.unit))
    card.value:setColor(q and look[3] or '#ece6dc')
    local ranged = q ~= nil and bonus.min ~= nil and bonus.max ~= nil
    card.meter:setVisible(ranged)
    card.rmin:setVisible(ranged)
    card.rmax:setVisible(ranged)
    card.accent:setVisible(q ~= nil or opts.locked or false)
    card.accent:setBackgroundColor(opts.locked and '#e8c77a' or look[3])
    card.accent:setHeight(opts.locked and 3 or 2)
    if ranged then
        setMeter(card, q, look[3])
        card.rmin:setText(plus(bonus.min, bonus.unit))
        card.rmax:setText(plus(bonus.max, bonus.unit))
    end
    if bonus.perfect then
        card.glow:setVisible(true)
        card.glow:setImageColor('#f3d38a')
        card.glow:setOpacity(0.6)
        card.grade:setColor('#f3d38a')
    elseif q and q >= 0.85 then
        -- an Excellent roll keeps a cold glow
        card.glow:setVisible(true)
        card.glow:setImageColor('#8cc4ff')
        card.glow:setOpacity(0.45)
        card.grade:setColor('#8cc4ff')
    end
    -- the card's tooltip: what the bonus does and how much the character has
    local tip = describe(bonus.key)
    local total = totalsByKey[bonus.key]
    local cap = total and not total.perItem and tonumber(total.cap)
    if cap and cap > 0 then
        local line = tr('In your character: %s of %s', number(tonumber(total.total) or 0) .. (bonus.unit or ''), number(cap) .. (bonus.unit or ''))
        tip = tip and (tip .. '\n\n' .. line) or line
    end
    card:setTooltip(tip)
end

-- what a reforge can give the item being reforged (the server's pool)
local function poolNow()
    local entry = reforge and bySlot[reforge.slot]
    return (entry and entry.pool) or {}
end

-- a card's back shows one bonus of the pool: icon, name, its range; never
-- the same one twice in a row
local function spinReel(card)
    local pool = poolNow()
    local back = card.back
    local on = #pool > 0
    back.band:setVisible(on)
    back.rune:setVisible(not on)
    back.reelIcon:setVisible(on)
    if not on then
        for _, id in ipairs({ 'reelPrev', 'reelName', 'reelRange', 'reelNextRow' }) do
            back[id]:setText('')
        end
        return
    end
    -- a column that rolls down: the next row moves into the band, the band's
    -- row moves up, a new one comes in from below
    local function pick(avoid1, avoid2)
        local i = math.random(#pool)
        for _ = 1, 4 do
            if #pool <= 2 or (i ~= avoid1 and i ~= avoid2) then
                break
            end
            i = i % #pool + 1
        end
        return i
    end
    if not card.reelCur then
        card.reelCur = pick()
        card.reelNextIdx = pick(card.reelCur)
    end
    card.reelPrevIdx = card.reelCur
    card.reelCur = card.reelNextIdx
    card.reelNextIdx = pick(card.reelCur, card.reelPrevIdx)
    local prev, cur, nxt = pool[card.reelPrevIdx], pool[card.reelCur], pool[card.reelNextIdx]
    back.reelPrev:setText(tr(prev.label or ''))
    bonusIcon(back.reelIcon, cur.key)
    back.reelName:setText(tr(cur.label or ''))
    back.reelRange:setColoredText(string.format('{%s, #8f877c}  {%s, #6e665e}  {%s, #f3d38a}', plus(cur.min, cur.unit), tr('to'), plus(cur.max, cur.unit)))
    back.reelNextRow:setText(tr(nxt.label or ''))
end

local function backCard(card, n)
    if reforge and (reforge.phase == 'rolling' or reforge.phase == 'reveal') then
        spinReel(card)
    else
        card.back.band:setVisible(false)
        card.back.rune:setVisible(true)
        card.back.reelIcon:setVisible(false)
        for _, id in ipairs({ 'reelPrev', 'reelName', 'reelRange', 'reelNextRow' }) do
            card.back[id]:setText('')
        end
    end
    card.delta:setVisible(false)
    card.icon:setVisible(false)
    card.back:setVisible(true)
    card.empty:setVisible(false)
    card.sealed:setVisible(false)
    card.glow:setVisible(false)
    card:setTooltip(nil)
end

local function emptyCard(card)
    card.delta:setVisible(false)
    card.icon:setVisible(false)
    card.back:setVisible(false)
    card.flash:setVisible(false)
    card.glow:setVisible(false)
    card.sealed:setVisible(false)
    for _, id in ipairs({ 'number', 'track', 'grade', 'name', 'value', 'meter', 'rmin', 'rmax' }) do
        card[id]:setVisible(false)
    end
    card.empty:setVisible(true)
    card.emptyRune:setVisible(true)
    card:setBackgroundColor('#13101666')
    card:setTooltip(nil)
end

-- a card that just turned: its value climbs from the bottom of its range
-- to what was rolled, the ring filling and the grade name changing on the
-- way, so it shows how far it could have gone (it stops on the real roll)
local COUNT_MS, COUNT_STEPS = 1100, 26
local function countUp(card, bonus)
    local q = qualityOf(bonus)
    local value, min = tonumber(bonus.value), tonumber(bonus.min)
    if not q or not value or not min or value <= min then
        return
    end
    local whole = math.floor(value) == value
    local step = 0
    local function frame()
        if card:isDestroyed() or not card.value then
            return
        end
        step = step + 1
        local t = step / COUNT_STEPS
        -- quick at first, crawling at the end
        local e = 1 - (1 - t) ^ 3
        if step >= COUNT_STEPS then
            e = 1
        end
        local v = min + (value - min) * e
        v = whole and math.floor(v + 0.5) or math.floor(v * 10 + 0.5) / 10
        local qe = q * e
        local perfect = bonus.perfect and e >= 1
        local look = quality(qe, perfect)
        card.value:setText(plus(v, bonus.unit))
        card.value:setColor(look[3])
        card.track.arc:setImageClip(string.format('%d 0 76 76', math.floor(qe * 20 + 0.5) * 76))
        card.track.arc:setImageColor(look[3])
        card.track.percent:setText(math.floor(qe * 100 + 0.5) .. '%')
        card.track.percent:setColor(look[3])
        card.grade:setText(tr(look[2]):upper())
        card.grade:setColor(look[3])
        card.accent:setBackgroundColor(look[3])
        if card.meter:isVisible() then
            setMeter(card, qe, look[3])
        end
        if step < COUNT_STEPS then
            scheduleEvent(frame, math.floor(COUNT_MS / COUNT_STEPS))
        else
            card.grade:setColor(qe >= 0.85 and look[3] or '#a59d92')
        end
    end
    frame()
end

-- a card that just turned: a flash of its quality colour that fades out
local function flashCard(card, color)
    card.flash:setVisible(true)
    card.flash:setBackgroundColor(color)
    local step = 0
    local function fade()
        if card:isDestroyed() then
            return
        end
        step = step + 1
        card.flash:setOpacity(math.max(0, 0.75 - step * 0.075))
        if step < 10 then
            scheduleEvent(fade, 35)
        else
            card.flash:setVisible(false)
        end
    end
    card.flash:setOpacity(0.75)
    scheduleEvent(fade, 35)
end

local function sameKey(list, key, label)
    for _, bonus in ipairs(list or {}) do
        if (key and bonus.key == key) or (not key and label and bonus.label == label) then
            return bonus
        end
    end
end

-- the rolled lines of a reroll answer as bonuses (label, value, unit...)
local function rolledBonuses(result)
    local list = {}
    for _, line in ipairs(result.rolled or {}) do
        local value = tonumber((line.text or ''):match('^%+(%-?[%d%.]+)')) or 0
        list[#list + 1] = {
            key = line.key, label = line.label, unit = line.unit, value = value,
            quality = line.quality, perfect = line.perfect, min = line.min, max = line.max,
            locked = line.locked,
        }
    end
    return list
end

-- after a reforge, how a bonus changed: text and colour for the card's corner
local function deltaOf(bonus)
    if not (reforge and reforge.phase ~= 'rolling') then
        return nil
    end
    if bonus.locked or (reforge.lock and bonus.key == reforge.lock) then
        return nil
    end
    local old = sameKey(reforge.before, bonus.key, bonus.label)
    if not old then
        return tr('new'), '#c9a4ff'
    end
    local d = (tonumber(bonus.value) or 0) - (tonumber(old.value) or 0)
    if math.abs(d) < 0.05 then
        return '=', '#a59d92'
    end
    return (d > 0 and '+' or '-') .. number(math.abs(math.floor(d * 10 + 0.5) / 10)), d > 0 and '#8fdc9a' or '#ff9c8a'
end

fillReforge = function()
    local c = window.pages.arsenal.center
    local entry = bySlot[selected]
    local cards = c.cards
    cards:destroyChildren()
    if not entry then
        return
    end
    local g = grade(entry.rarity)
    local max = math.max(1, tonumber(entry.maxBonuses) or #(entry.bonuses or {}))
    -- the cards share the row's width (five fill it), from the left
    local avail = c:getWidth()
    if avail < 300 then
        avail = 636
    end
    local cardWidth = math.min(150, math.floor((avail - (max - 1) * 10) / max))

    local phase = reforge and reforge.slot == selected and reforge.phase or 'idle'
    local lock = locks[selected]
    for n = 1, max do
        local card = g_ui.createWidget('ForgeCard', cards)
        card:setWidth(cardWidth)
        if phase == 'idle' then
            local bonus = (entry.bonuses or {})[n]
            if bonus then
                fillCard(card, bonus, { n = n, locked = lock == bonus.key })
                if lockable(entry) then
                    card.onClick = function()
                        toggleSeal(entry, bonus)
                        fillReforge()
                    end
                end
            else
                emptyCard(card)
            end
        elseif phase == 'rolling' then
            local bonus = (reforge.before or {})[n]
            if bonus and reforge.lock == bonus.key then
                fillCard(card, bonus, { n = n, locked = true })
            else
                backCard(card, n)
            end
        else
            local list = reforge.after or {}
            local bonus = list[n]
            if bonus and (n <= reforge.shown or bonus.locked) then
                fillCard(card, bonus, { n = n, locked = bonus.locked })
                local text, color = deltaOf(bonus)
                card.delta:setVisible(text ~= nil)
                if text then
                    card.delta:setText(text)
                    card.delta:setColor(color)
                    -- the corner note takes the header's place (they touched)
                    card.number:setText('')
                end
                if n == reforge.flashAt then
                    flashCard(card, bonus.perfect and '#f3d38a' or quality(qualityOf(bonus), bonus.perfect)[3])
                    countUp(card, bonus)
                end
            elseif not bonus and reforge.shown >= #list then
                emptyCard(card)
            else
                backCard(card, n)
            end
            if phase == 'done' then
                -- back to the item as it is now, and the card clicked is
                -- sealed (or unsealed) at once: no second click
                card.onClick = function()
                    reforge = nil
                    local now = bySlot[selected]
                    if bonus and now and lockable(now) and sameKey(now.bonuses, bonus.key, bonus.label) then
                        toggleSeal(now, sameKey(now.bonuses, bonus.key, bonus.label))
                    end
                    Forge.refresh()
                end
            end
        end
    end
    if reforge then
        reforge.flashAt = nil
    end

    -- the rules and the price
    local s = c.reforgeBox
    local perfect = tonumber(data and data.perfectChance) or 0
    local rules = tr('Which bonuses: drawn from the list of this kind of item.') .. '\n' ..
        tr('Values: within the range of %s.', g.label)
    if perfect > 0 then
        local pct = perfect * 100
        local text = pct >= 1 and string.format('%.1f%%', pct) or pct >= 0.01 and string.format('%.2f%%', pct) or string.format('%.3f%%', pct)
        rules = rules .. '\n' .. tr('Perfect roll: %s per bonus.', text)
    end
    rules = rules .. '\n' .. tr('Fewer bonuses come stronger.')
    -- the seal: what it is, its price, or why this item has none
    local seal
    if lockable(entry) then
        seal = tr('Seal: click a card before reforging; it keeps its bonus with this value and the others roll again. Price: %s gold.', formatGold(entry.lockCost))
    else
        seal = tr('Seal: needs an item with 2 or more bonuses')
    end
    s.info:setTooltip(rules .. '\n\n' .. seal)
    -- what a reforge can give: one chip per bonus of the item's pool, the
    -- ones the item has now (or that the reveal has shown) in gold
    local pool = entry.pool or {}
    local have = {}
    if phase == 'idle' then
        for _, bonus in ipairs(entry.bonuses or {}) do
            have[bonus.key or ''] = true
        end
    elseif phase == 'rolling' then
        have[reforge.lock or ''] = true
    else
        for n, bonus in ipairs(reforge.after or {}) do
            if n <= reforge.shown or bonus.locked then
                have[bonus.key or ''] = true
            end
        end
    end
    s.pool:setVisible(#pool > 0)
    s.poolGrid:setVisible(#pool > 0)
    s.poolGrid:destroyChildren()
    s.pool:setText(tr('CAN ROLL') .. '   ' .. #pool)
    for i, bonus in ipairs(pool) do
        if i > 20 then
            break
        end
        local chip = g_ui.createWidget('ForgePoolChip', s.poolGrid)
        chip:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        chip:addAnchor(AnchorTop, 'parent', AnchorTop)
        chip:setMarginLeft(((i - 1) % 10) * 27)
        chip:setMarginTop(math.floor((i - 1) / 10) * 27)
        bonusIcon(chip.icon, bonus.key)
        local tip = tr(bonus.label or '') .. '\n' .. plus(bonus.min, bonus.unit) .. '  -  ' .. plus(bonus.max, bonus.unit)
        if have[bonus.key or ''] then
            chip.mark:setVisible(true)
            tip = tip .. '\n' .. tr('On this item now')
        end
        chip:setTooltip(tip)
    end
    local cost = tonumber(entry.rerollCost) or 0
    s.costXp:setText(tr('%d Rarity XP (you have %d)', cost, rarityXp))
    s.costXp:setColor(rarityXp >= cost and '#d6cfc2' or '#ff9c8a')
    local busySeal = phase == 'rolling' or phase == 'reveal'
    s.sealClear:setVisible(lock ~= nil and not busySeal)
    s.sealClear.onClick = function()
        local sealed = sameKey(entry.bonuses, locks[selected])
        locks[selected] = nil
        if reforge and reforge.phase == 'done' then
            reforge = nil
        end
        setStatus(sealed and tr('%s is no longer sealed.', bonusText(sealed)) or '', '#ab9fc6')
        fillReforge()
    end
    if lock then
        s.costSeal:setText(tr('%s (+%s gold)', tr(((sameKey(entry.bonuses, lock) or {}).label) or ''), formatGold(entry.lockCost)))
        s.costSeal:setColor('#e8c77a')
    elseif lockable(entry) then
        s.costSeal:setText(tr('click a card to seal it'))
        s.costSeal:setColor('#8f877c')
    else
        s.costSeal:setText(tr('needs 2 or more bonuses'))
        s.costSeal:setColor('#8f877c')
    end
    local lockGold = lock and (tonumber(entry.lockCost) or 0) or 0
    local busy = phase == 'rolling' or phase == 'reveal'
    s.rollButton:setText(lock and tr('Reforge  -  %d XP + %s gold', cost, formatGold(lockGold)) or tr(phase == 'done' and 'Reforge again  -  %d XP' or 'Reforge  -  %d XP', cost))
    if busy then
        -- the Skip button sits on the right of it while the cards turn
        s.rollButton:setText(tr('Reforging...') .. '            ')
    end
    s.rollButton:setEnabled(not busy and cost > 0 and rarityXp >= cost and gold >= lockGold)
    s.skipButton:setVisible(busy)
    if cost > 0 and rarityXp < cost then
        s.rollButton:setTooltip(tr('You need %d Rarity XP and have %d. Buy more here or kill Pale, Ashen, Obsidian and Lord of Death monsters.', cost, rarityXp))
    elseif gold < lockGold then
        s.rollButton:setTooltip(tr('The seal costs %s gold and you have %s.', formatGold(lockGold), formatGold(gold)))
    else
        s.rollButton:setTooltip(nil)
    end
end

-- the card backs pulse while the server rolls
local function pulse()
    stopAnim()
    local t0 = g_clock.millis()
    local function tick()
        animEvent = nil
        if not reforge or reforge.phase ~= 'rolling' or not window then
            return
        end
        local a = (math.sin((g_clock.millis() - t0) / 1100 * math.pi * 2) + 1) / 2
        for _, card in ipairs(window.pages.arsenal.center.cards:getChildren()) do
            if card.back:isVisible() then
                card.back.rune:setOpacity(0.55 + 0.45 * a)
            end
        end
        animEvent = scheduleEvent(tick, 50)
    end
    tick()
end

-- the card that turns next in the reveal (sealed ones are face up already)
local function nextToFlip()
    local list = reforge.after or {}
    local n = reforge.shown + 1
    while list[n] and list[n].locked do
        n = n + 1
    end
    return n
end

-- the reels run while the server rolls and through the reveal; the card
-- about to turn slows down before it stops on its bonus
local function runReels()
    if reelEvent then
        removeEvent(reelEvent)
        reelEvent = nil
    end
    local function tick()
        reelEvent = nil
        if not reforge or not window or (reforge.phase ~= 'rolling' and reforge.phase ~= 'reveal') then
            return
        end
        local now = g_clock.millis()
        local slowing = reforge.phase == 'reveal' and nextToFlip() or nil
        for n, card in ipairs(window.pages.arsenal.center.cards:getChildren()) do
            if card.back:isVisible() and now >= (card.reelNext or 0) then
                spinReel(card)
                local every = REEL_TICK
                if n == slowing then
                    local elapsed = now - (reforge.lastFlip or now)
                    every = REEL_TICK + math.floor(elapsed * 0.4)
                end
                card.reelNext = now + every
            end
        end
        reelEvent = scheduleEvent(tick, 30)
    end
    tick()
end

local function tellPending()
    local pending = Forge.pendingMessage
    Forge.pendingMessage = nil
    if pending and pending[1] then
        setStatus(pending[1], pending[2])
    end
end

-- where a bonus fell: 1 weak/fair, 2 good, 3 excellent, 4 perfect
local function tierOf(bonus)
    local q = qualityOf(bonus) or 0
    if bonus.perfect or q >= 0.999 then
        return 4
    elseif q >= 0.85 then
        return 3
    elseif q >= 0.6 then
        return 2
    end
    return 1
end

-- a short jolt of the cards on a perfect roll
local function jolt(widget)
    local offsets = { -6, 5, -4, 3, -2, 0 }
    local i = 0
    widget.restMargin = widget.restMargin or widget:getMarginTop()
    local base = widget.restMargin
    local function step()
        if widget:isDestroyed() then
            return
        end
        i = i + 1
        widget:setMarginTop(base + (offsets[i] or 0))
        if i < #offsets then
            scheduleEvent(step, 45)
        end
    end
    step()
end

-- a card has just stopped: a jolt for a perfect one
local function landed(bonus)
    if not bonus then
        return
    end
    local tier = tierOf(bonus)
    if tier == 4 and window then
        jolt(window.pages.arsenal.center.cards)
    end
    if tier >= 2 then
        reforge.hot = true
    end
end

local function finishReforge()
    stopAnim()
    if not reforge then
        return
    end
    tellPending()
    reforge.phase = 'done'
    reforge.shown = #(reforge.after or {})
    local pending = pendingData
    pendingData = nil
    if pending then
        Forge.apply(pending)
    else
        Forge.refresh()
    end
end

local function revealNext()
    animEvent = nil
    if not reforge or reforge.phase ~= 'reveal' then
        return
    end
    local list = reforge.after or {}
    -- the sealed ones are face up already
    repeat
        reforge.shown = reforge.shown + 1
    until reforge.shown > #list or not list[reforge.shown].locked
    landed(list[reforge.shown])
    if reforge.shown >= #list then
        reforge.flashAt = math.min(reforge.shown, #list)
        fillReforge()
        animEvent = scheduleEvent(finishReforge, 1300)
        return
    end
    reforge.flashAt = reforge.shown
    reforge.lastFlip = g_clock.millis()
    -- the last card to turn waits longer when something good came out
    local after = reforge.shown + 1
    while list[after] and list[after].locked do
        after = after + 1
    end
    local last = after >= #list
    reforge.stepLen = (last and reforge.hot) and (REEL_STEP + REEL_SUSPENSE) or REEL_STEP
    fillReforge()
    animEvent = scheduleEvent(revealNext, reforge.stepLen)
end

function reforgeNow()
    local entry = bySlot[selected]
    if not entry or (reforge and (reforge.phase == 'rolling' or reforge.phase == 'reveal')) then
        return
    end
    local cost = tonumber(entry.rerollCost) or 0
    local lock = locks[selected]
    local again = reforge and reforge.phase == 'done' and reforge.slot == selected
    -- the item the question is about: "Yes" acts on it, not on whatever is
    -- selected when it is clicked
    local slot, itemId = selected, entry.itemId
    local function go()
        local now = bySlot[slot]
        if not now or now.itemId ~= itemId then
            setStatus(tr('The item changed: pick it and try again.'), '#ff7a6b')
            return
        end
        selected = slot
        reforge = {
            phase = 'rolling', slot = slot, before = entry.bonuses or {}, lock = lock,
            shown = 0, startedAt = g_clock.millis(),
        }
        setStatus(tr('Reforging...'), '#e0c060')
        Forge.send({ action = 'rerollItem', slot = slot, lock = lock })
        Forge.expectAnswer()
        fillReforge()
        pulse()
        runReels()
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
        text = tr('Reforge %s for %d Rarity XP and %s gold?\n\nSealed, with its value: %s\n\nRolled again:\n%s\n\nThe new ones can be better or worse, and there is no way back.', titleCase(entry.name), cost, formatGold(entry.lockCost), kept, table.concat(lines, '\n'))
    else
        text = tr('Reforge %s for %d Rarity XP?\n\nEvery bonus it has now is rolled again:\n%s\n\nThe new ones can be better or worse, and there is no way back.', titleCase(entry.name), cost, table.concat(lines, '\n'))
    end
    Forge.confirm(tr('Reforge'), text, go)
end

function skipReforge()
    if not reforge then
        return
    end
    if reforge.phase == 'rolling' then
        reforge.skip = true
    elseif reforge.phase == 'reveal' then
        stopAnim()
        finishReforge()
    end
end

-- ---------------------------------------------------------------------------
-- Ascension
-- ---------------------------------------------------------------------------

local TICKS = 72
local DIAL = 116
local RADIUS = 49

local function buildDial(dial)
    if dial.ticks then
        return
    end
    dial.ticks = {}
    local c = DIAL / 2
    for i = 0, TICKS - 1 do
        local angle = (i + 0.5) * 360 / TICKS
        local rad = math.rad(angle)
        local tick = g_ui.createWidget('UIWidget', dial)
        tick:setImageSource('/game_raritybonus/images/forge/tick')
        tick:setSize({ width = 4, height = 12 })
        tick:setPhantom(true)
        tick:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        tick:addAnchor(AnchorTop, 'parent', AnchorTop)
        tick:setMarginLeft(math.floor(c + RADIUS * math.sin(rad) - 2 + 0.5))
        tick:setMarginTop(math.floor(c - RADIUS * math.cos(rad) - 6 + 0.5))
        tick:setRotation(angle)
        dial.ticks[i + 1] = tick
    end
    dial.needle:raise()
end

fillAscend = function()
    local box = window.pages.arsenal.center.ascendBox
    local entry = bySlot[selected]
    if not entry then
        return
    end
    local up = entry.upgrade
    local shownUp = up
    -- right after going up, the dial still shows the way it went
    if ascend and ascend.slot == selected and ascend.offer then
        shownUp = ascend.offer
    end
    local visible = shownUp ~= nil
    for _, id in ipairs({ 'path', 'dial', 'resultTitle', 'resultText', 'history', 'goButton' }) do
        box[id]:setVisible(visible)
    end
    box.none:setVisible(not visible)
    if not visible then
        box.none:setText(tr('%s is %s, the highest grade: nothing above it.', titleCase(entry.name), grade(entry.rarity).label))
        return
    end
    local fromKey = ascend and ascend.slot == selected and ascend.fromKey or entry.rarity
    local from, to = grade(fromKey), grade(shownUp.to)
    box.path:setText(from.label .. '  >  ' .. to.label)
    box.path:setColor(to.color)
    box.path:setTooltip(tr('Up to %d bonuses now, up to %d if it goes up.', from.pips, to.pips))
    local how = tr('If it goes up: the item changes grade and its bonuses roll again, in the range of the new grade.') .. '\n\n' ..
        tr('If it fails: the item stays exactly as it was. The gold and the Rarity XP are spent.')
    box.info:setTooltip(how)
    buildDial(box.dial)
    local chance = tonumber(shownUp.chance) or 0
    for i, tick in ipairs(box.dial.ticks) do
        tick:setImageColor(i <= chance * TICKS / 100 and to.color or '#2a2430')
    end
    box.dial.chance:setText(chance .. '%')
    box.dial.chance:setColor(to.color)
    box.dial.needle:setRotation(needleAngle)

    local phase = ascend and ascend.slot == selected and ascend.phase or 'idle'
    if phase == 'idle' then
        box.resultTitle:setText(tr('%d%% chance', chance))
        box.resultTitle:setColor('#ece6dc')
        box.resultText:setText(tr('In the lit arc it becomes %s; outside it, it stays as it is.', to.label))
    elseif phase == 'waiting' or phase == 'spinning' then
        box.resultTitle:setText(tr('Spinning...'))
        box.resultTitle:setColor('#ddd0ff')
        box.resultText:setText(tr('Good luck.'))
    elseif phase == 'win' then
        box.resultTitle:setText(tr('Now %s!', to.label))
        box.resultTitle:setColor(to.color)
        box.resultText:setText(tr('It went up a grade and its bonuses rolled again: see the cards above.'))
    else
        box.resultTitle:setText(tr('Not this time'))
        box.resultTitle:setColor('#ff9c8a')
        box.resultText:setText(tr('It stays %s, as it was. Spent: %s gold and %d Rarity XP.', from.label, formatGold(shownUp.gold), tonumber(shownUp.xp) or 0))
    end
    -- this session's tries
    box.history:destroyChildren()
    local wins = 0
    for _, win in ipairs(history) do
        local pip = g_ui.createWidget('ForgePip', box.history)
        pip:setSize({ width = 10, height = 10 })
        if win then
            wins = wins + 1
            pip:setImageColor('#8fdc9a')
        else
            pip:setImageSource('/game_raritybonus/images/forge/pip_empty')
            pip:setImageColor('#ff9c8a')
        end
    end
    box.history:setTooltip(#history > 0 and tr('%d of %d tries went up', wins, #history) or nil)
    local goUp = entry.upgrade
    local busy = phase == 'waiting' or phase == 'spinning'
    if goUp then
        box.goButton:setText(tr('Ascend  -  %s gold + %d XP', formatGold(goUp.gold), tonumber(goUp.xp) or 0))
        box.goButton:setEnabled(not busy and gold >= (tonumber(goUp.gold) or 0) and rarityXp >= (tonumber(goUp.xp) or 0))
        if rarityXp < (tonumber(goUp.xp) or 0) then
            box.goButton:setTooltip(tr('You need %d Rarity XP and have %d.', tonumber(goUp.xp) or 0, rarityXp))
        elseif gold < (tonumber(goUp.gold) or 0) then
            box.goButton:setTooltip(tr('It costs %s gold and you have %s.', formatGold(goUp.gold), formatGold(gold)))
        else
            box.goButton:setTooltip(nil)
        end
    else
        box.goButton:setText(tr('Highest grade'))
        box.goButton:setEnabled(false)
    end
end

-- the result box shakes on a failure
local function shake(widget)
    local offsets = { -7, 6, -4, 3, -2, 0 }
    local i = 0
    -- around the widget's own margins (the box sits 12 px from its neighbour)
    widget.restMargins = widget.restMargins or { widget:getMarginLeft(), widget:getMarginRight() }
    local baseLeft, baseRight = widget.restMargins[1], widget.restMargins[2]
    local function step()
        if widget:isDestroyed() then
            return
        end
        i = i + 1
        widget:setMarginLeft(baseLeft + (offsets[i] or 0))
        widget:setMarginRight(baseRight - (offsets[i] or 0))
        if i < #offsets then
            scheduleEvent(step, 60)
        end
    end
    step()
end

local function setNeedle(angle)
    needleAngle = angle
    if window then
        window.pages.arsenal.center.ascendBox.dial.needle:setRotation(angle % 360)
    end
end

-- the needle while the server answers: a steady spin
local function spinWait()
    stopAnim()
    local last = g_clock.millis()
    local function tick()
        animEvent = nil
        if not ascend or ascend.phase ~= 'waiting' then
            return
        end
        local now = g_clock.millis()
        setNeedle(needleAngle + (now - last) * 0.54)
        last = now
        animEvent = scheduleEvent(tick, 16)
    end
    tick()
end

local function finishAscend()
    stopAnim()
    local win = ascend.win
    ascend.phase = win and 'win' or 'lose'
    tellPending()
    table.insert(history, win)
    while #history > 12 do
        table.remove(history, 1)
    end
    local pending = pendingData
    pendingData = nil
    if pending then
        Forge.apply(pending)
    else
        Forge.refresh()
    end
    if not win and window then
        shake(window.pages.arsenal.center.ascendBox)
    end
end

-- the answer came: the needle slows down onto its place in or out of the arc
local function spinTo(win, chance)
    stopAnim()
    local arc = chance * 3.6
    local land
    if win then
        land = arc * (0.15 + math.random() * 0.7)
    else
        land = arc + 4 + math.random() * math.max(1, 352 - arc)
    end
    local from = needleAngle
    local target = (math.floor(from / 360) + 3) * 360 + land
    local t0, duration = g_clock.millis(), 2800
    ascend.phase = 'spinning'
    local function tick()
        animEvent = nil
        if not ascend or ascend.phase ~= 'spinning' then
            return
        end
        local p = math.min(1, (g_clock.millis() - t0) / duration)
        local eased = 1 - (1 - p) ^ 3
        setNeedle(from + (target - from) * eased)
        if p >= 1 then
            finishAscend()
            return
        end
        animEvent = scheduleEvent(tick, 16)
    end
    tick()
end

function ascendNow()
    local entry = bySlot[selected]
    local up = entry and entry.upgrade
    if not up or (ascend and (ascend.phase == 'waiting' or ascend.phase == 'spinning')) then
        return
    end
    local slot, itemId = selected, entry.itemId
    local function go()
        local now = bySlot[slot]
        if not now or now.itemId ~= itemId or not now.upgrade then
            setStatus(tr('The item changed: pick it and try again.'), '#ff7a6b')
            return
        end
        selected = slot
        ascend = { phase = 'waiting', slot = slot, offer = up, fromKey = entry.rarity }
        setStatus(tr('Trying the Ascension...'), '#ddd0ff')
        Forge.send({ action = 'upgradeItem', slot = slot })
        Forge.expectAnswer()
        fillAscend()
        spinWait()
    end
    Forge.confirm(tr('Ascension'), tr('Raise %s to %s?\n\nPrice: %s gold and %d Rarity XP, paid even if it fails.\nChance: %d%%.\n\nOn success the item becomes %s and rolls its bonuses again at that grade. On a failure it stays exactly as it is.', titleCase(entry.name), up.label or '', formatGold(up.gold), tonumber(up.xp) or 0, tonumber(up.chance) or 0, up.label or ''), go)
end

-- ---------------------------------------------------------------------------
-- Your bonuses
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

function Forge.refresh()
    if not window then
        return
    end
    window.xpLabel:setText(tr('Rarity XP: %d', rarityXp))
    fillArsenal()
end

-- one page now (the Reforge, the Ascension and the bonuses are in it)
function showPage()
    if Forge.busy() then
        return
    end
    if reforge and reforge.phase == 'done' then
        reforge = nil
    end
    if ascend and (ascend.phase == 'win' or ascend.phase == 'lose') then
        ascend = nil
    end
    Forge.refresh()
end

local function messageOf(d)
    local result = d.result
    if type(result) ~= 'table' then
        return d.message and tr(d.message) or nil
    end
    local code = result.code
    if code == 'rerolled' and result.upgrade then
        return tr('Ascension! %s: %s. (-%s gold, -%d Rarity XP)', titleCase(result.name), table.concat(result.bonuses or {}, ', '), formatGold(result.gold), tonumber(result.cost) or 0)
    elseif code == 'rerolled' then
        local text = tr('%s reforged: %s. (-%d Rarity XP)', titleCase(result.name), table.concat(result.bonuses or {}, ', '), tonumber(result.cost) or 0)
        if result.perfect then
            text = text .. ' ' .. tr('Perfect roll!')
        end
        if (tonumber(result.gold) or 0) > 0 then
            text = text .. ' ' .. tr('(-%s gold for the seal)', formatGold(result.gold))
        end
        return text
    elseif code == 'upgradeFailed' then
        return tr('The Ascension to %s failed (%d%% chance): %s stays as it was. (-%s gold, -%d Rarity XP)', result.to or '', tonumber(result.chance) or 0, titleCase(result.name), formatGold(result.gold), tonumber(result.xp) or 0)
    elseif code == 'xp' then
        return tr('You need %d Rarity XP and have %d. Kill Pale, Ashen, Obsidian and Lord of Death monsters to earn more.', tonumber(result.cost) or 0, tonumber(result.balance) or 0)
    elseif code == 'gone' then
        return tr('That item is no longer equipped.')
    elseif code == 'gold' then
        return tr('You need %s gold in your backpack and bank.', formatGold(result.gold))
    elseif code == 'bought' then
        return result.currency == 'coins' and tr('+%d Rarity XP! (-%d Mythos Coins)', tonumber(result.xp) or 0, tonumber(result.price) or 0)
            or tr('+%d Rarity XP! (-%d Hunt Points)', tonumber(result.xp) or 0, tonumber(result.price) or 0)
    elseif code == 'coins' then
        return tr('This pack costs %d Mythos Coins and you have %d.', tonumber(result.price) or 0, tonumber(result.have) or 0)
    elseif code == 'points' then
        return tr('This pack costs %d Hunt Points and you have %d.', tonumber(result.price) or 0, tonumber(result.have) or 0)
    elseif code == 'pack' then
        return tr('This pack is not sold any more.')
    end
    return d.message and tr(d.message) or nil
end

-- a summary from the server becomes the window's data
function Forge.apply(d)
    data = d
    rarityXp = tonumber(d.rarityXp) or rarityXp
    gold = tonumber(d.gold) or gold
    items, bySlot, totalsByKey, bonusDescs = d.items or {}, {}, {}, {}
    for _, entry in ipairs(items) do
        bySlot[entry.slotId] = entry
        if locks[entry.slotId] and not sameKey(entry.bonuses, locks[entry.slotId]) then
            locks[entry.slotId] = nil
        end
    end
    for _, t in ipairs(d.totals or {}) do
        totalsByKey[t.key or ''] = t
        bonusDescs[t.key or ''] = t
    end
    if not bySlot[selected] then
        selected = items[1] and items[1].slotId or nil
    end
    Forge.refresh()
end

-- every 'bonuses' answer: an animation may be waiting for it
function Forge.onBonuses(d)
    if answerEvent and type(d.result) == 'table' then
        removeEvent(answerEvent)
        answerEvent = nil
    end
    local result = type(d.result) == 'table' and d.result or nil
    local message = messageOf(d)
    local color = d.ok == false and '#ff6464' or '#7fd35a'
    -- the answer to a reforge or an Ascension is told once the cards or the
    -- needle stop, not before
    local played = result and ((reforge and reforge.phase == 'rolling' and result.code == 'rerolled' and not result.upgrade)
        or (ascend and ascend.phase == 'waiting' and ((result.code == 'rerolled' and result.upgrade) or result.code == 'upgradeFailed')))
    if played then
        Forge.pendingMessage = { message, color }
    elseif message then
        setStatus(message, color)
    end
    rarityXp = tonumber(d.rarityXp) or rarityXp
    gold = tonumber(d.gold) or gold
    if result and reforge and reforge.phase == 'rolling' then
        if result.code == 'rerolled' and not result.upgrade then
            -- the new bonuses as the window shows them (with the finder's
            -- share); the roll's own lines if the item is not in the answer
            reforge.after = rolledBonuses(result)
            for _, entry in ipairs(d.items or {}) do
                if entry.slotId == reforge.slot then
                    reforge.after = {}
                    for _, bonus in ipairs(entry.bonuses or {}) do
                        local copy = {}
                        for k, v in pairs(bonus) do
                            copy[k] = v
                        end
                        copy.locked = reforge.lock ~= nil and bonus.key == reforge.lock or nil
                        table.insert(reforge.after, copy)
                    end
                end
            end
            reforge.shown = 0
            stopAnim()
            pendingData = d
            if reforge.skip then
                finishReforge()
                return
            end
            reforge.phase = 'reveal'
            fillReforge()
            runReels()
            -- the reels run a moment before the first card stops
            local wait = math.max(0, REEL_FIRST - (g_clock.millis() - reforge.startedAt))
            reforge.lastFlip = g_clock.millis() + wait - REEL_STEP
            animEvent = scheduleEvent(revealNext, wait)
            return
        end
        stopAnim()
        reforge = nil
    elseif result and ascend and ascend.phase == 'waiting' then
        local win = result.code == 'rerolled' and result.upgrade
        if win or result.code == 'upgradeFailed' then
            ascend.win = win and true or false
            if win then
                ascend.lines = table.concat(result.bonuses or {}, ', ')
            end
            pendingData = d
            spinTo(ascend.win, tonumber(ascend.offer and ascend.offer.chance) or 0)
            return
        end
        stopAnim()
        ascend = nil
    elseif (reforge and (reforge.phase == 'rolling' or reforge.phase == 'reveal')) or (ascend and (ascend.phase == 'waiting' or ascend.phase == 'spinning')) then
        -- a refresh while the cards or the needle move: after them
        pendingData = d
        return
    end
    Forge.apply(d)
end

-- the Rarity XP balance changed (a kill, the Store)
function Forge.onXp(xp)
    rarityXp = tonumber(xp) or rarityXp
    if window and window:isVisible() and not (reforge and reforge.phase ~= 'done') and not (ascend and (ascend.phase == 'waiting' or ascend.phase == 'spinning')) then
        Forge.refresh()
    end
end

-- no answer to a reforge or an Ascension: stop waiting and ask again
function Forge.expectAnswer()
    if answerEvent then
        removeEvent(answerEvent)
    end
    answerEvent = scheduleEvent(function()
        answerEvent = nil
        local stuck = (reforge and reforge.phase == 'rolling') or (ascend and ascend.phase == 'waiting')
        if not stuck then
            return
        end
        stopAnim()
        reforge, ascend = nil, nil
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
    local amount = bank or gold
    window.bankBox:setText(formatMoney(math.floor(amount), '.'))
    window.bankBox.icon:setImageSource('/images/game/cyclopedia/icons/icon-goldcoin')
    local tooltip = bank and backpack
        and tr('Bank: %s gold\nBackpack: %s gold\nThe gold prices (seal, Ascension) are paid from the backpack and the bank.', formatMoney(bank, '.'), formatMoney(backpack, '.'))
        or tr('Your gold, backpack and bank.')
    window.bankLabel:setTooltip(tooltip)
    window.bankBox:setTooltip(tooltip)
end

function Forge.window()
    return window
end

function Forge.busy()
    return (reforge and (reforge.phase == 'rolling' or reforge.phase == 'reveal')) or (ascend and (ascend.phase == 'waiting' or ascend.phase == 'spinning'))
end

function Forge.create()
    window = g_ui.displayUI('forge')
    window:hide()
end

function Forge.reset()
    stopAnim()
    if answerEvent then
        removeEvent(answerEvent)
        answerEvent = nil
    end
    reforge, ascend, pendingData = nil, nil, nil
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
    -- the next character starts clean: a seal left from this one would be
    -- charged on its item in the same slot with the same bonus
    locks, history, selected = {}, {}, nil
end

function Forge.destroy()
    Forge.reset()
    if window then
        window:destroy()
        window = nil
    end
end

function Forge.closeConfirm()
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
end
