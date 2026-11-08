-- Forja de Raridade: the rarity window (forge.otui). Four pages:
--   Arsenal      the rarity items worn, on a paperdoll; the one picked shows
--                each bonus with the range it rolls in and where the roll fell
--   Reforge      the reroll: the bonuses as cards, a click seals one (kept,
--                for gold); the cards turn face down and are revealed one by
--                one, then "before -> after"
--   Ascension    the grade upgrade: a dial whose lit arc is the chance; the
--                needle spins and stops in or out of it
--   Your bonuses the totals, each bar split by the items that give it
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
local SHARE_BAR = 206 -- "in your character"
local TOTAL_BAR = 426 -- Your bonuses

local window
local data -- the last summary from the server
local items, bySlot = {}, {}
local totalsByKey = {}
local selected -- slot id of the item shown
local page = 'arsenal'
local locks = {} -- slot id -> bonus key sealed on the next reforge
local filter = 'all'
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
            w:setBorderColor(g.color)
            w.pip:setImageColor(g.color)
            if slot == selected then
                w:setBorderWidth(3)
                w:setBorderColor('#f3d38a')
            end
            w:setTooltip(titleCase(entry.name) .. '\n' .. g.label)
            w.onClick = function() pickItem(slot) end
        else
            g_ui.createWidget('ForgeEmptySlot', doll)
        end
    end
    -- how many items of each grade
    local summary = p.left.summary
    summary:destroyChildren()
    local counts = {}
    for _, entry in ipairs(items) do
        counts[entry.rarity] = (counts[entry.rarity] or 0) + 1
    end
    for _, key in ipairs(GRADE_ORDER) do
        local row = g_ui.createWidget('UIWidget', summary)
        row:setHeight(14)
        local pip = g_ui.createWidget('ForgePip', row)
        pip:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        pip:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        pip:setImageColor(GRADES[key].color)
        local label = g_ui.createWidget('ForgeText', row)
        label:addAnchor(AnchorLeft, 'prev', AnchorRight)
        label:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        label:setMarginLeft(10)
        label:setText(GRADES[key].label)
        label:setTextAutoResize(true)
        local count = g_ui.createWidget('ForgeText', row)
        count:addAnchor(AnchorRight, 'parent', AnchorRight)
        count:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        count:setTextAutoResize(true)
        count:setFont('Verdana Bold-11px')
        count:setText(tostring(counts[key] or 0))
    end

    local c = p.center
    local entry = bySlot[selected]
    for _, id in ipairs({ 'pedestal', 'badge', 'pips', 'name', 'info', 'bonusTitle', 'qualityTitle', 'bonuses', 'reforgeButton', 'ascendButton' }) do
        c[id]:setVisible(entry ~= nil)
    end
    c.empty:setVisible(entry == nil)
    p.right.shares:destroyChildren()
    if not entry then
        return
    end
    local g = grade(entry.rarity)
    c.pedestal:setBorderColor(g.color)
    c.pedestal.inner:setBorderColor(g.color .. '55')
    setItem(c.pedestal.item, entry)
    c.badge:setText(g.label:upper())
    c.badge:setBackgroundColor(g.color)
    fillPips(c.pips, entry.rarity)
    c.name:setText(titleCase(entry.name))
    local info = { tr(entry.slot or '') }
    if (tonumber(entry.level) or 0) > 0 then
        table.insert(info, tr('Level %d', entry.level))
    end
    table.insert(info, entry.finder and tr('Found by you') or tr('Not found by you'))
    c.info:setText(table.concat(info, '   '))

    local list = c.bonuses
    list:destroyChildren()
    for _, bonus in ipairs(entry.bonuses or {}) do
        local row = g_ui.createWidget('ForgeBonusRow', list)
        row.name:setText(tr(bonus.label or ''))
        local q = qualityOf(bonus)
        local look = quality(q, bonus.perfect)
        row.value:setText(plus(bonus.value, bonus.unit))
        row.value:setColor(q and look[3] or '#ece6dc')
        local hasRange = q ~= nil
        row.track:setVisible(hasRange)
        row.low:setVisible(hasRange and bonus.min ~= nil)
        row.high:setVisible(hasRange and bonus.max ~= nil)
        if hasRange then
            row.track.fill:setWidth(math.floor(BAR * q + 0.5))
            row.track.fill:setBackgroundColor(look[3])
            row.track.fill:setOpacity(0.85)
            row.track.mark:setMarginLeft(math.max(0, math.floor(BAR * q + 0.5) - 1))
            if bonus.min then
                row.low:setText(plus(bonus.min, bonus.unit))
                row.high:setText(plus(bonus.max, bonus.unit))
            end
            row.quality:setText(tr(look[2]) .. ' ' .. math.floor(q * 100 + 0.5) .. '%')
            row.quality:setColor(look[3])
            row.quality:setBackgroundColor(look[4])
            row.quality:setBorderColor(look[3] .. '55')
        else
            row.quality:setText('')
            row.quality:setBorderWidth(0)
        end
        local desc = describe(bonus.key)
        if desc then
            row:setTooltip(desc)
        end
    end

    -- this item's share of each total
    for _, bonus in ipairs(entry.bonuses or {}) do
        local total = totalsByKey[bonus.key]
        local row = g_ui.createWidget('ForgeShareRow', p.right.shares)
        row.name:setText(tr(bonus.label or ''))
        local cap = total and not total.perItem and tonumber(total.cap)
        if cap and cap > 0 then
            local sum = tonumber(total.total) or 0
            row.total:setText(number(sum) .. (bonus.unit or '') .. ' / ' .. number(cap) .. (bonus.unit or ''))
            local mine = math.min(1, (tonumber(bonus.value) or 0) / cap)
            local others = math.max(0, math.min(1 - mine, (sum - (tonumber(bonus.value) or 0)) / cap))
            row.track.others:setWidth(math.floor(SHARE_BAR * others + 0.5))
            row.track.mine:setWidth(math.max(1, math.floor(SHARE_BAR * mine + 0.5)))
            if total.capped then
                row.total:setColor('#f3d38a')
            end
        else
            row.total:setText(tr('on the item'))
            row.track:setVisible(false)
        end
    end

    c.reforgeButton:setText(tr('Reforge  -  %d Rarity XP', tonumber(entry.rerollCost) or 0))
    local up = entry.upgrade
    c.ascendButton:setEnabled(up ~= nil)
    c.ascendButton:setText(up and tr('Ascend to %s  -  %d%%', up.label or '', tonumber(up.chance) or 0) or tr('Highest grade'))
