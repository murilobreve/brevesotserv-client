-- Raizes Errantes: the designer's art v2 (images/raizes, "Ascensao - artes
-- v2", layers.lua). The server sends each moment of a cast (scripts/
-- skillshot/druid.lua, fx "seed"):
--   fly   the seed goes on a sqm, spinning, `ms` a sqm, little leaves
--         falling behind it
--   hit   when it gets there: a green burst and clods of earth, the map
--         lit; on the creature held (id, for `ms`) the roots grow and
--         close, hold it pulsing and let go at its end; the poison's
--         bubbles on it once a second for 5 s
--   miss  it falls at the end of its way and sprouts
-- The preview flies from (-4, 0) and hits at (2, 0), holding 2.5 s.

local SEED_FORGET_MS = 1500
local LEAVES = 1 / 6 -- a share of the preview's leaves for each sqm (it flies 6)
local GROW_MS = 550 -- the roots grown and closed: held from then
local PULSE_MS = 250 -- the hold's squeeze, out and back
local LET_GO_MS = 480
local POISON_TICKS = 5
local LIGHT = layerLight('#4FAE4A')

local art = newLayerSet(3900, '/game_skillshot/images/raizes/', 'Raizes')
art.add('semente', { size = { 64, 64 }, anchor = { 32, 32 } })
for index = 1, 2 do
    art.add('folha_' .. index, { size = { 32, 32 }, anchor = { 16, 16 } })
end
art.add('acerto_nucleo', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
for index = 1, 2 do
    art.add('terra_' .. index, { size = { 32, 32 }, anchor = { 16, 16 } })
end
art.add('raizes_crescendo', { size = { 128, 128 }, anchor = { 64, 64 }, frames = 'once', ms = 600 })
art.add('raizes_presas', { size = { 128, 128 }, anchor = { 64, 64 } })
art.add('raizes_soltando', { size = { 128, 128 }, anchor = { 64, 64 }, frames = 'once', ms = 480 })
for index = 1, 2 do
    art.add('bolha_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end
art.add('broto', { size = { 64, 64 }, anchor = { 32, 32 }, frames = 'once', ms = 640 })

-- the seed spins as it flies (the preview's half turn in 650 ms)
local HEADS = { semente = { keys = { { t = 0, scale = 1, rot = 0 }, { t = 650, scale = 1, rot = 180 } } } }

local seeds = {} -- cast id -> { flight, forget }
local events = {} -- the poison's ticks still to come

function registerSeedArt()
    art.register()
end

local function forget(id, fade)
    local seed = seeds[id]
    if not seed then
        return
    end
    seeds[id] = nil
    removeEvent(seed.forget)
    seed.flight.stop(fade)
end

function clearSeedArt()
    for id in pairs(seeds) do
        forget(id)
    end
    for _, event in ipairs(events) do
        removeEvent(event)
    end
    events = {}
end

function unregisterSeedArt()
    clearSeedArt()
    art.unregister()
end

-- ms until the seed gets there (0 when it is not flying here)
local function arrival(id)
    local seed = seeds[id]
    return seed and seed.flight.arrivesIn() or 0
end

-- the closed roots from `from` to `to` ms: in, the squeeze, out
local function heldKeys(from, to)
    local keys = { { t = from, scale = 1.12, opacity = 0, x = 0, y = 0, rot = 0, ease = 2 } }
    local t, wide = from + 70, false
    while t < to - 60 do
        keys[#keys + 1] = { t = t, scale = wide and 1.456 or 1.4, opacity = wide and 0.8 or 1, x = 0, y = 0, rot = 0, ease = 2 }
        t, wide = t + PULSE_MS, not wide
    end
    keys[#keys + 1] = { t = math.max(from + 80, to - 60), scale = 1.4, opacity = 1, x = 0, y = 0, rot = 0, ease = 2 }
    keys[#keys + 1] = { t = math.max(from + 90, to), scale = 1.33, opacity = 0, x = 0, y = 0, rot = 0, ease = 2 }
    return keys
end

local handlers = {}

function handlers.fly(data)
    local seed = seeds[data.c]
    if not seed then
        seed = { flight = art.flight(data.f, HEADS) }
        seeds[data.c] = seed
    end
    removeEvent(seed.forget)
    seed.forget = scheduleEvent(function()
        forget(data.c, 150)
    end, SEED_FORGET_MS)
    seed.flight.step(data.t, tonumber(data.ms) or 110)
    art.particles('voo', data.f, { count = LEAVES, angle = layerAngle(data.t, data.f) })
end

function handlers.hit(data)
    local wait = arrival(data.c)
    forget(data.c, 80)
    local at = data.p
    art.play('acerto_nucleo', at, { moment = 'acerto', shift = wait, light = { keys = art.lightKeys('acerto'), color = LIGHT } })
    art.particles('acerto', at, { shift = wait })
    local id = tonumber(data.id)
    local creature = id and g_map.getCreatureById(id)
    if not creature then
        return
    end
    local ms = math.max(GROW_MS + 100, tonumber(data.ms) or 2500)
    local grow = wait + 30
    art.play('raizes_crescendo', creature, { moment = 'prende', shift = grow })
    art.play('raizes_presas', creature, { keys = heldKeys(grow + GROW_MS, grow + ms) })
    art.play('raizes_soltando', creature, { moment = 'solta', shift = grow + ms })
    -- the poison's bubbles where it is, once a second
    for tick = 1, POISON_TICKS do
        table.insert(events, scheduleEvent(function()
            local still = g_map.getCreatureById(id)
            if still then
                art.particles('veneno', still:getPosition())
            end
        end, wait + tick * 1000))
    end
    while #events > 40 do
        table.remove(events, 1)
    end
end

function handlers.miss(data)
    local wait = arrival(data.c)
    forget(data.c, 80)
    art.play('broto', data.p, { moment = 'erro', shift = wait })
end

function onSeedArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' and (data.p or (data.f and data.t)) then
        handler(data)
    end
end
