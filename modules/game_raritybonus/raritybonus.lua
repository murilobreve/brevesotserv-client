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
    epic      = { label = 'Praeclarus',  color = '#a679e6', frame = 3 },
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
    if up then
        row.upgradeItemButton:setText(tr('%s %d%%', up.label, up.chance))
        row.upgradeItemButton:setEnabled(gold >= up.gold and rarityXp >= up.xp)
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
        for _, bonus in ipairs(entry.bonuses or {}) do
            count = count + 1
            local line = g_ui.createWidget('BonusLine', row.bonuses)
            line.text:setText(bonusText(bonus))
            -- near its top: the roulette's colour (from the server)
            if bonus.color and bonus.color ~= '' then
                line.text:setColor(bonus.color)
            end
            -- the padlock: keep this bonus on the next reroll, for gold
            line.lock:setVisible(lockable)
            line.text:setMarginLeft(lockable and 4 or -12)
            if lockable then
                local locked = locks[entry.slotId] == bonus.key
                line.lock:setOn(locked)
                line.lock:setTooltip(locked and tr('Locked: this bonus keeps its value on the next reroll. Click to unlock it.')
                    or tr('Keep this bonus with its value on the next reroll: %s gold, on top of the Rarity XP. One bonus per item.', formatGold(entry.lockCost)))
                -- the whole line lights up, so a locked bonus is never missed
                if locked then
                    line:setBackgroundColor('#e0c06024')
                    line:setBorderWidth(1)
                    line:setBorderColor('#e0c06070')
                    line.tag:setText(tr('Locked: kept on the next reroll (+%s)', formatGold(entry.lockCost)))
                    line.tag:show()
                end
                line.lock.onClick = function()
                    local name = titleCase(entry.name or '')
                    if locks[entry.slotId] == bonus.key then
                        locks[entry.slotId] = nil
                        window.status:setText(tr('%s unlocked: the next reroll of %s rolls every bonus again.', bonusText(bonus), name))
                        window.status:setColor('#ab9fc6')
                    else
                        locks[entry.slotId] = bonus.key
                        window.status:setText(tr('%s locked on %s: the next reroll keeps it with this value and rolls only the others, for %s gold on top of the Rarity XP.', bonusText(bonus), name, formatGold(entry.lockCost)))
                        window.status:setColor('#e0c060')
                    end
                    fillItems(lastItems or {})
                end
            end
        end
        local cost = entry.rerollCost or 0
        local lockKey = locks[entry.slotId]
        row.rerollItemButton:setText(lockKey and tr('Reroll %s +%s', formatCost(cost), formatGold(entry.lockCost)) or tr('Reroll %s', formatCost(cost)))
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
                send({ action = 'upgradeItem', slot = entry.slotId })
            end)
        end
        local linesHeight = count * 18
        row.bonuses:setHeight(linesHeight)
        row:setHeight(math.max(48, 3 + 15 + 16 + 3 + linesHeight + 6))
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

-- a find floats over the corpse's tile for a few seconds, in the grade's
-- colour: the grade, the item, and whether it went into the backpack
-- (server: scripts/rarity/loot.lua, RarityConfig.floatOverCorpse)
local function showDrop(data)
    local rarity = ItemsDatabase.itemRarity and ItemsDatabase.itemRarity[data.grade]
    if not rarity or not data.x then
        return
    end
    local lines = { rarity.label, data.name or '' }
    if data.picked then
        table.insert(lines, tr('(na mochila)'))
    end
    local text = StaticText.create()
    text:addMessage('', MessageModes.MonsterSay, table.concat(lines, '\n'))
    text:setColor(rarity.color)
    text:setFont('Verdana Bold-11px')
    g_map.addStaticText(text, { x = data.x, y = data.y, z = data.z })
end

-- A rare monster rising from its corpse, told without words: thin rings of
-- light in the tier's colour open wide around the body and close in on it,
-- as if the soul were being pulled back, faster and faster as the moment
-- nears, over a soft glow that breathes with the corpse's heartbeat. When the
-- monster stands up a single ring opens out from it and fades. The server
-- sends it (scripts/rarity/revive.lua).
local REVIVE_COLORS = {
    pale = '#dce8f5',
    ashen = '#f2a46a',
    obsidian = '#b39bff',
    deathlord = '#ff6a5e',
}
local RING_LIFE = 900       -- ms a ring takes to close in
local FLASH_LIFE = 650      -- ms of the last ring opening out
local revivals = {}

local function mapTileWidth()
    local panel = modules.game_interface and modules.game_interface.getMapPanel()
    local dim = panel and panel:getVisibleDimension()
    if not dim or dim.width <= 0 then
        return 32
    end
    return math.min(panel:getWidth() / dim.width, panel:getHeight() / dim.height)
end

local function attachRevive(entry)
    if entry.box:getParent() then
        return true
    end
    local tile = g_map.getTile(entry.pos)
    if not tile then
        return false
    end
    tile:attachWidget(entry.box)
    return true
end

local function dropRevive(key)
    local entry = revivals[key]
    revivals[key] = nil
    if entry then
        removeEvent(entry.event)
        if not entry.box:isDestroyed() then
            entry.box:destroy()
        end
    end