end

-- ---------------------------------------------------------------------------
-- Reforge
-- ---------------------------------------------------------------------------

local CARD_W = 124

local function lockable(entry)
    return entry and (tonumber(entry.lockCost) or 0) > 0 and #(entry.bonuses or {}) >= 2
end

local function fillCard(card, bonus, opts)
    card.back:setVisible(false)
    card.empty:setVisible(false)
    card.flash:setVisible(false)
    card.glow:setVisible(false)
    for _, id in ipairs({ 'number', 'track', 'grade', 'name', 'value', 'range' }) do
        card[id]:setVisible(true)
    end
    card.number:setText(tr('BONUS %d', opts.n))
    card.sealed:setVisible(opts.locked or false)
    card:setBorderWidth(opts.locked and 2 or 1)
    card:setBorderColor(opts.locked and '#e8c77a' or '#2e2833')
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
    card.range:setText((bonus.min and bonus.max) and tr('range %s to %s', plus(bonus.min, bonus.unit), plus(bonus.max, bonus.unit)) or '')
    if bonus.perfect then
        card.glow:setVisible(true)
        card.glow:setImageColor('#f3d38a')
        card:setBorderColor('#f3d38a')
    end
    local desc = describe(bonus.key)
    card:setTooltip(desc)
end

local function backCard(card, n)
    card.back:setVisible(true)
    card.empty:setVisible(false)
    card.sealed:setVisible(false)
    card.glow:setVisible(false)
    card:setTooltip(nil)
    card:setBorderWidth(1)
    card:setBorderColor('#2e2833')
end

local function emptyCard(card)
    card.back:setVisible(false)
    card.flash:setVisible(false)
    card.glow:setVisible(false)
    card.sealed:setVisible(false)
    for _, id in ipairs({ 'number', 'track', 'grade', 'name', 'value', 'range' }) do
        card[id]:setVisible(false)
    end
    card.empty:setVisible(true)
    card:setBorderColor('#241f28')
    card:setTooltip(nil)
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

