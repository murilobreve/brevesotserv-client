-- Baiak Mythicum panel: the server's own systems (tasks, hunt rates, leaderboard,
-- rarity market, heal bot) as labelled rows in the right panel, instead of
-- 20px icons lost among the client's buttons. The news window lists them on
-- the first login after an update.
--
-- The feature modules register their row with addFeature() and get back the
-- button, which they use like the old toolbar button (setOn, setTooltip).

local NEWS_VERSION = 4

-- rows are shown in this order, whatever order the modules load in
local FEATURES = {
    { id = 'tasks', label = 'Hunt Tasks', icon = 'tasks',
      news = "A daily task and the Hunter's Trail, with 70 steps. The points buy items in the task shop, such as the Bag of Mythical." },
    { id = 'rates', label = 'Hunt Rates', icon = 'rates',
      news = 'The XP and loot rate of every monster changes every 2 hours. See the hottest hunts before you go.' },
    { id = 'messages', label = 'Screen Messages', icon = 'messages',
      news = 'Move the look, loot and warning messages anywhere on the game screen with two sliders.' },
    { id = 'board', label = 'Leaderboard', icon = 'board',
      news = 'Who kills the most monsters and who makes the most XP in the hour, the day and the month. The top hunters win Mythicum Coins.' },
    { id = 'rarity', label = 'Rarity Market', icon = 'rarity',
      news = 'Buy and sell the rarity items that drop from monsters, paid with the gold in your bank.' },
    { id = 'bonus', label = 'Rarity Bonuses', icon = 'bonus',
      news = 'Every bonus of the rarity items you wear, the total of each one and the item it comes from.' },
    { id = 'loot', label = 'Auto Loot', icon = 'loot',
      news = 'Choose what the auto loot picks up without opening a corpse: your recent drops and a search by name, each with a Take box.' },
    { id = 'healbot', label = 'Heal Bot', icon = 'healbot',
      news = 'Heals you with spells and potions, heals your friends and keeps your buffs up. You choose the rules.' },
    { id = 'wiki', label = 'Wiki', icon = 'wiki',
      news = 'Rare monsters, rarity items and every bonus explained, with the real numbers from the server.' },
}

local panel, newsWindow
local buttons = {}
local callbacks = {}
local states = {}
local toggles = {}

-- the title line's two buttons: collapsed hides the rows (vertical),
-- compact shows them as a grid of icons without names (horizontal)
local collapsed = false
local compact = false

local ROW_HEIGHT, ROW_SPACING = 20, 2
local CELL, CELL_SPACING = 22, 2
local HEADER = 4 + 14 + 4 -- header margin, header, list margin

local function featureOf(id)
    for index, feature in ipairs(FEATURES) do
        if feature.id == id then
            return feature, index
        end
    end
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
    button:setTooltip(tr(feature.label) .. ((compact and state) and (' (' .. state.text .. ')') or ''))
    -- no room for the badge next to an icon: the state colours the icon's frame
    button:setBorderWidth((compact and state) and 1 or 0)
    if state then
        button:setBorderColor(state.color)
    end
    if state and compact then
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

local function resize()
    if not panel then
        return
    end
    local rows = 0
    for _ in pairs(buttons) do
        rows = rows + 1
    end
    local height = 0
    if rows > 0 and collapsed then
        height = HEADER
    elseif rows > 0 and compact then
        local width = panel.list:getWidth()
        local columns = math.max(1, math.floor((width + CELL_SPACING) / (CELL + CELL_SPACING)))
        if width <= 0 then
            columns = 7
        end
        local lines = math.ceil(rows / columns)
        height = HEADER + lines * CELL + (lines - 1) * CELL_SPACING + 4
    elseif rows > 0 then
        height = HEADER + rows * ROW_HEIGHT + (rows - 1) * ROW_SPACING + 4
    end
    panel.panelHeight = height
    panel:setHeight(height)
    panel:setVisible(rows > 0)
    if modules.game_mainpanel and modules.game_mainpanel.reloadMainPanelSizes then
        modules.game_mainpanel.reloadMainPanelSizes()
    end
