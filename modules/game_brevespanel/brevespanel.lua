-- Mythos panel: the server's own systems (tasks, hunt rates, leaderboard,
-- rarity market, heal bot) as labelled rows in the right panel, instead of
-- 20px icons lost among the client's buttons. The news window lists them on
-- the first login after an update.
--
-- The feature modules register their row with addFeature() and get back the
-- button, which they use like the old toolbar button (setOn, setTooltip).

local NEWS_VERSION = 7

-- rows are shown in this order, whatever order the modules load in
local FEATURES = {
    { id = 'vip', group = 'vip', label = 'Mythos VIP', icon = 'vip',
      news = 'Mythos VIP: +10%% experience, loot and training, the Fusca, Uno and Gol mounts and more. The row shows your days left and opens the Store.' },
    { id = 'rates', group = 'hunt', label = 'Hunt Rates', icon = 'rates',
      news = 'The XP and loot rate of every monster changes every 2 hours. See the hottest hunts before you go.' },
    { id = 'board', group = 'hunt', label = 'Leaderboard', icon = 'board',
      news = 'Who kills the most monsters and who makes the most XP in the hour, the day and the month. The top hunters win Mythos Coins.' },
    { id = 'loot', group = 'hunt', label = 'Auto Loot', icon = 'loot',
      news = 'Choose what the auto loot picks up without opening a corpse: your recent drops and a search by name, each with a Take box.' },
    { id = 'tasks', group = 'tasks', label = 'Daily Task', icon = 'tasks',
      news = 'One monster of your level a day, for experience and Hunt Points. The row shows the monster and your kills.' },
    { id = 'trail', group = 'tasks', label = "Hunter's Trail", icon = 'trail',
      news = '70 monsters in order, from the weakest to the strongest, with a bonus every 5 steps.' },
    { id = 'taskshop', group = 'tasks', label = 'Shop', icon = 'taskshop',
      news = 'Hunt Points buy XP potions, rarity scrolls, Rarity XP, Mythos Coins, the Bag of Mythical and more.' },
    { id = 'rarity', group = 'rarity', label = 'Rarity Market', icon = 'rarity',
      news = 'Buy and sell the rarity items that drop from monsters, paid with the gold in your bank.' },
    { id = 'bonus', group = 'rarity', label = 'Roulette', icon = 'bonus',
      news = 'Every bonus of the rarity items you wear, the total of each one and the item it comes from.' },
    { id = 'healbot', group = 'tools', label = 'Heal Bot', icon = 'healbot',
      news = 'Heals you with spells and potions, heals your friends and keeps your buffs up. You choose the rules.' },
    { id = 'messages', group = 'tools', label = 'Interface', icon = 'messages',
      news = 'Interface settings, such as where the look, loot and warning messages show on the game screen.' },
    { id = 'tutorial', group = 'tools', label = 'Tutorial', icon = 'tutorial',
      news = 'A quick tour of every Mythos system, opening each window as it explains it.' },
    { id = 'wiki', group = 'tools', label = 'Wiki', icon = 'wiki',
      news = 'Rare monsters, rarity items and every bonus explained, with the real numbers from the server.' },
}

-- the rows are grouped under these titles (hidden in the icon grid)
local GROUPS = {
    { id = 'vip', label = 'Account' },
    { id = 'hunt', label = 'Hunting' },
    { id = 'tasks', label = 'Tasks' },
    { id = 'rarity', label = 'Rarity' },
    { id = 'tools', label = 'Tools' },
}

local panel, newsWindow, panelButton
local buttons = {}
local callbacks = {}
local states = {}
local toggles = {}
local labels = {} -- per-row text that replaces the feature name
local groupLabels = {} -- group id -> title widget

-- The panel is a mini window: it moves between the side panels, the bottom
-- border resizes it and the header minimizes it. Two extra header buttons:
-- the first switches between every row (full) and only the rows with
-- something to show such as the task kills or the Rarity XP (info). The second one
-- shows the full view as a grid of icons without names. A click on a group
-- title folds that group.
local VIEWS = { 'full', 'info' }
local view = 'full'
local compact = false
local folded = {} -- group id -> true

-- the icon grid only exists in the full view
local function iconGrid()
    return compact and view == 'full'
end

local ROW_HEIGHT, ROW_SPACING = 20, 2
local CELL, CELL_SPACING = 22, 2
local HEADER = 4 + 14 + 4 -- header margin, header, list margin
local GROUP_HEIGHT = 14

local function featureOf(id)
    for index, feature in ipairs(FEATURES) do
        if feature.id == id then
            return feature, index
        end
    end
end

-- order of a widget in the list: a group title just before its first row
local function sortKey(widget)
    local feature, index = featureOf(widget:getId())
    if feature then
        return index
    end
    local groupId = widget:getId():match('^group_(.+)$')
    for i, f in ipairs(FEATURES) do
        if f.group == groupId then
            return i - 0.5
        end
    end
    return 0
end

