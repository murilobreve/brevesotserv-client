-- Orbita: every Mythicus or Legendarius item a player wears is a small cut gem
-- circling the character, in the colour of the item's element.
--   - the gem's cut recalls the piece (a helmet, an amulet, an armor, a
--     shield, a weapon, a ring, legs, boots), and it circles at the height
--     of that piece: helmet and amulet round the head, armor, weapon, shield
--     and ring round the chest, legs and boots round the feet
--   - a Mythicus is the large gem with a short trail, a Legendarius the small
--     one without; lower grades show nothing
--   - the gems pass behind the character on the far half of the turn
--   - at rest the orbit is slow and faint; in combat it speeds up and lights
--   - when a bonus of an item fires, its gem flashes (my own character only)
--   - 3 Mythicus: a seal on the floor; 5: a glow in the dominant colour; a
--     full set (8): the chest turn is drawn as one ring
--
-- Who wears what comes from the server (scripts/rarity/orbit.lua), extended
-- opcode 143, JSON:
--   client -> server: { a = "hi" } at game start,
--     { a = "ask", ids = { cid, ... } } for the players that came into view,
--     { a = "hide", on = bool } (my orbit is not shown to the others)
--   server -> client: { a = "cfg", hide = bool },
--     { a = "sets", l = { { cid, "m:igneus:helmet,l:none:ring" }, ... } },
--     { a = "proc", s = "helmet,ring" }
-- A server without the script never answers and nothing is drawn.
--
-- Options (the Interface window, game_textmessage): whose orbits are drawn
-- ('all', 'mine', 'off'), Mythicus only, and hiding mine from the others.
--
-- Combat: my own character by the in-fight state; another player when their
-- health moved in the last COMBAT_MS (the server sends nothing for it).
--
-- A mounted character's orbit is lifted with the rider (MOUNT_LIFT); the seal
-- stays on the floor.
--
-- Cost: a gem is 3 to 5 image layers moved every TICK. With more than
-- LITE_FROM orbits on screen the other players' gems lose trail and flash,
-- with more than BARE_FROM the halo too, and the others move every second
-- tick: 30 players in full sets are about 250 layers, not 1000.
local OPCODE = 143
local BASE_ID = 9400 -- attached effect ids 9400 to 9999 (others: 1-24, 3000s, 3100s)
local ELEMENTS = { 'none', 'igneus', 'terrenus', 'fulmineus', 'glacialis', 'sacer', 'mortifer', 'corporalis' }
local KINDS = { 'halo', 'aura', 'orbit_front', 'orbit_back', 'seal_front', 'seal_back' }
local SLOTS = { 'helmet', 'amulet', 'armor', 'shield', 'weapon', 'ring', 'legs', 'boots' }
local SLOT_BASE = BASE_ID + 100
local SPARK_ID = BASE_ID + 590
local TICK = 33 -- ms
local COMBAT_MS = 4000
local ASK_MS = 250
local MAX_ASK = 40
local LITE_FROM, BARE_FROM = 6, 14
local MODE_KEY, MYTHIC_KEY = 'orbita_mode', 'orbita_mythic_only'

-- the orbit, in map pixels from where the creature is drawn (its tile corner)
local CENTER = { x = 9, y = 3 } -- the chest of a standing character
local SEAL = { x = 9, y = 17, w = 46, h = 20 } -- the seal on the floor, at the feet
local FULL_SET = 8
local MOUNT_LIFT = 9 -- a mounted character is drawn this much higher
-- the three turns: where on the body, how wide, and how fast against the chest's
local BANDS = {
    head = { y = -9, rx = 14, ry = 5, pace = 1.25, phase = 0.9 },
    chest = { y = 0, rx = 23, ry = 9, pace = 1, phase = 0 },
    feet = { y = 12, rx = 19, ry = 7, pace = 0.85, phase = 2.1 },
}
local BAND_OF = { helmet = 'head', amulet = 'head', armor = 'chest', shield = 'chest', weapon = 'chest', ring = 'chest', legs = 'feet', boots = 'feet' }

