-- Equipment drawn on the outfit: the server (scripts/custom/paperdolls.lua)
-- says which Dragon Scale pieces each player on screen wears, and each piece
-- is drawn over his character as an outfit layer (data/things/custom,
-- outfits 3000-3003, made by tools/custom-assets/add_paperdolls.py).
-- The art is drawn over the male Citizen on foot: on another outfit it does
-- not fit, so it only shows on that outfit (and not while mounted).

local OPCODE = 145
local OUTFITS = { [128] = true } -- male Citizen

-- piece -> paperdoll id, outfit (thing) id and draw order (higher on top)
local PIECES = {
    legs = { id = 101, thing = 3002, priority = 201 },
    boots = { id = 102, thing = 3003, priority = 202 },
    mail = { id = 103, thing = 3001, priority = 203 },
    helmet = { id = 104, thing = 3000, priority = 204 },
}

local registered = false
local worn = {} -- creature id -> { piece = true }

local function register()
    if registered then
        return
    end
    registered = true
    -- through game_paperdolls' manager: its attach and outfit change events
    -- look every paperdoll up there
    local manager = modules.game_paperdolls and modules.game_paperdolls.PaperdollManager
    for name, piece in pairs(PIECES) do
        local config = { priority = piece.priority, onTop = true }
        if manager then
            manager.register(piece.id, 'Dragon Scale ' .. name, piece.thing, config)
        else
            local paperdoll = g_paperdolls.register(piece.id, piece.thing)
            if paperdoll then
                paperdoll:setPriority(piece.priority)
                paperdoll:setOnTop(true)
            end
        end
    end
end

local function apply(creature)
    if not creature then
        return
    end
    local pieces = worn[creature:getId()] or {}
    local outfit = creature:getOutfit()
    local fits = outfit and OUTFITS[outfit.type]
    for name, piece in pairs(PIECES) do
        local has = creature:getPaperdollById(piece.id) ~= nil
        local want = fits and pieces[name] or false
        if want and not has then
            local base = g_paperdolls.getById(piece.id)
            if base then
                -- each creature its own copy: the direction lives in it
                creature:attachPaperdoll(base:clone())
            end
        elseif has and not want then
            creature:detachPaperdollById(piece.id)
        end
    end
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' or type(data.set) ~= 'table' then
        return
    end
    for _, entry in ipairs(data.set) do
        local id = tonumber(entry.id)
        if id then
            local pieces = {}
            for _, name in ipairs(type(entry.p) == 'table' and entry.p or {}) do
                if PIECES[name] then
                    pieces[name] = true
                end
            end
            worn[id] = next(pieces) and pieces or nil
            apply(g_map.getCreatureById(id))
        end
    end
end

local function onAppear(creature)
    if creature:isPlayer() then
        apply(creature)
    end
end

local function onOutfitChange(creature, outfit, oldOutfit)
    if creature:isPlayer() then
        apply(creature)
    end
end

local function onGameStart()
    worn = {}
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(OPCODE, { reset = true })
    end
end

local function onGameEnd()
    worn = {}
end

function init()
    register()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    connect(Creature, { onAppear = onAppear, onOutfitChange = onOutfitChange })
    connect(LocalPlayer, { onOutfitChange = onOutfitChange })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    disconnect(Creature, { onAppear = onAppear, onOutfitChange = onOutfitChange })
    disconnect(LocalPlayer, { onOutfitChange = onOutfitChange })
    for _, piece in pairs(PIECES) do
        g_paperdolls.remove(piece.id)
    end
    registered = false
    worn = {}
end
