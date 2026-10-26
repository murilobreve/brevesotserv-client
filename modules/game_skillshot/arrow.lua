-- Flecha do Crepusculo: the designer's art v2 (images/flecha, "Ascensao -
-- artes v2", layers.lua). The server sends each moment of a shot
-- (scripts/skillshot/paladin.lua, fx "arrow"):
--   draw   the paladin (f) draws a bow of light turned to the aim (t): the
--          string goes back in `ms` (0.4 s) and light gathers on the tip
--   loose  he lets go (f, toward t): a flash and a ring of air at the bow,
--          and the arrow of light flies up to `n` sqm at `ms` a sqm with
--          its streak behind
--   hit    near (1-7 sqm) or far (8-12, a column of light too): a burst,
--          a golden ring, feathers falling, the map lit; the halo on the
--          feet of whom it holds, for `ms`
--   miss   the arrow stuck in the ground, fading
-- The preview shoots from (-6, 0) to (6, 0) at 30 ms a sqm.

local ARROW_FORGET_MS = 1500 -- a shot with no news for this long is cleared
local PREVIEW_DRAW_MS = 400
local PREVIEW_STEP_MS = 30
local STREAK_LAG = 1.2 -- sqm the streak's middle is behind the arrow
local FROM, TO = { -6, 0 }, { 6, 0 }
local LIGHT = 205 -- gold

local art = newLayerSet(3500, '/game_skillshot/images/flecha/', 'Flecha')
for index = 1, 3 do
    art.add('arco_' .. index, { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
end
art.add('ponta_energia', { size = { 64, 64 }, anchor = { 32, 32 }, additive = true })
art.add('soltar_flash', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
art.add('soltar_anel', { size = { 128, 128 }, anchor = { 64, 64 } })
art.add('flecha', { size = { 64, 64 }, anchor = { 32, 32 }, additive = true })
art.add('rastro', { size = { 256, 32 }, anchor = { 128, 16 }, additive = true })
art.add('acerto_nucleo', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('acerto_raio', { size = { 64, 256 }, anchor = { 32, 224 }, additive = true })
art.add('acerto_anel', { size = { 192, 192 }, anchor = { 96, 96 }, ground = true })
for index = 1, 3 do
    art.add('pena_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end
art.add('preso_halo', { size = { 128, 128 }, anchor = { 64, 64 }, ground = true })
art.add('erro_cravada', { size = { 64, 64 }, anchor = { 32, 32 } })

local shots = {} -- shot id -> { placed = { ... }, angle, forget }
local held = {} -- creature id -> placed halo

function registerArrowArt()
    art.register()
end

local function forget(id)
    local shot = shots[id]
    if not shot then
        return
    end
    shots[id] = nil
    removeEvent(shot.forget)
    for _, placed in ipairs(shot.placed) do
        detachArt(placed)
    end
end

function clearArrowArt()
    for id in pairs(shots) do
        forget(id)
    end
    for id, placed in pairs(held) do
        detachArt(placed)
        held[id] = nil
    end
end

function unregisterArrowArt()
    clearArrowArt()
    art.unregister()
end

local function shotOf(data)
    local shot = shots[data.c]
    if not shot then
        shot = { placed = {}, angle = 0 }
        shots[data.c] = shot
    end
    removeEvent(shot.forget)
    shot.forget = scheduleEvent(function()
        forget(data.c)
    end, ARROW_FORGET_MS)
    return shot
end

local function keep(shot, placed)
    if placed then
        table.insert(shot.placed, placed)
    end
end

-- the arrow gone (hit or miss): the arrow and its streak off, a streak that
-- fades where it stopped
local function stop(shot, at)
    for _, placed in ipairs(shot.placed) do
        detachArt(placed)
    end
    shot.placed = {}
    local fade = {
        { t = 0, x = -STREAK_LAG, y = 0, scale = 0.9, opacity = 0.9, rot = 0, ease = 0 },
        { t = 145, x = -STREAK_LAG + 0.2, y = 0, scale = 1.1, opacity = 0, rot = 0, ease = 1 }
    }
    art.play('rastro', at, { keys = fade, angle = shot.angle, turn = true })
end

local handlers = {}

function handlers.draw(data)
    local shot = shotOf(data)
    shot.angle = layerAngle(data.f, data.t)
    local ms = tonumber(data.ms) or PREVIEW_DRAW_MS
    local timing = { moment = 'puxar', home = FROM, angle = shot.angle, turn = true, scaleTime = ms / PREVIEW_DRAW_MS }
    for _, name in ipairs({ 'arco_1', 'arco_2', 'ponta_energia' }) do
        keep(shot, art.play(name, data.f, timing))
    end
    -- fully drawn it stays until he lets go
    timing.duration = ms + 300
    keep(shot, art.play('arco_3', data.f, timing))
end

function handlers.loose(data)
    local shot = shotOf(data)
    for _, placed in ipairs(shot.placed) do
        detachArt(placed)
    end
    shot.placed = {}
    shot.angle = layerAngle(data.f, data.t)
    local step = tonumber(data.ms) or PREVIEW_STEP_MS
    local reach = math.max(1, tonumber(data.n) or 12)
    local release = { moment = 'soltar', home = FROM, angle = shot.angle, turn = true }
    art.play('soltar_flash', data.f, release)
    art.play('soltar_anel', data.f, release)
    -- the preview's 30 ms a sqm; gone where the way ends if nothing comes first
    local flight = { moment = 'voo', home = FROM, angle = shot.angle, turn = true, scaleTime = step / PREVIEW_STEP_MS, duration = reach * step + 40 }
    keep(shot, art.play('flecha', data.f, flight))
    keep(shot, art.play('rastro', data.f, flight))
end

function handlers.hit(data)
    local shot = shotOf(data)
    stop(shot, data.p)
    forget(data.c)
    local at = { moment = 'acerto', home = TO }
    art.play('acerto_nucleo', data.p, { moment = 'acerto', home = TO, light = { keys = art.lightKeys('acerto'), color = LIGHT } })
    art.play('acerto_anel', data.p, at)
    if data.far then
        art.play('acerto_raio', data.p, { moment = 'acerto longe', home = TO })
    end
    art.particles('acerto', data.p)
    local id, ms = tonumber(data.id), tonumber(data.ms)
    local creature = id and ms and g_map.getCreatureById(id)
    if creature then
        detachArt(held[id])
        -- in, held for `ms`, out at its end (the preview's 350 ms, less
        -- for a short hold)
        local out = math.min(350, ms / 3)
        local keys = {
            { t = 0, scale = 1, opacity = 0, x = 0, y = 0, rot = 0, ease = 2 },
            { t = 140, scale = 1, opacity = 0.8, x = 0, y = 0, rot = 0, ease = 2 },
            { t = math.max(150, ms - out), scale = 1, opacity = 0.75, x = 0, y = 0, rot = 0, ease = 2 },
            { t = math.max(160, ms), scale = 1, opacity = 0, x = 0, y = 0, rot = 0, ease = 2 }
        }
        held[id] = art.play('preso_halo', creature, { keys = keys })
    end
end

function handlers.miss(data)
    local shot = shotOf(data)
    stop(shot, data.p)
    forget(data.c)
    art.play('erro_cravada', data.p, { moment = 'erro', home = TO })
end

function onArrowArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' then
        handler(data)
    end
end
