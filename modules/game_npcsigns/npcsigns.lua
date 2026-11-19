-- A small sign over the head of an NPC players look for, so he is found at a
-- glance in a crowded temple: Gersao buys the loot, Morvena sells the
-- imbuements, Nimral food and backpacks (the owner, 2026-11-19).
-- A gold bag and two words in the font of the names, right over his name
-- (the owner: small and close to him). It is a widget of the interface that
-- follows the NPC: drawn with the map (as an attached effect) the next wall
-- would cut it. The client puts it on by the NPC's name, the server knows
-- nothing of it.
local BAG = '/game_npcsigns/images/loot_bag'
local SIGNS = {
    ['gersao'] = { text = 'Loot Buyer', icon = BAG },
    -- the same bag for the two other shops of the temple (the owner, 2026-11-19)
    ['morvena'] = { text = 'Imbuements', icon = BAG },
    ['nimral'] = { text = 'Food & Equipment', icon = BAG },
}

local ICON_ROOM = 14 -- the bag and its gap, left of the words
-- from the point the map hands over (the foot of the NPC's name) up to the
-- foot of the sign: the height of the name
local ABOVE_NAME = 11

local shown = {} -- creature id -> widget
local owners = {} -- creature id -> the NPC of the widget
local waiting = {} -- creature id -> true while its sign waits for the map

local RETRIES, RETRY_DELAY = 20, 250

local function unmark(creature)
    local id = creature and creature:getId()
    if id then
        waiting[id] = nil
    end
    local widget = id and shown[id]
    if widget then
        shown[id] = nil
        owners[id] = nil
        if not widget:isDestroyed() then
            widget:destroy()
        end
    end
end

-- only on the player's floor: the NPC of the floor above is under a roof,
-- his sign would hang over nothing
local function sameFloor(creature)
    local player = g_game.getLocalPlayer()
    local mine = player and player:getPosition()
    local his = creature and creature:getPosition()
    return mine ~= nil and his ~= nil and mine.z == his.z
end

local mark
mark = function(creature, tries)
    if not creature or not creature.isNpc or not creature:isNpc() then
        return
    end
    local sign = SIGNS[creature:getName():lower()]
    if not sign then
        return
    end
    local id = creature:getId()
    local old = shown[id]
    if old and not old:isDestroyed() and old:getParent() then
        return
    end
    local widget = g_ui.createWidget('NpcSign')
    widget:setId('npcsign_' .. id)
    widget:setText(tr(sign.text))
    widget:setIcon(sign.icon)
    widget:resizeToText()
    widget:setSize({ width = widget:getWidth() + ICON_ROOM, height = 13 })
    -- the map hands the point over the middle of the NPC's head
    widget:setMarginLeft(-math.floor(widget:getWidth() / 2))
    widget:setMarginTop(-(widget:getHeight() + ABOVE_NAME))
    creature:attachWidget(widget)
    if not widget:getParent() then
        -- right after the login the map is not drawn yet and takes no
        -- widget: once more in a moment
        widget:destroy()
        waiting[id] = (tries or 0) < RETRIES or nil
        if waiting[id] then
            scheduleEvent(function()
                -- not when he left the screen meanwhile (unmark)
                if waiting[id] and g_game.isOnline() then
                    mark(creature, (tries or 0) + 1)
                end
            end, RETRY_DELAY)
        end
        return
    end
    waiting[id] = nil
    shown[id] = widget
    owners[id] = creature
    widget:setVisible(sameFloor(creature))
end

-- the player changed floor: the signs of the other floors hide
local function refresh()
    for id, widget in pairs(shown) do
        if not widget:isDestroyed() then
            widget:setVisible(sameFloor(owners[id]))
        end
    end
end

local function onPlayerMove(player, newPos, oldPos)
    if not oldPos or not newPos or oldPos.z ~= newPos.z then
        refresh()
    end
end

-- the NPCs already on screen (a module reload, or a login beside one)
local function markAll()
    local player = g_game.getLocalPlayer()
    local position = player and player:getPosition()
    if not position then
        return
    end
    -- at the very start of a game the map may not be there yet
    for _, creature in ipairs(g_map.getSpectators(position, false) or {}) do
        mark(creature)
    end
end

local function clear()
    for id, widget in pairs(shown) do
        if not widget:isDestroyed() then
            widget:destroy()
        end
        shown[id] = nil
    end
    owners = {}
    waiting = {}
end

function init()
    g_ui.importStyle('npcsigns')
    connect(Creature, { onAppear = mark, onDisappear = unmark })
    connect(LocalPlayer, { onPositionChange = onPlayerMove })
    connect(g_game, { onGameStart = markAll, onGameEnd = clear })
    if g_game.isOnline() then
        markAll()
    end
end

function terminate()
    disconnect(Creature, { onAppear = mark, onDisappear = unmark })
    disconnect(LocalPlayer, { onPositionChange = onPlayerMove })
    disconnect(g_game, { onGameStart = markAll, onGameEnd = clear })
    clear()
end
