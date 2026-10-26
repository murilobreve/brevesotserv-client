-- Lanca Ricochete: the designer's art v2 (images/lanca, "Ascensao - artes
-- v2", layers.lua). The server sends each moment of a cast (scripts/
-- skillshot/paladin.lua, fx "spear"):
--   fly     the spear of light goes on a sqm, `ms` a sqm, turned to its
--           way, a golden streak behind it
--   hit     it strikes (bounce `n`, 0 to 3): a burst of light 15% bigger at
--           each bounce, golden sparks, the map lit; the third bounce's
--           star comes in strong
--   bounce  it jumps from `f` to the next one at `t` in `ms`, in an arc
--   ground  missed: it lies stuck in the ground with a glow around it for
--           `ms`, until the paladin picks it up
--   picked  he picked it up: a flash, the spear and its glow gone
-- The preview throws from (-4, 0); its bounce arcs are 3 sqm in 420 ms,
-- 1.1 sqm high.

local SPEAR_FORGET_MS = 1500
local LAST_BOUNCE = 3 -- paladin.lua's SPEAR_BOUNCES
local GROWTH = 1.15 -- a bounce's burst is this much bigger than the one before
local PREVIEW_BOUNCE_SQM, PREVIEW_BOUNCE_MS = 3, 420
local TRAIL = { name = 'rastro', length = 1.5, lag = 0.2 }
local LIGHT = layerLight('#FFC94D')

local art = newLayerSet(4300, '/game_skillshot/images/lanca/', 'Lanca')
art.add('lanca', { size = { 64, 64 }, anchor = { 32, 32 } })
art.add('rastro', { size = { 256, 32 }, anchor = { 128, 16 }, additive = true })
art.add('acerto_nucleo', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })
art.add('acerto_estrela', { size = { 192, 192 }, anchor = { 96, 96 }, additive = true })
for index = 1, 3 do
    art.add('faisca_' .. index, { size = { 32, 32 }, anchor = { 16, 16 }, additive = true })
end
art.add('chao_lanca', { size = { 64, 64 }, anchor = { 32, 32 }, ground = true })
art.add('chao_brilho', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true, ground = true })
art.add('pegou_flash', { size = { 128, 128 }, anchor = { 64, 64 }, additive = true })

local HEADS = { lanca = { face = true } }

local spears = {} -- cast id -> { flight, forget }
local grounds = {} -- cast id -> { placed, ... }

function registerSpearArt()
    art.register()
end

local function forget(id, fade)
    local spear = spears[id]
    if not spear then
        return
    end
    spears[id] = nil
    removeEvent(spear.forget)
    spear.flight.stop(fade)
end

local function pickUp(id)
    for _, placed in ipairs(grounds[id] or {}) do
        detachArt(placed)
    end
    grounds[id] = nil
end

function clearSpearArt()
    for id in pairs(spears) do
        forget(id)
    end
    for id in pairs(grounds) do
        pickUp(id)
    end
end

function unregisterSpearArt()
    clearSpearArt()
    art.unregister()
end

-- ms until the thrown spear gets there (0 when it is not flying)
local function arrival(id)
    local spear = spears[id]
    return spear and spear.flight.arrivesIn() or 0
end

-- the preview's arc made the bounce's length and time
local function arcKeys(name, length, ms)
    local keys = {}
    local high = math.min(1, length / PREVIEW_BOUNCE_SQM)
    for index, key in ipairs(art.keys('voo', name) or {}) do
        local copy = {}
        for field, value in pairs(key) do
            copy[field] = value
        end
        copy.x = key.x * length / PREVIEW_BOUNCE_SQM
        copy.y = key.y * high
        copy.t = key.t * ms / PREVIEW_BOUNCE_MS
        keys[index] = copy
    end
    return keys
end

local handlers = {}

function handlers.fly(data)
    local spear = spears[data.c]
    if not spear then
        spear = { flight = art.flight(data.f, HEADS, TRAIL) }
        spears[data.c] = spear
    end
    removeEvent(spear.forget)
    spear.forget = scheduleEvent(function()
        forget(data.c, 100)
    end, SPEAR_FORGET_MS)
    spear.flight.step(data.t, tonumber(data.ms) or 70)
end

function handlers.hit(data)
    local wait = arrival(data.c)
    forget(data.c, 60)
    local count = math.max(0, math.min(LAST_BOUNCE, tonumber(data.n) or 0))
    local grow = GROWTH ^ count
    local keys = {}
    for index, key in ipairs(art.keys('acerto', 'acerto_nucleo') or {}) do
        local copy = {}
        for field, value in pairs(key) do
            copy[field] = value
        end
        copy.scale = key.scale * grow
        keys[index] = copy
    end
    art.play('acerto_nucleo', data.p, { keys = keys, shift = wait, light = { keys = art.lightKeys('acerto'), color = LIGHT } })
    art.particles('acerto', data.p, { shift = wait, count = grow })
    if count >= LAST_BOUNCE then
        art.play('acerto_estrela', data.p, { moment = 'ultimo', shift = wait })
    end
end

function handlers.bounce(data)
    local from, to = data.f, data.t
    local ms = tonumber(data.ms) or 180
    local length = math.max(1, math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2))
    local angle = layerAngle(from, to)
    for _, name in ipairs({ 'lanca', 'rastro' }) do
        art.play(name, from, { keys = arcKeys(name, length, ms), angle = angle, face = angle })
    end
end

function handlers.ground(data)
    local wait = arrival(data.c)
    forget(data.c, 60)
    pickUp(data.c)
    local ms = tonumber(data.ms) or 6000
    -- the preview's 1.3 s made `ms`: in, the glow breathing, out at its end
    local lying = { moment = 'chão', shift = wait, scaleTime = ms / 1300 }
    grounds[data.c] = {
        art.play('chao_brilho', data.p, lying),
        art.play('chao_lanca', data.p, lying)
    }
end

function handlers.picked(data)
    pickUp(data.c)
    art.play('pegou_flash', data.p, { moment = 'pegou' })
end

function onSpearArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' and (data.p or (data.f and data.t)) then
        handler(data)
    end
end
