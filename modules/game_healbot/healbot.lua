-- Heal bot: casts healing spells and uses potions when health or mana drop
-- below a percent, heals friends and keeps buffs up. Settings are saved per
-- character. The server still applies its own exhaust, so this never heals
-- faster than a player pressing hotkeys.

local window, toolbarButton, tickEvent
local running = false
local cfg
local nextSpell, nextPotion = 0, 0
local buffCast = {}

local TICK = 100
local SPELL_DELAY = 1000
local POTION_DELAY = 1000

local function defaults()
    return {
        heal = {
            { on = false, action = 'exura vita', stat = 'hp', below = 60 },
            { on = false, action = 'exura med ico', stat = 'hp', below = 75 },
            { on = false, action = '7643', stat = 'hp', below = 45 },
            { on = false, action = '23373', stat = 'mp', below = 40 },
            { on = false, action = '', stat = 'hp', below = 0 },
            { on = false, action = '', stat = 'mp', below = 0 },
        },
        friends = {
            { on = false, action = 'exura sio "{name}"', below = 60, party = true },
            { on = false, action = '', below = 0, party = true },
        },
        buffs = {
            { on = false, action = 'utamo vita', every = 0 },
            { on = false, action = 'utani hur', every = 0 },
            { on = false, action = '', every = 60 },
        },
    }
end

local function characterKey()
    local player = g_game.getLocalPlayer()
    return player and player:getName() or ''
end

local function load()
    local all = g_settings.getNode('healbot') or {}
    cfg = defaults()
    local saved = all[characterKey()]
    if type(saved) == 'table' then
        for _, group in ipairs({ 'heal', 'friends', 'buffs' }) do
            for i, row in ipairs(cfg[group]) do
                local s = saved[group] and saved[group][tostring(i)] or saved[group] and saved[group][i]
                if type(s) == 'table' then
                    for k in pairs(row) do
                        if s[k] ~= nil then
                            row[k] = s[k]
                        end
                    end
                end
            end
        end
    end
end

local function save()
    if not cfg or characterKey() == '' then
        return
    end
    local all = g_settings.getNode('healbot') or {}
    local out = {}
    for _, group in ipairs({ 'heal', 'friends', 'buffs' }) do
        out[group] = {}
        for i, row in ipairs(cfg[group]) do
            out[group][tostring(i)] = row
        end
    end
    all[characterKey()] = out
    g_settings.setNode('healbot', all)
end

-- ---------------------------------------------------------------------------
-- the bot
-- ---------------------------------------------------------------------------

local function percent(value, max)
    if not max or max <= 0 then
        return 100
    end
    return value * 100 / max
end

local function isManaShieldSpell(words)
    return words:find('^utamo vita') ~= nil
end

local function isHasteSpell(words)
    return words:find('^utani') ~= nil
end

local function hasState(player, state)
    return bit.band(player:getStates(), state) ~= 0
end

local function friendToHeal(player, row)
    local mapPanel = modules.game_interface and modules.game_interface.getMapPanel()
    if not mapPanel then
        return nil
    end
    local best
    for _, creature in ipairs(mapPanel:getSpectators()) do
        if creature:isPlayer() and not creature:isLocalPlayer() and creature:getHealthPercent() < row.below
            and (not row.party or creature:isPartyMember()) then
            if not best or creature:getHealthPercent() < best:getHealthPercent() then
                best = creature
            end
        end
    end
    return best
end

