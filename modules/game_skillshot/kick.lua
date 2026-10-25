-- Chute do Dragao: the designer's art (images/chute, from "Chute do Dragao -
-- artes v1"). The server sends (scripts/skillshot/monk.lua, fx "kick"):
--   kick   the dragon kick on the one beside the monk, the way it goes (`w`)
--   trail  the dust on each sqm the kicked one flies over
--   bump   it ran into someone
--   land   it stops (at the end of its way or on a wall)

-- anchors: the centre of the sqm; the trail and the fall on its feet
local art = newArtSet(4600, '/game_skillshot/images/chute/', 'Chute')
for _, dir in ipairs({ 'e', 'w', 'n', 's', 'ne', 'nw', 'se', 'sw' }) do
    art.add('chute_' .. dir, 64, 16, 16, 300)
    art.add('rastro_' .. dir, 32, 0, 4, 300)
end
art.add('atropelo', 64, 16, 16, 300)
art.add('queda', 64, 16, 24, 300)

function registerKickArt()
    art.register()
end

function unregisterKickArt()
    art.unregister()
end

local function wayOf(data)
    local way = type(data.w) == 'table' and data.w or {}
    return artDirection(tonumber(way[1]) or 1, tonumber(way[2]) or 0)
end

local handlers = {}

function handlers.kick(data)
    art.burst('chute_' .. wayOf(data), data.p)
end

function handlers.trail(data)
    art.burst('rastro_' .. wayOf(data), data.p)
end

function handlers.bump(data)
    art.burst('atropelo', data.p)
end

function handlers.land(data)
    art.burst('queda', data.p)
end

function onKickArt(data)
    local handler = handlers[data.k]
    if handler and data.p then
        handler(data)
    end
end
