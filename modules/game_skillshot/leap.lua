-- Salto do Tita: the designer's art v2 (images/salto, "Ascensao - artes v2",
-- layers.lua). The server sends (scripts/skillshot/knight.lua, fx "leap"):
--   jump  where the knight leaves (f) and lands (t), `ms` in the air: dust
--         and a ring of air where he leaves; on the landing his shadow
--         grows and the 5x5 runes light up like a clock, full when he
--         lands; the knight is not drawn meanwhile
--   land  he comes down (p): the flash, the shock wave and the cracked
--         ground (5x5), dust rolling out, rocks, the map lit and shaken
-- The preview has him leave from (-3, 0) and land on (1, 0) over 900 ms.

local HIDE_SAFETY_MS = 400 -- drawn again by then even with no landing
local PREVIEW_AIR_MS = 900
local FROM, TO = { -3, 0 }, { 1, 0 }
local LIGHT = 199 -- ember orange

local art = newLayerSet(4500, '/game_skillshot/images/salto/', 'Salto')
art.add('saida_poeira', { size = { 128, 128 }, anchor = { 64, 64 }, frames = 'once', ms = 600 })
art.add('saida_anel', { size = { 192, 192 }, anchor = { 96, 96 } })
art.add('sombra', { size = { 128, 128 }, anchor = { 64, 64 }, ground = true })
art.add('alvo_relogio', { size = { 320, 320 }, anchor = { 160, 160 }, ground = true, frames = 'clock' })
art.add('queda_nucleo', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('onda', { size = { 320, 320 }, anchor = { 160, 160 }, ground = true })
art.add('rachaduras', { size = { 320, 320 }, anchor = { 160, 160 }, ground = true })
art.add('poeira_anel', { size = { 256, 256 }, anchor = { 128, 128 }, frames = 'once', ms = 900 })
for index = 1, 3 do
    art.add('rocha_' .. index, { size = { 32, 32 }, anchor = { 16, 16 } })
end

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
        art.play('saida_poeira', data.f, { moment = 'salto', home = FROM })
        art.play('saida_anel', data.f, { moment = 'salto', home = FROM })
    end
    if data.t then
        -- the preview's 900 ms are the server's `ms`; the clock is gone when he lands
        local timing = { moment = 'salto', home = TO, scaleTime = ms / PREVIEW_AIR_MS }
        art.play('sombra', data.t, timing)
        timing.frames, timing.duration = ms, ms
        art.play('alvo_relogio', data.t, timing)
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
    local p = data.p
    if not p then
        return
    end
    art.play('queda_nucleo', p, { moment = 'queda', home = TO, light = { keys = art.lightKeys('queda'), color = LIGHT } })
    for _, name in ipairs({ 'onda', 'poeira_anel', 'rachaduras' }) do
        art.play(name, p, { moment = 'queda', home = TO })
    end
    art.particles('queda', p)
    art.tremor('queda', p)
end

function onLeapArt(data)
    local handler = handlers[data.k]
    if handler then
        handler(data)
    end
end
