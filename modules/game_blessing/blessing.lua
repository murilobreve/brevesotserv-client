BlessingController = Controller:new()

local GLOWSTATE ={
    Disabled = 1,
    Normal = 2,
    Green = 3
}

local VISUAL_STATE_IMAGES = {
    [GLOWSTATE.Disabled] = '/images/inventory/button_blessings_grey',
    [GLOWSTATE.Normal] = '/images/inventory/button_blessings_gold',
    [GLOWSTATE.Green] = '/images/inventory/button_blessings_green',
}

function BlessingController:onInit()
    BlessingController:registerEvents(LocalPlayer, {
        onBlessingsChange = onBlessingsChange
    })
end

function BlessingController:onTerminate()
    -- BlessingController:findWidget("#blessingsWindow"):destroy()
end

function BlessingController:onGameStart()
    if g_game.getClientVersion() >= 1000 then
        BlessingController:registerEvents(g_game, {
            onUpdateBlessDialog = onUpdateBlessDialog
        })
    else
        BlessingController:scheduleEvent(function()
            g_modules.getModule("game_blessing"):unload()
        end, 100, "unloadModule")
    end
end

function BlessingController:onGameEnd()
    hide()
end

function BlessingController:close()
    hide()
end

function BlessingController:showHistory()
    local ui = BlessingController.ui
    if ui.historyPanel:isVisible() then
        BlessingController.historyButtonText = "History"
        setBlessingView()
    else
        BlessingController.historyButtonText = "Back"
        setHistoryView()
    end
end

function setHistoryView()
    local ui = BlessingController.ui
    ui.blessingsRecordPanel:hide()
    ui.promotionPanel:hide()
    ui.deathPenaltyPanel:hide()
    ui.historyPanel:show()
end

function setBlessingView()
    local ui = BlessingController.ui
    ui.blessingsRecordPanel:show()
    ui.promotionPanel:show()
    ui.deathPenaltyPanel:show()
    ui.historyPanel:hide()
end

function show()
    BlessingController.historyButtonText = "History"
    g_ui.importStyle("style.otui")
    BlessingController:loadHtml('blessing.html')
    g_game.requestBless()
    BlessingController.ui:show()
    BlessingController.ui:raise()
    BlessingController.ui:focus()
    setBlessingView()
end

function hide()
    if BlessingController.ui then
        BlessingController:unloadHtml()
    end
end

function toggle()
    if BlessingController.ui and BlessingController.ui:isVisible() then
        hide()
    else
        show()
    end
end

function onUpdateBlessDialog(data)
    local ui = BlessingController.ui
    ui.blessingsRecordPanel:destroyChildren()
    for i, entry in ipairs(data.blesses) do
        local label = g_ui.createWidget("blessingTEST", ui.blessingsRecordPanel)
        local totalCount = entry.playerBlessCount + entry.store
        label.text:setText(entry.playerBlessCount .. " (" .. entry.store .. ")")
        label.enabled:setImageSource(totalCount >= 1 and ("images/" .. i .. "_on") or ("images/" .. i))
    end
    local promotionText = (data.promotion ~= 0) and
                              "Your character is promoted and your account has Premium\nstatus. As a result, your XP loss is reduced by {30%, #f75f5f}." or
                              "Your character is promoted and your account has Premium\nstatus. As a result, your XP loss is reduced by {0%, #f75f5f}."
    ui.promotionPanel.promotionStatusLabel:setColoredText(promotionText)
    ui.deathPenaltyPanel.fightRulesLabel:setColoredText(
        "- Depending on the fair fight rules, you will lose between {" .. data.pvpMinXpLoss .. ", #f75f5f} and {" ..
            data.pvpMaxXpLoss .. "%, #f75f5f} less XP and skill points \nupon your next PvP death.")
    ui.deathPenaltyPanel.expLossLabel:setColoredText("- You will lose {" .. data.pveExpLoss ..
                                                         "%, #f75f5f}% less XP and skill points upon your next PvE death.")
    ui.deathPenaltyPanel.containerLossLabel:setColoredText("- There is a {" .. data.equipPvpLoss ..
                                                               "%, #f75f5f} chance that you will lose your equipped container on your next death.")

    ui.deathPenaltyPanel.equipmentLossLabel:setColoredText("- There is a {" .. data.equipPveLoss ..
                                                               "%, #f75f5f} chance that you will lose items upon your next death.")
    ui.historyPanel.historyScrollArea:destroyChildren()
    local headerRow = g_ui.createWidget("historyData", ui.historyPanel.historyScrollArea)
    headerRow:setBackgroundColor("#363636")
    headerRow:setBorderColor("#00000077")
    headerRow:setBorderWidth(1)
    headerRow.rank:setText("date")
    headerRow.name:setText("Event")
    headerRow.rank:setColor("#c0c0c0")
    headerRow.name:setColor("#c0c0c0")
    for index, entry in ipairs(data.logs) do
        local row = g_ui.createWidget("historyData", ui.historyPanel.historyScrollArea)
        local date = os.date("%Y-%m-%d, %H:%M:%S", entry.timestamp)
        row:setBackgroundColor(index % 2 == 0 and "#ffffff12" or "#00000012")
        row.rank:setText(date)
        row.name:setText(entry.historyMessage)
    end
end

function BlessingController:onClickSendStore()
    modules.game_store.toggle()
    g_game.sendRequestStorePremiumBoost()
end

-- The server's blessing packet (0x9C) carries the glow of the equipment
-- (1 or 0) and a state: 1 = not all regular blessings, 2 = the five
-- regular ones, 3 = all of them. The first field is no list of blessings,
-- so the button follows the state, on both layouts of the inventory.
local BLESS_TOOLTIPS = {
    [GLOWSTATE.Disabled] = 'You are not protected by all the blessings.',
    [GLOWSTATE.Normal] = 'You are protected by the five regular blessings.',
    [GLOWSTATE.Green] = 'You are protected by all the blessings.',
}

function onBlessingsChange(player, blessings, oldBlessings, blessVisualState)
    local hasAdventurerBlessing = Bit.hasBit(blessings, Blessings.Adventurer)
    if hasAdventurerBlessing ~= Bit.hasBit(oldBlessings, Blessings.Adventurer) then
        modules.game_inventory.toggleAdventurerStyle(hasAdventurerBlessing)
    end
    local image = VISUAL_STATE_IMAGES[blessVisualState]
    local tooltip = BLESS_TOOLTIPS[blessVisualState]
    for _, button in ipairs(modules.game_inventory.getButtonsBlessings()) do
        if image then
            button:setImageSource(image)
        end
        if tooltip then
            button:setTooltip(tr(tooltip))
        end
    end
end
