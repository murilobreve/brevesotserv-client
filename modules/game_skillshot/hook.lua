-- Gancho do Carrasco: the designer's art v2 (images/gancho, "Ascensao -
-- artes v2", layers.lua). The server sends each moment of a cast
-- (scripts/skillshot, fx "hook"):
--   fly   the hook goes on a sqm, `ms` a sqm, turned to its way, a red
--         streak behind it and the chain laid link by link from the knight
--   hit   a big spark, a ring of impact, metal sparks, the map lit; the
--         chain pulls back
--   pull  the creature is dragged from `f` to `t` with dust, and the
--         chain closes in a ring at its feet (rooted `ms`; a boss, or a
--         player held again lately, is not: ms 0)
--   miss  it falls short where it is, turning, a little dust; the chain
--         pulls back
-- The preview throws from (-4, 0) at 75 ms a sqm and hits at (3, 0).

local HOOK_FORGET_MS = 1000 -- a cast with no news for this long is cleared
local LINK_SPACING = 0.4 -- sqm between two links of the chain
local RETRACT_MS = 200 -- the chain pulls back in this long
local TRAIL = { name = 'rastro', length = 3.5, lag = 0.3 }
local LIGHT = layerLight('#FF7A2A')

local art = newLayerSet(3200, '/game_skillshot/images/gancho/', 'Gancho')
art.add('gancho', { size = { 64, 64 }, anchor = { 32, 32 } })
art.add('corrente_elo', { size = { 64, 64 }, anchor = { 32, 32 } })
art.add('rastro', { size = { 256, 32 }, anchor = { 128, 16 }, additive = true })
art.add('impacto_nucleo', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('impacto_onda', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
for index = 1, 3 do
    art.add('faisca_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end
art.add('puxao_arrasto', { size = { 64, 64 }, anchor = { 32, 32 }, frames = 'loop', ms = 360 })
art.add('puxao_anel', { size = { 128, 128 }, anchor = { 64, 64 }, ground = true })
art.add('erro_poeira', { size = { 64, 64 }, anchor = { 32, 32 } })

-- the hook turns a little as it flies (a quarter turn in 600 ms)
local HEADS = { gancho = { face = true, keys = { { t = 0, scale = 1, rot = 0 }, { t = 600, scale = 1, rot = 90 } } } }

-- cast id -> { flight, origin, links = { { placed, keys, at } }, laid, forget }
local casts = {}

function registerHookArt()
    art.register()
end

local function forget(id)
    local cast = casts[id]
    if not cast then
        return
    end
    casts[id] = nil
    removeEvent(cast.forget)
    cast.flight.stop()
    for _, link in ipairs(cast.links) do
        detachArt(link.placed)
    end
end

function clearHookArt()
    for id in pairs(casts) do
        forget(id)
    end
end

function unregisterHookArt()
    clearHookArt()
    art.unregister()
end

local function castOf(data)
    local cast = casts[data.c]
    if not cast then
        local origin = data.o or data.f
        cast = { flight = art.flight(origin, HEADS, TRAIL), origin = origin, links = {}, laid = 0, start = g_clock.millis() }
        casts[data.c] = cast
    end
    removeEvent(cast.forget)
    cast.forget = scheduleEvent(function()
        forget(data.c)
    end, HOOK_FORGET_MS)
    return cast
end

-- the links of a step: one every LINK_SPACING sqm of the way, each coming
-- in as the hook goes over it, turned along the way
local function layLinks(cast, from, to, startMs, ms)
    local fx, fy = from.x - cast.origin.x, from.y - cast.origin.y
    local tx, ty = to.x - cast.origin.x, to.y - cast.origin.y
    local length = math.sqrt((tx - fx) ^ 2 + (ty - fy) ^ 2)
    if length <= 0 then
        return
    end
    local angle = math.deg(math.atan2(ty - fy, tx - fx))
    local walked = cast.laid
    while walked + LINK_SPACING <= cast.laid + length do
        walked = walked + LINK_SPACING
        local share = (walked - cast.laid) / length
        local x, y = fx + (tx - fx) * share, fy + (ty - fy) * share
        local t = startMs + ms * share
        local keys = {
            { t = t, scale = 0.8, opacity = 0, x = x, y = -y, rot = -angle, ease = 2 },
            { t = t + 70, scale = 1, opacity = 1, x = x, y = -y, rot = -angle, ease = 2 }
        }
        local placed = art.play('corrente_elo', cast.origin, { keys = keys, duration = 30000 })
        if placed then
            table.insert(cast.links, { placed = placed, keys = keys, at = walked })
        end
    end
    cast.laid = cast.laid + length
end

-- the chain pulls back from the hook to the knight once the hook gets
-- there; the hook and its streak go too
local function retract(cast)
    local now = g_clock.millis() - cast.start
    local from = now + cast.flight.arrivesIn()
    for _, link in ipairs(cast.links) do
        local last = link.keys[#link.keys]
        local gone = from + RETRACT_MS * (1 - link.at / math.max(cast.laid, 0.1))
        local keys = { link.keys[1], link.keys[2] }
        keys[3] = { t = math.max(last.t + 10, gone - 40), scale = 1, opacity = 1, x = last.x, y = last.y, rot = last.rot, ease = 0 }
        keys[4] = { t = math.max(last.t + 20, gone), scale = 0.9, opacity = 0, x = last.x, y = last.y, rot = last.rot, ease = 0 }
        art.update(link.placed, keys)
        link.placed.effect:setDuration(math.floor(keys[4].t) + 20)
    end
    cast.flight.stop(60)
end

local handlers = {}

function handlers.fly(data)
    local cast = castOf(data)
    local ms = tonumber(data.ms) or 75
    local startMs = math.max(g_clock.millis() - cast.start, cast.flight.arrivesIn() + g_clock.millis() - cast.start)
    layLinks(cast, data.f, data.t, startMs, ms)
    cast.flight.step(data.t, ms)
end

function handlers.hit(data)
    local cast = casts[data.c]
    local wait = cast and cast.flight.arrivesIn() or 0
    if cast then
        retract(cast)
    end
    art.play('impacto_nucleo', data.p, { moment = 'acerto', shift = wait, light = { keys = art.lightKeys('acerto'), color = LIGHT } })
    art.play('impacto_onda', data.p, { moment = 'acerto', shift = wait })
    art.particles('acerto', data.p, { shift = wait })
end

function handlers.miss(data)
    local cast = casts[data.c]
    local wait = cast and cast.flight.arrivesIn() or 0
    if cast then
        retract(cast)
    end
    -- the hook falls where it is, turning
    art.play('gancho', data.p, { moment = 'erro', shift = wait })
    art.play('erro_poeira', data.p, { moment = 'erro', shift = wait })
end

-- the preview drags 6 sqm in 400 ms: the dust goes the real way in the
-- same time a sqm
function handlers.pull(data)
    local from, to = data.f, data.t
    local length = math.max(1, math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2))
    local angle = layerAngle(from, to)
    local keys = {}
    for index, key in ipairs(art.keys('puxão', 'puxao_arrasto') or {}) do
        local copy = {}
        for field, value in pairs(key) do
            copy[field] = value
        end
        -- the preview drags toward -x: along the real way here
        copy.x = -key.x * length / 6
        copy.t = key.t * length / 6
        keys[index] = copy
    end
    art.play('puxao_arrasto', from, { keys = keys, angle = angle })
    local ring = {}
    for index, key in ipairs(art.keys('puxão', 'puxao_anel') or {}) do
        local copy = {}
        for field, value in pairs(key) do
            copy[field] = value
        end
        copy.x = 0
        copy.t = key.t * length / 6
        ring[index] = copy
    end
    art.play('puxao_anel', to, { keys = ring })
    if (tonumber(data.ms) or 0) > 0 then
        art.play('puxao_anel', to, { moment = 'preso', shift = 400 * length / 6, scaleTime = math.max(0.5, tonumber(data.ms) / 600) })
    end
end

function onHookArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' and (data.p or (data.f and data.t)) then
        handler(data)
    end
end
