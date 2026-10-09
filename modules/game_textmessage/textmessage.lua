MessageSettings = {
    none = {},
    consoleYellow = {
        color = TextColors.yellow,
        consoleTab = 'Local Chat'
    },
    consoleRed = {
        color = TextColors.red,
        consoleTab = 'Local Chat'
    },
    consoleOrange = {
        color = TextColors.orange,
        consoleTab = 'Local Chat'
    },
    consoleBlue = {
        color = TextColors.blue,
        consoleTab = 'Local Chat'
    },
    centerRed = {
        color = TextColors.red,
        consoleTab = 'Server Log',
        screenTarget = 'lowCenterLabel'
    },
    centerGreen = {
        color = TextColors.green,
        consoleTab = 'Server Log',
        screenTarget = 'highCenterLabel',
        consoleOption = 'showInfoMessagesInConsole'
    },
    centerHKGreen = {
        color = TextColors.green,
        consoleTab = 'Server Log',
        screenTarget = 'hotkeyCenterLabel',
        consoleOption = 'showInfoMessagesInConsole'
    },
    centerWhite = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'middleCenterLabel',
        consoleOption = 'showEventMessagesInConsole'
    },
    bottomWhite = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showEventMessagesInConsole'
    },
    status = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showStatusMessagesInConsole'
    },
    statusOwn = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        consoleOption = 'showStatusMessagesInConsole'
    },
    statusBoosted = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showBoostedMessagesInConsole'
    },
    othersStatus = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        consoleOption = 'showOthersStatusMessagesInConsole'
    },
    statusSmall = {
        color = TextColors.white,
        screenTarget = 'statusLabel'
    },
    private = {
        color = TextColors.lightblue,
        consoleTab = 'Local Chat',
        screenTarget = 'privateLabel'
    },
    privateRed = {
        color = TextColors.red,
        consoleTab = 'Local Chat',
        private = true
    },
    privatePlayerToPlayer = {
        color = TextColors.blue,
        consoleTab = 'Local Chat',
        private = true
    },
    privatePlayerToNpc = {
        color = TextColors.blue,
        consoleTab = 'Local Chat',
        private = true,
        npcChat = true
    },
    privateNpcToPlayer = {
        color = TextColors.lightblue,
        consoleTab = 'Local Chat',
        private = true,
        npcChat = true
    },
    channelYellow = {
        color = TextColors.yellow
    },
    channelWhite = {
        color = TextColors.white
    },
    channelRed = {
        color = TextColors.red
    },
    channelOrange = {
        color = TextColors.orange
    },
    monsterSay = {
        color = TextColors.orange,
        hideInConsole = true
    },
    monsterYell = {
        color = TextColors.orange,
        hideInConsole = true
    },
    potion = {
        color = TextColors.orange,
        hideInConsole = true
    },
    loot = {
        color = TextColors.white,
        consoleTab = 'Loot',
        screenTarget = 'highCenterLabel',
        consoleOption = 'showInfoMessagesInConsole',
        colored = true
    },
    valuableLoot = {
        color = TextColors.white,
        consoleTab = 'Loot',
        screenTarget = 'statusLabel',
        consoleOption = 'showInfoMessagesInConsole',
        colored = true
    }
}

