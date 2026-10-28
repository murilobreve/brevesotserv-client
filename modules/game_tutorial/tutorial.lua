-- Mythos tour: on the first login the screen goes dark around the real
-- button of each step, a gold ring breathes around it and a bubble says what
-- it does. Using the button itself (or Next) goes on: the player learns
-- where it is by using it. Five steps: the Mythos bar, Teleports, the task's
-- Go hunt, the Roulette and the Hunter's Journey (game_journey), which shows
-- its hunt card when the tour ends. The small "?" next to the Mythos panel's
-- title starts it again; Esc or "Skip the tour" ends it.

local TICK_MS = 50
local TELEPORT_SQM = 6 -- a step whose button teleports: this far counts as used
local RING_GAP = 3 -- px between the target and the ring
local ARROW_GAP = 10 -- px between the ring and the bubble

local bubble, ring, arrow
local shades = {}
local dots = {}
local index = 0
local steps -- the steps whose target is on screen now
local target -- the widget the current step points at
local tickEvent, startEvent, startedAt
local paused -- the window the step's button opened: the tour waits for it
local stepTop, stepPos, stepReady -- the top window, the player's place and the
-- task teleport's ready time when the step began

local function mod(name)
    return modules[name]
end

local function bar()
    return mod('game_brevespanel')
end

local function featureButton(id)
    local panel = bar()
    return panel and panel.getFeatureButton and panel.getFeatureButton(id)
end

local function visible(widget)
    return widget and not widget:isDestroyed() and widget:isVisible() and widget:getWidth() > 0 and widget:getHeight() > 0
end

local function showPanel()
    local panel = rootWidget:recursiveGetChildById('brevespanel')
    if panel and not panel:isVisible() and bar() and bar().togglePanel then
        bar().togglePanel()
    end
end

-- each step finds its widget when it starts (nil: the step is left out)
local STEPS = {
    { title = 'The Mythos bar',
      text = 'Everything Mythos has is here.',
      target = function()
          return bar() and bar().getPanel and bar().getPanel()
      end },
    { title = 'Teleports',
      text = 'Every hunt, with a free TP. Click it.',
      opens = true,
      target = function()
          return featureButton('rates')
      end },
    { title = 'Go hunt',
      text = 'Free teleport to your task monster.',
      teleports = true,
      target = function()
          for _, id in ipairs({ 'tasks', 'trail' }) do
              local button = featureButton(id)
              if button and visible(button.action) then
                  return button.action
              end
          end
          return featureButton('tasks') or featureButton('trail')
      end },
    { title = 'The Roulette',
      text = 'New bonuses for your rare items. First spin free.',
      opens = true,
      target = function()
          return featureButton('bonus')
      end },
    { title = "Hunter's Journey",
      text = 'Three steps, one reward. Good hunting!',
      -- the window may come after the tour starts (it waits for the server)
      late = true,
      target = function()
          return mod('game_journey') and mod('game_journey').getWindow and mod('game_journey').getWindow()
      end },
}

-- ---------------------------------------------------------------- drawing

local function destroyAll()
    target = nil
    paused = nil
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    for _, widget in ipairs(shades) do
        widget:destroy()
    end
    shades = {}
    dots = {}
    for _, widget in ipairs({ bubble, ring, arrow }) do
        if widget then
            widget:destroy()
        end
    end
    bubble, ring, arrow = nil, nil, nil
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function ours(widget)
    if widget == bubble or widget == ring or widget == arrow then
        return true
    end
    for _, shade in ipairs(shades) do
        if widget == shade then
            return true
        end
    end
    return false
end

-- the top window on screen that is not the tour's (a tooltip or a notice
-- is not a window)
local function topWindow()
    local children = rootWidget:getChildren()
    for i = #children, 1, -1 do
        local child = children[i]
        if child:isVisible() and not child:isPhantom() and not ours(child) and child:getWidth() >= 200 and child:getHeight() >= 150 then
            return child
        end
    end
    return nil
