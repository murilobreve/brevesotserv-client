-- Heal bot window and settings. What to cast or drink is decided in
-- engine.lua; the spell and potion lists come from data.lua. Settings are
-- saved per character.

local window, toolbarButton, countEvent
local cfg
local CONFIG_VERSION = 3
local SPELL_RULES, POTION_RULES, FRIEND_RULES = 4, 3, 2
local PAGES = { 'healing', 'potions', 'friends', 'support' }
local PAGE_ICONS = {
    healing = '/images/icons/icon-healing',
    potions = '/images/icons/icon_health',
    friends = '/images/icons/icon_players',
    support = '/images/icons/icon_magic',
}

-- ---------------------------------------------------------------------------
-- settings
-- ---------------------------------------------------------------------------

local function characterKey()
    local player = g_game.getLocalPlayer()
    return player and player:getName() or ''
end

-- never preselected: the regeneration buffs and the long-cooldown heals cast
-- once a minute or less, and Charge is a 5 second haste for 100 mana. They
-- stay in the lists, so a player can still pick them by hand
local NOT_DEFAULT = {
    ['utura'] = true,
    ['utura gran'] = true,
    ['exura gran ico'] = true,
    ['exura gran sio'] = true,
    ['utani tempo hur'] = true,
}

local function defaults(player)
    local vocation, level = HealData.vocation(player), player:getLevel()
    local function bestSpell(list)
        local spell = HealData.best(list, level, function(s)
            return not NOT_DEFAULT[s.words]
        end)
        return spell and spell.id or 0
    end
    local function bestPotion(stat)
        local potion = HealData.best(HealData.potionsFor(vocation), level, function(p)
            return p.stat == stat
        end)
        return potion and potion.id or 0
    end

    local config = { version = CONFIG_VERSION, spells = {}, potions = {}, friends = {} }
    for i = 1, SPELL_RULES do
        config.spells[i] = { on = false, spell = 0, stat = 'hp', below = 70 }
    end
    -- mass healing costs much more mana, so the default is the best single heal
    local single = {}
    for _, spell in ipairs(HealData.healSpells(vocation)) do
        if not spell.words:find(' mas ') then
            single[#single + 1] = spell
        end
    end
    config.spells[1].spell = bestSpell(single)
    config.spells[1].on = config.spells[1].spell ~= 0
    for i = 1, POTION_RULES do
        config.potions[i] = { on = false, item = 0, stat = 'hp', below = 50 }
    end
    config.potions[1].item = bestPotion('hp')
    config.potions[2].item, config.potions[2].stat, config.potions[2].below = bestPotion('mp'), 'mp', 40
    config.potions[1].on = config.potions[1].item ~= 0
    config.potions[2].on = config.potions[2].item ~= 0
    for i = 1, FRIEND_RULES do
        config.friends[i] = { on = false, spell = 0, below = 60, party = true }
    end
    config.friends[1].spell = bestSpell(HealData.friendSpells(vocation))
    config.support = {
        shield = { on = false, spell = bestSpell(HealData.shieldSpells(vocation)) },
        haste = { on = false, spell = bestSpell(HealData.hasteSpells(vocation)) },
        cures = false,
        antiIdle = false,
    }
    -- the bot starts on with the best heal and potions; turning it off is
    -- remembered per character
    config.running = true
    return config
end

-- g_settings stores everything as text with string keys, so read each field
-- back with the type the default has
local function merge(into, saved)
    if type(saved) ~= 'table' then
        return into
    end
    for key, value in pairs(into) do
        local s = saved[key]
        if s == nil then
            s = saved[tostring(key)]
        end
        if type(value) == 'table' then
            merge(value, s)
        elseif s ~= nil then
            if type(value) == 'boolean' then
                into[key] = s == true or s == 'true'
            elseif type(value) == 'number' then
                into[key] = tonumber(s) or value
            else
                into[key] = tostring(s)
            end
        end
    end
    return into
end

local function toNode(value)
    if type(value) ~= 'table' then
        return value
    end
    local out = {}
    for key, v in pairs(value) do
        out[tostring(key)] = toNode(v)
    end
    return out
end

-- drop choices this vocation can't use (a config saved before a vocation
-- change, or edited by hand)
local function sanitize(config, vocation)
    local function check(rule, field, list)
        for _, entry in ipairs(list) do
            if entry.id == rule[field] then
                return
            end
        end
        rule[field] = 0
    end
    local heal, friend = HealData.healSpells(vocation), HealData.friendSpells(vocation)
    local potions = HealData.potionsFor(vocation)
    for _, rule in ipairs(config.spells) do
        check(rule, 'spell', heal)
    end
    for _, rule in ipairs(config.potions) do
        check(rule, 'item', potions)
    end
    for _, rule in ipairs(config.friends) do
        check(rule, 'spell', friend)
    end
    check(config.support.shield, 'spell', HealData.shieldSpells(vocation))
    check(config.support.haste, 'spell', HealData.hasteSpells(vocation))
