-- The skillshots' art v2 ("Ascensao - artes v2"): a spell is a few layers,
-- images the client animates by the designer's curves, turned to the way
-- the spell goes, the glows added over what is under them, and particles
-- thrown with speed and gravity. Each spell's folder has the images (2x:
-- 64 px = 1 sqm), curvas.csv and particulas.csv as the designer delivers
-- them; the engine (AttachedEffect:setCurve and the rest, UIMap:shake)
-- evaluates it all in draw(), with no Lua per frame.
--   set = newLayerSet(base, path, label)
--   set.add(name, spec)  spec, in the file's pixels: size { w, h }, anchor
--                        { x, y } (the point put on the sqm, the turning
--                        point), additive (a glow), ground (under the
--                        creatures), frames ('once', 'loop', 'clock')
--   set.register(), set.unregister()
--   warmUpLayers(position)  every image of every set drawn once, unseen
--   set.keys(moment, name)  the layer's points in curvas.csv: { t, scale,
--                        opacity, x, y (sqm, y up), rot (degrees, the
--                        designer's way: counterclockwise), ease }
--   set.play(name, target, opts) -> placed   target: a position or a
--                        creature; opts:
--     keys      the points (default: the layer's in curvas.csv)
--     home      where `target` is in the designer's preview { x, y } (sqm):
--               the points' x and y count from there
--     angle     the spell's way, degrees clockwise from east: the x of the
--               points goes along it; turn = true also turns the image
--               (flipped going west, so it stays the right way up)
--     shift     ms added to every point (it comes in later)
--     scaleTime the points' times multiplied (the preview's 900 ms clock
--               is the server's `ms`)
--     duration  how long it stays (default: its last point)
--     frames    ms the frames take ('once', 'loop', 'clock' layers)
--     light     the moment's map light: { keys, color }
--   set.update(placed, keys, opts)  new points for a layer already placed
--                        (its clock keeps going: a streak that follows a
--                        flight it learns step by step)
--   set.lightKeys(moment), set.tremor(moment, position)
--   set.particles(moment, position, opts) -> { placed, ... }  the rows of
--                        particulas.csv for the moment; opts.angle,
--                        opts.count (a share of it), opts.shift (ms later)
-- placed is { tile, effect } (detachArt takes it off).

LAYER_SCALE, LAYER_STRETCH, LAYER_OPACITY, LAYER_X, LAYER_Y, LAYER_ROTATION, LAYER_LIGHT = 0, 1, 2, 3, 4, 5, 6
local EASES = { linear = 0, entrada = 1, saida = 2, entrada_saida = 3, saida_forte = 4, estouro = 5 }
local FRAMES = { once = 1, loop = 2, clock = 3 }
local DRAW_ON_GROUND, DRAW_OVER_ALL = 1, 4 -- the draw pool's SECOND and FIFTH
local SQM = 32
local TREMOR = { leve = 2, medio = 3, ['médio'] = 3, forte = 4 }
local TREMOR_REACH = 6 -- sqm from the player: a blow farther off does not shake his screen

local function trim(text)
    return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function split(line)
    local fields = {}
    for field in (line .. ';'):gmatch('([^;]*);') do
        fields[#fields + 1] = trim(field)
    end
    return fields
end

-- the rows of a ';' csv after its header, as tables by the header's names
local function readCsv(file)
    local ok, text = pcall(g_resources.readFileContents, file)
    if not ok or not text then
        return {}
    end
    text = text:gsub('^\239\187\191', ''):gsub('\r', '')
    local rows, header = {}, nil
    for line in text:gmatch('[^\n]+') do
        local fields = split(line)
        if not header then
            header = fields
        elseif #fields > 1 then
            local row = {}
            for index, name in ipairs(header) do
                row[name] = fields[index] or ''
            end
            rows[#rows + 1] = row
        end
    end
    return rows
end

-- "a-b" -> a, b (one number: both)
local function range(text)
    local a, b = tostring(text or ''):match('^%s*([%d%.]+)%s*%-%s*([%d%.]+)%s*$')
    if a then
        return tonumber(a), tonumber(b)
    end
    local n = tonumber(text) or 0
    return n, n
end

local function between(text)
    local a, b = range(text)
    return a + math.random() * (b - a)
end

-- "pena_1..3" -> { pena_1, pena_2, pena_3 }
local function images(text)
    local prefix, first, last = text:match('^(.-)(%d+)%.%.(%d+)$')
    if not prefix then
        return { text }
    end
    local names = {}
    for index = tonumber(first), tonumber(last) do
        names[#names + 1] = prefix .. index
    end
    return names
end

local function flat(keys, value)
    local out = {}
    for _, key in ipairs(keys) do
        out[#out + 1] = key.t
        out[#out + 1] = value(key)
        out[#out + 1] = key.ease or 0
    end
    return out
end

local function anyOf(keys, value)
    for _, key in ipairs(keys) do
        if math.abs(value(key)) > 0.001 then
            return true
        end
    end
    return false
end

local layerSets = {}

function newLayerSet(base, path, label)
    local set = { entries = {}, count = 0 }
    table.insert(layerSets, set)
    local curves, lights, tremors, particles = {}, {}, {}, {}

    for _, row in ipairs(readCsv(path .. 'curvas.csv')) do
        local moment, name = row.momento, row.camada
        local key = {
            t = tonumber(row.t_ms) or 0,
            ease = EASES[row.suavizacao] or EASES.saida
        }
        if name == '(luz do mapa)' then
            key.value = tonumber(row.luz) or 0
            lights[moment] = lights[moment] or {}
            table.insert(lights[moment], key)
        elseif name == '(tremor)' then
            local strength, ms = row.suavizacao:match('^(%S+)%s+(%d+)')
            tremors[moment] = { strength = TREMOR[strength or ''] or TREMOR.leve, ms = tonumber(ms) or 120 }
        else
            key.scale = tonumber(row.escala) or 1
            key.opacity = tonumber(row.opacidade) or 1
            key.x = tonumber(row.x_sqm) or 0
            key.y = tonumber(row.y_sqm) or 0
            key.rot = tonumber(row.rotacao_graus) or 0
            curves[moment] = curves[moment] or {}
            curves[moment][name] = curves[moment][name] or {}
            table.insert(curves[moment][name], key)
        end
    end
    for _, row in ipairs(readCsv(path .. 'particulas.csv')) do
        particles[row.momento] = particles[row.momento] or {}
        table.insert(particles[row.momento], row)
    end

    function set.add(name, spec)
        set.count = set.count + 1
        spec.id = base + set.count
        set.entries[name] = spec
    end

    function set.register()
        for name, entry in pairs(set.entries) do
            g_attachedEffects.remove(entry.id)
            g_textures.preload(path .. name, true)
            local effect = g_attachedEffects.registerByImage(entry.id, label .. ' ' .. name, path .. name, true)
            if effect then
                local w, h = entry.size[1] / 2, entry.size[2] / 2
                local ax, ay = entry.anchor[1] / 2, entry.anchor[2] / 2
                effect:setSize({ width = w, height = h })
                -- the anchor on the centre of the sqm
                effect:setOffset(ax - SQM / 2, ay - SQM / 2)
                effect:setAnchor({ x = ax, y = ay })
                if entry.additive then
                    effect:setAdditive(true)
                end
                if entry.ground then
                    effect:setOnTop(false)
                    effect:setDrawOrder(DRAW_ON_GROUND)
                else
                    effect:setOnTop(true)
                    effect:setDrawOrder(DRAW_OVER_ALL)
                end
            end
        end
    end

    function set.unregister()
        for _, entry in pairs(set.entries) do
            g_attachedEffects.remove(entry.id)
        end
    end

    function set.keys(moment, name)
        return (curves[moment] or {})[name]
    end

    function set.lightKeys(moment)
        return lights[moment]
    end

    -- the screen trembles for a heavy blow near the player
    function set.tremor(moment, position)
        local tremor = tremors[moment]
        local player = g_game.getLocalPlayer()
        local mapPanel = modules.game_interface and modules.game_interface.getMapPanel()
        if not tremor or not player or not mapPanel or not mapPanel.shake then
            return
        end
        local at = player:getPosition()
        if at.z == position.z and math.max(math.abs(at.x - position.x), math.abs(at.y - position.y)) <= TREMOR_REACH then
            mapPanel:shake(tremor.strength, tremor.ms)
        end
    end

    -- the points on the layer's curves; the time of the last one
    local function apply(effect, keys, opts)
        local shift, scaleTime = opts.shift or 0, opts.scaleTime or 1
        local home = opts.home or { 0, 0 }
        local angle = math.rad(opts.angle or 0)
        local along, across = math.cos(angle), math.sin(angle)
        local timed = {}
        for index, key in ipairs(keys) do
            -- x along the spell's way, y straight up the screen
            local dx, up = (key.x - home[1]) * SQM, (key.y - home[2]) * SQM
            timed[index] = {
                t = key.t * scaleTime + shift, ease = key.ease, scale = key.scale, opacity = key.opacity,
                px = dx * along, py = dx * across - up, rot = -key.rot
            }
        end
        effect:setCurve(LAYER_SCALE, flat(timed, function(k) return k.scale end))
        effect:setCurve(LAYER_OPACITY, flat(timed, function(k) return k.opacity end))
        if anyOf(timed, function(k) return k.px end) then
            effect:setCurve(LAYER_X, flat(timed, function(k) return k.px end))
        end
        if anyOf(timed, function(k) return k.py end) then
            effect:setCurve(LAYER_Y, flat(timed, function(k) return k.py end))
        end
        if anyOf(timed, function(k) return k.rot end) then
            effect:setCurve(LAYER_ROTATION, flat(timed, function(k) return k.rot end))
        end
        local last = timed[#timed].t
        if opts.light and opts.light.keys then
            local lightKeys = {}
            for _, key in ipairs(opts.light.keys) do
                lightKeys[#lightKeys + 1] = { t = key.t * scaleTime + shift, ease = key.ease, value = key.value }
                last = math.max(last, lightKeys[#lightKeys].t)
            end
            effect:setLight({ color = opts.light.color or 215, intensity = 0 })
            effect:setCurve(LAYER_LIGHT, flat(lightKeys, function(k) return k.value end))
        end
        return last
    end

    function set.play(name, target, opts)
        opts = opts or {}
        local entry = set.entries[name]
        local keys = opts.keys or set.keys(opts.moment or '', name)
        if not entry or not keys or #keys == 0 or not target then
            return nil
        end
        local holder = target
        if not target.attachEffect then
            holder = g_map.getTile(target)
        end
        local effect = holder and g_attachedEffects.getById(entry.id)
        if not effect then
            return nil
        end
        local last = apply(effect, keys, opts)
        if opts.turn then
            local degrees = opts.angle or 0
            effect:setRotation(degrees)
            -- going west it would be upside down: drawn flipped instead
            if math.cos(math.rad(degrees)) < -0.01 then
                effect:setFlipped(true)
            end
        end
        if entry.frames then
            effect:setFramePlay(FRAMES[entry.frames] or FRAMES.once, opts.frames or entry.ms or 600)
        end
        effect:setDuration(math.max(1, math.floor(opts.duration or last)))
        holder:attachEffect(effect)
        return { tile = holder, effect = effect }
    end

    function set.update(placed, keys, opts)
        if placed and placed.effect and keys and #keys > 0 then
            apply(placed.effect, keys, opts or {})
        end
    end

    -- the rows of particulas.csv for a moment, thrown from `position`
    function set.particles(moment, position, opts)
        opts = opts or {}
        local thrown = {}
        local tile = g_map.getTile(position)
        if not tile then
            return thrown
        end
        for _, row in ipairs(particles[moment] or {}) do
            local names = images(row.imagem)
            local count = math.floor((tonumber(row.quantidade) or 0) * (opts.count or 1) + 0.5)
            local spread = math.rad(tonumber(row.espalhamento_graus) or 360)
            local delay = (tonumber(row.atraso_ms) or 0) + (opts.shift or 0)
            local gravity = (tonumber(row.gravidade_sqm_s2) or 0) * SQM
            local spins = row.gira == 'sim'
            for index = 1, count do
                local name = names[(index - 1) % #names + 1]
                local entry = set.entries[name]
                local effect = entry and g_attachedEffects.getById(entry.id)
                if effect then
                    local life = between(row.vida_ms)
                    local speed = between(row.velocidade_sqm_s) * SQM
                    local way = math.rad(opts.angle or 0) + (math.random() - 0.5) * spread
                    local rise = between(row.subida_sqm_s) * SQM
                    local size = between(row.tamanho)
                    -- on the ground the spread is seen from above at a slant:
                    -- half as deep as it is wide; then thrown up
                    effect:setMotion(math.cos(way) * speed, math.sin(way) * speed / 2 - rise, gravity,
                        spins and (math.random() < 0.5 and -1 or 1) * (180 + math.random() * 360) or 0)
                    local keys = {
                        { t = delay, value = 0, ease = 0 },
                        { t = delay + 40, value = 1, ease = EASES.saida },
                        { t = delay + life * 0.6, value = 1, ease = 0 },
                        { t = delay + life, value = 0, ease = EASES.entrada }
                    }
                    effect:setCurve(LAYER_OPACITY, flat(keys, function(k) return k.value end))
                    effect:setCurve(LAYER_SCALE, { delay, size, 0 })
                    effect:setDuration(math.floor(delay + life))
                    tile:attachEffect(effect)
                    thrown[#thrown + 1] = { tile = tile, effect = effect }
                end
            end
        end
        return thrown
    end

    -- every image drawn once, unseen (see warmUpArt)
    function set.warmUp(position)
        local tile = g_map.getTile(position)
        if not tile then
            return
        end
        for _, entry in pairs(set.entries) do
            local effect = g_attachedEffects.getById(entry.id)
            if effect then
                effect:setCurve(LAYER_OPACITY, { 0, 0.01, 0 })
                effect:setDuration(1000)
                tile:attachEffect(effect)
            end
        end
    end

    return set
end

-- see warmUpArt: the first draw of a texture is what costs
function warmUpLayers(position)
    for _, set in ipairs(layerSets) do
        set.warmUp(position)
    end
end

-- the way from one sqm to another, degrees clockwise from east
function layerAngle(from, to)
    return math.deg(math.atan2(to.y - from.y, to.x - from.x))
end