MessageTypes = {
    [MessageModes.Say] = MessageSettings.consoleYellow,
    [MessageModes.Whisper] = MessageSettings.consoleYellow,
    [MessageModes.Yell] = MessageSettings.consoleYellow,
    [MessageModes.MonsterSay] = MessageSettings.monsterSay,
    [MessageModes.MonsterYell] = MessageSettings.monsterYell,
    [MessageModes.BarkLow] = MessageSettings.consoleOrange,
    [MessageModes.BarkLoud] = MessageSettings.consoleOrange,
    [MessageModes.Failure] = MessageSettings.statusSmall,
    [MessageModes.Login] = MessageSettings.bottomWhite,
    [MessageModes.Game] = MessageSettings.centerWhite,
    [MessageModes.Status] = MessageSettings.status,
    [MessageModes.Warning] = MessageSettings.centerRed,
    [MessageModes.Look] = MessageSettings.centerGreen,
    [MessageModes.Loot] = MessageSettings.loot,
    [MessageModes.Red] = MessageSettings.consoleRed,
    [MessageModes.Blue] = MessageSettings.consoleBlue,
    [MessageModes.PrivateFrom] = MessageSettings.private,
    [MessageModes.PrivateTo] = MessageSettings.privatePlayerToPlayer,
    [MessageModes.GamemasterPrivateFrom] = MessageSettings.privateRed,
    [MessageModes.NpcTo] = MessageSettings.privatePlayerToNpc,
    [MessageModes.NpcFrom] = MessageSettings.privateNpcToPlayer,
    [MessageModes.NpcFromStartBlock] = MessageSettings.privateNpcToPlayer,
    [MessageModes.Channel] = MessageSettings.channelYellow,
    [MessageModes.ChannelManagement] = MessageSettings.channelWhite,
    [MessageModes.GamemasterChannel] = MessageSettings.channelRed,
    [MessageModes.ChannelHighlight] = MessageSettings.channelOrange,
    [MessageModes.Spell] = MessageSettings.consoleYellow,
    [MessageModes.RVRChannel] = MessageSettings.channelWhite,
    [MessageModes.RVRContinue] = MessageSettings.consoleYellow,

    [MessageModes.GamemasterBroadcast] = MessageSettings.consoleRed,

    [MessageModes.DamageDealed] = MessageSettings.statusOwn,
    [MessageModes.DamageReceived] = MessageSettings.statusOwn,
    [MessageModes.Heal] = MessageSettings.statusOwn,
    [MessageModes.Exp] = MessageSettings.statusOwn,

    [MessageModes.DamageOthers] = MessageSettings.statusOwn,
    [MessageModes.HealOthers] = MessageSettings.statusOwn,
    [MessageModes.ExpOthers] = MessageSettings.statusOwn,
    [MessageModes.Potion] = MessageSettings.potion,

    [MessageModes.TradeNpc] = MessageSettings.centerGreen,
    [MessageModes.Guild] = MessageSettings.statusOwn,
    [MessageModes.Party] = MessageSettings.statusOwn,
    [MessageModes.PartyManagement] = MessageSettings.centerGreen,
    [MessageModes.TutorialHint] = MessageSettings.statusSmall,
    [MessageModes.BeyondLast] = MessageSettings.centerWhite,
    [MessageModes.Report] = MessageSettings.centerWhite,
    [MessageModes.GameHighlight] = MessageSettings.centerRed,
    [MessageModes.HotkeyUse] = MessageSettings.centerHKGreen,
    [MessageModes.Attention] = MessageSettings.bottomWhite,
    [MessageModes.BoostedCreature] = MessageSettings.centerWhite,
    [MessageModes.OfflineTrainning] = MessageSettings.centerWhite,
    [MessageModes.Transaction] = MessageSettings.centerWhite,
    [MessageModes.ValuableLoot] = MessageSettings.valuableLoot,

    [254] = MessageSettings.private
}

messagesPanel = nil

function init()
    for messageMode, _ in pairs(MessageTypes) do
        registerMessageMode(messageMode, displayMessage)
    end

    connect(g_game, 'onGameEnd', clearMessages)
    g_ui.importStyle('positionwindow')
    messagesPanel = g_ui.loadUI('textmessage', modules.game_interface.getRootPanel())
    messagesPanel.onGeometryChange = function()
        applyPosition()
    end
    applyPosition()
    connect(g_game, { onGameStart = addPanelRow })
    if g_game.isOnline() then
        addPanelRow()
    end
end

-- Where the look, loot, warning and event messages show on the game screen:
-- two sliders (0-100) in the "Screen Messages" window of the Mythicum panel.
-- 50/50 is the middle of the screen. Hotkey use messages stay in the middle.
local POSITION_X, POSITION_Y = 'screen_messages_x', 'screen_messages_y'
local PANEL_HEIGHT = 60 -- three message lines
local positionWindow, panelRow