end

local function load()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end
    local saved = (g_settings.getNode('healbot') or {})[characterKey()]
    cfg = defaults(player)
    if type(saved) ~= 'table' then
        return
    end
    local version = tonumber(saved.version)
    if version == CONFIG_VERSION then
        merge(cfg, saved)
        sanitize(cfg, HealData.vocation(player))
    elseif version == 2 then
        -- version 2 started with every rule off: keep what the player turned
        -- on, and give the defaults to who never turned anything on
        local fresh = defaults(player)
        merge(cfg, saved)
        local any = false
        for _, list in ipairs({ cfg.spells, cfg.potions }) do
            for _, rule in ipairs(list) do
                any = any or rule.on
            end
        end
        if not any then
            cfg.spells[1].on = fresh.spells[1].on
            cfg.potions[1].on, cfg.potions[2].on = fresh.potions[1].on, fresh.potions[2].on
        end
        cfg.version = CONFIG_VERSION
        sanitize(cfg, HealData.vocation(player))
    end
end

local function save()
    if not cfg or characterKey() == '' then
        return
    end
    local all = g_settings.getNode('healbot') or {}
    all[characterKey()] = toNode(cfg)
    g_settings.setNode('healbot', all)
end

-- ---------------------------------------------------------------------------
-- rule rows
-- ---------------------------------------------------------------------------

local function setSpellIcon(icon, spell)
    if spell then
        icon:setImageSource(SpelllistSettings.Default.iconFile)
        icon:setImageClip(Spells.getImageClip(tonumber(spell.clientId) or 0, 'Default'))
        icon:setTooltip(string.format('%s\n%s: %d   %s: %d', spell.name, tr('Level'), spell.level, tr('Mana'), spell.mana))
    else
        icon:setImageSource('')
        icon:removeTooltip()
    end
end

local function fillCombo(combo, entries, selected, label, onChange)
    combo:clearOptions()
    combo:addOption(tr('None'), 0)
    for _, entry in ipairs(entries) do
        combo:addOption(label(entry), entry.id)
    end
    combo:setCurrentOptionByData(selected, true)
    combo.onOptionChange = function(_, _, data)
        onChange(data)
        save()
    end
end

local function spellLabel(spell)
    return spell.words
end

local function bindCheck(check, rule, field)
    check:setChecked(rule[field])
    check.onCheckChange = function(_, checked)
        rule[field] = checked
        save()
    end
end

local function bindSlider(widget, rule)
    local function show(value)
        widget.belowLabel:setText(value .. '%')
    end
    widget.below:setValue(rule.below)
    show(rule.below)
    widget.below.onValueChange = function(_, value)
        rule.below = value
        show(value)
        save()
    end
end

local function bindStat(combo, rule)
    combo:clearOptions()
    combo:addOption(tr('Health'), 'hp')
    combo:addOption(tr('Mana'), 'mp')
    combo:setCurrentOptionByData(rule.stat, true)
    combo.onOptionChange = function(_, _, data)
        rule.stat = data
        save()
    end
end

