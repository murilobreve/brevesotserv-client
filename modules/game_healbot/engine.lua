-- Decides what to use each tick. Cooldowns come from the server the same way
-- the action bar gets them (onSpellCooldown, onSpellGroupCooldown,
-- onMultiUseCooldown), so the bot waits exactly as long as the server wants
-- and never spams words that would only answer "You are exhausted".

HealEngine = {}

local TICK = 100
local POTION_FALLBACK = 1000
-- the server kicks after 15 idle minutes (kickIdlePlayerAfterMinutes), and a
-- turn resets that timer, the same as a player tapping ctrl+arrow
local ANTI_IDLE_EVERY = 5 * 60 * 1000
-- the server says "You are full." when the regeneration time and the food's
-- would reach 1200 s (data/scripts/actions/items/foods.lua)
local FULL = 1200
local FULL_MARGIN = 2 -- s: the time counted down here runs a little behind the server's
local MEAL_WAIT = 1500 -- ms: the most it waits for the server's answer to a meal
local MEAL_CHECK = 500 -- ms between looks into the backpacks while not eating
local FULL_PAUSE = 30 * 1000
local FULL_MESSAGE = 'You are full.'

local tickEvent
local running = false
local getConfig, onAction
local spellUntil, groupUntil, potionUntil = {}, {}, 0
local unlearned, lastCast = {}, nil
local lastTurn = 0
-- the regeneration time the server sent (s) and when; it counts down here
local regen, regenAt = 0, 0
local filling, ateAt, fullUntil, mealCheckAt = false, nil, 0, 0
local NOT_LEARNED = 'You need to learn this spell first.'

local function now()
    return g_clock.millis()
end

local function percent(value, max)
    if not max or max <= 0 then
        return 100
    end
    return value * 100 / max
end

local function hasState(player, state)
    return state and bit.band(player:getStates(), state) ~= 0
end

local function onSpellCooldown(spellId, delay)
    spellUntil[spellId] = now() + delay
end

local function onSpellGroupCooldown(groupId, delay)
    groupUntil[groupId] = now() + delay
end

-- the client has no list of learned spells, so stop trying a spell the
-- server refused instead of repeating the same error every second
local function onTextMessage(_, text)
    if text == FULL_MESSAGE and ateAt and now() - ateAt < MEAL_WAIT then
        filling, ateAt, fullUntil = false, nil, now() + FULL_PAUSE
        return
    end
    if text == NOT_LEARNED and lastCast and now() - lastCast.time < 1500 then
        unlearned[lastCast.spell.id] = true
        if onAction then
            onAction(tr('You have not learned %s.', lastCast.spell.words))
        end
        lastCast = nil
    end
end

-- the server sends it again after every meal (the food leaves the backpack)
local function onRegenerationChange(_, seconds)
    regen, regenAt = seconds, now()
    ateAt = nil
end

local function onMultiUseCooldown(delay)
    potionUntil = now() + (delay or POTION_FALLBACK)
end

local function spellReady(player, spell, t)
    if not spell or unlearned[spell.id] or player:getLevel() < spell.level or player:getMana() < spell.mana then
        return false
    end
    if (spellUntil[spell.id] or 0) > t then
        return false
    end
    for group in pairs(spell.group) do
        if (groupUntil[group] or 0) > t then
            return false
        end
    end
    return true
end

local function cast(spell, t, target)
    local words = target and string.format('%s "%s"', spell.words, target) or spell.words
    g_game.talk(words)
    -- until the server answers with the real cooldown
    spellUntil[spell.id] = t + (spell.exhaustion or 1000)
    for group, delay in pairs(spell.group) do
        groupUntil[group] = math.max(groupUntil[group] or 0, t + delay)
    end
    lastCast = { spell = spell, time = t }
    if onAction then
        onAction(tr('Used %s', words))
    end
end

