-- Raizes Errantes: the designer's art (images/raizes, from "Raizes Errantes
-- - artes v1"). The server sends each moment of a cast (scripts/skillshot/
-- druid.lua, fx "seed"):
--   fly   the seed moves one sqm (a still frame per step)
--   hit   the burst, the roots on the creature (in, held, letting go, `ms`
--         in all) and the poison on it once a second for 5 s
--   miss  the seed falls and sprouts at the end of its way

local SEED_FORGET_MS = 1500
local ROOT_IN_MS = 300
local ROOT_OUT_MS = 300
local POISON_TICKS = 5

-- anchors: the centre of the sqm; the roots and the miss on the ground
local art = newArtSet(3900, '/game_skillshot/images/raizes/', 'Raizes')
for frame = 1, 4 do
    art.add('semente_' .. frame, 32, 0, 0)
end
art.add('acerto', 64, 16, 16, 300)
art.add('entrada', 64, 16, 16, ROOT_IN_MS)
art.add('preso', 64, 16, 16)
art.add('soltando', 64, 16, 16, ROOT_OUT_MS)
art.add('veneno', 32, 0, 0, 400)
art.add('erro', 32, 0, -2, 350)

local seeds = {} -- cast id -> { head, arrive, forget }
local pending = {}

local function later(delay, callback)
    local event
    event = scheduleEvent(function()
        pending[event] = nil
        callback()
    end, math.max(0, delay))
    pending[event] = true
end

function registerSeedArt()
    art.register()
end

local function forget(id)
    local seed = seeds[id]
    if not seed then
        return
    end
    seeds[id] = nil
    removeEvent(seed.forget)
    detachArt(seed.head)
end

function clearSeedArt()
    for id in pairs(seeds) do
        forget(id)
    end
    for event in pairs(pending) do
        removeEvent(event)
    end
    pending = {}
end

function unregisterSeedArt()
    clearSeedArt()
    art.unregister()
end

local function seedOf(data)
    local seed = seeds[data.c]
    if not seed then
        seed = { arrive = 0 }
        seeds[data.c] = seed
    end
    removeEvent(seed.forget)
    seed.forget = scheduleEvent(function()
        forget(data.c)
    end, SEED_FORGET_MS)
    return seed
end

local function onArrival(seed, callback)
    local wait = seed.arrive - g_clock.millis()
    if wait > 0 then
        later(wait, callback)
    else
        callback()
    end
end

-- on the creature, if it is still on the screen
local function onCreature(id, name, duration)
    local creature = g_map.getCreatureById(id)
    if creature then
        art.attach(name, creature, duration)
    end
end

local handlers = {}

function handlers.fly(data)
    local seed = seedOf(data)
    local from, to = data.f, data.t
    detachArt(seed.head)
    local frame = ((tonumber(data.i) or 1) - 1) % 4 + 1
    local ms = tonumber(data.ms) or 110
    seed.head = art.place('semente_' .. frame, from)
    if seed.head then
        seed.head.effect:setDuration(ms)
        seed.head.effect:move(from, to)
    end
    seed.arrive = g_clock.millis() + ms
end

function handlers.hit(data)
    local seed = seedOf(data)
    onArrival(seed, function()
        forget(data.c)
        art.burst('acerto', data.p)
        local id = tonumber(data.id)
        if not id then
            return
        end
        local ms = tonumber(data.ms) or 2000
        local held = math.max(0, ms - ROOT_IN_MS - ROOT_OUT_MS)
        onCreature(id, 'entrada', ROOT_IN_MS - 10)
        later(ROOT_IN_MS, function()
            onCreature(id, 'preso', held)
        end)
        later(ROOT_IN_MS + held, function()
            onCreature(id, 'soltando', ROOT_OUT_MS - 10)
        end)
        for tick = 1, POISON_TICKS do
            later(tick * 1000, function()
                onCreature(id, 'veneno', 390)
            end)
        end
    end)
end

function handlers.miss(data)
    local seed = seedOf(data)
    onArrival(seed, function()
        forget(data.c)
        art.burst('erro', data.p)
    end)
end

function onSeedArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' then
        handler(data)
    end
end
