-- Mythos bar: the server's own systems (tasks, hunt rates, leaderboard,
-- rarity market, heal bot) in a bar under the game screen, just above the
-- spell bar: four framed sections side by side, Tasks, Hunts, Rarity and
-- Tools, and the VIP button after them. It cannot be closed; the map gives up its height.
-- The news window lists the systems on the first login after an update.
--
-- The feature modules register their row with addFeature() and get back the
-- button, which they use like the old toolbar button (setOn, setTooltip).

local NEWS_VERSION = 7

-- rows are shown in this order, whatever order the modules load in
local FEATURES = {
    { id = 'vip', group = 'vip', label = 'Mythos VIP', icon = 'vip',
      news = 'Mythos VIP: +10%% experience, loot and training, the Fusca, Uno and Gol mounts and more. The row shows your days left and opens the Store.' },
    { id = 'tasks', group = 'tasks', label = 'Daily Task', icon = 'tasks',
      news = 'One monster of your level a day, for experience and Hunt Points. The row shows the monster and your kills.' },
    { id = 'trail', group = 'tasks', label = "Hunter's Trail", icon = 'trail',
      news = '70 monsters in order, from the weakest to the strongest, with a bonus every 5 steps.' },
    { id = 'taskshop', group = 'tasks', label = 'Shop', icon = 'taskshop',
      news = 'Hunt Points buy XP potions, rarity scrolls, Rarity XP, Mythos Coins, the Bag of Mythical and more.' },
    { id = 'rates', group = 'hunt', label = 'Hunt Rates', icon = 'rates',
      news = 'The XP and loot rate of every monster changes every 2 hours. See the hottest hunts before you go.' },
    { id = 'board', group = 'hunt', label = 'Leaderboard', icon = 'board',
      news = 'Who kills the most monsters and who makes the most XP in the hour, the day and the month. The top hunters win Mythos Coins.' },
    { id = 'loot', group = 'hunt', label = 'Auto Loot', icon = 'loot',
      news = 'Choose what the auto loot picks up without opening a corpse: your recent drops and a search by name, each with a Take box.' },
    { id = 'rarity', group = 'rarity', label = 'Rarity Market', icon = 'rarity',
      news = 'Buy and sell the rarity items that drop from monsters, paid with the gold in your bank.' },
    { id = 'bonus', group = 'rarity', label = 'Roulette', icon = 'bonus',
      news = 'Every bonus of the rarity items you wear, the total of each one and the item it comes from.' },
    { id = 'healbot', group = 'tools', label = 'Heal Bot', icon = 'healbot',
      news = 'Heals you with spells and potions, heals your friends and keeps your buffs up. You choose the rules.' },
    { id = 'messages', group = 'tools', label = 'Interface', icon = 'messages',
      news = 'Interface settings, such as where the look, loot and warning messages show on the game screen.' },
    { id = 'wiki', group = 'tools', label = 'Wiki', icon = 'wiki',
      news = 'Rare monsters, rarity items and every bonus explained, with the real numbers from the server.' },
}

-- the four sections, top to bottom; the VIP row sits above them on its own
local SECTORS = {
    { id = 'tasks', label = 'Tasks', icon = 'tasks' },
    { id = 'hunt', label = 'Hunts', icon = 'rates' },
    { id = 'rarity', label = 'Rarity', icon = 'rarity' },
    { id = 'tools', label = 'Tools', icon = 'healbot' },
}

local panel, newsWindow
local buttons = {}
local callbacks = {}
local states = {}
local toggles = {}
local labels = {} -- per-row text that replaces the feature name
local sectors = {} -- section id -> section widget
local vipHolder -- the VIP button's box in the bar

local BUTTON_SPACING = 2 -- between the buttons of a section (otui)
local SECTOR_SPACING = 6 -- between the sections (otui)
local SECTOR_PADDING = 8 -- the buttons' margins, left and right
local TITLE_ROOM = 18 + 16 + 6 + 22 -- header art end, icon, gap, the other end
local ICON_ONLY = 24 -- a button's width when the screen is too narrow for names
local compact = false -- names hidden for lack of room

