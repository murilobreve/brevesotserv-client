-- Mythos VIP row at the top of the Mythos panel: the days left in gold for a
-- VIP, "Become VIP" for everyone else. A click opens the Store on the Mythos
-- VIP category. The server sends the status when asked and whenever it changes
-- (extended opcode 127, JSON; data-otservbr-global/scripts/vip/vip.lua); the
-- client asks for it once the game screen is up.

local OPCODE = 127
local row
local status

local function refresh()
    local panel = modules.game_brevespanel
    if not row or not panel or not panel.setFeatureLabel then
        return
    end
    if status and status.vip then
        -- short: the bar has to fit it in its first line
        panel.setFeatureLabel('vip', tr('VIP %dd', tonumber(status.days) or 0), '#ffd77a')
        row:setTooltip(tr('Mythos VIP until %s', os.date('%d/%m/%Y %H:%M', tonumber(status.expires) or 0)))
    else
        panel.setFeatureLabel('vip', tr('Become VIP'), '#e6cf8f')
        row:setTooltip(tr('+10%% experience, loot and training, the Fusca, Uno and Gol mounts and more. Opens the Store.'))
    end
end

local function openStore()
    if modules.game_store and modules.game_store.openCategory then
        modules.game_store.openCategory('Mythos VIP')
    end
end

local function onVipOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    status = data
    refresh()
end

local function onGameStart()
    if not row and modules.game_brevespanel then
        row = modules.game_brevespanel.addFeature('vip', openStore)
    end
    refresh()
    -- ask for the status (the server also sends it whenever it changes)
    scheduleEvent(function()
        local protocol = g_game.getProtocolGame()
        if g_game.isOnline() and protocol then
            protocol:sendExtendedOpcode(OPCODE, 'get')
        end
    end, 1500)
end

local function onGameEnd()
    status = nil
end

function init()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onVipOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    if row then
        row:destroy()
        row = nil
    end
end
