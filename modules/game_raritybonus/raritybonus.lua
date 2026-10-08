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
            line.rerollButton:setText(tr('Reroll %d', entry.rerollCost or 0))
            line.rerollButton:setTooltip(tr('Roll a new value for %s (%d Rarity XP).', bonus.label, entry.rerollCost or 0))
            line.rerollButton:setEnabled(rarityXp >= (entry.rerollCost or 0))
            line.rerollButton.onClick = function()
                send({ action = 'reroll', slot = entry.slotId, key = bonus.key, mode = 'value' })
            end
            line.changeButton:setText(tr('Change %d', entry.changeCost or 0))
            line.changeButton:setTooltip(tr('Swap %s for another random bonus (%d Rarity XP).', bonus.label, entry.changeCost or 0))
            line.changeButton:setEnabled(rarityXp >= (entry.changeCost or 0))
            line.changeButton.onClick = function()
                confirm(tr('Change bonus'), tr('Swap %s for another random bonus of this item for %d Rarity XP? The current one is lost.', bonusText(bonus), entry.changeCost or 0), function()
                    send({ action = 'reroll', slot = entry.slotId, key = bonus.key, mode = 'change' })
                end)
            end
        end
        local linesHeight = count * 20
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

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' or data.action ~= 'bonuses' or not window then
        return
    end
    rarityXp = tonumber(data.rarityXp) or 0
    window.xpLabel:setText(tr('Rarity XP: %d', rarityXp))
    window.xpLabel:setTooltip(tr('Earned by killing Pale, Ashen, Obsidian and Lord of Death monsters: the stronger the monster and its tier, the more you get. Spend it here to reroll the bonuses of the items you wear; items of a higher grade or level cost more.'))
    -- automatic refreshes (equipment changed) carry no message: keep the
    -- answer to the last reroll on screen
    if data.message then
        window.status:setText(data.message)
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
end
