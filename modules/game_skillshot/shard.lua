-- Estilhaco de Gelo: the designer's art (images/estilhaco, from "Estilhaco
-- de Gelo - artes v1"). The server sends (scripts/skillshot/druid.lua, fx
-- "shard"):
--   fly     the orb moves one sqm through what it meets (still frames)
--   graze   the frost on whom it passes through
--   burst   said again: it shatters (3x3) and the stunned get the stars
--           over their heads for `ms`
--   fade    not said again: it comes apart at the end of its way

local SHARD_FORGET_MS = 2000

-- anchors: the centre of the sqm; the stun on the creature's feet
local art = newArtSet(4000, '/game_skillshot/images/estilhaco/', 'Estilhaco')
for frame = 1, 4 do
    art.add('orbe_' .. frame, 32, 0, 0)
end
art.add('geada', 32, 0, 0, 300)
art.add('estilhaco', 96, 32, 32, 400)
art.add('atordoado', { 32, 48 }, 0, 16)
art.add('desfazendo', 32, 0, 0, 350)

local shards = {}

function registerShardArt()
    art.register()
end

local function forget(id)
    local shard = shards[id]
    if not shard then
        return
    end
    shards[id] = nil
    removeEvent(shard.forget)
    detachArt(shard.head)
end

function clearShardArt()
    for id in pairs(shards) do
        forget(id)
    end
end

function unregisterShardArt()
    clearShardArt()
    art.unregister()
end

local function shardOf(data)
    local shard = shards[data.c]
    if not shard then
        shard = {}
        shards[data.c] = shard
    end
    removeEvent(shard.forget)
    shard.forget = scheduleEvent(function()
        forget(data.c)
    end, SHARD_FORGET_MS)
    return shard
end

local handlers = {}

function handlers.fly(data)
    local shard = shardOf(data)
    local from, to = data.f, data.t
    detachArt(shard.head)
    local frame = ((tonumber(data.i) or 1) - 1) % 4 + 1
    local ms = tonumber(data.ms) or 200
    shard.head = art.place('orbe_' .. frame, from)
    if shard.head then
        shard.head.effect:setDuration(ms)
        shard.head.effect:move(from, to)
    end
end

function handlers.graze(data)
    art.burst('geada', data.p)
end

function handlers.burst(data)
    forget(data.c)
    art.burst('estilhaco', data.p)
    local ms = tonumber(data.ms) or 1500
    for _, id in ipairs(data.ids or {}) do
        local creature = g_map.getCreatureById(tonumber(id) or 0)
        if creature then
            art.attach('atordoado', creature, ms)
        end
    end
end

function handlers.fade(data)
    forget(data.c)
    art.burst('desfazendo', data.p)
end

function onShardArt(data)
    local handler = handlers[data.k]
    if handler and type(data.p) == 'table' then
        handler(data)
    end
end
