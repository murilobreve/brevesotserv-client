-- Mythos bar: the server's own systems (tasks, hunt rates, leaderboard,
-- rarity market, heal bot) in a bar under the game screen, just above the
-- spell bar: four framed sections side by side, Tasks, Hunts, Rarity and
-- Tools, and the VIP button after them. It cannot be closed; it lies over
-- the bottom of the map, which shows through it.
-- The news window lists the systems on the first login after an update.
--
-- The feature modules register their row with addFeature() and get back the
-- button, which they use like the old toolbar button (setOn, setTooltip).

local NEWS_VERSION = 11

-- rows are shown in this order, whatever order the modules load in
local FEATURES = {
    { id = 'vip', group = 'vip', label = 'Mythos VIP', icon = 'vip',
      news = 'Mythos VIP: +10%% experience, loot and training, the Fusca, Uno and Gol mounts and more. The row shows your days left and opens the Store.' },
    { id = 'tasks', group = 'tasks', label = 'Daily Task', short = 'Task', icon = 'tasks',
      news = 'One monster of your level a day, for experience and Hunt Points. The row shows the monster and your kills.' },
    { id = 'trail', group = 'tasks', label = "Hunter's Trail", short = 'Trail', icon = 'trail',
      news = '70 monsters in order, from the weakest to the strongest, with a bonus every 5 steps.' },
    { id = 'taskshop', group = 'tasks', label = 'Shop', icon = 'taskshop',
      news = 'Hunt Points buy XP potions, rarity scrolls, Rarity XP, Mythos Coins, the Bag of Mythical and more.' },
    { id = 'rates', group = 'hunt', label = 'Hunts TP', short = 'TP', icon = 'rates',
      news = 'Every hunt in one list: the XP and loot rate of each monster, which change every 2 hours, and a TP to its hunt every 30 seconds.' },
    { id = 'board', group = 'hunt', label = 'Leaderboard', icon = 'board',
      news = 'Who kills the most monsters and who makes the most XP in the hour, the day and the month. The top hunters win Mythos Coins.' },
    { id = 'loot', group = 'hunt', label = 'Auto Loot', short = 'Loot', icon = 'loot',
      news = 'Choose what the auto loot picks up without opening a corpse: your recent drops and a search by name, each with a Take box.' },
    { id = 'bosses', group = 'hunt', label = 'Bosses', icon = 'bosses',
      news = 'The bosses of the official quests, each in its own lever room: pick one, go there with your team and pull the lever. The list shows your wait for each.' },
    { id = 'rarity', group = 'rarity', label = 'Rarity Market', short = 'Market', icon = 'rarity',
      news = 'Buy and sell the rarity items that drop from monsters, paid with the gold in your bank.' },
    { id = 'bonus', group = 'rarity', label = 'Roulette', icon = 'bonus',
      news = 'Every bonus of the rarity items you wear, the total of each one and the item it comes from.' },
    { id = 'incense', group = 'rarity', label = 'Incense', icon = 'incense',
      news = 'Hunting incense: for an hour, more rare monsters and more Rarity XP. One a day, priced by your level.' },
    { id = 'ascensao', group = 'tools', label = 'Ascens\227o', short = 'Ascens\227o', icon = 'ascensao',
      news = 'Ascens\227o: from level 50 you earn 1 point every 10 levels for three paths of your vocation. The first circle of each path teaches one of the new aimed spells, and every circle makes it stronger, up to level 1500.' },
    { id = 'healbot', group = 'tools', label = 'Heal Bot', short = 'Bot', icon = 'healbot',
      news = 'Heals you with spells and potions, heals your friends and keeps your buffs up. You choose the rules.' },
    { id = 'messages', group = 'tools', label = 'Interface', icon = 'messages',
      news = 'Interface settings, such as where the look, loot and warning messages show on the game screen.' },
    { id = 'wiki', group = 'tools', label = 'Wiki', icon = 'wiki',
      news = 'Rare monsters, rarity items and every bonus explained, with the real numbers from the server.' },
    -- only when the game runs in a browser
    { id = 'fullscreen', group = 'tools', label = 'Fullscreen', short = 'Tela', icon = 'fullscreen', browserOnly = true,
      news = 'Plays in full screen (also F11 or Ctrl+Shift+F). In full screen the browser leaves the game keys alone: Ctrl+N, Ctrl+W, Esc and the others reach the game.' },
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
local actions = {} -- row id -> { text, tooltip, enabled, callback }: a small button on the row
local sectors = {} -- section id -> section widget
local vipHolder -- the VIP button's box in the bar

local BUTTON_SPACING = 2 -- between the buttons of a section (otui)
local SECTOR_SPACING = 6 -- between the sections (otui)
local SECTOR_PADDING = 8 -- the buttons' margins, left and right
local TITLE_ROOM = 18 + 16 + 6 + 22 -- header art end, icon, gap, the other end
local ICON_ONLY = 24 -- a button's width with its icon alone
-- how much the buttons show, as the screen narrows: their names, short
-- names, the icon with its state (ON / OFF, points, minutes), the icon alone
local FULL, SHORT, STATES, ICONS = 0, 1, 2, 3
local density = FULL
local TOGGLE_WIDTH = 28 -- a switch's badge, as wide for ON as for OFF
-- the widest each button has been at each level since login: a name or a
-- badge that changes by itself (the teleport countdown, points, minutes)
-- never makes the bar jump between levels; only the window size does
local widest = {}

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
        -- a switch keeps one width, so turning it on or off never moves the bar
        badge:setTextAutoResize(not toggles[id])
        if toggles[id] then
            badge:setWidth(math.max(TOGGLE_WIDTH, badge:getTextSize().width + 8))
        end
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
    if density == ICONS and button:getId() ~= 'vip' then
        return ICON_ONLY
    end
    local width = button:getText() == '' and ICON_ONLY or 23 + button:getTextSize().width + 6
    if button.badge:isVisible() then
        width = width + button.badge:getWidth() + 4
    end
    if button.action:isVisible() then
        width = width + button.action:getWidth() + 6
    end
    return width
end

-- widths of the buttons and the sections; when everything does not fit, the
-- names get short, then give way to the icons with their state, and only on a
-- very narrow screen to the icons alone
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
                    local key = button:getId() .. ':' .. density
                    widest[key] = math.max(widest[key] or 0, buttonWidth(button))
                    button:setWidth(widest[key])
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
    local function apply(level)
        density = level
        for id in pairs(buttons) do
            styleButton(id)
        end
        return measure()
    end
    local room = panel:getWidth() - 24
    for level = FULL, ICONS do
        if apply(level) <= room or room <= 0 then
            break
        end
    end
end

styleButton = function(id)
    local button = buttons[id]
    local feature = featureOf(id)
    if not button or not feature then
        return
    end
    -- the VIP button keeps its text: it is the one that sells
    local level = id == 'vip' and FULL or density
    local name = labels[id] or tr(level == SHORT and feature.short or feature.label)
    button:setText(level >= STATES and '' or name)
    -- without its name, the name is in the tooltip (refreshBadge)
    refreshBadge(id)
    local iconsOnly = level == ICONS
    if iconsOnly then
        button.badge:hide()
    end
    -- the row's quick action, left of the badge; none in the icons-only bar
    local action = actions[id]
    button.action:setVisible(action ~= nil and not iconsOnly)
    if action then
        button.action:setText(level >= SHORT and action.short or action.text)
        button.action:setTooltip(action.tooltip or '')
        button.action:setEnabled(action.enabled ~= false)
        button.action.onClick = function()
            action.callback()
            return true
        end
    end
    button.badge:setMarginRight((action and not iconsOnly) and (button.action:getWidth() + 6) or 3)
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

-- ---------------------------------------------------------------- gains

local GAIN_STEPS, GAIN_STEP_MS = 40, 40 -- the count up takes about 1.6 seconds
local FLOAT_STEPS, FLOAT_STEP_MS = 70, 40 -- the "+N" pill rises for about 2.8 seconds
local FLOAT_RISE = 46 -- pixels the pill climbs
local gainEvents = {} -- row id -> the running count up

-- the first number in a badge ("2.990 pts", "65 XP"), whatever thousands mark it uses
local function numberIn(text)
    local digits = text and text:match('%d[%d.,]*')
    if not digits then
        return nil
    end
    return tonumber((digits:gsub('[.,]', ''))), digits
end

-- `template` with its number swapped for `value`, written with the same thousands mark
local function withNumber(template, value)
    local _, digits = numberIn(template)
    local mark = digits and digits:match('[.,]')
    local text = tostring(math.floor(value))
    if mark then
        text = text:reverse():gsub('(%d%d%d)', '%1' .. mark):reverse():gsub('^%' .. mark, '')
    end
    return (template:gsub('%d[%d.,]*', text, 1))
end

-- a gold pill with "+500 pts" over the row: it pops in, climbs, holds and
-- fades; it never takes a click
local function floatGain(button, text)
    local root = panel and panel:getParent()
    if not root then
        return
    end
    local label = g_ui.createWidget('BrevesGainLabel', root)
    label:setText(text)
    local size = label:getTextSize()
    label:setSize({ width = size.width + 24, height = size.height + 10 })
    local pos = button:getPosition()
    local x = math.max(0, pos.x + math.floor((button:getWidth() - label:getWidth()) / 2))
    local y = pos.y - label:getHeight() - 8
    label:setPosition({ x = x, y = y })
    label:raise()
    for step = 1, FLOAT_STEPS do
        scheduleEvent(function()
            if label:isDestroyed() then
                return
            end
            if step == FLOAT_STEPS then
                label:destroy()
                return
            end
            local t = step / FLOAT_STEPS
            -- climbs fast, then slows; a small pop at the start
            local rise = math.floor(FLOAT_RISE * (1 - (1 - t) ^ 3))
            local pop = step <= 4 and (4 - step) * 2 or 0
            label:setPosition({ x = x, y = y - rise - pop })
            -- fully visible for the first 60%, then fades out
            label:setOpacity(t < 0.6 and 1 or math.max(0, 1 - (t - 0.6) / 0.4))
        end, step * FLOAT_STEP_MS)
    end
end

-- the badge counts from `from` up to the number in `text`; the row pulses
-- gold, and the badge blinks when it lands on the new value
local function animateGain(id, from, to, text)
    local button = buttons[id]
    if not button or density == ICONS or not button.badge:isVisible() then
        return
    end
    if gainEvents[id] then
        removeEvent(gainEvents[id])
        gainEvents[id] = nil
    end
    local badge = button.badge
    floatGain(button, '+' .. withNumber(text, to - from))
    button.glow:show()
    local step = 0
    local blinks = 6 -- after the count: three gold flashes of the badge
    local function tick()
        step = step + 1
        if buttons[id] ~= button or not states[id] or states[id].text ~= text then
            button.glow:hide()
            gainEvents[id] = nil
            return
        end
        if step <= GAIN_STEPS then
            -- eases out: fast at first, settling on the new value
            local t = 1 - (1 - step / GAIN_STEPS) ^ 3
            badge:setText(step == GAIN_STEPS and text or withNumber(text, from + (to - from) * t))
            badge:setBackgroundColor('#f1d39955')
            badge:setBorderColor('#ffe7b0')
            badge:setBorderWidth(1)
            -- the row breathes: two slow pulses during the count
            button.glow:setOpacity(0.18 + 0.32 * (0.5 + 0.5 * math.cos(step / GAIN_STEPS * math.pi * 4)))
        else
            local blink = step - GAIN_STEPS
            local on = blink % 2 == 1
            badge:setBackgroundColor(on and '#f1d399aa' or '#f1d39933')
            button.glow:setOpacity(on and 0.5 or 0.12)
            if blink >= blinks then
                badge:setBackgroundColor('#00000080')
                badge:setBorderColor('#6a5226')
                badge:setBorderWidth(toggles[id] and 1 or 0)
                button.glow:hide()
                gainEvents[id] = nil
                return
            end
            gainEvents[id] = scheduleEvent(tick, 140)
            return
        end
        gainEvents[id] = scheduleEvent(tick, GAIN_STEP_MS)
    end
    tick()
end

-- a short state on the right of a row, e.g. ON / OFF; when the number in it
-- goes up (Hunt Points, Rarity XP) the badge counts up to the new value
function setFeatureState(id, text, color)
    local before = numberIn(states[id] and states[id].text)
    states[id] = text and { text = text, color = color or '#dfdfdf' } or nil
    styleButton(id)
    resize()
    local after = numberIn(text)
    if before and after and after > before then
        animateGain(id, before, after, text)
    end
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

-- a small button on the right of a row (nil text removes it), e.g. the Trail
-- row's hunt teleport; `enabled` false greys it, for a cooldown; `short` is
-- its text when the bar is short of room
function setFeatureAction(id, text, tooltip, callback, enabled, short)
    actions[id] = (text and callback) and { text = text, short = short or text, tooltip = tooltip, callback = callback, enabled = enabled } or nil
    if buttons[id] then
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
        if not feature.browserOnly or g_platform.isBrowser() then
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
    end
    newsWindow:raise()
    newsWindow:focus()
end


local BAR_HEIGHT, FOLDED_HEIGHT = 53, 22
local collapsed = false

-- folds the bar to one line or opens it
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

-- the game writes its messages (loot, "You see", warnings) at the bottom of
-- the map (game_textmessage's statusLabel): they go up by the bar's height
-- so the bar never covers them
local STATUS_MARGIN = 7 -- statusLabel's own margin-bottom (textmessage.otui)
local function keepMessagesClear()
    local root = modules.game_interface and modules.game_interface.getRootPanel()
    local label = root and root:recursiveGetChildById('statusLabel')
    if label then
        local covered = (panel and panel:isVisible()) and panel:getHeight() or 0
        label:setMarginBottom(STATUS_MARGIN + covered)
    end
end

-- the bar lies over the bottom of the map, just above the spell bars; the map
-- keeps its size and shows through the bar's background
local function placeBar()
    local root = modules.game_interface and modules.game_interface.getRootPanel()
    if panel or not root then
        return panel ~= nil
    end
    panel = g_ui.createWidget('BrevesBar', root)
    panel:addAnchor(AnchorLeft, 'gameMapPanel', AnchorLeft)
    panel:addAnchor(AnchorRight, 'gameMapPanel', AnchorRight)
    panel:addAnchor(AnchorBottom, 'gameMapPanel', AnchorBottom)
    for _, sector in ipairs(SECTORS) do
        local widget = g_ui.createWidget('BrevesSector', panel.strip)
        widget:setId('sector_' .. sector.id)
        widget.title:setText(tr(sector.label))
        widget.icon:setImageSource(iconPath(sector.icon))
        widget:hide()
        sectors[sector.id] = widget
    end
    -- names or icons follow the width of the map; the messages follow its
    -- height (open or folded)
    panel.onGeometryChange = function(widget, oldRect, newRect)
        if oldRect.width ~= newRect.width then
            resize()
        end
        if oldRect.height ~= newRect.height then
            keepMessagesClear()
        end
    end
    panel.onVisibilityChange = keepMessagesClear
    return true
end

-- the browser's full screen: the game keys stop being the browser's
local function toggleFullscreen()
    g_window.setFullscreen(not g_window.isFullscreen())
end

local function onGameStart()
    -- another character: its rows measure afresh
    widest = {}
    placeBar()
    if g_platform.isBrowser() then
        addFeature('fullscreen', toggleFullscreen)
    end
    -- open on every login, whatever it was when the player left
    setCollapsed(false)
    resize()
    keepMessagesClear()
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
        panel:destroy()
        panel = nil
    end
    for id, event in pairs(gainEvents) do
        removeEvent(event)
    end
    gainEvents = {}
    buttons = {}
    callbacks = {}
    actions = {}
    sectors = {}
    vipHolder = nil
end
