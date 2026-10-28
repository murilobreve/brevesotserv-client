-- Hunter's Journey (Jornada do Caçador): the first steps of a new player.
-- The server (data-otservbr-global/scripts/journey/journey.lua, extended
-- opcode 136) keeps three steps - go to a hunt with the Teleports list, go to
-- the task monster with "Go hunt", spin the Rarity Roulette - and pays a
-- reward when all three are done. This module shows them:
--   * a mini window on the left with the three steps and their buttons;
--   * the bar rows of the next step breathe gold, the Roulette row shows the
--     spins the player can pay (game_brevespanel);
--   * a card with the best hunt for the player's level over the map, on
--     login and when the player stands idle in a protection zone;
--   * a celebration when the first rarity item drops;
--   * a hint when the player walks up to the hunts teleport of a temple.
-- Each of them closes with its x. Closing the window turns the journey off
-- for the character (no glow, card or hint); the "?" of the bar, which
-- starts the tour, brings it back (reopen).

local OPCODE = 136
local IDLE_SECONDS = 25 -- standing still in a protection zone, before the card
local CARD_COOLDOWN = 10 * 60 -- seconds between two idle cards
local PORTAL_RANGE = 2 -- sqm from the hunts teleport of a temple

local STEPS = {
    { key = 'hunt', icon = '/game_brevespanel/images/rates', title = 'Go hunting' },
    { key = 'task', icon = '/game_brevespanel/images/tasks', title = 'Do your task' },
    { key = 'roulette', icon = '/game_brevespanel/images/bonus', title = 'Spin your luck' },
}

local GRADE_COLORS = {
    uncommon = '#63c08a', rare = '#4f8fe8', epic = '#af78ea', legendary = '#e2a443', mythic = '#e8e4ff',
}

local window, card, rareWindow
local journey -- the server's state (see the server file)
local taskState -- game_hunttasks' state: the daily task and the Trail
local cardDismissed = false -- the card's x: no idle card again this login
local cardShownAt = 0
local lastMoveAt = 0
local portalHinted = false
local hintShown = false -- the portal hint is on the Teleports row
local checkEvent, raysEvent, firstStateEvent
local closeForGood -- the journey window's own close (below)

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(OPCODE, data)
    end
end

local function panel()
    return modules.game_brevespanel
end

-- the player closed the journey (per character)
local function hiddenKey()
    return 'journey_hidden_' .. (g_game.getCharacterName() or '')
end

local function isHidden()
    return g_settings.getBoolean(hiddenKey())
end

local function allDone()
    return journey and journey.steps and journey.steps.hunt and journey.steps.task and journey.steps.roulette
end

-- ---------------------------------------------------------------- the bar

-- the next step's rows breathe gold; the Roulette shows its spins
local function updateBar()
    local bar = panel()
    if not bar or not bar.setFeatureHighlight or not journey then
        return
    end
    -- a closed journey asks for nothing
    local hidden = isHidden()
    local steps = journey.steps or {}
    bar.setFeatureHighlight('rates', not hidden and not steps.hunt)
    bar.setFeatureHighlight('tasks', not hidden and not steps.task)
    bar.setFeatureHighlight('trail', not hidden and not steps.task)
    local spins = journey.spins or {}
    local count = tonumber(spins.count) or 0
    bar.setFeatureHighlight('bonus', not hidden and spins.worn and count > 0 and not steps.roulette or false)
    local flag
    if hidden then
        flag = nil
    elseif spins.worn and count == 1 then
        flag = tr('1 SPIN')
    elseif spins.worn and count > 1 then
        flag = tr('%s SPINS', count > 99 and '99+' or tostring(count))
    end
    bar.setFeatureFlag('bonus', flag, '#d8483e')
end

-- ---------------------------------------------------------------- the window

