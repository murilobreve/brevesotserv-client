-- Passo Fantasma: the designer's art v2 (images/passo, "Ascensao - artes
-- v2", layers.lua). The server sends one moment per dash (scripts/
-- skillshot/monk.lua, fx "step", k "dash"): the monk leaves a blur of ki
-- where he was (f) with jade sparks, a jade streak runs to where he lands
-- (t), the arc of the cut opens on the one he went through (p), a ring
-- and a flash where he lands, the map lit; and the bonus on him (id) for
-- as long as the chain lasts (`ms`): a ring of ki at his feet and flames
-- around him, bigger at each level (n, 1 to 4).

local LEVELS = { 0.7, 0.85, 1.05, 1.25 } -- runtime.json's bonus levels
local AURA_OPACITY = { 0.65, 0.8, 0.9, 1 }
local FLAME_OPACITY = { 0.6, 0.75, 0.9, 1 }
local NATIVE_LENGTH = 4 -- sqm, the streak's image
local PREVIEW_DASH_SQM = 7
local LIGHT = layerLight('#5FD1B0')

local art = newLayerSet(4200, '/game_skillshot/images/passo/', 'Passo')
art.add('saida_vulto', { size = { 128, 128 }, anchor = { 64, 64 } })
for index = 1, 2 do
    art.add('fagulha_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end
art.add('rastro', { size = { 256, 32 }, anchor = { 128, 16 }, additive = true })
art.add('corte', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('chegada_anel', { size = { 128, 128 }, anchor = { 64, 64 }, ground = true })
art.add('chegada_flash', { size = { 96, 96 }, anchor = { 48, 48 }, additive = true })
art.add('bonus_aura', { size = { 96, 96 }, anchor = { 48, 48 }, ground = true })
art.add('bonus_chama', { size = { 96, 96 }, anchor = { 48, 48 }, additive = true, frames = 'loop', ms = 640 })

local bonuses = {} -- creature id -> { placed, ... }

function registerStepArt()
    art.register()
end

local function drop(id)
    for _, placed in ipairs(bonuses[id] or {}) do
        detachArt(placed)
    end
    bonuses[id] = nil
end

function clearStepArt()
    for id in pairs(bonuses) do
        drop(id)
    end
end

function unregisterStepArt()
    clearStepArt()
    art.unregister()
end

-- the bonus at its level for `ms`: in, held, out at the end
local function bonusKeys(scale, opacity, ms)
    return {
        { t = 0, scale = scale * 0.93, opacity = 0, x = 0, y = 0, rot = 0, ease = 2 },
        { t = 100, scale = scale, opacity = opacity, x = 0, y = 0, rot = 0, ease = 2 },
        { t = math.max(110, ms - 400), scale = scale, opacity = opacity * 0.9, x = 0, y = 0, rot = 0, ease = 0 },
        { t = math.max(120, ms), scale = scale, opacity = 0, x = 0, y = 0, rot = 0, ease = 2 }
    }
end

local handlers = {}

function handlers.dash(data)
    local from, to = data.f, data.t
    if type(from) ~= 'table' or type(to) ~= 'table' then
        return
    end
    art.play('saida_vulto', from, { moment = 'saída' })
    art.particles('saída', from)
    local angle = layerAngle(from, to)
    local length = math.max(1, math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2))
    local keys = {}
    for index, key in ipairs(art.keys('avanço', 'rastro') or {}) do
        local copy = {}
        for field, value in pairs(key) do
            copy[field] = value
        end
        copy.x = key.x * length / PREVIEW_DASH_SQM
        copy.stretch = length / NATIVE_LENGTH
        keys[index] = copy
    end
    art.play('rastro', from, { keys = keys, angle = angle, face = angle })
    if type(data.p) == 'table' then
        art.play('corte', data.p, { moment = 'corte', face = angle })
    end
    art.play('chegada_anel', to, { moment = 'chegada' })
    art.play('chegada_flash', to, { moment = 'chegada', light = { keys = art.lightKeys('chegada'), color = LIGHT } })
    local id, level = tonumber(data.id), tonumber(data.n)
    local monk = id and g_map.getCreatureById(id)
    if monk and level and level >= 1 then
        drop(id)
        level = math.min(level, #LEVELS)
        local ms = tonumber(data.ms) or 4000
        bonuses[id] = {
            art.play('bonus_aura', monk, { keys = bonusKeys(LEVELS[level], AURA_OPACITY[level], ms) }),
            art.play('bonus_chama', monk, { keys = bonusKeys(LEVELS[level], FLAME_OPACITY[level], ms) })
        }
    end
end

function onStepArt(data)
    local handler = handlers[data.k]
    if handler then
        handler(data)
    end
end
