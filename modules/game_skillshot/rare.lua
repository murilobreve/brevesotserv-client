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
-- and the second part ("Magias do Renascimento - parte 2", sprites etapa 1):
--   mist     Pale, Mare de Bruma: the mist `t` and the safe lane `f` in front
--            of the monster at `p`, facing `d`; `ms` later the wave rolls
--            from the monster, a row every `s` ms
--   fuse     Ashen, Pavio de Cobre: the coals `ch` (each with the time `b`
--            it blows), a fuse from the monster at `p` to each; the sparks
--            set off at `lt`
--   blast    ... coal `n` blew
--   dome     Obsidian, Redoma de Vidro: the crystals `t` around `p`, the door
--            `dr`; it shuts in `ms`
--   shut     ... it shut
--   bell     Lord of Death, Dobre de Finados: the bell over the monster
--   toll     ... these rings `t` are hit in `ms` (`nx`: the next toll's)
--   knell    ... the bell tolled on `t` (`last`: the third time)
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
-- the second part
local ONDA_MS = 300
local THROW_MS, BLAST_MS, COAL_MS, COAL_FAST_MS, COAL_HURRY_MS = 500, 500, 800, 400, 900
local SHUT_MS, BREAK_MS = 500, 400
local KNELL_MS, BELL_MS, REST_MS, FAINT = 400, 500, 600, 0.3
-- the engine plays a picture's frames over any time (AttachedEffect::FramePlay)
local FRAMES_ONCE, FRAMES_LOOP, FRAMES_CLOCK = 1, 2, 3

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
-- the second part. Pale: the mist's sqm and the lane's; the wave's sqm is
-- the bottom of its file
add('rare_pale', 'mare/aviso', 32, 0, 0, 3000, true)
add('rare_pale', 'mare/fresta', 32, 0, 0, nil, true)
add('rare_pale', 'mare/onda_h', { 32, 64 }, 0, 32, ONDA_MS)
add('rare_pale', 'mare/onda_v', { 32, 64 }, 0, 32, ONDA_MS)
-- Ashen: the coal's sqm is the bottom of its files; its danger and its
-- blast are the 3x3 around it
add('rare_ashen', 'pavio/carga_arremesso', { 32, 96 }, 0, 64, THROW_MS)
add('rare_ashen', 'pavio/carga_loop', { 32, 48 }, 0, 16)
add('rare_ashen', 'pavio/area_aviso', 96, 32, 32, 3000, true)
-- the fuse: its straight piece, turned to the way of each line
add('rare_ashen', 'pavio/pavio_h', 32, 0, 0, nil, true)
-- the spark: half as big again as its file says, it is a dot in it
for frame = 1, 4 do
    add('rare_ashen', 'pavio/faisca_' .. frame, 48, 8, 8)
end
add('rare_ashen', 'pavio/estouro', 96, 32, 32, BLAST_MS)
-- Obsidian: a crystal's sqm is the bottom of its file; the floor is the 3x3
-- inside, the dome the whole 5x5
add('rare_obsidian', 'redoma/cristal_cresce', { 32, 64 }, 0, 32, 3000)
add('rare_obsidian', 'redoma/porta', { 32, 64 }, 0, 32)
add('rare_obsidian', 'redoma/miolo_aviso', 96, 32, 32, 3000, true)
add('rare_obsidian', 'redoma/fecha', 160, 64, 64, SHUT_MS)
add('rare_obsidian', 'redoma/cristal_quebra', { 32, 64 }, 0, 32, BREAK_MS)
-- Lord of Death: the bell hangs in the top half of its file, centred on
-- the monster's sqm: drawn half as big again, it hangs over the head of a
-- big monster too; a hand's sqm is the bottom of its file
add('rare_deathlord', 'dobre/sino_surge', 144, 56, 56, BELL_MS)
add('rare_deathlord', 'dobre/sino_dobra', 144, 56, 56, KNELL_MS)
add('rare_deathlord', 'dobre/sino_some', 144, 56, 56, BELL_MS)
add('rare_deathlord', 'dobre/anel_aviso', 32, 0, 0, 3000, true)
add('rare_deathlord', 'dobre/anel_golpe', { 32, 64 }, 0, 32, KNELL_MS)
add('rare_deathlord', 'dobre/anel_resto', 32, 0, 0, REST_MS, true)

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

-- a `later` event called off before it runs leaves `pending` too
local function cancel(event)
    if event then
        pending[event] = nil
        removeEvent(event)
    end
end

local function forget(id)
    local cast = casts[id]
    if not cast then
        return
    end
    casts[id] = nil
    cancel(cast.forget)
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
    cancel(cast.forget)
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

-- a picture whose frames are played over `ms` however long its file is:
-- a clock (its last frame only when the time is up), once (the last one
-- held) or in a loop; it stays `total` ms (`ms` by default)
local function timed(set, name, p, ms, mode, total)
    local placed = set.place(name, p, math.max(1, math.floor(total or ms)))
    if placed then
        placed.effect:setFramePlay(mode or FRAMES_CLOCK, math.max(1, math.floor(ms)))
    end
    return placed
end

local SQM = 32

-- a picture centred on `at` (sqm, in fractions too), turned `degrees`
-- clockwise. It goes on the sqm right and below it (and of `at` + `reach`,
-- where it moves to): the map draws the sqm from the top left and the ones
-- after would paint over it
local function placeAt(set, name, at, z, duration, degrees, reach)
    local far = reach and { x = at.x + reach.x, y = at.y + reach.y } or at
    local tile = { x = math.ceil(math.max(at.x, far.x) - 0.001), y = math.ceil(math.max(at.y, far.y) - 0.001), z = z }
    local placed = set.place(name, tile, math.max(1, math.floor(duration)))
    if not placed then
        tile = { x = math.floor(at.x + 0.5), y = math.floor(at.y + 0.5), z = z }
        placed = set.place(name, tile, math.max(1, math.floor(duration)))
    end
    if not placed then
        return nil
    end
    -- the sqm it went on (a big picture goes further down and right)
    local on = placed.tile:getPosition()
    local entry = set.entries[name]
    local ax, ay = entry.width / 2, entry.height / 2
    local effect = placed.effect
    effect:setAnchor({ x = ax, y = ay })
    effect:setOffset(math.floor(ax - SQM / 2 + (on.x - at.x) * SQM + 0.5), math.floor(ay - SQM / 2 + (on.y - at.y) * SQM + 0.5))
    if degrees then
        effect:setRotation(degrees)
    end
    return placed
end

local function spotsOf(list, z)
    local spots = {}
    for i, spot in ipairs(type(list) == 'table' and list or {}) do
        spots[i] = { x = spot.x, y = spot.y, z = spot.z or z }
    end
    return spots
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

-- ---------------------------------------------------------- the second part
-- Pale, Mare de Bruma: each row of mist darkens until the wave gets to it
local AHEAD = { [0] = { 0, -1 }, [1] = { 1, 0 }, [2] = { 0, 1 }, [3] = { -1, 0 } }

function handlers.mist(set, data)
    local p, ms, step = data.p, tonumber(data.ms) or 3000, tonumber(data.s) or 120
    local ahead = AHEAD[tonumber(data.d)]
    if not p or not ahead then
        return
    end
    local wave = ahead[1] ~= 0 and 'mare/onda_h' or 'mare/onda_v'
    local rows, last = {}, 0
    for _, spot in ipairs(spotsOf(data.t, p.z)) do
        local row = (spot.x - p.x) * ahead[1] + (spot.y - p.y) * ahead[2]
        rows[row] = rows[row] or {}
        table.insert(rows[row], spot)
        last = math.max(last, row)
        timed(set, 'mare/aviso', spot, ms + (row - 1) * step)
    end
    for row, spots in pairs(rows) do
        later(ms + (row - 1) * step, function()
            for _, spot in ipairs(spots) do
                set.burst(wave, spot)
            end
        end)
    end
    for _, spot in ipairs(spotsOf(data.f, p.z)) do
        set.place('mare/fresta', spot, ms + last * step + ONDA_MS)
    end
    tint(set, ms)
    later(ms, function()
        tintLanded(set)
    end)
end

-- Ashen, Pavio de Cobre: the coals fall, a fuse runs from the monster to
-- each one and its spark gets there when the coal blows
function handlers.fuse(set, data)
    local c, p, light = data.c, data.p, tonumber(data.lt) or 1000
    if type(c) ~= 'number' or not p then
        return
    end
    local charges = type(data.ch) == 'table' and data.ch or {}
    local lastBlast = 0
    for _, charge in ipairs(charges) do
        lastBlast = math.max(lastBlast, tonumber(charge.b) or 0)
    end
    local cast = castOf(c, lastBlast + 1500)
    cast.coals = {}
    tint(set, lastBlast)
    for index, charge in ipairs(charges) do
        local spot = { x = charge.x, y = charge.y, z = p.z }
        local blast = math.max(THROW_MS + 100, tonumber(charge.b) or 3000)
        local coal = { spot = spot }
        cast.coals[index] = coal
        set.burst('pavio/carga_arremesso', spot)
        coal.area = timed(set, 'pavio/area_aviso', spot, blast)
        -- the coal glows on the ground, faster near the blast
        local hurry = math.max(THROW_MS, blast - COAL_HURRY_MS)
        later(THROW_MS - 10, function()
            if hurry > THROW_MS then
                coal.glow = timed(set, 'pavio/carga_loop', spot, COAL_MS, FRAMES_LOOP, hurry - THROW_MS + 20)
            end
        end)
        later(hurry, function()
            coal.glow = timed(set, 'pavio/carga_loop', spot, COAL_FAST_MS, FRAMES_LOOP, blast - hurry + 150)
        end)
        -- the fuse: a straight line from the monster to the coal, a piece
        -- each sqm of it turned its way (the pieces are drawn for the 8 ways
        -- of the grid; the line is seldom one of them). The spark runs it and
        -- gets to the coal when it blows; each piece burns away once the
        -- spark has gone past it
        local dx, dy = spot.x - p.x, spot.y - p.y
        local length = math.max(1, math.sqrt(dx * dx + dy * dy))
        local ux, uy = dx / length, dy / length
        local degrees = math.deg(math.atan2(dy, dx))
        local run = blast - light
        for k = 0, math.max(1, math.floor(length)) - 1 do
            local burnt = light + math.min(1, (k + 1) / length) * run
            placeAt(set, 'pavio/pavio_h', { x = p.x + ux * (k + 0.5), y = p.y + uy * (k + 0.5) }, p.z, burnt, degrees)
        end
        local moves = math.ceil(length)
        local stepMs = math.max(1, math.floor(run / moves))
        local stride = length / moves
        for i = 1, moves do
            later(light + (i - 1) * stepMs, function()
                local from = { x = p.x + ux * stride * (i - 1), y = p.y + uy * stride * (i - 1) }
                local spark = placeAt(set, 'pavio/faisca_' .. ((i - 1) % 4 + 1), from, p.z, stepMs, nil, { x = ux * stride, y = uy * stride })
                if spark then
                    -- the brightest point of the fuse, on any floor
                    spark.effect:setAdditive(true)
                    spark.effect:setCurve(LAYER_X, { 0, 0, 0, stepMs, ux * stride * SQM, 0 })
                    spark.effect:setCurve(LAYER_Y, { 0, 0, 0, stepMs, uy * stride * SQM, 0 })
                end
            end)
        end
    end
end

function handlers.blast(set, data)
    if not data.p then
        return
    end
    tintLanded(set)
    set.burst('pavio/estouro', data.p)
    local cast = type(data.c) == 'number' and casts[data.c]
    local coal = cast and cast.coals and cast.coals[tonumber(data.n)]
    if coal then
        detachArt(coal.glow)
        detachArt(coal.area)
        coal.glow, coal.area = nil, nil
    end
end

-- Obsidian, Redoma de Vidro: crystals grow around the player, the door
-- shines, and the floor inside cracks until it shuts
function handlers.dome(set, data)
    local c, p, ms = data.c, data.p, tonumber(data.ms) or 3000
    if type(c) ~= 'number' or not p then
        return
    end
    local cast = castOf(c, ms + 1500)
    tint(set, ms)
    cast.placed.floor = timed(set, 'redoma/miolo_aviso', p, ms, FRAMES_CLOCK, ms + 100)
    for index, spot in ipairs(spotsOf(data.t, p.z)) do
        cast.placed['crystal' .. index] = timed(set, 'redoma/cristal_cresce', spot, ms, FRAMES_CLOCK, ms + 100)
    end
    if type(data.dr) == 'table' then
        local door = set.place('redoma/porta', { x = data.dr.x, y = data.dr.y, z = p.z }, ms + 100)
        if door then
            -- the way out shows in the dark of a cave too
            door.effect:setLight({ intensity = 3, color = 101 })
            cast.placed.door = door
        end
    end
end

function handlers.shut(set, data)
    if not data.p then
        return
    end
    if type(data.c) == 'number' then
        forget(data.c)
    end
    tintLanded(set)
    set.burst('redoma/fecha', data.p)
    for _, spot in ipairs(spotsOf(data.t, data.p.z)) do
        set.burst('redoma/cristal_quebra', spot)
    end
end

-- Lord of Death, Dobre de Finados: a bell over the monster tolls three
-- times; each toll's rings darken before it, the next toll's faint
local function hang(set, cast, name, p, ms)
    detachArt(cast.placed.bell)
    -- its last frame held until the next toll takes it off
    cast.placed.bell = timed(set, name, p, ms, FRAMES_ONCE, 6000)
end

function handlers.bell(set, data)
    local c, p, ms = data.c, data.p, tonumber(data.ms) or 9000
    if type(c) ~= 'number' or not p then
        return
    end
    hang(set, castOf(c, ms + 1500), 'dobre/sino_surge', p, BELL_MS)
end

function handlers.toll(set, data)
    local c, p, ms = data.c, data.p, tonumber(data.ms) or 3000
    if type(c) ~= 'number' or not p then
        return
    end
    local cast = castOf(c, ms + KNELL_MS + 6000)
    for _, placed in ipairs(cast.faint or {}) do
        detachArt(placed)
    end
    cast.marks, cast.faint = {}, {}
    for _, spot in ipairs(spotsOf(data.t, p.z)) do
        table.insert(cast.marks, timed(set, 'dobre/anel_aviso', spot, ms, FRAMES_CLOCK, ms + 100))
    end
    for _, spot in ipairs(spotsOf(data.nx, p.z)) do
        -- the first frame, faint, until its own toll comes
        local placed = timed(set, 'dobre/anel_aviso', spot, 60000, FRAMES_CLOCK, ms + KNELL_MS + 4000)
        if placed then
            placed.effect:setOpacity(FAINT)
            table.insert(cast.faint, placed)
        end
    end
    tint(set, ms)
end

function handlers.knell(set, data)
    local c, p = data.c, data.p
    if type(c) ~= 'number' or not p then
        return
    end
    local cast = castOf(c, KNELL_MS + BELL_MS + 6000)
    for _, placed in ipairs(cast.marks or {}) do
        detachArt(placed)
    end
    cast.marks = {}
    tintLanded(set)
    local spots = spotsOf(data.t, p.z)
    for _, spot in ipairs(spots) do
        set.burst('dobre/anel_golpe', spot)
    end
    later(KNELL_MS - 10, function()
        for _, spot in ipairs(spots) do
            set.burst('dobre/anel_resto', spot)
        end
    end)
    if data.last then
        detachArt(cast.placed.bell)
        cast.placed.bell = nil
        set.burst('dobre/sino_dobra', p)
        later(KNELL_MS - 10, function()
            set.burst('dobre/sino_some', p)
        end)
        castOf(c, KNELL_MS + BELL_MS)
    else
        hang(set, cast, 'dobre/sino_dobra', p, KNELL_MS)
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
