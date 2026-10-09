QuickLoot = {}

local function getFilter(id)
    local filter = {
        [1] = 0,
        [2] = 1
    }
    return filter[id]
end

-- Gersao's buy prices (server scripts/quickloot/loot_prices.lua), for the
-- "take everything Gersao buys for at least X gold" rule
LOOT_PRICES_OPCODE = 124

quickLootController = Controller:new()
quickLootController:setUI('quickloot')
function quickLootController:onInit()

    QuickLoot.Define()

    QuickLoot.data = {
        filter = 1,
        loots = {
            [0] = {},
            {}
        }
    }

    quickLootController.ui:hide()

    quickLootController:registerEvents(g_game, {
        onQuickLootContainers = QuickLoot.start,
        onTextMessage = QuickLoot.onTextMessage
    })
    ProtocolGame.registerExtendedJSONOpcode(LOOT_PRICES_OPCODE, QuickLoot.onPrices)
    Keybind.new("Loot", "Quick Loot Nearby Corpses", "Alt+Q", "")
    Keybind.bind("Loot", "Quick Loot Nearby Corpses", {
      {
        type = KEY_DOWN,
        callback = function() g_game.sendQuickLoot(2) end,
      }
    })

end

function quickLootController:onTerminate()
    Keybind.delete("Loot", "Quick Loot Nearby Corpses")
    ProtocolGame.unregisterExtendedJSONOpcode(LOOT_PRICES_OPCODE)
    if QuickLoot.mouseGrabberWidget then
        QuickLoot.mouseGrabberWidget:destroy()
        QuickLoot.mouseGrabberWidget = nil
    end

    QuickLoot = {}
end

function quickLootController:onGameStart()
    if not g_game.getFeature(GameThingQuickLoot) then
        return
    end
    if not QuickLoot.mouseGrabberWidget then
        QuickLoot.mouseGrabberWidget = g_ui.createWidget("UIWidget")
    end
    QuickLoot.mouseGrabberWidget:setVisible(false)
    QuickLoot.mouseGrabberWidget:setFocusable(false)

    QuickLoot.mouseGrabberWidget.onMouseRelease = QuickLoot.onChooseItem
    QuickLoot.lastSelectBag = nil
    QuickLoot.ErrorWindow = nil

    local player = g_game.getLocalPlayer()
    quickLootController.ui.information.vipPanel.premium:setOn(not (player and player:isPremium()))
    QuickLoot.load()
    QuickLoot.searchText = ''
    QuickLoot.prices = nil
    QuickLoot.requestPrices()
    QuickLoot.refreshPriceRule()

    if modules.game_brevespanel and modules.game_brevespanel.addFeature then
        modules.game_brevespanel.addFeature('loot', QuickLoot.toggle)
    end

    QuickLoot.sendList()
end

function quickLootController:onGameEnd()
    if not g_game.getFeature(GameThingQuickLoot) then
        return
    end
    QuickLoot.save()
    QuickLoot.toggle()
    if quickLootController.ui:isVisible() then
        quickLootController.ui:hide()
    end
end

