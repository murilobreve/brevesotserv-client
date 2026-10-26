-- Chuva de Juizo: the designer's art v2 (images/juizo, "Ascensao - artes
-- v2", layers.lua). The server sends two moments of a cast (scripts/
-- skillshot/paladin.lua, fx "judgement"):
--   mark    the golden circle with its inscriptions on the 3x3 (p), turning
--           slowly, its arc closing like a clock in `ms` (1 s), the centre
--           pulsing; the pillar of light comes down in its last 0.2 s
--   impact  a flash, rays of light opening in a fan, a golden ring and the
--           blessed ground glowing out slowly, feathers of light falling,
--           the map lit gold
-- The preview's mark is 1 s.

local PREVIEW_MARK_MS = 1000
local PILLAR_MS = 200 -- the pillar comes down in the mark's last 0.2 s
local LIGHT = layerLight('#FFC94D')

local art = newLayerSet(3600, '/game_skillshot/images/juizo/', 'Juizo')
art.add('circulo', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
art.add('circulo_relogio', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true, frames = 'clock' })
art.add('centro', { size = { 64, 64 }, anchor = { 32, 32 }, additive = true, ground = true })
art.add('raio', { size = { 64, 384 }, anchor = { 32, 352 }, additive = true })
art.add('impacto_nucleo', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('impacto_raios', { size = { 256, 256 }, anchor = { 128, 128 }, additive = true })
art.add('impacto_anel', { size = { 256, 256 }, anchor = { 128, 128 }, ground = true })
art.add('brilho_chao', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
for index = 1, 3 do
    art.add('pena_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end

function registerJudgementArt()
    art.register()
end

-- everything it draws is timed by its curves: nothing to cancel
function clearJudgementArt()
end

function unregisterJudgementArt()
    art.unregister()
end

local handlers = {}

function handlers.mark(data)
    local center, ms = data.p, tonumber(data.ms) or PREVIEW_MARK_MS
    local timing = { moment = 'marca', scaleTime = ms / PREVIEW_MARK_MS, duration = ms }
    art.play('circulo', center, timing)
    art.play('centro', center, timing)
    timing.frames = ms
    art.play('circulo_relogio', center, timing)
    art.play('raio', center, { moment = 'raio', shift = math.max(0, ms - PILLAR_MS) })
end

function handlers.impact(data)
    local center = data.p
    art.play('impacto_nucleo', center, { moment = 'impacto', light = { keys = art.lightKeys('impacto'), color = LIGHT } })
    for _, name in ipairs({ 'impacto_raios', 'impacto_anel', 'brilho_chao' }) do
        art.play(name, center, { moment = 'impacto' })
    end
    art.particles('impacto', center)
end

function onJudgementArt(data)
    local handler = handlers[data.k]
    if handler and type(data.p) == 'table' then
        handler(data)
    end
end
