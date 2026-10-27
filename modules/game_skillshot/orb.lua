-- Esfera do Vazio: the designer's art v2 (images/esfera, "Ascensao - artes
-- v2", layers.lua). The server sends each moment of a cast (scripts/
-- skillshot/sorcerer.lua, fx "orb"):
--   fly     the orb goes on a sqm (through creatures), `ms` a sqm: the dark
--           core, its turning ring and glow, a trail of void behind
--   burst   said again: where it is, the void implodes and bursts (2 sqm),
--           dark fragments thrown out, the map lit violet
--   fizzle  not said again: it comes apart at the end of its way
-- The preview flies from (-4, 0) at 150 ms a sqm; the burst is at (2, 0).

local ORB_FORGET_MS = 1500
local IMPLODE_MS = 260 -- the preview's implosion, then the burst
local TRAIL = { name = 'rastro', length = 3, lag = 0.2 }
local LIGHT = layerLight('#6B2BD9') -- violet

local art = newLayerSet(3800, '/game_skillshot/images/esfera/', 'Esfera')
art.add('esfera', { size = { 64, 64 }, anchor = { 32, 32 } })
art.add('esfera_anel', { size = { 128, 128 }, anchor = { 64, 64 } })
art.add('esfera_brilho', { size = { 96, 96 }, anchor = { 48, 48 }, additive = true })
art.add('rastro', { size = { 256, 32 }, anchor = { 128, 16 }, additive = true })
art.add('implosao', { size = { 256, 256 }, anchor = { 128, 128 } })
art.add('explosao_nucleo', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('explosao_onda', { size = { 320, 320 }, anchor = { 160, 160 }, ground = true })
art.add('desfazendo', { size = { 128, 128 }, anchor = { 64, 64 }, frames = 'once', ms = 640 })
for index = 1, 3 do
    art.add('fragmento_' .. index, { size = { 32, 32 }, anchor = { 16, 16 } })
end

-- the ring turns as it flies (the preview's half turn in 900 ms)
local HEADS = {
    esfera = {},
    esfera_anel = { keys = { { t = 0, scale = 1, rot = 0 }, { t = 900, scale = 1, rot = 180 } } },
    esfera_brilho = {}
}

local orbs = {} -- cast id -> { flight, forget }

function registerOrbArt()
    art.register()
end

local function forget(id, fade)
    local orb = orbs[id]
    if not orb then
        return
    end
    orbs[id] = nil
    removeEvent(orb.forget)
    orb.flight.stop(fade)
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

local handlers = {}

function handlers.fly(data)
    local orb = orbs[data.c]
    if not orb then
        orb = { flight = art.flight(data.f, HEADS, TRAIL) }
        orbs[data.c] = orb
    end
    removeEvent(orb.forget)
    orb.forget = scheduleEvent(function()
        forget(data.c, 150)
    end, ORB_FORGET_MS)
    orb.flight.step(data.t, tonumber(data.ms) or 150)
end

function handlers.burst(data)
    forget(data.c)
    local center = data.p
    art.play('implosao', center, { moment = 'implosão', light = { keys = art.lightKeys('implosão'), color = LIGHT } })
    local burst = { moment = 'explosão', shift = IMPLODE_MS }
    art.play('explosao_nucleo', center, { moment = 'explosão', shift = IMPLODE_MS, light = { keys = art.lightKeys('explosão'), color = LIGHT } })
    art.play('explosao_onda', center, burst)
    art.particles('explosão', center, { shift = IMPLODE_MS })
end

function handlers.fizzle(data)
    forget(data.c, 120)
    art.play('desfazendo', data.p, { moment = 'fim' })
end

function onOrbArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' and (data.p or (data.f and data.t)) then
        handler(data)
    end
end
