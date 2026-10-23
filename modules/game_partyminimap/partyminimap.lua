-- Party on the minimap: the server (scripts/party_minimap.lua) sends every
-- second where the other party members are, on screen or not, and each one
-- gets a dot on the minimap, coloured by health. A member on another floor
-- is shown faded; the tooltip says the name, health and floor.

local OPCODE = 130

local marks = {} -- name -> widget
local members = {} -- the last list from the server

local function getMinimap()
    local mapModule = modules.game_minimap
    local ui = mapModule and mapModule.mapController and mapModule.mapController.ui
    local widget = ui and ui.minimapBorder and ui.minimapBorder.minimap
    if widget then
        return widget
    end
    -- full screen: the minimap moves to the game's root panel
    local root = modules.game_interface and modules.game_interface.getRootPanel()
    return root and root:recursiveGetChildById('minimap')
end

local function healthColor(hp)
    if hp > 60 then
        return '#5fdc6a'
    elseif hp > 30 then
        return '#f0c23c'
    end
    return '#e2483a'
end

local function clearMarks()
    for _, mark in pairs(marks) do
        mark:destroy()
    end
    marks = {}
end

local function refresh()
    local minimap = getMinimap()
    if not minimap then
        return
    end
    local floor = minimap:getCameraPosition().z
    local seen = {}
    for _, member in ipairs(members) do
        local name = tostring(member.name or '')
        local pos = { x = tonumber(member.x) or 0, y = tonumber(member.y) or 0, z = tonumber(member.z) or 7 }
        local hp = tonumber(member.hp) or 100
        local mark = marks[name]
        if mark and mark:getParent() ~= minimap then
            mark:destroy()
            mark = nil
        end
        if not mark then
            mark = g_ui.createWidget('PartyMinimapMark', minimap)
            marks[name] = mark
        end
        seen[name] = true
        mark:setBackgroundColor(healthColor(hp))
        local where = ''
        if pos.z < floor then
            where = ' - ' .. tr('%d floor(s) up', floor - pos.z)
        elseif pos.z > floor then
            where = ' - ' .. tr('%d floor(s) down', pos.z - floor)
        end
        mark:setTooltip(string.format('%s (%d%%)%s', name, hp, where))
        mark:setOpacity(pos.z == floor and 1 or 0.55)
        -- the minimap only places what is on its own floor: another floor's
        -- member goes where they are above or below it
        minimap:centerInPosition(mark, { x = pos.x, y = pos.y, z = floor })
    end
    for name, mark in pairs(marks) do
        if not seen[name] then
            mark:destroy()
            marks[name] = nil
        end
    end
end

local function onOpcode(protocol, opcode, data)
    members = type(data) == 'table' and type(data.members) == 'table' and data.members or {}
    refresh()
end

-- the dots fade or brighten as the minimap changes floor
local hookedMinimap
local function hookFloorChanges()
    local minimap = getMinimap()
    if not minimap or hookedMinimap == minimap then
        return
    end
    hookedMinimap = minimap
    local original = minimap.onCameraPositionChange
    minimap.onCameraPositionChange = function(widget, position, oldPosition)
        if original then
            original(widget, position, oldPosition)
        end
        if oldPosition and position.z ~= oldPosition.z then
            refresh()
        end
    end
end

local function onGameStart()
    hookFloorChanges()
end

local function onGameEnd()
    members = {}
    clearMarks()
end

function init()
    g_ui.importStyle('partyminimap')
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    clearMarks()
end
