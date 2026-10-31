-- Magias do Renascimento: the designer's art (images/renascimento, from
-- "Magias do Renascimento - Etapa 1 - artes v1") for the boss spells of the
-- risen monsters. The server (scripts/rarity/spells.lua) sends each moment
-- with fx "rare_<tier>":
--   cast     the monster gathers the spell for `ms` (its tier's "conjurar"),
--            then lets it go ("conjurar_fim")
--   hit      a player took it
--   tear     Pale, Lagrimas de Perola: a mark that falls in `ms`
--   splash   ... the tear fell; frost for `ms`
--   bud      Ashen, Flor de Cinza: the 3x3 bud and the petals' lines `l`
--   bloom    ... it opens and the petals run, `ms` per sqm
--   crack    Obsidian, Coroa Partida: these sqm (`t`) spike in `ms`
--            (phase `n`: the second one is faster)
--   spike    ... they spiked
--   seal     Lord of Death, Eclipse Total: the seal and its refuges `r`
--   eclipse  ... it landed
-- The files are 2x: the sizes here are half of theirs.

-- tint: the colour the map takes while a spell of the tier is coming (the
-- Lord of Death's eclipse darkens it; the others tint it in their colour)
local TIERS = {
    rare_pale = { folder = 'pale', base = 5000, tint = '#08304f' },
    rare_ashen = { folder = 'ashen', base = 5100, tint = '#3d1000' },
    rare_obsidian = { folder = 'obsidian', base = 5200, tint = '#1a0326' },
    rare_deathlord = { folder = 'lord-of-death', base = 5300, tint = '#07040a' },
}
local ROOT = '/game_skillshot/images/renascimento/'

local QUEDA_MS = 300
local GEADA_IN_MS, GEADA_OUT_MS = 250, 300
local SPIKE_MS, REST_AFTER_MS = 450, 350
local REFUGE_IN_MS = 300
local ECLIPSE_MS = 700
local DARK_WARN, DARK_PEAK = 0.28, 0.45 -- how dark the map gets for the eclipse
-- the other tiers: how strong their tint gets while the spell comes, and
-- the flash when it lands
local TINT_WARN, TINT_PEAK, TINT_OUT_MS = 0.3, 0.42, 700

-- one art set per tier: its common pieces (anchors: the centre of the
-- monster's sqm, a little up like the aura, and the player's) and its spell's
local sets = {}
for fx, tier in pairs(TIERS) do
    local set = newArtSet(tier.base, ROOT .. tier.folder .. '/', 'Renascimento ' .. tier.folder)
    set.tint = tier.tint
    sets[fx] = set
end

-- every file sits in <folder>/<spell>/: the set's names carry the spell
local function add(fx, name, ...)
    sets[fx].add(name, ...)
end

for fx in pairs(TIERS) do
    add(fx, 'comum/conjurar', 64, 16, 18)
    add(fx, 'comum/conjurar_fim', 64, 16, 18, 250)
    add(fx, 'comum/acerto', 64, 16, 16, 300)
end
-- Pale: anchors the centre of the sqm; the tear's sqm is the bottom of its file
add('rare_pale', 'lagrimas/marca', 32, 0, 0, 1600, true)
add('rare_pale', 'lagrimas/queda', { 32, 96 }, 0, 64, QUEDA_MS)
add('rare_pale', 'lagrimas/impacto', 64, 16, 16, 350)
add('rare_pale', 'lagrimas/geada_entrada', 32, 0, 0, GEADA_IN_MS, true)
add('rare_pale', 'lagrimas/geada_loop', 32, 0, 0, nil, true)
add('rare_pale', 'lagrimas/geada_saida', 32, 0, 0, GEADA_OUT_MS, true)
-- Ashen: the bud's centre, a line's sqm, the petal's sqm
add('rare_ashen', 'flor/botao', 96, 32, 32, 1500, true)
for _, way in ipairs({ 'h', 'v', 'ne', 'nw' }) do
    add('rare_ashen', 'flor/trilha_' .. way, 32, 0, 0, nil, true)
end
add('rare_ashen', 'flor/desabrocha', 160, 64, 64, 500)
for frame = 1, 4 do
    add('rare_ashen', 'flor/petala_' .. frame, 32, 0, 0)
end
-- Obsidian: the sqm; the spike's sqm is the bottom of its file
add('rare_obsidian', 'coroa/marca', 32, 0, 0, 1400, true)
add('rare_obsidian', 'coroa/marca_fase2', 32, 0, 0, 1000, true)
add('rare_obsidian', 'coroa/espinho', { 32, 64 }, 0, 32, SPIKE_MS)
add('rare_obsidian', 'coroa/resto', 32, 0, 0, 600, true)
-- Lord of Death: the seal and the eclipse are 512 px files drawn on 11x11
-- sqm around the monster; a refuge's sqm is the bottom of its column
add('rare_deathlord', 'eclipse/selo_marca', 352, 160, 160, 3000, true)
add('rare_deathlord', 'eclipse/refugio_entrada', { 32, 96 }, 0, 64, REFUGE_IN_MS)
add('rare_deathlord', 'eclipse/refugio_loop', { 32, 96 }, 0, 64)
add('rare_deathlord', 'eclipse/eclipse', 352, 160, 160, ECLIPSE_MS)

local pending = {} -- scheduled events, cancelled when the game ends
local casts = {} -- cast id -> { placed = { ... }, forget }
local darkness -- the widget that darkens the map for the eclipse
local darkEvents = {}

local function later(delay, callback)
    local event
    event = scheduleEvent(function()
        pending[event] = nil
        callback()
    end, math.max(0, delay))
    pending[event] = true
    return event
end

local function forget(id)
    local cast = casts[id]
    if not cast then
        return
    end
    casts[id] = nil
    removeEvent(cast.forget)
    for _, placed in pairs(cast.placed) do
        detachArt(placed)
    end
end

-- the pieces a cast leaves on the map until it ends (or `ms` without news)
local function castOf(id, ms)
    local cast = casts[id]
    if not cast then
        cast = { placed = {} }
        casts[id] = cast
    end
    removeEvent(cast.forget)
    cast.forget = later(ms, function()
        forget(id)
    end)
    return cast
end

local function stopDarkness()
    for _, event in ipairs(darkEvents) do
        removeEvent(event)
    end
    darkEvents = {}
    if darkness then
        darkness:destroy()
        darkness = nil
    end
end

-- the map goes from its opacity now to `to` in `ms`, in `color` (the
-- eclipse's dark by default)
local function fadeDarkness(to, ms, after, color)
    if not darkness then
        local mapPanel = modules.game_interface and modules.game_interface.getMapPanel()
        if not mapPanel then
            return
        end
        darkness = g_ui.createWidget('UIWidget', mapPanel)
        darkness:fill('parent')
        darkness:setPhantom(true)
        darkness:setFocusable(false)
        darkness:setOpacity(0)
    end
    darkness:setBackgroundColor(color or TIERS.rare_deathlord.tint)
    for _, event in ipairs(darkEvents) do
        removeEvent(event)
    end
    darkEvents = {}
    local from = darkness:getOpacity()
    local steps = math.max(1, math.floor(ms / 50))
    for step = 1, steps do
        table.insert(darkEvents, scheduleEvent(function()
            if darkness then
                darkness:setOpacity(from + (to - from) * step / steps)
            end
            if step == steps and after then
                after()
            end
        end, step * 50))
    end
end

-- the creature's "conjurar", twice as big on a big creature (a dragon),
-- around the middle of its sprite like the aura
local function attachToCreature(set, name, creature, duration)
    local placed = set.attach(name, creature, duration)
    if not placed then
        return nil
    end
    local outfit = creature.getOutfit and creature:getOutfit()
    local thingType = outfit and outfit.type > 0 and g_things.getThingType(outfit.type, ThingCategoryCreature)
    local span = thingType and math.max(1, math.min(2, math.max(thingType:getWidth(), thingType:getHeight()))) or 1
    if span > 1 then
        placed.effect:setSize({ width = 64 * span, height = 64 * span })
        placed.effect:setOffset(64 * span / 2 - 16 + (span - 1) * 16, 64 * span / 2 - 14 + (span - 1) * 16)
    end
    return placed
end

-- the map takes the tier's colour while the spell comes, flashes when it
-- lands and clears
local function tint(set, ms)
    fadeDarkness(TINT_WARN, ms, nil, set.tint)
end

local function tintLanded(set)
    fadeDarkness(TINT_PEAK, 120, function()
        fadeDarkness(0, TINT_OUT_MS, stopDarkness, set.tint)
    end, set.tint)
end

-- a mark drawn for `ms` when its picture lasts less: the picture plays in
-- the last part (it counts down to the hit) and `early` (a ground picture
-- that can loop) shows the sqm until then
local function markFor(set, name, p, ms, early)
    local own = set.entries[name].duration
    if ms <= own then
        return set.burst(name, p)
    end
    if early then
        set.place(early, p, ms - own)
    end
    later(ms - own, function()
        set.burst(name, p)
    end)
end

local handlers = {}

function handlers.cast(set, data)
    local id = tonumber(data.id)
    local ms = tonumber(data.ms) or 1000
    local creature = id and g_map.getCreatureById(id)
    if not creature then
        return
    end
    attachToCreature(set, 'comum/conjurar', creature, ms)
    later(ms, function()
        local still = g_map.getCreatureById(id)
        if still then
            attachToCreature(set, 'comum/conjurar_fim', still, 240)
        end
    end)
end

function handlers.hit(set, data)
    if data.p then
        set.burst('comum/acerto', data.p)
    end
end

function handlers.tear(set, data)
    local p, ms = data.p, tonumber(data.ms) or 1600
    markFor(set, 'lagrimas/marca', p, ms, 'lagrimas/geada_loop')
    tint(set, ms)
    later(ms - QUEDA_MS, function()
        set.place('lagrimas/queda', p, QUEDA_MS - 10)
    end)
end

function handlers.splash(set, data)
    local p, ms = data.p, tonumber(data.ms) or 2500
    tintLanded(set)
    set.burst('lagrimas/impacto', p)
    set.burst('lagrimas/geada_entrada', p)
    later(GEADA_IN_MS - 10, function()
        set.place('lagrimas/geada_loop', p, math.max(50, ms - GEADA_IN_MS - GEADA_OUT_MS))
    end)
    later(ms - GEADA_OUT_MS, function()
        set.burst('lagrimas/geada_saida', p)
    end)
end

local function sign(n)
    return n > 0 and 1 or (n < 0 and -1 or 0)
end

function handlers.bud(set, data)
    local c, p, ms = data.c, data.p, tonumber(data.ms) or 1500
    if type(c) ~= 'number' then
        return
    end
    local cast = castOf(c, ms + 2000)
    cast.lines = {}
    -- the bud pulses until it blooms
    set.place('flor/botao', p, ms)
    tint(set, ms)
    for index, line in ipairs(type(data.l) == 'table' and data.l or {}) do
        local tiles = {}
        for i, spot in ipairs(line) do
            local at = { x = spot.x, y = spot.y, z = p.z }
            local way = ART_LINE_OF[artDirection(sign(at.x - p.x), sign(at.y - p.y))]
            tiles[i] = at
            cast.placed[index .. ':' .. i] = set.place('flor/trilha_' .. way, at)
        end
        cast.lines[index] = tiles
    end
end

function handlers.bloom(set, data)
    local c, p, step = data.c, data.p, tonumber(data.ms) or 60
    tintLanded(set)
    set.burst('flor/desabrocha', p)
    local cast = type(c) == 'number' and casts[c]
    if not cast or not cast.lines then
        return
    end
    castOf(c, step * 8 + 500)
    for index, tiles in ipairs(cast.lines) do
        local first = tiles[1]
        local dx, dy = sign(first.x - p.x), sign(first.y - p.y)
        for i, to in ipairs(tiles) do
            local from = i == 1 and { x = p.x + dx, y = p.y + dy, z = p.z } or tiles[i - 1]
            later((i - 1) * step, function()
                local petal = set.place('flor/petala_' .. ((i - 1) % 4 + 1), from, step)
                if petal then
                    petal.effect:move(from, to)
                end
            end)
            -- the petal took its way: the line goes as it passes
            later(i * step, function()
                local key = index .. ':' .. i
                detachArt(cast.placed[key])
                cast.placed[key] = nil
            end)
        end
    end
end

function handlers.crack(set, data)
    local name = tonumber(data.n) == 2 and 'coroa/marca_fase2' or 'coroa/marca'
    local ms = tonumber(data.ms) or set.entries[name].duration
    for _, p in ipairs(type(data.t) == 'table' and data.t or {}) do
        markFor(set, name, p, ms, 'coroa/resto')
    end
    tint(set, ms)
end

function handlers.spike(set, data)
    tintLanded(set)
    for _, p in ipairs(type(data.t) == 'table' and data.t or {}) do
        set.burst('coroa/espinho', p)
        later(REST_AFTER_MS, function()
            set.burst('coroa/resto', p)
        end)
    end
end

function handlers.seal(set, data)
    local c, p, ms = data.c, data.p, tonumber(data.ms) or 3000
    if type(c) ~= 'number' then
        return
    end
    local cast = castOf(c, ms + ECLIPSE_MS + 1500)
    set.burst('eclipse/selo_marca', p)
    for index, spot in ipairs(type(data.r) == 'table' and data.r or {}) do
        set.burst('eclipse/refugio_entrada', spot)
        later(REFUGE_IN_MS - 10, function()
            if casts[c] ~= cast then
                return
            end
            local column = set.place('eclipse/refugio_loop', spot)
            if column then
                -- the only light left: it shows in the dark of a cave too
                column.effect:setLight({ intensity = 5, color = 179 })
                cast.placed['refugio' .. index] = column
            end
        end)
    end
    fadeDarkness(DARK_WARN, ms)
end

function handlers.eclipse(set, data)
    local c, p = data.c, data.p
    set.burst('eclipse/eclipse', p)
    fadeDarkness(DARK_PEAK, 150, function()
        fadeDarkness(0, ECLIPSE_MS + 500, stopDarkness)
    end)
    if type(c) == 'number' and casts[c] then
        castOf(c, ECLIPSE_MS)
    end
end

function registerRareArt()
    for _, set in pairs(sets) do
        set.register()
    end
end

function clearRareArt()
    for event in pairs(pending) do
        removeEvent(event)
    end
    pending = {}
    for id in pairs(casts) do
        forget(id)
    end
    stopDarkness()
end

function unregisterRareArt()
    clearRareArt()
    for _, set in pairs(sets) do
        set.unregister()
    end
end

function isRareArt(fx)
    return sets[fx] ~= nil
end

function rareArtNames()
    local names = {}
    for fx in pairs(TIERS) do
        table.insert(names, fx)
    end
    return names
end

function onRareArt(data)
    local set = sets[data.fx]
    local handler = handlers[data.k]
    if set and handler then
        handler(set, data)
    end
end
