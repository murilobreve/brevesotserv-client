-- Flecha do Crepusculo: the designer's art (images/flecha, from "Flecha do
-- Crepusculo - artes v1"). The server sends each moment of a shot
-- (scripts/skillshot/paladin.lua, fx "arrow") and this draws it:
--   fly   the arrow moves one sqm, brighter the farther it has gone
--         (sqm 1-4, 5-8, 9-12); a still frame per step, like the hook
--   hit   the small hit (1-7 sqm) or the beam of light (8-12 sqm), and the
--         loop of light on the creature's feet while it is held
--   miss  the arrow falls at the end of its way

local ARROW_FORGET_MS = 1500 -- a shot with no news for this long is cleared
local HELD_IN_MS = 100
local HELD_OUT_MS = 100

local DIRECTIONS = { 'e', 'w', 'n', 's', 'ne', 'nw', 'se', 'sw' }
local LEVELS = { 'inicial', 'medio', 'forte' }

-- anchors: the centre of the sqm, the ground under the beam and the miss
local art = newArtSet(3500, '/game_skillshot/images/flecha/', 'Flecha')
for _, level in ipairs(LEVELS) do
    for _, dir in ipairs(DIRECTIONS) do
        for frame = 1, 4 do
            art.add('voo_' .. level .. '_' .. dir .. '_' .. frame, 32, 0, 0)
        end
    end
end
art.add('acerto_perto', 64, 16, 16, 300)
art.add('acerto_longe', { 96, 128 }, 32, 88, 400)
art.add('preso_entrada', 64, 16, 8, HELD_IN_MS)
art.add('preso_loop', 64, 16, 8)
art.add('preso_saida', 64, 16, 8, HELD_OUT_MS)
art.add('erro', 64, 16, 28, 350)

local shots = {} -- shot id -> { head, arrive, forget }
local held = {} -- creature id -> { placed, events }

function registerArrowArt()
    art.register()
end

local function forget(id)
    local shot = shots[id]
    if not shot then
        return
    end
    shots[id] = nil
    removeEvent(shot.forget)
    detachArt(shot.head)
end

local function release(creatureId)
    local hold = held[creatureId]
    if not hold then
        return
    end
    held[creatureId] = nil
    for _, event in ipairs(hold.events) do
        removeEvent(event)
    end
    detachArt(hold.placed)
end

function clearArrowArt()
    for id in pairs(shots) do
        forget(id)
    end
    for id in pairs(held) do
        release(id)
    end
end

function unregisterArrowArt()
    clearArrowArt()
    art.unregister()
end

local function shotOf(data)
    local shot = shots[data.c]
    if not shot then
        shot = { arrive = 0 }
        shots[data.c] = shot
    end
    removeEvent(shot.forget)
    shot.forget = scheduleEvent(function()
        forget(data.c)
    end, ARROW_FORGET_MS)
    return shot
end

local function onArrival(shot, callback)
    local wait = shot.arrive - g_clock.millis()
    if wait > 0 then
        scheduleEvent(callback, wait)
    else
        callback()
    end
end

-- the loop of light on its feet: in, the loop, out, `ms` in all
local function hold(creatureId, ms)
    release(creatureId)
    if not g_map.getCreatureById(creatureId) then
        return
    end
    local entry = { events = {} }
    held[creatureId] = entry
    local phases = {
        { 'preso_entrada', HELD_IN_MS },
        { 'preso_loop', math.max(0, ms - HELD_IN_MS - HELD_OUT_MS) },
        { 'preso_saida', HELD_OUT_MS - 10 }
    }
    local at = 0
    for index, phase in ipairs(phases) do
        local name, duration = phase[1], phase[2]
        local function show()
            local creature = g_map.getCreatureById(creatureId)
            if held[creatureId] ~= entry or not creature or duration <= 0 then
                return
            end
            entry.placed = art.attach(name, creature, duration)
            if index == #phases then
                held[creatureId] = nil
            end
        end
        if at == 0 then
            show()
        else
            table.insert(entry.events, scheduleEvent(show, at))
        end
        at = at + duration
    end
end

local handlers = {}

function handlers.fly(data)
    local shot = shotOf(data)
    local from, to = data.f, data.t
    detachArt(shot.head)
    local origin = data.o or from
    local dir = artDirection(to.x - origin.x, to.y - origin.y)
    local step = tonumber(data.i) or 1
    local level = step <= 4 and 'inicial' or step <= 8 and 'medio' or 'forte'
    local frame = (step - 1) % 4 + 1
    local ms = tonumber(data.ms) or 80
    -- no duration on attach (it would take the arrow off at the end of the
    -- step): set after, it times the move
    shot.head = art.place('voo_' .. level .. '_' .. dir .. '_' .. frame, from)
    if shot.head then
        shot.head.effect:setDuration(ms)
        shot.head.effect:move(from, to)
    end
    shot.arrive = g_clock.millis() + ms
end

function handlers.hit(data)
    local shot = shotOf(data)
    onArrival(shot, function()
        forget(data.c)
        art.burst(data.far and 'acerto_longe' or 'acerto_perto', data.p)
        if tonumber(data.id) and tonumber(data.ms) then
            hold(tonumber(data.id), tonumber(data.ms))
        end
    end)
end

function handlers.miss(data)
    local shot = shotOf(data)
    onArrival(shot, function()
        forget(data.c)
        art.burst('erro', data.p)
    end)
end

function onArrowArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' then
        handler(data)
    end
end
