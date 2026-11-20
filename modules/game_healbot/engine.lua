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
-- spell id -> until when it is skipped as not learned (the server said so)
local unlearned = {}
-- spells the server has accepted this session (it sent their cooldown):
-- learned for sure, a "learn this spell first" is never about them
local confirmed = {}
-- the bot's own last casts, newest first: { spell, time }
local castLog = {}
local UNLEARNED_RETRY = 2 * 60 * 1000 -- ms: then the spell is tried again
local NOT_LEARNED_WINDOW = 1500 -- ms: how old a cast the server's answer can be about
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
    confirmed[spellId] = true
    unlearned[spellId] = nil
end

local function onSpellGroupCooldown(groupId, delay)
    groupUntil[groupId] = now() + delay
end

-- the client has no list of learned spells, so stop trying a spell the
-- server refused instead of repeating the same error every second. The
-- answer does not say which spell it is about: a spell the player cast by
-- hand (a monk's Spiritual Outburst not learned yet) got the same answer
-- right after the bot healed, and the heal was skipped until its rule was
-- changed. Now only a bot cast of the last moments that the server has not
-- accepted yet can be the one, and only for a while.
local function onTextMessage(_, text)
    local t = now()
    if text == FULL_MESSAGE and ateAt and t - ateAt < MEAL_WAIT then
        filling, ateAt, fullUntil = false, nil, t + FULL_PAUSE
        return
    end
    if text ~= NOT_LEARNED then
        return
    end
    for _, entry in ipairs(castLog) do
        if t - entry.time > NOT_LEARNED_WINDOW then
            break
        end
        if not confirmed[entry.spell.id] then
            unlearned[entry.spell.id] = t + UNLEARNED_RETRY
            if onAction then
                onAction(tr('You have not learned %s.', entry.spell.words))
            end
            castLog = {}
            return
        end
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
    if not spell or (unlearned[spell.id] or 0) > t or player:getLevel() < spell.level or player:getMana() < spell.mana then
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
    table.insert(castLog, 1, { spell = spell, time = t })
    castLog[6] = nil
    if onAction then
        onAction(tr('Used %s', words))
    end
end

local function itemCount(player, id)
    -- the server's list for the action bar, else the equipment and the open
    -- backpacks (LocalPlayer::getInventoryCount looks there itself: the Lua
    -- getItemsCount fallback walked them all again for every food missing,
    -- about 140 times every half second)
    return player:getInventoryCount(id, 0)
end

local function potionReady(player, potion, t)
    return potion and potionUntil <= t and player:getLevel() >= (potion.level or 0) and itemCount(player, potion.id) > 0
end

local function drink(player, potion, t)
    if modules.game_healbot and modules.game_healbot.usingMessage then
        modules.game_healbot.usingMessage(potion.id)
    end
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

-- ---------------------------------------------------------------------------
-- the caster: attack spells and runes on the monster being attacked
-- ---------------------------------------------------------------------------

local RUNE_WAIT = 2000 -- a rune shares the attack spells' 2 s
local ATTACK_GROUP = 1
local AROUND_SELF, AROUND_TARGET, RUNE_RANGE = 3, 2, 7
local runeUntil = 0

local function isWildMonster(creature)
    if not creature or not creature:isMonster() or creature:getHealthPercent() <= 0 then
        return false
    end
    -- never the player's own summon
    return not (creature.getType and CreatureTypeSummonOwn and creature:getType() == CreatureTypeSummonOwn)
end

local function monstersAround(centre, radius)
    local count = 0
    for _, creature in ipairs(g_map.getSpectatorsInRange(centre, false, radius, radius) or {}) do
        if isWildMonster(creature) then
            count = count + 1
        end
    end
    return count
end

-- another player in sight who is not of the party: an area spell could hit him
local function strangerInSight(player)
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), false) or {}) do
        if creature:isPlayer() and not creature:isLocalPlayer() and not isPartyMember(creature) then
            return true
        end
    end
    return false
end

