-- Chute do Dragao: the designer's art v2 (images/chute, "Ascensao - artes
-- v2", layers.lua). The server sends (scripts/skillshot/monk.lua, fx
-- "kick"):
--   kick   the ki dragon roars over the one beside the monk (p), turned
--          the way it goes (`w`)
--   trail  the kicked one leaves this sqm (one every KICK_STEP_MS): a
--          streak of ki follows it, and dust
--   bump   it ran into someone: a flash and a shock wave
--   land   it stops (at the end of its way or on a wall): dust and cracked
--          ground, and the streak fades
-- The preview kicks from (-3, 0) and stops at (3.5, 0).

local KICK_STEP_MS = 90 -- monk.lua's KICK_STEP
local STREAK_LAG = 1 -- sqm the streak's middle stays behind the flying one
local STREAK_LINGER_MS = 300 -- with no news of the flight it fades by itself
local DUST = 0.25 -- a share of the dust for each sqm flown
local FROM, STOP = { -3, 0 }, { 3.5, 0 }
local LIGHT = 205 -- golden ki

local art = newLayerSet(4600, '/game_skillshot/images/chute/', 'Chute')
art.add('dragao', { size = { 192, 192 }, anchor = { 96, 96 }, frames = 'once', ms = 520 })
art.add('dragao_brilho', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('rastro_ki', { size = { 256, 64 }, anchor = { 128, 32 }, additive = true })
art.add('atropelo_nucleo', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('atropelo_onda', { size = { 192, 192 }, anchor = { 96, 96 } })
art.add('queda', { size = { 128, 128 }, anchor = { 64, 64 }, frames = 'once', ms = 600 })
for index = 1, 2 do
    art.add('poeira_' .. index, { size = { 32, 32 }, anchor = { 16, 16 } })
end

-- the sqm the flying one is on -> its streak: { placed, start, steps, angle }
local flights = {}

local function keyOf(position)
    return position.x .. ':' .. position.y .. ':' .. position.z
end

function registerKickArt()
    art.register()
end

function clearKickArt()
    for _, flight in pairs(flights) do
        detachArt(flight.placed)
    end
    flights = {}
end

function unregisterKickArt()
    clearKickArt()
    art.unregister()
end

local function wayOf(data)
    local way = type(data.w) == 'table' and data.w or {}
    return tonumber(way[1]) or 1, tonumber(way[2]) or 0
end

local function angleOf(data)
    local sx, sy = wayOf(data)
    return math.deg(math.atan2(sy, sx))
end

local function key(t, x, scale, opacity, ease)
    return { t = t, x = x, y = 0, scale = scale, opacity = opacity, rot = 0, ease = ease }
end

-- the streak's points: from where the flight began, a sqm every step so
-- far; then it lingers, or (`stopped`) fades a little farther on. A
-- diagonal step is longer than a straight one.
local function streakKeys(flight, stopped)
    local sqm = flight.diagonal and math.sqrt(2) or 1
    local keys = { key(0, -STREAK_LAG * sqm, 0.5, 0, 0) }
    for step = 1, flight.steps do
        keys[#keys + 1] = key(step * KICK_STEP_MS, (step - STREAK_LAG) * sqm, 1, 0.9, step == 1 and 2 or 0)
    end
    local last = keys[#keys]
    local now = g_clock.millis() - flight.start
    local fadeFrom = math.max(last.t, stopped and now or last.t + STREAK_LINGER_MS)
    keys[#keys + 1] = key(fadeFrom, last.x, 1, 0.8, 0)
    keys[#keys + 1] = key(fadeFrom + 150, last.x + 0.5 * sqm, 1.1, 0, 1)
    return keys
end

local handlers = {}

function handlers.kick(data)
    local angle = angleOf(data)
    for _, name in ipairs({ 'dragao', 'dragao_brilho' }) do
        art.play(name, data.p, { moment = 'chute', home = FROM, angle = angle, turn = true })
    end
end

function handlers.trail(data)
    local sx, sy = wayOf(data)
    -- flights that never landed (the kicked one died on the way)
    for at, other in pairs(flights) do
        if g_clock.millis() - other.seen > 2000 then
            flights[at] = nil
        end
    end
    local here = keyOf(data.p)
    local flight = flights[here]
    flights[here] = nil
    if not flight or g_clock.millis() - flight.seen > KICK_STEP_MS * 3 then
        flight = { start = g_clock.millis(), steps = 0, diagonal = sx ~= 0 and sy ~= 0 }
        local opts = { keys = { key(0, 0, 0.5, 0, 0) }, angle = angleOf(data), turn = true, duration = 3000 }
        flight.opts = opts
        flight.placed = art.play('rastro_ki', data.p, opts)
    end
    flight.steps = flight.steps + 1
    flight.seen = g_clock.millis()
    art.update(flight.placed, streakKeys(flight), flight.opts)
    flights[keyOf({ x = data.p.x + sx, y = data.p.y + sy, z = data.p.z })] = flight
    art.particles('voo', data.p, { angle = flight.opts.angle + 180, count = DUST })
end

function handlers.bump(data)
    art.play('atropelo_nucleo', data.p, { moment = 'batida', home = STOP, light = { keys = art.lightKeys('batida'), color = LIGHT } })
    art.play('atropelo_onda', data.p, { moment = 'batida', home = STOP })
end

function handlers.land(data)
    local here = keyOf(data.p)
    local flight = flights[here]
    flights[here] = nil
    if flight then
        art.update(flight.placed, streakKeys(flight, true), flight.opts)
    end
    art.play('queda', data.p, { moment = 'queda', home = STOP })
end

function onKickArt(data)
    local handler = handlers[data.k]
    if handler and data.p then
        handler(data)
    end
end