local function taskOf()
    local state = taskState
    if not state then
        return nil
    end
    local daily = state.daily
    if daily and daily.monster and not daily.done and state.teleportDaily then
        return { which = 'daily', name = daily.monster, kills = daily.kills or 0, need = daily.need or 0 }
    end
    local trail = state.trail
    local step = trail and not trail.finished and trail.steps and trail.steps[trail.index]
    if step then
        return { which = state.teleportTrail and 'trail' or nil, name = step.name, kills = trail.kills or 0, need = step.need or 0 }
    end
    return nil
end

local function stepHeight(step)
    local height = 6 + 18 + 6
    if step.text:isVisible() then
        height = height + 4 + step.text:getHeight()
    end
    if step.bar:isVisible() then
        height = height + 4 + 6
    end
    if step.action:isVisible() then
        height = height + 6 + step.action:getHeight()
    end
    return height
end

-- each step: its title, a short line only when it says something (the task's
-- kills) and the button that does it
local function fillStep(widget, index, done, active)
    local def = STEPS[index]
    widget:setOn(active)
    widget:setOpacity(done and 0.7 or 1)
    widget.icon:setImageSource(def.icon)
    widget.title:setText(tr(def.title))
    widget.title:setColor(done and '#ab9fc6' or '#ffd682')
    widget.mark:setImageSource(done and '/game_journey/images/step_done' or (active and '/game_journey/images/step_active' or '/game_journey/images/step_next'))
    widget.number:setText(done and '' or tostring(index))
    widget.number:setColor(active and '#1d1206' or '#e6e0f2')
    widget.bar:hide()
    local text, button, onClick
    if def.key == 'hunt' then
        button = tr('TELEPORTS')
        onClick = function()
            if panel() then
                panel().open('rates')
            end
        end
    elseif def.key == 'task' then
        local task = taskOf()
        if task and not done then
            text = string.format('%s  %d/%d', task.name, task.kills, task.need)
            if task.need > 0 then
                widget.bar:show()
                local width = math.floor(widget.bar:getWidth() * math.min(1, task.kills / task.need))
                widget.bar.fill:setWidth(math.max(0, width))
            end
        end
        button = tr('GO HUNT')
        onClick = function()
            local t = taskOf()
            if t and t.which and modules.game_hunttasks and modules.game_hunttasks.teleport then
                modules.game_hunttasks.teleport(t.which)
            elseif panel() then
                panel().open('tasks')
            end
        end
    else
        button = tr('SPIN')
        onClick = function()
            if modules.game_raritybonus and modules.game_raritybonus.request then
                modules.game_raritybonus.request()
            end
        end
    end
    widget.text:setText(text or '')
    widget.text:setVisible(text ~= nil)
    widget.action:setText(button)
    widget.action.onClick = onClick
    widget.action:setEnabled(true)
    -- a done step needs no button
    widget.action:setVisible(not done)
end

local function layoutWindow()
    if not window then
        return
    end
    local contents = window.contentsPanel
    -- the text wraps to the width it has: measured once it is laid out
    scheduleEvent(function()
        if not window or window:isDestroyed() then
            return
        end
        local total = 0
        local count = 0
        for _, child in ipairs(contents:getChildren()) do
            if child:isVisible() then
                if child:getId():match('^step') then
                    child:setHeight(stepHeight(child))
                end
                total = total + child:getHeight() + child:getMarginTop() + child:getMarginBottom()
                count = count + 1
            end
        end
        total = total + math.max(0, count - 1) * 5 + contents:getPaddingTop() + contents:getPaddingBottom() + 2
        window:setContentMinimumHeight(math.min(total, 200))
        window:setContentHeight(total)
    end, 20)
end