end

local function styleButton(id)
    local button = buttons[id]
    local feature = featureOf(id)
    if not button or not feature then
        return
    end
    button:setText(compact and '' or tr(feature.label))
    button:setSize({ width = compact and CELL or button:getWidth(), height = compact and CELL or ROW_HEIGHT })
    button.icon:setMarginLeft(compact and 3 or 5)
    refreshBadge(id)
end

-- lays the rows out for the current collapsed / compact state
local function applyLayout()
    if not panel then
        return
    end
    local list = panel.list
    if compact then
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
    list:setVisible(not collapsed)

    local header = panel.header
    header.collapseButton:setOn(collapsed)
    header.collapseButton:setTooltip(collapsed and tr('Show') or tr('Hide'))
    header.compactButton:setTooltip(compact and tr('Show the names') or tr('Only the icons'))
    -- with the rows hidden there is nothing to switch between names and icons
    header.compactButton:setVisible(not collapsed)
    resize()
end

function toggleCollapsed()
    collapsed = not collapsed
    g_settings.set('breves_panel_collapsed', collapsed)
    applyLayout()
end

function toggleCompact()
    compact = not compact
    g_settings.set('breves_panel_compact', compact)
    applyLayout()
end

local function placeInRightPanel()
    local mainRightPanel = modules.game_interface.getMainRightPanel()
    if not panel or not mainRightPanel then
        return
    end
    if panel:getParent() ~= mainRightPanel then
        if panel:getParent() then
            panel:getParent():removeChild(panel)
        end
        mainRightPanel:addChild(panel)
    end
    -- right under the store and control buttons
    local options = mainRightPanel:getChildById('mainoptionspanel')
    if options then
        mainRightPanel:moveChildToIndex(panel, mainRightPanel:getChildIndex(options) + 1)
    end
end

local function sortRows()
    local children = panel.list:getChildren()
    table.sort(children, function(a, b)
        return select(2, featureOf(a:getId())) < select(2, featureOf(b:getId()))
    end)
    panel.list:reorderChildren(children)
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
        button = g_ui.createWidget('BrevesFeatureButton', panel.list)
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
                resize()
            end
        end
    end
    sortRows()
    styleButton(id)
    resize()
    return button
end

-- a short state on the right of a row, e.g. ON / OFF
function setFeatureState(id, text, color)
    states[id] = text and { text = text, color = color or '#dfdfdf' } or nil
    refreshBadge(id)
end

-- makes the state badge of a row a switch: a click runs `callback`
function setFeatureToggle(id, callback)
    toggles[id] = callback
    refreshBadge(id)
end

-- ---------------------------------------------------------------- news window

function hideNews()
    if newsWindow then
        newsWindow:destroy()
        newsWindow = nil
    end
end

function showNews()
    hideNews()
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

local function onGameStart()
    placeInRightPanel()
    resize()
    if g_settings.getNumber('breves_news_version') < NEWS_VERSION then
        g_settings.set('breves_news_version', NEWS_VERSION)
        -- written now: a client that crashes never saves its settings on exit
        g_settings.save()
        -- after the feature modules added their rows
        scheduleEvent(showNews, 1500)
    end
end

local function onGameEnd()
    hideNews()
end

function init()
    g_ui.importStyle('brevespanel')
    panel = g_ui.createWidget('BrevesPanel')
    panel:setId('brevespanel')
    panel:hide()
    collapsed = g_settings.getBoolean('breves_panel_collapsed')
    compact = g_settings.getBoolean('breves_panel_compact')
    -- the icon grid's line count follows the panel's width
    panel.list.onGeometryChange = function(widget, oldRect, newRect)
        if compact and oldRect.width ~= newRect.width then
            resize()
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
    if panel then
        panel:destroy()
        panel = nil
    end
    buttons = {}
    callbacks = {}
end
