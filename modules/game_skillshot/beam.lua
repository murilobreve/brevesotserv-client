-- Raio Arcano: the designer's art (images/raio, from "Raio Arcano - artes
-- v1"). The server sends (scripts/skillshot/sorcerer.lua, fx "beam"):
--   charge  the sorcerer starts gathering: the charge grows in three levels
--           (at 0, `ms` / 2 and `ms`) and flashes once when it is full
--   fire    the whole beam at once on its sqm (`t`): the start on the first,
--           the middle on the others and the tip on the last, the way it
--           goes; the hit on the sqm in `h`
--   stop    the charge goes with no beam

local LEVEL_COUNT = 3

-- anchors: the centre of the sqm (the charge on the sorcerer)
local art = newArtSet(4400, '/game_skillshot/images/raio/', 'Raio')
for level = 1, LEVEL_COUNT do
    art.add('carga_' .. level, 64, 16, 16)
end
art.add('cheia', 64, 16, 16, 200)
for _, piece in ipairs({ 'inicio', 'meio', 'ponta' }) do
    for _, dir in ipairs({ 'e', 'w', 'n', 's', 'ne', 'nw', 'se', 'sw' }) do
        art.add(piece .. '_' .. dir, 32, 0, 0, 300)
    end
end
art.add('acerto', 64, 16, 16, 300)

local charges = {} -- creature id -> { placed, events }

function registerBeamArt()
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

function clearBeamArt()
    for id in pairs(charges) do
        stop(id)
    end
end

function unregisterBeamArt()
    clearBeamArt()
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
        local sorcerer = g_map.getCreatureById(id)
        if charges[id] ~= charge or not sorcerer then
            return
        end
        detachArt(charge.placed)
        charge.placed = art.attach('carga_' .. level, sorcerer)
        if level == LEVEL_COUNT then
            art.attach('cheia', sorcerer, 190)
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
    if tonumber(data.id) then
        stop(tonumber(data.id))
    end
end

function handlers.fire(data)
    if tonumber(data.id) then
        stop(tonumber(data.id))
    end
    local tiles = type(data.t) == 'table' and data.t or {}
    local last = tiles[#tiles]
    if not data.f or not last then
        return
    end
    local dir = artDirection(last.x - data.f.x, last.y - data.f.y)
    for index, position in ipairs(tiles) do
        local piece = index == #tiles and 'ponta' or index == 1 and 'inicio' or 'meio'
        art.burst(piece .. '_' .. dir, position)
    end
    for _, position in ipairs(type(data.h) == 'table' and data.h or {}) do
        art.burst('acerto', position)
    end
end

function onBeamArt(data)
    local handler = handlers[data.k]
    if handler then
        handler(data)
    end
end
