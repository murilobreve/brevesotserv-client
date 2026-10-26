-- Translocacao: the designer's art v2 (images/translocacao, "Ascensao -
-- artes v2", layers.lua). The server sends one moment
-- (scripts/ascensao/06_sorcerer.lua, fx "transloc"):
--   jump   the sorcerer goes from `f` to `t` (up to 3 sqm) at once: a rune
--          circle closes on him and a point of light swallows him, an
--          arcane streak runs to where he lands, and there a circle opens
--          with a flash, the map lit blue, runes floating up
-- The preview jumps 8 sqm, from (-4, 0) to (4, 0).

local PREVIEW_LENGTH = 8
local NATIVE_LENGTH = 4 -- sqm, the streak's image
local ARRIVAL_MS = 60 -- the circle opens as the streak gets there
local LIGHT = layerLight('#4F7BFF')

local art = newLayerSet(5400, '/game_skillshot/images/translocacao/', 'Translocacao')
art.add('saida_anel', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
art.add('saida_nucleo', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('rastro', { size = { 256, 32 }, anchor = { 128, 16 }, additive = true })
art.add('chegada_anel', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
art.add('chegada_flash', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
for index = 1, 2 do
    art.add('runa_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end

function registerTranslocArt()
    art.register()
end

-- everything it draws is timed by its curves: nothing to cancel
function clearTranslocArt()
end

function unregisterTranslocArt()
    art.unregister()
end

-- the streak's points for `length` sqm, stretched to it
local function streakKeys(length)
    local keys = {}
    for index, key in ipairs(art.keys('trajeto', 'rastro') or {}) do
        local copy = {}
        for field, value in pairs(key) do
            copy[field] = value
        end
        copy.x = key.x * length / PREVIEW_LENGTH
        copy.stretch = length / NATIVE_LENGTH
        keys[index] = copy
    end
    return keys
end

local handlers = {}

function handlers.jump(data)
    local from, to = data.f, data.t
    art.play('saida_anel', from, { moment = 'saída' })
    art.play('saida_nucleo', from, { moment = 'saída' })
    local angle = layerAngle(from, to)
    local length = math.max(1, math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2))
    art.play('rastro', from, { keys = streakKeys(length), angle = angle, face = angle })
    local arrival = { moment = 'chegada', shift = ARRIVAL_MS }
    art.play('chegada_anel', to, arrival)
    art.play('chegada_flash', to, { moment = 'chegada', shift = ARRIVAL_MS, light = { keys = art.lightKeys('chegada'), color = LIGHT } })
    art.particles('chegada', to, { shift = ARRIVAL_MS })
end

function onTranslocArt(data)
    local handler = handlers[data.k]
    if handler and type(data.f) == 'table' and type(data.t) == 'table' then
        handler(data)
    end
end
