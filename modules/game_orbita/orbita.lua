-- Orbita (prototype): every Mythicus or Legendarius item a player wears is a
-- small cut gem circling the character, in the colour of the item's element.
--   - a Mythicus is the large gem with a short trail, a Legendarius the small
--     one without; lower grades show nothing
--   - the gem's cut recalls the piece (a helmet, an amulet, an armor, a
--     shield, a weapon, a ring, legs, boots), and it circles at the height
--     of that piece: helmet and amulet round the head, armor, weapon, shield
--     and ring round the chest, legs and boots round the feet
--   - the gems pass behind the character on the far half of the turn
--   - at rest the orbit is slow and faint; in combat it speeds up and lights
--   - when an item's bonus fires, its gem flashes
--   - 3 Mythicus: a seal on the floor; 5: a glow in the dominant colour; a
--     full set (8): the orbit itself is drawn as one ring
-- Prototype: who wears what comes from /orbita_cmd.txt (lines appended by the
-- recording script), not from the server:
--   set <name>|<grade>:<element>:<slot>,...   grade = m (Mythicus) or l (Legendarius)
--   state <name>|combat   or   state <name>|rest
--   proc <name>|<index>
--   clear <name>
local BASE_ID = 9400
local ELEMENTS = { 'none', 'igneus', 'terrenus', 'fulmineus', 'glacialis', 'sacer', 'mortifer', 'corporalis' }
local KINDS = { 'core', 'halo', 'aura', 'orbit_front', 'orbit_back', 'seal_front', 'seal_back' }
local SLOTS = { 'helmet', 'amulet', 'armor', 'shield', 'weapon', 'ring', 'legs', 'boots' }
local SLOT_BASE = BASE_ID + 100
local SPARK_ID = BASE_ID + 990
-- the three turns: where on the body, how wide, and how fast against the chest's
local BANDS = {
    head = { y = -9, rx = 14, ry = 5, pace = 1.25, phase = 0.9 },
    chest = { y = 0, rx = 23, ry = 9, pace = 1, phase = 0 },
    feet = { y = 12, rx = 19, ry = 7, pace = 0.85, phase = 2.1 },
}
local BAND_OF = { helmet = 'head', amulet = 'head', armor = 'chest', shield = 'chest', weapon = 'chest', ring = 'chest', legs = 'feet', boots = 'feet' }
local TICK = 30 -- ms

-- the orbit, in map pixels from where the creature is drawn (its tile corner)
local CENTER = { x = 9, y = 3 }  -- the chest of a standing character
local RX, RY = 23, 9
local SEAL = { x = 9, y = 17, w = 46, h = 20 } -- the seal on the floor, at the feet
local FULL_SET = 8

local tracked = {} -- name -> entry
local event, pollEvent
local lastLine = 0

local function effectId(kind, element)
    local k, e = table.find(KINDS, kind), table.find(ELEMENTS, element) or 1
    return BASE_ID + (e - 1) * 10 + k
end

local function slotCoreId(slot, element)
    return SLOT_BASE + ((table.find(SLOTS, slot) or 3) - 1) * 10 + (table.find(ELEMENTS, element) or 1)
end

local function register()
    for _, slot in ipairs(SLOTS) do
        for _, element in ipairs(ELEMENTS) do
            local id = slotCoreId(slot, element)
            g_attachedEffects.remove(id)
            local effect = g_attachedEffects.registerByImage(id, 'Orbita ' .. slot .. ' ' .. element, '/game_orbita/images/core_' .. slot .. '_' .. element, true)
            if effect then
                effect:setPermanent(true)
            end
        end
    end
    for _, element in ipairs(ELEMENTS) do
        for _, kind in ipairs(KINDS) do
            local id = effectId(kind, element)
            g_attachedEffects.remove(id)
            local effect = g_attachedEffects.registerByImage(id, 'Orbita ' .. kind .. ' ' .. element, '/game_orbita/images/' .. kind .. '_' .. element, true)
            if effect then
                effect:setPermanent(true)
            end
        end
    end
    g_attachedEffects.remove(SPARK_ID)
    local spark = g_attachedEffects.registerByImage(SPARK_ID, 'Orbita spark', '/game_orbita/images/spark', true)
    if spark then
        spark:setPermanent(true)
    end
end

local function unregister()
    for _, slot in ipairs(SLOTS) do
        for _, element in ipairs(ELEMENTS) do
            g_attachedEffects.remove(slotCoreId(slot, element))
        end
    end
    for _, element in ipairs(ELEMENTS) do
        for _, kind in ipairs(KINDS) do
            g_attachedEffects.remove(effectId(kind, element))
        end
    end
    g_attachedEffects.remove(SPARK_ID)
end

