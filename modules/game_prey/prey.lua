-- sponsored by kivera-global.com
-- remade by Vithrax#5814
Prey = {}
preyWindow = nil
preyButton = nil
local preyTrackerButton
local msgWindow
-- a confirmation box open over the window (the window is hidden meanwhile)
local confirmWindow
local bankGold = 0
local inventoryGold = 0
-- list reroll price: the server sends it at login (level x gold per level)
-- and never again, so it follows the local player's level from there
local rerollPrice = 0
local rerollPricePerLevel
local bonusRerolls = 0
-- Prey Wildcards: a bonus reroll and the Automatic Bonus Reroll cost
-- bonusRerollPrice; choosing any creature and Lock Prey cost selectListPrice
-- (the server's 'wildcard' and 'directly' prices, onPreyRerollPrice)
local DEFAULT_BONUS_REROLL_PRICE = 1
local DEFAULT_SELECT_LIST_PRICE = 5
local bonusRerollPrice = DEFAULT_BONUS_REROLL_PRICE
local selectListPrice = DEFAULT_SELECT_LIST_PRICE
-- free list reroll: the moment (g_clock seconds) each slot gets it, and the
-- full wait (the server's preyFreeRerollTime, 20 hours) for the bar
local FREE_REROLL_TIME = 72000
local freeRerollDeadlineBySlot = {}
local freeRerollEvent

-- the slot states of the server (Otc::PreyState_t), for the Kill Tracker
local PREY_STATE_LOCKED = 0
local PREY_STATE_INACTIVE = 1
local PREY_STATE_ACTIVE = 2
local PREY_STATE_SELECTION = 3
local PREY_STATE_SELECTION_CHANGE_MONSTER = 4
local PREY_STATE_LIST_SELECTION = 5

local PREY_BONUS_DAMAGE_BOOST = 0
local PREY_BONUS_DAMAGE_REDUCTION = 1
local PREY_BONUS_XP_BONUS = 2
local PREY_BONUS_IMPROVED_LOOT = 3
local PREY_BONUS_NONE = 4

local PREY_ACTION_LISTREROLL = 0
local PREY_ACTION_BONUSREROLL = 1
local PREY_ACTION_MONSTERSELECTION = 2
local PREY_ACTION_REQUEST_ALL_MONSTERS = 3
local PREY_ACTION_CHANGE_FROM_ALL = 4
local PREY_ACTION_OPTION = 5
local PREY_OPTION_UNTOGGLE = 0
local PREY_OPTION_TOGGLE_AUTOREROLL = 1
local PREY_OPTION_TOGGLE_LOCK_PREY = 2

local preyDescription = {}

local raceEntriesBySlot = {}
local selectedRaceEntryBySlot = {}
local selectedRaceWidgetBySlot = {}
local raceSearchTextsBySlot = {}
-- the full creature list (~750 races): its race ids and rows, built once per
-- list; the search only shows and hides rows, a moment after the last key
local RACE_SEARCH_DELAY = 150
local raceIdsBySlot = {}
local raceRowsBySlot = {}
local raceSearchEventBySlot = {}
local listModeBySlot = {}
-- Choose was sent: off until the next prey packet of the slot
local choosePendingBySlot = {}
local resettingWindow = false

local refreshRaceList
local setRaceSelection
local updateRaceSelectionDisplay
local restoreRaceListItemBackground
local setWidgetTreePhantom
local updatePickSpecificPreyButton
local refreshRerollButtonState
local showListRerollConfirmation
local updateFreeRerollDisplay
local refreshBalanceState
local clearRaceList
local startFreeRerollTimer
local stopFreeRerollTimer
local destroyConfirmWindow

function bonusDescription(bonusType, bonusValue, bonusGrade)
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return 'Damage bonus (' .. bonusGrade .. '/10)'
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return 'Damage reduction bonus (' .. bonusGrade .. '/10)'
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return 'XP bonus (' .. bonusGrade .. '/10)'
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return 'Loot bonus (' .. bonusGrade .. '/10)'
    else
        return 'Unknown bonus'
    end
    return 'Unknown bonus'
end

function timeleftTranslation(timeleft, forPreyTimeleft) -- in seconds
    if timeleft == 0 then
        if forPreyTimeleft then
            return tr('infinite bonus')
        end
        return tr('Free')
    end
    local hours = string.format('%02.f', math.floor(timeleft / 3600))
    local mins = string.format('%02.f', math.floor(timeleft / 60 - (hours * 60)))
    return hours .. ':' .. mins
end

function init()
    connect(g_game, {
        onGameStart = check,
        onGameEnd = onGameEnd,
        onResourcesBalanceChange = Prey.onResourcesBalanceChange,
        onPreyFreeRerolls = onPreyFreeRerolls,
        onPreyTimeLeft = onPreyTimeLeft,
        onPreyRerollPrice = onPreyRerollPrice,
        onPreyLocked = onPreyLocked,
        onPreyInactive = onPreyInactive,
        onPreyActive = onPreyActive,
        onPreySelection = onPreySelection,
        onPreySelectionChangeMonster = onPreySelectionChangeMonster,
        onPreyListSelection = onPreyListSelection,
        onPreyWildcardSelection = onPreyWildcardSelection
    })
    connect(LocalPlayer, {
        onLevelChange = onPlayerLevelChange
    })

    preyWindow = g_ui.displayUI('prey')
    preyWindow:hide()
    preyTracker = g_ui.createWidget('PreyTracker', modules.game_interface.getRightPanel())
    preyTracker:setup()
    preyTracker:setContentMaximumHeight(110)
    preyTracker:setContentMinimumHeight(70)
    preyTracker:hide()

    -- Hide buttons similar to unjustifiedpoints implementation
    local toggleFilterButton = preyTracker:recursiveGetChildById('toggleFilterButton')
    if toggleFilterButton then
        toggleFilterButton:setVisible(false)
    end

    local contextMenuButton = preyTracker:recursiveGetChildById('contextMenuButton')
    if contextMenuButton then
        contextMenuButton:setVisible(false)
    end

    local newWindowButton = preyTracker:recursiveGetChildById('newWindowButton')
    if newWindowButton then
        newWindowButton:setVisible(false)
    end

    -- Set up the miniwindow title and icon
    local titleWidget = preyTracker:getChildById('miniwindowTitle')
    if titleWidget then
        titleWidget:setText(tr('Prey'))
    else
        -- Fallback to old method if miniwindowTitle doesn't exist
        preyTracker:setText(tr('Prey'))
    end

    local iconWidget = preyTracker:getChildById('miniwindowIcon')
    if iconWidget then
        iconWidget:setImageSource('/images/game/prey/icon-prey-widget')
    end

    -- Position lockButton where toggleFilterButton was (to the left of minimize button)
    local lockButton = preyTracker:recursiveGetChildById('lockButton')
    local minimizeButton = preyTracker:recursiveGetChildById('minimizeButton')

    if lockButton and minimizeButton then
        lockButton:breakAnchors()
        lockButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
        lockButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
        lockButton:setMarginRight(7) -- Same margin as toggleFilterButton had
        lockButton:setMarginTop(0)
    end

    if g_game.isOnline() then
        check()
    end
    setUnsupportedSettings()
end

local pickSpecificPreyBonusBySlot = {}

-- the texts stay in English here and go through tr() when they are shown
local pickSpecificPreyDescriptionDefault =
'If you like to select another prey creature, click here to choose from all available creatures.\nThe newly selected prey will be active for 2 hours hunting time again.\nYour current bonus will not be affected.'
local pickSpecificPreyDescriptionTemplate =
'If you like to select another prey creature, click here to choose from all available creatures.\nThe newly selected prey will be active for 2 hours hunting time again.\nYour current bonus (%s +%d%%) will not be affected.'

local descriptionTable = {
    ['shopPermButton'] =
    'Go to the Store to purchase the Permanent Prey Slot. Once you have completed the purchase, you can activate a prey here, no matter if your character is on a free or a Premium account.',
    ['shopTempButton'] = 'You can activate this prey whenever your account has Premium Status.',
    ['preyWindow'] = 'Move the mouse over a button to see what it does.',
    ['noBonusIcon'] =
    'This prey is not available for your character yet.\nCheck the large blue button to learn how to unlock this prey slot.',
    ['selectPrey'] =
    'Click here to get a bonus with a higher value. The bonus for your prey will be selected randomly from one of the following: damage boost, damage reduction, bonus XP, improved loot. Your prey will be active for 2 hours hunting time again. Your prey creature will stay the same.',
    ['pickSpecificPrey'] = pickSpecificPreyDescriptionDefault,
    ['rerollButton'] =
    'If you like to select another prey creature, click here to get a new list with 9 creatures to choose from.\nThe newly selected prey will be active for 2 hours hunting time again.',
    ['preyCandidate'] = 'Select a new prey creature for the next 2 hours hunting time.',
    ['choosePreyButton'] =
    'Click on this button to confirm selected monsters as your prey creature for the next 2 hours hunting time.',
    -- %d: the price in Prey Wildcards
    ['automaticBonusReroll'] =
    'Do you want to enable the Automatic Bonus Reroll?\nEach time the Automatic Bonus Reroll is triggered, %d of your Prey Wildcards will be consumed.',
    ['preyLock'] =
    'Do you want to enable the Lock Prey?\nEach time the Lock Prey is triggered, %d of your Prey Wildcards will be consumed.'
}

local function getSlotIndexFromWidget(widget)
    while widget do
        local id = widget:getId()
        if id then
            local slotNumber = id:match('^slot(%d+)$')
            if slotNumber then
                return tonumber(slotNumber) - 1
            end
        end
        widget = widget:getParent()
    end

    return nil
end

local function getPickSpecificPreyDescription(slot)
    local bonusInfo = pickSpecificPreyBonusBySlot[slot]

    if bonusInfo then
        return tr(pickSpecificPreyDescriptionTemplate, getBonusDescription(bonusInfo.type), bonusInfo.value)
    end

    return tr(pickSpecificPreyDescriptionDefault)
end

local function setPickSpecificPreyBonus(slot, bonusType, bonusValue)
    if slot == nil then
        return
    end

    if bonusType and bonusType ~= PREY_BONUS_NONE and bonusValue ~= nil then
        pickSpecificPreyBonusBySlot[slot] = {
            type = bonusType,
            value = bonusValue
        }
    else
        pickSpecificPreyBonusBySlot[slot] = nil
    end
end

-- what the slot's active prey gives (the tracker's tooltip, without the
-- line about clicking)
local function getActivePreyDescription(slot)
    local info = preyDescription[slot]
    if not info then
        return ''
    end
    return tr('Creature: %s\nDuration: %s\nValue: %d/10\nType: %s\n%s', info.name,
        timeleftTranslation(info.timeLeft or 0, true), info.grade or 0, getBonusDescription(info.bonusType),
        getTooltipBonusDescription(info.bonusType, info.bonusValue))
end

local function getActivePreyTooltip(slot)
    return getActivePreyDescription(slot) .. '\n\n' .. tr('Click in this window to open the prey dialog.')
end

function onHover(widget)
    if type(widget) == 'string' then
        local desc = descriptionTable[widget]
        return preyWindow.description:setText(desc and tr(desc) or '')
    elseif type(widget) == 'number' then
        return preyWindow.description:setText(getActivePreyDescription(widget))
    end
    if widget and widget:isVisible() then
        local id = widget:getId()
        if id == 'pickSpecificPrey' then
            local slot = getSlotIndexFromWidget(widget)
            if slot then
                preyWindow.description:setText(getPickSpecificPreyDescription(slot))
                return
            end
        end

        local desc = descriptionTable[id]
        if desc then
            preyWindow.description:setText(tr(desc))
        end
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = check,
        onGameEnd = onGameEnd,
        onResourcesBalanceChange = Prey.onResourcesBalanceChange,
        onPreyFreeRerolls = onPreyFreeRerolls,
        onPreyTimeLeft = onPreyTimeLeft,
        onPreyRerollPrice = onPreyRerollPrice,
        onPreyLocked = onPreyLocked,
        onPreyInactive = onPreyInactive,
        onPreyActive = onPreyActive,
        onPreySelection = onPreySelection,
        onPreySelectionChangeMonster = onPreySelectionChangeMonster,
        onPreyListSelection = onPreyListSelection,
        onPreyWildcardSelection = onPreyWildcardSelection
    })
    disconnect(LocalPlayer, {
        onLevelChange = onPlayerLevelChange
    })

    stopFreeRerollTimer()
    destroyConfirmWindow()
    for slot, event in pairs(raceSearchEventBySlot) do
        removeEvent(event)
    end
    raceSearchEventBySlot = {}

    if preyButton then
        preyButton:destroy()
    end
    if preyTrackerButton then
        preyTrackerButton:destroy()
    end
    preyWindow:destroy()
    preyTracker:destroy()
    if msgWindow then
        msgWindow:destroy()
        msgWindow = nil
    end
