-- Mythos panel: the server's own systems (tasks, hunt rates, leaderboard,
-- rarity market, heal bot) in the right panel, in four framed sections the
-- player always sees: Tasks, Hunts, Rarity and Tools, with the VIP bar above
-- them. The panel cannot be closed, minimized or folded. The news window
-- lists the systems on the first login after an update.
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

local ROW_HEIGHT, ROW_SPACING = 19, 1
local VIP_HEIGHT = 24
local SECTOR_HEADER, SECTOR_PADDING = 22, 2 + 4 -- the rows' margins above and below
local SECTOR_SPACING = 4

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

-- each section is as tall as its rows and the window as tall as its
-- sections, so nothing is ever cut off or scrolled away; the bottom border
-- cannot make it smaller
local function resize()
    if not panel then
        return
    end
    local list = panel.contentsPanel
    local content = list:getPaddingTop() + list:getPaddingBottom()
    local blocks = 0
    if buttons.vip then
        content = content + VIP_HEIGHT
        blocks = blocks + 1
    end
    for _, sector in ipairs(SECTORS) do
        local widget = sectors[sector.id]
        local rows = widget.rows:getChildCount()
        widget:setVisible(rows > 0)
        if rows > 0 then
            local height = SECTOR_HEADER + SECTOR_PADDING + rows * ROW_HEIGHT + (rows - 1) * ROW_SPACING
            widget:setHeight(height)
            content = content + height
            blocks = blocks + 1
        end
    end
    content = content + math.max(0, blocks - 1) * SECTOR_SPACING
    -- the mini window's content sizes leave out the header strip
    content = content + panel.miniwindowHeader:getHeight()
    panel:setContentMinimumHeight(content)
    panel:setContentMaximumHeight(content)
    panel:setContentHeight(content)
end

local function styleButton(id)
    local button = buttons[id]
    local feature = featureOf(id)
    if not button or not feature then
        return
    end
    button:setText(labels[id] or tr(feature.label))
    refreshBadge(id)
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
            button = g_ui.createWidget('BrevesVipButton', panel.contentsPanel)
            panel.contentsPanel:moveChildToIndex(button, 1)
            -- the crown inside the gold frame, clear of its pointed end
            button.icon:setMarginLeft(24)
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
    refreshBadge(id)
end

-- replaces the name shown on a row (nil puts the feature name back), e.g.
-- the Hunt Tasks row shows the current monster and kills
function setFeatureLabel(id, text, color)
    labels[id] = text
    local button = buttons[id]
    if button then
        button:setColor(text and color or (id == 'vip' and '#fff4d8' or '#e6e0f2'))
        styleButton(id)
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


-- the panel is always open; kept for the tour, which calls it
function togglePanel()
    if not panel then
        return
    end
    panel:open()
    if panel:isOn() then
        panel:maximize()
    end
    panel:raise()
end

local function onGameStart()
    panel:setupOnStart()
    -- the first time, at the top of the right panel, where the old fixed
    -- panel was; after that the mini window settings remember the place
    if not g_settings.getBoolean('breves_panel_placed') then
        g_settings.set('breves_panel_placed', true)
        local right = modules.game_interface.getRightPanel()
        if right and panel:getParent() == right then
            right:moveChildToIndex(panel, 1)
        end
    end
    -- open and unfolded on every login, whatever a saved setting says
    togglePanel()
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
    panel = g_ui.createWidget('BrevesPanel')
    panel:setId('brevespanel')
    panel:setup()
    -- no close, minimize, lock or filter buttons: the panel stays
    for _, id in ipairs({ 'closeButton', 'minimizeButton', 'lockButton', 'toggleFilterButton', 'contextMenuButton', 'newWindowButton' }) do
        local button = panel:getChildById(id)
        if button then
            button:hide()
        end
    end
    -- its height always fits the sections (resize), so no scroll bar
    if panel.miniwindowScrollBar then
        panel.miniwindowScrollBar:hide()
    end
    -- and nothing else (a double click on the header, a saved state) hides it
    panel.minimize = function() end
    panel.close = function() end
    -- Mythos colours on the Tibia frame
    panel:setImageSource('/images/mythos/panel')
    panel:setImageBorder(4)
    panel.miniwindowHeader:setImageSource('')
    panel.miniwindowHeader:setBackgroundColor('#140e1f')
    for _, sector in ipairs(SECTORS) do
        local widget = g_ui.createWidget('BrevesSector', panel.contentsPanel)
        widget:setId('sector_' .. sector.id)
        widget.title:setText(tr(sector.label))
        widget.icon:setImageSource(iconPath(sector.icon))
        widget:hide()
        sectors[sector.id] = widget
    end
    resize()
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
        panel:destroy()
        panel = nil
    end
    buttons = {}
    callbacks = {}
    sectors = {}
end
