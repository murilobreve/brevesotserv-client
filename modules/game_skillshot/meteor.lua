-- Meteoro: the designer's art v2 (images/meteoro, "Ascensao - artes v2",
-- layers.lua). The server sends two moments of a cast (scripts/skillshot,
-- fx "meteor"):
--   mark    the 3x3 mark (p) for `ms` (1.5 s): the ring closes like a
--           clock, runes turn, the rock's shadow grows; in the last 0.4 s
--           the rock falls from the upper left with its tail of fire, and
--           `n` rocks in all, `gap` ms apart (the mark stays for them)
--   impact  rock `i` lands: the flash, the ring of fire, the ball of fire
--           and smoke, rocks and sparks, the map lit and shaken; the
--           crater cools for 3 s (the server burns whoever stands there)
-- The preview's mark is 1.5 s; the rock falls from (-4, 5) to the centre.

local PREVIEW_MARK_MS = 1500
local FALL_MS = 400
local LIGHT = 199 -- fire
-- where each rock comes down, sqm from the centre (x right, y up): all
-- inside the mark, not on one another
local ROCK_SPOTS = { { 0, 0 }, { -0.4, 0.3 }, { 0.4, -0.25 } }
local DEBRIS = 0.6 -- a share of the rocks and sparks for each of several

local art = newLayerSet(3300, '/game_skillshot/images/meteoro/', 'Meteoro')
art.add('marca_relogio', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true, frames = 'clock' })
art.add('marca_runas', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
art.add('sombra', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
art.add('meteoro', { size = { 128, 128 }, anchor = { 64, 64 } })
art.add('meteoro_cauda', { size = { 256, 64 }, anchor = { 128, 32 }, additive = true })
art.add('impacto_nucleo', { size = { 256, 256 }, anchor = { 128, 128 }, additive = true })
art.add('impacto_anel', { size = { 320, 320 }, anchor = { 160, 160 }, ground = true })
art.add('impacto_fogo', { size = { 256, 256 }, anchor = { 128, 128 }, frames = 'once', ms = 750 })
art.add('cratera', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
art.add('poeira', { size = { 256, 256 }, anchor = { 128, 128 } })
for index = 1, 3 do
    art.add('rocha_' .. index, { size = { 32, 32 }, anchor = { 16, 16 } })
end
for index = 1, 2 do
    art.add('fagulha_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end

function registerMeteorArt()
    art.register()
end

-- everything it draws is timed by its curves: nothing to cancel
function clearMeteorArt()
end

function unregisterMeteorArt()
    art.unregister()
end

-- the tail: where the preview has it when the rock lands (behind it),
-- moved with the rock and as the rock (speeding up); its own fade in
local function tailKeys()
    local rock = art.keys('queda', 'meteoro') or {}
    local tail = art.keys('queda', 'meteoro_cauda') or {}
    if #rock < 2 or #tail < 2 then
        return tail
    end
    local landed, last = rock[#rock], tail[#tail]
    local behindX, behindY = last.x - landed.x, last.y - landed.y
    local keys = {}
    for index, key in ipairs(tail) do
        -- the rock's place at this time, on its own curve
        local first = rock[1]
        local x = math.max(0, math.min(1, (key.t - first.t) / (landed.t - first.t)))
        local along = x * x * x -- "entrada"
        keys[index] = {
            t = key.t, scale = key.scale, opacity = key.opacity, rot = key.rot, ease = index == 1 and 0 or landed.ease,
            x = first.x + (landed.x - first.x) * along + behindX, y = first.y + (landed.y - first.y) * along + behindY
        }
    end
    return keys
end

local handlers = {}

-- the home that puts a layer `spot` sqm off the centre
local function homeOf(rock)
    local spot = ROCK_SPOTS[(rock - 1) % #ROCK_SPOTS + 1]
    return { -spot[1], -spot[2] }
end

function handlers.mark(data)
    local center, ms = data.p, tonumber(data.ms) or PREVIEW_MARK_MS
    local rocks, gap = math.max(1, tonumber(data.n) or 1), tonumber(data.gap) or 0
    local last = ms + (rocks - 1) * gap
    -- the clock is full when the first lands; the runes stay for the others
    local timing = { moment = 'marca', scaleTime = ms / PREVIEW_MARK_MS, duration = last }
    art.play('marca_runas', center, timing)
    art.play('sombra', center, timing)
    timing.frames, timing.duration = ms, ms
    art.play('marca_relogio', center, timing)
    -- each fall in the 0.4 s before its rock lands; the tail behind the
    -- rock all the way down (in the preview's points it goes straight
    -- while the rock speeds up, and runs ahead of it)
    for rock = 1, rocks do
        local lands = ms + (rock - 1) * gap
        local home = homeOf(rock)
        art.play('meteoro_cauda', center, { keys = tailKeys(), home = home, shift = lands - FALL_MS, duration = lands })
        art.play('meteoro', center, { moment = 'queda', home = home, shift = lands - FALL_MS, duration = lands })
    end
end

function handlers.impact(data)
    local center = data.p
    local rock = tonumber(data.i)
    local home = homeOf(rock or 1)
    art.play('impacto_nucleo', center, { moment = 'impacto', home = home, light = { keys = art.lightKeys('impacto'), color = LIGHT } })
    for _, name in ipairs({ 'impacto_anel', 'impacto_fogo', 'poeira' }) do
        art.play(name, center, { moment = 'impacto', home = home })
    end
    art.play('cratera', center, { moment = 'chão', home = home })
    art.particles('impacto', center, { count = rock and DEBRIS or 1 })
    art.tremor('impacto', center)
end

function onMeteorArt(data)
    local handler = handlers[data.k]
    if handler and type(data.p) == 'table' then
        handler(data)
    end
end