local styleButton

local function featureOf(id)
    for index, feature in ipairs(FEATURES) do
        if feature.id == id then
            return feature, index
        end
    end
end

local function iconPath(name)
    return '/game_brevespanel/images/' .. name
end

local function refreshBadge(id)
    local button = buttons[id]
    if not button then
        return
    end
    local badge = button.badge
    local state = states[id]
    local feature = featureOf(id)
    button:setTooltip(labels[id] and (tr(feature.label) .. ': ' .. labels[id]) or tr(feature.label))
    if state then
        badge:setText(state.text)
        badge:setColor(state.color)
        badge:setBackgroundColor('#00000080')
        -- a feature with a toggle switches on a click on its badge, without
        -- opening the window
        badge:setPhantom(toggles[id] == nil)
        badge:setBorderWidth(toggles[id] and 1 or 0)
        badge:setTooltip(toggles[id] and tr('Click to turn it on or off') or '')
        badge.onClick = function()
            if toggles[id] then
                toggles[id]()
            end
            return true
        end
        badge:show()
    else
        badge:hide()
    end
end

-- a button is as wide as its icon, its name and its badge
local function buttonWidth(button)
    if compact and button:getId() ~= 'vip' then
        return ICON_ONLY
    end
    local width = 23 + button:getTextSize().width + 6
    if button.badge:isVisible() then
        width = width + button.badge:getWidth() + 4
    end
    return width
end

