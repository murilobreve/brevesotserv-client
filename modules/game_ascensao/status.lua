-- The Ascensão relics' states (2026-11-04): the server sends each one
-- (action "status", scripts/ascensao/04_engine.lua Ascensao.status) and its
-- icon goes in the rows of state icons, beside hunger, battle and protection
-- zone: the inventory's under the equipment (both of its layouts) and the
-- stats bars'. Its tooltip says what it does and, while it runs out, the
-- seconds left.
--   { action = "status", key, ms, text }   ms > 0: for that long; 0: until
--                                          the server takes it off; < 0: off

local SHEET = '/game_ascensao/images/estados'
local ORDER = { 'abismo', 'coroa', 'serafim', 'estrelas', 'estandarte', 'sino', 'semente', 'lua' }
local INDEX = {}
for index, key in ipairs(ORDER) do
    INDEX[key] = index
end

local active = {} -- key -> { untilMs (nil: lasting), text }
local tickEvent

local function widgetId(key)
    return 'ascensaoStatus_' .. key
end

-- every row of state icons on screen
local function rows()
    local list = {}
    local inventory = modules.game_inventory
    if inventory and inventory.getIconsPanelOn then
        for _, panel in ipairs({ inventory.getIconsPanelOn(), inventory.getIconsPanelOff() }) do
            if panel then
                table.insert(list, panel)
            end
        end
    end
    local interface = modules.game_interface
    local statsBar = interface and interface.StatsBar
    if statsBar and statsBar.getAllStatsBarWithPosition then
        for _, bar in ipairs(statsBar.getAllStatsBarWithPosition() or {}) do
            if bar.icons then
                table.insert(list, bar.icons)
            end
        end
    end
    return list
end

local function tooltipOf(state)
    local text = state.text or ''
    if state.untilMs then
        local left = math.max(0, math.ceil((state.untilMs - g_clock.millis()) / 1000))
        text = string.format('%s (%d s)', text, left)
    end
    return text
end

-- the icon of `key` in every row (made where it is missing: a stats bar
-- built again, the other inventory layout)
local function show(key, state)
    for _, row in ipairs(rows()) do
        local icon = row:getChildById(widgetId(key))
        if not icon then
            icon = g_ui.createWidget('ConditionWidget', row)
            icon:setId(widgetId(key))
            icon:setImageSource(SHEET)
            icon:setImageClip(((INDEX[key] - 1) * 9) .. ' 0 9 9')
            icon:setImageSize(tosize('9 9'))
            icon:setMarginRight(-1)
        end
        icon:setTooltip(tooltipOf(state))
    end
end

local function hideIcon(key)
    for _, row in ipairs(rows()) do
        local icon = row:getChildById(widgetId(key))
        if icon then
            icon:destroy()
        end
    end
end

-- once a second while any icon runs out: the seconds in the tooltips, and
-- the icons whose time is over go away
local function tick()
    tickEvent = nil
    local now = g_clock.millis()
    local timed = false
    for key, state in pairs(active) do
        if state.untilMs and now >= state.untilMs then
            active[key] = nil
            hideIcon(key)
        else
            show(key, state)
            timed = timed or state.untilMs ~= nil
        end
    end
    if timed then
        tickEvent = scheduleEvent(tick, 1000)
    end
end

function onStatus(data)
    local key = data.key
    if not INDEX[key] then
        return
    end
    local ms = tonumber(data.ms) or 0
    if ms < 0 then
        active[key] = nil
        hideIcon(key)
        return
    end
    local state = { text = data.text or '', untilMs = ms > 0 and g_clock.millis() + ms or nil }
    active[key] = state
    show(key, state)
    if state.untilMs and not tickEvent then
        tickEvent = scheduleEvent(tick, 1000)
    end
end

function clearStatus()
    removeEvent(tickEvent)
    tickEvent = nil
    for key in pairs(active) do
        hideIcon(key)
    end
    active = {}
end