local function itemCount(player, id)
    -- the server keeps this list for the action bar; open backpacks as fallback
    local count = player:getInventoryCount(id, 0)
    if count == 0 then
        count = player:getItemsCount(id)
    end
    return count
end

local function potionReady(player, potion, t)
    return potion and potionUntil <= t and player:getLevel() >= (potion.level or 0) and itemCount(player, potion.id) > 0
end

local function drink(player, potion, t)
    g_game.useInventoryItemWith(potion.id, player)
    potionUntil = t + POTION_FALLBACK
    if onAction then
        onAction(tr('Used %s', potion.name))
    end
    return true
end

local function isPartyMember(creature)
    local shield = creature:getShield()
    return shield >= ShieldBlue and shield <= ShieldYellowNoSharedExp
end

-- the whole party, anyone, or the one character the rule names
local function isTarget(rule, creature)
    local target = rule.target or HealData.FRIEND_PARTY
    if target == HealData.FRIEND_ANYONE then
        return true
    elseif target == HealData.FRIEND_PARTY then
        return isPartyMember(creature)
    end
    return creature:getName():lower() == target:lower()
end

local function woundedFriend(player, rule)
    local pos = player:getPosition()
    local best
    for _, creature in ipairs(g_map.getSpectators(pos, false)) do
        if creature:isPlayer() and not creature:isLocalPlayer() then
            local cpos = creature:getPosition()
            local hp = creature:getHealthPercent()
            if math.abs(cpos.x - pos.x) <= 7 and math.abs(cpos.y - pos.y) <= 5 and hp > 0 and hp < rule.below
                and isTarget(rule, creature) and (not best or hp < best:getHealthPercent()) then
                best = creature
            end
        end
    end
    return best
end

-- one spell per tick: own health first, then friends, then support
local function pickSpell(player, cfg, hp, mp, t)
    for _, rule in ipairs(cfg.spells) do
        local spell = rule.on and HealData.spell(rule.spell)
        if spell and (rule.stat == 'mp' and mp or hp) < rule.below and spellReady(player, spell, t) then
            return cast(spell, t)
        end
    end

    for _, rule in ipairs(cfg.friends) do
        local spell = rule.on and HealData.spell(rule.spell)
        if spell and spellReady(player, spell, t) then
            local friend = woundedFriend(player, rule)
            if friend then
                return cast(spell, t, friend:getName())
            end
        end
    end

    local support = cfg.support
    if support.cures then
        for _, cure in ipairs(HealData.curesFor(HealData.vocation(player))) do
            if hasState(player, cure.state) and spellReady(player, cure.spell, t) then
                return cast(cure.spell, t)
            end
        end
    end

    local train = support.train
    local trainSpell = train.on and HealData.spell(train.spell)
    local function training()
        if trainSpell and mp >= train.below and spellReady(player, trainSpell, t) then
            return cast(trainSpell, t)
        end
    end

    -- training (utana vid in the temple) goes on in a protection zone too
    if hasState(player, PlayerStates.Pz) then
        return training()
    end

    local haste = support.haste.on and HealData.spell(support.haste.spell)
    if haste and (not hasState(player, PlayerStates.Haste) or hasState(player, PlayerStates.Paralyze))
        and spellReady(player, haste, t) then
        return cast(haste, t)
    end

    local shield = support.shield.on and HealData.spell(support.shield.spell)
    if shield and not hasState(player, PlayerStates.ManaShield) and not hasState(player, PlayerStates.NewManaShield)
        and spellReady(player, shield, t) then
        return cast(shield, t)
    end

    -- last: only mana nobody else needs goes to training
    return training()
end

local function pickPotion(player, cfg, hp, mp, t)
    for _, rule in ipairs(cfg.potions) do
        local potion = rule.on and HealData.potion(rule.item)
        if potion and (rule.stat == 'mp' and mp or hp) < rule.below and potionReady(player, potion, t) then
            return drink(player, potion, t)
        end
    end
end