local supported = false
local sets = {}     -- creature id -> the set the server sent ("" for none)
local tracked = {}  -- creature id -> the orbit drawn on that creature
local trackedCount = 0
local lastHit = {}  -- creature id -> ms when its health last moved
local askQueue, askEvent = {}, nil
local hideMine = false
local event
local lastTick, tickCount = 0, 0

local function effectId(kind, element)
    return BASE_ID + ((table.find(ELEMENTS, element) or 1) - 1) * 10 + table.find(KINDS, kind)
end

local function slotCoreId(slot, element)
    return SLOT_BASE + ((table.find(SLOTS, slot) or 3) - 1) * 10 + (table.find(ELEMENTS, element) or 1)
end

local function registerImage(id, name, file)
    g_attachedEffects.remove(id)
    local effect = g_attachedEffects.registerByImage(id, name, '/game_orbita/images/' .. file, true)
    if effect then
        effect:setPermanent(true)
    end
    return effect
end

-- false on a client whose engine has no image layers (an old executable)
local function register()
    if not g_attachedEffects or not g_attachedEffects.registerByImage then
        return false
    end
    local probe
    for _, slot in ipairs(SLOTS) do
        for _, element in ipairs(ELEMENTS) do
            probe = registerImage(slotCoreId(slot, element), 'Orbita ' .. slot .. ' ' .. element, 'core_' .. slot .. '_' .. element) or probe
        end
    end
    for _, element in ipairs(ELEMENTS) do
        for _, kind in ipairs(KINDS) do
            registerImage(effectId(kind, element), 'Orbita ' .. kind .. ' ' .. element, kind .. '_' .. element)
        end
    end
    registerImage(SPARK_ID, 'Orbita spark', 'spark')
    return probe ~= nil and probe.setAdditive ~= nil and probe.setSize ~= nil and probe.setOnTop ~= nil
end

local function unregister()
    if not g_attachedEffects or not g_attachedEffects.registerByImage then
        return
    end
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

-- an image of `side` x `h` pixels centred on (x, y)
local function place(effect, x, y, side, opacity, onTop, h)
    side = math.max(1, math.floor(side + 0.5))
    local height = h and math.max(1, math.floor(h + 0.5)) or side
    effect:setSize({ width = side, height = height })
    effect:setOffset(math.floor(side / 2 - x + 0.5), math.floor(height / 2 - y + 0.5))
    effect:setOpacity(math.max(0.01, math.min(1, opacity)))
    effect:setOnTop(onTop)
end

-- options ---------------------------------------------------------------------

function getMode()
    local mode = g_settings.getString(MODE_KEY)
    return (mode == 'mine' or mode == 'off') and mode or 'all'
end

function getMythicOnly()
    return g_settings.getBoolean(MYTHIC_KEY)
end

function getHideMine()
    return hideMine
end

local function localId()
    local player = g_game.getLocalPlayer()
    return player and player:getId() or 0
end

local function wanted(cid)
    local mode = getMode()
    return supported and mode ~= 'off' and (mode == 'all' or cid == localId())
end

-- "m:igneus:helmet,l:none:ring" -> the gems to draw
local function parse(set)
    local runes, mythicOnly = {}, getMythicOnly()
    for grade, element, slot in tostring(set or ''):gmatch('([ml]):(%a+):(%a+)') do
        if (grade == 'm' or not mythicOnly) and #runes < 10 then
            runes[#runes + 1] = { grade = grade, element = table.find(ELEMENTS, element) and element or 'none',
                slot = table.find(SLOTS, slot) and slot or 'armor' }
        end
    end
    return runes
end

-- drawing ---------------------------------------------------------------------

local function detach(cid)
    local entry = tracked[cid]
    if not entry then
        return
    end
    tracked[cid] = nil
    trackedCount = trackedCount - 1
    local creature = g_map.getCreatureById(cid)
    if creature then
        for _, effect in ipairs(entry.attached) do
            creature:detachEffect(effect)
        end
    end
end

local function dominant(runes)
    local count, best, bestN = {}, runes[1].element, 0
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

