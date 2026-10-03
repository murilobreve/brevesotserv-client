-- Rarity Market: buy and sell the rarity items that drop from monsters.
-- Talks to the server script custom_market.lua through extended opcode
-- MARKET_OPCODE with JSON payloads; every rule (ownership, prices, races)
-- is enforced on the server, this window only displays and asks.

local MARKET_OPCODE = 120
local FRAME_SIZE = 34

-- one entry per rarity grade the server writes into rar_rarity
local RARITIES = {
    none      = { label = 'Common',    color = '#c8c8c8', badge = '#e6e6e6', frame = 0 },
    uncommon  = { label = 'Communis',  color = '#3ddc2e', badge = '#a6ff9a', frame = 1 },
    rare      = { label = 'Rarus',     color = '#3d9bff', badge = '#b0d6ff', frame = 2 },
    epic      = { label = 'Praeclarus',color = '#b45cff', badge = '#e2c2ff', frame = 3 },
    legendary = { label = 'Legendarius',color = '#ff9a1f', badge = '#ffd49a', frame = 4 },
    mythic    = { label = 'Mythicus',  color = '#66f0ff', badge = '#dffbff', frame = 5 },
}

local ELEMENT_COLORS = {
    Igneus = '#ff6a3d',
    Terrenus = '#8bc34a',
    Fulmineus = '#b388ff',
    Glacialis = '#4dd0e1',
    Sacer = '#ffe082',
    Mortifer = '#b07ad8',
    Corporalis = '#b0bec5',
}

local CATEGORIES = {
    { key = nil, label = 'All Types' },
    { key = 'weapon', label = 'Weapons' },
    { key = 'shield', label = 'Shields' },
    { key = 'armor', label = 'Armor' },
    { key = 'other', label = 'Other' },
}

local RARITY_FILTERS = {
    { key = nil, label = 'All Rarities' },
    { key = 'uncommon', label = 'Communis' },
    { key = 'rare', label = 'Rarus' },
    { key = 'epic', label = 'Praeclarus' },
    { key = 'legendary', label = 'Legendarius' },
    { key = 'mythic', label = 'Mythicus' },
}

local SORTS = {
    { key = 'newest', label = 'Newest first' },
    { key = 'price_asc', label = 'Lowest price' },
    { key = 'price_desc', label = 'Highest price' },
    { key = 'oldest', label = 'Oldest first' },
}

local window
local marketButton
local currentTab = 'browse'
local selected -- { kind = 'offer'|'sell'|'own'|'sold', data = <entry> }
local browseState = { page = 1, pages = 1 }
local searchEvent
local maxPrice = 999999999

