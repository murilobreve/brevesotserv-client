-- /*=============================================
-- =            Spells html Windows             =
-- =============================================*/
-- the Assign Spell window lives in SpellAssignWindow.lua
function assignSpell(button, multiSlotIndex)
    local actionbar = button:getParent():getParent()
    if actionbar.locked then
        alert('Action bar is locked')
        return
    end
    SpellAssign.open(button, multiSlotIndex)
end
-- /*=============================================
-- =            SetText html Windows             =
-- =============================================*/
function assignText(button, multiSlotIndex)
    local actionbar = button:getParent():getParent()
    if actionbar.locked then
        alert('Action bar is locked')
        return
    end
    if ActionBarController.ui then
        ActionBarController:unloadHtml()
    end
    SpellAssign.close()
    ActionBarController:loadHtml('html/text.html')
    local ui = ActionBarController.ui
    ActionBarController:scheduleEvent(function()
        ui:centerIn('parent')
    end, 1, "lazyHtml")
    ui:show()
    ui:raise()
    ui:focus()
    local titleSuffix = multiSlotIndex and (" (Slot " .. multiSlotIndex .. ")") or ""
    ui:setTitle("Assign Text to Action Button " .. button:getId() .. titleSuffix)
    local textWidget = ActionBarController:findWidget("#text")
    local tickWidget = ActionBarController:findWidget("#tick")
    local param = ''
    local sendAuto = false
    if multiSlotIndex and button.cache and button.cache.multiActions then
        local slot = button.cache.multiActions[multiSlotIndex]
        if slot and slot["chatText"] then
            param = slot["chatText"]
            sendAuto = slot["sendAutomatically"] or false
        end
    else
        param = button.cache.param or ''
        sendAuto = button.cache.sendAutomatic or false
    end
    textWidget:setText(param)
    textWidget:setCursorPos(#param)
    local hasText = #param > 0
    tickWidget:setChecked(hasText and sendAuto or false)
    local function saveText(closeAfter)
        local autoSay = tickWidget:isChecked()
        local text = textWidget:getText()
        local formattedText = Spells.getSpellFormatedName(text)
        local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
        if multiSlotIndex then
            if not button.cache.multiActions then button.cache.multiActions = {{}, {}, {}} end
            button.cache.multiActions[multiSlotIndex] = {chatText = formattedText, sendAutomatically = autoSay}
            ApiJson.createOrUpdateMultiText(tonumber(barID), tonumber(buttonID), multiSlotIndex, formattedText, autoSay)
            if updateMultiButtonState then updateMultiButtonState(button) end
            if assignMultiAction then assignMultiAction(button, true) end
        else
            ApiJson.createOrUpdateText(tonumber(barID), tonumber(buttonID), formattedText, autoSay)
            updateButton(button)
        end
        if closeAfter then
            ActionBarController:unloadHtml()
        end
    end
    ActionBarController:findWidget("#buttonOk").onClick = function()
        saveText(true)
    end
    ActionBarController:findWidget("#buttonApply").onClick = function()
        saveText(false)
    end
    local function cancelFunc()
        ActionBarController:unloadHtml()
    end
    ActionBarController:findWidget("#buttonClose").onClick = cancelFunc
end

function ActionBarController:updateAssignTextState(event)
    local hasText = event.value:len() > 0
    ActionBarController:findWidget("#buttonApply"):setEnabled(hasText)
    ActionBarController:findWidget("#buttonOk"):setEnabled(hasText)
end
-- /*=============================================
-- =            SetObject html Windows             =
-- =============================================*/
local function canEquipItem(item)
    if item:isContainer() then
        return false
    end
    if not g_game.getFeature(GameEnterGameShowAppearance) then -- old protocol
        return true
    end
    if item:getClothSlot() == 0 and (item:getClassification() > 0 or item:isAmmo()) then
        return true
    end

    if item:getClothSlot() > 0 or (item:getClothSlot() == 0 and item:hasWearout()) then
        return true
    end
    return false
end

function assignItem(button, itemId, itemTier, dragEvent, multiSlotIndex)
    if not isLoaded then
        return true
    end
    if not button.item then
        local parent = button:getParent()
        local id = button:getId()
        updateButton(button)
        button = parent:getChildById(id)
        if not button or not button.item then
            return
        end
    end
    local item = button.item:getItem()
    local actionbar = button:getParent():getParent()
    if dragEvent and actionbar.locked or actionbar.locked then
        updateButton(button)
        return
    end
    if dragEvent and not multiSlotIndex then
        updateButton(button)
        return
    end
    if ActionBarController.ui then
        ActionBarController:unloadHtml()
    end
    SpellAssign.close()
    ActionBarController:loadHtml('html/object.html')
    local ui = ActionBarController.ui
    ActionBarController:scheduleEvent(function()
        ui:centerIn('parent')
    end, 1, "lazyHtml")
    ui:show()
    ui:raise()
    ui:focus()
    local titleSuffix = multiSlotIndex and (" (Slot " .. multiSlotIndex .. ")") or ""
    ui:setTitle("Assign Object to Action Button " .. button:getId() .. titleSuffix)
    local itemWidget = ui:querySelector("#item")
    local selectButton = ui:querySelector("button[text='Select Object']")
    local checkbox1 = ui:querySelector("#UseOnYourself")
    local checkbox2 = ui:querySelector("#UseOnTarget")
    local checkbox3 = ui:querySelector("#UseAtCursorPosition")
    local checkbox4 = ui:querySelector("#SelectUseTarget")
    local checkbox5 = ui:querySelector("#Equip")
    local checkbox6 = ui:querySelector("#Use")
    local buttonOk = ui:querySelector("#buttonOk")
    local buttonApply = ui:querySelector("#buttonApply")
    local buttonClose = ui:querySelector("#buttonClose")
    if selectButton then
        selectButton.onClick = function()
            ActionBarController:unloadHtml()
            assignItemEvent(button, multiSlotIndex)
        end
    end
    local preselectActionType = nil
    local preselectItemId = nil
    if multiSlotIndex and button.cache and button.cache.multiActions then
        local slot = button.cache.multiActions[multiSlotIndex]
        if slot and slot["useObject"] then
            preselectItemId = slot["useObject"]
            preselectActionType = slot["useType"]
        end
    end
    local fromSelect
    if multiSlotIndex then
        fromSelect = preselectItemId and preselectItemId ~= itemId or false
    else
        fromSelect = button.item:getItemId() > 0 and button.item:getItemId() ~= itemId
    end
    itemWidget:setItemId(itemId)
    if not item or item:getId() == 0 then
        item = itemWidget:getItem()
    end
    if item:getClassification() == 0 then
        itemTier = 0
    end
    if itemWidget:getItem() then
        ItemsDatabase.setTier(itemWidget, itemTier, false)
    end
    local checkboxWidgets = {{
        widget = checkbox1,
        useType = "UseOnYourself"
    }, {
        widget = checkbox2,
        useType = "UseOnTarget"
    }, {
        widget = checkbox3,
        useType = "UseAtCursorPosition"
    }, {
        widget = checkbox4,
        useType = "SelectUseTarget"
    }, {
        widget = checkbox5,
        useType = "Equip"
    }, {
        widget = checkbox6,
        useType = "Use"
    }}

    local activeActionType = multiSlotIndex and preselectActionType or button.cache.actionType
    local selectedCheckbox = nil
    for _, cbData in ipairs(checkboxWidgets) do
        if cbData.widget then
            cbData.widget:setEnabled(false)
            cbData.widget:setChecked(false)
        end
    end

    -- UseTypes: UseOnYourself=1, UseOnTarget=2, SelectUseTarget=3, UseAtCursorPosition=9
    if item:isMultiUse() then
        for _, cbData in ipairs(checkboxWidgets) do
            local useTypeIndex = UseTypes[cbData.useType]
            if (useTypeIndex <= UseTypes["SelectUseTarget"] or useTypeIndex == UseTypes["UseAtCursorPosition"]) and
                cbData.widget then
                cbData.widget:setEnabled(true)

                if not selectedCheckbox and
                    not (item:getClothSlot() > 0 or (item:getClothSlot() == 0 and item:getClassification() > 0)) then
                    if fromSelect or activeActionType == 0 or activeActionType == cbData.useType or
                        activeActionType == UseTypes[cbData.useType] then
                        selectedCheckbox = cbData.widget
                    end
                end
            end
        end
    end

    -- UseTypes: Equip=4
    if canEquipItem(item) then
        checkbox5:setEnabled(true)

        if not selectedCheckbox then
            if fromSelect or activeActionType == 0 or activeActionType == "Equip" or
                activeActionType == UseTypes["Equip"] then
                selectedCheckbox = checkbox5
            end
        end
    end

    -- UseTypes: Use=5 (items usables no-multiuso)
    if (item:isUsable() and not item:isMultiUse()) or item:isContainer() then
        checkbox6:setEnabled(true)

        if not selectedCheckbox then
            if fromSelect or activeActionType == 0 or activeActionType == "Use" or activeActionType ==
                UseTypes["Use"] then
                selectedCheckbox = checkbox6
            end
        end
    end
    buttonOk:setEnabled(item and item:getId() > 100)
    buttonApply:setEnabled(item and item:getId() > 100)
    if not selectedCheckbox then
        for _, cbData in ipairs(checkboxWidgets) do
            if cbData.widget and cbData.widget:isEnabled() then
                selectedCheckbox = cbData.widget
                break
            end
        end
    end
    if selectedCheckbox then
        selectedCheckbox:setChecked(true)
    end
    for _, cbData in ipairs(checkboxWidgets) do
        if cbData.widget then
            cbData.widget.onCheckChange = function(widget, checked)
                if checked then
                    for _, otherCbData in ipairs(checkboxWidgets) do
                        if otherCbData.widget and otherCbData.widget ~= widget and otherCbData.widget:isChecked() then
                            otherCbData.widget:setChecked(false)
                        end
                    end
                end
            end
        end
    end
    local function okFunc(destroy)
        local selected = nil
        for _, cbData in ipairs(checkboxWidgets) do
            if cbData.widget and cbData.widget:isChecked() then
                selected = cbData.useType
                break
            end
        end
        if not selected then
            return
        end
        local barID, buttonID = string.match(button:getId(), "^(%d+)%.(%d+)$")
        if not barID or not buttonID then
            return
        end
        local cache = getButtonCache(button)
        local cachedItem = cachedItemWidget[cache.itemId]
        if cachedItem then
            for index, widget in pairs(cachedItem) do
                if button == widget then
                    table.remove(cachedItem, index)
                    break
                end
            end
        end
        if multiSlotIndex then
            if not button.cache.multiActions then button.cache.multiActions = {{}, {}, {}} end
            button.cache.multiActions[multiSlotIndex] = {useObject = itemId, useType = selected, upgradeTier = itemTier, useEquipSmartMode = false}
            ApiJson.createOrUpdateMultiAction(tonumber(barID), tonumber(buttonID), multiSlotIndex, selected, itemId, itemTier, false)
            if updateMultiButtonState then updateMultiButtonState(button) end
            if assignMultiAction then assignMultiAction(button, true) end
        else
            ApiJson.createOrUpdateAction(tonumber(barID), tonumber(buttonID), selected, itemId, itemTier)
            updateButton(button)
        end

        if destroy then
            ActionBarController:unloadHtml()
        end
    end
    buttonOk.onClick = function()
        okFunc(true)
    end
    buttonApply.onClick = function()
        okFunc(false)
    end
    buttonClose.onClick = function()
        updateButton(button)
        ActionBarController:unloadHtml()
    end
    ui.onEnter = function()
        okFunc(true)
    end
    ui.onEscape = function()
        updateButton(button)
        ActionBarController:unloadHtml()
    end
    if actionbar.locked then
        ActionBarController:unloadHtml()
    end
end
-- /*=============================================
-- =            Passive html Windows          =
-- =============================================*/

function assignPassive(button)
    local actionbar = button:getParent():getParent()
    if actionbar.locked then
        alert('Action bar is locked')
        return
    end
    local radio = UIRadioGroup.create()
    if ActionBarController.ui then
        ActionBarController:unloadHtml()
    end
    SpellAssign.close()
    ActionBarController:loadHtml('html/passive.html')
    local ui = ActionBarController.ui
    ui:show()
    ui:raise()
    ui:setTitle("Assign Passive to Action Button " .. button:getId())
    local passiveList = ActionBarController:findWidget("#passiveList")
    local previewWidget = ActionBarController:findWidget("#preview")
    local image = ActionBarController:findWidget("#image")
    for id, passiveData in pairs(PassiveAbilities) do
        local widget = g_ui.createWidget('PassivePreview', passiveList)
        radio:addWidget(widget)
        widget:setId(id)
        widget:setText(passiveData.name)
        widget.image:setImageSource(passiveData.icon)
        widget.source = passiveData.icon
    end
    radio.onSelectionChange = function(widget, selected)
        if selected then
            previewWidget:setText(selected:getText())
            image:setImageSource(selected.source)
            passiveList:ensureChildVisible(widget)
        end
    end
    local passiveChildren = passiveList:getChildren()
    if #passiveChildren > 0 then
        radio:selectWidget(passiveChildren[1])
    end
    local function okFunc(destroy)
        local selected = radio:getSelectedWidget()
        if not selected then
            return
        end
        local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
        ApiJson.createOrUpdatePassive(tonumber(barID), tonumber(buttonID), tonumber(selected:getId()))
        updateButton(button)
        if destroy then
            ActionBarController:unloadHtml()
        end
    end
    local function cancelFunc()
        ActionBarController:unloadHtml()
    end
    ActionBarController:findWidget("#buttonOk").onClick = function()
        okFunc(true)
    end
    ActionBarController:findWidget("#buttonApply").onClick = function()
        okFunc(false)
    end
    ActionBarController:findWidget("#buttonClose").onClick = cancelFunc
    ui.onEnter = function()
        okFunc(true)
    end
end

function assignSpecialAction(button, mousePos)
    local actionbar = button:getParent():getParent()
    if actionbar.locked then
        alert('Action bar is locked')
        return
    end

    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)

    for _, specialAction in ipairs(ActionBarSpecialActions) do
        menu:addOption(specialAction.text, function()
            local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
            ApiJson.createOrUpdateSpecialAction(tonumber(barID), tonumber(buttonID), specialAction.id)
            updateButton(button)
        end)
    end

    if button.cache and button.cache.specialAction then
        menu:addSeparator()
        menu:addOption(tr("Clear Assigned Action"), function()
            clearButton(button, true)
        end)
    end

    menu:display(mousePos)