local function fillDiff()
    local p = window.pages.reforge.main
    p.diff:destroyChildren()
    local show = reforge and reforge.phase == 'done'
    p.diffTitle:setVisible(show or false)
    if not show then
        return
    end
    local after = reforge.after or {}
    for _, bonus in ipairs(after) do
        local row = g_ui.createWidget('ForgeDiffRow', p.diff)
        local old = sameKey(reforge.before, bonus.key, bonus.label)
        row.name:setText(tr(bonus.label or ''))
        row.after:setText(plus(bonus.value, bonus.unit))
        if bonus.locked or (reforge.lock and bonus.key == reforge.lock) then
            row.before:setText(plus(old and old.value or bonus.value, bonus.unit))
            row.delta:setText(tr('sealed'))
            row.delta:setColor('#e8c77a')
        elseif old then
            row.before:setText(plus(old.value, old.unit))
            local d = (tonumber(bonus.value) or 0) - (tonumber(old.value) or 0)
            row.delta:setText((d >= 0 and '+' or '-') .. number(math.abs(math.floor(d * 10 + 0.5) / 10)))
            row.delta:setColor(d >= 0 and '#8fdc9a' or '#ff9c8a')
        else
            row.before:setText('-')
            row.delta:setText(tr('new'))
            row.delta:setColor('#c9a4ff')
        end
    end
    for _, old in ipairs(reforge.before or {}) do
        if not sameKey(after, old.key, old.label) and not sameKey(after, nil, old.label) then
            local row = g_ui.createWidget('ForgeDiffRow', p.diff)
            row.name:setText(tr(old.label or ''))
            row.before:setText(plus(old.value, old.unit))
            row.after:setText('-')
            row.delta:setText(tr('lost'))
            row.delta:setColor('#ff9c8a')
        end
    end
end