local function fillWindow()
    if not window or not journey then
        return
    end
    local contents = window.contentsPanel
    window.miniwindowTitle:setText(tr("Hunter's Journey"))
    local steps = journey.steps or {}
    local reward = journey.reward or {}
    local doneCount = 0
    local active
    for index, def in ipairs(STEPS) do
        if steps[def.key] then
            doneCount = doneCount + 1
        elseif not active then
            active = index
        end
    end
    local finished = doneCount == #STEPS
    contents.subtitle:setText(tr('Journey complete!'))
    contents.subtitle:setVisible(finished)
    for index = 1, #STEPS do
        local widget = contents['step' .. index]
        fillStep(widget, index, steps[STEPS[index].key], index == active)
    end
    contents.reward:setText(tr(finished and 'You got: %d Rarity XP + %d Hunt Points' or 'Reward: %d Rarity XP + %d Hunt Points', reward.rarityXp or 0, reward.huntPoints or 0))
    contents.doneButton:setVisible(finished)
    contents.doneButton:setText(tr('Close'))
    contents.doneButton.onClick = function()
        closeForGood()
    end
    layoutWindow()
end

local function ensureWindow()
    if window then
        return window
    end
    local interface = modules.game_interface
    if not interface then
        return nil
    end
    local left = interface.getLeftPanel and interface.getLeftPanel()
    local parent = (left and left:isVisible() and left:getWidth() > 0) and left or nil
    window = g_ui.createWidget('JourneyWindow', parent or interface.getRightPanel())
    if not parent and interface.findContentPanelAvailable then
        local found = interface.findContentPanelAvailable(window, 200)
        if found and found ~= window:getParent() then
            window:setParent(found)
        end
    end
    window:setup()
    -- only minimize and close: the title needs the room
    for _, id in ipairs({ 'toggleFilterButton', 'contextMenuButton', 'newWindowButton', 'lockButton' }) do
        local button = window:recursiveGetChildById(id)
        if button then
            button:setVisible(false)
        end
    end
    local closeButton = window:recursiveGetChildById('closeButton')
    if closeButton then
        closeButton.onClick = function()
            closeForGood()
            return true
        end
    end
    -- the journey goes first in its column
    local column = window:getParent()
    if column and column.moveChildToIndex then
        column:moveChildToIndex(window, 1)
    end
    return window
end

local function showWindow()
    if isHidden() or not ensureWindow() then
        return
    end
    window:open(true)
    fillWindow()
end

-- the window's x (or Close once complete): the journey is off for good. Not
-- every close() (the interface also closes a window it moves to another
-- column), so the button says it
function closeForGood()
    g_settings.set(hiddenKey(), true)
    g_settings.save()
    updateBar()
    if window then
        window:close()
    end
end

-- ---------------------------------------------------------------- the hunt card

local function hideCard()
    if card then
        card:destroy()
        card = nil
    end
end

local function outfitOf(raw)
    raw = raw or {}
    return {
        type = raw.lookType or 0, head = raw.lookHead or 0, body = raw.lookBody or 0,
        legs = raw.lookLegs or 0, feet = raw.lookFeet or 0, addons = raw.lookAddons or 0,
    }
end

local function showCard(hunt)
    hideCard()
    local interface = modules.game_interface
    local root = interface and interface.getRootPanel and interface.getRootPanel()
    if not hunt or not root or not g_game.isOnline() then
        return
    end
    -- the tour comes first
    if modules.game_tutorial and modules.game_tutorial.isRunning and modules.game_tutorial.isRunning() then
        return
    end
    card = g_ui.createWidget('JourneyHuntCard', root)
    card:addAnchor(AnchorLeft, 'gameMapPanel', AnchorLeft)
    card:addAnchor(AnchorBottom, 'gameMapPanel', AnchorBottom)
    card:setMarginLeft(8)
    card:setMarginBottom(8)
    card.title:setText(tr('RECOMMENDED HUNT'))
    card.level:setText(tr('level %d', tonumber(hunt.level) or 0))
    card.frame.creature:setOutfit(outfitOf(hunt.outfit))
    card.name:setText(hunt.town ~= '' and string.format('%s  -  %s', hunt.name, hunt.town) or hunt.name)
    card.rates:setText(tr('XP x%.1f    Loot x%.1f', tonumber(hunt.xp) or 1, tonumber(hunt.loot) or 1))
    card.task:setText(hunt.task == 'daily' and tr('Your daily task!') or (hunt.task == 'trail' and tr('Your Trail monster!')) or '')
    card.goButton:setText(tr('TELEPORT'))
    card.goButton.onClick = function()
        local board = modules.game_huntboard
        if board and board.teleportToHunt then
            local wait = board.teleportToHunt(hunt.name)
            if wait > 0 then
                modules.game_textmessage.displayFailureMessage(tr('The hunt teleport is back in %d seconds.', wait))
                return
            end
        end
        hideCard()
    end
    card.allButton:setText(tr('see all'))
    card.allButton.onClick = function()
        hideCard()
        if panel() then
            panel().open('rates')
        end
    end
    card.closeButton.onClick = function()
        cardDismissed = true
        hideCard()
    end
    card:raise()
    cardShownAt = os.time()
    -- the card says it better than the NEW RATES callout
    if panel() and panel().hidePoint then
        panel().hidePoint('rates')
    end
