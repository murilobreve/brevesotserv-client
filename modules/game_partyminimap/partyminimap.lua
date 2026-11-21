-- Party on the minimap: the server (scripts/party_minimap.lua) sends every
-- second where the other party members are, on screen or not, and each one
-- gets a mark on the minimap: their outfit in a frame coloured by vocation,
-- with a health bar under it (a dot coloured by health when the server sends
-- no outfit). A member on another floor is shown faded; the tooltip says the
-- name, vocation, health and floor.

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

-- frame colour and name of each base vocation (the server's vocation ids)
local VOCATIONS = {
    [1] = { color = '#3fa9f5', name = 'Sorcerer' },
    [2] = { color = '#4fd36a', name = 'Druid' },
    [3] = { color = '#f2c230', name = 'Paladin' },
    [4] = { color = '#e5483c', name = 'Knight' },
    [9] = { color = '#b07cff', name = 'Monk' },
}

local function outfitOf(raw)
    return {
        type = tonumber(raw[1]) or 0,
        head = tonumber(raw[2]) or 0,
        body = tonumber(raw[3]) or 0,
        legs = tonumber(raw[4]) or 0,
        feet = tonumber(raw[5]) or 0,
        addons = tonumber(raw[6]) or 0,
        mount = 0,
    }
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
        local outfit = type(member.o) == 'table' and tonumber(member.o[1]) and tonumber(member.o[1]) > 0 and outfitOf(member.o)
        local style = outfit and 'PartyMinimapMark' or 'PartyMinimapDot'
        local mark = marks[name]
        if mark and (mark:getParent() ~= minimap or mark.partyStyle ~= style) then
            mark:destroy()
            mark = nil
        end
        if not mark then
            mark = g_ui.createWidget(style, minimap)
            mark.partyStyle = style
            marks[name] = mark
        end
        seen[name] = true
        local vocation = VOCATIONS[tonumber(member.voc) or 0]
        if outfit then
            local key = table.concat(member.o, ',')
            if mark.outfitKey ~= key then
                mark.outfitKey = key
                mark.creature:setOutfit(outfit)
            end
            mark.frame:setBorderColor(vocation and vocation.color or '#ffffff')
            mark.health:setWidth(math.max(1, math.floor(20 * math.max(0, math.min(100, hp)) / 100 + 0.5)))
            mark.health:setBackgroundColor(healthColor(hp))
        else
            mark:setBackgroundColor(healthColor(hp))
        end
        local where = ''
        if pos.z < floor then
            where = ' - ' .. tr('%d floor(s) up', floor - pos.z)
        elseif pos.z > floor then
            where = ' - ' .. tr('%d floor(s) down', pos.z - floor)
        end
        local label = vocation and string.format('%s - %s', name, tr(vocation.name)) or name
        mark:setTooltip(string.format('%s (%d%%)%s', label, hp, where))
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