local function tick()
    if not running or not g_game.isOnline() or not cfg then
        return
    end
    local player = g_game.getLocalPlayer()
    if not player or player:getHealth() <= 0 then
        return
    end
    local now = g_clock.millis()
    local hp = percent(player:getHealth(), player:getMaxHealth())
    local mp = percent(player:getMana(), player:getMaxMana())
    local spellUsed, potionUsed = now < nextSpell, now < nextPotion

    for _, row in ipairs(cfg.heal) do
        local action = (row.action or ''):trim()
        local value = row.stat == 'mp' and mp or hp
        if row.on and action ~= '' and value < (tonumber(row.below) or 0) then
            local itemId = tonumber(action)
            if itemId and not potionUsed then
                g_game.useInventoryItemWith(itemId, player)
                nextPotion, potionUsed = now + POTION_DELAY, true
            elseif not itemId and not spellUsed then
                g_game.talk(action)
                nextSpell, spellUsed = now + SPELL_DELAY, true
            end
        end
    end

    if not spellUsed then
        for _, row in ipairs(cfg.friends) do
            local action = (row.action or ''):trim()
            if row.on and action ~= '' then
                local friend = friendToHeal(player, row)
                if friend then
                    g_game.talk((action:gsub('{name}', friend:getName())))
                    nextSpell, spellUsed = now + SPELL_DELAY, true
                    break
                end
            end
        end
    end

    if not spellUsed then
        for i, row in ipairs(cfg.buffs) do
            local action = (row.action or ''):trim()
            if row.on and action ~= '' then
                local words = action:lower()
                local due
                if isManaShieldSpell(words) then
                    due = not hasState(player, PlayerStates.ManaShield) and not hasState(player, PlayerStates.NewManaShield)
                elseif isHasteSpell(words) then
                    due = not hasState(player, PlayerStates.Haste)
                else
                    local every = (tonumber(row.every) or 0) * 1000
                    due = every > 0 and now - (buffCast[i] or 0) >= every
                end
                if due then
                    g_game.talk(action)
                    buffCast[i] = now
                    nextSpell = now + SPELL_DELAY
                    break
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- window
-- ---------------------------------------------------------------------------

local function bindRow(widget, row)
    widget.enabled:setChecked(row.on)
    widget.action:setText(row.action or '')
    widget.enabled.onCheckChange = function(_, checked)
        row.on = checked
        save()
    end
    widget.action.onTextChange = function(_, text)
        row.action = text
        save()
    end
    if widget.below then
        widget.below:setText(tostring(row.below or 0))
        widget.below.onTextChange = function(_, text)
            row.below = tonumber(text) or 0
            save()
        end
    end
    if widget.every then
        widget.every:setText(tostring(row.every or 0))
        widget.every.onTextChange = function(_, text)
            row.every = tonumber(text) or 0
            save()
        end
    end
    if widget.stat then
        widget.stat:setText(row.stat == 'mp' and 'MP' or 'HP')
        widget.stat.onClick = function(self)
            row.stat = row.stat == 'mp' and 'hp' or 'mp'
            self:setText(row.stat == 'mp' and 'MP' or 'HP')
            save()
        end
    end
    if widget.partyOnly then
        widget.partyOnly:setChecked(row.party)
        widget.partyOnly.onCheckChange = function(_, checked)
            row.party = checked
            save()
        end
    end
end

local function fill()
    for _, part in ipairs({ { 'healRows', 'heal', 'HealRow' }, { 'friendRows', 'friends', 'FriendRow' }, { 'buffRows', 'buffs', 'BuffRow' } }) do
        local panel = window:getChildById(part[1])
        panel:destroyChildren()
        for _, row in ipairs(cfg[part[2]]) do
            bindRow(g_ui.createWidget(part[3], panel), row)
        end
    end
end

local function updateButton()
    if toolbarButton then
        toolbarButton:setOn(running)
        toolbarButton:setTooltip(running and tr('Heal Bot (on)') or tr('Heal Bot (off)'))
    end
end

function setRunning(value)
    running = value and true or false
    if window then
        window.master:setChecked(running)
    end
    updateButton()
end

function show()
    if not window then
        return
    end
    fill()
    window:show()
    window:raise()
    window:focus()
end

function hide()
    if window then
        window:hide()
    end
    save()
end

function toggle()
    if window and window:isVisible() then
        hide()
    else
        show()
    end
end

local function onGameStart()
    load()
    running = false
    nextSpell, nextPotion, buffCast = 0, 0, {}
    if not toolbarButton and modules.game_mainpanel then
        toolbarButton = modules.game_mainpanel.addToggleButton('healBotButton', tr('Heal Bot (off)'),
            '/game_healbot/images/button', toggle, false, 22)
    end
    setRunning(false)
end

local function onGameEnd()
    save()
    setRunning(false)
    hide()
end

function init()
    window = g_ui.displayUI('healbot')
    window:hide()
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    tickEvent = cycleEvent(tick, TICK)
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    save()
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    if toolbarButton then
        toolbarButton:destroy()
        toolbarButton = nil
    end
    if window then
        window:destroy()
        window = nil
    end
end