end

-- a centred square child of the box, `size` pixels wide
local function setCircle(widget, size, opacity)
    size = math.max(1, math.floor(size))
    widget:setSize({ width = size, height = size })
    widget:setOpacity(math.max(0, math.min(1, opacity)))
end

local function newCircle(entry, style)
    local widget = g_ui.createWidget(style, entry.box)
    widget:setImageColor(entry.color)
    widget:setOpacity(0)
    return widget
end

local function showRevive(data)
    if not data.x or not tonumber(data.ms) then
        return
    end
    local pos = { x = data.x, y = data.y, z = data.z }
    local key = pos.x .. ':' .. pos.y .. ':' .. pos.z
    dropRevive(key)
    local box = g_ui.createWidget('ReviveBox')
    local entry = {
        pos = pos,
        box = box,
        color = REVIVE_COLORS[data.tier] or '#ffffff',
        total = tonumber(data.ms),
        starts = g_clock.millis(),
        rings = {},
        nextRing = 0,
    }
    entry.glow = newCircle(entry, 'ReviveGlow')
    revivals[key] = entry

    local function frame()
        if box:isDestroyed() then
            revivals[key] = nil
            return
        end
        local now = g_clock.millis()
        local elapsed = now - entry.starts
        local p = math.min(1, elapsed / entry.total)
        local tile = mapTileWidth()
        local span = math.floor(tile * 3.4)
        box:setSize({ width = span, height = span })
        box:setMarginLeft(math.floor((tile - span) / 2))
        box:setMarginTop(math.floor((tile - span) / 2))
        attachRevive(entry)

        if p < 1 then
            -- a new ring every 1.1 s at first, every 0.32 s at the end
            if elapsed >= entry.nextRing then
                table.insert(entry.rings, { widget = newCircle(entry, 'ReviveRing'), born = now })
                entry.nextRing = elapsed + 1100 - 780 * p
            end
            -- the glow breathes: one breath every 1.2 s, three a second at the end
            local rate = 0.8 + 2.2 * p * p
            local breath = 0.5 + 0.5 * math.cos(elapsed / 1000 * rate * 2 * math.pi)
            local fadeIn = math.min(1, elapsed / 800)
            setCircle(entry.glow, tile * (1.3 + 0.3 * breath), fadeIn * (0.22 + 0.30 * p + 0.15 * breath))
        end

        for i = #entry.rings, 1, -1 do
            local ring = entry.rings[i]
            local t = (now - ring.born) / RING_LIFE
            if t >= 1 then
                ring.widget:destroy()
                table.remove(entry.rings, i)
            else
                -- closes in fast and slows down as it reaches the body
                local ease = 1 - (1 - t) * (1 - t)
                setCircle(ring.widget, tile * (3.2 - 2.6 * ease), 0.95 * math.sin(math.pi * t))
            end
        end

        if p >= 1 then
            -- the monster stands up: one ring opens out and the glow fades
            if not entry.flash then
                entry.flash = newCircle(entry, 'ReviveRing')
                entry.flashBorn = now
            end
            local t = (now - entry.flashBorn) / FLASH_LIFE
            if t >= 1 and #entry.rings == 0 then
                dropRevive(key)
                return
            end
            t = math.min(1, t)
            local ease = 1 - (1 - t) * (1 - t) * (1 - t)
            setCircle(entry.flash, tile * (0.6 + 2.8 * ease), 0.9 * (1 - t))
            setCircle(entry.glow, tile * (1.4 + 0.8 * ease), 0.45 * (1 - t))
        end
        entry.event = scheduleEvent(frame, 30)
    end
    frame()
end

local function onOpcode(protocol, opcode, data)
    if type(data) == 'table' and data.action == 'drop' then
        showDrop(data)
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
    if not spin or not spin.result then
        return
    end
    -- an upgrade is not spun again: the item is rerolled from the list
    roulette.againButton:setVisible(not spin.result.upgrade)
    local cost = tonumber(spin.result.nextCost or spin.result.cost) or 0
    local lockGold = spin.result.lock and (tonumber(spin.result.nextGold) or 0) or 0
    roulette.againButton:setText(lockGold > 0 and tr('Spin again (%d + %s)', cost, formatGold(lockGold)) or tr('Spin again (%d)', cost))
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
        row.result.slot:setText(tr('Locked'))
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
        subtitle = subtitle .. '  ' .. (result.lock and tr('-%s gold (lock)', formatGold(result.gold)) or tr('-%s gold', formatGold(result.gold)))
    end
    if result.upgrade then
        subtitle = tr('Upgrade to %s!', grade.label) .. '  ' .. subtitle
    end
    roulette.subtitle:setText(subtitle)
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

-- an answer from the server while the roulette is open
rouletteTakes = function(data)
    local result = data.result
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
    hide()
    if roulette then
        roulette:hide()
    end
    spin = nil
end

function init()
    g_ui.importStyle('revive')
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
    if roulette then
        roulette:destroy()
        roulette = nil
    end
    spin = nil
end
