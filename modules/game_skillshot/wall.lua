-- Muralha Glacial: the designer's art (images/muralha, from "Muralha
-- Glacial - artes v1"). The server blocks the wall's sqm with an invisible
-- wall and sends (scripts/skillshot/druid.lua, fx "wall"):
--   up     the sqm and the way it runs (ns, eo, ne, nw) and how long it
--          stands: each piece rises, stands shimmering, cracks in its last
--          second and breaks
--   chill  the frost on the feet of what stands next to it

local RISE_MS = 250
local CRACK_MS = 1000

-- anchors: the foot of each piece on the ground of its sqm
local art = newArtSet(3700, '/game_skillshot/images/muralha/', 'Muralha')
for _, way in ipairs({ 'ns', 'eo', 'ne', 'nw' }) do
    art.add('subida_' .. way, { 32, 64 }, 0, 32, RISE_MS)
    art.add('pe_' .. way, { 32, 64 }, 0, 32)
    art.add('rachando_' .. way, { 32, 64 }, 0, 32, CRACK_MS)
end
art.add('quebra', 64, 16, 26, 300)
art.add('frio', 32, 0, 0, 400)

local pending = {} -- scheduled events, cancelled when the game ends
local standing = {} -- pieces on the map, taken off when the game ends

local function later(delay, callback)
    local event
    event = scheduleEvent(function()
        pending[event] = nil
        callback()
    end, math.max(0, delay))
    pending[event] = true
end

function registerWallArt()
    art.register()
end

function clearWallArt()
    for event in pairs(pending) do
        removeEvent(event)
    end
    pending = {}
    for placed in pairs(standing) do
        detachArt(placed)
    end
    standing = {}
end

function unregisterWallArt()
    clearWallArt()
    art.unregister()
end

local function piece(position, way, ms)
    art.burst('subida_' .. way, position)
    local standMs = math.max(0, ms - RISE_MS - CRACK_MS)
    later(RISE_MS - 10, function()
        local placed = art.place('pe_' .. way, position, standMs)
        if placed then
            standing[placed] = true
            later(standMs, function()
                standing[placed] = nil
            end)
        end
    end)
    later(RISE_MS + standMs, function()
        art.burst('rachando_' .. way, position)
    end)
    later(ms, function()
        art.burst('quebra', position)
    end)
end

local handlers = {}

function handlers.up(data)
    local way = ({ ns = 'ns', eo = 'eo', ne = 'ne', nw = 'nw' })[data.o] or 'ns'
    local ms = tonumber(data.ms) or 4000
    for _, position in ipairs(data.p or {}) do
        piece(position, way, ms)
    end
end

function handlers.chill(data)
    for _, position in ipairs(data.p or {}) do
        art.burst('frio', position)
    end
end

function onWallArt(data)
    local handler = handlers[data.k]
    if handler and type(data.p) == 'table' then
        handler(data)
    end
end
