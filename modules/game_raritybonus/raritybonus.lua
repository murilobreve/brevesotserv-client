-- Rarity Bonuses: every rarity item the player wears with its bonuses, and
-- the total of each bonus with the items it comes from. The numbers come from
-- the server (scripts/rarity/bonus_window.lua, extended opcode 123), which
-- adds them up the same way the bonuses are applied.

local OPCODE = 123
local FRAME_SIZE = 34
local LINE = 14

local GRADES = {
    uncommon  = { label = 'Communis',    color = '#63c08a', frame = 1 },
    rare      = { label = 'Rarus',       color = '#4f8fe8', frame = 2 },
    epic      = { label = 'Praeclarus',  color = '#af78ea', frame = 3 },
    legendary = { label = 'Legendarius', color = '#e2a443', frame = 4 },
    mythic    = { label = 'Mythicus',    color = '#e8e4ff', frame = 5 },
}

local window
local featureButton
local refreshEvent
local confirmBox
local rarityXp = 0
local gold = 0 -- backpack + bank, for the gold prices (lock, upgrade)
local locks = {} -- slot id -> affix key kept on that item's next reroll
local upgradeAsked -- { entry }: an upgrade sent, its answer plays on the reel

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(OPCODE, data)
    end
end

-- 12 -> "12", 14.4 -> "14.4"
local function number(value)
    value = tonumber(value) or 0
    if math.floor(value) == value then
        return tostring(math.floor(value))
    end
    return string.format('%.1f', value)
end

-- 2450 -> "2.4k": the buttons are small
local function formatCost(cost)
    cost = tonumber(cost) or 0
    if cost >= 10000 then
        return string.format('%dk', math.floor(cost / 1000))
    elseif cost >= 1000 then
        return string.format('%.1fk', math.floor(cost / 100) / 10)
    end
    return tostring(cost)
end

-- 25000000 -> "25kk", 3500000 -> "3.5kk", 800000 -> "800k"
local function formatGold(value)
    value = tonumber(value) or 0
    if value >= 1000000 then
        local kk = value / 1000000
        return (math.floor(kk) == kk and string.format('%dkk', kk) or string.format('%.1fkk', math.floor(kk * 10) / 10))
    elseif value >= 1000 then
        return string.format('%dk', math.floor(value / 1000))
    end
    return tostring(value)
end

local function bonusText(bonus)
    local text = string.format('+%s%s %s', number(bonus.value), bonus.unit or '', bonus.label)
    if bonus.range then
        text = text .. string.format(' (%d sqm)', bonus.range)
    end
    return text
end

