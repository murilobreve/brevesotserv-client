-- Raio Arcano: the designer's art v2 (images/raio, "Ascensao - artes v2",
-- layers.lua). The server sends (scripts/skillshot/sorcerer.lua, fx
-- "beam"):
--   charge  the sorcerer (id) starts gathering: the orb grows, the runes
--           turn and lightning crackles; full in `ms`, with a flash, and
--           held full until he lets go (or the server does)
--   fire    the whole beam at once from `f` to its last sqm in `t`: the
--           flash in his hand, the body stretched to the end, the tip; a
--           blue burst and sparks on each sqm in `h`
-- The preview charges in 1.8 s at (-4, 0) and fires 8 sqm to (4, 0).

local PREVIEW_FULL_MS = 1800
local HOLD_MS = 3500 -- sorcerer.lua's longest hold, and a little more
local PREVIEW_LENGTH = 8 -- sqm, the preview's beam
local NATIVE_LENGTH = 4 -- sqm, the body's image
local LIGHT = layerLight('#4F7BFF')

local art = newLayerSet(4400, '/game_skillshot/images/raio/', 'Raio')
art.add('carga_orbe', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('carga_runas', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
art.add('carga_raios', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true, frames = 'loop', ms = 640 })
art.add('cheia_flash', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('feixe_corpo', { size = { 256, 64 }, anchor = { 128, 32 }, additive = true })
art.add('feixe_turbulencia', { size = { 256, 64 }, anchor = { 128, 32 }, additive = true, frames = 'loop', ms = 400 })
art.add('feixe_origem', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('feixe_ponta', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('acerto_nucleo', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('acerto_anel', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
for index = 1, 3 do
    art.add('centelha_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end

local charges = {} -- creature id -> { placed, ... }

function registerBeamArt()
    art.register()
end

local function stop(id)
    local charge = charges[id]
    if not charge then
        return
    end
    charges[id] = nil
    for _, placed in ipairs(charge) do
        detachArt(placed)
    end
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

-- the beam's points for `length` sqm: the preview's 8 made `length`, the
-- body stretched to it
local function beamKeys(name, length, stretch)
    local keys = {}
    for index, key in ipairs(art.keys('feixe', name) or {}) do
        local copy = {}
        for field, value in pairs(key) do
            copy[field] = value
        end
        copy.x = key.x * length / PREVIEW_LENGTH
        if stretch then
            copy.stretch = length / NATIVE_LENGTH
        end
        keys[index] = copy
    end
    return keys
end

local handlers = {}

function handlers.charge(data)
    local id = tonumber(data.id)
    local sorcerer = id and g_map.getCreatureById(id)
    if not sorcerer then
        return
    end
    stop(id)
    local ms = tonumber(data.ms) or 1500
    local charge = {}
    charges[id] = charge
    for _, name in ipairs({ 'carga_runas', 'carga_orbe', 'carga_raios' }) do
        local keys = art.held('carga', name, PREVIEW_FULL_MS, ms, HOLD_MS)
        local placed = art.play(name, sorcerer, { keys = keys, duration = keys[#keys] and keys[#keys].t or ms })
        if placed then
            table.insert(charge, placed)
        end
    end
    -- full: a flash, and the map lit for a moment
    -- (gone with the charge if it is let go or lost before)
    table.insert(charge, art.play('cheia_flash', sorcerer, { moment = 'cheia', shift = ms, light = { keys = art.lightKeys('cheia'), color = LIGHT } }))
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
    local angle = layerAngle(data.f, last)
    local length = math.max(1, math.sqrt((last.x - data.f.x) ^ 2 + (last.y - data.f.y) ^ 2))
    art.play('feixe_corpo', data.f, { keys = beamKeys('feixe_corpo', length, true), angle = angle, face = angle })
    art.play('feixe_turbulencia', data.f, { keys = beamKeys('feixe_turbulencia', length, true), angle = angle, face = angle })
    art.play('feixe_origem', data.f, { moment = 'feixe', angle = angle })
    art.play('feixe_ponta', data.f, { keys = beamKeys('feixe_ponta', length), angle = angle, face = angle })
    for index, position in ipairs(type(data.h) == 'table' and data.h or {}) do
        local hit = { moment = 'acerto' }
        if index == 1 then
            hit.light = { keys = art.lightKeys('acerto'), color = LIGHT }
        end
        art.play('acerto_nucleo', position, hit)
        art.play('acerto_anel', position, { moment = 'acerto' })
        art.particles('acerto', position, { count = #data.h > 2 and 0.5 or 1 })
    end
end

function onBeamArt(data)
    local handler = handlers[data.k]
    if handler then
        handler(data)
    end
end