local function newLayer(id, additive)
    local proto = g_attachedEffects.getById(id)
    if not proto then
        return nil
    end
    local effect = proto:clone()
    if additive then
        effect:setAdditive(true)
    end
    return effect
end

-- a square image of `side` pixels centred on (x, y)
local function place(effect, x, y, side, opacity, onTop, h)
    side = math.max(1, math.floor(side + 0.5))
    local height = h and math.max(1, math.floor(h + 0.5)) or side
    effect:setSize({ width = side, height = height })
    effect:setOffset(math.floor(side / 2 - x + 0.5), math.floor(height / 2 - y + 0.5))
    effect:setOpacity(math.max(0.01, math.min(1, opacity)))
    effect:setOnTop(onTop)
end

local function findCreature(name)
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end
    if player:getName() == name then
        return player
    end
    for _, c in ipairs(g_map.getSpectators(player:getPosition(), false)) do
        if c:getName() == name then
            return c
        end
    end
    return nil
end

local function detachAll(entry)
    local creature = entry.cid and g_map.getCreatureById(entry.cid)
    if creature then
        for _, effect in ipairs(entry.attached) do
            creature:detachEffect(effect)
        end
    end
    entry.attached = {}
    entry.cid = nil
end

local function dominant(runes)
    local count, best, bestN = {}, 'none', 0
    for _, r in ipairs(runes) do
        if r.grade == 'm' then
            count[r.element] = (count[r.element] or 0) + 1
            if count[r.element] > bestN then
                best, bestN = r.element, count[r.element]
            end
        end
    end
    return best
end

