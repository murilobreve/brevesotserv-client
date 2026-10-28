-- Races of the server's own monsters (the bestiary class "Mythos"). The
-- client's data files only know Tibia's creatures, so the Cyclopedia, prey,
-- charms and trackers showed them without a name or a look; the server sends
-- their names and outfits (data-otservbr-global/scripts/bestiary/
-- bestiary_world.lua, extended opcode 135) and g_things answers for them.

local OPCODE = 135
local customRaces = {} -- raceId -> RaceType-like table

local function request()
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(OPCODE, { action = 'races' })
    end
end

local function onRaces(protocol, opcode, data)
    if type(data) ~= 'table' or data.action ~= 'races' then
        return
    end
    customRaces = {}
    for _, race in ipairs(data.races or {}) do
        local id = tonumber(race[1])
        if id then
            customRaces[id] = {
                raceId = id,
                -- lower case like the client's own race names: the Cyclopedia
                -- capitalizes each word itself
                name = tostring(race[2] or ''):lower(),
                outfit = { type = race[3] or 0, head = race[4] or 0, body = race[5] or 0, legs = race[6] or 0, feet = race[7] or 0, addons = race[8] or 0 },
                category = 0,
                hasCategory = false,
                boss = false,
            }
        end
    end
end

-- the engine's answers first; a race it does not know may be one of ours
-- (kept once: reloading this file must not wrap the wrappers)
MYTHOS_ENGINE_RACES = MYTHOS_ENGINE_RACES or { data = g_things.getRaceData, byName = g_things.getRacesByName }
local engineRaceData = MYTHOS_ENGINE_RACES.data
local engineRacesByName = MYTHOS_ENGINE_RACES.byName

g_things.getRaceData = function(raceId)
    local race = engineRaceData(raceId)
    if (not race or (race.raceId or 0) == 0) and customRaces[tonumber(raceId)] then
        return customRaces[tonumber(raceId)]
    end
    return race
end

g_things.getRacesByName = function(text)
    local list = engineRacesByName(text) or {}
    for _, race in pairs(customRaces) do
        if race.name:find(tostring(text):lower(), 1, true) then
            table.insert(list, race)
        end
    end
    return list
end

if MYTHOS_RACES_HOOKED then
    -- protocolgame.lua may have been reloaded too, with no opcode registered
    pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
    disconnect(g_game, { onGameStart = MYTHOS_RACES_HOOKED })
end
ProtocolGame.registerExtendedJSONOpcode(OPCODE, onRaces)
connect(g_game, { onGameStart = request })
MYTHOS_RACES_HOOKED = request
if g_game.isOnline() then
    request()
end