end

-- the Prey Wildcard prices on the card labels
local function refreshCardPrices()
    for _, slot in ipairs({ 'slot1', 'slot2', 'slot3' }) do
        local panel = preyWindow[slot]
        for _, state in ipairs({ panel.active, panel.inactive }) do
            state.select.price.text:setText(tostring(selectListPrice))
        end
        panel.active.autoRerollPrice.text:setText(tostring(bonusRerollPrice))
        panel.active.lockPreyPrice.text:setText(tostring(selectListPrice))
        panel.active.choose.price.text:setText(tostring(bonusRerollPrice))
    end
end

function setUnsupportedSettings()
    refreshCardPrices()
end

function check()
    if g_game.getFeature(GamePrey) then
        if not preyButton then
            preyButton = modules.game_mainpanel.addToggleButton('preyButton', tr('Prey Dialog'),
                '/images/options/button_preydialog', toggle)
        end
        if g_game.getFeature(GameTaskboard) then
            if preyTrackerButton then
                preyTrackerButton:destroy()
                preyTrackerButton = nil
            end
            return
        end
        if not preyTrackerButton then
            preyTrackerButton = modules.game_mainpanel.addToggleButton('preyTrackerButton', tr('Prey Tracker'),
                '/images/options/button_prey', toggleTracker)
        end
    elseif preyButton then
        preyButton:destroy()
        preyButton = nil
    end
end

function toggleTracker()
    if preyTracker:isVisible() then
        preyTracker:hide()
        onMiniWindowClose()
    else
        if not preyTracker:getParent() then
            local panel = modules.game_interface.findContentPanelAvailable(preyTracker, preyTracker:getMinimumHeight())
            if not panel then
                return
            end

            panel:addChild(preyTracker)
        end
        preyTracker:show()
        onMiniWindowOpen()
    end
end

local function resetPreyWindowState()
    if not preyWindow then
        return
    end

    preyWindow.description:setText('')
    preyWindow.gold.text:setText('0')
    preyWindow.wildCards.text:setText('0')

    -- a clean window for the next login; the Kill Tracker is not told
    resettingWindow = true
    for slot = 0, 2 do
        onPreyInactive(slot, 0, 0)

        local prey = preyWindow['slot' .. (slot + 1)]
        if prey then
            if prey.title then
                prey.title:setText('')
            end

            if prey.inactive and prey.inactive.list then
                prey.inactive.list:setVisible(true)
                prey.inactive.list:destroyChildren()
            end

            if prey.inactive then
                if prey.inactive.fullList then
                    clearFullListEntries(prey.inactive.fullList)
                    prey.inactive.fullList:setVisible(false)
                end

                if prey.inactive.preview then
                    resetPreyPreviewWidget(prey.inactive.preview)
                    prey.inactive.preview:setVisible(false)
                end

                if prey.inactive.select then
                    prey.inactive.select:setVisible(true)
                end

                if prey.inactive.reroll then
                    prey.inactive.reroll:setVisible(true)
                end
            end

            if prey.active and prey.active.creatureAndBonus then
                local creatureAndBonus = prey.active.creatureAndBonus
                if creatureAndBonus.timeLeft then
                    creatureAndBonus.timeLeft:setPercent(0)
                    creatureAndBonus.timeLeft:setText('')
                end

                if creatureAndBonus.bonus and creatureAndBonus.bonus.grade then
                    creatureAndBonus.bonus.grade:destroyChildren()
                end
            end
        end
    end

    preyDescription = {}
    rerollPrice = 0
    rerollPricePerLevel = nil
    bonusRerollPrice = DEFAULT_BONUS_REROLL_PRICE
    selectListPrice = DEFAULT_SELECT_LIST_PRICE
    refreshCardPrices()
    bonusRerolls = 0
    bankGold = 0
    inventoryGold = 0
    raceEntriesBySlot = {}
    selectedRaceEntryBySlot = {}
    selectedRaceWidgetBySlot = {}
    freeRerollDeadlineBySlot = {}
    choosePendingBySlot = {}
    resettingWindow = false
