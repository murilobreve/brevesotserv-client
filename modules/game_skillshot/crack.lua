-- Corte Sismico: the designer's art v2 (images/corte, "Ascensao - artes
-- v2", layers.lua). The server sends (scripts/skillshot/knight.lua, fx
-- "crack"):
--   charge  the knight (id) starts gathering: a ring of ember runes turns
--           on the ground under him and grows, the glow on him pulses
--           faster, sparks rise; full in `ms` with a flash, then held
--   stop    released (the crack follows) or lost (`lost`: he walked): the
--           charge goes; lost, it dies down where it is
--   cut     one sqm of the crack (p), the way it runs (o: h, v, ne, nw):
--           the ground splits with magma, dust and stones thrown; a burst
--           and a shock wave if it hit someone
-- The preview charges in 1.4 s and runs the crack from (-3, 0) to (2, 0).

local PREVIEW_FULL_MS = 1400
local HOLD_MS = 3500 -- knight.lua's longest hold, and a little more
local GLOW_TURN = { h = 0, v = 90, ne = -45, nw = 45 } -- the magma's glow along the crack
local LIGHT = layerLight('#FF7A2A')

local art = newLayerSet(4100, '/game_skillshot/images/corte/', 'Corte')
art.add('carga_runas', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
art.add('carga_brilho', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
for index = 1, 3 do
    art.add('carga_fagulha_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end
art.add('cheia_flash', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
for way in pairs(GLOW_TURN) do
    art.add('fenda_' .. way, { size = { 64, 64 }, anchor = { 32, 32 }, ground = true, frames = 'once', ms = 640 })
end
art.add('fenda_brilho', { size = { 64, 64 }, anchor = { 32, 32 }, additive = true, ground = true })
art.add('poeira', { size = { 128, 128 }, anchor = { 64, 64 } })
for index = 1, 3 do
    art.add('rocha_' .. index, { size = { 32, 32 }, anchor = { 16, 16 } })
end
art.add('acerto_nucleo', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('acerto_onda', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })

local charges = {} -- creature id -> { placed, ... }

function registerCrackArt()
    art.register()
end

local function stop(id)
    local charge = charges[id]
    if not charge then
        return false
    end
    charges[id] = nil
    for _, placed in ipairs(charge) do
        detachArt(placed)
    end
    return true
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
    local knight = id and g_map.getCreatureById(id)
    if not knight then
        return
    end
    stop(id)
    local ms = tonumber(data.ms) or 1500
    local charge = {}
    charges[id] = charge
    for _, name in ipairs({ 'carga_runas', 'carga_brilho' }) do
        local keys = art.held('carga', name, PREVIEW_FULL_MS, ms, HOLD_MS)
        local placed = art.play(name, knight, { keys = keys, duration = keys[#keys] and keys[#keys].t or ms })
        if placed then
            table.insert(charge, placed)
        end
    end
    art.particles('carga', knight:getPosition())
    -- (gone with the charge if it is let go or lost before)
    table.insert(charge, art.play('cheia_flash', knight, { moment = 'cheia', shift = ms, light = { keys = art.lightKeys('cheia'), color = LIGHT } }))
end

function handlers.stop(data)
    local id = tonumber(data.id)
    if not id then
        return
    end
    local knight = g_map.getCreatureById(id)
    -- lost: the charge dies down where it is (the full flash too, if it
    -- was still to come)
    if stop(id) and data.lost and knight then
        art.play('carga_runas', knight, { moment = 'cancelamento' })
        art.play('carga_brilho', knight, { moment = 'cancelamento' })
    end
end

function handlers.cut(data)
    local at, way = data.p, GLOW_TURN[data.o] and data.o or 'h'
    local cut = { moment = 'corte' }
    art.play('fenda_' .. way, at, { keys = art.keys('corte', 'fenda_h') })
    art.play('fenda_brilho', at, { moment = 'corte', face = GLOW_TURN[way] })
    art.play('poeira', at, cut)
    art.particles('corte', at)
    if data.hit then
        art.play('acerto_nucleo', at, { moment = 'acerto', light = { keys = art.lightKeys('acerto'), color = LIGHT } })
        art.play('acerto_onda', at, { moment = 'acerto' })
    end
end

function onCrackArt(data)
    local handler = handlers[data.k]
    if handler then
        handler(data)
    end
end