-- a title shows when its group has at least one row and the names are shown
local function updateGroups()
    local count = 0
    for _, group in ipairs(GROUPS) do
        local label = groupLabels[group.id]
        local used = false
        for id in pairs(buttons) do
            if featureOf(id).group == group.id then
                used = true
                break
            end
        end
        local visible = used and view == 'full' and not compact
        if label then
            label:setVisible(visible)
            label:setOn(folded[group.id] == true)
        end
        if visible then
            count = count + 1
        end
    end
    return count
end

local function iconPath(feature)
    return '/game_brevespanel/images/' .. feature.icon
end

local function refreshBadge(id)
    local button = buttons[id]
    if not button then
        return
    end
    local badge = button.badge
    local state = states[id]
    local feature = featureOf(id)
    button:setTooltip((labels[id] and (tr(feature.label) .. ': ' .. labels[id]) or tr(feature.label)) .. ((iconGrid() and state) and (' (' .. state.text .. ')') or ''))
    -- no room for the badge next to an icon: the state colours the icon's frame
    button:setBorderWidth((iconGrid() and state) and 1 or 0)
    if state then
        button:setBorderColor(state.color)
    end
    if state and iconGrid() then
        badge:hide()
    elseif state then
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

-- the info view keeps the rows that carry a value (kills, XP, ON / OFF)
local function rowVisible(id)
    if view == 'info' then
        return labels[id] ~= nil or states[id] ~= nil
    end
    if iconGrid() then
        return true
    end
    local feature = featureOf(id)
    return not (feature and folded[feature.group])
end

-- fit: grow or shrink the window to its rows (after a change the player
-- made, or rows that came or went); otherwise only the limits move, so a
-- size the player chose by dragging the border stays
local function resize(fit)
    if not panel then
        return
    end
    local list = panel.contentsPanel
    local rows, shown = 0, 0
    for id, button in pairs(buttons) do
        rows = rows + 1
        local visible = rowVisible(id)
        button:setVisible(visible)
        if visible then
            shown = shown + 1
        end
    end
    local groups = updateGroups()
    local padding = list:getPaddingTop() + list:getPaddingBottom()
    local content = padding
    if iconGrid() then
        local width = list:getWidth() - list:getPaddingLeft() - list:getPaddingRight()
        local columns = width > 0 and math.max(1, math.floor((width + CELL_SPACING) / (CELL + CELL_SPACING))) or 7
        local lines = math.ceil(rows / columns)
        content = content + lines * CELL + math.max(0, lines - 1) * CELL_SPACING
    else
        local lines = shown + groups
        content = content + shown * ROW_HEIGHT + groups * GROUP_HEIGHT + math.max(0, lines - 1) * ROW_SPACING
    end
    content = math.max(content, ROW_HEIGHT + padding)
    -- the mini window's content sizes leave out the header strip
    content = content + panel.miniwindowHeader:getHeight()
    panel:setContentMinimumHeight(math.min(content, 2 * ROW_HEIGHT + ROW_SPACING + padding + panel.miniwindowHeader:getHeight()))
    panel:setContentMaximumHeight(content)
    if fit and not panel:isOn() then
        panel:setContentHeight(content)
    end
end

local function styleButton(id)
    local button = buttons[id]
    local feature = featureOf(id)
    if not button or not feature then
        return
    end
    button:setText(iconGrid() and '' or (labels[id] or tr(feature.label)))
    button:setSize({ width = iconGrid() and CELL or button:getWidth(), height = iconGrid() and CELL or ROW_HEIGHT })
    button.icon:setMarginLeft(iconGrid() and 3 or 5)
    refreshBadge(id)
end

-- lays the rows out for the current collapsed / compact state
local function applyLayout()
    if not panel then
        return
    end
    local list = panel.contentsPanel
    if iconGrid() then
        local layout = UIGridLayout.create(list)
        layout:setCellSize({ width = CELL, height = CELL })
        layout:setCellSpacing(CELL_SPACING)
        layout:setFlow(true)
        list:setLayout(layout)
    else
        local layout = UIVerticalLayout.create(list)
        layout:setSpacing(ROW_SPACING)
        list:setLayout(layout)
    end
    for id in pairs(buttons) do
        styleButton(id)
    end
    panel.collapseButton:setOn(view ~= 'full')
    panel.collapseButton:setTooltip(view == 'full' and tr('Only the info') or tr('Show everything'))
    panel.compactButton:setTooltip(compact and tr('Show the names') or tr('Only the icons'))
    -- names or icons only means something in the full view
    panel.compactButton:setVisible(view == 'full')
    resize(true)
end

