-- Estilhaco de Gelo: the designer's art v2 (images/estilhaco, "Ascensao -
-- artes v2", layers.lua). The server sends (scripts/skillshot/druid.lua,
-- fx "shard"):
--   fly     the faceted orb goes on a sqm through what it meets, `ms` a
--           sqm, its cold glow around it, little crystals falling behind
--   graze   frost at the feet of whom it passes through
--   burst   said again: it shatters (3x3), a cold flash, a ring of ice and
--           a mist, ice splinters thrown out, the map lit; the stunned
--           (ids) get a crown of crystals turning over their heads, each
--           for its own time (mss; `ms` with no mss)
--   fade    not said again: it melts at the end of its way
-- The preview flies from (-4, 0); the shatter is at (2, 0).

local SHARD_FORGET_MS = 2000
local CRYSTALS = 1 / 6 -- a share of the preview's crystals for each sqm (it flies 6)
local CROWN_TURN = 0.1 -- degrees a ms: the preview's half turn in 1.8 s
local LIGHT = layerLight('#8FD3FF')

local art = newLayerSet(4000, '/game_skillshot/images/estilhaco/', 'Estilhaco')
art.add('orbe', { size = { 64, 64 }, anchor = { 32, 32 } })
art.add('orbe_brilho', { size = { 96, 96 }, anchor = { 48, 48 }, additive = true })
for index = 1, 2 do
    art.add('cristal_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end
art.add('geada', { size = { 64, 64 }, anchor = { 32, 32 }, ground = true })
art.add('estilhaco_nucleo', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('estilhaco_onda', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
art.add('nevoa', { size = { 192, 192 }, anchor = { 96, 96 } })
art.add('atordoado', { size = { 64, 64 }, anchor = { 32, 32 } })
for index = 1, 3 do
    art.add('lasca_' .. index, { size = { 32, 32 }, anchor = { 16, 16 } })
end
art.add('desfazendo', { size = { 64, 64 }, anchor = { 32, 32 }, frames = 'once', ms = 480 })

local HEADS = { orbe = {}, orbe_brilho = {} }

local shards = {} -- cast id -> { flight, forget }
local crowns = {} -- creature id -> placed crown

function registerShardArt()
    art.register()
end

local function forget(id, fade)
    local shard = shards[id]
    if not shard then
        return
    end
    shards[id] = nil
    removeEvent(shard.forget)
    shard.flight.stop(fade)
end

function clearShardArt()
    for id in pairs(shards) do
        forget(id)
    end
    for id, placed in pairs(crowns) do
        detachArt(placed)
        crowns[id] = nil
    end
end

function unregisterShardArt()
    clearShardArt()
    art.unregister()
end

-- the crown over the head for `ms`: in, turning, out at its end
local function crownKeys(ms)
    local up = 0.9
    local out = math.min(60, ms / 4)
    return {
        { t = 0, scale = 0.8, opacity = 0, x = 0, y = up, rot = 0, ease = 2 },
        { t = 70, scale = 1, opacity = 1, x = 0, y = up, rot = 7, ease = 2 },
        { t = math.max(80, ms - out), scale = 1, opacity = 1, x = 0, y = up, rot = CROWN_TURN * (ms - out), ease = 0 },
        { t = math.max(90, ms), scale = 0.95, opacity = 0, x = 0, y = up, rot = CROWN_TURN * ms, ease = 2 }
    }
end

local handlers = {}

function handlers.fly(data)
    local shard = shards[data.c]
    if not shard then
        shard = { flight = art.flight(data.f, HEADS) }
        shards[data.c] = shard
    end
    removeEvent(shard.forget)
    shard.forget = scheduleEvent(function()
        forget(data.c, 150)
    end, SHARD_FORGET_MS)
    shard.flight.step(data.t, tonumber(data.ms) or 200)
    art.particles('voo', data.f, { count = CRYSTALS, angle = layerAngle(data.t, data.f) })
end

function handlers.graze(data)
    art.play('geada', data.p, { moment = 'passa' })
end

function handlers.burst(data)
    forget(data.c)
    local center = data.p
    art.play('estilhaco_nucleo', center, { moment = 'estilhaço', light = { keys = art.lightKeys('estilhaço'), color = LIGHT } })
    art.play('estilhaco_onda', center, { moment = 'estilhaço' })
    art.play('nevoa', center, { moment = 'estilhaço' })
    art.particles('estilhaço', center)
    local ms = tonumber(data.ms) or 1500
    local each = type(data.mss) == 'table' and data.mss or {}
    for index, id in ipairs(type(data.ids) == 'table' and data.ids or {}) do
        local creature = g_map.getCreatureById(id)
        if creature then
            detachArt(crowns[id])
            crowns[id] = art.play('atordoado', creature, { keys = crownKeys(tonumber(each[index]) or ms) })
        end
    end
end

function handlers.fade(data)
    forget(data.c, 100)
    art.play('desfazendo', data.p, { moment = 'fim' })
end

function onShardArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' and (data.p or (data.f and data.t)) then
        handler(data)
    end
end