local function savedPosition()
    local x = g_settings.getNumber(POSITION_X, 50)
    local y = g_settings.getNumber(POSITION_Y, 50)
    return math.max(0, math.min(100, x)), math.max(0, math.min(100, y))
end

function applyPosition()
    if not messagesPanel then
        return
    end
    local panel = messagesPanel:getChildById('centerTextMessagePanel')
    local private = messagesPanel:getChildById('privateLabel')
    if not panel or not private then
        return
    end
    local x, y = savedPosition()
    local width, height = messagesPanel:getWidth(), messagesPanel:getHeight()
    panel:breakAnchors()
    panel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    panel:addAnchor(AnchorTop, 'parent', AnchorTop)
    panel:setMarginLeft(math.floor(math.max(0, width - panel:getWidth()) * x / 100))
    panel:setMarginTop(math.floor(math.max(0, height - PANEL_HEIGHT) * y / 100))
    local align = x < 34 and AlignLeft or (x > 66 and AlignRight or AlignCenter)
    for _, label in ipairs(panel:getChildren()) do
        label:setTextAlign(align)
    end
    -- private messages use the top half, or the bottom half when the other
    -- messages sit in the top middle
    private:breakAnchors()
    private:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    if y < 45 and x >= 25 and x <= 75 then
        private:addAnchor(AnchorTop, 'parent', AnchorVerticalCenter)
        private:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    else
        private:addAnchor(AnchorTop, 'parent', AnchorTop)
        private:addAnchor(AnchorBottom, 'parent', AnchorVerticalCenter)
    end
end

local function showSample()
    local label = messagesPanel and messagesPanel:recursiveGetChildById('highCenterLabel')
    if not label then
        return
    end
    label:setText(tr('Messages show here.'))
    label:setColor(TextColors.green)
    label:setVisible(true)
    removeEvent(label.hideEvent)
    label.hideEvent = scheduleEvent(function()
        label:setVisible(false)
    end, 3000)
end

local function setPosition(x, y)
    g_settings.set(POSITION_X, x)
    g_settings.set(POSITION_Y, y)
    applyPosition()
    showSample()
end

function hidePositionWindow()
    if positionWindow then
        positionWindow:destroy()
        positionWindow = nil
    end
    if panelRow then
        panelRow:setOn(false)
    end
end

function togglePositionWindow()
    if positionWindow then
        hidePositionWindow()
        return
    end
    positionWindow = g_ui.createWidget('ScreenMessagesWindow', rootWidget)
    local x, y = savedPosition()
    local horizontal, vertical = positionWindow:getChildById('horizontal'), positionWindow:getChildById('vertical')
    horizontal:setValue(x)
    vertical:setValue(y)
    horizontal.onValueChange = function(widget, value)
        setPosition(value, vertical:getValue())
    end
    vertical.onValueChange = function(widget, value)
        setPosition(horizontal:getValue(), value)
    end
    positionWindow:getChildById('centerButton').onClick = function()
        horizontal:setValue(50)
        vertical:setValue(50)
    end
    positionWindow:getChildById('closeButton').onClick = hidePositionWindow
    positionWindow.onEscape = hidePositionWindow
    positionWindow:raise()
    positionWindow:focus()
    if panelRow then
        panelRow:setOn(true)
    end
    showSample()
end

function addPanelRow()
    if not panelRow and modules.game_brevespanel then
        panelRow = modules.game_brevespanel.addFeature('messages', togglePositionWindow)
    end
end

function terminate()
    for messageMode, _ in pairs(MessageTypes) do
        unregisterMessageMode(messageMode, displayMessage)
    end

    disconnect(g_game, 'onGameEnd', clearMessages)
    disconnect(g_game, { onGameStart = addPanelRow })
    hidePositionWindow()
    if panelRow then
        panelRow:destroy()
        panelRow = nil
    end
    clearMessages()
    messagesPanel:destroy()
    messagesPanel = nil