local function attach(entry, creature)
    entry.cid = creature:getId()
    entry.attached = {}
    local function add(effect)
        if effect then
            creature:attachEffect(effect)
            entry.attached[#entry.attached + 1] = effect
        end
        return effect
    end
    local mythic = 0
    for _, r in ipairs(entry.runes) do
        if r.grade == 'm' then
            mythic = mythic + 1
        end
    end
    local main = dominant(entry.runes)
    entry.mythic = mythic
    -- each gem's place in its own turn
    local inBand = {}
    for _, r in ipairs(entry.runes) do
        r.band = BAND_OF[r.slot] or 'chest'
        inBand[r.band] = (inBand[r.band] or 0) + 1
        r.index = inBand[r.band]
    end
    for _, r in ipairs(entry.runes) do
        r.of = inBand[r.band]
    end
    if mythic >= 5 then
        entry.aura = add(newLayer(effectId('aura', main), true))
    end
    if mythic >= 3 then
        entry.sealBack = add(newLayer(effectId('seal_back', main), true))
        entry.sealFront = add(newLayer(effectId('seal_front', main), true))
    end
    if mythic >= FULL_SET then
        entry.orbitBack = add(newLayer(effectId('orbit_back', main), true))
        entry.orbitFront = add(newLayer(effectId('orbit_front', main), true))
    end
    for _, r in ipairs(entry.runes) do
        if r.grade == 'm' then
            r.trail = { add(newLayer(effectId('halo', r.element), true)), add(newLayer(effectId('halo', r.element), true)) }
        end
        r.halo = add(newLayer(effectId('halo', r.element), true))
        r.core = add(newLayer(slotCoreId(r.slot, r.element), false))
        r.spark = add(newLayer(SPARK_ID, true))
    end
end

local function update(entry, now, dt)
    local creature = entry.cid and g_map.getCreatureById(entry.cid)
    if not creature then
        if entry.cid then
            entry.attached, entry.cid = {}, nil
        end
        return
    end
    -- rest and combat blend into each other
    local target = entry.combat and 1 or 0
    entry.heat = entry.heat + (target - entry.heat) * math.min(1, dt / 450)
    local heat = entry.heat
    local period = 9000 - 5600 * heat -- ms a turn
    entry.angle = (entry.angle + dt / period * 2 * math.pi) % (2 * math.pi)
    local bright = 0.50 + 0.50 * heat
    local n = #entry.runes
    -- a crowded orbit: smaller gems on a wider turn, so the character shows
    local crowd = n > 5 and 0.86 or 1
    local rx, ry = BANDS.chest.rx, BANDS.chest.ry
    local breath = 0.5 + 0.5 * math.sin(now / 900)

    if entry.aura then
        local side = 58 + 8 * breath + 10 * heat
        place(entry.aura, CENTER.x, CENTER.y + 3, side, 0.28 + 0.12 * heat + 0.08 * breath, false)
    end
    if entry.sealBack then
        local a = 0.45 + 0.35 * heat + 0.12 * breath
        place(entry.sealBack, SEAL.x, SEAL.y, SEAL.w, a, false, SEAL.h)
        place(entry.sealFront, SEAL.x, SEAL.y, SEAL.w, a, false, SEAL.h)
    end
    if entry.orbitBack then
        local w, h = (rx * 2 + 6) * 1.0, ry * 2 + 6
        place(entry.orbitBack, CENTER.x, CENTER.y, w, 0.55 + 0.35 * heat, false, h)
        place(entry.orbitFront, CENTER.x, CENTER.y, w, 0.55 + 0.35 * heat, true, h)
    end

    for i, r in ipairs(entry.runes) do
        local band = BANDS[r.band]
        local rx, ry, cy = band.rx, band.ry, CENTER.y + band.y
        local a = entry.angle * band.pace + band.phase + (r.index - 1) * 2 * math.pi / r.of
        local depth = math.sin(a) -- 1 nearest the viewer, -1 farthest
        local front = depth > 0
        local bob = math.sin(now / 700 + i * 1.7) * 1.2
        local x, y = CENTER.x + rx * math.cos(a), cy + ry * depth + bob
        local big = r.grade == 'm'
        local size = (big and 16 or 11) * crowd * (1 + 0.16 * depth)
        local alpha = bright * (0.72 + 0.28 * depth)
        -- the flash of a bonus that has just fired
        local flash = 0
        if r.procAt then
            local t = (now - r.procAt) / 520
            if t >= 1 then
                r.procAt = nil
            else
                flash = math.sin(t * math.pi)
            end
        end
        place(r.core, x, y, size * (1 + 0.35 * flash), math.min(1, 0.62 + 0.12 * (depth + 1) + 0.16 * heat + flash), front)
        place(r.halo, x, y, size * (2.3 + 0.3 * heat + 1.6 * flash), alpha * (big and 0.85 or 0.75) * (n > 5 and 0.62 or 1) + flash, front)
        place(r.spark, x, y, size * 4.2 * flash + 1, flash, front)
        if r.trail then
            for k, ghost in ipairs(r.trail) do
                local b = a - k * (0.20 + 0.10 * heat)
                local d2 = math.sin(b)
                place(ghost, CENTER.x + rx * math.cos(b), cy + ry * d2 + bob, size * (1.7 - 0.35 * k), alpha * (0.55 - 0.17 * k) * (0.75 + 0.25 * heat) * (n > 5 and 0.6 or 1), d2 > 0)
            end
        end
    end
end

local lastTick = 0
local function tick()
    local now = g_clock.millis()
    local dt = math.min(100, now - lastTick)
    lastTick = now
    for name, entry in pairs(tracked) do
        if not entry.cid then
            local creature = findCreature(name)
            if creature then
                attach(entry, creature)
            end
        end
        local ok, err = pcall(update, entry, now, dt)
        if not ok then
            g_logger.error('game_orbita: ' .. tostring(err))
            detachAll(entry)
            tracked[name] = nil
        end
    end
end

-- the prototype's commands ---------------------------------------------------
local function command(cmd, name, arg)
    if cmd == 'set' then
        local old = tracked[name]
        if old then
            detachAll(old)
        end
        local runes = {}
        for grade, element, slot in arg:gmatch('([ml]):(%a+):(%a+)') do
            runes[#runes + 1] = { grade = grade, element = table.find(ELEMENTS, element) and element or 'none', slot = table.find(SLOTS, slot) and slot or 'armor' }
        end
        tracked[name] = { runes = runes, attached = {}, angle = old and old.angle or 0, heat = old and old.heat or 0, combat = old and old.combat or false }
    elseif cmd == 'state' and tracked[name] then
        tracked[name].combat = arg == 'combat'
    elseif cmd == 'proc' and tracked[name] then
        local r = tracked[name].runes[tonumber(arg) or 1]
        if r then
            r.procAt = g_clock.millis()
        end
    elseif cmd == 'clear' and tracked[name] then
        detachAll(tracked[name])
        tracked[name] = nil
    end
end

local function poll()
    local ok, text = pcall(g_resources.readFileContents, '/orbita_cmd.txt')
    if not ok or type(text) ~= 'string' then
        return
    end
    local n = 0
    for line in text:gmatch('[^\r\n]+') do
        n = n + 1
        if n > lastLine then
            lastLine = n
            local cmd, name, arg = line:match('^(%a+) ([^|]+)|?(.*)$')
            if cmd then
                local ok2, err = pcall(command, cmd, name, arg or '')
                if not ok2 then
                    g_logger.error('game_orbita: ' .. tostring(err))
                end
            end
        end
    end
end

function init()
    register()
    lastTick = g_clock.millis()
    event = cycleEvent(tick, TICK)
    pollEvent = cycleEvent(poll, 100)
    connect(g_game, { onGameEnd = clearAll })
end

function clearAll()
    for _, entry in pairs(tracked) do
        detachAll(entry)
    end
    tracked = {}
end

function terminate()
    disconnect(g_game, { onGameEnd = clearAll })
    removeEvent(event)
    removeEvent(pollEvent)
    clearAll()
    unregister()
end
