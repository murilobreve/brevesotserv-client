-- Palma Sonica: the designer's art (images/palma, from "Palma Sonica - artes
-- v1"). The server sends each moment of a cast (scripts/skillshot, fx
-- "palm") and this draws it:
--   fly   the wave moves one tile (a still frame per step, like the hook)
--   hit   the burst where it lands and the mark on the creature, which
--         follows it: in, a loop, a warning 0.5 s before the end, out
--   miss  the wave comes apart at the end of its way
--   dash  the monk vanishes (a puff and a trail) and shows up beside the
--         marked one with the final strike; the mark goes at once

local PALM_FORGET_MS = 1000 -- a cast with no news for this long is cleared
local MARK_IN_MS = 200
local MARK_WARNING_MS = 200
local MARK_OUT_MS = 300

local DIRECTIONS = { 'e', 'w', 'n', 's', 'ne', 'nw', 'se', 'sw' }
local TRAILS = { 'h', 'v', 'ne', 'nw' }

-- anchors: the centre of the sqm, the ground under the final strike
local art = newArtSet(3400, '/game_skillshot/images/palma/', 'Palma')
for _, dir in ipairs(DIRECTIONS) do
    for frame = 1, 4 do
        art.add('onda_' .. dir .. '_' .. frame, 32, 0, 0)
    end
end
art.add('acerto', 64, 16, 16, 300)
art.add('marca_entrada', 64, 16, 16, MARK_IN_MS)
art.add('marca_loop', 64, 16, 16)
art.add('marca_aviso', 64, 16, 16, MARK_WARNING_MS)
art.add('marca_saida', 64, 16, 16, MARK_OUT_MS)
art.add('avanco_saida', 64, 16, 16, 300)
art.add('avanco_chegada', 64, 16, 16, 300)
art.add('golpe', 128, 48, 64, 400)
art.add('erro', 64, 16, 16, 350)
for _, trail in ipairs(TRAILS) do
    art.add('rastro_' .. trail, 32, 0, 0, 150)
end

local casts = {} -- cast id -> { head, arrive, forget }
local marks = {} -- creature id -> { placed, events }

function registerPalmArt()
    art.register()
end

local function forget(id)
    local cast = casts[id]
    if not cast then
        return
    end
    casts[id] = nil
    removeEvent(cast.forget)
    detachArt(cast.head)
end

local function unmark(creatureId)
    local mark = marks[creatureId]
    if not mark then
        return
    end
    marks[creatureId] = nil
    for _, event in ipairs(mark.events) do
        removeEvent(event)
    end
    detachArt(mark.placed)
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

local function castOf(data)
    local cast = casts[data.c]
    if not cast then
        cast = { arrive = 0 }
        casts[data.c] = cast
    end
    removeEvent(cast.forget)
    cast.forget = scheduleEvent(function()
        forget(data.c)
    end, PALM_FORGET_MS)
    return cast
end

local function onArrival(cast, callback)
    local wait = cast.arrive - g_clock.millis()
    if wait > 0 then
        scheduleEvent(callback, wait)
    else
        callback()
    end
end

-- the mark's phases on the creature, one after the other, `ms` in all
local function mark(creatureId, ms)
    unmark(creatureId)
    local creature = g_map.getCreatureById(creatureId)
    if not creature then
        return
    end
    local entry = { events = {} }
    marks[creatureId] = entry
    local loopMs = math.max(0, ms - MARK_IN_MS - MARK_WARNING_MS - MARK_OUT_MS)
    local phases = {
        { 'marca_entrada', MARK_IN_MS },
        { 'marca_loop', loopMs },
        { 'marca_aviso', MARK_WARNING_MS },
        { 'marca_saida', MARK_OUT_MS - 10 }
    }
    local at = 0
    for index, phase in ipairs(phases) do
        local name, duration = phase[1], phase[2]
        local function show()
            local now = g_map.getCreatureById(creatureId)
            if marks[creatureId] ~= entry or not now or duration <= 0 then
                return
            end
            entry.placed = art.attach(name, now, duration)
            if index == #phases then
                marks[creatureId] = nil
            end
        end
        if at == 0 then
            show()
        else
            table.insert(entry.events, scheduleEvent(show, at))
        end
        at = at + phase[2]
    end
end

local handlers = {}

function handlers.fly(data)
    local cast = castOf(data)
    local from, to = data.f, data.t
    detachArt(cast.head)
    local origin = data.o or from
    local dir = artDirection(to.x - origin.x, to.y - origin.y)
    local frame = ((tonumber(data.i) or 1) - 1) % 4 + 1
    local ms = tonumber(data.ms) or 80
    -- no duration on attach (it would take the wave off at the end of the
    -- step): set after, it times the move
    cast.head = art.place('onda_' .. dir .. '_' .. frame, from)
    if cast.head then
        cast.head.effect:setDuration(ms)
        cast.head.effect:move(from, to)
    end
    cast.arrive = g_clock.millis() + ms
end

function handlers.hit(data)
    local cast = castOf(data)
    onArrival(cast, function()
        forget(data.c)
        art.burst('acerto', data.p)
        if tonumber(data.id) then
            mark(tonumber(data.id), tonumber(data.ms) or 3000)
        end
    end)
end

function handlers.miss(data)
    local cast = castOf(data)
    onArrival(cast, function()
        forget(data.c)
        art.burst('erro', data.p)
    end)
end

function handlers.dash(data)
    local from, to = data.f, data.t
    if tonumber(data.id) then
        unmark(tonumber(data.id))
    end
    art.burst('avanco_saida', from)
    -- the trail on the sqm between where the monk was and where it lands
    local dx, dy = to.x - from.x, to.y - from.y
    local steps = math.max(math.abs(dx), math.abs(dy))
    local trail = 'rastro_' .. ART_LINE_OF[artDirection(dx, dy)]
    for step = 1, steps - 1 do
        art.burst(trail, {
            x = from.x + math.floor(dx * step / steps + 0.5),
            y = from.y + math.floor(dy * step / steps + 0.5),
            z = from.z
        })
    end
    art.burst('avanco_chegada', to)
    if data.p then
        art.burst('golpe', data.p)
    end
end

function onPalmArt(data)
    local handler = handlers[data.k]
    if handler and (data.k == 'dash' or type(data.c) == 'number') then
        handler(data)
    end
end