end

local function playerPos()
    local player = g_game.getLocalPlayer()
    return player and player:getPosition()
end

local function teleportReadyAt()
    local tasks = mod('game_hunttasks')
    return tasks and tasks.getTeleportReadyAt and tasks.getTeleportReadyAt() or 0
end

-- the task teleport was used: the player moved far, or its wait started
-- (the player may have stood at that hunt already)
local function teleported()
    local pos = playerPos()
    if pos and stepPos and (pos.z ~= stepPos.z or math.max(math.abs(pos.x - stepPos.x), math.abs(pos.y - stepPos.y)) >= TELEPORT_SQM) then
        return true
    end
    local now = os.time()
    return stepReady <= now and teleportReadyAt() > now + 5
end

local function showTour(on)
    for _, widget in ipairs(shades) do
        widget:setVisible(on)
    end
    bubble:setVisible(on)
    ring:setVisible(on)
    arrow:setVisible(on)
end

-- the dark pieces around the hole, the ring and the bubble beside it
local function place()
    if not bubble then
        return
    end
    local screen = rootWidget:getRect()
    local rect = visible(target) and target:getRect() or nil
    if not rect then
        -- no hole: all dark, the bubble in the middle
        shades[1]:setRect(screen)
        for i = 2, 4 do
            shades[i]:setRect({ x = 0, y = 0, width = 0, height = 0 })
        end
        ring:hide()
        arrow:hide()
        bubble:setPosition({ x = math.floor((screen.width - bubble:getWidth()) / 2), y = math.floor((screen.height - bubble:getHeight()) / 2) })
        return
    end
    local hole = {
        x = rect.x - RING_GAP, y = rect.y - RING_GAP,
        width = rect.width + RING_GAP * 2, height = rect.height + RING_GAP * 2,
    }
    local right = hole.x + hole.width
    local bottom = hole.y + hole.height
    shades[1]:setRect({ x = 0, y = 0, width = screen.width, height = math.max(0, hole.y) })
    shades[2]:setRect({ x = 0, y = bottom, width = screen.width, height = math.max(0, screen.height - bottom) })
    shades[3]:setRect({ x = 0, y = hole.y, width = math.max(0, hole.x), height = hole.height })
    shades[4]:setRect({ x = right, y = hole.y, width = math.max(0, screen.width - right), height = hole.height })
    ring:show()
    ring:setRect(hole)

    -- the bubble above the hole when it fits, else below it
    local width, height = bubble:getWidth(), bubble:getHeight()
    local centerX = hole.x + math.floor(hole.width / 2)
    local x = clamp(centerX - math.floor(width / 2), 8, screen.width - width - 8)
    local y
    arrow:show()
    if hole.y - ARROW_GAP - height >= 4 then
        y = hole.y - ARROW_GAP - height
        arrow:setImageSource('/game_tutorial/images/arrow_down')
        arrow:setPosition({ x = clamp(centerX - 10, x + 6, x + width - 26), y = y + height - 2 })
    else
        y = math.min(bottom + ARROW_GAP, screen.height - height - 4)
        arrow:setImageSource('/game_tutorial/images/arrow_up')
        arrow:setPosition({ x = clamp(centerX - 10, x + 6, x + width - 26), y = y - 9 })
    end
    -- a hole as tall as the screen (the journey window): the bubble beside it
    if y < 4 or (y < bottom and y + height > hole.y) then
        arrow:hide()
        y = clamp(hole.y + 20, 4, screen.height - height - 4)
        x = right + ARROW_GAP
        if x + width > screen.width - 4 then
            x = hole.x - ARROW_GAP - width
        end
    end
    bubble:setPosition({ x = x, y = y })
end

-- the ring breathes and everything follows the target (windows move)
local render

