-- The Ascensão relics' art (fx "relic"), made of the paladin's golden art
-- (images/reliquia: the Chuva de Juizo's pillar, burst and ring, the
-- Flecha's trail and release, the Lanca's star, the relic's own eye) and
-- the sorcerer's void (the Esfera's implosion and blast). The server sends
-- (scripts/ascensao/05_paladin.lua and 06_sorcerer.lua):
--   dawn      Arco do Amanhecer: a beam of light from the paladin (f) along
--             its line (t, the sqm it crosses), a star on each monster it
--             hits (h) and feathers of light
--   smite     Olhar Fulminante: the eye opens over the monster (id, or its
--             sqm p when it is not seen) and a pillar of light comes down
--   smiteHit  the pillar lands where the monster died (p): a flash, rays,
--             a golden ring, feathers, the map lit gold
--   nova      Coração da Supernova: a monster the sorcerer killed (p)
--             implodes and bursts in violet over the 3x3 around it
-- The beam of curvas.csv goes 8 sqm east; each beam is made its length.

local PREVIEW_LENGTH = 8 -- sqm, the beam of curvas.csv
local LIGHT = layerLight('#FFC94D')
local VOID_LIGHT = layerLight('#9B6BFF')

local art = newLayerSet(4700, '/game_skillshot/images/reliquia/', 'Reliquia')
art.add('feixe', { size = { 384, 64 }, anchor = { 192, 32 }, additive = true })
art.add('nucleo', { size = { 256, 32 }, anchor = { 128, 16 }, additive = true })
art.add('origem', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('origem_anel', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('acerto', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('olho', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('pilar', { size = { 64, 384 }, anchor = { 32, 352 }, additive = true })
art.add('impacto', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('impacto_raios', { size = { 256, 256 }, anchor = { 128, 128 }, additive = true })
art.add('impacto_anel', { size = { 256, 256 }, anchor = { 128, 128 }, ground = true })
for index = 1, 3 do
    art.add('pena_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end
art.add('nova_implosao', { size = { 256, 256 }, anchor = { 128, 128 } })
art.add('nova_nucleo', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('nova_onda', { size = { 320, 320 }, anchor = { 160, 160 }, ground = true })

-- the images' own length in sqm (64 px each): stretched to the beam's
local NATIVE = { feixe = 6, nucleo = 4 }

function registerRelicArt()
    art.register()
end

-- everything it draws is timed by its curves: nothing to cancel
function clearRelicArt()
end

function unregisterRelicArt()
    art.unregister()
end

-- a layer's points on the preview's 8 sqm made `length`, stretched to it
local function along(name, length)
    local keys = {}
    for index, key in ipairs(art.keys('feixe', name) or {}) do
        local copy = {}
        for field, value in pairs(key) do
            copy[field] = value
        end
        copy.x = key.x * length / PREVIEW_LENGTH
        copy.stretch = length / NATIVE[name]
        keys[index] = copy
    end
    return keys
end

local function isPosition(value)
    return type(value) == 'table' and tonumber(value.x) and tonumber(value.y) and tonumber(value.z)
end

local handlers = {}

function handlers.dawn(data)
    local tiles = type(data.t) == 'table' and data.t or {}
    local last = tiles[#tiles]
    if not isPosition(data.f) or not isPosition(last) then
        return
    end
    local angle = layerAngle(data.f, last)
    local length = math.max(1, math.sqrt((last.x - data.f.x) ^ 2 + (last.y - data.f.y) ^ 2))
    art.play('feixe', data.f, { keys = along('feixe', length), angle = angle, face = angle })
    art.play('nucleo', data.f, { keys = along('nucleo', length), angle = angle, face = angle })
    art.play('origem', data.f, { moment = 'feixe', angle = angle, face = angle, light = { keys = art.lightKeys('feixe'), color = LIGHT } })
    art.play('origem_anel', data.f, { moment = 'feixe', angle = angle, face = angle })
    art.play('acerto', last, { moment = 'ponta' })
    local hits = type(data.h) == 'table' and data.h or {}
    for _, position in ipairs(hits) do
        if isPosition(position) then
            art.play('acerto', position, { moment = 'acerto' })
            art.particles('acerto', position, { count = #hits > 2 and 0.5 or 1 })
        end
    end
end

function handlers.smite(data)
    -- on the monster, so they follow it while the pillar comes down
    local monster = tonumber(data.id) and g_map.getCreatureById(tonumber(data.id))
    local target = monster or (isPosition(data.p) and data.p)
    if not target then
        return
    end
    art.play('olho', target, { moment = 'olhar' })
    art.play('pilar', target, { moment = 'olhar' })
end

function handlers.smiteHit(data)
    if not isPosition(data.p) then
        return
    end
    art.play('impacto', data.p, { moment = 'impacto', light = { keys = art.lightKeys('impacto'), color = LIGHT } })
    art.play('impacto_raios', data.p, { moment = 'impacto' })
    art.play('impacto_anel', data.p, { moment = 'impacto' })
    art.particles('impacto', data.p)
end

function handlers.nova(data)
    if not isPosition(data.p) then
        return
    end
    art.play('nova_implosao', data.p, { moment = 'nova' })
    art.play('nova_nucleo', data.p, { moment = 'nova', light = { keys = art.lightKeys('nova'), color = VOID_LIGHT } })
    art.play('nova_onda', data.p, { moment = 'nova' })
end

function onRelicArt(data)
    local handler = handlers[data.k]
    if handler then
        handler(data)
    end
end