local function fillReforge()
    local p = window.pages.reforge
    local m = p.main
    local entry = bySlot[selected]
    m.strip:destroyChildren()
    for _, it in ipairs(items) do
        local chip = g_ui.createWidget('ForgeItemChip', m.strip)
        setItem(chip.item, it)
        local g = grade(it.rarity)
        chip:setBorderColor(it.slotId == selected and '#f3d38a' or g.color)
        chip:setBorderWidth(it.slotId == selected and 3 or 2)
        chip:setTooltip(titleCase(it.name) .. '\n' .. g.label)
        chip.onClick = function() pickItem(it.slotId) end
    end
    local cards = m.cards
    cards:destroyChildren()
    if not entry then
        m.name:setText(tr('No rarity item worn'))
        m.gradeLine:setText('')
        m.hint:setText('')
        p.side.rollButton:setEnabled(false)
        p.side.skipButton:setVisible(false)
        fillDiff()
        return
    end
    local g = grade(entry.rarity)
    m.frame:setBorderColor(g.color)
    setItem(m.frame.item, entry)
    local max = math.max(1, tonumber(entry.maxBonuses) or #(entry.bonuses or {}))
    m.gradeLine:setText(tr('%s  -  1 to %d bonuses', g.label:upper(), max))
    if max == 1 then
        m.gradeLine:setText(g.label:upper() .. '  -  ' .. tr('1 bonus'))
    end
    m.gradeLine:setColor(g.color)
    m.name:setText(titleCase(entry.name))
    cards:setWidth(max * CARD_W + (max - 1) * 10)

    local phase = reforge and reforge.slot == selected and reforge.phase or 'idle'
    local lock = locks[selected]
    if phase == 'idle' then
        if lockable(entry) then
            m.hint:setText(tr('Click a card to seal its bonus: it keeps its value and the others roll again. Then reforge.'))
        else
            m.hint:setText(tr('The Reforge rolls the whole item again: how many bonuses, which ones and their values.'))
        end
    elseif phase == 'rolling' or phase == 'reveal' then
        m.hint:setText(tr('The cards turn one by one, from left to right.'))
    else
        m.hint:setText(tr('Done. Below, before and after: green went up, red went down, violet is a new bonus.'))
    end

    for n = 1, max do
        local card = g_ui.createWidget('ForgeCard', cards)
        if phase == 'idle' then
            local bonus = (entry.bonuses or {})[n]
            if bonus then
                fillCard(card, bonus, { n = n, locked = lock == bonus.key })
                if lockable(entry) then
                    card.onClick = function()
                        locks[selected] = (locks[selected] == bonus.key) and nil or bonus.key
                        if locks[selected] then
                            setStatus(tr('%s sealed: the next reforge keeps it with this value and rolls the others, for %s gold more.', bonusText(bonus), formatGold(entry.lockCost)), '#e8c77a')
                        else
                            setStatus(tr('%s is no longer sealed.', bonusText(bonus)), '#ab9fc6')
                        end
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
                if n == reforge.flashAt then
                    flashCard(card, bonus.perfect and '#f3d38a' or quality(qualityOf(bonus), bonus.perfect)[3])
                end
            elseif not bonus and reforge.shown >= #list then
                emptyCard(card)
            else
                backCard(card, n)
            end
            if phase == 'done' then
                card.onClick = function()
                    reforge = nil
                    fillReforge()
                end
            end
        end
    end
    if reforge then
        reforge.flashAt = nil
    end

    -- the odds of how many bonuses, the rules and the price
    local s = p.side
    s.odds:destroyChildren()
    local counts = entry.counts
    if lock then
        s.countTitle:setText(tr('With a seal, the item keeps its %d bonuses', #(entry.bonuses or {})))
    elseif type(counts) == 'table' and #counts > 0 then
        s.countTitle:setText(tr('How many bonuses the item gets'))
        local top = 0
        for _, pct in ipairs(counts) do
            top = math.max(top, tonumber(pct) or 0)
        end
        for i, pct in ipairs(counts) do
            local row = g_ui.createWidget('ForgeOddsRow', s.odds)
            row.label:setText(i == 1 and tr('1 bonus') or tr('%d bonuses', i))
            row.pct:setText(number(pct) .. '%')
            row.track.fill:setBackgroundColor(g.color)
            row.track.fill:setWidth(math.floor(110 * (tonumber(pct) or 0) / math.max(1, top) + 0.5))
        end
    else
        s.countTitle:setText(tr('The item always gets %d bonuses', max))
    end
    local perfect = tonumber(data and data.perfectChance) or 0
    local rules = tr('Which bonuses: drawn from the list of this kind of item.') .. '\n' ..
        tr('Values: within the range of %s.', g.label)
    if perfect > 0 then
        local pct = perfect * 100
        local text = pct >= 1 and string.format('%.1f%%', pct) or pct >= 0.01 and string.format('%.2f%%', pct) or string.format('%.3f%%', pct)
        rules = rules .. '\n' .. tr('Perfect roll: %s per bonus.', text)
    end
    rules = rules .. '\n' .. tr('Fewer bonuses come stronger.')
    s.rules:setText(rules)
    local cost = tonumber(entry.rerollCost) or 0
    s.costXp:setText(tr('Rarity XP: %d (you have %d)', cost, rarityXp))
    s.costXp:setColor(rarityXp >= cost and '#d6cfc2' or '#ff9c8a')
    if lockable(entry) then
        s.costSeal:setText(tr('Seal (keep 1 bonus): %s gold', formatGold(entry.lockCost)))
        s.costSeal:setColor(lock and '#e8c77a' or '#6e665e')
        s.sealHelp:setText(tr('Click a card to seal it. One card at a time; click it again to let it go.'))
    else
        s.costSeal:setText(tr('Seal: needs an item with 2 or more bonuses'))
        s.costSeal:setColor('#6e665e')
        s.sealHelp:setText('')
    end
    local lockGold = lock and (tonumber(entry.lockCost) or 0) or 0
    local busy = phase == 'rolling' or phase == 'reveal'
    s.rollButton:setText(lock and tr('Reforge  -  %d XP + %s gold', cost, formatGold(lockGold)) or tr(phase == 'done' and 'Reforge again  -  %d XP' or 'Reforge  -  %d XP', cost))
    s.rollButton:setEnabled(not busy and cost > 0 and rarityXp >= cost and gold >= lockGold)
    s.skipButton:setVisible(busy)
    if cost > 0 and rarityXp < cost then
        s.rollButton:setTooltip(tr('You need %d Rarity XP and have %d. Buy more here or kill Pale, Ashen, Obsidian and Lord of Death monsters.', cost, rarityXp))
    elseif gold < lockGold then
        s.rollButton:setTooltip(tr('The seal costs %s gold and you have %s.', formatGold(lockGold), formatGold(gold)))
    else
        s.rollButton:setTooltip(nil)
    end
    fillDiff()
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
        for _, card in ipairs(window.pages.reforge.main.cards:getChildren()) do
            if card.back:isVisible() then
                card.back:setBorderColor(a > 0.5 and '#8a6dd0' or '#3d3346')
                card.back.rune:setOpacity(0.55 + 0.45 * a)
            end
        end
        animEvent = scheduleEvent(tick, 50)
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
    if reforge.shown >= #list then
        reforge.flashAt = math.min(reforge.shown, #list)
        fillReforge()
        animEvent = scheduleEvent(finishReforge, 450)
        return
    end
    reforge.flashAt = reforge.shown
    fillReforge()
    animEvent = scheduleEvent(revealNext, 450)
end

function reforgeNow()
    local entry = bySlot[selected]
    if not entry or (reforge and (reforge.phase == 'rolling' or reforge.phase == 'reveal')) then
        return
    end
    local cost = tonumber(entry.rerollCost) or 0
    local lock = locks[selected]
    local again = reforge and reforge.phase == 'done' and reforge.slot == selected
    local function go()
        reforge = {
            phase = 'rolling', slot = selected, before = entry.bonuses or {}, lock = lock,
            shown = 0, startedAt = g_clock.millis(),
        }
        setStatus(tr('Reforging...'), '#e0c060')
        Forge.send({ action = 'rerollItem', slot = selected, lock = lock })
        Forge.expectAnswer()
        fillReforge()
        pulse()
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

local TICKS = 100
local DIAL = 220
local RADIUS = 97

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
        tick:setSize({ width = 6, height = 18 })
        tick:setPhantom(true)
        tick:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        tick:addAnchor(AnchorTop, 'parent', AnchorTop)
        tick:setMarginLeft(math.floor(c + RADIUS * math.sin(rad) - 3 + 0.5))
        tick:setMarginTop(math.floor(c - RADIUS * math.cos(rad) - 9 + 0.5))
        tick:setRotation(angle)
        dial.ticks[i + 1] = tick
    end
    dial.needle:raise()
end

local function upgradable()
    local list = {}
    for _, entry in ipairs(items) do
        list[#list + 1] = entry
    end
    return list
end

local function fillAscend()
    local p = window.pages.ascend
    local entry = bySlot[selected]
    p.list.rows:destroyChildren()
    local any = false
    for _, it in ipairs(upgradable()) do
        local row = g_ui.createWidget('ForgeAscendRow', p.list.rows)
        local from = grade(it.rarity)
        setItem(row.frame.item, it)
        row.frame:setBorderColor(from.color)
        row.name:setText(titleCase(it.name))
        row:setOn(it.slotId == selected)
        if it.upgrade then
            any = true
            row.path:setText(from.label .. ' -> ' .. (it.upgrade.label or ''))
            row.chance:setText((tonumber(it.upgrade.chance) or 0) .. '%')
        else
            row.path:setText(from.label .. '  ' .. tr('(highest grade)'))
            row.chance:setText('')
        end
        row.onClick = function() pickItem(it.slotId) end
    end
    local m = p.main
    local up = entry and entry.upgrade
    local shownUp = up
    -- right after going up, the crests still show the way it went
    if ascend and ascend.slot == selected and ascend.offer then
        shownUp = ascend.offer
    end
    local visible = entry ~= nil and (shownUp ~= nil)
    m.stage:setVisible(visible)
    m.result:setVisible(visible)
    m.goButton:setVisible(visible)
    m.none:setVisible(not visible)
    if not entry then
        m.none:setText(tr('You wear no rarity item.'))
    elseif not shownUp then
        m.none:setText(tr('%s is %s, the highest grade.', titleCase(entry.name), grade(entry.rarity).label))
    end
    local s = p.side
    s.how:setText(tr('If it goes up: the item changes grade and its bonuses roll again, in the range of the new grade.') .. '\n\n' ..
        tr('If it fails: the item stays exactly as it was. The gold and the Rarity XP are spent.') .. '\n\n' ..
        tr('The needle spins and stops in or out of the lit arc: the arc is as big as the chance.'))
    s.history:destroyChildren()
    local wins = 0
    for _, win in ipairs(history) do
        local pip = g_ui.createWidget('ForgePip', s.history)
        pip:setSize({ width = 12, height = 12 })
        if win then
            wins = wins + 1
            pip:setImageColor('#8fdc9a')
        else
            pip:setImageSource('/game_raritybonus/images/forge/pip_empty')
            pip:setImageColor('#ff9c8a')
        end
    end
    s.historyText:setText(#history > 0 and tr('%d of %d tries went up', wins, #history) or tr('No tries yet.'))
    if not visible then
        return
    end

    local fromKey = ascend and ascend.slot == selected and ascend.fromKey or entry.rarity
    local from, to = grade(fromKey), grade(shownUp.to)
    local stage = m.stage
    buildDial(stage.dial)
    setItem(stage.from.item, entry)
    stage.from.frame:setImageColor(from.color)
    stage.fromName:setText(from.label)
    stage.fromName:setColor(from.color)
    stage.fromInfo:setText(tr('now, up to %d bonuses', from.pips))
    setItem(stage.to.item, entry)
    stage.to.frame:setImageColor(to.color)
    stage.toName:setText(to.label)
    stage.toName:setColor(to.color)
    stage.toInfo:setText(tr('if it goes up, up to %d', to.pips))
    local won = ascend and ascend.slot == selected and ascend.phase == 'win'
    stage.to:setOpacity(won and 1 or 0.5)
    stage.to.glow:setVisible(won or false)
    stage.to.glow:setImageColor(to.color)
    local chance = tonumber(shownUp.chance) or 0
    for i, tick in ipairs(stage.dial.ticks) do
        tick:setImageColor(i <= chance * TICKS / 100 and to.color or '#2a2430')
    end
    stage.dial.chance:setText(chance .. '%')
    stage.dial.chance:setColor(to.color)
    stage.dial.needle:setRotation(needleAngle)

    local phase = ascend and ascend.slot == selected and ascend.phase or 'idle'
    local r = m.result
    r:setBorderColor('#2e2833')
    if phase == 'idle' then
        r.title:setText(tr('Ready to try'))
        r.title:setColor('#ece6dc')
        r.text:setText(tr('The needle spins and stops. If it lands in the %s arc, the item goes up a grade.', to.label))
    elseif phase == 'waiting' or phase == 'spinning' then
        r.title:setText(tr('Spinning...'))
        r.title:setColor('#ddd0ff')
        r.text:setText(tr('Good luck.'))
    elseif phase == 'win' then
        r.title:setText(tr('It went up! Now it is %s', to.label))
        r.title:setColor(to.color)
        r.text:setText(ascend.lines and ascend.lines ~= '' and tr('New bonuses: %s', ascend.lines) or tr('Its bonuses rolled again at %s.', to.label))
        r:setBorderColor(to.color)
    else
        r.title:setText(tr('Not this time'))
        r.title:setColor('#ff9c8a')
        r.text:setText(tr('%s stays %s, as it was. Spent: %s gold and %d Rarity XP.', titleCase(entry.name), from.label, formatGold(shownUp.gold), tonumber(shownUp.xp) or 0))
        r:setBorderColor('#7a3a33')
    end
    local goUp = entry.upgrade
    local busy = phase == 'waiting' or phase == 'spinning'
    if goUp then
        m.goButton:setText(tr('Try the Ascension  -  %s gold + %d XP', formatGold(goUp.gold), tonumber(goUp.xp) or 0))
        m.goButton:setEnabled(not busy and gold >= (tonumber(goUp.gold) or 0) and rarityXp >= (tonumber(goUp.xp) or 0))
        if rarityXp < (tonumber(goUp.xp) or 0) then
            m.goButton:setTooltip(tr('You need %d Rarity XP and have %d.', tonumber(goUp.xp) or 0, rarityXp))
        elseif gold < (tonumber(goUp.gold) or 0) then
            m.goButton:setTooltip(tr('It costs %s gold and you have %s.', formatGold(goUp.gold), formatGold(gold)))
        else
            m.goButton:setTooltip(nil)
        end
    else
        m.goButton:setText(tr('Highest grade'))
        m.goButton:setEnabled(false)
    end
end

-- the result box shakes on a failure
local function shake(widget)
    local offsets = { -7, 6, -4, 3, -2, 0 }
    local i = 0
    local function step()
        if widget:isDestroyed() then
            return
        end
        i = i + 1
        widget:setMarginLeft(offsets[i] or 0)
        widget:setMarginRight(-(offsets[i] or 0))
        if i < #offsets then
            scheduleEvent(step, 60)
        end
    end
    step()
end

local function setNeedle(angle)
    needleAngle = angle
    if window then
        window.pages.ascend.main.stage.dial.needle:setRotation(angle % 360)
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
        shake(window.pages.ascend.main.result)
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
    local function go()
        ascend = { phase = 'waiting', slot = selected, offer = up, fromKey = entry.rarity }
        setStatus(tr('Trying the Ascension...'), '#ddd0ff')
        Forge.send({ action = 'upgradeItem', slot = selected })
        Forge.expectAnswer()
        fillAscend()
        spinWait()
    end
    Forge.confirm(tr('Ascension'), tr('Raise %s to %s?\n\nPrice: %s gold and %d Rarity XP, paid even if it fails.\nChance: %d%%.\n\nOn success the item becomes %s and rolls its bonuses again at that grade. On a failure it stays exactly as it is.', titleCase(entry.name), up.label or '', formatGold(up.gold), tonumber(up.xp) or 0, tonumber(up.chance) or 0, up.label or ''), go)
end

-- ---------------------------------------------------------------------------
-- Your bonuses
-- ---------------------------------------------------------------------------

local function groupOf(key)
    key = key or ''
    if key:find('resist') or key == 'max_health' or key == 'dodge' or key == 'armor' or key == 'defense'
        or key == 'mending' or key:find('barrier') or key == 'vanguard' then
        return 'defense'
    end
    if key == 'speed' or key:find('cooldown') or key:find('leech') or key == 'max_mana' then
        return 'utility'
    end
    return 'offense'
end

local FILTERS = {
    { 'all', 'All' }, { 'offense', 'Offense' }, { 'defense', 'Defense' }, { 'utility', 'Utility' },
}

local function fillBonuses()
    local p = window.pages.bonuses
    local totals = (data and data.totals) or {}
    local atLimit, near = 0, 0
    for _, t in ipairs(totals) do
        local cap = not t.perItem and tonumber(t.cap)
        if cap and cap > 0 then
            local share = (tonumber(t.total) or 0) / cap
            if t.capped or share >= 1 then
                atLimit = atLimit + 1
            elseif share >= 0.8 then
                near = near + 1
            end
        end
    end
    p.tiles:destroyChildren()
    for _, tile in ipairs({
        { tr('ACTIVE BONUSES'), tostring(#totals), tr('from %d items', #items), '#ece6dc' },
        { tr('AT THE LIMIT'), tostring(atLimit), tr('more adds nothing'), '#f3d38a' },
        { tr('NEAR THE LIMIT'), tostring(near), tr('80% or more'), '#e8c77a' },
        { tr('RARITY XP'), tostring(rarityXp), tr('for the Forge'), '#c9a4ff' },
    }) do
        local w = g_ui.createWidget('ForgeTile', p.tiles)
        w:setWidth(228)
        w.label:setText(tile[1])
        w.value:setText(tile[2])
        w.value:setColor(tile[4])
        w.sub:setText(tile[3])
    end
    p.filters:destroyChildren()
    for _, f in ipairs(FILTERS) do
        local b = g_ui.createWidget('ForgeFilter', p.filters)
        b:setText(tr(f[2]))
        b:setOn(filter == f[1])
        b.onClick = function()
            filter = f[1]
            fillBonuses()
        end
    end
    p.legend:destroyChildren()
    for i = #GRADE_ORDER, 1, -1 do
        local key = GRADE_ORDER[i]
        local pip = g_ui.createWidget('ForgePip', p.legend)
        pip:setImageColor(GRADES[key].color)
        pip:setMarginTop(3)
        local label = g_ui.createWidget('ForgeDim', p.legend)
        label:setText(GRADES[key].label)
        label:setWidth(#GRADES[key].label * 7 + 4)
    end

    local list = p.list
    list:destroyChildren()
    for _, t in ipairs(totals) do
        if filter == 'all' or groupOf(t.key) == filter then
            local row = g_ui.createWidget('ForgeTotalRow', list)
            row.name:setText(tr(t.label or ''))
            local desc = describe(t.key)
            if desc then
                row:setTooltip(desc)
            end
            local unit = t.unit or ''
            local cap = not t.perItem and tonumber(t.cap)
            if cap and cap <= 0 then
                cap = nil
            end
            local sum = tonumber(t.total) or 0
            local share = cap and sum / cap or nil
            if cap then
                row.total:setText(plus(sum, unit) .. ' / ' .. number(cap) .. unit)
            else
                row.total:setText(plus(sum, unit) .. ' ' .. tr('(on each item)'))
            end
            if share and (t.capped or share >= 1) then
                row.tag:setText(tr('at the limit'))
                row.tag:setColor('#1a1306')
                row.tag:setBackgroundColor('#e8c77a')
                row.total:setColor('#f3d38a')
            elseif share and share >= 0.8 then
                row.tag:setText(tr('near the limit'))
                row.tag:setColor('#e8c77a')
                row.tag:setBorderWidth(1)
                row.tag:setBorderColor('#8a6d36')
            else
                row.tag:setVisible(false)
            end
            -- the bar: one piece per item, in its grade's colour
            local sources = t.sources or {}
            local scale = cap or 0
            if not cap then
                for _, src in ipairs(sources) do
                    scale = scale + (tonumber(src.value) or 0)
                end
            end
            local widths, used = {}, 0
            for i, src in ipairs(sources) do
                widths[i] = scale > 0 and math.max(2, math.floor(TOTAL_BAR * (tonumber(src.value) or 0) / scale)) or 0
                used = used + widths[i] + 2
            end
            if used > TOTAL_BAR then
                local k = TOTAL_BAR / used
                for i in ipairs(widths) do
                    widths[i] = math.max(1, math.floor(widths[i] * k))
                end
            end
            for i, src in ipairs(sources) do
                local it = items[tonumber(src.item) or 0]
                local seg = g_ui.createWidget('UIWidget', row.track)
                seg:setWidth(widths[i])
                seg:setPhantom(true)
                seg:setBackgroundColor(it and grade(it.rarity).color or '#5a5260')
                local chip = g_ui.createWidget('ForgeChip', row.chips)
                if it then
                    setItem(chip.item, it)
                    chip:setBorderColor(grade(it.rarity).color .. '88')
                end
                chip.value:setText(plus(src.value, unit))
                chip:setWidth(26 + chip.value:getTextSize().width + 6)
                chip:setTooltip(titleCase(src.name or (it and it.name) or ''))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

local PAGES = { arsenal = 'tabArsenal', reforge = 'tabReforge', ascend = 'tabAscend', bonuses = 'tabBonuses' }

function Forge.refresh()
    if not window then
        return
    end
    window.xpLabel:setText(tr('Rarity XP: %d', rarityXp))
    for name, tab in pairs(PAGES) do
        window.tabs[tab]:setOn(name == page)
        window.pages[name]:setVisible(name == page)
    end
    if page == 'arsenal' then
        fillArsenal()
    elseif page == 'reforge' then
        fillReforge()
    elseif page == 'ascend' then
        fillAscend()
    else
        fillBonuses()
    end
end

function showPage(name)
    if not PAGES[name] then
        return
    end
    if reforge and (reforge.phase == 'rolling' or reforge.phase == 'reveal') and name ~= 'reforge' then
        return
    end
    if ascend and (ascend.phase == 'waiting' or ascend.phase == 'spinning') and name ~= 'ascend' then
        return
    end
    page = name
    if reforge and reforge.phase == 'done' then
        reforge = nil
    end
    if ascend and (ascend.phase == 'win' or ascend.phase == 'lose') then
        ascend = nil
    end
    -- the Ascension starts on an item that can go up
    if name == 'ascend' then
        local entry = bySlot[selected]
        if not (entry and entry.upgrade) then
            for _, it in ipairs(items) do
                if it.upgrade then
                    selected = it.slotId
                    break
                end
            end
        end
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
            local wait = math.max(0, 900 - (g_clock.millis() - reforge.startedAt))
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
