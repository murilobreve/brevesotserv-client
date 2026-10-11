-- Rarity Bonuses: every rarity item the player wears with its bonuses, and
-- the total of each bonus with the items it comes from. The numbers come from
-- the server (scripts/rarity/bonus_window.lua, extended opcode 123), which
-- adds them up the same way the bonuses are applied.

local OPCODE = 123
local FRAME_SIZE = 34
local LINE = 14

local GRADES = {
    uncommon  = { label = 'Communis',    color = '#3ddc2e', frame = 1 },
    rare      = { label = 'Rarus',       color = '#3d9bff', frame = 2 },
    epic      = { label = 'Praeclarus',  color = '#b45cff', frame = 3 },
    legendary = { label = 'Legendarius', color = '#ff9a1f', frame = 4 },
    mythic    = { label = 'Mythicus',    color = '#66f0ff', frame = 5 },
}

local window
local featureButton
local refreshEvent
local confirmBox
local rarityXp = 0

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

local function fillItems(items)
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
        for _, bonus in ipairs(entry.bonuses or {}) do
            count = count + 1
            local line = g_ui.createWidget('BonusLine', row.bonuses)
            line.text:setText(bonusText(bonus))
            -- near its top: the roulette's colour (from the server)
            if bonus.color and bonus.color ~= '' then
                line.text:setColor(bonus.color)
            end
        end
        local cost = entry.rerollCost or 0
        row.rerollItemButton:setText(tr('Reroll %s', formatCost(cost)))
        row.rerollItemButton:setTooltip(tr('Reroll the whole item at %s: how many bonuses (up to %d), which ones and their values are rolled again. The item, its grade and its finder stay. (%d Rarity XP)', grade.label, entry.maxBonuses or 0, cost))
        row.rerollItemButton:setEnabled(cost > 0 and rarityXp >= cost)
        if cost > 0 and rarityXp < cost then
            row.rerollItemButton:setTooltip(tr('You need %d Rarity XP and have %d. Buy more in the Store (Rarity) or kill Pale, Ashen, Obsidian and Lord of Death monsters.', cost, rarityXp))
        end
        row.rerollItemButton.onClick = function()
            local lines = {}
            for _, bonus in ipairs(entry.bonuses or {}) do
                table.insert(lines, bonusText(bonus))
            end
            confirm(tr('Reroll item'), tr('Reroll %s for %d Rarity XP?\n\nEvery bonus it has now is lost:\n%s\n\nThe new ones can be better or worse, and there is no way back.', titleCase(entry.name or ''), cost, table.concat(lines, '\n')), function()
                send({ action = 'rerollItem', slot = entry.slotId })
            end)
        end
        local linesHeight = count * 18
        row.bonuses:setHeight(linesHeight)
        row:setHeight(math.max(42, 3 + 15 + 16 + 3 + linesHeight + 6))
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
        row.total:setColor(entry.capped and '#ff9a1f' or '#7fd35a')
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
        modules.game_brevespanel.setFeatureLabel('bonus', tr('Bonuses'), '#dfdfdf')
        modules.game_brevespanel.setFeatureState('bonus', tr('%d XP', xp), '#e0c060')
    end
end

local applyBonuses
local rouletteTakes

local function onOpcode(protocol, opcode, data)
    -- the balance, after every change: shown on the Rarity Bonuses row; past
    -- a multiple of 50 a notice offers the window without opening it
    if type(data) == 'table' and data.action == 'xp' then
        showXpBadge(tonumber(data.xp) or 0)
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
local spin -- { result, rows, startedAt, finished, waiting, onDone, pending, event }
local CARD_WIDTH = 176 -- fits "+30% Exevo Gran Mas Flam"
local CARD_GAP = 4
-- The first strip's result is its 16th card, each later strip runs 5 cards
-- more, so every strip moves at about the same pace. A short run on a cubic
-- curve leaves the last two or three cards crawling under the marker for a
-- couple of seconds: time to read them and cheer.
local WIN_INDEX = 16
local WIN_INDEX_STEP = 5
local CARDS_AFTER = 6 -- cards past the winner, so the strip never runs dry
local FIRST_STOP = 4200 -- ms
local NEXT_STOP = 1500 -- ms between strips, one stops at a time
local ACTIVE_COLOR = '#e0c060' -- the strip about to stop

local QUALITY_COLORS = {
    { 0.9, '#ff9a1f' }, -- near the top
    { 0.7, '#c060ff' },
    { 0.45, '#3d9bff' },
    { 0.2, '#3ddc2e' },
    { 0, '#b8b8b8' },
}

local function qualityColor(quality, perfect)
    if perfect then
        return '#ffe24a'
    end
    for _, entry in ipairs(QUALITY_COLORS) do
        if (quality or 0) >= entry[1] then
            return entry[2]
        end
    end
    return '#b8b8b8'
end

-- a card the item could have rolled: mostly low and middle values, now and
-- then one near the top, like the odds really are
local function randomCard(pool)
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
    local cost = tonumber(spin.result.nextCost or spin.result.cost) or 0
    roulette.againButton:setText(tr('Spin again (%d)', cost))
    roulette.againButton:setEnabled(spin.finished and not spin.waiting and rarityXp >= cost)
    -- the balance only once the strips stop: it is updated with the result
    roulette.xp:setText(spin.finished and tr('Rarity XP: %d', rarityXp) or '')
end

local function easeOut(p)
    -- fast start, long slow end (a CS case wheel)
    return 1 - (1 - p) ^ 3
end