local function tick()
    tickEvent = nil
    if not bubble then
        return
    end
    tickEvent = scheduleEvent(tick, TICK_MS)
    -- the window a step's button opened: back once it is closed
    if paused then
        if paused:isDestroyed() or not paused:isVisible() then
            paused = nil
            showTour(true)
            render()
        end
        return
    end
    -- the step's button was used: a window it opened (the tour steps aside
    -- until it is closed) or a teleport
    local step = steps[index]
    if step.opens then
        local top = topWindow()
        if top and top ~= stepTop then
            if index >= #steps then
                stop()
                return
            end
            index = index + 1
            paused = top
            showTour(false)
            return
        end
    elseif step.teleports and teleported() then
        next()
        return
    end
    -- above any window opened meanwhile
    if rootWidget:getLastChild() ~= arrow then
        ring:raise()
        bubble:raise()
        arrow:raise()
    end
    place()
    local t = (g_clock.millis() - startedAt) / 1400
    ring:setOpacity(0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * math.pi * 2)))
end

function render()
    local step = steps[index]
    target = step.target()
    if not visible(target) then
        target = nil
    end
    bubble.title:setText(tr(step.title))
    bubble.text:setText(tr(step.text))
    bubble.counter:setText(tr('%d of %d', index, #steps))
    bubble.nextButton:setText(index == #steps and tr('Finish') or tr('Next'))
    for i, dot in ipairs(dots) do
        dot:setOn(i <= index)
    end
    -- what the step's button changes, to see it used
    stepTop = topWindow()
    stepPos = playerPos()
    stepReady = teleportReadyAt()
    -- once the text is laid out: the bubble fits it
    scheduleEvent(function()
        if not bubble then
            return
        end
        local height = bubble.text:getY() + bubble.text:getHeight()
        bubble:setHeight(height - bubble:getY() + 12 + 28 + 10)
        place()
        bubble:raise()
        arrow:raise()
        bubble:focus()
    end, 30)
    place()
    bubble:raise()
    arrow:raise()
    bubble:focus()
end

-- ---------------------------------------------------------------- the tour

function isRunning()
    return bubble ~= nil
end

function start()
    if not g_game.isOnline() then
        return
    end
    destroyAll()
    if bar() and bar().hideNews then
        bar().hideNews()
    end
    if bar() and bar().hidePoint then
        bar().hidePoint()
    end
    showPanel()
    steps = {}
    for _, step in ipairs(STEPS) do
        if step.late or visible(step.target()) then
            table.insert(steps, step)
        end
    end
    if #steps == 0 then
        return
    end
    for i = 1, 4 do
        shades[i] = g_ui.createWidget('MythosTourShade', rootWidget)
    end
    ring = g_ui.createWidget('MythosTourRing', rootWidget)
    bubble = g_ui.createWidget('MythosTourBubble', rootWidget)
    arrow = g_ui.createWidget('MythosTourArrow', rootWidget)
    bubble.dots:setWidth(#steps * 11)
    for i = 1, #steps do
        dots[i] = g_ui.createWidget('MythosTourDot', bubble.dots)
    end
    startedAt = g_clock.millis()
    index = 1
    render()
    tick()
end

function stop()
    local wasRunning = bubble ~= nil
    destroyAll()
    g_settings.set('mythos_tutorial_done', true)
    g_settings.save()
    if wasRunning and mod('game_journey') and mod('game_journey').onTourEnd then
        mod('game_journey').onTourEnd()
    end
end

function next()
    if not bubble then
        return
    end
    if index >= #steps then
        stop()
        return
    end
    index = index + 1
    render()
end

local function onGameStart()
    if not g_settings.getBoolean('mythos_tutorial_done') then
        -- after the panel rows and the journey window had their turn
        startEvent = scheduleEvent(function()
            startEvent = nil
            start()
        end, 2500)
    end
end

local function onGameEnd()
    if startEvent then
        removeEvent(startEvent)
        startEvent = nil
    end
    destroyAll()
end

function init()
    g_ui.importStyle('tutorial')
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    onGameEnd()
end
