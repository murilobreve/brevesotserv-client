-- Salto do Tita: the designer's art (images/salto, from "Salto do Tita -
-- artes v1"). The server sends (scripts/skillshot/knight.lua, fx "leap"):
--   jump  the dust where the knight leaves and the shadow growing where he
--         lands, for `ms`; the knight is in the air meanwhile (not drawn)
--   land  the fall and the ground wave (5x5) where he comes down
-- The arc of the leap is not drawn: he goes and comes back at the landing.

local HIDE_SAFETY_MS = 400 -- drawn again by then even with no landing

-- anchors: the knight's feet for the dust, the centre of the sqm for the rest
local art = newArtSet(4500, '/game_skillshot/images/salto/', 'Salto')
art.add('saida', 64, 16, 24, 300)
art.add('sombra', 64, 16, 16, 600, true)
art.add('queda', 96, 32, 32, 400)
art.add('onda', 160, 64, 64, 400, true)

local airborne = {} -- creature id -> safety event

function registerLeapArt()
    art.register()
end

-- an older client cannot hide a creature: the knight just stays in view
local function setDrawn(id, drawn)
    local creature = g_map.getCreatureById(id)
    if creature and creature.setDrawable then
        creature:setDrawable(drawn)
    end
end

local function land(id)
    removeEvent(airborne[id])
    airborne[id] = nil
    setDrawn(id, true)
end

function clearLeapArt()
    for id in pairs(airborne) do
        land(id)
    end
end

function unregisterLeapArt()
    clearLeapArt()
    art.unregister()
end

local handlers = {}

function handlers.jump(data)
    local ms = tonumber(data.ms) or 600
    if data.f then
        art.burst('saida', data.f)
    end
    if data.t then
        art.place('sombra', data.t, ms - 10)
    end
    local id = tonumber(data.id)
    if id then
        land(id)
        setDrawn(id, false)
        airborne[id] = scheduleEvent(function()
            airborne[id] = nil
            setDrawn(id, true)
        end, ms + HIDE_SAFETY_MS)
    end
end

function handlers.land(data)
    if tonumber(data.id) then
        land(tonumber(data.id))
    end
    if data.p then
        art.burst('onda', data.p)
        art.burst('queda', data.p)
    end
end

function onLeapArt(data)
    local handler = handlers[data.k]
    if handler then
        handler(data)
    end
end