end

function onGameEnd()
    resetPreyWindowState()
    hide()
end

local function refreshFreeRerollTimers()
    for slot = 0, 2 do
        updateFreeRerollDisplay(slot)
    end
end

-- the free reroll countdown moves once a minute, only while the window is open
startFreeRerollTimer = function()
    if not freeRerollEvent then
        freeRerollEvent = cycleEvent(refreshFreeRerollTimers, 60000)
    end
end

stopFreeRerollTimer = function()
    if freeRerollEvent then
        removeEvent(freeRerollEvent)
        freeRerollEvent = nil
    end
end

-- a confirmation left open when the window goes away (logout, Escape, the
-- prey button) goes with it, without bringing the window back
destroyConfirmWindow = function()
    local window = confirmWindow
    confirmWindow = nil
    if window and not window:isDestroyed() then
        window.onDestroy = nil
        window:destroy()
    end
end

function hide()
    stopFreeRerollTimer()
    destroyConfirmWindow()
    preyWindow:hide()
    if preyButton then
        preyButton:setOn(false)
    end
    if msgWindow then
        msgWindow:destroy()
        msgWindow = nil
    end
end

function show()
    if not g_game.getFeature(GamePrey) then
        return hide()
    end
    preyWindow:show()
    preyWindow:raise()
    preyWindow:focus()
    if preyButton then
        preyButton:setOn(true)
    end
    refreshBalanceState()
    refreshFreeRerollTimers()
    startFreeRerollTimer()
    g_game.preyRequest() -- update preys, it's for tibia 12
end

function toggle()
    if preyWindow:isVisible() then
        return hide()
    end
    show()
end

function onMiniWindowOpen()
    if preyTrackerButton then
        preyTrackerButton:setOn(true)
    end
end

function onMiniWindowClose()
    if preyTrackerButton then
        preyTrackerButton:setOn(false)
    end
end

-- the Kill Tracker of game_taskboard: that module is sandboxed, so its
-- Tracker table lives in its environment (modules.game_taskboard)
local function getKillTracker()
    local taskboard = modules.game_taskboard
    local tracker = type(taskboard) == 'table' and rawget(taskboard, 'Tracker')
    return type(tracker) == 'table' and tracker.Prey or nil
end

local function updateKillTracker(slot, state, outfit)
    if resettingWindow then
        return
    end
    local killTracker = getKillTracker()
    local prey = preyWindow and preyWindow['slot' .. (slot + 1)]
    if killTracker and killTracker.updateWidget and prey then
        killTracker.updateWidget(slot, state, outfit, prey, show)
    end
end

-- the tracker row of a slot that was locked comes back with the slot
local function showTrackerRow(tracker)
    if not tracker:isExplicitlyVisible() then
        tracker:show()
        preyTracker:setContentMaximumHeight(110)
    end
end

local function setTrackerInactive(slot)
    preyDescription[slot] = nil
    local tracker = preyTracker.contentsPanel['slot' .. (slot + 1)]
    if not tracker then
        return
    end
    showTrackerRow(tracker)
    tracker.creature:hide()
    tracker.noCreature:show()
    tracker.creatureName:setText(tr('Inactive'))
    tracker.time:setPercent(0)
    tracker.preyType:setImageSource('/images/game/prey/prey_no_bonus')
    local tooltip = tr('Inactive prey.\n\nClick in this window to open the prey dialog.')
    for i, element in pairs({ tracker.creatureName, tracker.creature, tracker.preyType, tracker.time }) do
        element:setTooltip(tooltip)
        element.onClick = function()
            show()
        end
    end
end

local function getPlayerLevel()
    local player = g_game.getLocalPlayer()
    return player and player:getLevel() or 0
end

-- the list reroll price for the local player's level now
local function getCurrentRerollPrice()
    local level = getPlayerLevel()
    if rerollPricePerLevel and level > 0 then
        return math.floor(rerollPricePerLevel * level + 0.5)
    end
    return rerollPrice
end

-- seconds until the slot's free list reroll (nil: no slot data yet)
local function getFreeRerollTimeLeft(slot)
    local deadline = freeRerollDeadlineBySlot[slot]
    if not deadline then
        return nil
    end
    return math.max(0, deadline - g_clock.seconds())
end

-- a deadline that has passed is a free reroll, even before the server says so
local function isFreeReroll(slot)
    local timeLeft = getFreeRerollTimeLeft(slot)
    return timeLeft ~= nil and timeLeft <= 0
end

local function getListRerollPrice(slot)
    if isFreeReroll(slot) then
        return 0
    end
    return getCurrentRerollPrice()
end

updateFreeRerollDisplay = function(slot)
    local prey = preyWindow and preyWindow['slot' .. (slot + 1)]
    if not prey then
        return
    end
    local timeLeft = getFreeRerollTimeLeft(slot)
    local percent = timeLeft and math.min(100, timeLeft / FREE_REROLL_TIME * 100) or 0
    -- whole minutes, rounded up: "00:00" never shows, it is free then
    local timeText = timeLeft and timeleftTranslation(math.ceil(timeLeft / 60) * 60) or ''
    local priceText = isFreeReroll(slot) and tr('Free') or comma_value(getCurrentRerollPrice())
    for i, panel in pairs({ prey.active, prey.inactive }) do
        if panel and panel.reroll and panel.reroll.button and panel.reroll.price then
            panel.reroll.button.time:setPercent(percent)
            panel.reroll.button.time:setText(timeText)
            panel.reroll.price.text:setText(priceText)
        end
    end

    refreshRerollButtonState(slot)
end

function onPreyFreeRerolls(slot, timeleft) -- minutes (older protocols)
    freeRerollDeadlineBySlot[slot] = g_clock.seconds() + timeleft * 60
    updateFreeRerollDisplay(slot)
end

function onPreyTimeLeft(slot, timeLeft)
    if preyDescription[slot] then
        preyDescription[slot].timeLeft = timeLeft
    end
    local percent = (timeLeft / (2 * 60 * 60)) * 100
    -- tracker
    local tracker = preyTracker.contentsPanel['slot' .. (slot + 1)]
    if tracker then
        tracker.time:setPercent(percent)
        if preyDescription[slot] then
            local text = getActivePreyTooltip(slot)
            for i, element in pairs({ tracker.creatureName, tracker.creature, tracker.preyType, tracker.time }) do
                element:setTooltip(text)
            end
        end
    end
    local killTracker = getKillTracker()
    if killTracker and killTracker.updateTimeLeft then
        killTracker.updateTimeLeft(slot, timeLeft)
    end
    -- main window
    local prey = preyWindow['slot' .. (slot + 1)]
    if not prey then
        return
    end
    local progressbar = prey.active.creatureAndBonus.timeLeft
    progressbar:setPercent(percent)
    progressbar:setText(timeleftTranslation(timeLeft, true))
end

-- price: list reroll in gold (level x gold per level); wildcard: Prey
-- Wildcards for a bonus reroll; directly: for choosing any creature
function onPreyRerollPrice(price, wildcard, directly)
    rerollPrice = price
    local level = getPlayerLevel()
    rerollPricePerLevel = level > 0 and price / level or nil
    if wildcard and wildcard > 0 then
        bonusRerollPrice = wildcard
    end
    if directly and directly > 0 then
        selectListPrice = directly
    end
    refreshCardPrices()

    for slot = 0, 2 do
        updateFreeRerollDisplay(slot)
    end
    refreshBalanceState()
end

-- the price follows the level (onLevelChange also comes with every bit of
-- experience: only a new level does anything)
function onPlayerLevelChange(localPlayer, level, levelPercent, oldLevel)
    if level == oldLevel or not rerollPricePerLevel then
        return
    end
    for slot = 0, 2 do
        updateFreeRerollDisplay(slot)
    end
