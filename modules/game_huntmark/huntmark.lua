-- Where the hunt (or quest) teleport left the player: the server sends the
-- arrival (extended opcode 143, JSON { x, y, z, name }: hunt_tasks/
-- 05_teleport.lua, HuntTaskTeleport.markArrival) and the minimap shows the
-- teleport icon there, so the way back to the Voltar is easy to find. One
-- mark at a time: the next teleport moves it. It stays while the character
-- is online and goes away at logout (a temporary flag, not saved).

local OPCODE = 143
local ICON = '/game_brevespanel/images/teleport_small'

local mark -- { pos, name } of the mark on the minimap now

local function minimap()
    local module = modules.game_minimap
    local ok, widget = pcall(function()
        return module and module.getMiniMapUi and module.getMiniMapUi()
    end)
    return ok and widget or nil
end

local function clear()
    local widget = minimap()
    if mark and widget then
        local flag = widget:getFlag(mark.pos)
        if flag then
            flag:destroy()
        end
    end
    mark = nil
end

local function onArrival(protocol, opcode, data)
    if type(data) ~= 'table' or not tonumber(data.x) then
        return
    end
    clear()
    local widget = minimap()
    if not widget then
        return
    end
    local pos = { x = tonumber(data.x), y = tonumber(data.y), z = tonumber(data.z) }
    local name = tostring(data.name or '')
    widget:addFlag(pos, ICON, name ~= '' and tr('Teleport: %s', name) or tr('Teleport'), true)
    mark = { pos = pos, name = name }
end

function init()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onArrival)
    connect(g_game, { onGameEnd = clear })
end

function terminate()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    disconnect(g_game, { onGameEnd = clear })
    clear()
end
