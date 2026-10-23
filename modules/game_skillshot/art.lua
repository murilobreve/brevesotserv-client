-- The designer's art for the skillshots, drawn as effects attached to map
-- tiles. Each spell (hook.lua, meteor.lua) makes a set of its images:
--   set.add(name, size, offsetX, offsetY, duration, ground)
--     size      the 1x side in pixels (the files are 2x, sharp on a zoomed map)
--     offset    puts the designer's anchor on the tile (pixels from the
--               tile's top-left corner up and left)
--     duration  of the animation, played once (nil: stays until taken off)
--     ground    under the creatures (marks on the floor), else over them
--   set.place(name, position, duration) -> { tile, effect } or nil
--   set.burst(name, position)  plays a once-played animation and lets it go
--   set.attach(name, thing, duration)  on a creature, following it

local sets = {}

function newArtSet(base, path, label)
    local set = { entries = {}, count = 0 }
    table.insert(sets, set)

    function set.add(name, size, offsetX, offsetY, duration, ground)
        set.count = set.count + 1
        set.entries[name] = {
            id = base + set.count,
            size = size,
            offsetX = offsetX,
            offsetY = offsetY,
            duration = duration,
            ground = ground
        }
    end

    function set.register()
        for name, entry in pairs(set.entries) do
            -- a module reload finds them still registered
            g_attachedEffects.remove(entry.id)
            -- loaded now, not on the first cast (a hitch in the middle of it)
            g_textures.preload(path .. name, true)
            local effect = g_attachedEffects.registerByImage(entry.id, label .. ' ' .. name, path .. name, true)
            if effect then
                effect:setSize({ width = entry.size, height = entry.size })
                if entry.offsetX ~= 0 or entry.offsetY ~= 0 then
                    effect:setOffset(entry.offsetX, entry.offsetY)
                end
                if entry.ground then
                    effect:setOnTop(false)
                    effect:setDrawOrder(1)
                else
                    effect:setOnTop(true)
                end
            end
        end
    end

    function set.unregister()
        for _, entry in pairs(set.entries) do
            g_attachedEffects.remove(entry.id)
        end
    end

    -- nil when the tile is off the known map
    function set.place(name, position, duration)
        local entry = set.entries[name]
        local tile = entry and g_map.getTile(position)
        if not tile then
            return nil
        end
        local effect = g_attachedEffects.getById(entry.id)
        if not effect then
            return nil
        end
        if duration then
            effect:setDuration(duration)
        end
        tile:attachEffect(effect)
        return { tile = tile, effect = effect }
    end

    function set.attach(name, thing, duration)
        local entry = set.entries[name]
        if not entry or not thing then
            return nil
        end
        local effect = g_attachedEffects.getById(entry.id)
        if not effect then
            return nil
        end
        if duration then
            effect:setDuration(duration)
        end
        thing:attachEffect(effect)
        return { tile = thing, effect = effect }
    end

    -- goes away just before the animation would loop
    function set.burst(name, position)
        local entry = set.entries[name]
        return entry and set.place(name, position, entry.duration - 10)
    end

    return set
end

-- Every image drawn once, unseen, on `position`: the first draw of a texture
-- sends it to the graphics card, which on a slow machine (a browser with no
-- graphics acceleration) freezes the game for a second or two. Better at
-- login than in the middle of the first cast.
function warmUpArt(position)
    for _, set in ipairs(sets) do
        for name, entry in pairs(set.entries) do
            local placed = set.place(name, position, entry.duration or 1000)
            if placed then
                placed.effect:setOpacity(0.01)
            end
        end
    end
end

function detachArt(placed)
    if placed and placed.tile then
        placed.tile:detachEffect(placed.effect)
    end
end

-- one of the 8 directions (e, ne, n...) a line from here to there goes,
-- snapped: a line that is nearly straight counts as straight
function artDirection(dx, dy)
    local ax, ay = math.abs(dx), math.abs(dy)
    local ns = dy < 0 and 'n' or 's'
    local ew = dx < 0 and 'w' or 'e'
    if ax > ay * 2 then
        return ew
    elseif ay > ax * 2 then
        return ns
    end
    return ns .. ew
end

-- the piece of a line (chain, trail) for each direction: straight across,
-- straight up, or one of the two diagonals
ART_LINE_OF = { e = 'h', w = 'h', n = 'v', s = 'v', ne = 'ne', sw = 'ne', nw = 'nw', se = 'nw' }
