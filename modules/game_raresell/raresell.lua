-- Rare Sell: the rarity items in the player's bags that Gersao buys, to tick
-- and sell. No NPC buys rarity items in the trade window, so they are never
-- sold by accident; asking Gersao for "trade" opens this list next to the
-- trade window (when there is something to sell), "rare" opens it alone. The list and
-- the sale are on the server (scripts/rarity/sell_window.lua, extended
-- opcode 125), which checks every item again before selling it.

local OPCODE = 125
local FRAME_SIZE = 34

local GRADES = {
    { key = 'uncommon',  label = 'Communis',    color = '#63c08a', frame = 1 },
    { key = 'rare',      label = 'Rarus',       color = '#4f8fe8', frame = 2 },
    { key = 'epic',      label = 'Praeclarus',  color = '#a679e6', frame = 3 },
    { key = 'legendary', label = 'Legendarius', color = '#e2a443', frame = 4 },
    { key = 'mythic',    label = 'Mythicus',    color = '#e8e4ff', frame = 5 },
}
local GRADE_BY_KEY = {}
for index, grade in ipairs(GRADES) do
    grade.order = index
    GRADE_BY_KEY[grade.key] = grade
end

local window
local confirmBox
local token = 0
local rows = {}
-- set while a button ticks many rows: the total is counted once at the end,
-- not once per row (250 rows made that 250 times 250)
local bulk = false

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(OPCODE, data)
    end
end

