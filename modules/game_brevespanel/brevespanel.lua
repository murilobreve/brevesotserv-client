-- Baiak Breves panel: the server's own systems (tasks, hunt rates, leaderboard,
-- rarity market, heal bot) as labelled rows in the right panel, instead of
-- 20px icons lost among the client's buttons. Each row says NEW until the
-- player opens it once, and the news window lists them on the first login
-- after an update.
--
-- The feature modules register their row with addFeature() and get back the
-- button, which they use like the old toolbar button (setOn, setTooltip).

local NEWS_VERSION = 1

-- rows are shown in this order, whatever order the modules load in
local FEATURES = {
    { id = 'tasks', label = 'Hunt Tasks', icon = 'tasks',
      news = "A daily task and the Hunter's Trail, with 70 steps. The points buy items in the task shop, such as the Bag of Mythical." },
    { id = 'rates', label = 'Hunt Rates', icon = 'rates',
      news = 'The XP and loot rate of every monster changes every 2 hours. See the hottest hunts before you go.' },
    { id = 'board', label = 'Leaderboard', icon = 'board',
      news = 'Who kills the most monsters and who makes the most XP in the hour, the day and the month. The top hunters win Breves Coins.' },
    { id = 'rarity', label = 'Rarity Market', icon = 'rarity',
      news = 'Buy and sell the rarity items that drop from monsters, paid with the gold in your bank.' },
    { id = 'healbot', label = 'Heal Bot', icon = 'healbot',
      news = 'Heals you with spells and potions, heals your friends and keeps your buffs up. You choose the rules.' },
}

local panel, newsWindow
local buttons = {}
local callbacks = {}
local states = {}
local pulseEvent

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

local function isSeen(id)
    return g_settings.getBoolean('breves_seen_' .. id)
end

local function refreshBadge(id)
    local button = buttons[id]
    if not button then
        return
    end
    local badge = button.badge
    local state = states[id]
    if not isSeen(id) then
        badge:setText(tr('NEW'))
        badge:setColor('#1a1200')
        badge:setBackgroundColor('#f2b632')
        badge:show()
    elseif state then
        badge:setText(state.text)
        badge:setColor(state.color)
        badge:setBackgroundColor('#00000080')
        badge:show()
    else
        badge:hide()
    end
end

-- the NEW badges blink between two golds until every row was opened once
local function pulse(bright)
    pulseEvent = nil
    local any = false
    for id, button in pairs(buttons) do
        if not isSeen(id) then
            any = true
            button.badge:setBackgroundColor(bright and '#ffd76a' or '#f2b632')
        end
    end
    if any then
        pulseEvent = scheduleEvent(function() pulse(not bright) end, 700)
    end
end

local function startPulse()
    if not pulseEvent then
        pulse(true)
    end
end

local function markSeen(id)
    if not isSeen(id) then
        g_settings.set('breves_seen_' .. id, true)
        refreshBadge(id)
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
    local height = rows > 0 and (10 + rows * 20 + (rows - 1) * 2) or 0
    panel.panelHeight = height
    panel:setHeight(height)
    panel:setVisible(rows > 0)
    if modules.game_mainpanel and modules.game_mainpanel.reloadMainPanelSizes then
        modules.game_mainpanel.reloadMainPanelSizes()
    end
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
    markSeen(id)
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
    button:setTooltip(tr(feature.label))
    sortRows()
    refreshBadge(id)
    if not isSeen(id) then
        startPulse()
    end
    resize()
    return button
end

-- a short state on the right of a row once it is no longer NEW, e.g. ON / OFF
function setFeatureState(id, text, color)
    states[id] = text and { text = text, color = color or '#dfdfdf' } or nil
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
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if pulseEvent then
        removeEvent(pulseEvent)
        pulseEvent = nil
    end
    hideNews()
    if panel then
        panel:destroy()
        panel = nil
    end
    buttons = {}
    callbacks = {}
end
