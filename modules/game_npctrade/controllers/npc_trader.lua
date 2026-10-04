function controllerNpcTrader:onOpenNpcTrade(items, currencyId, currencyName)
    local ui = controllerNpcTrader.ui
    if not ui or not ui:isVisible() then
        controllerNpcTrader:initNpcWindow()
    end
    local isNewSession = not controllerNpcTrader.isTradeOpen
    if isNewSession then
        controllerNpcTrader.isTradeOpen = true
        controllerNpcTrader.widthConsole = controllerNpcTrader.TRADE_CONSOLE_WIDTH
        controllerNpcTrader.buyItems = {}
        controllerNpcTrader.sellItems = {}
        controllerNpcTrader.currencyId = currencyId or controllerNpcTrader.DEFAULT_CURRENCY_ID
        controllerNpcTrader.currencyName = currencyName or controllerNpcTrader.DEFAULT_CURRENCY_NAME
    else
        if currencyId then
            controllerNpcTrader.currencyId = currencyId
        end
        if currencyName then
            controllerNpcTrader.currencyName = currencyName
        end
    end

    if items and type(items) == "table" then
        controllerNpcTrader.buyItems = {}
        controllerNpcTrader.sellItems = {}
        controllerNpcTrader.selectedItem = nil
        for _, itemData in ipairs(items) do
            local ptr = itemData[1]
            local name = itemData[2]
            local weight = itemData[3] / 100
            local buyPrice = itemData[4]
            local sellPrice = itemData[5]
            if buyPrice > 0 then
                table.insert(controllerNpcTrader.buyItems, {
                    ptr = ptr,
                    name = name,
                    weight = weight,
                    price = buyPrice,
                    count = 1
                })
            end
            if sellPrice > 0 then
                table.insert(controllerNpcTrader.sellItems, {
                    ptr = ptr,
                    name = name,
                    weight = weight,
                    price = sellPrice,
                    count = 1
                })
            end
        end
    end

    local currencyLabel = controllerNpcTrader:findWidget(".tradeCurrencyName")
    if currencyLabel then
        currencyLabel:setText(controllerNpcTrader.currencyName)
    end
    local currencyIcon = controllerNpcTrader:findWidget(".tradeCurrencyIcon")
    if currencyIcon then
        local item = Item.create(controllerNpcTrader.currencyId)
        if item then
            currencyIcon:setItem(item)
        else
            currencyIcon:setItemId(controllerNpcTrader.currencyId)
        end
    end

    if isNewSession then
        -- Initial State
        local initialMode = controllerNpcTrader.BUY
        if #controllerNpcTrader.buyItems > 0 then
            initialMode = controllerNpcTrader.BUY
        elseif #controllerNpcTrader.sellItems > 0 then
            initialMode = controllerNpcTrader.SELL
        end

        controllerNpcTrader.tradeMode = initialMode
        controllerNpcTrader.searchText = ""
        controllerNpcTrader.itemBatchSize = controllerNpcTrader.ITEM_BATCH_SIZE
        controllerNpcTrader.loadedItems = 0
        controllerNpcTrader.currentList = {}

        -- Settings & Sorting
        controllerNpcTrader.sortBy = controllerNpcTrader.DEFAULT_SORT_BY
        controllerNpcTrader.ignoreCapacity = controllerNpcTrader.DEFAULT_IGNORE_CAPACITY
        controllerNpcTrader.buyWithBackpack = controllerNpcTrader.DEFAULT_BUY_WITH_BACKPACK
        controllerNpcTrader.ignoreEquipped = controllerNpcTrader.DEFAULT_IGNORE_EQUIPPED

        controllerNpcTrader:setTradeMode(initialMode)
    else
        controllerNpcTrader.allTradeItems = (controllerNpcTrader.tradeMode == controllerNpcTrader.BUY) and
                                                controllerNpcTrader.buyItems or controllerNpcTrader.sellItems
        controllerNpcTrader:filterTradeList(controllerNpcTrader.searchText or "")
        controllerNpcTrader:refreshPlayerGoods(true)
    end