-- 1234567 -> "1.234.567"
local function gold(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    local result = text:reverse():gsub('(%d%d%d)', '%1.'):reverse()
    return (result:gsub('^%.', ''))
end

local function titleCase(text)
    return (text:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

local function closeConfirm()
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
end

local function selected()
    local list = {}
    for _, row in ipairs(rows) do
        if row.pick:isChecked() then
            table.insert(list, row.entry)
        end
    end
    return list
end

local function updateTotal()
    if bulk then
        return
    end
    local picked = selected()
    local total = 0
    for _, entry in ipairs(picked) do
        total = total + (tonumber(entry.price) or 0)
    end
    if #picked == 0 then
        window.total:setText(tr('Nothing selected'))
    else
        window.total:setText(tr('%d selected: %s gold', #picked, gold(total)))
    end
    window.sellButton:setEnabled(#picked > 0)
end

-- the grade buttons tick every item of that grade (or untick, if all are)
local function selectGrade(key)
    local all = true
    for _, row in ipairs(rows) do
        if (key == nil or row.entry.rarity == key) and not row.pick:isChecked() then
            all = false
        end
    end
    bulk = true
    for _, row in ipairs(rows) do
        if key == nil or row.entry.rarity == key then
            row.pick:setChecked(not all)
        end
    end
    bulk = false
    updateTotal()
end

local function gradeButton(parent, text)
    local button = g_ui.createWidget('RareSellGradeButton', parent)
    button:setText(text)
    button:setWidth(math.max(46, #text * 7 + 16))
    return button
end

local function fillGradeButtons(items)
    local panel = window.gradeButtons
    panel:destroyChildren()
    local present = {}
    for _, entry in ipairs(items) do
        present[entry.rarity] = true
    end
    local all = gradeButton(panel, tr('All'))
    all.onClick = function() selectGrade(nil) end
    for _, grade in ipairs(GRADES) do
        if present[grade.key] then
            local button = gradeButton(panel, grade.label)
            button:setColor(grade.color)
            button.onClick = function() selectGrade(grade.key) end
        end
    end
    local none = gradeButton(panel, tr('Clear'))
    none.onClick = function()
        bulk = true
        for _, row in ipairs(rows) do
            row.pick:setChecked(false)
        end
        bulk = false
        updateTotal()
    end
end

local function fillItems(items)
    local list = window.itemsSection.itemsList
    list:destroyChildren()
    rows = {}
    -- weakest grades first: those are the ones usually sold
    table.sort(items, function(a, b)
        local ga = GRADE_BY_KEY[a.rarity] or GRADES[1]
        local gb = GRADE_BY_KEY[b.rarity] or GRADES[1]
        if ga.order ~= gb.order then
            return ga.order < gb.order
        end
        if (a.price or 0) ~= (b.price or 0) then
            return (a.price or 0) > (b.price or 0)
        end
        return (a.name or '') < (b.name or '')
    end)
    window.itemsSection.itemsEmpty:setVisible(#items == 0)
    for index, entry in ipairs(items) do
        local row = g_ui.createWidget(index % 2 == 0 and 'RareSellRowEven' or 'RareSellRow', list)
        local grade = GRADE_BY_KEY[entry.rarity] or GRADES[1]
        row.entry = entry
        row.frame:setImageClip(string.format('%d 0 %d %d', grade.frame * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE))
        local item = Item.create(entry.itemId, math.max(1, tonumber(entry.count) or 1))
        if entry.shader and entry.shader ~= '' then
            item:setShader(entry.shader)
        end
        row.frame.item:setItem(item)
        local name = titleCase(entry.name or '')
        if (entry.count or 1) > 1 then
            name = string.format('%dx %s', entry.count, name)
        end
        row.name:setText(name)
        row.name:setColor(grade.color)
        -- the item name already carries its grade: the line below shows the
        -- bonuses, so two items of the same kind can be told apart
        local bonuses = entry.bonuses or {}
        local info = table.concat(bonuses, ', ')
        if entry.perfect then
            info = tr('perfect roll') .. '  ' .. info
            row.info:setColor('#ffd84a')
        end
        row.info:setText(info)
        if #bonuses > 0 then
            row:setTooltip(name .. '\n' .. table.concat(bonuses, '\n'))
        end
        row.price:setText(gold(entry.price) .. ' gp')
        row.pick.onCheckChange = updateTotal
        -- a click anywhere on the row ticks it
        row.onClick = function()
            row.pick:setChecked(not row.pick:isChecked())
        end
        table.insert(rows, row)
    end
    fillGradeButtons(items)
    updateTotal()
end

-- the answer to a sale, in the player's language
local function resultText(result)
    if type(result) ~= 'table' then
        return nil
    end
    if result.code == 'sold' then
        local sold = tonumber(result.sold) or 0
        if sold == 1 then
            return tr('You sold 1 rarity item (%s) for %s gold. The gold went to your bank.', result.grades or '', gold(result.total))
        end
        return tr('You sold %d rarity items (%s) for %s gold. The gold went to your bank.', sold, result.grades or '', gold(result.total))
    elseif result.code == 'stale' then
        return tr('The list was out of date, here it is again. Nothing was sold.')
    elseif result.code == 'far' then
        return tr('Go back to Gersao to sell.')
    elseif result.code == 'gone' then
        return tr('None of those items is in your bags any more.')
    end
    return nil
end

local docked = false -- opened with Gersao's trade window

-- the NPC trade window on screen (new dialog or legacy), if any
local function tradeWindow()
    for _, id in ipairs({ 'windowTrader', 'npcWindow' }) do
        local widget = rootWidget:recursiveGetChildById(id)
        if widget and widget:isVisible() then
            return widget
        end
    end
    return nil
end

-- side by side with the trade window, the pair centred on screen; on a small
-- screen the trade window goes to the left edge and this list takes the rest
-- of the width (never narrower than MIN_DOCK_WIDTH)
local DOCK_GAP = 6
local MIN_DOCK_WIDTH = 380
local FULL_WIDTH = 600

local function dockBesideTrade()
    local trade = tradeWindow()
    if not trade then
        return
    end
    local screenW, screenH = rootWidget:getWidth(), rootWidget:getHeight()
    local rect = trade:getRect()
    local width = FULL_WIDTH
    local tradeX
    if rect.width + DOCK_GAP + FULL_WIDTH <= screenW then
        tradeX = math.floor((screenW - rect.width - DOCK_GAP - FULL_WIDTH) / 2)
    else
        tradeX = 0
        width = math.max(MIN_DOCK_WIDTH, screenW - rect.width - DOCK_GAP)
    end
    local y = math.max(0, math.min(rect.y, screenH - window:getHeight()))
    trade:breakAnchors()
    trade:setPosition({ x = tradeX, y = rect.y })
    window:breakAnchors()
    window:setWidth(width)
    window:setPosition({ x = math.min(tradeX + rect.width + DOCK_GAP, screenW - width), y = y })
    window:raise()
end

local function show()
    if not window:isVisible() then
        window:show()
        window:raise()
        window:focus()
    end
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' or data.action ~= 'list' or not window then
        return
    end
    -- with the trade window: only when there is a rarity item to sell
    if data.docked then
        if #(data.items or {}) == 0 then
            return
        end
        docked = true
    end
    closeConfirm()
    token = tonumber(data.token) or 0
    fillItems(data.items or {})
    local message = resultText(data.result) or data.message
    if message then
        window.status:setText(message)
        window.status:setColor(data.ok == false and '#ff6464' or '#7fd35a')
    else
        window.status:setText('')
    end
    local wasVisible = window:isVisible()
    show()
    if data.docked and not wasVisible then
        -- the trade window is created in the same tick: dock once it is laid out
        scheduleEvent(dockBesideTrade, 50)
    end
end

-- the trade window closed: the list opened with it goes too. The NPC dialog
-- also fires these while it turns into the trade window, so look again a
-- moment later and only hide when no trade window is left on screen.
local function onTradeClosed()
    if not docked then
        return
    end
    scheduleEvent(function()
        if docked and not tradeWindow() then
            hide()
        end
    end, 300)
end

function sellSelected()
    local picked = selected()
    if #picked == 0 then
        return
    end
    local total, refs = 0, {}
    local strong, perfect = {}, 0
    for _, entry in ipairs(picked) do
        total = total + (tonumber(entry.price) or 0)
        table.insert(refs, entry.ref)
        if entry.rarity == 'legendary' or entry.rarity == 'mythic' then
            local grade = GRADE_BY_KEY[entry.rarity]
            strong[grade.label] = (strong[grade.label] or 0) + 1
        end
        if entry.perfect then
            perfect = perfect + 1
        end
    end
    local message
    if #picked == 1 then
        message = tr('Sell 1 rarity item to Gersao for %s gold?', gold(total))
    else
        message = tr('Sell %d rarity items to Gersao for %s gold?', #picked, gold(total))
    end
    local warnings = {}
    for _, label in ipairs({ 'Mythicus', 'Legendarius' }) do
        if strong[label] then
            table.insert(warnings, string.format('%d %s', strong[label], label))
        end
    end
    if perfect > 0 then
        table.insert(warnings, tr('%d with a perfect roll', perfect))
    end
    if #warnings > 0 then
        message = message .. '\n\n' .. tr('Among them: %s. A sold item does not come back.', table.concat(warnings, ', '))
    end
    closeConfirm()
    local sentToken = token
    local function confirmSell()
        closeConfirm()
        send({ action = 'sell', token = sentToken, refs = refs })
    end
    confirmBox = displayGeneralBox(tr('Sell rarity items'), message, {
        { text = tr('Sell'), callback = confirmSell },
        { text = tr('Cancel'), callback = closeConfirm },
        anchor = AnchorHorizontalCenter,
    }, confirmSell, closeConfirm)
end

function hide()
    docked = false
    if window then
        window:setWidth(FULL_WIDTH)
    end
    closeConfirm()
    if window then
        window:hide()
    end
end

local function onGameEnd()
    hide()
    token = 0
end

function init()
    window = g_ui.displayUI('raresell')
    window:hide()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameEnd = onGameEnd, onCloseNpcTrade = onTradeClosed, onNpcChatWindowClose = onTradeClosed })
end

function terminate()
    disconnect(g_game, { onGameEnd = onGameEnd, onCloseNpcTrade = onTradeClosed, onNpcChatWindowClose = onTradeClosed })
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    closeConfirm()
    if window then
        window:destroy()
        window = nil
    end
end