local function attach(cid, creature, runes, old)
    local mine = cid == localId()
    -- many orbits on screen: the others' are drawn with fewer layers
    local lite = not mine and trackedCount >= LITE_FROM
    local bare = not mine and trackedCount >= BARE_FROM
    local entry = { runes = runes, attached = {}, mine = mine, angle = old and old.angle or math.random() * 6.28, heat = old and old.heat or 0 }
    local function add(effect)
        if effect then
            creature:attachEffect(effect)
            entry.attached[#entry.attached + 1] = effect
        end
        return effect
    end
    local mythic, inBand = 0, {}
    for _, r in ipairs(runes) do
        if r.grade == 'm' then
            mythic = mythic + 1
        end
        r.band = BAND_OF[r.slot] or 'chest'
        inBand[r.band] = (inBand[r.band] or 0) + 1
        r.index = inBand[r.band]
    end
    local main = dominant(runes)
    if mythic >= 5 and not lite then
        entry.aura = add(newLayer(effectId('aura', main), true))
    end
    if mythic >= 3 and not bare then
        entry.sealBack = add(newLayer(effectId('seal_back', main), true))
        entry.sealFront = add(newLayer(effectId('seal_front', main), true))
    end
    if mythic >= FULL_SET and not bare then
        entry.orbitBack = add(newLayer(effectId('orbit_back', main), true))
        entry.orbitFront = add(newLayer(effectId('orbit_front', main), true))
    end
    for _, r in ipairs(runes) do
        r.of = inBand[r.band]
        if r.grade == 'm' and not lite then
            r.trail = { add(newLayer(effectId('halo', r.element), true)), add(newLayer(effectId('halo', r.element), true)) }
        end
        if not bare then
            r.halo = add(newLayer(effectId('halo', r.element), true))
        end
        r.core = add(newLayer(slotCoreId(r.slot, r.element), false))
        if mine then
            r.spark = add(newLayer(SPARK_ID, true))
        end
    end
    tracked[cid] = entry
    trackedCount = trackedCount + 1
    return entry
end

-- draws (or takes away) the orbit of a creature from the set the server sent
local function rebuild(cid)
    local old = tracked[cid]
    detach(cid)
    local set = sets[cid]
    if not set or set == '' or not wanted(cid) then
        return
    end
    local creature = g_map.getCreatureById(cid)
    if not creature then
        return
    end
    local runes = parse(set)
    if #runes > 0 then
        attach(cid, creature, runes, old)
    end
end

local function rebuildAll()
    local ids = {}
    for cid in pairs(sets) do
        ids[#ids + 1] = cid
    end
    for cid in pairs(tracked) do
        if not sets[cid] then
            ids[#ids + 1] = cid
        end
    end
    for _, cid in ipairs(ids) do
        rebuild(cid)
    end
end

local function inCombat(cid, entry, now)
    if entry.mine then
        local player = g_game.getLocalPlayer()
        return player ~= nil and bit.band(player:getStates() or 0, PlayerStates.Swords) ~= 0
    end
    return (lastHit[cid] or 0) + COMBAT_MS > now
end

local function update(cid, entry, now, dt)
    -- a rider sits higher than a character on foot: looked at now and then
    entry.looked = (entry.looked or 0) + 1
    if entry.looked % 15 == 1 then
        local creature = g_map.getCreatureById(cid)
        local outfit = creature and creature:getOutfit()
        entry.lift = (outfit and (outfit.mount or 0) > 0) and MOUNT_LIFT or 0
    end
    local cx, cy0 = CENTER.x, CENTER.y - (entry.lift or 0)
    -- rest and combat blend into each other
    local target = inCombat(cid, entry, now) and 1 or 0
    entry.heat = entry.heat + (target - entry.heat) * math.min(1, dt / 450)
    local heat = entry.heat
    local period = 9000 - 5600 * heat -- ms a turn
    entry.angle = (entry.angle + dt / period * 2 * math.pi) % (40 * math.pi)
    local bright = 0.50 + 0.50 * heat
    local n = #entry.runes
    -- a crowded orbit: smaller gems and less glow, so the character shows
    local crowd = n > 5 and 0.86 or 1
    local glow = n > 5 and 0.62 or 1
    local breath = 0.5 + 0.5 * math.sin(now / 900)

    if entry.aura then
        place(entry.aura, cx, cy0 + 3, 58 + 8 * breath + 10 * heat, 0.28 + 0.12 * heat + 0.08 * breath, false)
    end
    if entry.sealBack then
        local a = 0.45 + 0.35 * heat + 0.12 * breath
        place(entry.sealBack, SEAL.x, SEAL.y, SEAL.w, a, false, SEAL.h)
        place(entry.sealFront, SEAL.x, SEAL.y, SEAL.w, a, false, SEAL.h)
    end
    if entry.orbitBack then
        local w, h = BANDS.chest.rx * 2 + 6, BANDS.chest.ry * 2 + 6
        place(entry.orbitBack, cx, cy0, w, 0.55 + 0.35 * heat, false, h)
        place(entry.orbitFront, cx, cy0, w, 0.55 + 0.35 * heat, true, h)
    end

    for i, r in ipairs(entry.runes) do
        local band = BANDS[r.band]
        local rx, ry, cy = band.rx, band.ry, cy0 + band.y
        local a = entry.angle * band.pace + band.phase + (r.index - 1) * 2 * math.pi / r.of
        local depth = math.sin(a) -- 1 nearest the viewer, -1 farthest
        local front = depth > 0
        local bob = math.sin(now / 700 + i * 1.7) * 1.2
        local x, y = cx + rx * math.cos(a), cy + ry * depth + bob
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
        if r.halo then
            place(r.halo, x, y, size * (2.3 + 0.3 * heat + 1.6 * flash), alpha * (big and 0.85 or 0.75) * glow + flash, front)
        end
        if r.spark then
            place(r.spark, x, y, size * 4.2 * flash + 1, flash, front)
        end
        if r.trail then
            for k, ghost in ipairs(r.trail) do
                local b = a - k * (0.20 + 0.10 * heat)
                local d2 = math.sin(b)
                place(ghost, cx + rx * math.cos(b), cy + ry * d2 + bob, size * (1.7 - 0.35 * k),
                    alpha * (0.55 - 0.17 * k) * (0.75 + 0.25 * heat) * glow, d2 > 0)
            end
        end
    end
end

local function tick()
    local now = g_clock.millis()
    local dt = math.min(100, now - lastTick)
    lastTick = now
    tickCount = tickCount + 1
    -- the others' orbits move every second tick once there are several
    local skipOthers = trackedCount > 4 and tickCount % 2 == 1
    local broken
    for cid, entry in pairs(tracked) do
        if entry.mine or not skipOthers then
            local step = entry.mine and dt or (trackedCount > 4 and math.min(200, now - (entry.at or now - dt)) or dt)
            entry.at = now
            local ok, err = pcall(update, cid, entry, now, step)
            if not ok then
                g_logger.error('game_orbita: ' .. tostring(err))
                broken = broken or {}
                broken[#broken + 1] = cid
            end
        end
    end
    for _, cid in ipairs(broken or {}) do
        detach(cid)
        sets[cid] = nil
    end
end

-- the server ------------------------------------------------------------------

local function send(msg)
    local protocol = g_game.getProtocolGame()
    if protocol and g_game.isOnline() then
        protocol:sendExtendedOpcode(OPCODE, json.encode(msg))
    end
end

local function flushAsk()
    askEvent = nil
    local ids = {}
    for cid in pairs(askQueue) do
        if #ids < MAX_ASK then
            ids[#ids + 1] = cid
            askQueue[cid] = nil
        end
    end
    if #ids > 0 then
        send({ a = 'ask', ids = ids })
    end
    if next(askQueue) then
        askEvent = scheduleEvent(flushAsk, ASK_MS)
    end
end

local function ask(cid)
    askQueue[cid] = true
    if not askEvent then
        askEvent = scheduleEvent(flushAsk, ASK_MS)
    end
end

local function onOpcode(protocol, opcode, buffer)
    local ok, msg = pcall(json.decode, buffer)
    if not ok or type(msg) ~= 'table' then
        return
    end
    if msg.a == 'cfg' then
        hideMine = msg.hide == true
    elseif msg.a == 'sets' and type(msg.l) == 'table' then
        for _, row in ipairs(msg.l) do
            local cid, set = type(row) == 'table' and tonumber(row[1]), type(row) == 'table' and row[2]
            if cid and type(set) == 'string' and #set <= 300 and sets[cid] ~= set then
                sets[cid] = set
                rebuild(cid)
            end
        end
    elseif msg.a == 'proc' and type(msg.s) == 'string' then
        local entry = tracked[localId()]
        if entry then
            local now = g_clock.millis()
            for slot in msg.s:gmatch('%a+') do
                for _, r in ipairs(entry.runes) do
                    if r.slot == slot then
                        r.procAt = now
                    end
                end
            end
        end
    end
end

-- creatures -------------------------------------------------------------------

local function isOtherPlayer(creature)
    return creature and creature:isPlayer() and not creature:isLocalPlayer()
end

local function onAppear(creature)
    if not supported or not isOtherPlayer(creature) or getMode() ~= 'all' then
        return
    end
    -- what they wore when last seen may have changed: asked again
    local cid = creature:getId()
    detach(cid)
    sets[cid] = nil
    ask(cid)
end

local function onDisappear(creature)
    if not creature or creature:isLocalPlayer() then
        return
    end
    local cid = creature:getId()
    detach(cid)
    sets[cid], lastHit[cid], askQueue[cid] = nil, nil, nil
end

local function onHealthPercentChange(creature)
    if creature and tracked[creature:getId()] then
        lastHit[creature:getId()] = g_clock.millis()
    end
end

local CREATURE_EVENTS = { onAppear = onAppear, onDisappear = onDisappear, onHealthPercentChange = onHealthPercentChange }

local function askVisible()
    local player = g_game.getLocalPlayer()
    if not player or getMode() ~= 'all' then
        return
    end
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), false)) do
        if isOtherPlayer(creature) and sets[creature:getId()] == nil then
            ask(creature:getId())
        end
    end
end

local function clearAll()
    local ids = {}
    for cid in pairs(tracked) do
        ids[#ids + 1] = cid
    end
    for _, cid in ipairs(ids) do
        detach(cid)
    end
    sets, lastHit, askQueue = {}, {}, {}
    removeEvent(askEvent)
    askEvent = nil
    hideMine = false
end

local function onGameStart()
    if not supported then
        return
    end
    clearAll()
    send({ a = 'hi' })
    scheduleEvent(askVisible, 600)
end

-- the options, set from the Interface window ----------------------------------

function setMode(mode)
    mode = (mode == 'mine' or mode == 'off') and mode or 'all'
    if mode == getMode() then
        return
    end
    g_settings.set(MODE_KEY, mode)
    if mode ~= 'all' then
        -- the others' sets are dropped: asked again when they are wanted
        local mine = localId()
        local ids = {}
        for cid in pairs(sets) do
            if cid ~= mine then
                ids[#ids + 1] = cid
            end
        end
        for _, cid in ipairs(ids) do
            detach(cid)
            sets[cid] = nil
        end
    end
    rebuildAll()
    if mode == 'all' then
        askVisible()
    end
end

function setMythicOnly(on)
    on = on == true
    if on == getMythicOnly() then
        return
    end
    g_settings.set(MYTHIC_KEY, on)
    rebuildAll()
end

function setHideMine(on)
    on = on == true
    if on ~= hideMine then
        hideMine = on -- the server's answer confirms it
        send({ a = 'hide', on = on })
    end
end

function isSupported()
    return supported
end

function init()
    local ok, result = pcall(register)
    supported = ok and result == true
    if not supported then
        pcall(unregister)
        return
    end
    lastTick = g_clock.millis()
    event = cycleEvent(tick, TICK)
    ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
    connect(Creature, CREATURE_EVENTS)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = clearAll })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    if not supported then
        return
    end
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = clearAll })
    disconnect(Creature, CREATURE_EVENTS)
    pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
    removeEvent(event)
    clearAll()
    unregister()
end