-- widths of the buttons and the sections; names give way to icons alone when
-- the bar is narrower than everything with names
local function resize()
    if not panel then
        return
    end
    local function measure()
        local total = 0
        local blocks = 0
        if buttons.vip then
            buttons.vip:setWidth(math.max(110, buttons.vip:getTextSize().width + 56))
            vipHolder:setWidth(buttons.vip:getWidth())
            total = total + buttons.vip:getWidth()
            blocks = blocks + 1
        end
        for _, sector in ipairs(SECTORS) do
            local widget = sectors[sector.id]
            local children = widget.rows:getChildren()
            widget:setVisible(#children > 0)
            if #children > 0 then
                local rows = 0
                for _, button in ipairs(children) do
                    button:setWidth(buttonWidth(button))
                    rows = rows + button:getWidth()
                end
                rows = rows + (#children - 1) * BUTTON_SPACING
                local title = TITLE_ROOM + widget.title:getWidth()
                widget:setWidth(math.max(rows, title) + SECTOR_PADDING)
                total = total + widget:getWidth()
                blocks = blocks + 1
            end
        end
        return total + math.max(0, blocks - 1) * SECTOR_SPACING
    end
    -- names first; icons alone only if the names do not fit
    local function apply(iconsOnly)
        compact = iconsOnly
        for id in pairs(buttons) do
            styleButton(id)
        end
        return measure()
    end
    local room = panel:getWidth() - 24
    if apply(false) > room and room > 0 then
        apply(true)
    end
end

styleButton = function(id)
    local button = buttons[id]
    local feature = featureOf(id)
    if not button or not feature then
        return
    end
    -- the VIP button keeps its text: it is the one that sells
    local iconsOnly = compact and id ~= 'vip'
    button:setText(iconsOnly and '' or (labels[id] or tr(feature.label)))
    refreshBadge(id)
    if iconsOnly then
        button.badge:hide()
    end
end

local function sortRows(parent)
    local children = parent:getChildren()
    table.sort(children, function(a, b)
        return select(2, featureOf(a:getId())) < select(2, featureOf(b:getId()))
    end)
    parent:reorderChildren(children)
end

function open(id)
    if callbacks[id] then
        callbacks[id]()
    end
end

-- id: one of FEATURES; callback opens or closes the feature's window.
-- Returns the row button; setOn / setTooltip work on it like on a toolbar button.
function addFeature(id, callback)
    local feature = featureOf(id)
    if not feature or not panel then
        return nil
    end
    callbacks[id] = callback
    local button = buttons[id]
    if not button then
        if feature.group == 'vip' then
            -- last in the bar, after Tools, where the eye ends its sweep
            vipHolder = vipHolder or g_ui.createWidget('BrevesVipHolder', panel.strip)
            panel.strip:moveChildToIndex(vipHolder, panel.strip:getChildCount())
            button = g_ui.createWidget('BrevesVipButton', vipHolder)
            -- the crown clear of the pointed end
            button.icon:setMarginLeft(18)
        else
            button = g_ui.createWidget('BrevesFeatureButton', sectors[feature.group].rows)
        end
        button:setId(id)
        button:setText(tr(feature.label))
        button.icon:setImageSource(iconPath(feature.icon))
        button.onClick = function() open(id) end
        buttons[id] = button
        -- the feature module destroys its button on unload
        button.onDestroy = function()
            if buttons[id] == button then
                buttons[id] = nil
                callbacks[id] = nil
                scheduleEvent(resize, 1)
            end
        end
        if feature.group ~= 'vip' then
            sortRows(sectors[feature.group].rows)
        end
    end
    styleButton(id)
    resize()
    return button
end

-- a short state on the right of a row, e.g. ON / OFF
function setFeatureState(id, text, color)
    states[id] = text and { text = text, color = color or '#dfdfdf' } or nil
    styleButton(id)
    resize()
end

-- replaces the name shown on a row (nil puts the feature name back), e.g.
-- the Hunt Tasks row shows the current monster and kills
function setFeatureLabel(id, text, color)
    labels[id] = text
    local button = buttons[id]
    if button then
        button:setColor(text and color or (id == 'vip' and '#fff4d8' or '#e6e0f2'))
        styleButton(id)
        resize()
    end
end

-- makes the state badge of a row a switch: a click runs `callback`
function setFeatureToggle(id, callback)
    toggles[id] = callback
    refreshBadge(id)
end

-- ---------------------------------------------------------------- notices

local notice, noticeEvent
local NOTICE_SECONDS = 20

function hideNotice()
    if noticeEvent then
        removeEvent(noticeEvent)
        noticeEvent = nil
    end
    if notice then
        notice:destroy()
        notice = nil
    end
end

-- a small notice in the corner of the game screen with a button that opens
-- the feature `id` (onOpen replaces the row's own action); it closes by
-- itself and never takes the focus from the game
function notify(id, text, buttonText, onOpen)
    local root = modules.game_interface and modules.game_interface.getRootPanel()
    if not root or not g_game.isOnline() then
        return
    end
    hideNotice()
    notice = g_ui.createWidget('BrevesNotice', root)
    notice:addAnchor(AnchorTop, 'gameMapPanel', AnchorTop)
    notice:addAnchor(AnchorRight, 'gameMapPanel', AnchorRight)
    notice:setMarginTop(8)
    notice:setMarginRight(8)
    notice.text:setText(text)
    notice:setHeight(math.max(66, notice.text:getHeight() + 12 + 24))
    notice.openButton:setText(buttonText or tr('Open'))
    notice.openButton.onClick = function()
        hideNotice()
        if onOpen then
            onOpen()
        else
            open(id)
        end
    end
    notice.closeButton.onClick = hideNotice
    noticeEvent = scheduleEvent(function()
        noticeEvent = nil
        hideNotice()
    end, NOTICE_SECONDS * 1000)
end

-- ---------------------------------------------------------------- news window

-- the delayed first showing of the news window (see onGameStart)
local newsEvent

function hideNews()
    if newsEvent then
        removeEvent(newsEvent)
        newsEvent = nil
    end
    if newsWindow then
        newsWindow:destroy()
        newsWindow = nil
    end
end

function showNews()
    hideNews()
    -- its buttons open game windows: never on the login screen
    if not g_game.isOnline() then
        return
    end
    newsWindow = g_ui.createWidget('BrevesNewsWindow', rootWidget)
    for _, feature in ipairs(FEATURES) do
        local row = g_ui.createWidget('BrevesNewsRow', newsWindow.rows)
        row.icon:setImageSource(iconPath(feature.icon))
        row.name:setText(tr(feature.label))
        row.text:setText(tr(feature.news))
        row.open.onClick = function()
            hideNews()
            open(feature.id)
        end
        row.open:setEnabled(callbacks[feature.id] ~= nil)
    end
    newsWindow:raise()
    newsWindow:focus()
end


local BAR_HEIGHT, FOLDED_HEIGHT = 53, 22
local collapsed = false

-- folds the bar to one line or opens it; the map takes or gives back the room
local function setCollapsed(fold)
    collapsed = fold
    if not panel then
        return
    end
    panel:setHeight(fold and FOLDED_HEIGHT or BAR_HEIGHT)
    panel.strip:setVisible(not fold)
    panel.tutorialButton:setVisible(not fold)
    panel.collapsedLabel:setVisible(fold)
    panel.collapseButton:setOn(fold)
    panel.collapseButton:setTooltip(fold and tr('Show the Mythos bar') or tr('Hide the Mythos bar'))
end

function toggleCollapsed()
    setCollapsed(not collapsed)
end

-- the bar is always there; the tour calls this to have it open
function togglePanel()
    if panel then
        panel:show()
        setCollapsed(false)
    end
end

-- the bar takes the place of the map's bottom edge: the map ends on its top
-- and the bar ends on the splitter above the spell bars
local function placeBar()
    local root = modules.game_interface and modules.game_interface.getRootPanel()
    if panel or not root then
        return panel ~= nil
    end
    panel = g_ui.createWidget('BrevesBar', root)
    panel:addAnchor(AnchorLeft, 'gameLeftActionPanel', AnchorRight)
    panel:addAnchor(AnchorRight, 'gameRightActionPanel', AnchorLeft)
    panel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
    local map = root:getChildById('gameMapPanel')
    if map then
        map:addAnchor(AnchorBottom, 'brevespanel', AnchorTop)
    end
    for _, sector in ipairs(SECTORS) do
        local widget = g_ui.createWidget('BrevesSector', panel.strip)
        widget:setId('sector_' .. sector.id)
        widget.title:setText(tr(sector.label))
        widget.icon:setImageSource(iconPath(sector.icon))
        widget:hide()
        sectors[sector.id] = widget
    end
    -- names or icons follow the width of the map
    panel.onGeometryChange = function(widget, oldRect, newRect)
        if oldRect.width ~= newRect.width then
            resize()
        end
    end
    return true
end

local function onGameStart()
    placeBar()
    -- open on every login, whatever it was when the player left
    setCollapsed(false)
    resize()
    if g_settings.getNumber('breves_news_version') < NEWS_VERSION then
        g_settings.set('breves_news_version', NEWS_VERSION)
        -- written now: a client that crashes never saves its settings on exit
        g_settings.save()
        -- after the feature modules added their rows; kept, so a logout
        -- before it fires cancels it (hideNews)
        newsEvent = scheduleEvent(function()
            newsEvent = nil
            showNews()
        end, 1500)
    end
end

local function onGameEnd()
    hideNews()
    hideNotice()
end

function init()
    g_ui.importStyle('brevespanel')
    placeBar()
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    hideNews()
    hideNotice()
    if panel then
        local root = panel:getParent()
        local map = root and root:getChildById('gameMapPanel')
        if map then
            map:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
        end
        panel:destroy()
        panel = nil
    end
    buttons = {}
    callbacks = {}
    sectors = {}
    vipHolder = nil
end