local function paintCard(card, text, color, empty)
    card.text:setText(text)
    card.text:setColor(empty and '#5a5a5a' or color)
    card:setBorderColor(empty and '#2a2a2a' or color .. '99')
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
    roulette.status:setColor(result.perfect and '#ffe24a' or qualityColor(best))
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

-- the winning card lights up when its strip stops
local function stopRow(row)
    if row.stopped then
        return
    end
    row.stopped = true
    row.strip:setMarginLeft(-row.target)
    row.widget:setBorderWidth(1)
    local card = row.winner
    if row.entry then
        local color = qualityColor(row.entry.quality, row.entry.perfect)
        card:setBackgroundColor(color .. '55')
        card:setBorderColor(color)
        scheduleEvent(function()
            if card and not card:isDestroyed() then
                card:setBackgroundColor(color .. '22')
            end
        end, 220)
        row.widget:setBorderColor(color)
    else
        row.widget:setBorderColor('#2a2a2a')
    end
end

local function animate()
    if not spin or spin.finished or not rouletteVisible() then
        return
    end
    local now = g_clock.millis()
    local running = false
    for _, row in ipairs(spin.rows) do
        if not row.stopped then
            local p = math.min(1, (now - spin.startedAt) / row.duration)
            row.strip:setMarginLeft(-math.floor(row.target * easeOut(p)))
            if p >= 1 then
                stopRow(row)
            else
                -- the next strip to stop gets a gold frame: watch this one
                if not running and not row.active then
                    row.active = true
                    row.widget:setBorderWidth(2)
                    row.widget:setBorderColor(ACTIVE_COLOR)
                end
                running = true
            end
        end
    end
    if running then
        spin.event = scheduleEvent(animate, 16)
    else
        spin.event = nil
        finishSpin()
    end
end

-- builds one strip per bonus slot and starts them
local function startStrips(result)
    roulette.reels:destroyChildren()
    spin.rows = {}
    local rolled = result.rolled or {}
    local viewport = roulette.reels:getWidth()
    for i = 1, math.max(1, result.maxBonuses or #rolled) do
        local widget = g_ui.createWidget('RouletteRow', roulette.reels)
        local strip = widget.strip
        local row = { widget = widget, strip = strip, entry = rolled[i] }
        local winIndex = WIN_INDEX + (i - 1) * WIN_INDEX_STEP
        local cards = winIndex + CARDS_AFTER
        for c = 1, cards do
            local card = g_ui.createWidget('RouletteCard', strip)
            card:setWidth(CARD_WIDTH)
            if c == winIndex then
                row.winner = card
                if row.entry then
                    local text = row.entry.perfect and (row.entry.text .. '  ' .. tr('PERFECT')) or row.entry.text
                    paintCard(card, text, qualityColor(row.entry.quality, row.entry.perfect))
                else
                    paintCard(card, tr('no bonus'), nil, true)
                end
            elseif (result.maxBonuses or 1) > 1 and math.random() < 0.08 then
                -- empty cards: the number of bonuses is rolled too
                paintCard(card, tr('no bonus'), nil, true)
            else
                local text, color = randomCard(result.pool)
                paintCard(card, text, color)
            end
        end
        strip:setWidth(cards * (CARD_WIDTH + CARD_GAP))
        -- stop with the winner under the marker, a little off-centre like a
        -- real wheel
        local winnerCentre = (winIndex - 1) * (CARD_WIDTH + CARD_GAP) + CARD_WIDTH / 2
        local jitter = math.random(-math.floor(CARD_WIDTH * 0.35), math.floor(CARD_WIDTH * 0.35))
        row.target = math.floor(winnerCentre - viewport / 2 + jitter)
        row.duration = FIRST_STOP + (i - 1) * NEXT_STOP
        spin.rows[i] = row
    end
    roulette.reels:setHeight(#spin.rows * 42)
    spin.startedAt = g_clock.millis()
    spin.finished = false
    roulette.status:setText(tr('Spinning...'))
    roulette.status:setColor('#e0c060')
    roulette.closeButton:setText(tr('Skip'))
    setAgainButton()
    if spin.event then
        removeEvent(spin.event)
    end
    spin.event = scheduleEvent(animate, 16)
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
    roulette.subtitle:setText(tr('%s  up to %d bonuses  -%d Rarity XP', grade.label, result.maxBonuses or 0, tonumber(result.cost) or 0))
    roulette:show()
    roulette:raise()
    roulette:focus()
    spin = spin or {}
    spin.result = result
    spin.onDone = onDone
    spin.waiting = false
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
    if spin and rouletteVisible() and spin.waiting then
        -- "spin again" failed (not enough XP, item taken off): say why
        spin.waiting = false
        spin.finished = true
        applyBonuses(data)
        roulette.status:setText(window.status:getText())
        roulette.status:setColor('#ff6464')
        roulette.closeButton:setText(tr('Close'))
        setAgainButton()
        return true
    end
    if spin and rouletteVisible() and not spin.finished then
        -- an automatic refresh while the strips run: keep it for the end
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
    send({ action = 'rerollItem', slot = spin.result.slot })
end

function closeRoulette()
    if not roulette then
        return
    end
    if spin and not spin.finished and spin.rows then
        -- skip: every strip jumps to its result
        for _, row in ipairs(spin.rows) do
            stopRow(row)
        end
        finishSpin()
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
local function onInventoryChange()
    if not window or not window:isVisible() then
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
end

local function onGameEnd()
    hide()
    if roulette then
        roulette:hide()
    end
    spin = nil
end

function init()
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