end

function setTimeUntilFreeReroll(slot, timeUntilFreeReroll) -- seconds
    -- a time already past comes wrapped around (unsigned) from the server
    if timeUntilFreeReroll > 720000 then
        timeUntilFreeReroll = 0
    end
    freeRerollDeadlineBySlot[slot] = g_clock.seconds() + timeUntilFreeReroll
    updateFreeRerollDisplay(slot)
end

function onPreyLocked(slot, unlockState, timeUntilFreeReroll, wildcards)
    choosePendingBySlot[slot] = nil
    setPickSpecificPreyBonus(slot)
    preyDescription[slot] = nil
    clearRaceList(slot)

    -- tracker
    local tracker = preyTracker.contentsPanel['slot' .. (slot + 1)]
    if tracker then
        tracker:hide()
        preyTracker:setContentMaximumHeight(preyTracker:getHeight())
    end
    -- main window
    local prey = preyWindow['slot' .. (slot + 1)]
    if prey then
        prey.bonusType = nil
        prey.lockType = nil
        prey.title:setText(tr('Locked prey slot'))
        prey.inactive:hide()
        prey.active:hide()
        prey.locked:show()
        -- this server sells the third slot in the Store; the second one
        -- opens with a Premium account
        local storeSlot = slot == 2
        prey.locked.perm:setVisible(storeSlot)
        prey.locked.temp:setVisible(not storeSlot)
    end
    updateKillTracker(slot, PREY_STATE_LOCKED)
end

function onPreyInactive(slot, timeUntilFreeReroll, wildcards)
    choosePendingBySlot[slot] = nil
    -- tracker
    setTrackerInactive(slot)
    -- main window
    setTimeUntilFreeReroll(slot, timeUntilFreeReroll)
    clearRaceList(slot)
    local prey = preyWindow['slot' .. (slot + 1)]
    if not prey then
        return
    end
    prey.bonusType = nil
    prey.lockType = nil
    prey.active:hide()
    prey.locked:hide()
    prey.inactive:show()
    setInactiveMode(slot, false, prey)
    local rerollButton = prey.inactive.reroll and prey.inactive.reroll.button and
        prey.inactive.reroll.button.rerollButton
    if rerollButton then
        rerollButton.onClick = function()
            showListRerollConfirmation(slot)
        end
    end

    setPickSpecificPreyBonus(slot)
    updatePickSpecificPreyButton(slot)
    updateKillTracker(slot, PREY_STATE_INACTIVE)
end

function setBonusGradeStars(slot, grade)
    local prey = preyWindow['slot' .. (slot + 1)]
    local gradePanel = prey.active.creatureAndBonus.bonus.grade

    gradePanel:destroyChildren()
    for i = 1, 10 do
        if i <= grade then
            local widget = g_ui.createWidget('Star', gradePanel)
            widget.onHoverChange = function(widget, hovered)
                onHover(slot)
            end
        else
            local widget = g_ui.createWidget('NoStar', gradePanel)
            widget.onHoverChange = function(widget, hovered)
                onHover(slot)
            end
        end
    end
end

function getBigIconPath(bonusType)
    local path = '/images/game/prey/'
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return path .. 'prey_bigdamage'
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return path .. 'prey_bigdefense'
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return path .. 'prey_bigxp'
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return path .. 'prey_bigloot'
    end
    return path .. 'prey_bignobonus'
end

function getSmallIconPath(bonusType)
    local path = '/images/game/prey/'
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return path .. 'prey_damage'
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return path .. 'prey_defense'
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return path .. 'prey_xp'
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return path .. 'prey_loot'
    end
    return path .. 'prey_no_bonus'
end

function getBonusDescription(bonusType)
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return tr('Damage Boost')
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return tr('Damage Reduction')
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return tr('XP Bonus')
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return tr('Improved Loot')
    end
    return tr('Unknown bonus')
end

function getTooltipBonusDescription(bonusType, bonusValue)
    bonusValue = tonumber(bonusValue) or 0
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return tr('You deal +%d%% extra damage against your prey creature.', bonusValue)
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return tr('You take %d%% less damage from your prey creature.', bonusValue)
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return tr('Killing your prey creature rewards +%d%% extra XP.', bonusValue)
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return tr('Your creature has a +%d%% chance to drop additional loot.', bonusValue)
    end
    return ''
end

function capitalFormatStr(str)
    local formatted = ''
    str = string.split(str, ' ')
    for i, word in ipairs(str) do
        formatted = formatted .. ' ' .. (string.gsub(word, '^%l', string.upper))
    end
    return formatted:trim()
end

local function getPreySlotWidget(slot)
    if not preyWindow then
        return nil
    end
    return preyWindow['slot' .. (slot + 1)]
end

local function setChoosePreyButtonEnabled(button, enabled)
    if not button then
        return
    end

    local imagePath
    if enabled then
        button:enable()
        imagePath = '/images/game/prey/prey_choose.png'
    else
        button:disable()
        imagePath = '/images/game/prey/prey_choose_blocked.png'
    end

    button:setImageSource(imagePath)
end

local function updateChoosePreyButtonState(slot)
    local prey = getPreySlotWidget(slot)
    if not prey or not prey.inactive or not prey.inactive.choose then
        return
    end

    local button = prey.inactive.choose.choosePreyButton
    if not button then
        return
    end

    -- the full list counts only its own pick (the 9 boxes behind it may still
    -- hold an old one); the 9 boxes count only theirs
    local hasSelection = false
    if listModeBySlot[slot] then
        hasSelection = selectedRaceEntryBySlot[slot] ~= nil
    else
        local list = prey.inactive.list
        if list then
            for _, child in ipairs(list:getChildren()) do
                if child.isChecked and child:isChecked() then
                    hasSelection = true
                    break
                end
            end
        end
    end

    setChoosePreyButtonEnabled(button, hasSelection and not choosePendingBySlot[slot])
end

-- Choose goes once: the button stays off until the slot's next prey packet
-- (or a new pick, after the server refused this one)
local function sendChoosePrey(slot, action, value)
    if choosePendingBySlot[slot] then
        return
    end
    choosePendingBySlot[slot] = true
    updateChoosePreyButtonState(slot)
    g_game.preyAction(slot, action, value)
end

