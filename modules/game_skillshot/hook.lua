-- Gancho do Carrasco: the designer's art (images/gancho, from "Gancho do
-- Carrasco - artes v1"). The server sends each moment of a cast
-- (scripts/skillshot, fx "hook") and this draws it on the map tiles:
--   fly   the hook moves one tile and leaves a link of chain behind
--   hit   the impact where the hook arrives, then the chain pulls back
--   pull  dust and the chain ring where the creature lands (rooted 600 ms)
--   miss  the hook falls short and the chain pulls back
-- The hook in flight is a still frame per step: a moving effect can't use an
-- animated texture (both share the effect's timer), so the four spin frames
-- go one per tile.

local HOOK_RETRACT_MS = 150 -- the chain pulls back in this long
local HOOK_FORGET_MS = 1000 -- a cast with no news for this long is cleared

local DIRECTIONS = { 'e', 'w', 'n', 's', 'ne', 'nw', 'se', 'sw' }
local LINKS = { 'h', 'v', 'ne', 'nw' }

-- anchors: the centre for the hook and the chain, the ground for the rest
local art = newArtSet(3200, '/game_skillshot/images/gancho/', 'Gancho')
for _, dir in ipairs(DIRECTIONS) do
    for frame = 1, 4 do
        art.add('voo_' .. dir .. '_' .. frame, 32, 0, 0)
    end
end
for _, link in ipairs(LINKS) do
    art.add('elo_' .. link, 32, 0, 0)
end
art.add('impacto', 96, 32, 48, 400)
art.add('arrasto', 32, 0, 0, 300)
art.add('preso', 64, 16, 12, 600)
art.add('erro', 64, 16, 28, 350)

function registerHookArt()
    art.register()
end

-- ---------------------------------------------------------------------------

local casts = {} -- cast id -> { head, links, arrive, forget }

local function forget(id)
    local cast = casts[id]
    if not cast then
        return
    end
    casts[id] = nil
    removeEvent(cast.forget)
    detachArt(cast.head)
    for _, link in ipairs(cast.links) do
        detachArt(link)
    end
end

function clearHookArt()
    for id in pairs(casts) do
        forget(id)
    end
end

function unregisterHookArt()
    clearHookArt()
    art.unregister()
end

local function castOf(data)
    local cast = casts[data.c]
    if not cast then
        cast = { links = {}, arrive = 0 }
        casts[data.c] = cast
    end
    removeEvent(cast.forget)
    cast.forget = scheduleEvent(function()
        forget(data.c)
    end, HOOK_FORGET_MS)
    return cast
end

-- when the hook gets where it is going
local function onArrival(cast, callback)
    local wait = cast.arrive - g_clock.millis()
    if wait > 0 then
        scheduleEvent(callback, wait)
    else
        callback()
    end
end

local function retract(id)
    local cast = casts[id]
    if not cast then
        return
    end
    detachArt(cast.head)
    cast.head = nil
    local count = #cast.links
    for index = count, 1, -1 do
        local link = cast.links[index]
        scheduleEvent(function()
            detachArt(link)
        end, math.floor((count - index) * HOOK_RETRACT_MS / count))
    end
    cast.links = {}
    scheduleEvent(function()
        forget(id)
    end, HOOK_RETRACT_MS)
end

local handlers = {}

function handlers.fly(data)
    local cast = castOf(data)
    local from, to = data.f, data.t
    detachArt(cast.head)
    -- the whole chain lies along the cast, one way (a line that is not
    -- straight or diagonal steps both ways)
    local origin = data.o or from
    local dir = artDirection(to.x - origin.x, to.y - origin.y)
    -- a link on the tile the hook leaves (none on the knight's own)
    if from.x ~= origin.x or from.y ~= origin.y then
        local link = art.place('elo_' .. ART_LINE_OF[dir], from)
        if link then
            table.insert(cast.links, link)
        end
    end
    local frame = ((tonumber(data.i) or 1) - 1) % 4 + 1
    local ms = tonumber(data.ms) or 90
    -- no duration on attach (it would take the hook off at the end of the
    -- step): set after, it times the move
    cast.head = art.place('voo_' .. dir .. '_' .. frame, from)
    if cast.head then
        cast.head.effect:setDuration(ms)
        cast.head.effect:move(from, to)
    end
    cast.arrive = g_clock.millis() + ms
end

function handlers.hit(data)
    local cast = castOf(data)
    onArrival(cast, function()
        art.burst('impacto', data.p)
        retract(data.c)
    end)
end

function handlers.miss(data)
    local cast = castOf(data)
    onArrival(cast, function()
        art.burst('erro', data.p)
        retract(data.c)
    end)
end

function handlers.pull(data)
    local cast = castOf(data)
    onArrival(cast, function()
        art.burst('arrasto', data.t)
        art.burst('preso', data.t)
    end)
end

function onHookArt(data)
    local handler = handlers[data.k]
    if handler and type(data.c) == 'number' then
        handler(data)
    end
end
