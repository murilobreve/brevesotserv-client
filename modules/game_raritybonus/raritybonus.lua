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
-- reroll roulette: a slot machine with one reel per bonus the grade allows.
-- The server rolls at once and sends the result; the reels spin through the
-- item's possible bonuses, slow down and stop one by one on it. Reels the
-- item didn't get stop on a dash (the number of bonuses is rolled too).
-- ---------------------------------------------------------------------------

local roulette
local spin -- { result, reels, stops, startedAt, finished, waiting, onDone, pending }
local SPIN_TICK = 45

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

local function randomLine(pool)
    if not pool or #pool == 0 then
        return '???'
    end
    local entry = pool[math.random(#pool)]
    local min, max = tonumber(entry.min) or 1, tonumber(entry.max) or 1
    return string.format('+%d%s %s', math.random(min, math.max(min, max)), entry.unit or '', entry.label or '')
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
    -- the balance only once the reels stop: it is updated with the result
    roulette.xp:setText(spin.finished and tr('Rarity XP: %d', rarityXp) or '')
end

local function finishSpin()
    if not spin or spin.finished then
        return
    end
    spin.finished = true
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

local function stopReel(index)
    local reel = spin.reels[index]
    if not reel or reel.stopped then
        return
    end
    reel.stopped = true
    local entry = (spin.result.rolled or {})[index]
    if entry then
        local color = qualityColor(entry.quality, entry.perfect)
        reel.widget.text:setText(entry.perfect and (entry.text .. '  ' .. tr('PERFECT')) or entry.text)
        reel.widget.text:setColor(color)
        reel.widget:setBorderColor(color)
        -- a short flash in the bonus's colour
        reel.widget:setBackgroundColor(color .. '66')
        scheduleEvent(function()
            if reel.widget and not reel.widget:isDestroyed() then
                reel.widget:setBackgroundColor('#0b0b0bee')
            end
        end, 160)
    else
        reel.widget.text:setText('-')
        reel.widget.text:setColor('#4a4a4a')
        reel.widget:setBorderColor('#2a2a2a')
    end
    for _, other in ipairs(spin.reels) do
        if not other.stopped then
            return
        end
    end
    finishSpin()
end

local function tickReel(index, token)
    if not spin or spin.token ~= token or not rouletteVisible() then
        return
    end
    local reel = spin.reels[index]
    if not reel or reel.stopped then
        return
    end
    local now = g_clock.millis()
    local delay = SPIN_TICK
    if spin.stops then
        local stopAt = spin.stops[index]
        if now >= stopAt then
            stopReel(index)
            return
        end
        -- slows down towards its stop
        local progress = math.max(0, math.min(1, (now - spin.resultAt) / (stopAt - spin.resultAt)))
        delay = SPIN_TICK + math.floor(260 * progress * progress * progress)
    end
    reel.widget.text:setText(randomLine(spin.pool))
    reel.widget.text:setColor(index % 2 == 0 and '#cfcfcf' or '#9f9f9f')
    scheduleEvent(function() tickReel(index, token) end, delay)
end

-- starts the reels; they spin until a result arrives (setSpinResult)
local function startSpin(pool, reelCount)
    spin = spin or {}
    spin.token = (spin.token or 0) + 1
    spin.pool = pool or spin.pool or {}
    spin.stops = nil
    spin.finished = false
    spin.reels = {}
    roulette.reels:destroyChildren()
    for i = 1, math.max(1, reelCount or 1) do
        local widget = g_ui.createWidget('RouletteReel', roulette.reels)
        spin.reels[i] = { widget = widget }
    end
    roulette.reels:setHeight(#spin.reels * 40)
    roulette.status:setText(tr('Spinning...'))
    roulette.status:setColor('#e0c060')
    roulette.closeButton:setText(tr('Skip'))
    roulette.againButton:setEnabled(false)
    local token = spin.token
    for i = 1, #spin.reels do
        scheduleEvent(function() tickReel(i, token) end, (i - 1) * 60)
    end
end

local function setSpinResult(result, onDone)
    spin.result = result
    spin.onDone = onDone
    spin.waiting = false
    spin.resultAt = g_clock.millis()
    spin.stops = {}
    for i = 1, #spin.reels do
        spin.stops[i] = spin.resultAt + 1300 + (i - 1) * 520
    end
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
    if not (spin and spin.waiting and not spin.finished) then
        startSpin(result.pool, result.maxBonuses)
    end
    spin.pool = result.pool or spin.pool
    setSpinResult(result, onDone)
    setAgainButton()
end

-- an answer from the server while the roulette is open
rouletteTakes = function(data)
    local result = data.result
    if type(result) == 'table' and result.code == 'rerolled' then
        showRoulette(result, function() applyBonuses(data) end)
        return true
    end
    if spin and rouletteVisible() and spin.waiting then
        -- "spin again" failed (not enough XP, item taken off): stop on the
        -- old result and say why
        spin.waiting = false
        for i = 1, #spin.reels do
            stopReel(i)
        end
        applyBonuses(data)
        roulette.status:setText(window.status:getText())
        roulette.status:setColor('#ff6464')
        setAgainButton()
        return true
    end
    if spin and rouletteVisible() and not spin.finished then
        -- an automatic refresh while the reels spin: keep it for the end
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
    startSpin(spin.result.pool, spin.result.maxBonuses)
    spin.waiting = true
    send({ action = 'rerollItem', slot = spin.result.slot })
end

function closeRoulette()
    if not roulette then
        return
    end
    if spin and not spin.finished and spin.stops then
        -- skip: every reel stops on the result at once
        for i = 1, #spin.reels do
            stopReel(i)
        end
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