-- the Prey Wildcards the player has now (the 'wildcards' of the slot packets
-- is not a count: for this protocol that byte is the slot's option)
local function getWildcardCount()
    local player = g_game.getLocalPlayer()
    if player and ResourceTypes and ResourceTypes.PREY_WILDCARDS then
        return player:getResourceBalance(ResourceTypes.PREY_WILDCARDS) or 0
    end

    return bonusRerolls or 0
end

local function showPreyConfirmationWindow(title, description, confirmAction, cancelAction)
    destroyConfirmWindow()

    local window
    local wasPreyWindowVisible = preyWindow and preyWindow:isVisible()
    local preyVisibilityRestored = false

    local function restorePreyWindowVisibility()
        if confirmWindow == window then
            confirmWindow = nil
        end
        if not preyVisibilityRestored and wasPreyWindowVisible and preyWindow then
            preyVisibilityRestored = true
            preyWindow:show()
            preyWindow:raise()
            preyWindow:focus()
            refreshBalanceState()
        end
    end

    if wasPreyWindowVisible then
        preyWindow:hide()
    end

    local function closeWindow()
        if window and not window:isDestroyed() then
            window:destroy()
        end
        restorePreyWindowVisibility()
    end

    local function confirm()
        if confirmAction then
            confirmAction()
        end
        closeWindow()
    end

    local function cancel()
        if cancelAction then
            cancelAction()
        end
        closeWindow()
    end

    window = displayGeneralBox(title, description, {
        {
            text = tr('Yes'),
            callback = confirm
        },
        {
            text = tr('No'),
            callback = cancel
        },
    }, confirm, cancel)

    if window then
        window.onDestroy = restorePreyWindowVisibility
        confirmWindow = window
    else
        restorePreyWindowVisibility()
    end
end

local function showPreyWildcardConfirmation(description, confirmAction, cancelAction)
    showPreyConfirmationWindow(tr('Confirmation of Using Prey Wildcards'), description, confirmAction, cancelAction)
end

-- the count is read when the button is clicked
local function showPickSpecificPreyConfirmation(slot)
    local wildcardCount = getWildcardCount()
    if wildcardCount < selectListPrice then
        return showMessage(tr('Error'), tr("You don't have enough Prey Wildcards to choose a creature."))
    end

    local description = tr('Are you sure you want to use %d of your remaining %d Prey Wildcards?', selectListPrice,
        wildcardCount)

    showPreyWildcardConfirmation(description, function()
        g_game.preyAction(slot, PREY_ACTION_REQUEST_ALL_MONSTERS, 0)
    end)
end

local function showBonusRerollConfirmation(slot)
    local wildcardCount = getWildcardCount()
    if wildcardCount < bonusRerollPrice then
        return showMessage(tr('Error'), tr("You don't have enough Prey Wildcards for a new bonus."))
    end

    local description = tr('Are you sure you want to use %d of your remaining %d Prey Wildcards?', bonusRerollPrice,
        wildcardCount)

    showPreyWildcardConfirmation(description, function()
        g_game.preyAction(slot, PREY_ACTION_BONUSREROLL, 0)
    end)
end

-- the bonus reroll button is off while the player has fewer Prey Wildcards
-- than it costs
local function updateBonusRerollButton(slot)
    local prey = getPreySlotWidget(slot)
    local button = prey and prey.active and prey.active.choose and prey.active.choose.selectPrey
    if button then
        button:setEnabled(getWildcardCount() >= bonusRerollPrice)
    end
end

local function getPlayerTotalGold()
    local player = g_game.getLocalPlayer()
    if player and player.getTotalMoney then
        return player:getTotalMoney()
    end

    return (bankGold or 0) + (inventoryGold or 0)
end

function refreshRerollButtonState(slot)
    local prey = getPreySlotWidget(slot)
    if not prey then
        return
    end

    local price = getListRerollPrice(slot)
    local canAfford = price <= 0 or getPlayerTotalGold() >= price

    local function updatePanel(panel)
        if not panel or not panel.reroll or not panel.reroll.button then
            return
        end

        local button = panel.reroll.button.rerollButton
        if not button then
            return
        end

        if canAfford then
            button:setImageSource('/images/game/prey/prey_reroll')
            button:enable()
        else
            button:setImageSource('/images/game/prey/prey_reroll_blocked')
            button:disable()
        end
    end

    updatePanel(prey.active)
    updatePanel(prey.inactive)
end

showListRerollConfirmation = function(slot)
    if isFreeReroll(slot) then
        g_game.preyAction(slot, PREY_ACTION_LISTREROLL, 0)
        return
    end

    local price = getCurrentRerollPrice()
    if price <= 0 then
        g_game.preyAction(slot, PREY_ACTION_LISTREROLL, 0)
        return
    end

    local description = tr(
        'Do you want to spend %s gold for a List Reroll?\nYou currently have %s gold available for the purchase.',
        comma_value(price), comma_value(getPlayerTotalGold()))

    showPreyConfirmationWindow(tr('Confirmation of Using List Reroll'), description, function()
        g_game.preyAction(slot, PREY_ACTION_LISTREROLL, 0)
    end)
end

-- Pick Specific Prey: on when the player has the price (the server's
-- 'directly' price)
function updatePickSpecificPreyButton(slot)
    local prey = getPreySlotWidget(slot)
    if not prey then
        return
    end

    local hasWildcardsAvailable = getWildcardCount() >= selectListPrice

    local function refreshButton(panel)
        if not panel or not panel.select or not panel.select.pickSpecificPrey then
            return
        end

        local button = panel.select.pickSpecificPrey

        button:setTooltip(getPickSpecificPreyDescription(slot))

        if hasWildcardsAvailable then
            button:setImageSource('/images/game/prey/prey_select')
            button:enable()
            button.onClick = function()
                showPickSpecificPreyConfirmation(slot)
            end
        else
            button:setImageSource('/images/game/prey/prey_select_blocked')
            button:disable()
            button.onClick = nil
        end
    end

    refreshButton(prey.active)
    refreshButton(prey.inactive)
end

-- gold and Prey Wildcards: the totals and every button they enable
refreshBalanceState = function()
    if not preyWindow then
        return
    end

    preyWindow.wildCards.text:setText(tostring(getWildcardCount()))
    preyWindow.gold.text:setText(comma_value(getPlayerTotalGold()))
    for slot = 0, 2 do
        refreshRerollButtonState(slot)
        updatePickSpecificPreyButton(slot)
        updateBonusRerollButton(slot)
    end
end

function resetPreyPreviewWidget(preview)
    if not preview then
        return
    end

    if preview.placeholder then
        preview.placeholder:setVisible(true)
    end

    if preview.creature then
        preview.creature:setVisible(false)
    end
end

setWidgetTreePhantom = function(widget, phantom)
    if not widget or widget:isDestroyed() then
        return
    end

    widget:setPhantom(phantom)

    for _, child in pairs(widget:getChildren()) do
        setWidgetTreePhantom(child, phantom)
    end
end

function setInactiveMode(slot, showFullList, prey)
    prey = prey or getPreySlotWidget(slot)
    if not prey or not prey.inactive then
        return prey
    end

    local inactive = prey.inactive

    if inactive.emptyList then
        inactive.emptyList:setVisible(false)
    end

    if inactive.list then
        inactive.list:setVisible(not showFullList)
        setWidgetTreePhantom(inactive.list, showFullList)
    end

    if inactive.fullList then
        inactive.fullList:setVisible(showFullList)
    end

    if inactive.preview then
        inactive.preview:setVisible(showFullList)
        if not showFullList or not selectedRaceEntryBySlot[slot] then
            resetPreyPreviewWidget(inactive.preview)
        end
    end

    if inactive.select then
        inactive.select:setVisible(not showFullList)
    end

    if inactive.reroll then
        inactive.reroll:setVisible(not showFullList)
    end

    return prey
end

local function isDescendantOf(widget, ancestor)
    if not widget or not ancestor then
        return false
    end
    local current = widget
    while current do
        if current == ancestor then
            return true
        end
        current = current:getParent()
    end
    return false
end

local function getFullListEntriesContainer(fullList)
    if not fullList then
        return nil
    end

    local entries = fullList.entries
    if not entries then
        return nil
    end

    if entries.entriesContainer then
        return entries.entriesContainer
    end

    if entries.getChildById then
        local contents = entries:getChildById('entriesContainer') or entries:getChildById('contentsPanel')
        if contents then
            entries.entriesContainer = contents
            return contents
        end
    end

    entries.entriesContainer = entries
    return entries
end

function clearFullListEntries(fullList)
    local container = getFullListEntriesContainer(fullList)
    if container then
        container:destroyChildren()
    end

    if fullList and fullList.entries and fullList.entries.verticalScrollBar then
        local scrollbar = fullList.entries.verticalScrollBar
        if scrollbar.getMinimum and scrollbar.setValue then
            scrollbar:setValue(scrollbar:getMinimum())
        end
    end
end

local suppressSearchTextHandler = false

local function setSearchTextSilently(widget, text)
    if not widget or widget:getText() == text then
        return
    end

    suppressSearchTextHandler = true
    widget:setText(text)
    suppressSearchTextHandler = false
end

local function updateRaceSearchClearButton(slot)
    local prey = getPreySlotWidget(slot)
    if not prey or not prey.inactive or not prey.inactive.fullList then
        return
    end

    local fullList = prey.inactive.fullList
    local clearButton = fullList.searchClearButton
    if not clearButton then
        return
    end

    -- what is in the box (spaces too), not the filter
    local text = fullList.searchEdit and fullList.searchEdit:getText() or ''
    clearButton:setVisible(text:len() > 0)
end

local function updateRaceSearchUI(slot)
    local prey = getPreySlotWidget(slot)
    if not prey or not prey.inactive or not prey.inactive.fullList then
        return
    end

    local fullList = prey.inactive.fullList
    local searchEdit = fullList.searchEdit
    local clearButton = fullList.searchClearButton
    local text = raceSearchTextsBySlot[slot] or ''

    if searchEdit then
        searchEdit.preySlot = slot
        setSearchTextSilently(searchEdit, text)
        searchEdit:setCursorPos(-1)
    end

    if clearButton then
        clearButton.preySlot = slot
        clearButton.searchEdit = searchEdit
    end

    updateRaceSearchClearButton(slot)
end

local function uncheckChildrenExcept(parent, except)
    if not parent then
        return
    end
    for _, child in pairs(parent:getChildren()) do
        if child ~= except and child.setChecked then
            if not child:isDestroyed() then
                child:setChecked(false)
                restoreRaceListItemBackground(child)
            end
        end
        uncheckChildrenExcept(child, except)
    end
end

-- a click on one of the 9 creatures (the full list has its own handler,
-- onPreyRaceListItemClicked)
function onItemBoxChecked(widget)
    for _, slotId in ipairs({ 'slot1', 'slot2', 'slot3' }) do
        local slotWidget = preyWindow[slotId]
        if slotWidget and slotWidget.inactive then
            local list = slotWidget.inactive.list
            if list and isDescendantOf(widget, list) then
                uncheckChildrenExcept(list, widget)
                widget:setChecked(true)
                local slotIndex = tonumber(slotId:match('slot(%d+)'))
                if slotIndex then
                    -- a new pick may be sent again
                    choosePendingBySlot[slotIndex - 1] = nil
                    updateChoosePreyButtonState(slotIndex - 1)
                end
                return
            end
        end
    end
    widget:setChecked(true)
end

local function setWidgetTextToFit(widget, text, formatter)
    if not widget then
        return ''
    end

    text = text or ''
    formatter = formatter or function(value) return value end

    local ellipsis = '...'
    local paddingLeft = widget.getPaddingLeft and widget:getPaddingLeft() or 0
    local paddingRight = widget.getPaddingRight and widget:getPaddingRight() or 0
    local availableWidth = widget:getWidth() - paddingLeft - paddingRight

    if availableWidth <= 0 then
        local formatted = formatter(text)
        widget:setText(formatted)
        return formatted
    end

    local function setAndCheck(value)
        local formattedValue = formatter(value)
        widget:setText(formattedValue)
        local textSize = widget:getTextSize()
        return textSize.width <= availableWidth, formattedValue
    end

    local fits, formatted = setAndCheck(text)
    if fits then
        return formatted
    end

    local bestFormatted
    local left, right = 0, #text
    while left <= right do
        local mid = math.floor((left + right) / 2)
        local candidate = text:sub(1, mid) .. ellipsis
        local candidateFits, candidateFormatted = setAndCheck(candidate)
        if candidateFits then
            bestFormatted = candidateFormatted
            left = mid + 1
        else
            right = mid - 1
        end
    end

    if bestFormatted then
        widget:setText(bestFormatted)
        return bestFormatted
    end

    local _, ellipsisFormatted = setAndCheck(ellipsis)
    widget:setText(ellipsisFormatted)
    return ellipsisFormatted
end

local function buildRaceEntry(raceId)
    local raceData = g_things.getRaceData(raceId)
    local name = raceData and raceData.name or nil

    if name and name ~= '' then
        name = capitalFormatStr(name)
    else
        name = tr('Unknown Creature (%d)', raceId)
    end

    local outfit = raceData and raceData.outfit or nil
    local realSize

    if outfit and outfit.type then
        local creatureType = g_things.getThingType(outfit.type, ThingCategoryCreature)
        realSize = creatureType and creatureType:getRealSize() or nil
    end

    return {
        raceId = raceId,
        name = name,
        searchName = name:lower(),
        outfit = outfit,
        realSize = realSize
    }
end

restoreRaceListItemBackground = function(widget)
    if not widget or widget:isDestroyed() then
        return
    end

    if widget:isChecked() then
        if widget.checkedBackground then
            widget:setBackgroundColor(widget.checkedBackground)
        end
        if widget.checkedTextColor then
            widget:setColor(widget.checkedTextColor)
        end
        return
    end

    if widget.baseBackground then
        widget:setBackgroundColor(widget.baseBackground)
    end
    if widget.baseTextColor then
        widget:setColor(widget.baseTextColor)
    end
end

updateRaceSelectionDisplay = function(slot)
    local prey = getPreySlotWidget(slot)
    if not prey or not prey.inactive or not prey.inactive.fullList then
        return
    end

    local entry = selectedRaceEntryBySlot[slot]

    if prey.title then
        if entry then
            setWidgetTextToFit(prey.title, entry.name, function(value)
                return tr('Selected: %s', value)
            end)
        else
            prey.title:setText(tr('Select your prey creature'))
        end
    end

    local preview = prey.inactive and prey.inactive.preview
    if preview then
        local creatureWidget = preview.creature
        local placeholder = preview.placeholder
        if entry and entry.outfit and creatureWidget then
            local spriteSize = g_gameConfig.getSpriteSize()
            if spriteSize <= 0 then
                spriteSize = 32
            end
            local widgetSize = math.min(creatureWidget:getWidth(), creatureWidget:getHeight())
            local referenceSize = math.max(entry.realSize or spriteSize * 2, spriteSize * 2)
            local targetSize = widgetSize > 0 and widgetSize or spriteSize * 2
            local scale = math.floor((targetSize / referenceSize) * 100)

            if scale < 1 then
                scale = 1
            elseif scale > 100 then
                scale = 100
            end
            -- its own size in pixels (`size` was never defined: nil made it 0
            -- and the preview collapsed)
            creatureWidget:setCreatureSize(math.min(targetSize, 255))
            creatureWidget:setOutfit(entry.outfit)
            creatureWidget:setVisible(true)
            if placeholder then
                placeholder:setVisible(false)
            end
        else
            if creatureWidget then
                creatureWidget:setVisible(false)
            end
            if placeholder then
                placeholder:setVisible(true)
            end
        end
    end
end

setRaceSelection = function(slot, widget)
    if widget and widget:isDestroyed() then
        widget = nil
    end

    -- only the row picked before is unchecked (not the whole list)
    local previousWidget = selectedRaceWidgetBySlot[slot]
    if previousWidget and previousWidget ~= widget and not previousWidget:isDestroyed() then
        previousWidget:setChecked(false)
        restoreRaceListItemBackground(previousWidget)
    end

    if widget and not widget:isChecked() then
        widget:setChecked(true)
    end

    selectedRaceWidgetBySlot[slot] = widget
    selectedRaceEntryBySlot[slot] = widget and widget.raceData or nil

    if widget then
        restoreRaceListItemBackground(widget)
    end

    -- a new pick may be sent again
    choosePendingBySlot[slot] = nil
    updateRaceSelectionDisplay(slot)
    updateChoosePreyButtonState(slot)
end

-- the rows of the full list, once per list (the search only shows and hides them)
local function buildRaceList(slot)
    local prey = getPreySlotWidget(slot)
    if not prey or not prey.inactive or not prey.inactive.fullList then
        return
    end

    local fullList = prey.inactive.fullList
    clearFullListEntries(fullList)

    local entriesPanel = getFullListEntriesContainer(fullList)
    if not entriesPanel then
        return
    end

    -- one layout pass for the whole list, not one per row
    local layout = entriesPanel:getLayout()
    if layout then
        layout:disableUpdates()
    end

    local rows = {}
    for _, entry in ipairs(raceEntriesBySlot[slot] or {}) do
        local item = g_ui.createWidget('PreyCreatureListItem', entriesPanel)
        item:setText(entry.name)
        item:setTooltip(entry.name)
        item.raceData = entry
        item.preySlot = slot
        item.baseBackground = '#484848'
        item.checkedBackground = '#585858'
        item.baseTextColor = '#c0c0c0'
        item.checkedTextColor = '#ffffff'
        item.onCheckChange = function(widget)
            restoreRaceListItemBackground(widget)
        end
        rows[#rows + 1] = item
    end

    if layout then
        layout:enableUpdates()
        layout:update()
    end

    -- the rows have their width now: a name too long ends in "..."
    for _, item in ipairs(rows) do
        setWidgetTextToFit(item, item.raceData.name)
    end

    raceRowsBySlot[slot] = rows
end

-- shows the rows that match the search (all of them without one)
refreshRaceList = function(slot)
    local rows = raceRowsBySlot[slot]
    local prey = getPreySlotWidget(slot)
    if not rows or not prey or not prey.inactive or not prey.inactive.fullList then
        return
    end

    local fullList = prey.inactive.fullList
    local entriesPanel = getFullListEntriesContainer(fullList)
    local layout = entriesPanel and entriesPanel:getLayout()
    if layout then
        layout:disableUpdates()
    end

    local searchFilter = raceSearchTextsBySlot[slot]
    searchFilter = searchFilter and searchFilter:lower() or nil

    local useAlternate = false
    for _, item in ipairs(rows) do
        local entry = item.raceData
        local visible = not searchFilter or (entry.searchName:find(searchFilter, 1, true) ~= nil)
        item:setVisible(visible)
        if visible then
            item.baseBackground = useAlternate and '#414141' or '#484848'
            restoreRaceListItemBackground(item)
            useAlternate = not useAlternate
        end
    end

    if layout then
        layout:enableUpdates()
        layout:update()
    end

    if fullList.entries and fullList.entries.verticalScrollBar then
        local scrollbar = fullList.entries.verticalScrollBar
        if scrollbar.getMinimum and scrollbar.setValue then
            scrollbar:setValue(scrollbar:getMinimum())
        end
    end
end

-- the slot left the full list: its rows go away
clearRaceList = function(slot)
    if raceSearchEventBySlot[slot] then
        removeEvent(raceSearchEventBySlot[slot])
        raceSearchEventBySlot[slot] = nil
    end

    local hadList = raceRowsBySlot[slot] ~= nil
    raceEntriesBySlot[slot] = nil
    raceIdsBySlot[slot] = nil
    raceRowsBySlot[slot] = nil
    raceSearchTextsBySlot[slot] = nil
    selectedRaceEntryBySlot[slot] = nil
    selectedRaceWidgetBySlot[slot] = nil
    listModeBySlot[slot] = nil

    local prey = getPreySlotWidget(slot)
    if hadList and prey and prey.inactive and prey.inactive.fullList then
        clearFullListEntries(prey.inactive.fullList)
    end
end

-- the text in the box stays as typed (spaces too); only the filter is trimmed,
-- and it is applied a moment after the last key
function onRaceSearchTextChanged(widget)
    if not widget or not widget.preySlot then
        return
    end

    local slot = widget.preySlot
    updateRaceSearchClearButton(slot)
    if suppressSearchTextHandler then
        return
    end

    local trimmed = (widget:getText() or ''):trim()
    local filter = trimmed:len() > 0 and trimmed or nil
    if filter == raceSearchTextsBySlot[slot] then
        return
    end
    raceSearchTextsBySlot[slot] = filter

    if raceSearchEventBySlot[slot] then
        removeEvent(raceSearchEventBySlot[slot])
    end
    raceSearchEventBySlot[slot] = scheduleEvent(function()
        raceSearchEventBySlot[slot] = nil
        refreshRaceList(slot)
    end, RACE_SEARCH_DELAY)
end

function onRaceSearchClearClicked(widget)
    if not widget or not widget.preySlot then
        return
    end

    local slot = widget.preySlot
    local searchEdit = widget.searchEdit

    if not searchEdit or searchEdit:isDestroyed() then
        local prey = getPreySlotWidget(slot)
        if prey and prey.inactive and prey.inactive.fullList then
            searchEdit = prey.inactive.fullList.searchEdit
        end
    end

    if raceSearchEventBySlot[slot] then
        removeEvent(raceSearchEventBySlot[slot])
        raceSearchEventBySlot[slot] = nil
    end
    raceSearchTextsBySlot[slot] = nil

    if searchEdit and not searchEdit:isDestroyed() then
        setSearchTextSilently(searchEdit, '')
        searchEdit:setCursorPos(0)
    end

    updateRaceSearchClearButton(slot)
    refreshRaceList(slot)
end

function onPreyRaceListItemClicked(widget)
    if not widget or not widget.preySlot then
        return
    end
    setRaceSelection(widget.preySlot, widget)
end

function onPreyRaceListItemHoverChange(widget, hovered)
    if not widget or widget:isDestroyed() then
        return
    end

    restoreRaceListItemBackground(widget)
end

local suppressOptionCheckHandler = false

local function setOptionCheckedSilently(checkbox, checked)
    if checkbox:isChecked() == checked then
        return
    end
    suppressOptionCheckHandler = true
    checkbox:setChecked(checked)
    suppressOptionCheckHandler = false
end

local function getToggleCheckboxes(slot)
    local prey = preyWindow and preyWindow['slot' .. (slot + 1)]
    if not prey or not prey.active then
        return nil, nil
    end

    local autoCheckbox = prey.active.autoReroll and prey.active.autoReroll.autoRerollCheck
    local lockCheckbox = prey.active.lockPrey and prey.active.lockPrey.lockPreyCheck

    return autoCheckbox, lockCheckbox
end

local function sendOption(slot, option)
    g_game.preyAction(slot, PREY_ACTION_OPTION, option)
end

-- the boxes show the server's option for the slot (onPreyActive), never a
-- local guess
local function syncOptionChecks(slot)
    local prey = getPreySlotWidget(slot)
    local option = prey and prey.lockType or PREY_OPTION_UNTOGGLE
    local autoCheckbox, lockCheckbox = getToggleCheckboxes(slot)
    if autoCheckbox then
        setOptionCheckedSilently(autoCheckbox, option == PREY_OPTION_TOGGLE_AUTOREROLL)
    end
    if lockCheckbox then
        setOptionCheckedSilently(lockCheckbox, option == PREY_OPTION_TOGGLE_LOCK_PREY)
    end
end

local function handleToggleOptions(checkbox, slot, currentOption, checked)
    if suppressOptionCheckHandler then
        return
    end

    if not checked then
        sendOption(slot, PREY_OPTION_UNTOGGLE)
        return
    end

    -- not ticked here: the box follows the slot the server sends back
    syncOptionChecks(slot)

    local isAutoReroll = currentOption == PREY_OPTION_TOGGLE_AUTOREROLL
    local price = isAutoReroll and bonusRerollPrice or selectListPrice
    if getWildcardCount() < price then
        if isAutoReroll then
            showMessage(tr('Error'), tr("You don't have enough Prey Wildcards for the Automatic Bonus Reroll."))
        else
            showMessage(tr('Error'), tr("You don't have enough Prey Wildcards to lock the prey."))
        end
        return
    end

    local description = tr(isAutoReroll and descriptionTable['automaticBonusReroll'] or descriptionTable['preyLock'],
        price)

    -- one option per slot: the server replaces the other one
    showPreyWildcardConfirmation(description, function()
        sendOption(slot, currentOption)
    end, function()
        syncOptionChecks(slot)
    end)
end

function onPreyActive(slot, currentHolderName, currentHolderOutfit, bonusType, bonusValue, bonusGrade, timeLeft,
                      timeUntilFreeReroll, wildcards, option) -- locktype always 0 for protocols <12
    choosePendingBySlot[slot] = nil
    clearRaceList(slot)

    currentHolderName = capitalFormatStr(currentHolderName)
    local percent = (timeLeft / (2 * 60 * 60)) * 100
    preyDescription[slot] = {
        name = currentHolderName,
        grade = bonusGrade,
        bonusType = bonusType,
        bonusValue = bonusValue,
        timeLeft = timeLeft
    }

    local tracker = preyTracker.contentsPanel['slot' .. (slot + 1)]
    if tracker then
        showTrackerRow(tracker)
        tracker.creature:show()
        tracker.noCreature:hide()
        tracker.creatureName:setText(currentHolderName)
        tracker.creature:setOutfit(currentHolderOutfit)
        tracker.preyType:setImageSource(getSmallIconPath(bonusType))
        tracker.time:setPercent(percent)
        local tooltip = getActivePreyTooltip(slot)
        for i, element in pairs({ tracker.creatureName, tracker.creature, tracker.preyType, tracker.time }) do
            element:setTooltip(tooltip)
            element.onClick = function()
                show()
            end
        end
    end
    local prey = preyWindow['slot' .. (slot + 1)]
    if not prey then
        return
    end
    -- read by the Kill Tracker (game_taskboard)
    prey.bonusType = bonusType
    prey.lockType = option
    prey.inactive:hide()
    prey.locked:hide()
    prey.active:show()
    prey.title:setText(currentHolderName)
    local creatureAndBonus = prey.active.creatureAndBonus
    creatureAndBonus.creature:setOutfit(currentHolderOutfit)
    setTimeUntilFreeReroll(slot, timeUntilFreeReroll)
    creatureAndBonus.bonus.icon:setImageSource(getBigIconPath(bonusType))
    creatureAndBonus.bonus.icon.onHoverChange = function(widget, hovered)
        onHover(slot)
    end
    setBonusGradeStars(slot, bonusGrade)
    creatureAndBonus.timeLeft:setPercent(percent)
    creatureAndBonus.timeLeft:setText(timeleftTranslation(timeLeft, true))
    -- bonus reroll (the Prey Wildcards are counted when it is clicked)
    setPickSpecificPreyBonus(slot, bonusType, bonusValue)
    prey.active.choose.selectPrey.onClick = function()
        showBonusRerollConfirmation(slot)
    end
    updateBonusRerollButton(slot)
    -- creature reroll
    prey.active.reroll.button.rerollButton.onClick = function()
        showListRerollConfirmation(slot)
    end

    syncOptionChecks(slot)
    prey.active.autoReroll.autoRerollCheck.onCheckChange = function(widget, checked)
        handleToggleOptions(widget, slot, PREY_OPTION_TOGGLE_AUTOREROLL, checked)
    end
    prey.active.lockPrey.lockPreyCheck.onCheckChange = function(widget, checked)
        handleToggleOptions(widget, slot, PREY_OPTION_TOGGLE_LOCK_PREY, checked)
    end

    updatePickSpecificPreyButton(slot)
    updateKillTracker(slot, PREY_STATE_ACTIVE, currentHolderOutfit)
end

-- the 9 creatures of a new list (onPreySelection, onPreySelectionChangeMonster)
local function showPreySelection(slot, names, outfits, timeUntilFreeReroll, bonusType, bonusValue, state)
    choosePendingBySlot[slot] = nil
    -- tracker
    setTrackerInactive(slot)
    -- main window
    local prey = preyWindow['slot' .. (slot + 1)]
    setTimeUntilFreeReroll(slot, timeUntilFreeReroll)
    clearRaceList(slot)
    if not prey then
        return
    end
    prey.bonusType = bonusType
    prey.lockType = nil
    prey.active:hide()
    prey.locked:hide()
    prey.inactive:show()
    setInactiveMode(slot, false, prey)
    -- a bonus kept from before (change monster) stays as it is
    setPickSpecificPreyBonus(slot, bonusType, bonusValue)
    prey.title:setText(tr('Select monster'))
    local rerollButton = prey.inactive.reroll and prey.inactive.reroll.button and
        prey.inactive.reroll.button.rerollButton
    if rerollButton then
        rerollButton.onClick = function()
            showListRerollConfirmation(slot)
        end
    end
    local list = prey.inactive.list
    list:destroyChildren()
    if prey.inactive.emptyList then
        prey.inactive.emptyList:setVisible(#names == 0)
    end
    for i, name in ipairs(names) do
        local box = g_ui.createWidget('PreyCreatureBox', list)
        name = capitalFormatStr(name)
        box:setTooltip(name)
        box.creature:setOutfit(outfits[i])
        local backgroundColor = (i % 2 == 1) and '#484848' or '#414141'
        box:setBackgroundColor(backgroundColor)
    end
    prey.inactive.choose.choosePreyButton.onClick = function()
        for i, child in ipairs(list:getChildren()) do
            if child:isChecked() then
                return sendChoosePrey(slot, PREY_ACTION_MONSTERSELECTION, i - 1)
            end
        end
        return showMessage(tr('Error'), tr('Select monster to proceed.'))
    end

    updateChoosePreyButtonState(slot)
    updatePickSpecificPreyButton(slot)
    updateKillTracker(slot, state)
end

function onPreySelection(slot, names, outfits, timeUntilFreeReroll, wildcards, option)
    showPreySelection(slot, names, outfits, timeUntilFreeReroll, nil, nil, PREY_STATE_SELECTION)
end

function onPreySelectionChangeMonster(slot, names, outfits, bonusType, bonusValue, bonusGrade, timeUntilFreeReroll,
                                      wildcards, option)
    showPreySelection(slot, names, outfits, timeUntilFreeReroll, bonusType, bonusValue,
        PREY_STATE_SELECTION_CHANGE_MONSTER)
end

local function isSameRaceList(slot, races)
    local current = raceIdsBySlot[slot]
    if not listModeBySlot[slot] or not current or #current ~= #races then
        return false
    end
    for i = 1, #races do
        if current[i] ~= races[i] then
            return false
        end
    end
    return true
end

function onPreyListSelection(slot, races, nextFreeReroll, wildcards, option)
    choosePendingBySlot[slot] = nil
    setTimeUntilFreeReroll(slot, nextFreeReroll)
    setTrackerInactive(slot)

    local prey = getPreySlotWidget(slot)
    if not prey then
        return
    end

    -- the same list again (the window was opened again, or a pick was refused):
    -- the rows, the search and the pick stay
    if isSameRaceList(slot, races) then
        updateRaceSelectionDisplay(slot)
        updateChoosePreyButtonState(slot)
        updatePickSpecificPreyButton(slot)
        updateKillTracker(slot, PREY_STATE_LIST_SELECTION)
        return
    end

    clearRaceList(slot)
    listModeBySlot[slot] = true
    prey.bonusType = nil
    prey.lockType = nil
    prey.active:hide()
    prey.locked:hide()
    prey.inactive:show()
    setPickSpecificPreyBonus(slot)

    setInactiveMode(slot, true, prey)

    local fullList = prey.inactive.fullList
    if not fullList then
        return
    end

    prey.title:setText(tr('Select your prey creature'))

    local preview = prey.inactive.preview
    if preview then
        resetPreyPreviewWidget(preview)
    end

    raceIdsBySlot[slot] = {}
    raceEntriesBySlot[slot] = {}
    for _, raceId in ipairs(races) do
        table.insert(raceIdsBySlot[slot], raceId)
        table.insert(raceEntriesBySlot[slot], buildRaceEntry(raceId))
    end
    table.sort(raceEntriesBySlot[slot], function(a, b)
        return a.name < b.name
    end)

    updateRaceSearchUI(slot)

    local chooseButton = prey.inactive.choose and prey.inactive.choose.choosePreyButton
    if chooseButton then
        chooseButton.onClick = function()
            local selected = selectedRaceEntryBySlot[slot]
            if not selected then
                return showMessage(tr('Error'), tr('Select monster to proceed.'))
            end
            sendChoosePrey(slot, PREY_ACTION_CHANGE_FROM_ALL, selected.raceId)
        end
    end

    buildRaceList(slot)
    refreshRaceList(slot)
    updateRaceSelectionDisplay(slot)

    local rerollButton = prey.inactive.reroll and prey.inactive.reroll.button and
        prey.inactive.reroll.button.rerollButton
    if rerollButton then
        rerollButton.onClick = function()
            showListRerollConfirmation(slot)
        end
    end

    updateChoosePreyButtonState(slot)
    updatePickSpecificPreyButton(slot)
    updateKillTracker(slot, PREY_STATE_LIST_SELECTION)
end

function onPreyWildcardSelection(slot, races, nextFreeReroll, wildcards, option)
    choosePendingBySlot[slot] = nil
    updatePickSpecificPreyButton(slot)
end

function Prey.onResourcesBalanceChange(balance, oldBalance, type)
    if type == ResourceTypes.BANK_BALANCE then       -- bank gold
        bankGold = balance
    elseif type == ResourceTypes.GOLD_EQUIPPED then  -- inventory gold
        inventoryGold = balance
    elseif type == ResourceTypes.PREY_WILDCARDS then -- bonus rerolls
        bonusRerolls = balance
    else
        return
    end

    -- gold changes with every kill: the window is brought up to date when it
    -- is open, and when it is shown
    if preyWindow and preyWindow:isVisible() then
        refreshBalanceState()
    end
end

function showMessage(title, message)
    if msgWindow then
        msgWindow:destroy()
    end

    msgWindow = displayInfoBox(title, message)
    msgWindow:show()
    msgWindow:raise()
    msgWindow:focus()
end
