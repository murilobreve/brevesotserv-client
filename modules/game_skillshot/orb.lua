-- Esfera do Vazio: the designer's art (images/esfera, from "Esfera do Vazio
-- - artes v1"). The server sends each moment of a cast (scripts/skillshot/
-- sorcerer.lua, fx "orb"):
--   fly     the orb moves one sqm (through creatures) and leaves a trail
--   burst   said again: it implodes and bursts where it is (2 sqm)
--   fizzle  not said again: it comes apart at the end of its way (1 sqm)

local ORB_FORGET_MS = 1500

-- anchors: the centre of the sqm
local art = newArtSet(3800, '/game_skillshot/images/esfera/', 'Esfera')
for frame = 1, 4 do
    art.add('voo_' .. frame, 32, 0, 0)
end
art.add('rastro', 32, 0, 0, 300)
art.add('explosao', 160, 64, 64, 500)
art.add('desfazendo', 96, 32, 32, 350)

local orbs = {} -- cast id -> { head, forget }

function registerOrbArt()
    art.register()
end

local function forget(id)
    local orb = orbs[id]
    if not orb then
        return
    end
    orbs[id] = nil
    removeEvent(orb.forget)
    detachArt(orb.head)
end

function clearOrbArt()
    for id in pairs(orbs) do
        forget(id)
    end
end

function unregisterOrbArt()
    clearOrbArt()
    art.unregister()
end

local function orbOf(data)
    local orb = orbs[data.c]
    if not orb then
        orb = {}
        orbs[data.c] = orb
    end
    removeEvent(orb.forget)
    orb.forget = scheduleEvent(function()
        forget(data.c)
    end, ORB_FORGET_MS)
    return orb
end

local handlers = {}

function handlers.fly(data)
    local orb = orbOf(data)
    local from, to = data.f, data.t
    detachArt(orb.head)
    if tonumber(data.i) and tonumber(data.i) > 1 then
        art.burst('rastro', from)
    end
    local frame = ((tonumber(data.i) or 1) - 1) % 4 + 1
    local ms = tonumber(data.ms) or 150
    orb.head = art.place('voo_' .. frame, from)
    if orb.head then
        orb.head.effect:setDuration(ms)
        orb.head.effect:move(from, to)
    end
end

function handlers.burst(data)
    forget(data.c)
    art.burst('explosao', data.p)
end

function handlers.fizzle(data)
    forget(data.c)
    art.burst('desfazendo', data.p)
end

function onOrbArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' then
        handler(data)
    end
end
