-- Lanca Ricochete: the designer's art (images/lanca, from "Lanca Ricochete
-- - artes v1"). The server sends each moment of a throw
-- (scripts/skillshot/paladin.lua, fx "spear"):
--   fly     the spear moves one sqm (still frames, like the arrow)
--   bounce  it jumps from the one it hit to the next (`ms`)
--   hit     the impact, stronger with each bounce (`n`: 0 the first hit)
--   ground  missed: it lies where it fell, glowing, for `ms`
--   picked  the paladin stepped on it: it goes with a flash

local SPEAR_FORGET_MS = 1500 -- a throw with no news for this long is cleared
local STRENGTH = { 'acerto_1', 'acerto_1', 'acerto_2', 'acerto_3' }

-- anchors: the centre of the sqm; the spear on the ground stands on it
local art = newArtSet(4300, '/game_skillshot/images/lanca/', 'Lanca')
for _, dir in ipairs({ 'e', 'w', 'n', 's', 'ne', 'nw', 'se', 'sw' }) do
    for frame = 1, 4 do
        art.add('voo_' .. dir .. '_' .. frame, 32, 0, 0)
    end
end
for _, name in ipairs({ 'acerto_1', 'acerto_2', 'acerto_3', 'pegou' }) do
    art.add(name, 64, 16, 16, 300)
end
art.add('chao', 32, 0, 8)

local throws = {} -- throw id -> { head, arrive, forget }
local grounds = {} -- throw id -> placed

function registerSpearArt()
    art.register()
end

local function forget(id)
    local throw = throws[id]
    if not throw then
        return
    end
    throws[id] = nil
    removeEvent(throw.forget)
    detachArt(throw.head)
end

function clearSpearArt()
    for id in pairs(throws) do
        forget(id)
    end
    for _, placed in pairs(grounds) do
        detachArt(placed)
    end
    grounds = {}
end

function unregisterSpearArt()
    clearSpearArt()
    art.unregister()
end

local function throwOf(data)
    local throw = throws[data.c]
    if not throw then
        throw = { arrive = 0 }
        throws[data.c] = throw
    end
    removeEvent(throw.forget)
    throw.forget = scheduleEvent(function()
        forget(data.c)
    end, SPEAR_FORGET_MS)
    return throw
end

local function onArrival(throw, callback)
    local wait = throw.arrive - g_clock.millis()
    if wait > 0 then
        scheduleEvent(callback, wait)
    else
        callback()
    end
end

-- the head from one sqm to another in `ms`, turned the way it goes
local function move(throw, from, to, origin, frame, ms)
    detachArt(throw.head)
    local dir = artDirection(to.x - origin.x, to.y - origin.y)
    -- no duration on place (it would take the spear off at the end of the
    -- step): set after, it times the move
    throw.head = art.place('voo_' .. dir .. '_' .. frame, from)
    if throw.head then
        throw.head.effect:setDuration(ms)
        throw.head.effect:move(from, to)
    end
    throw.arrive = g_clock.millis() + ms
end

local handlers = {}

function handlers.fly(data)
    if not data.f or not data.t then
        return
    end
    local step = tonumber(data.i) or 1
    move(throwOf(data), data.f, data.t, data.o or data.f, (step - 1) % 4 + 1, tonumber(data.ms) or 70)
end

function handlers.bounce(data)
    if not data.f or not data.t then
        return
    end
    local throw = throwOf(data)
    onArrival(throw, function()
        move(throw, data.f, data.t, data.f, 1, tonumber(data.ms) or 180)
    end)
end

function handlers.hit(data)
    local throw = throwOf(data)
    onArrival(throw, function()
        detachArt(throw.head)
        throw.head = nil
        local strength = STRENGTH[(tonumber(data.n) or 0) + 1] or STRENGTH[#STRENGTH]
        art.burst(strength, data.p)
    end)
end

function handlers.ground(data)
    local throw = throwOf(data)
    onArrival(throw, function()
        forget(data.c)
        detachArt(grounds[data.c])
        grounds[data.c] = art.place('chao', data.p, tonumber(data.ms) or 6000)
    end)
end

function handlers.picked(data)
    detachArt(grounds[data.c])
    grounds[data.c] = nil
    art.burst('pegou', data.p)
end

function onSpearArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' then
        handler(data)
    end
end