local function showPotion(widget, id)
    widget.item:setItemId(id)
    if id > 0 then
        local count = HealEngine.potionCount(id)
        widget.item:setItemCount(math.max(count, 1))
        widget.item:setShowCount(true)
        widget.item:setTooltip(string.format('%s\n%s', HealData.potion(id).name, tr('You have %d.', count)))
        widget.item:setOpacity(count > 0 and 1 or 0.4)
    else
        widget.item:removeTooltip()
    end
end

local function addSpellRule(panel, rule, spells)
    local widget = g_ui.createWidget('SpellRule', panel)
    bindCheck(widget.enabled, rule, 'on')
    setSpellIcon(widget.icon, HealData.spell(rule.spell))
    fillCombo(widget.choice, spells, rule.spell, spellLabel, function(id)
        rule.spell = id
        HealEngine.forget(id)
        setSpellIcon(widget.icon, HealData.spell(id))
    end)
    bindStat(widget.stat, rule)
    bindSlider(widget, rule)
end

local function addPotionRule(panel, rule, potions)
    local widget = g_ui.createWidget('PotionRule', panel)
    widget.icon:hide()
    bindCheck(widget.enabled, rule, 'on')
    showPotion(widget, rule.item)
    fillCombo(widget.choice, potions, rule.item, function(p)
        return p.name
    end, function(id)
        rule.item = id
        local potion = HealData.potion(id)
        if potion then
            rule.stat = potion.stat
            widget.stat:setCurrentOptionByData(rule.stat, true)
        end
        showPotion(widget, id)
    end)
    bindStat(widget.stat, rule)
    bindSlider(widget, rule)
    widget.potionRule = rule
end

local function addFriendRule(panel, rule, spells)
    local widget = g_ui.createWidget('FriendRule', panel)
    bindCheck(widget.enabled, rule, 'on')
    bindCheck(widget.party, rule, 'party')
    setSpellIcon(widget.icon, HealData.spell(rule.spell))
    fillCombo(widget.choice, spells, rule.spell, spellLabel, function(id)
        rule.spell = id
        HealEngine.forget(id)
        setSpellIcon(widget.icon, HealData.spell(id))
    end)
    bindSlider(widget, rule)
end

local function addSupportRule(panel, rule, spells, note)
    local widget = g_ui.createWidget('SupportRule', panel)
    bindCheck(widget.enabled, rule, 'on')
    setSpellIcon(widget.icon, HealData.spell(rule.spell))
    fillCombo(widget.choice, spells, rule.spell, spellLabel, function(id)
        rule.spell = id
        HealEngine.forget(id)
        setSpellIcon(widget.icon, HealData.spell(id))
    end)
    widget.note:setText(note)
end