local function formatNumber(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    while true do
        local replaced, count = text:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
        text = replaced
        if count == 0 then
            break
        end
    end
    return text
end

local function rarityOf(key)
    return RARITIES[key or 'none'] or RARITIES.none
end

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(MARKET_OPCODE, data)
    end
end

local function setStatus(text, ok)
    if not window then
        return
    end
    window.status:setText(text or '')
    window.status:setColor(ok == false and '#ff6464' or '#7fd35a')
end

local function applyFrame(frame, entry, size)
    local rarity = rarityOf(entry.rarity)
    frame:setImageClip(string.format('%d 0 %d %d', rarity.frame * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE))
    local itemWidget = frame.item
    local item = Item.create(entry.itemId, 1)
    if entry.shader and entry.shader ~= '' then
        item:setShader(entry.shader)
    end
    itemWidget:setItem(item)
    if size then
        itemWidget:setSize({ width = size, height = size })
    end
    if ItemsDatabase and ItemsDatabase.setFrameGems then
        local tags = {}
        for _, tag in ipairs(entry.tags or {}) do
            if #tags < 2 and ItemsDatabase.elementColors[tag] then
                table.insert(tags, tag)
            end
        end
        ItemsDatabase.setFrameGems(frame, tags)
    end
end

local function shorten(text, maxLen)
    if #text <= maxLen then
        return text
    end
    return text:sub(1, maxLen - 3) .. '...'
end

local function affixSummary(entry)
    if entry.lines and #entry.lines > 0 then
        return table.concat(entry.lines, ', ')
    end
    return rarityOf(entry.rarity).label
end

-- ---------------------------------------------------------------- details

local function clearDetails()
    selected = nil
    if not window then
        return
    end
    window.details.content:setVisible(false)
    window.details.placeholder:setVisible(true)
end

local function showDetails(kind, entry)
    selected = { kind = kind, data = entry }
    local details = window.details
    local content = details.content
    details.placeholder:setVisible(false)
    content:setVisible(true)

    local rarity = rarityOf(entry.rarity)
    applyFrame(content.bigFrame, entry, 64)

    content.name:setText(entry.name or '')
    content.name:setColor(rarity.color)

    -- pill badge: rarity-coloured text and outline on a soft tint of the same colour
    content.rarity:setText(rarity.label:upper())
    content.rarity:setColor(rarity.badge)
    content.rarity:setBorderColor(rarity.color)
    content.rarity:setBackgroundColor(rarity.color .. '40')

    if entry.odds and entry.odds ~= '' then
        content.odds:setText(tr('Odds: 1 in %s', formatNumber(entry.odds)))
    else
        content.odds:setText('')
    end

    local stats = {}
    if (entry.attack or 0) > 0 then
        table.insert(stats, tr('Attack %d', entry.attack))
    end
    if (entry.defense or 0) > 0 then
        table.insert(stats, tr('Defense %d', entry.defense))
    end
    if (entry.armor or 0) > 0 then
        table.insert(stats, tr('Armor %d', entry.armor))
    end
    if (entry.tier or 0) > 0 then
        table.insert(stats, tr('Tier %d', entry.tier))
    end
    if (entry.weight or 0) > 0 then
        table.insert(stats, string.format('%.2f oz', entry.weight / 100))
    end
    content.stats:setText(table.concat(stats, '   '))

    content.lines:destroyChildren()
    for _, line in ipairs(entry.lines or {}) do
        local label = g_ui.createWidget('AffixLine', content.lines)
        label:setText(line)
    end
    if #(entry.lines or {}) == 0 then
        local label = g_ui.createWidget('AffixLine', content.lines)
        label:setText(tr('No bonus attributes'))
        label:setColor('#8a8a8a')
    end

    if entry.tags and #entry.tags > 0 then
        local parts = {}
        for _, tag in ipairs(entry.tags) do
            table.insert(parts, string.format('[color=%s]%s[/color]', ELEMENT_COLORS[tag] or '#c0c0c0', tag))
        end
        content.tags:parseColoredText(string.format('[color=#b0b0b0]%s[/color] %s', tr('Essence:'), table.concat(parts, '  ')))
        content.tags:setVisible(true)
    else
        content.tags:setText('')
    end

    if entry.foundBy and entry.foundBy ~= '' then
        local text = tr('Found by %s', entry.foundBy)
        if entry.foundDate and entry.foundDate ~= '' then
            text = text .. ' ' .. tr('on %s', entry.foundDate)
        end
        content.found:setText(text)
    else
        content.found:setText('')
    end

    local isSell = kind == 'sell'
    content.priceEdit:setVisible(isSell)
    content.priceCaption:setVisible(isSell)
    content.price:setVisible(not isSell)
    content.priceGold:setVisible(not isSell)
    content.priceTitle:setVisible(not isSell)
    if not isSell then
        content.price:setText(formatNumber(entry.price))
    end

    local button = content.actionButton
    button:setVisible(true)
    button:setEnabled(true)
    if kind == 'offer' then
        content.seller:setText(tr('Seller: %s', entry.seller or ''))
        if entry.own then
            button:setText(tr('This is your listing'))
            button:setEnabled(false)
        else
            button:setText(tr('Buy'))
        end
    elseif kind == 'sell' then
        content.seller:setText(entry.location and entry.location ~= '' and tr('Carried in: %s', entry.location) or '')
        content.priceEdit:setText('')
        content.priceEdit:focus()
        button:setText(tr('List for sale'))
        button:setEnabled(false)
    elseif kind == 'own' then
        content.seller:setText(tr('Listed by you'))
        button:setText(tr('Cancel listing'))
    else
        content.seller:setText(tr('Sold'))
        button:setVisible(false)
    end
end

-- ---------------------------------------------------------------- lists

local function fillList(list, entries, kind, emptyLabel, emptyText)
    list:destroyChildren()
    local previousId = selected and selected.kind == kind and (selected.data.id or selected.data.token)
    local reselect
    for index, entry in ipairs(entries or {}) do
        local row = g_ui.createWidget(index % 2 == 0 and 'MarketRowEven' or 'MarketRow', list)
        local rarity = rarityOf(entry.rarity)
        applyFrame(row.frame, entry)
        row.name:setText(shorten(entry.name or '', 40))
        row.name:setColor(rarity.color)
        row.info:setText(shorten(affixSummary(entry), 48))
        row:setBackgroundColor(index % 2 == 1 and '#00000030' or '#00000000')
        if kind == 'sell' then
            row.price:setText(rarity.label)
            row.price:setColor(rarity.color)
            row.gold:setVisible(false)
            row.seller:setText(entry.location or '')
        else
            row.price:setText(formatNumber(entry.price))
            row.seller:setText(kind == 'offer' and (entry.seller or '') or '')
        end
        row.onFocusChange = function(widget, focused)
            if focused then
                showDetails(kind, entry)
            end
        end
        -- a list with one row focuses it as soon as it is created, before
        -- onFocusChange is set: clicking it then changes no focus
        row.onClick = function()
            if not selected or selected.data ~= entry then
                showDetails(kind, entry)
            end
        end
        if previousId and (entry.id or entry.token) == previousId then
            reselect = row
        end
    end
    if emptyLabel then
        emptyLabel:setVisible(#(entries or {}) == 0)
        if emptyText then
            emptyLabel:setText(emptyText)
        end
    end
    if reselect then
        list:focusChild(reselect, MouseFocusReason)
    elseif selected and selected.kind == kind then
        clearDetails()
    end
end

-- ---------------------------------------------------------------- requests

local function currentFilters()
    local panel = window.browsePanel
    return {
        action = 'browse',
        page = browseState.page,
        search = panel.searchEdit:getText(),
        category = panel.categoryBox:getCurrentOption().data,
        rarity = panel.rarityBox:getCurrentOption().data,
        sort = panel.sortBox:getCurrentOption().data,
    }
end

local function requestBrowse(resetPage)
    if resetPage then
        browseState.page = 1
    end
    send(currentFilters())
end

function changePage(delta)
    local page = browseState.page + delta
    if page < 1 or page > browseState.pages then
        return
    end
    browseState.page = page
    requestBrowse(false)
end

function onSearchChanged()
    if searchEvent then
        removeEvent(searchEvent)
    end
    searchEvent = scheduleEvent(function()
        searchEvent = nil
        requestBrowse(true)
    end, 450)
end

function selectTab(tab)
    currentTab = tab
    window.browseTab:setChecked(tab == 'browse')
    window.sellTab:setChecked(tab == 'sell')
    window.myTab:setChecked(tab == 'my')
    window.browsePanel:setVisible(tab == 'browse')
    window.sellPanel:setVisible(tab == 'sell')
    window.myPanel:setVisible(tab == 'my')
    clearDetails()
    setStatus('')
    if tab == 'browse' then
        requestBrowse(false)
    elseif tab == 'sell' then
        send({ action = 'sellList' })
    else
        send({ action = 'myOffers' })
    end
end

local function parsePrice()
    local text = window.details.content.priceEdit:getText():gsub('[^%d]', '')
    return tonumber(text)
end

function onPriceChanged()
    if not selected or selected.kind ~= 'sell' then
        return
    end
    local price = parsePrice()
    window.details.content.actionButton:setEnabled(price ~= nil and price > 0 and price <= maxPrice)
end

local confirmBox

local function confirm(title, message, callback)
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
    local function yes()
        confirmBox:destroy()
        confirmBox = nil
        callback()
    end
    local function no()
        confirmBox:destroy()
        confirmBox = nil
    end
    confirmBox = displayGeneralBox(title, message, {
        { text = tr('Yes'), callback = yes },
        { text = tr('No'), callback = no },
        anchor = AnchorHorizontalCenter,
    }, yes, no)
end

function onAction()
    if not selected then
        return
    end
    local entry = selected.data
    if selected.kind == 'offer' then
        confirm(tr('Confirm purchase'), tr('Buy %s for %s gold?\nThe gold is taken from your bank balance.', entry.name, formatNumber(entry.price)), function()
            send({ action = 'buy', id = entry.id })
        end)
    elseif selected.kind == 'sell' then
        local price = parsePrice()
        if not price or price <= 0 then
            return
        end
        confirm(tr('Confirm listing'), tr('List %s for %s gold?\nThe item leaves your inventory until it sells or you cancel the listing.', entry.name, formatNumber(price)), function()
            send({ action = 'sell', token = entry.token, price = price })
        end)
    elseif selected.kind == 'own' then
        confirm(tr('Cancel listing'), tr('Cancel the listing of %s and get the item back?', entry.name), function()
            send({ action = 'cancel', id = entry.id })
        end)
    end
end

-- ---------------------------------------------------------------- server

local function setBank(amount)
    if window then
        window.bankLabel:setText(tr('Bank: %s', formatNumber(amount)))
    end
end

local handlers = {}

function handlers.open(data)
    maxPrice = data.maxPrice or maxPrice
    setBank(data.bank)
    show()
    currentTab = 'browse'
    window.browseTab:setChecked(true)
    window.sellTab:setChecked(false)
    window.myTab:setChecked(false)
    window.browsePanel:setVisible(true)
    window.sellPanel:setVisible(false)
    window.myPanel:setVisible(false)
end

function handlers.balance(data)
    setBank(data.bank)
end

function handlers.browse(data)
    browseState.page = data.page or 1
    browseState.pages = data.pages or 1
    local panel = window.browsePanel
    local total = data.total or 0
    fillList(panel.offersList, data.offers, 'offer', panel.offersEmpty,
        (panel.searchEdit:getText() ~= '' or panel.categoryBox:getCurrentIndex() > 1 or panel.rarityBox:getCurrentIndex() > 1)
        and tr('No offers match your filters.') or tr('No items are for sale right now.'))
    panel.pageLabel:setText(tr('Page %d of %d  (%d offers)', browseState.page, browseState.pages, total))
    panel.prevPage:setEnabled(browseState.page > 1)
    panel.nextPage:setEnabled(browseState.page < browseState.pages)
end

function handlers.sellList(data)
    fillList(window.sellPanel.sellList, data.items, 'sell', window.sellPanel.sellEmpty)
end

function handlers.myOffers(data)
    local panel = window.myPanel
    fillList(panel.activeList, data.active, 'own', panel.activeEmpty)
    fillList(panel.soldList, data.sold, 'sold', panel.soldEmpty)
end

function handlers.result(data)
    setStatus(data.message, data.ok)
    if data.ok then
        clearDetails()
    end
    if data.refresh == 'browse' and currentTab == 'browse' then
        requestBrowse(false)
    end
end

local function onMarketOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    local handler = handlers[data.action]
    if handler and window then
        handler(data)
    end
end

-- ---------------------------------------------------------------- window

local function setupCombo(combo, options)
    combo:clearOptions()
    for _, option in ipairs(options) do
        combo:addOption(tr(option.label), option.key)
    end
    combo:setCurrentIndex(1, true)
    combo.onOptionChange = function()
        requestBrowse(true)
    end
end

function show()
    if not window then
        return
    end
    window:show()
    window:raise()
    window:focus()
    if marketButton then
        marketButton:setOn(true)
    end
end

function hide()
    if not window then
        return
    end
    window:hide()
    if marketButton then
        marketButton:setOn(false)
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
        send({ action = 'open' })
    end
end

local function onGameStart()
    if not marketButton and modules.game_mainpanel then
        marketButton = modules.game_mainpanel.addToggleButton('rarityMarketButton', tr('Rarity Market'),
            '/game_raritymarket/images/button', toggle, false, 20)
    end
end

local function onGameEnd()
    hide()
    clearDetails()
end

function init()
    window = g_ui.displayUI('raritymarket')
    window:hide()

    setupCombo(window.browsePanel.categoryBox, CATEGORIES)
    setupCombo(window.browsePanel.rarityBox, RARITY_FILTERS)
    setupCombo(window.browsePanel.sortBox, SORTS)
    window.details.content.priceEdit.onEnter = onAction
    window.browsePanel.searchEdit.onEnter = function()
        requestBrowse(true)
    end
    setBank(0)

    ProtocolGame.registerExtendedJSONOpcode(MARKET_OPCODE, onMarketOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedJSONOpcode(MARKET_OPCODE)
    if searchEvent then
        removeEvent(searchEvent)
        searchEvent = nil
    end
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
    if marketButton then
        marketButton:destroy()
        marketButton = nil
    end
    if window then
        window:destroy()
        window = nil
    end
end
