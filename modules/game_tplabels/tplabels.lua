-- Teleport labels: the server sends the list of teleports with their names
-- when the client asks for it (extended opcode 126, JSON). Each one in sight on the
-- player's floor gets a small fixed obsidian plate over its tile, coloured
-- by what it leads to, instead of floating text that blinks every few
-- seconds. The client answers "ok" so the server stops the floating text.

local OPCODE = 126
local RANGE_X, RANGE_Y = 9, 7

-- kind -> plate colours and gem
local STYLES = {
    city = { text = '#f1d399', border = '#8d7040', gem = 'gem_gold' },
    hunt = { text = '#d9c7ff', border = '#6e58c0', gem = 'gem_amethyst' },
    event = { text = '#ffc9d6', border = '#9a4660', gem = 'gem_ruby' },
    service = { text = '#ece8f6', border = '#6d6480', gem = 'gem_pearl' },
    back = { text = '#bfeccb', border = '#3f7a52', gem = 'gem_sapphire' },
}

local labels = {}   -- { pos = {x,y,z}, text, kind }
local shown = {}    -- key -> widget
local refreshEvent
local seen = {}     -- keys already faded in once, so a re-attach does not blink

local function key(p)
    return p.x .. ':' .. p.y .. ':' .. p.z
end

local function viewRange()
    local panel = modules.game_interface and modules.game_interface.getMapPanel()
    local dim = panel and panel:getVisibleDimension()
    if not dim or dim.width <= 0 then
        return RANGE_X, RANGE_Y
    end
    -- the plate pokes above its tile, so the top row is left out
    return math.floor((dim.width - 1) / 2), math.floor((dim.height - 1) / 2) - 1
end

local function tileWidth()
    local panel = modules.game_interface and modules.game_interface.getMapPanel()
    if not panel then
        return 32
    end
    local dim = panel:getVisibleDimension()
    if not dim or dim.width <= 0 then
        return 32
    end
    return math.min(panel:getWidth() / dim.width, panel:getHeight() / dim.height)
end

local function makeWidget(label)
    local widget = g_ui.createWidget('TeleportLabel')
    local style = STYLES[label.kind] or STYLES.city
    widget:setId('tplabel_' .. key(label.pos))
    widget:setBorderColor(style.border)
    widget:getChildById('gem'):setImageSource('/images/mythos/' .. style.gem)
    local name = widget:getChildById('name')
    name:setText(label.text)
    name:setColor(style.text)
    widget:setWidth(18 + name:getWidth() + 7)
    return widget
end

local function place(widget)
    -- centre the plate over the tile, mostly above it so the portal shows
    local tw = tileWidth()
    widget:setMarginLeft(math.floor((tw - widget:getWidth()) / 2))
    widget:setMarginTop(-math.floor(widget:getHeight() * 0.7))
end

local function alive(widget)
    -- the map drops attached widgets when it re-reads a tile from the server
    return widget and not widget:isDestroyed() and widget:getParent() ~= nil
end

local function clear()
    for k, widget in pairs(shown) do
        if not widget:isDestroyed() then
            widget:destroy()
        end
        shown[k] = nil
    end
end

local function refresh()
    local player = g_game.getLocalPlayer()
    if not player or #labels == 0 then
        return
    end
    local me = player:getPosition()
    if not me then
        return
    end
    local rx, ry = viewRange()
    local wanted = {}
    for _, label in ipairs(labels) do
        local p = label.pos
        if p.z == me.z and math.abs(p.x - me.x) <= rx and p.y - me.y >= -ry and p.y - me.y <= ry + 1 then
            wanted[key(p)] = label
        end
    end
    for k, widget in pairs(shown) do
        if not wanted[k] or not alive(widget) then
            if not widget:isDestroyed() then
                widget:destroy()
            end
            shown[k] = nil
        end
    end
    for k, label in pairs(wanted) do
        local widget = shown[k]
        if not widget then
            local tile = g_map.getTile(label.pos)
            if tile then
                widget = makeWidget(label)
                widget.onDetached = function()
                    addEvent(refresh)
                end
                tile:attachWidget(widget)
                shown[k] = widget
                if seen[k] then
                    widget:setOpacity(1)
                else
                    seen[k] = true
                    g_effects.fadeIn(widget, 250)
                end
            end
        end
        if widget then
            place(widget)
        end
    end
end

local function scheduleRefresh()
    if refreshEvent then
        removeEvent(refreshEvent)
    end
    refreshEvent = scheduleEvent(function()
        refreshEvent = nil
        refresh()
    end, 50)
end

local function onLabels(protocol, opcode, buffer)
    local ok, data = pcall(function() return json.decode(buffer) end)
    if not ok or type(data) ~= 'table' then
        return
    end
    clear()
    labels = {}
    for _, item in ipairs(data) do
        if item.x and item.t then
            labels[#labels + 1] = { pos = { x = item.x, y = item.y, z = item.z }, text = item.t, kind = item.k }
        end
    end
    protocol:sendExtendedOpcode(OPCODE, 'ok')
    scheduleRefresh()
end

local function onPositionChange(creature)
    if creature:isLocalPlayer() then
        scheduleRefresh()
    end
end

local tick
local function loop()
    refresh()
    tick = scheduleEvent(loop, 1000)
end

local function requestLabels()
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(OPCODE, 'get')
    end
end

local function onGameStart()
    scheduleEvent(requestLabels, 500)
    if not tick then
        loop()
    end
end

local function onGameEnd()
    if tick then
        removeEvent(tick)
        tick = nil
    end
    clear()
    labels = {}
    seen = {}
end

function init()
    g_ui.importStyle('tplabels')
    ProtocolGame.registerExtendedOpcode(OPCODE, onLabels)
    connect(LocalPlayer, { onPositionChange = onPositionChange })
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(LocalPlayer, { onPositionChange = onPositionChange })
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedOpcode(OPCODE)
    onGameEnd()
end
