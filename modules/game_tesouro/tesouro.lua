-- Tesouro Mythos: gold from the bank put away in bonds of 7, 15 or 30 days
-- that pay the server's inflation plus a fixed rate (server:
-- scripts/tesouro/tesouro.lua). The window shows the inflation, the three
-- terms and the character's bonds; a bond redeemed before its day pays only
-- part of what it earned.
--
-- Extended opcode 146, JSON:
--   client -> server: { action = 'open' }, { action = 'buy', term, amount },
--                     { action = 'redeem', id }
--   server -> client: { action = 'state', ok, message, bank, invested, daily,
--     week, offers = { { key, days, real, total } }, limits = { min, max,
--     bonds, level, earlyShare }, bonds = { { id, days, principal, value,
--     pay, earned, maturesAt, matured } }, now }

local OPCODE = 146

local window
local panelButton, toolbarButton
local state
local selectedTerm
local confirmBox
local clockOffset = 0 -- server time minus this machine's
local countdownEvent

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol and g_game.isOnline() then
        protocol:sendExtendedJSONOpcode(OPCODE, data)
    end
end

-- 1234567 -> "1.234.567"
local function gold(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    local out = text:reverse():gsub('(%d%d%d)', '%1.'):reverse()
    return (out:gsub('^%.', ''))
end

local function percent(value)
    return (string.format('%.2f', tonumber(value) or 0):gsub('%.', ','))
end

local function amountTyped()
    if not window then
        return 0
    end
    local digits = window.buyBox.amount:getText():gsub('%D', '')
    return tonumber(digits) or 0
end

local function setStatus(text, color)
    if window then
        window.status:setText(text or '')
        window.status:setColor(color or '#b4afc3')
    end
end

local function closeConfirm()
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
end

local function confirm(title, text, callback)
    closeConfirm()
    local function yes()
        closeConfirm()
        callback()
    end
    confirmBox = displayGeneralBox(title, text,
        { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = closeConfirm } }, yes, closeConfirm)
end

-- "12d 3h", "5h 20min", "40min" until a server time
local function timeLeft(at)
    local left = math.max(0, at - (os.time() + clockOffset))
    local days = math.floor(left / 86400)
    local hours = math.floor(left % 86400 / 3600)
    local minutes = math.floor(left % 3600 / 60)
    if days > 0 then
        return string.format('%dd %dh', days, hours)
    elseif hours > 0 then
        return string.format('%dh %dmin', hours, minutes)
    end
    return string.format('%dmin', math.max(1, minutes))
end

local function offerOf(key)
    for _, offer in ipairs(state and state.offers or {}) do
        if offer.key == key then
            return offer
        end
    end
    return nil
end