local function titleCase(text)
    return (text:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

local function confirm(title, message, callback)
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

-- an item's Reroll button follows the balance: off, saying why, while the
-- Rarity XP doesn't pay for it
local function setRerollState(row)
    local entry = row.entry
    local grade = GRADES[entry.rarity] or GRADES.uncommon
    local cost = entry.rerollCost or 0
    local lockGold = locks[entry.slotId] and (entry.lockCost or 0) or 0
    row.rerollItemButton:setTooltip(tr('Reroll the whole item at %s: how many bonuses (up to %d), which ones and their values are rolled again. The item, its grade and its finder stay. (%d Rarity XP)', grade.label, entry.maxBonuses or 0, cost))
    row.rerollItemButton:setEnabled(cost > 0 and rarityXp >= cost and gold >= lockGold)
    if cost > 0 and rarityXp < cost then
        row.rerollItemButton:setTooltip(tr('You need %d Rarity XP and have %d. Buy more in the Store (Rarity) or kill Pale, Ashen, Obsidian and Lord of Death monsters.', cost, rarityXp))
    elseif lockGold > gold then
        row.rerollItemButton:setTooltip(tr('Keeping a bonus costs %s gold and you have %s.', formatGold(lockGold), formatGold(gold)))
    end
    -- one grade up: gold and Rarity XP, with a chance
    local up = entry.upgrade
    row.upgradeItemButton:setVisible(up ~= nil)
    row.upgradeCost:setVisible(up ~= nil)
    if up then
        row.upgradeItemButton:setText(tr('%s %d%%', up.label, up.chance))
        row.upgradeItemButton:setEnabled(gold >= up.gold and rarityXp >= up.xp)
        -- the price under the button, so it is seen before clicking
        row.upgradeCost:setText(tr('%s gold + %s XP', formatGold(up.gold), formatCost(up.xp)))
        row.upgradeCost:setColor((gold >= up.gold and rarityXp >= up.xp) and '#c9b88a' or '#c46a5a')
        row.upgradeItemButton:setTooltip(tr('Raise to %s: %s gold and %d Rarity XP, %d%% chance. On success the item rolls again at %s; on a failure it stays as it is and the price is spent.', up.label, formatGold(up.gold), up.xp, up.chance, up.label))
        -- off: say what is missing
        if rarityXp < up.xp then
            row.upgradeItemButton:setTooltip(tr('Raising to %s needs %d Rarity XP and you have %d.', up.label, up.xp, rarityXp))
        elseif gold < up.gold then
            row.upgradeItemButton:setTooltip(tr('Raising to %s costs %s gold and you have %s.', up.label, formatGold(up.gold), formatGold(gold)))
        end
    end
end

local lastItems

function fillItems(items)
    lastItems = items
    local list = window.itemsSection.itemsList
    list:destroyChildren()
    window.itemsSection.itemsEmpty:setVisible(#items == 0)
    for index, entry in ipairs(items) do
        local row = g_ui.createWidget(index % 2 == 0 and 'BonusItemRowEven' or 'BonusItemRow', list)
        local grade = GRADES[entry.rarity] or GRADES.uncommon
        row.frame:setImageClip(string.format('%d 0 %d %d', grade.frame * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE))
        local item = Item.create(entry.itemId, 1)
        if entry.shader and entry.shader ~= '' then
            item:setShader(entry.shader)
        end
        row.frame.item:setItem(item)
        if ItemsDatabase and ItemsDatabase.setFrameGems then
            ItemsDatabase.setFrameGems(row.frame, entry.tags or {})
        end
        row.name:setText(titleCase(entry.name or ''))
        row.name:setColor(grade.color)
        local info = tr(entry.slot or '') .. '  ' .. grade.label
        if (entry.level or 0) > 0 then
            info = info .. '  ' .. tr('level %d', entry.level)
        end
        if entry.finder then
            info = info .. '  ' .. tr('found by you')
        end
        row.info:setText(info)
        local count = 0
        local lockable = (entry.lockCost or 0) > 0
        -- a kept bonus the item no longer has (rerolled elsewhere) is dropped
        local kept = false
        for _, bonus in ipairs(entry.bonuses or {}) do
            kept = kept or bonus.key == locks[entry.slotId]
        end
        if not kept then
            locks[entry.slotId] = nil
        end
        local keptBonus
        for _, bonus in ipairs(entry.bonuses or {}) do
            count = count + 1
            local line = g_ui.createWidget('BonusLine', row.bonuses)
            line.text:setText(bonusText(bonus))
            -- near its top: the roulette's colour (from the server)
            if bonus.color and bonus.color ~= '' then
                line.text:setColor(bonus.color)
            end
            -- "Keep": this bonus stays, with its value, on the next reroll (gold)
            line.keep:setVisible(lockable)
            if not lockable then
                line.text:setMarginRight(-line.keep:getWidth())
            else
                local locked = locks[entry.slotId] == bonus.key
                line.keep:setOn(locked)
                line.keep:setText(locked and tr('Kept') or tr('Keep'))
                line.keep:setTooltip(locked and tr('Kept: the next reroll keeps this bonus with its value and rolls only the others. Click to let it go.')
                    or tr('Keep this bonus with its value on the next reroll: only the others are rolled again. %s gold, on top of the Rarity XP. One bonus per item.', formatGold(entry.lockCost)))
                -- the whole line lights up, so a kept bonus is never missed
                if locked then
                    keptBonus = bonus
                    line:setBackgroundColor('#e0c06024')
                    line:setBorderWidth(1)
                    line:setBorderColor('#e0c06070')
                end
                line.keep.onClick = function()
                    local name = titleCase(entry.name or '')
                    if locks[entry.slotId] == bonus.key then
                        locks[entry.slotId] = nil
                        window.status:setText(tr('%s is no longer kept: the next reroll of %s rolls every bonus again.', bonusText(bonus), name))
                        window.status:setColor('#ab9fc6')
                    else
                        locks[entry.slotId] = bonus.key
                        window.status:setText(tr('%s kept on %s: the next reroll keeps it with this value and rolls only the others, for %s gold on top of the Rarity XP.', bonusText(bonus), name, formatGold(entry.lockCost)))
                        window.status:setColor('#e0c060')
                    end
                    fillItems(lastItems or {})
                end
            end
        end
        -- under the bonuses: what keeping one does, or what is kept
        row.keepHint:setVisible(lockable)
        if lockable then
            if keptBonus then
                row.keepHint:setText(tr('The next Reroll keeps %s and rolls only the others (+%s gold).', bonusText(keptBonus), formatGold(entry.lockCost)))
                row.keepHint:setColor('#e0c060')
            else
                row.keepHint:setText(tr('Like a bonus? Press Keep on it: the next Reroll keeps it and rolls only the others (+%s gold).', formatGold(entry.lockCost)))
                row.keepHint:setColor('#8f84a8')
            end
        end
        local cost = entry.rerollCost or 0
        local lockKey = locks[entry.slotId]
        -- the price says what it is paid in: Rarity XP, and gold for a kept bonus
        row.rerollItemButton:setText(lockKey and tr('%s XP + %s gold', formatCost(cost), formatGold(entry.lockCost)) or tr('Reroll %s XP', formatCost(cost)))
        row.rerollItemButton:setIcon(lockKey and '/game_raritybonus/images/lock_on' or '/game_raritybonus/images/reroll')
        row.entry = entry
        setRerollState(row)
        row.rerollItemButton.onClick = function()
            local lines, keptText = {}, nil
            for _, bonus in ipairs(entry.bonuses or {}) do
                if bonus.key == lockKey then
                    keptText = bonusText(bonus)
                else
                    table.insert(lines, bonusText(bonus))
                end
            end
            local text
            if keptText then
                text = tr('Reroll %s for %d Rarity XP and %s gold?\n\nKept, with its value: %s\n\nLost:\n%s\n\nThe new ones can be better or worse, and there is no way back.', titleCase(entry.name or ''), cost, formatGold(entry.lockCost), keptText, table.concat(lines, '\n'))
            else
                text = tr('Reroll %s for %d Rarity XP?\n\nEvery bonus it has now is lost:\n%s\n\nThe new ones can be better or worse, and there is no way back.', titleCase(entry.name or ''), cost, table.concat(lines, '\n'))
            end
            confirm(tr('Reroll item'), text, function()
                send({ action = 'rerollItem', slot = entry.slotId, lock = lockKey })
            end)
        end
        row.upgradeItemButton.onClick = function()
            local up = entry.upgrade
            if not up then
                return
            end
            confirm(tr('Raise the grade'), tr('Raise %s to %s?\n\nPrice: %s gold and %d Rarity XP, paid even if it fails.\nChance: %d%%.\n\nOn success the item becomes %s and rolls its bonuses again at that grade. On a failure it stays exactly as it is.', titleCase(entry.name or ''), up.label, formatGold(up.gold), up.xp, up.chance, up.label), function()
                upgradeAsked = { entry = entry }
                send({ action = 'upgradeItem', slot = entry.slotId })
            end)
        end
        local linesHeight = count * 20
        row.bonuses:setHeight(linesHeight)
        local hintHeight = lockable and (3 + row.keepHint:getHeight()) or 0
        -- the upgrade's price line under the two buttons needs a little more
        row:setHeight(math.max(entry.upgrade and 60 or 48, 3 + 15 + 16 + 3 + linesHeight + hintHeight + 6))
    end
end

local function fillTotals(totals, items)
    local list = window.totalsSection.totalsList
    list:destroyChildren()
    for index, entry in ipairs(totals) do
        local row = g_ui.createWidget(index % 2 == 0 and 'BonusTotalRowEven' or 'BonusTotalRow', list)
        -- bonus names stay as the items and the wiki write them
        row.label:setText(entry.label)
        local total = '+' .. number(entry.total) .. (entry.unit or '')
        if entry.perItem then
            total = total .. ' ' .. tr('(on each item)')
        elseif entry.cap then
            total = total .. ' / ' .. number(entry.cap) .. (entry.unit or '')
        end
        row.total:setText(total)
        row.total:setColor(entry.capped and '#e2a443' or '#7fd35a')
        if entry.capped then
            row.total:setTooltip(tr('This bonus is at its limit: more of it on other items adds nothing.'))
        end
        local lines = {}
        for _, source in ipairs(entry.sources or {}) do
            table.insert(lines, string.format('  %s: +%s%s', titleCase(source.name or ''), number(source.value), entry.unit or ''))
        end
        if entry.combined then
            table.insert(lines, '  ' .. tr('combined, not added up'))
        end
        row.sources:setText(table.concat(lines, '\n'))
        row.sources:setHeight(#lines * LINE)
        row:setHeight(3 + 14 + 2 + #lines * LINE + 5)
    end
end

function showXpBadge(xp)
    if modules.game_brevespanel and modules.game_brevespanel.setFeatureState then
        -- the row sits under the Rarity title: a short name leaves room for the badge
        modules.game_brevespanel.setFeatureLabel('bonus', tr('Roulette'), '#dfdfdf')
        modules.game_brevespanel.setFeatureState('bonus', tr('%d XP', xp), '#e0c060')
    end
end

-- a new balance (Store pack, tier kill) while the window is open: the label
-- and the Reroll buttons follow it without asking the server again
local function updateXp()
    window.xpLabel:setText(tr('Rarity XP: %d', rarityXp))
    for _, row in ipairs(window.itemsSection.itemsList:getChildren()) do
        if row.entry then
            setRerollState(row)
        end
    end
end

local applyBonuses
local rouletteTakes
local updateRouletteXp

-- ---------------------------------------------------------------------------
-- Hunting incense (server: rarity/incense.lua): a row of the Mythos bar. It
-- offers "Light" while today's incense is unused, counts the minutes while it
-- burns, and says "tomorrow" once used.
-- ---------------------------------------------------------------------------

local incenseButton
local incense -- last status from the server
local incenseEvent

local function incenseLeft()
    if not incense then
        return 0
    end
    return math.max(0, (incense.left or 0) - (os.time() - (incense.receivedAt or os.time())))
end

local function updateIncense()
    local panel = modules.game_brevespanel
    if incenseEvent then
        removeEvent(incenseEvent)
        incenseEvent = nil
    end
    if not panel or not panel.setFeatureState or not incense then
        return
    end
    local left = incenseLeft()
    local tip = tr('Hunting incense: for %d minutes, +%d%% chance of rare monsters and +%d%% Rarity XP. One a day, %s gold (your level x 2,000).', incense.minutes or 60, incense.rareMonster or 10, incense.rarityXp or 5, formatGold(incense.price))
    if left > 0 then
        panel.setFeatureAction('incense', nil)
        panel.setFeatureState('incense', tr('%d min', math.ceil(left / 60)), '#9be36b')
        if incenseButton then
            incenseButton:setTooltip(tr('Hunting incense burning: %d minutes left.', math.ceil(left / 60)))
        end
        incenseEvent = scheduleEvent(updateIncense, 20000)
    elseif incense.usedToday then
        panel.setFeatureAction('incense', nil)
        panel.setFeatureState('incense', tr('tomorrow'), '#8d8270')
        if incenseButton then
            incenseButton:setTooltip(tip .. ' ' .. tr('You already used today\'s.'))
        end
    else
        panel.setFeatureState('incense', nil)
        panel.setFeatureAction('incense', tr('Light'), tip, lightIncense, true)
        if incenseButton then
            incenseButton:setTooltip(tip)
        end
    end
end

function lightIncense()
    if not incense or incenseLeft() > 0 or incense.usedToday then
        return
    end
    confirm(tr('Hunting incense'), tr('Light the hunting incense for %s gold?\n\nFor %d minutes: +%d%% chance of rare monsters and +%d%% Rarity XP.\nOne a day. The gold comes from your backpack, then your bank.', formatGold(incense.price), incense.minutes or 60, incense.rareMonster or 10, incense.rarityXp or 5), function()
        send({ action = 'incense' })
    end)
end

-- A rare monster rising from its corpse (art and motion: the design kit
-- "Renascimento, quatro presencas"). Each tier is a material coming alive: a
-- veil of mist (Pale), a flower of ash (Ashen), a crown of glass (Obsidian),
-- an eclipse (Lord of Death). Three textures follow the corpse's tile: the
-- floor under the body and every creature, the air around it, and the burst
-- when the monster stands up. The living monster's aura is an attached effect
-- the server puts on it (game_attachedeffects, ids 21 to 24). The server sends
-- the tier and the time left (scripts/rarity/revive.lua).
local REVIVE_FOLDERS = { pale = 'pale', ashen = 'ashen', obsidian = 'obsidian', deathlord = 'lord-of-death' }
local REVIVE_LAYERS = { chao = 1, ar = 2, eclosao = 3 }
local REVIVE_EFFECT_BASE = 3000
local DESIGN_REVIVE = 7       -- the curves are drawn for a 7 s wait...
local DESIGN_SETTLE = 0.9     -- ...and 0.9 s of arrival
-- sizes (side of the texture, in tiles), peak opacities, how far the air lifts
-- (the kit's sizes; the game draws the whole composition REVIVE_SCALE times
-- bigger around the corpse, and stronger than the kit so it reads from across
-- the screen). `light`: the colour (8-bit, as the map's lights) the rising
-- body glows with, which shows in the dark of a cave.
local REVIVE_SCALE = 2.4
local REVIVE_MOTION = {
    pale = { tier = 1, g = 1.9, a = 2.15, r = 2.45, go = .64, ao = .82, ro = .74, lift = .20, light = 179 },
    ashen = { tier = 2, g = 2.2, a = 2.45, r = 2.7, go = .76, ao = .88, ro = .86, lift = .16, light = 199 },
    obsidian = { tier = 3, g = 2.45, a = 2.8, r = 3.05, go = .80, ao = .94, ro = .92, lift = .20, light = 125 },
    deathlord = { tier = 4, g = 2.85, a = 3.15, r = 3.35, go = .88, ao = .97, ro = .90, lift = .16, light = 152 },
}
local REVIVE_LIGHT = 7 -- the glow's strength at its brightest (map lights go up to about 10)
-- the corpse's heart: a double beat (lub-dub) that quickens from BEAT_FROM
-- to BEAT_TO beats a second as the monster gets ready to stand up; on each
-- beat the floor flares and swells and the air brightens
local BEAT_FROM, BEAT_TO = 0.8, 2.0
local BEAT_FLOOR, BEAT_SWELL, BEAT_AIR = 0.55, 0.10, 0.30
local revivals = {}

local function clamp01(x)
    return math.max(0, math.min(1, x))
end

local function smooth(x)
    x = clamp01(x)
    return x * x * (3 - 2 * x)
end

local function reviveEffectId(tierKey, layer)
    return REVIVE_EFFECT_BASE + REVIVE_MOTION[tierKey].tier * 10 + REVIVE_LAYERS[layer]
end

-- the floor goes in the ground-border pass, under corpses and every creature;
-- the air and the burst over them
local function registerReviveTextures()
    for tierKey, folder in pairs(REVIVE_FOLDERS) do
        for layer in pairs(REVIVE_LAYERS) do
            local id = reviveEffectId(tierKey, layer)
            local path = string.format('/game_raritybonus/images/revive/%s/revive_%s_%s', folder, folder, layer)
            -- a module reload finds them still registered
            g_attachedEffects.remove(id)
            local effect = g_attachedEffects.registerByImage(id, 'Revive ' .. folder .. ' ' .. layer, path, true)
            if effect then
                effect:setPermanent(true)
                effect:setOnTop(layer ~= 'chao')
                effect:setDrawOrder(layer == 'chao' and 1 or 3)
            end
        end
    end
end

local function unregisterReviveTextures()
    for tierKey in pairs(REVIVE_FOLDERS) do
        for layer in pairs(REVIVE_LAYERS) do
            g_attachedEffects.remove(reviveEffectId(tierKey, layer))
        end
    end
end

-- 0..1: how much of a heartbeat is in the corpse at design time t
local function heartbeat(t)
    local beats = BEAT_FROM * t + (BEAT_TO - BEAT_FROM) * t * t / (2 * DESIGN_REVIVE)
    local f = beats - math.floor(beats)
    local lub, dub = (f - .08) / .09, (f - .34) / .10
    return math.min(1, math.exp(-lub * lub) + .6 * math.exp(-dub * dub))
end

-- The designer's curves: which layers show at design time t (seconds, 0 = the
-- death, 7 = the monster stands up), how big, how opaque, how far up, and
-- the glow of the air.
local function reviveLayers(t, tierKey)
    local c = REVIVE_MOTION[tierKey]
    local out = {}
    local function add(layer, size, opacity, lift)
        out[layer] = { size = size, opacity = clamp01(opacity), lift = lift or 0 }
    end
    if t < DESIGN_REVIVE then
        local p = clamp01(t / DESIGN_REVIVE)
        local entry = smooth(t / .85)
        local tension = smooth((t - 5.5) / 1.5)
        local breath = math.sin(2 * math.pi * (.35 * t + .4 * t * t / 14))
        local beat = heartbeat(t) * entry
        add('chao', c.g * (.66 + .34 * smooth(p)) * (1 + BEAT_SWELL * beat), c.go * entry * (.60 + .40 * p) * (1 + .035 * breath) * (1 + BEAT_FLOOR * beat))
        local gather = smooth((t - .55) / 5.2)
        local scale = .72 + .28 * gather
        local lift = c.lift * (.3 + .7 * gather)
        if tierKey == 'pale' then
            scale = scale * (1 + .035 * breath)
            lift = lift + .035 * math.sin(t * 1.3)
        elseif tierKey == 'ashen' then
            scale = scale * (1 + .02 * math.sin(t * 1.6))
            lift = lift + .045 * gather
        elseif tierKey == 'obsidian' then
            scale = scale * (1 - .10 * tension)
            lift = lift + .025 * math.sin(t * 1.1)
        else
            scale = scale * (1 - .06 * tension)
            lift = lift + .06 * tension
        end
        add('ar', c.a * scale, c.ao * entry * gather * (.68 + .32 * tension) * (1 + BEAT_AIR * beat), lift)
        out.ar.light = REVIVE_LIGHT * (.25 + .45 * p + .3 * beat) * entry
    else
        local q = clamp01((t - DESIGN_REVIVE) / DESIGN_SETTLE)
        local exit = 1 - smooth(q)
        local eclipse = tierKey == 'deathlord'
        -- Pale, Ashen and Obsidian open out; the Lord's shadow implodes into it
        add('chao', c.g * (eclipse and (1 - .58 * smooth(q)) or (1 + .08 * q)), c.go * exit)
        add('ar', c.a * (1 - .1 * q), c.ao * exit, c.lift + .08 * q)
        add('eclosao', c.r * (eclipse and (1 - .7 * smooth(q)) or (.74 + .26 * smooth(q))), c.ro * math.sin(math.pi * q), eclipse and 0 or .18 * q)
        out.ar.light = REVIVE_LIGHT * (1 + .3 * math.sin(math.pi * q)) * exit
    end
    return out
end

-- the server's real delay maps onto the 7 s of the curves; after the rise the
-- clock runs in real seconds
local function designTime(elapsed, delay)
    if elapsed < delay then
        return elapsed / delay * DESIGN_REVIVE
    end
    return DESIGN_REVIVE + (elapsed - delay) / 1000
end

-- a corpse that is rising right now (lootfind.lua leaves it its floor)
function reviveActiveAt(key)
    return revivals[key] ~= nil
end

local function dropRevive(key)
    local entry = revivals[key]
    revivals[key] = nil
    if not entry then
        return
    end
    removeEvent(entry.event)
    local tile = g_map.getTile(entry.pos)
    for _, effect in pairs(entry.effects) do
        if tile then
            tile:detachEffect(effect)
        end
    end
end

-- a texture of `size` tiles centred on the tile, `lift` tiles up (an attached
-- effect is drawn at the tile's corner minus its offset, in 32 px units)
local function placeLayer(entry, tile, layer, state)
    local effect = entry.effects[layer]
    if not effect then
        -- getById hands out a copy of the registered effect
        effect = g_attachedEffects.getById(reviveEffectId(entry.tier, layer))
        if not effect then
            return
        end
        entry.effects[layer] = effect
    end
    local side = math.max(1, math.floor(state.size * REVIVE_SCALE * 32 + 0.5))
    local half = math.floor(side / 2) - 16
    effect:setSize({ width = side, height = side })
    effect:setOffset(half + entry.shift, half + entry.shift + math.floor(state.lift * REVIVE_SCALE * 32 + 0.5))
    effect:setOpacity(state.opacity)
    if state.light then
        effect:setLight({ intensity = math.max(0, math.floor(state.light + 0.5)), color = REVIVE_MOTION[entry.tier].light })
    end
    -- the tile is rebuilt when it leaves the screen and comes back
    if not tile:getAttachedEffectById(effect:getId()) then
        tile:attachEffect(effect)
    end
end

local function showRevive(data)
    if not data.x or not tonumber(data.ms) or not REVIVE_MOTION[data.tier] then
        return
    end
    local pos = { x = data.x, y = data.y, z = data.z }
    local key = pos.x .. ':' .. pos.y .. ':' .. pos.z
    dropRevive(key)
    local entry = {
        pos = pos,
        tier = data.tier,
        delay = math.max(1, tonumber(data.ms)),
        starts = g_clock.millis(),
        effects = {},
        shift = 0,
    }
    -- a 2x2 corpse (a dragon's) is drawn up and left of its tile: centre on it
    local tile = g_map.getTile(pos)
    local corpse = tile and tile:getTopUseThing()
    if corpse and corpse:isItem() then
        local thingType = g_things.getThingType(corpse:getId(), ThingCategoryItem)
        if thingType then
            entry.shift = (math.max(1, math.min(2, math.max(thingType:getWidth(), thingType:getHeight()))) - 1) * 16
        end
    end
    revivals[key] = entry

    local function frame()
        if revivals[key] ~= entry then
            return
        end
        local t = designTime(g_clock.millis() - entry.starts, entry.delay)
        if t >= DESIGN_REVIVE + DESIGN_SETTLE then
            dropRevive(key)
            return
        end
        local tile = g_map.getTile(pos)
        if tile then
            local layers = reviveLayers(t, entry.tier)
            for layer in pairs(REVIVE_LAYERS) do
                local state = layers[layer]
                if state and state.opacity > 0.005 then
                    placeLayer(entry, tile, layer, state)
                elseif entry.effects[layer] then
                    entry.effects[layer]:setOpacity(0)
                end
            end
        end
        entry.event = scheduleEvent(frame, 30)
    end
    frame()
end

local function onOpcode(protocol, opcode, data)
    if type(data) == 'table' and data.action == 'drop' then
        showLootDrop(data)
        return
    end
    if type(data) == 'table' and data.action == 'dropgone' then
        removeLootDrop(data)
        return
    end
    if type(data) == 'table' and data.action == 'dropmove' then
        moveLootDrop(data)
        return
    end
    if type(data) == 'table' and data.action == 'find' then
        showLootCard(data)
        return
    end
    if type(data) == 'table' and data.action == 'banner' then
        showLootBanner(data)
        return
    end
    if type(data) == 'table' and data.action == 'revive' then
        showRevive(data)
        return
    end
    if type(data) == 'table' and data.action == 'incense' then
        incense = data
        incense.receivedAt = os.time()
        updateIncense()
        return
    end
    -- the balance, after every change: shown on the Rarity Bonuses row; past
    -- a multiple of 50 a notice offers the window without opening it
    if type(data) == 'table' and data.action == 'xp' then
        rarityXp = tonumber(data.xp) or rarityXp
        showXpBadge(rarityXp)
        if window and window:isVisible() then
            updateXp()
        end
        updateRouletteXp()
        if data.ready and not (window and window:isVisible()) and modules.game_brevespanel then
            modules.game_brevespanel.notify('bonus',
                tr('You have %d Rarity XP! Use it to reroll your rarity items.', tonumber(data.xp) or 0),
                tr('Open'))
        end
        return
    end
    if type(data) ~= 'table' or data.action ~= 'bonuses' or not window then
        return
    end
    -- a reroll plays the roulette first; the list below only shows the new
    -- bonuses once the reels stop
    if rouletteTakes(data) then
        return
    end
    applyBonuses(data)
end

applyBonuses = function(data)
    rarityXp = tonumber(data.rarityXp) or 0
    gold = tonumber(data.gold) or gold
    showXpBadge(rarityXp)
    window.xpLabel:setText(tr('Rarity XP: %d', rarityXp))
    window.xpLabel:setTooltip(tr('Earned by killing Pale, Ashen, Obsidian and Lord of Death monsters: the stronger the monster and its tier, the more you get. Spend it here to reroll the items you wear; items of a higher grade or level cost more.'))
    -- automatic refreshes (equipment changed) carry no message: keep the
    -- answer to the last reroll on screen
    local message = data.message
    local result = data.result
    if type(result) == 'table' then
        if result.code == 'rerolled' then
            message = tr('%s rerolled: %s. (-%d Rarity XP)', titleCase(result.name or ''), table.concat(result.bonuses or {}, ', '), tonumber(result.cost) or 0)
            if result.perfect then
                message = message .. ' ' .. tr('Perfect roll!')
            end
        elseif result.code == 'xp' then
            message = tr('You need %d Rarity XP and have %d. Kill Pale, Ashen, Obsidian and Lord of Death monsters to earn more.', tonumber(result.cost) or 0, tonumber(result.balance) or 0)
        elseif result.code == 'gone' then
            message = tr('That item is no longer equipped.')
        elseif result.code == 'gold' then
            message = tr('You need %s gold in your backpack and bank.', formatGold(result.gold))
        elseif result.code == 'cannot' or result.code == 'busy' then
            -- fixed sentences from the server, translated here
            message = tr(data.message or '')
        elseif result.code == 'upgradeFailed' then
            message = tr('The upgrade to %s failed (%d%% chance): %s stays as it was. (-%s gold, -%d Rarity XP)', result.to or '', tonumber(result.chance) or 0, titleCase(result.name or ''), formatGold(result.gold), tonumber(result.xp) or 0)
        end
        if result.code == 'rerolled' and result.upgrade then
            message = tr('Upgrade! %s: %s. (-%s gold, -%d Rarity XP)', titleCase(result.name or ''), table.concat(result.bonuses or {}, ', '), formatGold(result.gold), tonumber(result.cost) or 0)
        elseif result.code == 'rerolled' and (tonumber(result.gold) or 0) > 0 then
            message = message .. ' ' .. tr('(-%s gold to keep a bonus)', formatGold(result.gold))
        end
    end
    if message then
        window.status:setText(message)
        window.status:setColor(data.ok == false and '#ff6464' or '#7fd35a')
    end
    fillItems(data.items or {})
    fillTotals(data.totals or {}, data.items or {})
    local note = tr('Each item shows its own bonuses; on the right, the total you get of each one and the items it comes from.') .. ' ' ..
        tr('A percent bonus on several items is combined: each one works on what the others leave. Orange: the bonus is at its limit.')
    if (data.finderPercent or 0) > 0 then
        note = note .. ' ' .. tr('Items you found yourself are %d%% stronger on you; the numbers here already include that.', data.finderPercent)
    end
    window.note:setText(note)
    if not window:isVisible() then
        window:show()
        window:raise()
        window:focus()
        if featureButton then
            featureButton:setOn(true)
        end
    end
end


-- ---------------------------------------------------------------------------
-- Rarity Roulette, opened like a CS case: one strip per bonus the grade
-- allows. Each strip is a long row of cards (bonuses this item could roll,
-- painted in their quality colour, so the player sees what was possible)
-- that races under a gold marker, slows down and stops on the server's
-- result. Strips stop one by one, each a bit later. Strips the item didn't
-- get stop on an empty card (the number of bonuses is rolled too).
-- The server rolls at once; this is only the show.
-- ---------------------------------------------------------------------------

local roulette
local spin -- { result, rows, current, count, assumed, bump, finished, waiting, onDone, pending, event }
-- raising the grade on the reel (below): { entry, data, success, chance,
-- from, to, row, line, startsAt, event, finished, waiting, next, pending }
local upgrade
local setUpgradeAgain
-- One reel, like a slot machine: the bonuses roll from the bottom to the
-- top, each one centred and on its own line, so it can be read as it goes
-- by. The slots roll one at a time; the result lands on the middle line and
-- goes to the list below the reel.
local LINE = 34 -- height of a reel line
local WIN_INDEX = 12 -- the result is the 12th line: 10 lines go by
local LINES_AFTER = 2 -- lines under the result, so the reel never runs dry
local SPIN_TIME = 4600 -- ms per slot
local SPEED_UP = 0.18 -- share of the spin spent speeding up
local PAUSE = 900 -- ms between one slot stopping and the next starting
local BUMP_TIME = 700 -- ms the bonuses take to grow at an empty slot
local FADE = 0.3 -- how much the reel dims at full speed
local ACTIVE_COLOR = '#e0c060' -- the slot rolling now
local REEL_TOP = 2 -- the strip's margin when its first line is at the top
-- ms between reel updates: under one frame even at 165 Hz, so every frame
-- shows a fresh position (16 ms skipped or doubled frames, a stutter)
local FRAME_MS = 6

local QUALITY_COLORS = {
    { 0.9, '#e2a443' }, -- near the top
    { 0.7, '#a679e6' },
    { 0.45, '#4f8fe8' },
    { 0.2, '#63c08a' },
    { 0, '#b8b8b8' },
}

local function qualityColor(quality, perfect)
    if perfect then
        return '#ffe7a6'
    end
    for _, entry in ipairs(QUALITY_COLORS) do
        if (quality or 0) >= entry[1] then
            return entry[2]
        end
    end
    return '#b8b8b8'
end

-- a bonus the item could have rolled: mostly low and middle values, now and
-- then one near the top, like the odds really are
local function randomLine(pool)
    if not pool or #pool == 0 then
        return '???', '#b8b8b8'
    end
    local entry = pool[math.random(#pool)]
    local min, max = tonumber(entry.min) or 1, tonumber(entry.max) or 1
    local quality = math.random() ^ 1.7
    local value = min + math.floor(quality * math.max(0, max - min) + 0.5)
    return string.format('+%d%s %s', value, entry.unit or '', entry.label or ''), qualityColor(quality)
end

local function rouletteVisible()
    return roulette and roulette:isVisible()
end

local function setAgainButton()
    if upgrade then
        setUpgradeAgain()
        return
    end
    if not spin or not spin.result then
        return
    end
    -- an upgrade is not spun again: the item is rerolled from the list
    roulette.againButton:setVisible(not spin.result.upgrade)
    local cost = tonumber(spin.result.nextCost or spin.result.cost) or 0
    local lockGold = spin.result.lock and (tonumber(spin.result.nextGold) or 0) or 0
    roulette.againButton:setText(lockGold > 0 and tr('Spin again (%d XP + %s gold)', cost, formatGold(lockGold)) or tr('Spin again (%d XP)', cost))
    roulette.againButton:setEnabled(spin.finished and not spin.waiting and rarityXp >= cost and gold >= lockGold)
    -- the balance only once the reel stops: it is updated with the result
    roulette.xp:setText(spin.finished and tr('Rarity XP: %d', rarityXp) or '')
end

-- a new balance while the roulette is open: "spin again" follows it
updateRouletteXp = function()
    if rouletteVisible() then
        setAgainButton()
    end
end

-- Where the reel is (0 to 1) and how fast it goes (1 = average speed) at
-- time p of a spin: speed rises in a straight line for SPEED_UP of the time,
-- then falls away as (1 - t)^2, a long slow end.
local CURVE_AREA = SPEED_UP / 2 + (1 - SPEED_UP) / 3
local function spinCurve(p)
    if p <= 0 then
        return 0, 0
    elseif p >= 1 then
        return 1, 0
    elseif p < SPEED_UP then
        return (p * p / (2 * SPEED_UP)) / CURVE_AREA, (p / SPEED_UP) / CURVE_AREA
    end
    local rest = (1 - p) / (1 - SPEED_UP)
    local position = SPEED_UP / 2 + (1 - SPEED_UP) / 3 * (1 - rest ^ 3)
    return position / CURVE_AREA, rest * rest / CURVE_AREA
end

-- "12%", "2.5%", "0.35%": enough digits to tell rare rolls apart
local function formatChance(chance)
    local percent = chance * 100
    if percent >= 10 then
        return string.format('%d%%', math.floor(percent + 0.5))
    elseif percent >= 1 then
        return string.format('%.1f%%', percent)
    elseif percent >= 0.01 then
        return string.format('%.2f%%', percent)
    end
    return '<0.01%'
end

-- once every slot stopped: each bonus's range on the item and the odds of
-- rolling its value or better (sent by the server with the roll)
local function showOdds()
    for _, row in ipairs(spin.rows or {}) do
        local entry = row.entry
        local widget = row.result
        if entry and entry.min and entry.max and entry.chance and widget and not widget:isDestroyed() then
            widget.odds:setText(tr('%d to %d, %s', entry.min, entry.max, entry.perfect and tr('perfect') or tr('top %s', formatChance(entry.chance))))
            widget.odds:setColor(qualityColor(entry.quality, entry.perfect))
        end
    end
end

local function finishSpin()
    if not spin or spin.finished then
        return
    end
    spin.finished = true
    if spin.event then
        removeEvent(spin.event)
        spin.event = nil
    end
    local result = spin.result or {}
    local rolled = result.rolled or {}
    local best = 0
    for _, entry in ipairs(rolled) do
        best = math.max(best, entry.perfect and 2 or (entry.quality or 0))
    end
    local summary
    if result.perfect then
        summary = tr('PERFECT ROLL!')
    elseif best >= 0.9 then
        summary = tr('Jackpot! A bonus near the top.')
    elseif best >= 0.7 then
        summary = tr('Great roll!')
    elseif #rolled == 1 then
        summary = tr('Just one bonus, all the power in it.')
    else
        summary = tr('%d bonuses.', #rolled)
    end
    roulette.status:setText(summary)
    roulette.status:setColor(result.perfect and '#ffe7a6' or qualityColor(best))
    showOdds()
    roulette.closeButton:setText(tr('Close'))
    if spin.onDone then
        local done = spin.onDone
        spin.onDone = nil
        done()
    end
    if spin.pending then
        local pending = spin.pending
        spin.pending = nil
        applyBonuses(pending)
    end
    setAgainButton()
end

-- The value of a rolled bonus while the item may still have `assumed`
-- bonuses: the server sends steps for its real count (steps[1]) and every
-- count above it, since the fewer bonuses an item has, the stronger each one.
-- Returns the step and whether it is the real one.
local function stepFor(entry, assumed)
    local steps = entry.steps
    if type(steps) ~= 'table' or #steps == 0 then
        return nil
    end
    local index = math.max(1, math.min(#steps, assumed - spin.count + 1))
    return steps[index], index == 1
end

local function bonusText(entry, value, final)
    local text = string.format('+%d%s %s', value, entry.unit or '', entry.label or '')
    if final and entry.perfect then
        text = text .. '  ' .. tr('PERFECT')
    end
    return text
end

-- text and colour of a slot's bonus with `assumed` bonuses; nil text for an
-- empty slot. Also remembers the value shown.
local function slotLook(row, assumed)
    local entry = row.entry
    if not entry then
        return nil
    end
    local step, final = stepFor(entry, assumed)
    if not step then
        -- a server without steps: the final value straight away
        row.shown = nil
        local text = entry.perfect and (entry.text .. '  ' .. tr('PERFECT')) or entry.text
        return text, qualityColor(entry.quality, entry.perfect)
    end
    row.shown = step.value
    return bonusText(entry, step.value, final), qualityColor(step.quality, final and entry.perfect)
end

local function paintLine(line, text, color)
    line.text:setText(text or tr('no bonus'))
    line.text:setColor(text and color or '#5a5a5a')
end

-- a slot's line in the list under the reel
local function paintResult(row, text, color)
    local widget = row.result
    widget:setOpacity(1)
    widget.text:setText(text or tr('no bonus'))
    widget.text:setColor(text and color or '#5a5a5a')
    widget:setBorderColor(text and color or '#2a2a2a')
    widget:setBackgroundColor(text and (color .. '22') or '#0b0b0bee')
    -- the locked bonus stays gold, whatever repaints it (skip, grow)
    if row.kept then
        widget:setBorderColor('#e0c060')
        widget:setBackgroundColor('#e0c06026')
    end
end

-- an empty slot: one bonus fewer, so the bonuses already out grow to their
-- value with one bonus fewer on the item, counting up
local function growRevealed()
    local from = {}
    for _, row in ipairs(spin.rows) do
        if row.stopped and row.entry and row.shown then
            from[row] = row.shown
        end
    end
    spin.assumed = spin.assumed - 1
    if not next(from) then
        return
    end
    local started = g_clock.millis()
    local token = {}
    spin.bump = token
    local function tick()
        if not spin or spin.bump ~= token or not rouletteVisible() then
            return
        end
        local p = math.min(1, (g_clock.millis() - started) / BUMP_TIME)
        for row, old in pairs(from) do
            local target, final = stepFor(row.entry, spin.assumed)
            if target then
                local value = math.floor(old + (target.value - old) * p + 0.5)
                local done = p >= 1
                paintResult(row, bonusText(row.entry, value, final and done), qualityColor(target.quality, final and done and row.entry.perfect))
                if done then
                    row.shown = target.value
                end
            end
        end
        if p < 1 then
            scheduleEvent(tick, 30)
        end
    end
    tick()
end

-- fills the reel for a slot: random bonuses, the result on line WIN_INDEX
local function loadReel(row)
    local strip = roulette.reel.strip
    strip:destroyChildren()
    local total = #spin.rows
    for i = 1, WIN_INDEX + LINES_AFTER do
        local line = g_ui.createWidget('RouletteLine', strip)
        if i == WIN_INDEX then
            row.line = line
            paintLine(line, slotLook(row, spin.assumed))
        elseif total > 1 and math.random() < 0.1 then
            -- empty lines: the number of bonuses is rolled too
            paintLine(line, nil)
        else
            paintLine(line, randomLine(spin.result.pool))
        end
    end
    strip:setHeight((WIN_INDEX + LINES_AFTER) * LINE)
    strip:setMarginTop(REEL_TOP)
    strip:setOpacity(1)
end

local function stopRow(row)
    if row.stopped then
        return
    end
    row.stopped = true
    roulette.reel.strip:setMarginTop(REEL_TOP - (WIN_INDEX - 2) * LINE)
    roulette.reel.strip:setOpacity(1)
    row.result:setBorderWidth(1)
    local text, color = slotLook(row, spin.assumed)
    paintResult(row, text, color)
    if row.line and not row.line:isDestroyed() then
        row.line:setBackgroundColor(text and (color .. '44') or '#00000000')
    end
    if text then
        return
    end
    local before = false
    for _, other in ipairs(spin.rows) do
        if other.stopped and other.entry then
            before = true
        end
    end
    growRevealed()
    roulette.status:setText(before and tr('No bonus: the bonuses above get stronger!') or tr('No bonus: the next bonuses will be stronger.'))
    roulette.status:setColor('#ffb84a')
end

-- one slot at a time: its reel rolls, the next waits its turn
local function animate()
    if not spin or spin.finished or not rouletteVisible() then
        return
    end
    local now = g_clock.millis()
    local row = spin.rows[spin.current]
    if row and now >= row.startsAt then
        if not row.active then
            row.active = true
            if spin.current > 1 then
                loadReel(row)
            end
            row.result:setOpacity(1)
            row.result:setBorderWidth(2)
            row.result:setBorderColor(ACTIVE_COLOR)
            row.result.text:setText('...')
            row.result.text:setColor(ACTIVE_COLOR)
            roulette.status:setText(tr('Bonus %d of %d', spin.current, #spin.rows))
            roulette.status:setColor(ACTIVE_COLOR)
        end
        local p = math.min(1, (now - row.startsAt) / SPIN_TIME)
        local position, speed = spinCurve(p)
        local strip = roulette.reel.strip
        strip:setMarginTop(REEL_TOP - math.floor((WIN_INDEX - 2) * LINE * position))
        -- dimmer while it runs fast, full contrast as it slows to a stop
        local peak = 1 / CURVE_AREA
        strip:setOpacity(1 - FADE * math.max(0, math.min(1, (speed - 0.6) / (peak - 0.6))))
        if p >= 1 then
            stopRow(row)
            spin.current = spin.current + 1
            local nextRow = spin.rows[spin.current]
            if nextRow then
                nextRow.startsAt = now + PAUSE
            end
        end
    end
    if spin.rows[spin.current] then
        spin.event = scheduleEvent(animate, FRAME_MS)
    elseif row and not row.entry then
        -- the last slot was empty: let the bonuses finish growing first
        spin.event = scheduleEvent(finishSpin, BUMP_TIME + 300)
    else
        spin.event = nil
        finishSpin()
    end
end

-- skip: every slot shows its result, at the real values
local function skipSpin()
    spin.bump = nil
    spin.assumed = spin.count
    for i, row in ipairs(spin.rows) do
        row.stopped = true
        row.result:setBorderWidth(1)
        paintResult(row, slotLook(row, spin.count))
        if i == spin.current and row.line and not row.line:isDestroyed() then
            roulette.reel.strip:setMarginTop(REEL_TOP - (WIN_INDEX - 2) * LINE)
            roulette.reel.strip:setOpacity(1)
            paintLine(row.line, slotLook(row, spin.count))
        end
    end
    finishSpin()
end

-- one line per bonus slot under the reel, and the first slot's reel
local function startStrips(result)
    roulette.results:destroyChildren()
    spin.rows = {}
    local rolled = result.rolled or {}
    local total = math.max(1, result.maxBonuses or 0, #rolled)
    spin.count = math.max(1, #rolled)
    spin.assumed = total
    spin.bump = nil
    -- the empty slots fall anywhere among the bonuses; a kept bonus is the
    -- first line and doesn't spin
    local slots, kept = {}, nil
    for _, entry in ipairs(rolled) do
        if entry.locked then
            kept = entry
        else
            slots[#slots + 1] = entry
        end
    end
    local free = total - (kept and 1 or 0)
    for i = #slots + 1, free do
        slots[i] = false
    end
    for i = free, 2, -1 do
        local j = math.random(i)
        slots[i], slots[j] = slots[j], slots[i]
    end
    if kept then
        table.insert(slots, 1, kept)
    end
    for i = 1, total do
        local widget = g_ui.createWidget('RouletteResult', roulette.results)
        widget.slot:setText(tr('Bonus %d', i))
        widget.text:setText('?')
        -- waiting: so the eye stays on the reel
        widget:setOpacity(0.35)
        spin.rows[i] = { result = widget, entry = slots[i] or nil }
    end
    roulette.results:setHeight(total * 29)
    spin.current = 1
    if kept then
        local row = spin.rows[1]
        row.stopped = true
        row.result.slot:setText(tr('Kept'))
        row.result.slot:setMarginLeft(24)
        row.result.slot:setColor('#f0cf6a')
        row.result.lock:show()
        row.kept = true
        paintResult(row, kept.text, qualityColor(kept.quality, kept.perfect))
        row.result:setBorderWidth(1)
        spin.current = 2
    end
    loadReel(spin.rows[spin.current])
    spin.rows[spin.current].startsAt = g_clock.millis() + 300
    spin.finished = false
    roulette.status:setText(tr('Spinning...'))
    roulette.status:setColor('#e0c060')
    roulette.closeButton:setText(tr('Skip'))
    setAgainButton()
    if spin.event then
        removeEvent(spin.event)
    end
    spin.event = scheduleEvent(animate, FRAME_MS)
end

local function showRoulette(result, onDone)
    if not roulette then
        roulette = g_ui.displayUI('roulette')
    end
    local grade = GRADES[result.rarity] or GRADES.uncommon
    roulette.frame:setImageClip(string.format('%d 0 %d %d', grade.frame * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE))
    local item = Item.create(result.itemId or 0, 1)
    if result.shader and result.shader ~= '' then
        item:setShader(result.shader)
    end
    roulette.frame.item:setItem(item)
    roulette.name:setText(titleCase(result.name or ''))
    roulette.name:setColor(grade.color)
    local subtitle = tr('%s  up to %d bonuses  -%d Rarity XP', grade.label, result.maxBonuses or 0, tonumber(result.cost) or 0)
    if (tonumber(result.gold) or 0) > 0 then
        subtitle = subtitle .. '  ' .. (result.lock and tr('-%s gold (kept bonus)', formatGold(result.gold)) or tr('-%s gold', formatGold(result.gold)))
    end
    if result.upgrade then
        subtitle = tr('Upgrade to %s!', grade.label) .. '  ' .. subtitle
    end
    roulette.subtitle:setText(subtitle)
    if upgrade then
        if upgrade.event then
            removeEvent(upgrade.event)
        end
        upgrade = nil
    end
    roulette:setText(tr('Rarity Roulette'))
    roulette:show()
    roulette:raise()
    roulette:focus()
    spin = spin or {}
    spin.result = result
    spin.onDone = onDone
    spin.waiting = false
    -- a refresh kept from before this reroll is older than its answer
    spin.pending = nil
    -- the strips are measured against the window: lay it out first
    addEvent(function()
        if spin and spin.result == result then
            startStrips(result)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Raising the grade plays on the same reel: its lines say "up to <grade>" or
-- "failed", as many of each as the chance gives, and it stops on the
-- server's answer (a failure often right before a success, as roulettes
-- go). The bar under the reel shows the odds. A success goes on to the
-- roulette of the new bonuses; a failure can be tried again from here.
-- ---------------------------------------------------------------------------
local UPGRADE_SPIN_TIME = 5200
local UPGRADE_REVEAL = 1500 -- ms on the success before the new bonuses spin
local FAILED_COLOR = '#9a8fb0'
local NEAR_MISS = 0.6 -- how often a failure stops right before a success

local function slotEntry(items, slot)
    for _, entry in ipairs(items or {}) do
        if entry.slotId == slot then
            return entry
        end
    end
end

setUpgradeAgain = function()
    local offer = upgrade.finished and not upgrade.success and upgrade.next and upgrade.next.upgrade
    roulette.againButton:setVisible(offer and true or false)
    roulette.xp:setText(upgrade.finished and tr('Rarity XP: %d', rarityXp) or '')
    if offer then
        roulette.againButton:setText(tr('Try again (%s gold + %d XP)', formatGold(offer.gold), offer.xp))
        roulette.againButton:setEnabled(not upgrade.waiting and gold >= offer.gold and rarityXp >= offer.xp)
    end
end

local function upgradeLine(line, success)
    line.text:setText(success and tr('Up to %s!', upgrade.to.label) or tr('Failed'))
    line.text:setColor(success and upgrade.to.color or FAILED_COLOR)
end

-- the reel's lines: each a success with the chance, the answer on WIN_INDEX
local function loadUpgradeReel()
    local strip = roulette.reel.strip
    strip:destroyChildren()
    local share = upgrade.chance / 100
    local lines = {}
    for i = 1, WIN_INDEX + LINES_AFTER do
        lines[i] = math.random() < share
    end
    -- both kinds go by under the marker, whatever the odds
    if share > 0 then
        lines[math.random(2, WIN_INDEX - 1)] = true
    end
    if share < 1 then
        lines[math.random(2, WIN_INDEX - 1)] = false
    end
    lines[WIN_INDEX] = upgrade.success
    if not upgrade.success and share > 0 and math.random() < NEAR_MISS then
        lines[WIN_INDEX + 1] = true
    end
    for i, success in ipairs(lines) do
        local line = g_ui.createWidget('RouletteLine', strip)
        upgradeLine(line, success)
        if i == WIN_INDEX then
            upgrade.line = line
        end
    end
    strip:setHeight(#lines * LINE)
    strip:setMarginTop(REEL_TOP)
    strip:setOpacity(1)
end

local function stopUpgrade()
    if not upgrade or upgrade.finished then
        return
    end
    upgrade.finished = true
    if upgrade.event then
        removeEvent(upgrade.event)
        upgrade.event = nil
    end
    roulette.reel.strip:setMarginTop(REEL_TOP - (WIN_INDEX - 2) * LINE)
    roulette.reel.strip:setOpacity(1)
    local color = upgrade.success and upgrade.to.color or '#ff6464'
    if upgrade.line and not upgrade.line:isDestroyed() then
        upgrade.line:setBackgroundColor(color .. '44')
    end
    local row = upgrade.row
    row:setBorderWidth(1)
    row:setBorderColor(color)
    row:setBackgroundColor(color .. '22')
    row.text:setColor(color)
    roulette.closeButton:setText(tr('Close'))
    if upgrade.success then
        row.text:setText(tr('Success! Now %s.', upgrade.to.label))
        roulette.status:setText(tr('Upgrade! %s rises to %s. Now its new bonuses...', titleCase(upgrade.entry.name or ''), upgrade.to.label))
        roulette.status:setColor(upgrade.to.color)
        local done = upgrade
        scheduleEvent(function()
            if upgrade ~= done or not rouletteVisible() then
                return
            end
            showRoulette(done.data.result, function() applyBonuses(done.data) end)
            -- a refresh that came during the reel is newer than the answer
            spin.pending = done.pending
        end, UPGRADE_REVEAL)
    else
        row.text:setText(tr('Failed: it stays %s.', upgrade.from.label))
        roulette.status:setText(tr('The upgrade failed (%d%% chance). The item stays exactly as it was.', upgrade.chance))
        roulette.status:setColor('#ff6464')
        local latest = upgrade.pending or upgrade.data
        upgrade.pending = nil
        applyBonuses(latest)
        upgrade.next = slotEntry(latest.items, upgrade.entry.slotId)
    end
    setUpgradeAgain()
end

local function animateUpgrade()
    if not upgrade or upgrade.finished or not rouletteVisible() then
        return
    end
    local p = (g_clock.millis() - upgrade.startsAt) / UPGRADE_SPIN_TIME
    if p >= 1 then
        stopUpgrade()
        return
    end
    local position, speed = spinCurve(p)
    local strip = roulette.reel.strip
    strip:setMarginTop(REEL_TOP - math.floor((WIN_INDEX - 2) * LINE * position))
    local peak = 1 / CURVE_AREA
    strip:setOpacity(1 - FADE * math.max(0, math.min(1, (speed - 0.6) / (peak - 0.6))))
    upgrade.event = scheduleEvent(animateUpgrade, FRAME_MS)
end

-- the answer to an upgrade of `entry` (the item as the list showed it)
local function showUpgrade(entry, data)
    if not roulette then
        roulette = g_ui.displayUI('roulette')
    end
    if spin and spin.rows and not spin.finished then
        skipSpin()
    end
    if upgrade and upgrade.event then
        removeEvent(upgrade.event)
    end
    local result = data.result
    local offer = entry.upgrade or {}
    local from = GRADES[entry.rarity] or GRADES.uncommon
    local to = GRADES[offer.to] or from
    local chance = math.max(0, math.min(100, tonumber(offer.chance) or tonumber(result.chance) or 0))
    upgrade = { entry = entry, data = data, success = result.code == 'rerolled', chance = chance, from = from, to = to }

    roulette:setText(tr('Raise the grade'))
    roulette.frame:setImageClip(string.format('%d 0 %d %d', from.frame * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE))
    local item = Item.create(entry.itemId or 0, 1)
    if entry.shader and entry.shader ~= '' then
        item:setShader(entry.shader)
    end
    roulette.frame.item:setItem(item)
    roulette.name:setText(titleCase(entry.name or ''))
    roulette.name:setColor(from.color)
    roulette.subtitle:setText(tr('%s to %s  %d%% chance  -%s gold  -%d Rarity XP', from.label, to.label, chance,
        formatGold(offer.gold or result.gold), tonumber(offer.xp or result.xp) or 0))

    roulette.results:destroyChildren()
    local odds = g_ui.createWidget('UpgradeChance', roulette.results)
    odds.label:setText(tr('Chance'))
    odds.percent:setText(tr('%d%% success, %d%% failure', chance, 100 - chance))
    odds.percent:setColor(to.color)
    odds.bar.fill:setBackgroundColor(to.color)
    local row = g_ui.createWidget('RouletteResult', roulette.results)
    row.slot:setText(tr('Upgrade'))
    row.text:setText('...')
    row.text:setColor(ACTIVE_COLOR)
    row:setBorderWidth(2)
    row:setBorderColor(ACTIVE_COLOR)
    upgrade.row = row
    roulette.results:setHeight(2 * 29)
    roulette.status:setText(tr('Spinning...'))
    roulette.status:setColor('#e0c060')
    roulette.closeButton:setText(tr('Skip'))
    setUpgradeAgain()
    roulette:show()
    roulette:raise()
    roulette:focus()
    -- the bar and the reel are measured against the window: lay it out first
    local mine = upgrade
    addEvent(function()
        if upgrade ~= mine then
            return
        end
        odds.bar.fill:setWidth(math.floor(math.max(0, odds.bar:getWidth() - 2) * chance / 100))
        loadUpgradeReel()
        upgrade.startsAt = g_clock.millis() + 300
        upgrade.event = scheduleEvent(animateUpgrade, FRAME_MS)
    end)
end

-- an answer from the server while the roulette is open
rouletteTakes = function(data)
    local result = data.result
    if upgradeAsked and type(result) == 'table' then
        local asked = upgradeAsked
        if result.code == 'upgradeFailed' or (result.code == 'rerolled' and result.upgrade) then
            upgradeAsked = nil
            showUpgrade(asked.entry, data)
            return true
        end
        if data.ok == false then
            -- refused before the roll (gold, XP, too fast): said where it was asked
            upgradeAsked = nil
            if upgrade and upgrade.waiting and rouletteVisible() then
                upgrade.waiting = false
                applyBonuses(data)
                roulette.status:setText(window.status:getText())
                roulette.status:setColor('#ff6464')
                setUpgradeAgain()
                return true
            end
            return false
        end
    end
    if upgrade and rouletteVisible() and (not upgrade.finished or upgrade.waiting) then
        -- an automatic refresh while the reel runs: kept for its end
        upgrade.pending = data
        return true
    end
    if type(result) == 'table' and result.code == 'rerolled' then
        showRoulette(result, function() applyBonuses(data) end)
        return true
    end
    if spin and rouletteVisible() and spin.waiting and data.ok == false then
        -- "spin again" failed (not enough XP, item taken off, too fast): say
        -- why. The answer carries the whole list, newer than a kept refresh.
        spin.waiting = false
        spin.finished = true
        spin.pending = nil
        applyBonuses(data)
        roulette.status:setText(window.status:getText())
        roulette.status:setColor('#ff6464')
        roulette.closeButton:setText(tr('Close'))
        setAgainButton()
        return true
    end
    if spin and rouletteVisible() and (not spin.finished or spin.waiting) then
        -- an automatic refresh while the strips run or "spin again" waits for
        -- its answer: keep it for the end
        spin.pending = data
        return true
    end
    return false
end

-- the Store on its Rarity category, where Rarity XP is sold
function buyRarityXp()
    if modules.game_store and modules.game_store.openCategory then
        modules.game_store.openCategory('Rarity', 'Rarity XP')
    elseif modules.game_store and modules.game_store.toggle then
        modules.game_store.toggle()
    end
end

function spinAgain()
    if upgrade then
        local next = upgrade.next
        if not upgrade.finished or upgrade.success or upgrade.waiting or not (next and next.upgrade) then
            return
        end
        upgrade.waiting = true
        upgradeAsked = { entry = next }
        roulette.status:setText(tr('Spinning...'))
        roulette.status:setColor('#e0c060')
        roulette.againButton:setEnabled(false)
        send({ action = 'upgradeItem', slot = next.slotId })
        return
    end
    if not spin or not spin.result or not spin.finished then
        return
    end
    local cost = tonumber(spin.result.nextCost or spin.result.cost) or 0
    if rarityXp < cost then
        return
    end
    spin.waiting = true
    roulette.status:setText(tr('Spinning...'))
    roulette.status:setColor('#e0c060')
    roulette.againButton:setEnabled(false)
    -- the same bonus stays kept, for gold again
    send({ action = 'rerollItem', slot = spin.result.slot, lock = spin.result.lock })
end

function closeRoulette()
    if not roulette then
        return
    end
    if upgrade then
        if not upgrade.finished then
            stopUpgrade()
            return
        end
        local done = upgrade
        upgrade = nil
        -- closed before the new bonuses spun: the list shows them
        if done.success then
            applyBonuses(done.pending or done.data)
        end
        roulette:hide()
        return
    end
    if spin and not spin.finished and spin.rows then
        skipSpin()
        return
    end
    roulette:hide()
end

function request()
    window.status:setText('')
    send({ action = 'open' })
end

function hide()
    if not window then
        return
    end
    window:hide()
    if featureButton then
        featureButton:setOn(false)
    end
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
end

function toggle()
    if window and window:isVisible() then
        hide()
    else
        request()
    end
end

-- equipment changed while the window is open: ask again
local function onInventoryChange(player, slot, item, oldItem)
    if not window or not window:isVisible() then
        return
    end
    -- the same item with only its count changed (an arrow shot, a charge
    -- used): its bonuses are the same, so no rebuild of the whole window
    if item and oldItem and item:getId() == oldItem:getId() and item:getCountOrSubType() ~= oldItem:getCountOrSubType() then
        return
    end
    if refreshEvent then
        removeEvent(refreshEvent)
    end
    refreshEvent = scheduleEvent(function()
        refreshEvent = nil
        send({ action = 'open' })
    end, 500)
end

local function onGameStart()
    if not featureButton and modules.game_brevespanel then
        featureButton = modules.game_brevespanel.addFeature('bonus', toggle)
    end
    if not incenseButton and modules.game_brevespanel then
        incenseButton = modules.game_brevespanel.addFeature('incense', lightIncense)
    end
end

local function onGameEnd()
    for key in pairs(revivals) do
        dropRevive(key)
    end
    clearLootFinds()
    hide()
    if roulette then
        roulette:hide()
    end
    spin = nil
end

function init()
    registerReviveTextures()
    registerLootTextures()
    g_ui.importStyle('lootfind')
    window = g_ui.displayUI('raritybonus')
    window:hide()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    connect(LocalPlayer, { onInventoryChange = onInventoryChange })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    disconnect(LocalPlayer, { onInventoryChange = onInventoryChange })
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
    end
    if featureButton then
        featureButton:destroy()
        featureButton = nil
    end
    if incenseButton then
        incenseButton:destroy()
        incenseButton = nil
    end
    if incenseEvent then
        removeEvent(incenseEvent)
        incenseEvent = nil
    end
    if window then
        window:destroy()
        window = nil
    end
    if upgrade and upgrade.event then
        removeEvent(upgrade.event)
    end
    upgrade, upgradeAsked = nil, nil
    if roulette then
        roulette:destroy()
        roulette = nil
    end
    spin = nil
    for key in pairs(revivals) do
        dropRevive(key)
    end
    unregisterReviveTextures()
    clearLootFinds()
    unregisterLootTextures()
end