end

function controllerNpcTrader:setTradeMode(mode)
    self.tradeMode = mode
    self.selectedItem = nil

    local buyTab = self:findWidget("#tabBuy")
    local sellTab = self:findWidget("#tabSell")

    -- both tabs stay clickable: the active one is marked by its colour
    if buyTab then
        buyTab:setOn(mode == controllerNpcTrader.BUY)
        buyTab:setColor(mode == controllerNpcTrader.BUY and '#f2c94c' or '#8a8a8a')
    end
    if sellTab then
        sellTab:setOn(mode == controllerNpcTrader.SELL)
        sellTab:setColor(mode == controllerNpcTrader.SELL and '#f2c94c' or '#8a8a8a')
    end
    local toggleButton = self:findWidget("#toggleButton")
    if toggleButton then
        toggleButton:setText(mode == controllerNpcTrader.BUY and "Buy" or "Sell")
    end

    self.shouldFocusFirst = true
    self:updateListSource()
    self:refreshPlayerGoods(true)
end

function controllerNpcTrader:updateListSource()
    if self.tradeMode == controllerNpcTrader.BUY then
        self.allTradeItems = self.buyItems
    else
        self.allTradeItems = self.sellItems
    end
    self:filterTradeList(self.searchText or "")
end

function controllerNpcTrader:loadNextBatch()
    if not self.currentList then
        return
    end

    local total = #self.currentList
    local current = self.loadedItems
    if current >= total then
        return
    end

    local limit = math.min(total, current + self.itemBatchSize)
    for i = current + 1, limit do
        table.insert(self.tradeItems, self.currentList[i])
    end
    self.loadedItems = limit
end

function controllerNpcTrader:onTradeScroll(widget, offset)
    if self.loadedItems >= #self.currentList then
        return
    end
    local rowHeight = controllerNpcTrader.ITEM_ROW_HEIGHT
    local contentHeight = self.loadedItems * rowHeight
    local viewportHeight = widget:getHeight()
    local maxScroll = math.max(0, contentHeight - viewportHeight)
    local value = offset.y
    if value >= maxScroll - controllerNpcTrader.SCROLL_THRESHOLD then
        self:loadNextBatch()
    end
end

-- The reactive *for engine repaints each row's data in place via __for_values on
-- reorder but never physically moves widgets (watchlist.lua: "no move callbacks"),
-- and the one-shot *trade-item attribute is not re-evaluated. So child.tradeItem
-- goes stale once the sell list re-sorts and the row shown no longer matches the
-- one clicked. The live item is always __for_values[1]; child.tradeItem is a fallback.
function controllerNpcTrader:getRowItem(child)
    return (child.__for_values and child.__for_values[1]) or child.tradeItem
end

function controllerNpcTrader:onTradeListRendered()
    local list = self:findWidget("#tradeListScroll")
    if list then
        if not list.onScrollEventConnected then
            list.onScrollChange = function(widget, offset)
                self:onTradeScroll(widget, offset)
            end
            list.onScrollEventConnected = true
        end
        local equippedCounts = self:getEquippedCounts()
        for i = 1, list:getChildCount() do
            local child = list:getChildByIndex(i)
            local item = self:getRowItem(child)
            if item then
                local canTrade = self:canTradeItem(item, equippedCounts)
                local nameLabel = child:recursiveGetChildById("nameLabel")
                local infoLabel = child:recursiveGetChildById("infoLabel")
                if nameLabel then
                    nameLabel:setColor(canTrade and '#e8e8e8' or '#7a7a7a')
                end
                if infoLabel then
                    infoLabel:setColor(canTrade and '#f2c94c' or '#86744a')
                end
                local sideLabel = child:recursiveGetChildById("sideLabel")
                if sideLabel then
                    sideLabel:setColor(self.tradeMode == controllerNpcTrader.SELL and '#9fd16b' or '#8c8c8c')
                end

                child.onMouseRelease = function(widget, mousePos, mouseButton)
                    -- resolve live at click time: the row may have been repainted
                    -- to a different item since this handler was bound.
                    self:onTradeItemMouseRelease(self:getRowItem(widget), widget, mousePos, mouseButton)
                end
            end
        end
        if self.shouldFocusFirst then
            local firstChild = list:getChildByIndex(1)
            if firstChild then
                self:selectTradeItem(self.tradeItems[1], firstChild)
            end
            self.shouldFocusFirst = false
        elseif self.selectedItem then
            for i = 1, list:getChildCount() do
                local child = list:getChildByIndex(i)
                if self:getRowItem(child) == self.selectedItem then
                    child:focus()
                    break
                end
            end
        end
    end