function QuickLoot.Define()
    function QuickLoot.filter(widget, isChecked)
        widget:setChecked(true)

        isChecked = true

        local accepted = quickLootController.ui.filters.accepted
        local skipped = quickLootController.ui.filters.skipped
        local add_text = tr("Search an item")
        local clear_text = string.format("Clear %s Loot List", widget:getId():gsub("^%l", string.upper))

        if widget == skipped and isChecked then
            quickLootController.ui.filters.accepted:setChecked(false)
            quickLootController.ui.filters.add:setText(add_text)
            quickLootController.ui.filters.clear:setText(clear_text)

            QuickLoot.data.filter = 1
        end

        if widget == accepted and isChecked then
            quickLootController.ui.filters.skipped:setChecked(false)
            quickLootController.ui.filters.add:setText(add_text)
            quickLootController.ui.filters.clear:setText(clear_text)

            QuickLoot.data.filter = 2
        end

        QuickLoot.sendList()
        QuickLoot.loadFilterItems()
    end

    function QuickLoot.lootExists(itemId, filter)
        if not filter then
            filter = QuickLoot.data.filter
        end
        return table.contains(QuickLoot.data.loots[filter], itemId)
    end

    function QuickLoot.addLootList(itemId,filter)
        if not filter then
            filter = QuickLoot.data.filter
        end
        if table.contains(QuickLoot.data.loots[filter], itemId) then
            return
        end

        table.insert(QuickLoot.data.loots[filter], itemId)

        QuickLoot.sendList()
        if quickLootController.ui:isVisible() then
            QuickLoot.loadFilterItems()
        end
    end
    function QuickLoot.clearFilterItems()
        if QuickLoot.priceRuleActive() then
            local rule = QuickLoot.priceRule()
            rule.take = {}
            rule.skip = {}
            QuickLoot.sendList()
            QuickLoot.loadFilterItems()
            return
        end
        QuickLoot.data.loots[QuickLoot.data.filter] = {}

        QuickLoot.sendList()
        QuickLoot.loadFilterItems()
    end

    function QuickLoot.removeLootList(itemId, filter)
        if not filter then
            filter = QuickLoot.data.filter
        end
        if not table.contains(QuickLoot.data.loots[filter], itemId) then
            return
        end

        table.removevalue(QuickLoot.data.loots[filter], itemId)

        QuickLoot.sendList()
        if quickLootController.ui:isVisible() then
            QuickLoot.loadFilterItems()
        end
    end

    function QuickLoot.load()
        local player = g_game.getLocalPlayer()
        if not player then
            return
        end
        local file = string.format("/settings/%s_containers.json",
            player:getName():lower():gsub("%s+", "_"))

        if g_resources.fileExists(file) then
            local status, result = pcall(function()
                return json.decode(g_resources.readFileContents(file))
            end)

            if not status then
                return g_logger.error("Error while reading containers settings file. " .. result)
            end

            if result == nil then
                QuickLoot.data = {
                    filter = 1,
                    loots = {{}, {}}
                }
            else
                QuickLoot.data = result
            end

        else
            QuickLoot.data = {
                filter = 1,
                loots = {{}, {}}
            }
        end
    end

    function QuickLoot.save()
        local file = string.format("/settings/%s_containers.json",
            g_game.getLocalPlayer():getName():lower():gsub("%s+", "_"))
        local status, result = pcall(function()
            return json.encode(QuickLoot.data, 2)
        end)

        if not status then
            return g_logger.warning("Error while saving QuickLoot settings. Data won't be saved. Details: " .. result)
        end

        if result:len() > 104857600 then
            return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
        end

        -- Safely attempt to write the file, ignoring errors during logout
        local writeStatus, writeError = pcall(function()
            return g_resources.writeFileContents(file, result)
        end)
        
        if not writeStatus then
            -- Log the error but don't spam the console during normal logout
            g_logger.debug("Could not save QuickLoot settings during logout: " .. tostring(writeError))
        end
    end

    function QuickLoot.start(quickLootFallbackToMainContainer, lootContainers)
        local player = g_game.getLocalPlayer()
        local vipPanel = quickLootController.ui.information.vipPanel
        local loots = lootContainers
        local fallback = quickLootFallbackToMainContainer

        -- Store lootContainers globally so other modules can access it
        -- Store a copy to avoid interfering with the local variable
        QuickLoot.lootContainers = {}
        if lootContainers then
            for i, container in ipairs(lootContainers) do
                QuickLoot.lootContainers[i] = {container[1], container[2], container[3]}
            end
        end

        QuickLoot.loadFilterItems()

        local filter = {
            [1] = "skipped",
            [2] = "accepted"
        }

        QuickLoot.filter(quickLootController.ui.filters[filter[QuickLoot.data.filter]], true)
        quickLootController.ui.list:getLayout():disableUpdates()
        quickLootController.ui.list:destroyChildren()

        quickLootController.ui.fallbackPanel.checkbox:setChecked(fallback)
        -- LuaFormatter off
		local slotBags = {
			{ color = "#484848", name = "Unassigned", type = 31 },
			{ color = "#414141", name = "Gold", type = 30 },
			{ color = "#484848", name = "Armors", type = 1 },
			{ color = "#414141", name = "Amulets", type = 2  },
			{ color = "#484848", name = "Boots", type = 3 },
			{ color = "#414141", name = "Containers", type = 4 },
			{ color = "#484848", name = "Creature\nProducts", type = 24 },
			{ color = "#414141", name = "Decoration", type = 5 },
			{ color = "#484848", name = "Food", type = 6 },
			{ color = "#414141", name = "Helmets\nand Hats", type =7 },
			{ color = "#484848", name = "Legs", type = 8 },
			{ color = "#414141", name = "Others", type = 9 },

			{ color = "#414141", name = "Potions", type = 10 },
			{ color = "#484848", name = "Rings", type = 11 },
			{ color = "#414141", name = "Runes", type = 12 },
			{ color = "#484848", name = "Shields", type = 13 },
			{ color = "#414141", name = "Tools", type = 14 },
			{ color = "#484848", name = "Valuables", type = 15 },
			{ color = "#414141", name = "Weapons:\nAmmo", type = 16 },
			{ color = "#484848", name = "Weapons:\nAxes", type = 17 },
			{ color = "#414141", name = "Weapons:\nClubs", type = 18 },
			{ color = "#484848", name = "Weapons:\nDistance", type = 19 },
			{ color = "#414141", name = "Weapons:\nSwords", type = 20 },
			{ color = "#484848", name = "Weapons:\nWands", type = 21 },
			--{ color = "#414141", name = "Quivers" , type = 25 },

		}
		-- LuaFormatter on

        for _, slot in ipairs(slotBags) do
            local widget = g_ui.createWidget("QuicklootBagLabel", quickLootController.ui.list)
            local id = slot.type and slot.type or 0

            widget:setId(id)
            widget:setBackgroundColor(slot.color)
            widget.label:setText(slot.name)

            for _, container in pairs(lootContainers) do
                if container[1] == id then
                    local lootContainerId = container[3]
                    local obtainerContainerId = container[2]

                    widget.item:setItemId(lootContainerId)
                    widget.item2:setItemId(obtainerContainerId)
                    break
                end
            end
        end
        quickLootController.ui.list:getLayout():enableUpdates()
        quickLootController.ui.list:getLayout():update()
    end

    -- ------------------------------------------------------------ picker
    -- The right column lists items with a "Take" box, so the player picks
    -- what the auto loot takes without opening a corpse: with the search
    -- empty it shows the items of the last loot messages (and the ones
    -- already on the list), with text it searches every market item by name.
    -- "Take" means the same in both filters: on Skipped Loot an unticked
    -- item goes on the list, on Accepted Loot a ticked one does.

    local MAX_RECENT = 60
    local MAX_RESULTS = 60

    -- Price rule: every item Gersao buys for at least `min` gold is taken.
    -- A Take box the player changes by hand overrides it for that item
    -- (priceRule.take / priceRule.skip). The server gets the result as an
    -- accepted loot list; rarity items are always taken by the server.
    function QuickLoot.priceRule()
        local data = QuickLoot.data
        data.priceRule = data.priceRule or {}
        local rule = data.priceRule
        rule.min = tonumber(rule.min) or 1000
        rule.take = rule.take or {}
        rule.skip = rule.skip or {}
        return rule
    end

    function QuickLoot.priceRuleActive()
        return QuickLoot.priceRule().enabled == true and QuickLoot.prices ~= nil
    end

    local function pays(itemId, rule)
        return (QuickLoot.prices[itemId] or 0) >= rule.min
    end

    local function priceRuleIds()
        local rule = QuickLoot.priceRule()
        local skip, ids, seen = {}, {}, {}
        for _, id in ipairs(rule.skip) do
            skip[id] = true
        end
        local function add(id)
            if not skip[id] and not seen[id] then
                seen[id] = true
                table.insert(ids, id)
            end
        end
        for id in pairs(QuickLoot.prices) do
            if pays(id, rule) then
                add(id)
            end
        end
        for _, id in ipairs(rule.take) do
            add(id)
        end
        -- coins: always, the price rule is about items
        for _, id in ipairs(QuickLoot.alwaysTake or {}) do
            if not seen[id] then
                seen[id] = true
                table.insert(ids, id)
            end
        end
        table.sort(ids)
        return ids
    end

    function QuickLoot.sendList()
        if QuickLoot.priceRuleActive() then
            local ids = priceRuleIds()
            g_game.requestQuickLootBlackWhiteList(getFilter(2), #ids, ids)
            return
        end
        local list = QuickLoot.data.loots[QuickLoot.data.filter] or {}
        g_game.requestQuickLootBlackWhiteList(getFilter(QuickLoot.data.filter), #list, list)
    end

    function QuickLoot.requestPrices()
        local protocol = g_game.getProtocolGame()
        if protocol then
            protocol:sendExtendedJSONOpcode(LOOT_PRICES_OPCODE, { action = 'prices' })
        end
    end

    function QuickLoot.onPrices(protocol, opcode, data)
        if type(data) ~= 'table' or data.action ~= 'prices' or type(data.items) ~= 'table' then
            return
        end
        local prices = {}
        for _, entry in ipairs(data.items) do
            local id, price = tonumber(entry[1]), tonumber(entry[2])
            if id and price then
                prices[id] = price
            end
        end
        QuickLoot.prices = prices
        QuickLoot.alwaysTake = {}
        for _, id in ipairs(type(data.always) == 'table' and data.always or {}) do
            if tonumber(id) then
                table.insert(QuickLoot.alwaysTake, tonumber(id))
            end
        end
        if QuickLoot.priceRule().enabled then
            QuickLoot.sendList()
        end
        if quickLootController.ui and quickLootController.ui:isVisible() then
            QuickLoot.loadFilterItems()
        end
    end

    -- the price rule's widgets, from QuickLoot.data
    function QuickLoot.refreshPriceRule()
        local ui = quickLootController.ui
        local panel = ui and ui.priceRule
        if not panel then
            return
        end
        local rule = QuickLoot.priceRule()
        QuickLoot.updatingPriceRule = true
        panel.enabled:setChecked(rule.enabled == true)
        if panel.min:getText() ~= tostring(rule.min) then
            panel.min:setText(tostring(rule.min))
        end
        QuickLoot.updatingPriceRule = false
        -- the skipped / accepted lists don't apply while the rule decides
        ui.filters.skipped:setEnabled(not rule.enabled)
        ui.filters.accepted:setEnabled(not rule.enabled)
    end

    function QuickLoot.setPriceRule(enabled)
        if QuickLoot.updatingPriceRule then
            return
        end
        QuickLoot.priceRule().enabled = enabled
        if enabled and not QuickLoot.prices then
            QuickLoot.requestPrices()
        end
        QuickLoot.refreshPriceRule()
        QuickLoot.sendList()
        QuickLoot.loadFilterItems()
    end

    function QuickLoot.setPriceMin(text)
        if QuickLoot.updatingPriceRule then
            return
        end
        local digits = (text or ''):gsub('%D', '')
        QuickLoot.priceRule().min = tonumber(digits) or 0
        -- typing a number sends one list, not one per key
        if QuickLoot.priceMinEvent then
            removeEvent(QuickLoot.priceMinEvent)
        end
        QuickLoot.priceMinEvent = scheduleEvent(function()
            QuickLoot.priceMinEvent = nil
            if QuickLoot.priceRule().enabled then
                QuickLoot.sendList()
            end
            QuickLoot.loadFilterItems()
        end, 400)
    end

    function QuickLoot.isWanted(itemId)
        if QuickLoot.priceRuleActive() then
            local rule = QuickLoot.priceRule()
            if table.contains(QuickLoot.alwaysTake or {}, itemId) then
                return true
            end
            if table.contains(rule.skip, itemId) then
                return false
            end
            return table.contains(rule.take, itemId) or pays(itemId, rule)
        end
        local listed = QuickLoot.lootExists(itemId)
        if QuickLoot.data.filter == 2 then
            return listed
        end
        return not listed
    end

    function QuickLoot.setWanted(itemId, wanted)
        if QuickLoot.priceRuleActive() then
            local rule = QuickLoot.priceRule()
            table.removevalue(rule.take, itemId)
            table.removevalue(rule.skip, itemId)
            if wanted and not pays(itemId, rule) then
                table.insert(rule.take, itemId)
            elseif not wanted and pays(itemId, rule) then
                table.insert(rule.skip, itemId)
            end
            QuickLoot.sendList()
            return
        end
        local addToList = (QuickLoot.data.filter == 2) == wanted
        if addToList then
            QuickLoot.addLootList(itemId)
        else
            QuickLoot.removeLootList(itemId)
        end
    end

    -- "Loot of a dragon: {3031|53 gold coins}, {5920|a green dragon scale}."
    function QuickLoot.onTextMessage(mode, text)
        if mode ~= MessageModes.Loot and mode ~= MessageModes.ValuableLoot then
            return
        end
        if not text or not text:find('{') then
            return
        end
        QuickLoot.data.recent = QuickLoot.data.recent or {}
        local recent = QuickLoot.data.recent
        local changed = false
        for id in text:gmatch('{(%d+)|') do
            id = tonumber(id)
            if id and id > 0 then
                table.removevalue(recent, id)
                table.insert(recent, 1, id)
                changed = true
            end
        end
        while #recent > MAX_RECENT do
            table.remove(recent)
        end
        if changed and quickLootController.ui and quickLootController.ui:isVisible() and (QuickLoot.searchText or '') == '' then
            QuickLoot.loadFilterItems()
        end
    end

    local function itemName(itemId)
        local thing = g_things.getThingType(itemId, ThingCategoryItem)
        if not thing then
            return ''
        end
        local market = thing:getMarketData()
        if market and market.name and market.name ~= '' then
            return market.name
        end
        return thing:getName() or ''
    end

    -- every item that can be sold on the market, by lower-case name
    local searchIndex
    local function buildSearchIndex()
        searchIndex = {}
        local seen = {}
        for _, thing in pairs(g_things.findThingTypeByAttr(ThingAttrMarket, 0) or {}) do
            local id = thing:getId()
            local name = itemName(id)
            if name ~= '' and not seen[name:lower()] then
                seen[name:lower()] = true
                table.insert(searchIndex, { id = id, name = name, lower = name:lower() })
            end
        end
        table.sort(searchIndex, function(a, b) return a.lower < b.lower end)
    end

    local function addRow(list, itemId, name, color)
        local row = g_ui.createWidget('QuickLootPickRow', list)
        row:setId(tostring(itemId))
        row:setBackgroundColor(color)
        row.item:setItemId(itemId)
        local price = QuickLoot.prices and QuickLoot.prices[itemId]
        local text = name ~= '' and name or tr('Unknown')
        if price then
            text = text .. '\n' .. tr('Gersao pays %s', comma_value and comma_value(price) or tostring(price))
        end
        row.label:setText(text)
        row.take:setChecked(QuickLoot.isWanted(itemId))
        row.take.onCheckChange = function(widget, checked)
            QuickLoot.setWanted(itemId, checked)
        end
    end

    function QuickLoot.loadFilterItems()
        local ui = quickLootController.ui
        if not ui or not ui.ignoreList then
            return
        end
        local list = ui.ignoreList
        list:destroyChildren()

        local text = (QuickLoot.searchText or ''):trim():lower()
        local ids, names = {}, {}
        if text ~= '' then
            if not searchIndex then
                buildSearchIndex()
            end
            for _, entry in ipairs(searchIndex) do
                if entry.lower:find(text, 1, true) then
                    table.insert(ids, entry.id)
                    names[entry.id] = entry.name
                    if #ids >= MAX_RESULTS then
                        break
                    end
                end
            end
            ui.pickTitle:setText(#ids > 0 and tr('Search results') or tr('No item with this name'))
        else
            local seen = {}
            for _, id in ipairs(QuickLoot.data.recent or {}) do
                if not seen[id] then
                    seen[id] = true
                    table.insert(ids, id)
                end
            end
            for _, id in ipairs(QuickLoot.data.loots[QuickLoot.data.filter] or {}) do
                if not seen[id] then
                    seen[id] = true
                    table.insert(ids, id)
                end
            end
            ui.pickTitle:setText(#ids > 0 and tr('Your recent drops') or tr('Kill something or search an item by name'))
        end

        local color = '#484848'
        for _, id in ipairs(ids) do
            addRow(list, id, names[id] or itemName(id), color)
            color = color == '#484848' and '#414141' or '#484848'
        end
    end

    function QuickLoot.search(text)
        QuickLoot.searchText = text or ''
        QuickLoot.loadFilterItems()
    end

    function QuickLoot.focusSearch()
        local search = quickLootController.ui and quickLootController.ui.search
        if search then
            search:focus()
        end
    end

    function QuickLoot.clearSearch()
        local search = quickLootController.ui.search
        search:clearText()
    end

    function QuickLoot.fallback(widget, isChecked)
        g_game.openContainerQuickLoot(3, nil, {}, nil, nil, isChecked)
    end

    function QuickLoot:chooseItem()
        if g_ui.isMouseGrabbed() then
            return
        end

        QuickLoot.mouseGrabberWidget:grabMouse()
        -- Use native cursor when enabled, otherwise use custom cursor
        if modules.client_options and modules.client_options.getOption('nativeCursor') then
            g_window.setSystemCursor('cross')
        else
            g_mouse.pushCursor("target")
        end

        QuickLoot.lastSelectBag = self:getParent()
        QuickLoot.actionsId = self.Select

        quickLootController.ui:hide()
    end

    function QuickLoot.confirmError()
        QuickLoot.ErrorWindow:destroy()
        quickLootController.ui:show()
    end

    function QuickLoot:onChooseItem(mousePosition, mouseButton)
        local item

        if mouseButton == MouseLeftButton then
            local clickedWidget = modules.game_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)

            if clickedWidget then
                if clickedWidget:getClassName() == "UIGameMap" then
                    local tile = clickedWidget:getTile(mousePosition)

                    if tile then
                        local thing = tile:getTopMoveThing()

                        if thing and thing:isContainer() then
                            item = thing
                        else
                            QuickLoot.ErrorWindow = displayGeneralBox(tr("Invalid Loot Container"), tr(
                                "You can only select containers you carry in your inventory."), {
                                {
                                    text = tr("Ok"),
                                    callback = QuickLoot.confirmError
                                },
                                anchor = AnchorHorizontalCenter
                            })
                        end
                    end
                elseif clickedWidget:getClassName() == "UIItem" and not clickedWidget:isVirtual() then
                    if clickedWidget:getItem() and clickedWidget:getItem():isContainer() then
                        item = clickedWidget:getItem()
                        g_game.openContainerQuickLoot(QuickLoot.actionsId, QuickLoot.lastSelectBag:getId(),
                            item:getPosition(), item:getId(), item:getStackPos())
                    else
                        QuickLoot.ErrorWindow = displayGeneralBox(tr("Invalid Loot Container"), tr(
                            "You can only select containers you carry in your inventory."), {
                            {
                                text = tr("Ok"),
                                callback = QuickLoot.confirmError
                            },
                            anchor = AnchorHorizontalCenter
                        })
                    end
                end
            end
        end

        if item then
            QuickLoot.lastSelectBag.item:setItem(item)
            quickLootController.ui:show()
        end

        -- Restore cursor
        if modules.client_options and modules.client_options.getOption('nativeCursor') then
            g_window.restoreMouseCursor()
        else
            g_mouse.popCursor("target")
        end
        self:ungrabMouse()

        return true
    end

    function QuickLoot:openContainer()
        for _, container in pairs(g_game.getContainers()) do
            if container:getContainerItem():getId() == self:getItemId() then
                return false
            end
        end
        g_game.openContainerQuickLoot(self.click, self:getParent():getId(), {}, nil, nil, nil)
        return true
    end

    function QuickLoot:clearItem()
        if self.borrar == 1 then
            self:getParent().item2:setItem(nil)
        else
            self:getParent().item:setItem(nil)
        end
        g_game.openContainerQuickLoot(self.borrar, self:getParent():getId(), {}, nil, nil, nil)
    end

    function QuickLoot:clearFilterItem()
        QuickLoot.removeLootList(self:getParent().item:getItemId())

        QuickLoot.loadFilterItems()
    end

    function QuickLoot.toggle()
        if not quickLootController.ui then
            return
        end

        if quickLootController.ui:isVisible() then
            return QuickLoot.hide()
        end
        QuickLoot.show()
        QuickLoot.loadFilterItems()
        if QuickLoot.data.filter == 2 and not quickLootController.ui.filters.accepted:isChecked() then
            quickLootController.ui.filters.accepted:onClick()
        end
    end

    function QuickLoot.show()
        if not quickLootController.ui then
            return
        end

        quickLootController.ui:show()
        quickLootController.ui:raise()
        quickLootController.ui:focus()

    end

    function QuickLoot.hide()
        if not quickLootController.ui then
            return
        end
        quickLootController.ui:hide()
    end

end