end

-- ---------------------------------------------------------------- first rare

local function hideRare()
    if raysEvent then
        removeEvent(raysEvent)
        raysEvent = nil
    end
    if rareWindow then
        rareWindow:destroy()
        rareWindow = nil
    end
end

local function showRare(data)
    hideRare()
    local interface = modules.game_interface
    local root = interface and interface.getRootPanel and interface.getRootPanel()
    local info = data.item or {}
    if not root then
        return
    end
    local color = GRADE_COLORS[info.grade] or '#e2a443'
    rareWindow = g_ui.createWidget('JourneyRareWindow', root)
    rareWindow:addAnchor(AnchorHorizontalCenter, 'gameMapPanel', AnchorHorizontalCenter)
    rareWindow:addAnchor(AnchorVerticalCenter, 'gameMapPanel', AnchorVerticalCenter)
    rareWindow.rays:setImageColor(color)
    rareWindow.frame:setBorderColor(color)
    local item = Item.create(tonumber(info.id) or 0, 1)
    if info.shader and info.shader ~= '' then
        item:setShader(info.shader)
    end
    rareWindow.frame.item:setItem(item)
    local box = rareWindow.box
    box.title:setText(tr('RARE ITEM!'))
    -- the name already says the grade; its colour too
    box.name:setText((info.name or ''):gsub('(%a)([%w\']*)', function(a, b) return a:upper() .. b end))
    box.name:setColor(color)
    box.text:setText(tr('Wear it and spin the Roulette.'))
    box.spinButton:setText(tr('SPIN'))
    box.spinButton.onClick = function()
        hideRare()
        if modules.game_raritybonus and modules.game_raritybonus.request then
            modules.game_raritybonus.request()
        end
    end
    box.laterButton:setText(tr('Later'))
    box.laterButton.onClick = hideRare
    box.closeButton.onClick = hideRare
    rareWindow:raise()
    rareWindow:focus()
    -- the rays breathe
    local started = g_clock.millis()
    local function tick()
        raysEvent = nil
        if not rareWindow or rareWindow:isDestroyed() then
            return
        end
        local t = (g_clock.millis() - started) / 1400
        rareWindow.rays:setOpacity(0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * math.pi * 2)))
        raysEvent = scheduleEvent(tick, 40)
    end
    tick()
end

-- ---------------------------------------------------------------- triggers

-- the hunts teleport of a temple: its name says hunts
local function nearHuntsPortal(pos)
    local labels = modules.game_tplabels and modules.game_tplabels.getLabels and modules.game_tplabels.getLabels()
    for _, label in ipairs(labels or {}) do
        local p = label.pos
        if p and p.z == pos.z and math.abs(p.x - pos.x) <= PORTAL_RANGE and math.abs(p.y - pos.y) <= PORTAL_RANGE
            and tostring(label.text or ''):lower():find('hunt', 1, true) then
            return true
        end
    end
    return false
end

