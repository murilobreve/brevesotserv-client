-- Skillshots: some spells are aimed with the mouse, like in a MOBA. Right
-- before one of them is said (action bar, hotkey or chat) this module tells
-- the server which tile is under the mouse (opcode OPCODE); the server
-- (scripts/skillshot) sends the spell toward it. With the mouse off the map
-- nothing is sent and the spell goes the way the character faces.
-- The server says at login which words are skillshots; the client answers
-- with the spells it has art for (ART) and the server then sends their
-- moments to draw (hook.lua, meteor.lua, palm.lua) instead of the Tibia effects.

local OPCODE = 131
local ART = { 'hook', 'meteor', 'palm' }

local words = {}
local originalTalk, originalTalkChannel

local function normalize(text)
    return tostring(text or ''):lower():gsub('^%s+', ''):gsub('%s+$', ''):gsub('^"', '')
end

local function sendAim(text)
    if not words[normalize(text)] then
        return
    end
    local mapPanel = modules.game_interface and modules.game_interface.getMapPanel()
    local protocol = g_game.getProtocolGame()
    if not mapPanel or not protocol then
        return
    end
    local mouse = g_window.getMousePosition()
    if not mapPanel:containsPoint(mouse) then
        return
    end
    local pos = mapPanel:getPosition(mouse)
    if not pos or pos.x == 0 then
        return
    end
    protocol:sendExtendedJSONOpcode(OPCODE, { x = pos.x, y = pos.y, z = pos.z })
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    if data.fx == 'hook' then
        onHookArt(data)
    elseif data.fx == 'meteor' then
        onMeteorArt(data)
    elseif data.fx == 'palm' then
        onPalmArt(data)
    elseif type(data.words) == 'table' then
        words = {}
        for _, spell in ipairs(data.words) do
            words[normalize(spell)] = true
        end
        protocol:sendExtendedJSONOpcode(OPCODE, { art = ART })
    end
end

function clearArt()
    clearHookArt()
    clearMeteorArt()
    clearPalmArt()
end

local warmUpEvent

local function warmUp()
    removeEvent(warmUpEvent)
    warmUpEvent = scheduleEvent(function()
        local player = g_game.getLocalPlayer()
        if player then
            warmUpArt(player:getPosition())
        end
    end, 2000)
end

function init()
    registerHookArt()
    registerMeteorArt()
    registerPalmArt()
    connect(g_game, { onGameStart = warmUp, onGameEnd = clearArt })
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    -- every spell goes through one of these two: the action bar and hotkeys
    -- call talk, the chat calls talkChannel with the say mode
    originalTalk = g_game.talk
    originalTalkChannel = g_game.talkChannel
    g_game.talk = function(text, ...)
        sendAim(text)
        return originalTalk(text, ...)
    end
    g_game.talkChannel = function(mode, channel, text, ...)
        if mode == MessageModes.Say then
            sendAim(text)
        end
        return originalTalkChannel(mode, channel, text, ...)
    end
end

function terminate()
    disconnect(g_game, { onGameStart = warmUp, onGameEnd = clearArt })
    removeEvent(warmUpEvent)
    unregisterHookArt()
    unregisterMeteorArt()
    unregisterPalmArt()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    if originalTalk then
        g_game.talk = originalTalk
        g_game.talkChannel = originalTalkChannel
    end
end
