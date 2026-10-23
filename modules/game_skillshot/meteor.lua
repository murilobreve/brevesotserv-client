-- Meteoro: the designer's art (images/meteoro, from "Meteoro - artes v1").
-- The server sends two moments of a cast (scripts/skillshot, fx "meteor"):
--   mark    the 3x3 square fills its ring and the centre glows for `ms`
--           (1.5 s); 0.4 s before the end the rock falls from the upper left
--   impact  the blast, then the ground burns, fainter each second (3 s,
--           while the server burns whoever stands there)
-- The falling rock is a still frame per tile it crosses (a moving effect
-- can't use an animated texture).

local FALL_MS = 400
local FALL_TILES = 4 -- it comes from this many tiles up and to the left
local BURN_STAGES = { 'brasas_fortes', 'brasas_medias', 'brasas_fracas' }
local BURN_STAGE_MS = 1000

-- anchors: the centre for the marks and the embers, the front of the rock,
-- the ground under the blast
local art = newArtSet(3300, '/game_skillshot/images/meteoro/', 'Meteoro')
art.add('marca', 96, 32, 32, 1500, true)
art.add('centro', 32, 0, 0, 1500, true)
for frame = 1, 8 do
    art.add('queda_' .. frame, 128, 88, 92)
end
art.add('impacto', 160, 64, 88, 400)
for _, stage in ipairs(BURN_STAGES) do
    art.add(stage, 96, 32, 32, BURN_STAGE_MS, true)
end

local pending = {} -- scheduled events, cancelled when the game ends

local function later(delay, callback)
    local event
    event = scheduleEvent(function()
        pending[event] = nil
        callback()
    end, math.max(0, delay))
    pending[event] = true
end

function registerMeteorArt()
    art.register()
end

function clearMeteorArt()
    for event in pairs(pending) do
        removeEvent(event)
    end
    pending = {}
end

function unregisterMeteorArt()
    clearMeteorArt()
    art.unregister()
end

local function at(center, dx, dy)
    return { x = center.x + dx, y = center.y + dy, z = center.z }
end

local function fall(center)
    local stepMs = math.floor(FALL_MS / FALL_TILES)
    for step = 0, FALL_TILES - 1 do
        later(step * stepMs, function()
            local from = at(center, step - FALL_TILES, step - FALL_TILES)
            -- the duration takes it off when it gets to the next tile
            local placed = art.place('queda_' .. (step * 2 + 1), from, stepMs)
            if placed then
                placed.effect:move(from, at(from, 1, 1))
            end
        end)
    end
end

local handlers = {}

function handlers.mark(data)
    local center, ms = data.p, tonumber(data.ms) or 1500
    art.burst('marca', center)
    art.burst('centro', center)
    later(ms - FALL_MS, function()
        fall(center)
    end)
end

function handlers.impact(data)
    local center = data.p
    art.burst('impacto', center)
    for index, stage in ipairs(BURN_STAGES) do
        later((index - 1) * BURN_STAGE_MS, function()
            art.burst(stage, center)
        end)
    end
end

function onMeteorArt(data)
    local handler = handlers[data.k]
    if handler and type(data.p) == 'table' then
        handler(data)
    end
end
