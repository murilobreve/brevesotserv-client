-- Mythos tour: on the first login a small window walks the player through
-- the server's own systems, one short step at a time. Each step opens the
-- window it talks about (and closes it again on the next step), so the
-- player sees the real thing instead of reading about it. The small "?" next
-- to the Mythos panel's title starts it again; Esc or "Skip" ends it.

local window
local index = 0
local closeCurrent

local function mod(name)
    return modules[name]
end

-- hide + open, so a toggle never closes a window the player already had open
local function section(name, tab)
    return function()
        local m = mod(name)
        if m and m.hide and m.openSection then
            m.hide()
            m.openSection(tab)
        end
    end, function()
        local m = mod(name)
        if m and m.hide then
            m.hide()
        end
    end
end

-- section() and plain() return the step's open and close functions
local function plain(name, openFn, closeFn)
    return function()
        local m = mod(name)
        if m and m[openFn] then
            m[openFn]()
        end
    end, function()
        local m = mod(name)
        if m and m[closeFn] then
            m[closeFn]()
        end
    end
end

local function showPanel()
    local panel = rootWidget:recursiveGetChildById('brevespanel')
    if panel and not panel:isVisible() and mod('game_brevespanel') then
        mod('game_brevespanel').togglePanel()
    end
end

local STEPS = {
    { title = 'Welcome to Mythos',
      text = 'This quick tour shows what is different here. Each step opens the window it talks about. Use Next and Back, or Esc to leave.' },
    { title = 'The Mythos panel',
      text = 'Everything Mythos has is in this bar under the game screen, above your spells, in four sections: Tasks, Hunts, Rarity and Tools, with your VIP on the right. Click a button to open it.',
      open = showPanel },
    { title = 'Hunts TP',
      text = 'Every hunt is in this list, with the XP and loot rate of each monster: new rates every 2 hours, and a high rate makes the monster stronger, but it pays much more. The TP button takes you to the hunt, every 30 seconds.',
      window = { section('game_huntboard', 'rates') } },
    { title = 'Ranking',
      text = 'All XP you make counts for the hour, the day and the month. First place wins Mythos Coins: 25 an hour, 250 a day and 5,000 a month.',
      window = { section('game_huntboard', 'board') } },
    { title = 'Daily Task and the Trail',
      text = 'A monster of your level every day, and a trail of 70 monsters from the weakest to the strongest. Both pay XP and Hunt Points. Go to the hunt takes you straight there, free, out of combat.',
      window = { section('game_hunttasks', 'tasks') } },
    { title = 'Rare items and the Roulette',
      text = 'Any monster can drop equipment with rarity, from Communis to Mythicus, with extra bonuses. Here you see every bonus you wear, and you can roll an item again with Rarity XP.',
      window = { plain('game_raritybonus', 'request', 'hide') } },
    { title = 'Rarity Market',
      text = 'Sell the rare items you do not use and buy the ones you want, paid with the gold in your bank.',
      window = { plain('game_raritymarket', 'show', 'hide') } },
    { title = 'Auto Loot',
      text = 'Choose what the loot picks up for you, without opening corpses: your recent drops and a search by name.',
      window = { function()
          local q = mod('game_quickloot')
          if q and q.QuickLoot and q.QuickLoot.show then q.QuickLoot.show() end
      end, function()
          local q = mod('game_quickloot')
          if q and q.QuickLoot and q.QuickLoot.hide then q.QuickLoot.hide() end
      end } },
    { title = 'Heal Bot',
      text = 'Heals you with spells and potions, heals your friends and keeps your buffs up. You choose the rules, and it is allowed here.',
      window = { plain('game_healbot', 'show', 'hide') } },
    { title = 'Store and Mythos VIP',
      text = 'Mythos Coins come from playing, from the ranking and from donations. VIP gives +10%% XP, loot and training and the Fusca, Uno and Gol mounts.',
      window = { function()
          local s = mod('game_store')
          if s and s.openCategory then s.openCategory('Mythos VIP') end
      end, function()
          local s = mod('game_store')
          if s and s.hide then s.hide() end
      end } },
    { title = 'Questions? The Wiki',
      text = 'Rare monsters, every rarity bonus and the real numbers of the server are in the Wiki. Useful commands: !hunt, !task, !vip and !bless. To see this tour again, click the small ? next to the Mythos title. Good hunting!',
      window = { plain('game_wiki', 'show', 'hide') } },
}

local function closeStepWindow()
    if closeCurrent then
        pcall(closeCurrent)
        closeCurrent = nil
    end
end

local function place()
    local map = modules.game_interface and modules.game_interface.getMapPanel()
    if map then
        -- MainWindow centres itself through its anchors
        window:breakAnchors()
        window:setPosition({ x = map:getX() + math.floor((map:getWidth() - window:getWidth()) / 2), y = map:getY() + 10 })
    end
end

local function render()
    local step = STEPS[index]
    window.title:setText(tr(step.title))
    window.text:setText(tr(step.text))
    window.counter:setText(tr('%d of %d', index, #STEPS))
    window.backButton:setEnabled(index > 1)
    window.nextButton:setText(index == #STEPS and tr('Finish') or tr('Next'))
    closeStepWindow()
    if step.open then
        pcall(step.open)
    end
    if step.window then
        pcall(step.window[1])
        closeCurrent = step.window[2]
    end
    -- once the text is laid out: the window fits it, keeps its place at
    -- the top of the game screen and stays above the window it just opened
    scheduleEvent(function()
        if window then
            window:setHeight(math.max(170, window.text:getY() - window:getY() + window.text:getHeight() + 62))
            window.progress:setWidth(math.max(4, math.floor(window.progressBack:getWidth() * index / #STEPS)))
            place()
            window:raise()
        end
    end, 60)
    scheduleEvent(function()
        if window then
            window:raise()
        end
    end, 400)
end

function start()
    if not g_game.isOnline() then
        return
    end
    if not window then
        window = g_ui.createWidget('MythosTutorialWindow', rootWidget)
    end
    if mod('game_brevespanel') and mod('game_brevespanel').hideNews then
        mod('game_brevespanel').hideNews()
    end
    index = 1
    window:show()
    place()
    render()
end

function stop()
    closeStepWindow()
    if window then
        window:destroy()
        window = nil
    end
    g_settings.set('mythos_tutorial_done', true)
    g_settings.save()
end

function next()
    if not window then
        return
    end
    if index >= #STEPS then
        stop()
        return
    end
    index = index + 1
    render()
end

function back()
    if window and index > 1 then
        index = index - 1
        render()
    end
end

local startEvent

local function onGameStart()
    if not g_settings.getBoolean('mythos_tutorial_done') then
        -- after the panel rows and the news window had their turn
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
    closeStepWindow()
    if window then
        window:destroy()
        window = nil
    end
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