end

-- /*=============================================
-- =            item Event external          =
-- =============================================*/
function onDropActionButton(self, mousePosition, mouseButton)
    if not g_ui.isMouseGrabbed() then
        return
    end
    -- Restore cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('target')
    end
    self:ungrabMouse()
end

function assignItemEvent(button, multiSlotIndex)
    mouseGrabberWidget:grabMouse()
    -- Use native cursor when enabled, otherwise use custom cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
    mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
        onAssignItem(self, mousePosition, mouseButton, button, multiSlotIndex)
    end
end

function onAssignItem(self, mousePosition, mouseButton, button, multiSlotIndex)
    mouseGrabberWidget:ungrabMouse()
    -- Restore cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('target')
    end
    mouseGrabberWidget.onMouseRelease = onDropActionButton

    local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then
        return true
    end

    local itemId = 0
    local itemTier = 0
    if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() and clickedWidget:getItem() then
        itemId = clickedWidget:getItem():getId()
        itemTier = clickedWidget:getItem():getTier()
    elseif clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
            itemId = tile:getTopUseThing():getId()
        end
    end

    local itemType = g_things.getThingType(itemId, ThingCategoryItem)
    if not itemType or not itemType:isPickupable() then
        modules.game_textmessage.displayFailureMessage(tr('Invalid object'))
        return true
    end
    assignItem(button, itemId, itemTier, false, multiSlotIndex)
end

-- /*=============================================
-- =            Windows hotkeys html             =
-- =============================================*/
-- in modules\game_actionbar\html\hotkeys.html
