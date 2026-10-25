-- Corte Sismico: the designer's art (images/corte, from "Corte Sismico -
-- artes v1"). The server sends (scripts/skillshot/knight.lua, fx "crack"):
--   charge  the knight starts gathering: the glow grows in three levels
--           (each `ms` / 3) and flashes once when it is full
--   stop    released or lost: the glow goes (lost: it fizzles on the knight)
--   cut     one sqm of the crack, the way it runs, and the hit if it got one

local LEVEL_COUNT = 3

-- anchors: the knight's feet for the charge, the centre of the sqm
local art = newArtSet(4100, '/game_skillshot/images/corte/', 'Corte')
for level = 1, LEVEL_COUNT do
    art.add('carga_' .. level, 64, 16, 21)
end
art.add('cheia', 64, 16, 21, 200)
for _, way in ipairs({ 'h', 'v', 'ne', 'nw' }) do
    art.add('fenda_' .. way, 32, 0, 0, 500)
end
art.add('acerto', 64, 16, 16, 300)
art.add('cancelamento', 32, 0, -2, 250)

local charges = {} -- creature id -> { placed, events }

function registerCrackArt()
    art.register()
end

local function stop(id)
    local charge = charges[id]
    if not charge then
        return
    end
    charges[id] = nil
    for _, event in ipairs(charge.events) do
        removeEvent(event)
    end
    detachArt(charge.placed)
end

function clearCrackArt()
    for id in pairs(charges) do
        stop(id)
    end
end

function unregisterCrackArt()
    clearCrackArt()
    art.unregister()
end

local handlers = {}

function handlers.charge(data)
    local id = tonumber(data.id)
    if not id then
        return
    end
    stop(id)
    local charge = { events = {} }
    charges[id] = charge
    local full = tonumber(data.ms) or 1500
    local function show(level)
        local knight = g_map.getCreatureById(id)
        if charges[id] ~= charge or not knight then
            return
        end
        detachArt(charge.placed)
        charge.placed = art.attach('carga_' .. level, knight)
        if level == LEVEL_COUNT then
            art.attach('cheia', knight, 190)
        end
    end
    show(1)
    for level = 2, LEVEL_COUNT do
        table.insert(charge.events, scheduleEvent(function()
            show(level)
        end, math.floor(full * (level - 1) / (LEVEL_COUNT - 1))))
    end
end

function handlers.stop(data)
    local id = tonumber(data.id)
    if id then
        stop(id)
    end
    if data.lost and data.p then
        art.burst('cancelamento', data.p)
    end
end

function handlers.cut(data)
    if not data.p then
        return
    end
    local way = ({ h = 'h', v = 'v', ne = 'ne', nw = 'nw' })[data.o] or 'h'
    art.burst('fenda_' .. way, data.p)
    if data.hit then
        art.burst('acerto', data.p)
    end
end

function onCrackArt(data)
    local handler = handlers[data.k]
    if handler then
        handler(data)
    end
end