local function refreshBuy()
    if not window or not state then
        return
    end
    local box = window.buyBox
    local limits = state.limits or {}
    local room = math.max(0, (tonumber(limits.max) or 0) - (tonumber(state.invested) or 0))
    local amount = amountTyped()
    local offer = offerOf(selectedTerm)
    local full = #(state.bonds or {}) >= (tonumber(limits.bonds) or 0)
    local okAmount = amount >= (tonumber(limits.min) or 0) and amount <= (tonumber(state.bank) or 0) and amount <= room
    box.buy:setEnabled(offer ~= nil and okAmount and not full)
    if full then
        box.limit:setText(tr('You hold %d bonds, the most.', #state.bonds))
    else
        box.limit:setText(tr('min %s, room for %s', gold(limits.min), gold(room)))
    end
end

local function refresh()
    if not window or not state then
        return
    end
    window.statDay.key:setText(tr('Inflation today'))
    window.statDay.value:setText(tr('%s%% a day', percent(state.daily)))
    window.statWeek.key:setText(tr('Last 7 days'))
    window.statWeek.value:setText(percent(state.week) .. '%')
    window.statBank.key:setText(tr('In the bank'))
    window.statBank.value:setText(gold(state.bank))
    window.statInvested.key:setText(tr('Invested'))
    window.statInvested.value:setText(gold(state.invested))
    local limits = state.limits or {}
    window.intro:setText(tr('A bond takes gold from your bank and gives it back with the inflation of the server plus a fixed rate. Redeemed before its day, it pays only %d%% of what it earned.', math.floor((tonumber(limits.earlyShare) or 0.5) * 100 + 0.5)))

    local offers = window.buyBox.offers
    offers:destroyChildren()
    local focus
    for _, offer in ipairs(state.offers or {}) do
        local row = g_ui.createWidget('TesouroOffer', offers)
        row.name:setText(tr('%d days', offer.days))
        row.rate:setText(tr('inflation + %s%% a month', (tostring(offer.real):gsub('%.', ','))))
        row.total:setText(tr('about +%s%% at today\'s pace', percent(offer.total)))
        row.onFocusChange = function(widget, focused)
            if focused then
                selectedTerm = offer.key
                refreshBuy()
            end
        end
        if offer.key == selectedTerm or not focus then
            focus = row
        end
    end
    if focus then
        offers:focusChild(focus)
    end

    local list = window.bondsBox.list
    list:destroyChildren()
    local bonds = state.bonds or {}
    window.bondsBox.none:setVisible(#bonds == 0)
    window.bondsBox.none:setText(tr('No bonds yet. Pick a term above, type the gold and press Invest.'))
    for _, bond in ipairs(bonds) do
        local row = g_ui.createWidget('TesouroBond', list)
        row.name:setText(tr('%d days  -  %s invested', bond.days, gold(bond.principal)))
        row.value:setText(gold(bond.value))
        row.earned:setText('+' .. gold(bond.earned))
        if bond.matured then
            row.when:setText(tr('Matured: redeem it, it no longer grows.'))
            row.when:setColor('#7fd35a')
            row.redeem:setText(tr('Redeem'))
        else
            row.when:setText(tr('Matures in %s', timeLeft(bond.maturesAt)))
            row.redeem:setText(tr('Redeem early'))
        end
        row.redeem.onClick = function()
            redeem(bond.id)
        end
    end
    refreshBuy()
end

function onAmountChange()
    refreshBuy()
end

-- everything the bank and the limit allow
function fillAll()
    if not window or not state then
        return
    end
    local limits = state.limits or {}
    local room = math.max(0, (tonumber(limits.max) or 0) - (tonumber(state.invested) or 0))
    window.buyBox.amount:setText(tostring(math.floor(math.min(tonumber(state.bank) or 0, room))))
end

function buy()
    local offer = offerOf(selectedTerm)
    local amount = amountTyped()
    if not offer or amount <= 0 then
        return
    end
    confirm(tr('Tesouro Mythos'), tr('Invest %s gold for %d days?\n\nIt pays the inflation of the server plus %s%% a month. The gold leaves your bank now and comes back, with what it earned, when you redeem the bond.\n\nRedeemed before the %d days, it pays only part of what it earned.', gold(amount), offer.days, (tostring(offer.real):gsub('%.', ',')), offer.days), function()
        setStatus(tr('Investing...'), '#e2c46a')
        send({ action = 'buy', term = offer.key, amount = amount })
    end)
end

function redeem(id)
    local bond
    for _, entry in ipairs(state and state.bonds or {}) do
        if entry.id == id then
            bond = entry
        end
    end
    if not bond then
        return
    end
    local function go()
        setStatus(tr('Redeeming...'), '#e2c46a')
        send({ action = 'redeem', id = id })
    end
    if bond.matured then
        go()
        return
    end
    confirm(tr('Redeem early'), tr('Redeem this bond before its day?\n\nInvested: %s\nWorth now: %s\nYou get: %s\n\nWaiting %s more pays the full value.', gold(bond.principal), gold(bond.value), gold(bond.pay), timeLeft(bond.maturesAt)), go)
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' or data.action ~= 'state' then
        return
    end
    state = data
    clockOffset = (tonumber(data.now) or os.time()) - os.time()
    if data.message then
        setStatus(data.message, data.ok and '#7fd35a' or '#ff6464')
        if data.ok and window then
            window.buyBox.amount:setText('')
        end
    end
    -- !tesouro opens the window too
    if data.show and window and not window:isVisible() then
        window:show()
        window:raise()
        window:focus()
    end
    refresh()
end

local function setOn(value)
    if panelButton then
        panelButton:setOn(value)
    end
    if toolbarButton then
        toolbarButton:setOn(value)
    end
end

-- the countdowns of the bonds, once a minute while the window is open
local function countdown()
    countdownEvent = nil
    if window and window:isVisible() then
        if state then
            refresh()
        end
        countdownEvent = scheduleEvent(countdown, 60 * 1000)
    end
end

function show()
    if not window then
        return
    end
    window:show()
    window:raise()
    window:focus()
    setOn(true)
    setStatus('')
    send({ action = 'open' })
    if not countdownEvent then
        countdownEvent = scheduleEvent(countdown, 60 * 1000)
    end
end

function hide()
    if not window then
        return
    end
    closeConfirm()
    window:hide()
    setOn(false)
end

function toggle()
    if window and window:isVisible() then
        hide()
    else
        show()
    end
end

local function onGameStart()
    if not panelButton and modules.game_brevespanel then
        panelButton = modules.game_brevespanel.addFeature('tesouro', toggle)
    end
    if not panelButton and not toolbarButton and modules.game_mainpanel then
        toolbarButton = modules.game_mainpanel.addToggleButton('tesouroButton', tr('Tesouro Mythos'),
            '/game_brevespanel/images/tesouro', toggle, false, 25)
    end
end

local function onGameEnd()
    hide()
    state = nil
    selectedTerm = nil
end

function init()
    window = g_ui.displayUI('tesouro')
    window:hide()
    window:setText(tr('Tesouro Mythos'))
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    closeConfirm()
    if countdownEvent then
        removeEvent(countdownEvent)
        countdownEvent = nil
    end
    if panelButton then
        panelButton:destroy()
        panelButton = nil
    end
    if toolbarButton then
        toolbarButton:destroy()
        toolbarButton = nil
    end
    if window then
        window:destroy()
        window = nil
    end
end
