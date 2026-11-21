-- Party Hunt window, "Loot" tab (server: data-otservbr-global/scripts/party_loot.lua,
-- extended opcode 144). The drops of the party's kills (rarity items with
-- their grade and bonuses), a claim for single items, and the loot split:
-- one member proposes it, every member accepts, the server sells the loot
-- as Gersao would, hands the claimed items over and pays the shares into the
-- bank.

local OPCODE = 144
local GRADE_COLORS = { uncommon = '#63c08a', rare = '#4f8fe8', epic = '#af78ea', legendary = '#e2a443', mythic = '#e8e4ff' }

-- the fonts draw one glyph per byte (Latin-1); this file and the server's JSON are UTF-8
local function latin1(text)
    return (tostring(text):gsub('[\194\195][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        return string.char((a - 194) * 64 + b)
    end))
end

local globalTr = tr
local function tr(text, ...)
    return latin1(globalTr(text, ...))
end

local function convertStrings(value)
    if type(value) == 'string' then
        return latin1(value)
    elseif type(value) == 'table' then
        for k, v in pairs(value) do
            value[k] = convertStrings(v)
        end
    end
    return value
end

PartyLoot = PartyLoot or {}
PartyLoot.tab = PartyLoot.tab or 'summary'
PartyLoot.state = PartyLoot.state or nil
PartyLoot.seen = PartyLoot.seen or 0

local tickEvent

local function window()
    return openedWindows and openedWindows['partyButton']
end

-- 12.345 (PT-BR)
local function money(value)
    value = math.floor(tonumber(value) or 0)
    local text = tostring(math.abs(value)):reverse():gsub('(%d%d%d)', '%1.'):reverse()
    text = text:gsub('^%.', '')
    return (value < 0 and '-' or '') .. text
end

-- the text cut with "..." to fit `width` pixels of the label's font
local function fit(label, text, width)
    label:setText(text)
    if width <= 0 or label:getTextSize().width <= width then
        return
    end
    local cut = text
    while #cut > 1 do
        cut = cut:sub(1, -2)
        label:setText(cut .. '...')
        if label:getTextSize().width <= width then
            return
        end
    end
end

function PartyLoot.send(action, extra)
    local protocol = g_game.getProtocolGame()
    if not protocol or not g_game.isOnline() then
        return
    end
    local data = { action = action }
    for k, v in pairs(extra or {}) do
        data[k] = v
    end
    protocol:sendExtendedJSONOpcode(OPCODE, data)
end

local function setTabLook()
    local w = window()
    if not w then
        return
    end
    local onLoot = PartyLoot.tab == 'loot'
    w.tabBar.summaryTab:setOn(not onLoot)
    w.tabBar.lootTab:setOn(onLoot)
    local unseen = 0
    local drops = PartyLoot.state and PartyLoot.state.drops or {}
    if not onLoot then
        for _, row in ipairs(drops) do
            if row.n > PartyLoot.seen then
                unseen = unseen + 1
            end
        end
    end
    local proposal = PartyLoot.state and PartyLoot.state.proposal
    local text = tr('Loot')
    if proposal and not proposal.accepted then
        text = tr('Loot') .. ' !'
    elseif unseen > 0 then
        text = string.format('%s (%d)', tr('Loot'), unseen)
    end
    w.tabBar.lootTab:setText(text)
end

function PartyLoot.showTab(tab)
    local w = window()
    if not w then
        return
    end
    PartyLoot.tab = tab
    local onLoot = tab == 'loot'
    w.contentsPanel:setVisible(not onLoot)
    w.lootPanel:setVisible(onLoot)
    -- one scrollbar for both panels: the visible one drives it (the
    -- hidden one keeps its connection, it only moves while hidden)
    local scrollbar = w:getChildById('miniwindowScrollBar')
    if scrollbar then
        local shown, hidden = w.contentsPanel, w.lootPanel
        if onLoot then
            shown, hidden = w.lootPanel, w.contentsPanel
        end
        hidden.verticalScrollBar = nil
        if not shown.lootScrollConnected and shown == w.lootPanel then
            shown.lootScrollConnected = true
            shown:setVerticalScrollBar(scrollbar)
        else
            shown.verticalScrollBar = scrollbar
            shown:updateScrollBars()
        end
    end
    if onLoot then
        PartyLoot.send('open')
        PartyLoot.render()
    end
    setTabLook()