local function distance(a, b)
    return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function castRunes(player, preset, target, here, there, t)
    if runeUntil > t or (groupUntil[ATTACK_GROUP] or 0) > t or distance(here, there) > RUNE_RANGE then
        return false
    end
    local around
    for _, rule in ipairs(preset.runes) do
        local rune = rule.on and HealData.rune(rule.item)
        if rune and player:getLevel() >= rune.level and itemCount(player, rune.id) > 0 then
            around = around or monstersAround(there, AROUND_TARGET)
            if around >= (tonumber(rule.count) or 1) then
                g_game.useInventoryItemWith(rune.id, target)
                runeUntil = t + RUNE_WAIT
                groupUntil[ATTACK_GROUP] = math.max(groupUntil[ATTACK_GROUP] or 0, t + RUNE_WAIT)
                if onAction then
                    onAction(tr('Used %s', rune.name))
                end
                return true
            end
        end
    end
    return false
end

-- an aimed spell of the Ascensão, at the target: said through
-- game_skillshot, which tells the server where it goes; a two-step spell
-- is said again when its moment comes
local aimedUntil = {}
local AIMED_MARGIN = 500

local function castAimed(spell, aim, target, here, there, t)
    local skillshot = modules.game_skillshot
    if not skillshot or not skillshot.castAt or not skillshot.castAt(spell.words, there) then
        return false
    end
    spellUntil[spell.id] = t + (spell.exhaustion or 1000)
    -- a little over the spell's cooldown: said the instant it ends here, the
    -- server (which heard the last cast a moment later) still refused it,
    -- and the second cast then started the spell instead of finishing it
    aimedUntil[spell.id] = t + (aim.cooldown or spell.exhaustion or 1000) + AIMED_MARGIN
    for group, delay in pairs(spell.group) do
        groupUntil[group] = math.max(groupUntil[group] or 0, t + delay)
    end
    table.insert(castLog, 1, { spell = spell, time = t })
    castLog[6] = nil
    if onAction then
        onAction(tr('Used %s', spell.words))
    end
    if aim.recast then
        local targetId = target:getId()
        scheduleEvent(function()
            if not g_game.isOnline() or not running then
                return
            end
            local again = g_map.getCreatureById(targetId)
            local pos = again and again:getPosition()
            skillshot.castAt(spell.words, pos and pos.z == there.z and pos or there)
        end, aim.recast(distance(here, there)))
    end
    return true
end

-- For each way the character can face: how far ahead and how far to the
-- side a tile `dx, dy` away from it lies.
local FACINGS = {
    { dir = Directions.North, ahead = function(dx, dy) return -dy, dx end },
    { dir = Directions.East, ahead = function(dx, dy) return dx, dy end },
    { dir = Directions.South, ahead = function(dx, dy) return dy, dx end },
    { dir = Directions.West, ahead = function(dx, dy) return -dx, dy end },
}
local WAVE_SIGHT = 8 -- the longest beam

local function inWave(shape, ahead, side)
    side = math.abs(side)
    if ahead == 0 then
        return side >= 1 and side <= (shape.beside or 0)
    end
    local half = shape.rows[ahead]
    return half ~= nil and side <= half
end

-- The way to face for a wave to hit the target, and how many monsters it
-- hits then; nil when the target is out of it whichever way (in a diagonal,
-- too far). Of two ways that hit the target, the one with more monsters;
-- the same number, the way the character already faces.
local function waveFacing(shape, player, target, here, there)
    local facing = player:getDirection()
    local monsters, best, bestCount
    for _, way in ipairs(FACINGS) do
        if inWave(shape, way.ahead(there.x - here.x, there.y - here.y)) then
            monsters = monsters or g_map.getSpectatorsInRange(here, false, WAVE_SIGHT, WAVE_SIGHT) or {}
            local count = 0
            for _, creature in ipairs(monsters) do
                local pos = isWildMonster(creature) and creature:getPosition()
                if pos and inWave(shape, way.ahead(pos.x - here.x, pos.y - here.y)) then
                    count = count + 1
                end
            end
            if not best or count > bestCount or (count == bestCount and way.dir == facing) then
                best, bestCount = way.dir, count
            end
        end
    end
    return best, bestCount or 0