end

function controllerNpcTrader:onTradeItemMouseRelease(item, widget, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption("Look", function()
            g_game.inspectNpcTrade(item.ptr)
        end)
        menu:addOption("Inspect", function()
            g_game.inspectionObject(InspectObjectTypes.INSPECT_CYCLOPEDIA, item.ptr:getId())
        end)
        menu:display(mousePos)
        return true
    elseif mouseButton == MouseLeftButton then
        self:selectTradeItem(item, widget)
        return true
    end
    return false
end

function controllerNpcTrader:selectTradeItem(item, widget)
    self.selectedItem = item
    if widget then
        widget:focus()
    end

    -- When selling, default the amount to the full sellable stack (mirrors the
    -- legacy NPC window) so a single Sell dumps everything. Buying stays at 1.
    local defaultAmount = 1
    if item and self.tradeMode == controllerNpcTrader.SELL then
        defaultAmount = math.max(1, self:getSellQuantity(item.ptr))
    end
    self:updateAmount(defaultAmount)

    local scroll = self:findWidget("#amountScrollBar")
    if scroll then
        scroll:enable()
        scroll:setValue(self.amount)
    end
end

function controllerNpcTrader:updateAmount(amount)
    amount = tonumber(amount) or 1
    if self.selectedItem then
        local maxAmount = controllerNpcTrader.MAX_AMOUNT_NORMAL
        local minAmount = controllerNpcTrader.MIN_AMOUNT
        if self.tradeMode == controllerNpcTrader.BUY then
            local playerMoney = self:getPlayerMoney()
            local maxByMoney = math.floor(playerMoney / self.selectedItem.price)
            local maxByCapacity = controllerNpcTrader.MAX_AMOUNT_NORMAL
            if not self.ignoreCapacity then
                local player = g_game.getLocalPlayer()
                local freeCapacity = player and player:getFreeCapacity() or 0
                local itemWeight = tonumber(self.selectedItem.weight) or 0
                maxByCapacity = itemWeight > 0 and math.floor(freeCapacity / itemWeight) or maxByCapacity
            end
            maxAmount = math.max(minAmount, math.min(controllerNpcTrader.MAX_AMOUNT_NORMAL, maxByMoney, maxByCapacity))
            if self.selectedItem.ptr and self.selectedItem.ptr:isStackable() then
                maxAmount = math.max(minAmount,
                    math.min(controllerNpcTrader.MAX_AMOUNT_STACKABLE, maxByMoney, maxByCapacity))
            end
        else
            local sellable = self:getSellQuantity(self.selectedItem.ptr)
            minAmount = sellable > 0 and controllerNpcTrader.MIN_AMOUNT or 0
            maxAmount = math.max(minAmount, sellable)
        end
        if amount > maxAmount then
            amount = maxAmount
        end
        if amount < minAmount then
            amount = minAmount
        end
        local scroll = self:findWidget("#amountScrollBar")
        if scroll then
            scroll:setMaximum(maxAmount)
            scroll:setMinimum(minAmount)
            if scroll:getValue() ~= amount then
                scroll:setValue(amount)
            end
        end
    end
    self.amount = amount
    if self.selectedItem then
        self.totalPrice = self.selectedItem.price * amount
        self.totalWeight = string.format("%.2f", self.selectedItem.weight * amount)
    else
        self.totalPrice = 0
        self.totalWeight = "0.00"
    end
end

function controllerNpcTrader:onAmountScrollBarChange(value)
    self:updateAmount(value)
end

function controllerNpcTrader:onAmountInputChange(event)
    local input = event.target
    local text = input:getText()
    local cleanText = text:gsub("[^%d]", "")
    if cleanText ~= text then
        input:setText(cleanText)
        text = cleanText
    end
    if text == "" then
        text = "1"
    end
    local amount = tonumber(text) or 1
    self:updateAmount(amount)
    local scroll = self:findWidget("#amountScrollBar")
    if scroll then
        if amount ~= self.amount then
            input:setText(tostring(self.amount))
        end
        scroll:setValue(self.amount)
    end
end

function controllerNpcTrader:getPlayerMoney()
    if self.playerMoney ~= nil then
        return self.playerMoney
    end
    local player = g_game.getLocalPlayer()
    if not player then
        return 0
    end
    return player:getTotalMoney()
end

-- Equipped items with an active imbuement are already excluded from the goods
-- count the server sends (Item::hasMarketAttributes), so subtracting them again
-- here would hide sellable copies the player carries in containers.
function controllerNpcTrader:onUpdateEquippedImbuements(items)
    local counts = {}
    for _, entry in ipairs(items or {}) do
        local ptr = entry.item
        if ptr then
            local hasActiveImbuement = false
            for _, slot in pairs(entry.slots or {}) do
                if slot.duration and slot.duration > 0 then
                    hasActiveImbuement = true
                    break
                end
            end
            if hasActiveImbuement then
                local id = ptr:getId()
                counts[id] = (counts[id] or 0) + ptr:getCount()
            end
        end
    end
    self.equippedImbuedCounts = counts

    if self:isLegacyMode() then
        refreshPlayerGoods()
    elseif self.isTradeOpen then
        self:refreshPlayerGoods()
    end
end

function controllerNpcTrader:getEquippedImbuedCount(itemId)
    return (self.equippedImbuedCounts and self.equippedImbuedCounts[itemId]) or 0
end

function controllerNpcTrader:startEquippedImbuementsTracking()
    self.equippedImbuedCounts = {}
    if g_game.getClientVersion() >= 1100 then
        g_game.imbuementDurations(true)
    end
end

function controllerNpcTrader:stopEquippedImbuementsTracking()
    self.equippedImbuedCounts = {}
    if g_game.getClientVersion() < 1100 or not g_game.isOnline() then
        return
    end
    local tracker = modules.game_imbuementtracker
    local trackerOn = tracker and tracker.imbuementTrackerButton and tracker.imbuementTrackerButton:isOn() or false
    g_game.imbuementDurations(trackerOn)
end

-- count of each id_subType in the equipment slots, read once per call site
function controllerNpcTrader:getEquippedCounts()
    local counts = {}
    local player = g_game.getLocalPlayer()
    if not player then
        return counts
    end
    for i = 1, 10 do
        local item = player:getInventoryItem(i)
        if item then
            local key = item:getId() .. "_" .. item:getSubType()
            counts[key] = (counts[key] or 0) + item:getCount()
        end
    end
    return counts
end

function controllerNpcTrader:getSellQuantity(itemPtr, equippedCounts)
    if not itemPtr then
        return 0
    end
    local id = itemPtr:getId()
    local key = id .. "_" .. itemPtr:getSubType()
    local inventoryTotal = self.playerItems and self.playerItems[key] or 0
    if inventoryTotal == 0 then
        return 0
    end

    if self.ignoreEquipped then
        equippedCounts = equippedCounts or self:getEquippedCounts()
        local equippedCount = math.max(0, (equippedCounts[key] or 0) - self:getEquippedImbuedCount(id))
        return math.max(0, inventoryTotal - equippedCount)
    end

    return inventoryTotal
end

-- 52131501 -> 52,131,501
function controllerNpcTrader:formatGold(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    local formatted = text:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (formatted:gsub('^,', ''))
end

-- the server sends some names capitalised and some not: show them all alike
function controllerNpcTrader:displayName(item)
    local name = item and item.name or ''
    return short_text(name:sub(1, 1):upper() .. name:sub(2), 22)
end

-- right side of a row: how many the player carries when selling, the
-- weight when buying
function controllerNpcTrader:sideText(item)
    if not item then
        return ''
    end
    if self.tradeMode == controllerNpcTrader.SELL then
        local quantity = self:getSellQuantity(item.ptr)
        return quantity > 0 and ('you have ' .. quantity) or ''
    end
    return item.weight .. ' oz'
end

function controllerNpcTrader:canTradeItem(item, equippedCounts)
    if self.tradeMode == controllerNpcTrader.BUY then
        local playerMoney = self:getPlayerMoney()
        -- Add capacity check if needed, but for now we'll just check price
        return playerMoney >= item.price
    else
        return self:getSellQuantity(item.ptr, equippedCounts) > 0
    end
end

function controllerNpcTrader:onPlayerGoods(money, items)
    if not items or type(items) ~= "table" then
        return
    end
    self.playerMoney = money
    local newPlayerItems = {}
    for _, itemData in ipairs(items) do
        local ptr = itemData[1]
        local key = ptr:getId() .. "_" .. ptr:getSubType()
        local count = itemData[2]
        newPlayerItems[key] = (newPlayerItems[key] or 0) + count
    end
    self.playerItems = newPlayerItems
    -- every sale sends a new goods list; a Sell All of many items sends one
    -- per item, so rebuild the list once after they stop coming
    if self.goodsRefreshEvent then
        removeEvent(self.goodsRefreshEvent)
    end
    self.goodsRefreshEvent = scheduleEvent(function()
        self.goodsRefreshEvent = nil
        if self.isTradeOpen then
            self:refreshPlayerGoods()
        end
    end, 100)
end

function controllerNpcTrader:refreshPlayerGoods(skipFilter)
    local money = self:getPlayerMoney()
    local display = self:findWidget("#playerMoneyDisplay")
    if display then
        display:setText(self:formatGold(money))
    end
    if not skipFilter and self.tradeMode == controllerNpcTrader.SELL then
        self:filterTradeList(self.searchText or "")
    end
    if self.selectedItem then
        self:updateAmount(self.amount)
    end
end

function controllerNpcTrader:executeTrade()
    if not self.selectedItem then
        return
    end
    if self.tradeMode == controllerNpcTrader.BUY then
        g_game.buyItem(self.selectedItem.ptr, self.amount, self.ignoreCapacity, self.buyWithBackpack)
    else
        g_game.sellItem(self.selectedItem.ptr, self.amount, self.ignoreEquipped)
    end
end

function controllerNpcTrader:clearSearch()
    local input = self:findWidget(".tradeSearchInput")
    if input then
        input:setText("")
        self:filterTradeList("")
    end
end

function controllerNpcTrader:filterTradeList(searchText)
    if not self.allTradeItems then
        return
    end

    self.searchText = searchText
    local lowerSearch = searchText:lower()
    local filteredItems = {}

    for _, item in ipairs(self.allTradeItems) do
        local includeItem = true
        if searchText ~= "" and not item.name:lower():find(lowerSearch, 1, true) then
            includeItem = false
        end

        if includeItem then
            table.insert(filteredItems, item)
        end
    end

    if self.tradeMode == controllerNpcTrader.SELL then
        -- big shops (Gersao buys ~1700 items): work out each quantity once,
        -- not twice per comparison of the sort
        local equippedCounts = self:getEquippedCounts()
        local quantity = {}
        for _, item in ipairs(filteredItems) do
            quantity[item] = self:getSellQuantity(item.ptr, equippedCounts)
        end
        table.sort(filteredItems, function(a, b)
            local qtyA = quantity[a]
            local qtyB = quantity[b]
            if qtyA ~= qtyB then
                return qtyA > qtyB
            end
            if self.sortBy == 'price' then
                return a.price > b.price
            elseif self.sortBy == 'weight' then
                return a.weight > b.weight
            else
                return a.name:lower() < b.name:lower()
            end
        end)
    else
        self:sortTradeItems(filteredItems)
    end

    self.currentList = filteredItems
    self.tradeItems = {}
    self.loadedItems = 0
    self:loadNextBatch()

    if #self.currentList > 0 then
        local found = false
        if self.selectedItem then
            for _, item in ipairs(self.currentList) do
                if item == self.selectedItem then
                    found = true;
                    break
                end
            end
        end
        -- When selling, don't keep a selection that has nothing left to sell:
        -- advance to the top of the re-sorted list (highest remaining stock) so
        -- spamming Sell drains each stack and moves on to the next sellable item.
        if found and self.tradeMode == controllerNpcTrader.SELL and self.selectedItem
                and self:getSellQuantity(self.selectedItem.ptr) <= 0 then
            found = false
        end
        if not found then
            self:selectTradeItem(self.tradeItems[1])
        end
    else
        self.selectedItem = nil
        self:updateAmount(0)
    end
end

-- the server sells every item of the loot pouch the NPC buys in one go when
-- it is asked to sell the pouch itself; rarity, tiered and imbued items stay
local LOOT_POUCH_ID = 23721

function controllerNpcTrader:sellLoot()
    local pouch = Item.create(LOOT_POUCH_ID)
    if pouch then
        g_game.sellItem(pouch, 1, self.ignoreEquipped)
    end
end

function controllerNpcTrader:confirmSellLoot()
    if self.sellLootBox then
        return
    end
    local function close()
        if self.sellLootBox then
            self.sellLootBox:destroy()
            self.sellLootBox = nil
        end
    end
    local function yes()
        close()
        self:sellLoot()
    end
    self.sellLootBox = displayGeneralBox(tr('Sell loot'),
        tr('Sell everything in your loot pouch that this NPC buys?\nRarity items stay in the pouch.'),
        { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = close } }, yes, close)
end

function controllerNpcTrader:sellAll(delayed, exceptions)
    if type(delayed) == "table" then
        exceptions = delayed
        delayed = false
    end
    exceptions = exceptions or {}

    if self.sellAllWithDelayEvent then
        removeEvent(self.sellAllWithDelayEvent)
        self.sellAllWithDelayEvent = nil
    end

    local queue = {}
    if not self.sellItems or #self.sellItems == 0 then
        return
    end

    local equippedCounts = self:getEquippedCounts()
    for _, entry in ipairs(self.sellItems or {}) do
        local id = entry.ptr:getId()
        if not table.find(exceptions, id) then
            local sellQuantity = self:getSellQuantity(entry.ptr, equippedCounts)
            while sellQuantity > 0 do
                local maxPossible = g_game.getFeature(GameDoubleShopSellAmount) and 10000 or 100
                local maxAmount = math.min(sellQuantity, maxPossible)

                if delayed then
                    g_game.sellItem(entry.ptr, maxAmount, self.ignoreEquipped)
                    self.sellAllWithDelayEvent = scheduleEvent(function()
                        self:sellAll(true, exceptions)
                    end, 1100)
                    return
                end

                table.insert(queue, {entry.ptr, maxAmount, self.ignoreEquipped})
                sellQuantity = sellQuantity - maxAmount
            end
        end
    end

    for _, entry in ipairs(queue) do
        g_game.sellItem(entry[1], entry[2], entry[3])
    end
end