local function onPositionChange(creature, newPos)
    if not creature:isLocalPlayer() then
        return
    end
    lastMoveAt = os.time()
    -- the card already says it
    if portalHinted or card or isHidden() or not journey or (journey.steps or {}).hunt or not newPos then
        return
    end
    if nearHuntsPortal(newPos) and panel() and panel().point then
        portalHinted = true
        hintShown = true
        panel().point('rates', tr('SHORTCUT'), tr('Any hunt from here, no walking.'), nil, function()
            hintShown = false
        end)
    end
end

-- every few seconds: a player standing still in a protection zone, journey
-- not done, gets the card again (not too often)
local function check()
    checkEvent = scheduleEvent(check, 5000)
    local player = g_game.getLocalPlayer()
    if not player or not journey or allDone() or card or rareWindow or cardDismissed or isHidden() then
        return
    end
    if os.time() - lastMoveAt < IDLE_SECONDS or os.time() - cardShownAt < CARD_COOLDOWN then
        return
    end
    if player:hasState(PlayerStates.Pz) then
        send({ action = 'card' })
        cardShownAt = os.time()
    end
end

-- ---------------------------------------------------------------- server

local handlers = {}

function handlers.state(data)
    local first = journey == nil
    journey = data
    updateBar()
    if hintShown and (data.steps or {}).hunt and panel() and panel().hidePoint then
        hintShown = false
        panel().hidePoint('rates')
    end
    showWindow()
    if window and window:isVisible() then
        fillWindow()
    end
    -- the card once a login, for the player who has not gone hunting yet or
    -- has not seen it today
    if first and data.hunt and not isHidden() then
        local today = os.date('%Y-%m-%d')
        local key = 'journey_card_' .. (g_game.getCharacterName() or '')
        if not (data.steps or {}).hunt or g_settings.getString(key) ~= today then
            g_settings.set(key, today)
            firstStateEvent = scheduleEvent(function()
                firstStateEvent = nil
                showCard(data.hunt)
            end, 2500)
        end
    end
end

function handlers.card(data)
    if data.hunt then
        showCard(data.hunt)
    end
end

function handlers.spins(data)
    if not journey then
        return
    end
    journey.spins = data.spins or {}
    updateBar()
    if window and window:isVisible() then
        fillWindow()
    end
end

function handlers.firstRare(data)
    showRare(data)
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    local handler = handlers[data.action]
    if handler then
        handler(data)
    end
end

-- game_hunttasks tells the task and its kills
function onTaskState(state)
    taskState = state
    if window and window:isVisible() and journey then
        fillWindow()
    end
end

-- the hunt card is on screen (game_huntboard holds its NEW RATES callout)
function isShowingCard()
    return card ~= nil
end

-- the tour points at the journey window
function getWindow()
    return window
end

-- the "?" of the bar: the journey again, for a player who closed it
function reopen()
    g_settings.set(hiddenKey(), false)
    if journey then
        showWindow()
        updateBar()
    end
end

-- called by the tour when it ends: the card it held back
function onTourEnd()
    if journey and journey.hunt and not card and not (journey.steps or {}).hunt then
        showCard(journey.hunt)
    end
end

local function onGameStart()
    journey = nil
    cardDismissed = false
    portalHinted = false
    cardShownAt = os.time()
    lastMoveAt = os.time()
    if modules.game_hunttasks and modules.game_hunttasks.getState then
        taskState = modules.game_hunttasks.getState()
    end
    scheduleEvent(function()
        send({ action = 'state' })
    end, 800)
    if not checkEvent then
        checkEvent = scheduleEvent(check, 5000)
    end
end

local function onGameEnd()
    if checkEvent then
        removeEvent(checkEvent)
        checkEvent = nil
    end
    if firstStateEvent then
        removeEvent(firstStateEvent)
        firstStateEvent = nil
    end
    hideCard()
    hideRare()
    if window then
        window:destroy()
        window = nil
    end
    journey = nil
end

function init()
    g_ui.importStyle('journey')
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(LocalPlayer, { onPositionChange = onPositionChange })
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(LocalPlayer, { onPositionChange = onPositionChange })
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
    onGameEnd()
end
