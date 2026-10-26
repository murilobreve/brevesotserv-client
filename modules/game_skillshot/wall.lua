-- Muralha Glacial: the designer's art v2 (images/muralha, "Ascensao - artes
-- v2", layers.lua). The server blocks the wall's sqm with an invisible wall
-- and sends (scripts/skillshot/druid.lua, fx "wall"):
--   up     the sqm and the way it runs (ns, eo, ne, nw) and how long it
--          stands: each block springs from the ground with a jolt and
--          splinters, a glow runs inside the ice, cracks come in its last
--          second and it bursts into splinters and mist
--   chill  the frost on the feet of what stands next to it
--   down   a boss came next to it: the blocks burst now, before their time
-- All of a block's moments are placed when it rises, timed by their
-- curves; "down" takes off what had not come yet and bursts it at once.

local RISE_MS = 250 -- the block springs up in this long
local CRACK_MS = 1000 -- the cracks come in the block's last second
local GLOW_CYCLE_MS = 2550 -- the glow's pulse in the preview, again and again
local SHARDS = 0.4 -- a share of the splinters for each block (5 blocks)
local LIGHT = 137 -- ice blue

local art = newLayerSet(3700, '/game_skillshot/images/muralha/', 'Muralha')
for _, way in ipairs({ 'ns', 'eo', 'ne', 'nw' }) do
    art.add('pilar_' .. way, { size = { 64, 128 }, anchor = { 32, 96 } })
    art.add('rachaduras_' .. way, { size = { 64, 128 }, anchor = { 32, 96 } })
end
art.add('pilar_brilho', { size = { 64, 128 }, anchor = { 32, 96 }, additive = true })
art.add('quebra', { size = { 128, 128 }, anchor = { 64, 96 }, frames = 'once', ms = 600 })
art.add('nevoa', { size = { 128, 128 }, anchor = { 64, 64 } })
art.add('frio', { size = { 64, 64 }, anchor = { 32, 32 }, ground = true })
for index = 1, 3 do
    art.add('lasca_' .. index, { size = { 32, 32 }, anchor = { 16, 16 } })
end

local blocks = {} -- "x:y:z" -> { placed = { ... }, center } of a block standing there

local function keyOf(position)
    return position.x .. ':' .. position.y .. ':' .. position.z
end

function registerWallArt()
    art.register()
end

function clearWallArt()
    for _, block in pairs(blocks) do
        removeEvent(block.done)
        for _, placed in ipairs(block.placed) do
            detachArt(placed)
        end
    end
    blocks = {}
end

function unregisterWallArt()
    clearWallArt()
    art.unregister()
end

-- the block springs up as in the preview and stands until `ms`
local function pillarKeys(way, ms)
    local keys = {}
    for _, key in ipairs(art.keys('subir/parado', 'pilar_' .. way) or {}) do
        if key.t <= RISE_MS then
            keys[#keys + 1] = key
        end
    end
    if #keys == 0 then
        return nil
    end
    local last = keys[#keys]
    keys[#keys + 1] = { t = ms - 10, scale = last.scale, opacity = last.opacity, x = 0, y = 0, rot = 0, ease = 0 }
    keys[#keys + 1] = { t = ms, scale = last.scale, opacity = 0, x = 0, y = 0, rot = 0, ease = 0 }
    return keys
end

-- the preview's pulse of the glow, over and over until the block cracks
-- (`ms` from when it stands)
local function glowKeys(ms)
    local pulse = art.keys('parado', 'pilar_brilho') or {}
    local keys = {}
    local stop = ms - CRACK_MS
    for cycle = 0, math.floor(stop / GLOW_CYCLE_MS) do
        for _, key in ipairs(pulse) do
            local t = key.t + cycle * GLOW_CYCLE_MS
            if t < stop and (cycle == 0 or key.t > 0) then
                keys[#keys + 1] = { t = t, scale = key.scale, opacity = key.opacity, x = 0, y = 0, rot = 0, ease = key.ease }
            end
        end
    end
    if #keys > 0 then
        local last = keys[#keys]
        keys[#keys + 1] = { t = stop + 200, scale = last.scale, opacity = 0, x = 0, y = 0, rot = 0, ease = 1 }
    end
    return keys
end

-- the burst: the block breaking, the mist and the splinters, `at` ms from now
local function burst(position, at, lit)
    local placed = {}
    local function keep(p)
        if p then
            placed[#placed + 1] = p
        end
    end
    local light = lit and { keys = art.lightKeys('quebra'), color = LIGHT } or nil
    keep(art.play('quebra', position, { moment = 'quebra', shift = at, light = light }))
    keep(art.play('nevoa', position, { moment = 'quebra', shift = at }))
    for _, p in ipairs(art.particles('quebra', position, { count = SHARDS, shift = at })) do
        keep(p)
    end
    return placed
end

local handlers = {}

function handlers.up(data)
    local way = ({ ns = 'ns', eo = 'eo', ne = 'ne', nw = 'nw' })[data.o] or 'ns'
    local ms = tonumber(data.ms) or 4000
    local middle = math.ceil(#(data.p or {}) / 2)
    for index, position in ipairs(data.p or {}) do
        local key = keyOf(position)
        local old = blocks[key]
        if old then
            removeEvent(old.done)
            for _, placed in ipairs(old.placed) do
                detachArt(placed)
            end
        end
        local block = { placed = {}, lit = index == middle }
        blocks[key] = block
        local function keep(p)
            if p then
                table.insert(block.placed, p)
            end
        end
        keep(art.play('pilar_' .. way, position, { keys = pillarKeys(way, ms) }))
        -- the glow once it stands
        keep(art.play('pilar_brilho', position, { keys = glowKeys(ms - RISE_MS), shift = RISE_MS, duration = ms }))
        keep(art.play('rachaduras_' .. way, position, { moment = 'rachando', shift = ms - CRACK_MS, duration = ms }))
        art.particles('subir/parado', position, { count = SHARDS })
        -- its burst, already timed: "down" takes it off to burst it earlier
        for _, p in ipairs(burst(position, ms, block.lit)) do
            keep(p)
        end
        block.done = scheduleEvent(function()
            if blocks[key] == block then
                blocks[key] = nil
            end
        end, ms + 1500)
    end
end

function handlers.down(data)
    for _, position in ipairs(data.p or {}) do
        local key = keyOf(position)
        local block = blocks[key]
        if block then
            blocks[key] = nil
            removeEvent(block.done)
            for _, placed in ipairs(block.placed) do
                detachArt(placed)
            end
            burst(position, 0, block.lit)
        end
    end
end

-- the frost on the feet: short, as the server sends it every half second
function handlers.chill(data)
    local keys = {
        { t = 0, scale = 0.7, opacity = 0, x = 0, y = 0, rot = 0, ease = 2 },
        { t = 150, scale = 1, opacity = 0.8, x = 0, y = 0, rot = 0, ease = 2 },
        { t = 450, scale = 1, opacity = 0.75, x = 0, y = 0, rot = 0, ease = 2 },
        { t = 600, scale = 1, opacity = 0, x = 0, y = 0, rot = 0, ease = 1 }
    }
    for _, position in ipairs(data.p or {}) do
        art.play('frio', position, { keys = keys })
    end
end

function onWallArt(data)
    local handler = handlers[data.k]
    if handler and type(data.p) == 'table' then
        handler(data)
    end
end
