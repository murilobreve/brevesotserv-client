-- The Ascensão relics' states (2026-11-04): the server sends each one
-- (action "status", scripts/ascensao/04_engine.lua Ascensao.status) and its
-- icon goes in the rows of state icons, beside hunger, battle and protection
-- zone: the inventory's under the equipment (both of its layouts) and the
-- stats bars'. Its tooltip says what it does and, while it runs out, the
-- seconds left. Every relic has its icon while the player has it
-- (2026-11-05), faded while it recharges.
--   { action = "status", key, ms, text, dim, count, silent }
--       ms > 0: for that long; 0: until the server takes it off; < 0: off
--       dim: faded (recharging); count: ms the tooltip counts down
--       ("pronta em"); silent: no seconds (renewed while one stays near)

local SHEET = '/game_ascensao/images/estados'
local ORDER = {
    'abismo', 'coroa', 'serafim', 'estrelas', 'estandarte', 'sino', 'semente', 'lua',
    'corrente', 'arco', 'olho', 'supernova', 'glaciar', 'tatuagem', 'vento',
}
local DIM_OPACITY = 0.4
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

-- "45 s", "12 min"
local function timeText(ms)
    local seconds = math.max(0, math.ceil(ms / 1000))
    if seconds > 120 then
        return string.format('%d min', math.ceil(seconds / 60))
    end
    return string.format('%d s', seconds)
end

local function tooltipOf(state)
    local text = state.text or ''
    local now = g_clock.millis()
    if state.countUntil then
        if state.countUntil > now then
            text = string.format('%s (%s)', text, timeText(state.countUntil - now))
        end
    elseif state.untilMs and not state.silent then
        text = string.format('%s (%s)', text, timeText(state.untilMs - now))
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
        icon:setOpacity(state.dim and DIM_OPACITY or 1)
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
            timed = timed or state.untilMs ~= nil or (state.countUntil ~= nil and state.countUntil > now)
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
    local now = g_clock.millis()
    local count = tonumber(data.count) or 0
    local state = {
        text = data.text or '',
        untilMs = ms > 0 and now + ms or nil,
        countUntil = count > 0 and now + count or nil,
        dim = data.dim and true or false,
        silent = data.silent and true or false,
    }
    active[key] = state
    show(key, state)
    if (state.untilMs or state.countUntil) and not tickEvent then
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