end

local function rowTooltip(row)
    local lines = {}
    if row.gradeName then
        lines[#lines + 1] = string.format('%s %s', row.gradeName, row.name)
        for _, bonus in ipairs(row.bonuses or {}) do
            lines[#lines + 1] = bonus
        end
    else
        lines[#lines + 1] = row.count > 1 and string.format('%dx %s', row.count, row.name) or row.name
    end
    lines[#lines + 1] = string.format(tr('Valor (Gersão): %s gold'), money(row.value))
    if row.monster then
        lines[#lines + 1] = string.format(tr('Último drop: %s'), row.monster)
    end
    if row.claim then
        lines[#lines + 1] = string.format(tr('Reivindicado por %s'), row.claim)
    elseif row.claimable then
        lines[#lines + 1] = tr('Reivindique para ficar com ele na divisão (o valor sai da sua parte).')
    end
    return table.concat(lines, '\n')
end

local function addText(panel, text, color, style)
    local label = g_ui.createWidget(style or 'PartyLootWrap', panel)
    label:setText(text)
    if color then
        label:setColor(color)
    end
    return label
end

local function renderProposal(panel, proposal, width)
    panel:destroyChildren()
    if not proposal then
        panel:setVisible(false)
        return
    end
    panel:setVisible(true)
    local inner = width - 10
    local title = addText(panel, '', '#e8d27a', 'PartyLootText')
    title:setFont('Verdana Bold-11px')
    fit(title, string.format(tr('Divisão de %s'), proposal.by or '?'), inner)
    title:setTooltip(tr('Cada um recebe de volta o que gastou em supplies, mais a sua parte do lucro. O loot é vendido pelo preço do Gersão. Todos precisam aceitar.'))

    -- the hunt in four lines: loot, what was spent, the profit, each one's part
    local function sum(label, value, color, bold)
        local row = g_ui.createWidget('PartyLootSum', panel)
        row.label:setText(label)
        row.amount:setText(value)
        if color then
            row.amount:setColor(color)
        end
        if bold then
            row.label:setFont('Verdana Bold-11px')
            row.amount:setFont('Verdana Bold-11px')
            row.label:setColor('#c0c0c0')
            row:setHeight(16)
        end
        return row
    end
    local profit = (proposal.total or 0) - (proposal.supplies or 0)
    sum(tr('Loot'), money(proposal.total), '#e8d27a')
    sum(tr('Gastos (supplies)'), '-' .. money(proposal.supplies), '#c88a5a')
    sum(profit >= 0 and tr('Lucro') or tr('Prejuízo'), money(profit), profit >= 0 and '#4fd14f' or '#f36500')
    sum(tr('Cada um'), money(proposal.share), proposal.share >= 0 and '#4fd14f' or '#f36500', true)
        :setTooltip(tr('O lucro (ou prejuízo) dividido igualmente entre todos.'))

    local sep = g_ui.createWidget('HorizontalSeparator', panel)
    sep:setMarginTop(3)

    for _, line in ipairs(proposal.lines or {}) do
        local row = g_ui.createWidget('PartyLootPerson', panel)
        row.dot:setBackgroundColor(line.accepted and '#4fd14f' or '#6a6a6a')
        local amount = (line.payout > 0 and '+' or '') .. money(line.payout)
        row.amount:setText(amount)
        row.amount:setColor(line.payout >= 0 and '#4fd14f' or '#f36500')
        fit(row.name, line.name, inner - 11 - row.amount:getTextSize().width - 4)
        row.name:setColor(line.accepted and '#e0e0e0' or '#a8a8a8')
        row.spent:setText(string.format(tr('gasto %s'), money(line.supplies)))
        row.looted:setText(string.format(tr('loot %s'), money(line.loot)))
        -- both on one line only when they fit (the loot is in the tooltip too)
        if row.spent:getTextSize().width + row.looted:getTextSize().width + 11 + 6 > inner then
            row.looted:setVisible(false)
        end
        local tip = {
            line.accepted and tr('Já aceitou') or tr('Ainda não aceitou'),
            string.format(tr('Gastou em supplies: %s (volta para ele)'), money(line.supplies)),
            string.format(tr('Parte do lucro: %s'), money(proposal.share)),
            string.format(tr('Lootou: %s (é vendido na divisão)'), money(line.loot)),
        }
        if (line.missing or 0) > 0 then
            tip[#tip + 1] = string.format(tr('Já não tem parte do loot (usou, vendeu, guardou ou equipou): -%s'), money(line.missing))
        end
        if line.claimed and #line.claimed > 0 then
            tip[#tip + 1] = string.format(tr('Fica com: %s (o valor sai da parte dele)'), table.concat(line.claimed, ', '))
        end
        tip[#tip + 1] = line.payout >= 0 and string.format(tr('Recebe %s no banco.'), money(line.payout)) or string.format(tr('Paga %s do banco.'), money(-line.payout))
        row:setTooltip(table.concat(tip, '\n'))
        if line.claimed and #line.claimed > 0 then
            local claimed = addText(panel, '', '#c9a0ff', 'PartyLootText')
            claimed:setMarginLeft(11)
            fit(claimed, '+ ' .. table.concat(line.claimed, ', '), inner - 11)
        end
    end
    if proposal.notFound and #proposal.notFound > 0 then
        addText(panel, string.format(tr('Fora da divisão (não achados): %s'), table.concat(proposal.notFound, ', ')), '#f36500')
    end
    local left = addText(panel, '', '#7d7d7d', 'PartyLootText')
    left:setId('left')
    left:setMarginTop(3)
    left:setText(string.format(tr('Expira em %ds'), proposal.left or 0))
end

function PartyLoot.render()
    local w = window()
    if not w then
        return
    end
    local panel = w.lootPanel
    local width = math.max(100, panel:getWidth())
    local state = PartyLoot.state
    if not state or state.noParty then
        panel.header.count:setText(tr('Sem party'))
        panel.header.total:setText('')
        panel.header.goldIcon:setVisible(false)
        panel.actions:setVisible(false)
        renderProposal(panel.proposal, nil, width)
        panel.dropsTitle:setVisible(false)
        panel.drops:destroyChildren()
        return
    end
    local total = 0
    for _, row in ipairs(state.drops or {}) do
        total = total + (row.value or 0)
    end
    local count = #(state.drops or {})
    panel.header.count:setText(count == 1 and tr('1 drop') or string.format(tr('%d drops'), count))
    panel.header.total:setText(money(total))
    panel.header.goldIcon:setVisible(true)
    panel.header:setTooltip(tr('Valor pelo preço do Gersão'))
    panel.actions:setVisible(true)
    local proposal = state.proposal
    panel.actions.split:setVisible(not proposal)
    panel.actions.split:setEnabled(count > 0)
    panel.actions.accept:setVisible(proposal ~= nil and not proposal.accepted)
    panel.actions.cancel:setVisible(proposal ~= nil)
    -- already accepted: Cancelar takes the whole row
    panel.actions.cancel:breakAnchors()
    panel.actions.cancel:addAnchor(AnchorTop, 'parent', AnchorTop)
    panel.actions.cancel:addAnchor(AnchorRight, 'parent', AnchorRight)
    if proposal and proposal.accepted then
        panel.actions.cancel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        panel.actions.cancel:setMarginLeft(0)
    else
        panel.actions.cancel:addAnchor(AnchorLeft, 'parent', AnchorHorizontalCenter)
        panel.actions.cancel:setMarginLeft(1)
    end
    renderProposal(panel.proposal, proposal, width)

    panel.dropsTitle:setVisible(true)
    panel.dropsTitle:setText(count == 0 and tr('Os drops da party aparecem aqui.') or tr('Drops'))
    panel.drops:destroyChildren()
    local textWidth = width - 32 - 8
    for _, row in ipairs(state.drops or {}) do
        local widget = g_ui.createWidget('PartyLootRow', panel.drops)
        widget.item:setItemId(row.id)
        fit(widget.name, row.name, textWidth)
        widget.name:setColor(row.grade and GRADE_COLORS[row.grade] or '#c0c0c0')
        local value = money(row.value)
        if row.count > 1 then
            value = string.format('%dx  %s', row.count, value)
        end
        widget:setTooltip(rowTooltip(row))
        if not row.claimable then
            widget.claim:setVisible(false)
        elseif row.mine then
            widget.claim:setText(tr('Soltar'))
            widget.claim:setColor('#e8d27a')
            widget.claim:setTooltip(tr('Desistir do item'))
            widget.claim.onClick = function() PartyLoot.send('unclaim', { n = row.n }) end
        elseif row.claim then
            widget.claim:setText(tr('Dono'))
            widget.claim:setEnabled(false)
            widget.claim:setTooltip(string.format(tr('Reivindicado por %s'), row.claim))
            value = row.claim
            widget.value:setColor('#c9a0ff')
        else
            widget.claim:setText(tr('Quero'))
            widget.claim:setTooltip(tr('Reivindicar: fica com você na divisão, pelo preço do Gersão'))
            widget.claim.onClick = function() PartyLoot.send('claim', { n = row.n }) end
        end
        fit(widget.value, value, textWidth - (widget.claim:isVisible() and 44 or 0))
    end
    if PartyLoot.tab == 'loot' then
        for _, row in ipairs(state.drops or {}) do
            PartyLoot.seen = math.max(PartyLoot.seen, row.n)
        end
    end
    setTabLook()
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    data = convertStrings(data)
    if data.action == 'state' then
        if data.noParty or not PartyLoot.state or #(data.drops or {}) < #(PartyLoot.state.drops or {}) then
            PartyLoot.seen = 0
        end
        PartyLoot.state = data
        if data.proposal then
            PartyLoot.proposalAt = g_clock.millis()
        end
        PartyLoot.render()
    elseif data.action == 'message' and data.text and not data.ok then
        -- the server's own loot message says a split went through
        if modules.game_textmessage then
            modules.game_textmessage.displayGameMessage(data.text)
        end
    end
end

-- the proposal's countdown
local function tick()
    local w = window()
    local proposal = PartyLoot.state and PartyLoot.state.proposal
    if not w or not proposal or not w.lootPanel:isVisible() then
        return
    end
    local elapsed = math.floor((g_clock.millis() - (PartyLoot.proposalAt or 0)) / 1000)
    local left = math.max(0, (proposal.left or 0) - elapsed)
    local label = w.lootPanel.proposal:getChildById('left')
    if label then
        label:setText(string.format(tr('Expira em %ds'), left))
    end
end

function PartyLoot.create()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    PartyLoot.tab = 'summary'
    PartyLoot.showTab('summary')
    if tickEvent then
        removeEvent(tickEvent)
    end
    tickEvent = cycleEvent(tick, 1000)
end

function PartyLoot.onGameStart()
    PartyLoot.state = nil
    PartyLoot.seen = 0
    PartyLoot.send('open')
    PartyLoot.render()
end

function PartyLoot.terminate()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
end
