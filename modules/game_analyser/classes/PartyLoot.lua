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

local function money(value)
    value = tonumber(value) or 0
    local text = comma_value(tostring(math.abs(value)))
    return (value < 0 and '-' or '') .. text
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

local function renderProposal(panel, proposal)
    panel:destroyChildren()
    if not proposal then
        panel:setVisible(false)
        return
    end
    panel:setVisible(true)
    local head = g_ui.createWidget('PartyLootLine', panel)
    head:setColor('#e8d27a')
    head:setText(string.format(tr('Divisão proposta por %s'), proposal.by or '?'))
    local sums = g_ui.createWidget('PartyLootLine', panel)
    sums:setText(string.format(tr('Loot %s, supplies %s'), money(proposal.total), money(proposal.supplies)))
    local each = g_ui.createWidget('PartyLootLine', panel)
    each:setText(string.format(tr('Lucro para cada um: %s'), money(proposal.share)))
    for _, line in ipairs(proposal.lines or {}) do
        local label = g_ui.createWidget('PartyLootLine', panel)
        local mark = line.accepted and '[ok]' or '[...]'
        local text = string.format('%s %s: %s', mark, line.name, money(line.payout))
        if line.claimed and #line.claimed > 0 then
            text = text .. ' + ' .. table.concat(line.claimed, ', ')
        end
        label:setText(text)
        label:setColor(line.accepted and '#6fd36f' or '#c0c0c0')
        local tip = {
            string.format(tr('Lootou: %s'), money(line.loot)),
            string.format(tr('Supplies: %s'), money(line.supplies)),
        }
        if (line.missing or 0) > 0 then
            tip[#tip + 1] = string.format(tr('Já não tem (usou, vendeu ou guardou): %s'), money(line.missing))
        end
        tip[#tip + 1] = line.payout >= 0 and tr('Recebe no banco.') or tr('Paga do banco.')
        label:setTooltip(table.concat(tip, '\n'))
    end
    if proposal.notFound and #proposal.notFound > 0 then
        local warn = g_ui.createWidget('PartyLootLine', panel)
        warn:setColor('#f36500')
        warn:setText(string.format(tr('Não encontrados (ficam fora): %s'), table.concat(proposal.notFound, ', ')))
    end
    local left = g_ui.createWidget('PartyLootLine', panel)
    left:setId('left')
    left:setColor('#9d9d9d')
    left:setText(string.format(tr('Expira em %ds. Todos precisam aceitar.'), proposal.left or 0))
end

function PartyLoot.render()
    local w = window()
    if not w then
        return
    end
    local panel = w.lootPanel
    local state = PartyLoot.state
    if not state or state.noParty then
        panel.status:setText(tr('Entre em uma party para ver o loot e dividir.'))
        panel.actions:setVisible(false)
        renderProposal(panel.proposal, nil)
        panel.drops:destroyChildren()
        return
    end
    local total = 0
    for _, row in ipairs(state.drops or {}) do
        total = total + (row.value or 0)
    end
    if #(state.drops or {}) == 0 then
        panel.status:setText(tr('Nenhum loot ainda. Os drops da party aparecem aqui.'))
    else
        panel.status:setText(string.format(tr('%d drops - %s gold (Gersão)'), #state.drops, money(total)))
    end
    panel.actions:setVisible(true)
    local proposal = state.proposal
    panel.actions.split:setVisible(not proposal)
    panel.actions.accept:setVisible(proposal ~= nil and not proposal.accepted)
    panel.actions.cancel:setVisible(proposal ~= nil)
    if proposal and proposal.accepted then
        panel.actions.cancel:breakAnchors()
        panel.actions.cancel:addAnchor(AnchorTop, 'parent', AnchorTop)
        panel.actions.cancel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        panel.actions.cancel:addAnchor(AnchorRight, 'parent', AnchorRight)
    else
        panel.actions.cancel:breakAnchors()
        panel.actions.cancel:addAnchor(AnchorTop, 'parent', AnchorTop)
        panel.actions.cancel:addAnchor(AnchorRight, 'parent', AnchorRight)
        panel.actions.cancel:setWidth(70)
    end
    renderProposal(panel.proposal, proposal)

    panel.drops:destroyChildren()
    for _, row in ipairs(state.drops or {}) do
        local widget = g_ui.createWidget('PartyLootRow', panel.drops)
        widget.item:setItemId(row.id)
        widget.name:setText(row.name)
        widget.name:setColor(row.grade and GRADE_COLORS[row.grade] or '#c0c0c0')
        local value = money(row.value)
        if row.count > 1 then
            value = string.format('%dx - %s', row.count, value)
        elseif row.gradeName then
            value = string.format('%s - %s', value, row.gradeName)
        end
        widget.value:setText(value)
        widget:setTooltip(rowTooltip(row))
        if not row.claimable then
            widget.claim:setVisible(false)
        elseif row.mine then
            widget.claim:setText(tr('Soltar'))
            widget.claim:setColor('#e8d27a')
            widget.claim.onClick = function() PartyLoot.send('unclaim', { n = row.n }) end
        elseif row.claim then
            widget.claim:setText(row.claim:sub(1, 6))
            widget.claim:setEnabled(false)
            widget.claim:setTooltip(string.format(tr('Reivindicado por %s'), row.claim))
        else
            widget.claim:setText(tr('Quero'))
            widget.claim:setTooltip(tr('Reivindicar: fica com você na divisão, pelo valor do Gersão'))
            widget.claim.onClick = function() PartyLoot.send('claim', { n = row.n }) end
        end
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
        label:setText(string.format(tr('Expira em %ds. Todos precisam aceitar.'), left))
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