-- the biggest food in the backpacks worth less than `room` seconds
local function pickFood(player, room)
    local best
    for id, food in pairs(HealData.foods) do
        if food[1] < room and (not best or food[1] > best.seconds) and itemCount(player, id) > 0 then
            best = { id = id, seconds = food[1], name = food[2] }
        end
    end
    return best
end

-- eats as soon as its biggest food fits, then whatever still fits until
-- full: one meal at a time, each after the server answered the last
local function feed(player, t)
    if ateAt and t - ateAt < MEAL_WAIT or fullUntil > t or mealCheckAt > t then
        return
    end
    ateAt = nil
    mealCheckAt = filling and 0 or t + MEAL_CHECK
    local room = FULL - FULL_MARGIN - math.max(0, regen - (t - regenAt) / 1000)
    local food = pickFood(player, room)
    if not food then
        filling = false
        return
    end
    if not filling then
        if pickFood(player, FULL).seconds > food.seconds then
            return
        end
        filling = true
    end
    g_game.useInventoryItem(food.id)
    ateAt, mealCheckAt = t, 0
    if onAction then
        onAction(tr('Used %s', food.name))
    end
end

local function antiIdle(player, t)
    if t - lastTurn < ANTI_IDLE_EVERY or player:isWalking() then
        return
    end
    lastTurn = t
    local facing = player:getDirection()
    g_game.turn((facing + 1) % 4)
    scheduleEvent(function()
        if g_game.isOnline() then
            g_game.turn(facing)
        end
    end, 400)
end

local function tick()
    if not g_game.isOnline() then
        return
    end
    local cfg = getConfig()
    local player = g_game.getLocalPlayer()
    if not cfg or not player or player:getHealth() <= 0 then
        return
    end
    local t = now()
    -- ticked, it keeps the character online with the bot itself off too
    if cfg.support.antiIdle then
        antiIdle(player, t)
    end
    if not running then
        return
    end
    local hp = percent(player:getHealth(), player:getMaxHealth())
    local mp = percent(player:getMana(), player:getMaxMana())
    -- spells and potions are separate exhausts in Tibia, so both can go off
    pickSpell(player, cfg, hp, mp, t)
    local drank = pickPotion(player, cfg, hp, mp, t)
    -- a meal waits for a tick with no potion
    if cfg.support.food and not drank then
        feed(player, t)
    end
end

function HealEngine.potionCount(id)
    local player = g_game.getLocalPlayer()
    return player and itemCount(player, id) or 0
end

function HealEngine.setRunning(value)
    running = value and true or false
end

function HealEngine.isRunning()
    return running
end

function HealEngine.reset()
    spellUntil, groupUntil, potionUntil = {}, {}, 0
    unlearned, lastCast = {}, nil
    lastTurn = now()
    local player = g_game.getLocalPlayer()
    regen, regenAt = player and player:getRegenerationTime() or 0, now()
    filling, ateAt, fullUntil, mealCheckAt = false, nil, 0, 0
end

function HealEngine.forget(spellId)
    unlearned[spellId] = nil
end

function HealEngine.init(configGetter, actionCallback)
    getConfig, onAction = configGetter, actionCallback
    connect(g_game, {
        onSpellCooldown = onSpellCooldown,
        onSpellGroupCooldown = onSpellGroupCooldown,
        onMultiUseCooldown = onMultiUseCooldown,
        onTextMessage = onTextMessage,
    })
    connect(LocalPlayer, { onRegenerationChange = onRegenerationChange })
    tickEvent = cycleEvent(tick, TICK)
end

function HealEngine.terminate()
    disconnect(g_game, {
        onSpellCooldown = onSpellCooldown,
        onSpellGroupCooldown = onSpellGroupCooldown,
        onMultiUseCooldown = onMultiUseCooldown,
        onTextMessage = onTextMessage,
    })
    disconnect(LocalPlayer, { onRegenerationChange = onRegenerationChange })
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    running = false
end