end

function calculateVisibleTime(text)
    return math.max(#text * 50, 4000)
end

function displayMessage(mode, text)

    if not g_game.isOnline() then
        return
    end
    if g_game.getClientVersion() >= 1300 then
        MessageTypes[MessageModes.Loot] = MessageSettings.loot
        MessageTypes[MessageModes.ValuableLoot] = MessageSettings.valuableLoot
        MessageTypes[MessageModes.Guild] = MessageSettings.statusOwn
        MessageTypes[MessageModes.Party] = MessageSettings.statusOwn
    else
        MessageTypes[MessageModes.PrivateFrom] = MessageSettings.privateNpcToPlayer
        MessageTypes[MessageModes.Loot] = MessageSettings.centerGreen
        MessageTypes[MessageModes.ValuableLoot] = MessageSettings.centerGreen
        MessageTypes[MessageModes.Guild] = MessageSettings.centerGreen
        MessageTypes[MessageModes.Party] = MessageSettings.centerGreen
        MessageTypes[MessageModes.MonsterSay] = MessageSettings.consoleOrange
        MessageTypes[MessageModes.MonsterYell] = MessageSettings.consoleOrange
    end
    local msgtype = MessageTypes[mode]
    if not msgtype then
        return
    end

    if msgtype == MessageSettings.none then
        return
    end

    if msgtype.consoleTab ~= nil and
        (msgtype.consoleOption == nil or modules.client_options.getOption(msgtype.consoleOption)) then
        if msgtype == MessageSettings.loot or msgtype == MessageSettings.valuableLoot then
            local lootColoredText = ItemsDatabase.setColorLootMessage(text)
            local lootTabName = tr(msgtype.consoleTab)
            local targetTab = modules.game_console.getTab(lootTabName) and lootTabName or tr("Server Log")
            modules.game_console.addText(lootColoredText, msgtype, targetTab)
        else
            modules.game_console.addText(text, msgtype, tr(msgtype.consoleTab))
        end
    end

    if msgtype.screenTarget then
        local label = messagesPanel:recursiveGetChildById(msgtype.screenTarget)
        if msgtype == MessageSettings.loot and not modules.client_options.getOption('showLootMessagesOnScreen') then
            return
        elseif msgtype == MessageSettings.loot or msgtype == MessageSettings.valuableLoot then
            local coloredText = ItemsDatabase.setColorLootMessage(text)
            label:setColoredText(coloredText)
        else
            label:setText(text)
            label:setColor(msgtype.color)
        end

        label:setVisible(true)
        removeEvent(label.hideEvent)
        label.hideEvent = scheduleEvent(function()
            label:setVisible(false)
        end, calculateVisibleTime(text))
    end
end

function displayPrivateMessage(text)
    if not g_game.isOnline() then
        return
    end
    
    local msgtype = MessageSettings.private
    if not msgtype or not msgtype.screenTarget then
        return
    end
    
    local label = messagesPanel:recursiveGetChildById(msgtype.screenTarget)
    if not label then
        return
    end
    
    label:setText(text)
    label:setColor(msgtype.color)
    label:setVisible(true)
    removeEvent(label.hideEvent)
    label.hideEvent = scheduleEvent(function()
        label:setVisible(false)
    end, calculateVisibleTime(text))
end

function displayStatusMessage(text)
    displayMessage(MessageModes.Status, text)
end

function displayFailureMessage(text)
    displayMessage(MessageModes.Failure, text)
end

function displayGameMessage(text)
    displayMessage(MessageModes.Game, text)
end

function displayBroadcastMessage(text)
    displayMessage(MessageModes.Warning, text)
end

function clearMessages()
    for _i, child in pairs(messagesPanel:recursiveGetChildren()) do
        if child:getId():match('Label') then
            child:hide()
            removeEvent(child.hideEvent)
        end
    end
end

function LocalPlayer:onAutoWalkFail(player)
    modules.game_textmessage.displayFailureMessage(tr('There is no way.'))
end