local function addCureRule(panel, vocation)
    local widget = g_ui.createWidget('CureRule', panel)
    local words = {}
    for _, cure in ipairs(HealData.curesFor(vocation)) do
        words[#words + 1] = cure.spell.words
    end
    bindCheck(widget.enabled, cfg.support, 'cures')
    if #words == 0 then
        widget.enabled:setEnabled(false)
        widget.note:setText(tr('Your vocation has no spell that cures conditions.'))
    else
        widget.note:setText(tr('Cure conditions with %s', table.concat(words, ', ')))
    end
end

local function clearRules(page)
    for i = page:getChildCount(), 2, -1 do
        page:getChildByIndex(i):destroy()
    end
end

local function fill()
    local player = g_game.getLocalPlayer()
    if not player or not cfg then
        return
    end
    local vocation = HealData.vocation(player)

    local page = window.content.healingPage
    clearRules(page)
    local healSpells = HealData.healSpells(vocation)
    for _, rule in ipairs(cfg.spells) do
        addSpellRule(page, rule, healSpells)
    end

    page = window.content.potionsPage
    clearRules(page)
    local potions = HealData.potionsFor(vocation)
    for _, rule in ipairs(cfg.potions) do
        addPotionRule(page, rule, potions)
    end

    page = window.content.friendsPage
    clearRules(page)
    local friendSpells = HealData.friendSpells(vocation)
    for _, rule in ipairs(cfg.friends) do
        addFriendRule(page, rule, friendSpells)
    end

    page = window.content.supportPage
    clearRules(page)
    addSupportRule(page, cfg.support.shield, HealData.shieldSpells(vocation), tr('Magic shield: cast again when it runs out.'))
    addSupportRule(page, cfg.support.haste, HealData.hasteSpells(vocation),
        tr('Haste: cast again when it runs out or when you get paralyzed.'))
    addCureRule(page, vocation)
    local idle = g_ui.createWidget('CureRule', page)
    bindCheck(idle.enabled, cfg.support, 'antiIdle')
    idle.note:setText(tr('Anti idle: turns your character every 5 minutes so the server does not log you out.'))
end

local function refreshCounts()
    if not window or not window:isVisible() then
        return
    end
    for _, widget in ipairs(window.content.potionsPage:getChildren()) do
        if widget.potionRule then
            showPotion(widget, widget.potionRule.item)
        end
    end
end

local function selectPage(id)
    for _, name in ipairs(PAGES) do
        window.categories[name]:setChecked(name == id)
        window.content[name .. 'Page']:setVisible(name == id)
    end
end

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

local function updateButton()
    if toolbarButton then
        toolbarButton:setOn(HealEngine.isRunning())
        toolbarButton:setTooltip(HealEngine.isRunning() and tr('Heal Bot (on)') or tr('Heal Bot (off)'))
    end
    if modules.game_brevespanel then
        modules.game_brevespanel.setFeatureState('healbot', HealEngine.isRunning() and 'ON' or 'OFF',
            HealEngine.isRunning() and '#7fd35a' or '#909090')
    end
end

local function onAction(message)
    if window then
        window.status:setText(message)
    end
end

function setRunning(value, keep)
    HealEngine.setRunning(value)
    if cfg and not keep and cfg.running ~= HealEngine.isRunning() then
        cfg.running = HealEngine.isRunning()
        save()
    end
    if window and window.master:isChecked() ~= HealEngine.isRunning() then
        window.master:setChecked(HealEngine.isRunning())
    end
    updateButton()
end

function show()
    if not window or not g_game.isOnline() then
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
    HealEngine.reset()
    setRunning(cfg and cfg.running, true)
    window.status:setText('')
    if not toolbarButton and modules.game_brevespanel then
        toolbarButton = modules.game_brevespanel.addFeature('healbot', toggle)
        if toolbarButton and modules.game_brevespanel.setFeatureToggle then
            modules.game_brevespanel.setFeatureToggle('healbot', function()
                setRunning(not HealEngine.isRunning())
            end)
        end
    end
    if not toolbarButton and modules.game_mainpanel then
        toolbarButton = modules.game_mainpanel.addToggleButton('healBotButton', tr('Heal Bot (off)'),
            '/game_healbot/images/button', toggle, false, 22)
    end
    updateButton()
end

-- the vocation arrives after onGameStart, so defaults and the saved rules
-- are checked again once it is known
local function onVocationChange()
    load()
    setRunning(cfg and cfg.running, true)
    if window and window:isVisible() then
        fill()
    end
end

local function onGameEnd()
    save()
    setRunning(false, true)
    hide()
    cfg = nil
end

function init()
    window = g_ui.displayUI('healbot')
    window:hide()
    for _, name in ipairs(PAGES) do
        window.categories[name].icon:setImageSource(PAGE_ICONS[name])
        window.categories[name].onClick = function()
            selectPage(name)
        end
    end
    selectPage('healing')

    HealEngine.init(function()
        return cfg
    end, onAction)
    countEvent = cycleEvent(refreshCounts, 1000)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    connect(LocalPlayer, { onVocationChange = onVocationChange })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    disconnect(LocalPlayer, { onVocationChange = onVocationChange })
    save()
    HealEngine.terminate()
    if countEvent then
        removeEvent(countEvent)
        countEvent = nil
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
