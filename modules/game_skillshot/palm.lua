-- Palma Sonica: the designer's art v2 (images/palma, "Ascensao - artes v2",
-- layers.lua). The server sends each moment of a cast (scripts/skillshot,
-- fx "palm"):
--   fly   the sonic crescent goes on a sqm, `ms` a sqm, turned to its
--         way, two fainter echoes behind it
--   hit   when it gets there: rings and a flash, the map lit; the ki seal
--         on the creature (id) for `ms`, turning at its feet and following
--         it, its glow blinking in the last half second
--   miss  the wave comes apart at the end of its way
--   dash  the monk crosses from `f` to `t` in a brushstroke of ki ink and
--         strikes the marked one (p, id) with a giant palm of ki, a wave,
--         ink splashed, the map lit; the seal goes at once
-- The preview throws from (-4, 0) at 75 ms a sqm and hits at (2, 0); the
-- seal lasts 2 s there.

local PALM_FORGET_MS = 1000 -- a cast with no news for this long is cleared
local WARNING_MS = 550 -- the glow blinks from this long before the end
local SEAL_TURN = 0.06 -- degrees a ms: the preview's third of a turn in 2 s
local STRIKE_MS = 100 -- the palm comes as the brushstroke gets there
local PREVIEW_DASH_SQM = 6
local NATIVE_LENGTH = 4 -- sqm, the brushstroke's image
local LIGHT = layerLight('#FFC86B')

local art = newLayerSet(3400, '/game_skillshot/images/palma/', 'Palma')
art.add('onda', { size = { 96, 96 }, anchor = { 48, 48 }, additive = true })
art.add('acerto_onda', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
art.add('acerto_nucleo', { size = { 96, 96 }, anchor = { 48, 48 }, additive = true })
art.add('marca', { size = { 128, 128 }, anchor = { 64, 64 }, ground = true })
art.add('marca_brilho', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true, ground = true })
art.add('avanco_pincelada', { size = { 256, 64 }, anchor = { 128, 32 } })
art.add('golpe_palma', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('golpe_onda', { size = { 320, 320 }, anchor = { 160, 160 }, ground = true })
for index = 1, 3 do
    art.add('tinta_' .. index, { size = { 32, 32 }, anchor = { 16, 16 } })
end
art.add('erro', { size = { 96, 96 }, anchor = { 48, 48 }, frames = 'once', ms = 420 })

-- the crescent and its two echoes (runtime.json's "ecos")
local HEADS = {
    onda = { face = true },
    eco_1 = { image = 'onda', face = true, delay = 45, opacity = 0.35 },
    eco_2 = { image = 'onda', face = true, delay = 90, opacity = 0.15 }
}

local casts = {} -- cast id -> { flight, forget }
local marks = {} -- creature id -> { placed, ... }

function registerPalmArt()
    art.register()
end

local function forget(id, fade)
    local cast = casts[id]
    if not cast then
        return
    end
    casts[id] = nil
    removeEvent(cast.forget)
    cast.flight.stop(fade)
end

local function unmark(id)
    for _, placed in ipairs(marks[id] or {}) do
        detachArt(placed)
    end
    marks[id] = nil
end

function clearPalmArt()
    for id in pairs(casts) do
        forget(id)
    end
    for id in pairs(marks) do
        unmark(id)
    end
end

function unregisterPalmArt()
    clearPalmArt()
    art.unregister()
end

-- ms until the wave gets there (0 when it is not flying)
local function arrival(id)
    local cast = casts[id]
    return cast and cast.flight.arrivesIn() or 0
end

-- the seal for `ms` from `from`: in, turning, out at its end
local function sealKeys(from, ms)
    return {
        { t = from, scale = 0.88, opacity = 0, x = 0, y = 0, rot = 0, ease = 2 },
        { t = from + 70, scale = 1.1, opacity = 1, x = 0, y = 0, rot = -SEAL_TURN * 70, ease = 2 },
        { t = from + ms - 60, scale = 1.1, opacity = 1, x = 0, y = 0, rot = -SEAL_TURN * (ms - 60), ease = 0 },
        { t = from + ms, scale = 1.045, opacity = 0, x = 0, y = 0, rot = -SEAL_TURN * ms, ease = 2 }
    }
end

-- its glow: steady, then the preview's last half second of blinking
local function glowKeys(from, ms)
    local keys = {
        { t = from, scale = 0.8, opacity = 0, x = 0, y = 0, rot = 0, ease = 2 },
        { t = from + 100, scale = 1, opacity = 0.6, x = 0, y = 0, rot = 0, ease = 2 }
    }
    local blink = art.keys('marca', 'marca_brilho') or {}
    local shift = from + ms - 2000
    for _, key in ipairs(blink) do
        if key.t >= 2000 - WARNING_MS and key.t + shift > keys[#keys].t then
            keys[#keys + 1] = { t = key.t + shift, scale = key.scale, opacity = key.opacity, x = 0, y = 0, rot = 0, ease = key.ease }
        end
    end
    return keys
end

local handlers = {}

function handlers.fly(data)
    local cast = casts[data.c]
    if not cast then
        cast = { flight = art.flight(data.f, HEADS) }
        casts[data.c] = cast
    end
    removeEvent(cast.forget)
    cast.forget = scheduleEvent(function()
        forget(data.c, 100)
    end, PALM_FORGET_MS)
    cast.flight.step(data.t, tonumber(data.ms) or 80)
end

function handlers.hit(data)
    local wait = arrival(data.c)
    forget(data.c, 60)
    art.play('acerto_nucleo', data.p, { moment = 'acerto', shift = wait, light = { keys = art.lightKeys('acerto'), color = LIGHT } })
    art.play('acerto_onda', data.p, { moment = 'acerto', shift = wait })
    local id, ms = tonumber(data.id), tonumber(data.ms)
    local creature = id and ms and g_map.getCreatureById(id)
    if creature then
        unmark(id)
        marks[id] = {
            art.play('marca', creature, { keys = sealKeys(wait, ms) }),
            art.play('marca_brilho', creature, { keys = glowKeys(wait, ms) })
        }
    end
end

function handlers.miss(data)
    local wait = arrival(data.c)
    forget(data.c, 60)
    art.play('erro', data.p, { moment = 'erro', shift = wait })
end

function handlers.dash(data)
    local from, to = data.f, data.t
    if type(from) ~= 'table' or type(to) ~= 'table' then
        return
    end
    local length = math.max(1, math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2))
    local keys = {}
    for index, key in ipairs(art.keys('avanço', 'avanco_pincelada') or {}) do
        local copy = {}
        for field, value in pairs(key) do
            copy[field] = value
        end
        copy.x = key.x * length / PREVIEW_DASH_SQM
        copy.stretch = length / NATIVE_LENGTH
        keys[index] = copy
    end
    local angle = layerAngle(from, to)
    art.play('avanco_pincelada', from, { keys = keys, angle = angle, face = angle })
    if tonumber(data.id) then
        unmark(tonumber(data.id))
    end
    local at = type(data.p) == 'table' and data.p or to
    art.play('golpe_palma', at, { moment = 'golpe', shift = STRIKE_MS, light = { keys = art.lightKeys('golpe'), color = LIGHT } })
    art.play('golpe_onda', at, { moment = 'golpe', shift = STRIKE_MS })
    art.particles('golpe', at, { shift = STRIKE_MS })
end

function onPalmArt(data)
    local handler = handlers[data.k]
    if handler and (data.p or (data.f and data.t)) then
        if (data.k == 'fly' or data.k == 'hit' or data.k == 'miss') and type(data.c) ~= 'number' then
            return
        end
        handler(data)
    end
end