end

local function castSpells(player, preset, target, here, there, mp, t)
    local aroundSelf, aroundTarget
    for _, rule in ipairs(preset.spells) do
        local spell = rule.on and HealData.spell(rule.spell)
        local need = tonumber(rule.count) or 1
        if spell and mp >= (tonumber(rule.below) or 0) then
            local aim = HealData.aimed(spell)
            local wave = not aim and HealData.directional(spell)
            if aim then
                aroundTarget = aroundTarget or monstersAround(there, AROUND_TARGET)
                if aroundTarget >= need and distance(here, there) <= (spell.range or 1)
                    and (aimedUntil[spell.id] or 0) <= t and spellReady(player, spell, t)
                    and castAimed(spell, aim, target, here, there, t) then
                    return true
                end
            elseif wave then
                -- a wave, a beam, a sweep: turned to the target first
                if spellReady(player, spell, t) then
                    local dir, count = waveFacing(wave, player, target, here, there)
                    if dir and count >= need then
                        if player:getDirection() ~= dir then
                            g_game.turn(dir)
                        end
                        cast(spell, t)
                        return true
                    end
                end
            else
                local ranged = (spell.range or -1) > 0
                local count
                if ranged then
                    aroundTarget = aroundTarget or monstersAround(there, AROUND_TARGET)
                    count = aroundTarget
                else
                    aroundSelf = aroundSelf or monstersAround(here, AROUND_SELF)
                    count = aroundSelf
                end
                if count >= need and (not ranged or distance(here, there) <= spell.range)
                    and spellReady(player, spell, t) then
                    cast(spell, t)
                    return true
                end
            end
        end
    end
    return false
end

-- The first rule that fits, from the top: enough mana, enough monsters (around
-- the character for a spell cast on itself, around the target for a spell
-- with a range and for a rune, inside the wave for one cast the way the
-- character faces) and its cooldown over. Only with a monster
-- being attacked; with another player in sight it waits, if asked to.
local function pickAttack(player, cfg, mp, t)
    local caster = cfg.caster
    if not caster or not caster.on then
        return false
    end
    local target = g_game.getAttackingCreature()
    if not isWildMonster(target) then
        return false
    end
    local here, there = player:getPosition(), target:getPosition()
    if not here or not there or here.z ~= there.z then
        return false
    end
    if caster.noPlayers and strangerInSight(player) then
        return false
    end
    -- the preset in use: its spells and its runes
    local preset = caster.presets and (caster.presets[tonumber(caster.current) or 1] or caster.presets[1])
    if not preset then
        return false
    end
    if caster.runesFirst then
        return castRunes(player, preset, target, here, there, t) or castSpells(player, preset, target, here, there, mp, t)
    end
    return castSpells(player, preset, target, here, there, mp, t) or castRunes(player, preset, target, here, there, t)
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

    -- the magic shield at `below` percent of health or less (100: always),
    -- and exana vita once the health is back over the other rule's
    local shield = support.shield.on and HealData.spell(support.shield.spell)
    local shielded = hasState(player, PlayerStates.ManaShield) or hasState(player, PlayerStates.NewManaShield)
    local shieldAt = tonumber(support.shield.below) or 100
    if shield and not shielded and hp <= shieldAt and spellReady(player, shield, t) then
        return cast(shield, t)
    end
    local unshield = support.unshield
    if unshield and unshield.on and shielded then
        local offAt = tonumber(unshield.below) or 90
        -- never where the shield rule would put it right back
        if hp >= offAt and (not shield or offAt > shieldAt) then
            local off = HealData.unshieldSpell(HealData.vocation(player))
            if off and spellReady(player, off, t) then
                return cast(off, t)
            end
        end
    end

    -- the caster, once nobody needs healing or a support spell
    if pickAttack(player, cfg, mp, t) then
        return
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
    aimedUntil, runeUntil = {}, 0
    unlearned, confirmed, castLog = {}, {}, {}
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