function toggleCollapsed()
    for index, name in ipairs(VIEWS) do
        if name == view then
            view = VIEWS[index % #VIEWS + 1]
            break
        end
    end
    g_settings.set('breves_panel_view', view)
    applyLayout()
end

function toggleGroup(groupId)
    folded[groupId] = not folded[groupId] or nil
    local names = {}
    for id in pairs(folded) do
        table.insert(names, id)
    end
    g_settings.set('breves_panel_folded', table.concat(names, ','))
    applyLayout()
end

function toggleCompact()
    compact = not compact
    g_settings.set('breves_panel_compact', compact)
    applyLayout()
end

local function sortRows()
    local children = panel.contentsPanel:getChildren()
    table.sort(children, function(a, b)
        return sortKey(a) < sortKey(b)
    end)
    panel.contentsPanel:reorderChildren(children)
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
        button = g_ui.createWidget('BrevesFeatureButton', panel.contentsPanel)
        button:setId(id)
        button:setText(tr(feature.label))
        button.icon:setImageSource(iconPath(feature))
        button.onClick = function() open(id) end
        buttons[id] = button
        -- the feature module destroys its button on unload
        button.onDestroy = function()
            if buttons[id] == button then
                buttons[id] = nil
                callbacks[id] = nil
                resize(true)
            end
        end
    end
    sortRows()
    styleButton(id)
    resize(true)
    return button
end

-- a short state on the right of a row, e.g. ON / OFF
function setFeatureState(id, text, color)
    states[id] = text and { text = text, color = color or '#dfdfdf' } or nil
    refreshBadge(id)
    if view == 'info' then
        resize(true)
    end
end

-- replaces the name shown on a row (nil puts the feature name back), e.g.
-- the Hunt Tasks row shows the current monster and kills
function setFeatureLabel(id, text, color)
    labels[id] = text
    local button = buttons[id]
    if button then
        button:setColor(text and color or '#dfdfdf')
        styleButton(id)
    end
    if view == 'info' then
        resize(true)
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
        row.icon:setImageSource(iconPath(feature))
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

function togglePanel()
    if not panel then
        return
    end
    if panel:isVisible() then
        panel:close()
    else
        panel:open()
        if panel:isOn() then
            panel:maximize()
        end
        panel:raise()
    end
end

local function onGameStart()
    if not panelButton and modules.game_mainpanel and modules.game_mainpanel.addToggleButton then
        panelButton = modules.game_mainpanel.addToggleButton('mythosPanelButton', tr('Mythos panel: tasks, hunt rates, rarity, heal bot'),
            '/game_brevespanel/images/button', togglePanel, true)
    end
    panel:setupOnStart()
    -- the first time, at the top of the right panel, where the old fixed
    -- panel was; after that the mini window settings remember the place
    if not g_settings.getBoolean('breves_panel_placed') then
        g_settings.set('breves_panel_placed', true)
        local right = modules.game_interface.getRightPanel()
        if right and panel:getParent() == right then
            right:moveChildToIndex(panel, 1)
        end
        panel:open(true)
    end
    applyLayout()
    if panelButton then
        panelButton:setOn(panel:isVisible())
    end
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
    -- the gem button among the Tibia option buttons opens it again
    for _, id in ipairs({ 'toggleFilterButton', 'contextMenuButton', 'newWindowButton' }) do
        local button = panel:getChildById(id)
        if button then
            button:hide()
        end
    end
    panel.lockButton:breakAnchors()
    panel.lockButton:addAnchor(AnchorTop, 'parent', AnchorTop)
    panel.lockButton:addAnchor(AnchorRight, 'minimizeButton', AnchorLeft)
    panel.lockButton:setMarginTop(2)
    panel.lockButton:setMarginRight(2)
    panel.onOpen = function()
        if panelButton then
            panelButton:setOn(true)
        end
    end
    panel.onClose = function()
        if panelButton then
            panelButton:setOn(false)
        end
    end
    -- Mythos colours on the Tibia frame
    panel:setImageSource('/images/mythos/panel')
    panel:setImageBorder(4)
    panel.miniwindowHeader:setImageSource('')
    panel.miniwindowHeader:setBackgroundColor('#1c1230')
    for _, group in ipairs(GROUPS) do
        local label = g_ui.createWidget('BrevesGroupLabel', panel.contentsPanel)
        label:setId('group_' .. group.id)
        label:setText(tr(group.label))
        label:hide()
        label.onClick = function()
            toggleGroup(group.id)
            return true
        end
        groupLabels[group.id] = label
    end
    view = g_settings.getString('breves_panel_view')
    if view ~= 'info' then
        view = 'full'
    end
    compact = g_settings.getBoolean('breves_panel_compact')
    folded = {}
    for id in (g_settings.getString('breves_panel_folded') or ''):gmatch('[^,]+') do
        folded[id] = true
    end
    -- the icon grid's line count follows the panel's width
    panel.contentsPanel.onGeometryChange = function(widget, oldRect, newRect)
        if iconGrid() and oldRect.width ~= newRect.width then
            resize(true)
        end
    end
    applyLayout()
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    hideNews()
    hideNotice()
    if panelButton then
        panelButton:destroy()
        panelButton = nil
    end
    if panel then
        panel:destroy()
        panel = nil
    end
    buttons = {}
    callbacks = {}
    groupLabels = {}
end
