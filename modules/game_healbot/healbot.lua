-- Heal bot window and settings. What to cast or drink is decided in
-- engine.lua; the spell and potion lists come from data.lua. Settings are
-- saved per character.

local window, toolbarButton, countEvent
local cfg
local CONFIG_VERSION = 4
-- (6, 5 and 4 since 2026-11-28: a rule saved before keeps its place, the new
-- ones come off and empty)
local SPELL_RULES, POTION_RULES, FRIEND_RULES = 6, 5, 4
local FRIEND_PARTY, FRIEND_ANYONE = HealData.FRIEND_PARTY, HealData.FRIEND_ANYONE
local PAGES = { 'healing', 'potions', 'friends', 'support', 'caster', 'loot' }
local CASTER_SPELLS, CASTER_RUNES, CASTER_COUNT, CASTER_PRESETS = 8, 4, 10, 5
-- which monster the auto attack takes (engine.lua, autoAttack)
local CASTER_PICKS = { 'near', 'weak', 'strong' }
local CASTER_PICK_NAMES = { near = 'Nearest', weak = 'Least health', strong = 'Most health' }
-- the bot's own keys (Options, Hotkeys): none until the player sets them
local KEY_CATEGORY = 'Heal Bot'
local KEY_BOT, KEY_CASTER, KEY_PRESET = 'Ligar/desligar o bot', 'Ligar/desligar o Caster', 'Trocar o preset do Caster'
local PAGE_ICONS = {
    healing = '/images/icons/icon-healing',
    potions = '/images/icons/icon_health',
    friends = '/images/icons/icon_players',
    support = '/images/icons/icon_magic',
    caster = '/images/icons/icon-damage',
    loot = '/game_brevespanel/images/loot',
}

-- the auto loot lives in game_quickloot (the server loots on each kill what
-- its list says); the bot's Loot page shows that list's rule and opens it
local function quickLoot()
    return modules.game_quickloot and modules.game_quickloot.QuickLoot
end

local function fillLoot()
    local page = window.content.lootPage
    local loot = quickLoot()
    local text
    if not loot or not loot.priceRule then
        text = tr('The auto loot is not available on this client.')
    elseif loot.priceRule().enabled then
        text = tr('Auto loot on: coins, items worth %d gold or more, and your list', loot.priceRule().min)
    else
        text = tr('Auto loot on: the items on your list')
    end
    page.state:setText(text)
    page.open.onClick = function()
        if loot and loot.toggle then
            loot.toggle()
        end
    end
end

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

-- the cheapest way to spend mana: utana vid, else light, else any
local TRAIN_DEFAULTS = { 'utana vid', 'utevo lux', 'utevo gran lux' }

local function bestTrainSpell(list)
    for _, words in ipairs(TRAIN_DEFAULTS) do
        for _, spell in ipairs(list) do
            if spell.words == words then
                return spell.id
            end
        end
    end
    return list[1] and list[1].id or 0
end

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
    -- target: the whole party (FRIEND_PARTY), anyone (FRIEND_ANYONE) or one
    -- character by name
    for i = 1, FRIEND_RULES do
        config.friends[i] = { on = false, spell = 0, below = 60, target = FRIEND_PARTY }
    end
    config.friends[1].spell = bestSpell(HealData.friendSpells(vocation))
    config.support = {
        -- `below`: the health the magic shield comes on at (100: always,
        -- as it was before the slider)
        shield = { on = false, spell = bestSpell(HealData.shieldSpells(vocation)), below = 100 },
        -- exana vita once the health is back at `below` or more (the slider
        -- is shared, the field keeps its name): only over the shield's own
        unshield = { on = false, below = 90 },
        haste = { on = false, spell = bestSpell(HealData.hasteSpells(vocation)) },
        cures = false,
        -- eats the food in the backpacks until full (engine.lua)
        food = true,
        -- on for everyone: a turn every 5 minutes keeps the character online
        antiIdle = true,
        -- "Using one of 37 great health potions..." when a potion is used
        usingMsg = true,
        -- a red line on the screen when a rule wants a potion and none is left
        potionAlert = true,
        -- `below` is the mana it trains from (the slider is shared)
        train = { on = false, spell = bestTrainSpell(HealData.trainSpells(vocation)), below = 90 },
    }
    -- the caster (engine.lua, pickAttack): a preset is a list of attack
    -- spells tried from the top, each with the mana it needs left (`below`)
    -- and the monsters it waits for, and a list of runes. The player keeps
    -- CASTER_PRESETS of them (one per hunt, say) and picks which is in use.
    -- A rule's `hp` is the health the target must still have (0: any).
    -- `safeOn`/`safeHp`: no attack spell or rune with the character's own
    -- health under it. `pick`: which monster the auto attack takes
    -- (CASTER_PICKS). Off until the player turns it on
    config.caster = {
        on = false, noPlayers = true, runesFirst = false, autoAttack = false, pick = 'near',
        safeOn = false, safeHp = 40, current = 1, presets = {},
    }
    for p = 1, CASTER_PRESETS do
        local preset = { name = 'Preset ' .. p, spells = {}, runes = {} }
        for i = 1, CASTER_SPELLS do
            preset.spells[i] = { on = false, spell = 0, below = 10, hp = 0, count = 1 }
        end
        for i = 1, CASTER_RUNES do
            preset.runes[i] = { on = false, item = 0, hp = 0, count = 1 }
        end
        config.caster.presets[p] = preset
    end
    -- the bot starts on with the best heal and potions
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
    check(config.support.train, 'spell', HealData.trainSpells(vocation))
    -- a number out of its range (a file edited by hand, or cut short by a
    -- crash) goes back into it: the engine compares with these every tick
    local function clamp(rule, field, low, high, fallback)
        local value = math.floor(tonumber(rule[field]) or fallback)
        rule[field] = math.max(low, math.min(high, value))
    end
    for _, list in ipairs({ config.spells, config.potions, config.friends }) do
        for _, rule in ipairs(list) do
            clamp(rule, 'below', 1, 99, 50)
        end
    end
    for _, list in ipairs({ config.spells, config.potions }) do
        for _, rule in ipairs(list) do
            if rule.stat ~= 'mp' then
                rule.stat = 'hp'
            end
        end
    end
    local attack = HealData.attackSpells(vocation)
    for _, preset in ipairs(config.caster.presets) do
        for _, rule in ipairs(preset.spells) do
            check(rule, 'spell', attack)
            clamp(rule, 'below', 0, 99, 10)
            clamp(rule, 'hp', 0, 99, 0)
            clamp(rule, 'count', 1, CASTER_COUNT, 1)
        end
        for _, rule in ipairs(preset.runes) do
            check(rule, 'item', HealData.runes)
            clamp(rule, 'hp', 0, 99, 0)
            clamp(rule, 'count', 1, CASTER_COUNT, 1)
        end
    end
    clamp(config.caster, 'safeHp', 1, 99, 40)
    if not table.contains(CASTER_PICKS, config.caster.pick) then
        config.caster.pick = CASTER_PICKS[1]
    end
    config.caster.current = math.max(1, math.min(#config.caster.presets, math.floor(tonumber(config.caster.current) or 1)))
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
    -- every login starts with the bot on; turning it off lasts the session
    saved.running = nil
    local version = tonumber(saved.version)
    -- a rule saved before the target: its old "party only" box decides
    for i, rule in ipairs(cfg.friends) do
        local old = type(saved.friends) == 'table' and (saved.friends[i] or saved.friends[tostring(i)])
        if type(old) == 'table' and old.target == nil and (old.party == false or old.party == 'false') then
            old.target = FRIEND_ANYONE
        end
    end
    -- the caster's first days kept one list of spells and runes: it becomes
    -- the first preset
    local function oldCaster()
        local old = saved.caster
        if type(old) == 'table' and old.presets == nil and (old.spells or old.runes) then
            merge(cfg.caster.presets[1].spells, old.spells)
            merge(cfg.caster.presets[1].runes, old.runes)
        end
    end
    if version == CONFIG_VERSION then
        merge(cfg, saved)
        oldCaster()
        sanitize(cfg, HealData.vocation(player))
    elseif version == 3 then
        -- version 3 saved the anti idle off for everyone (its old default):
        -- it comes on once, and a player who turns it off keeps it off
        merge(cfg, saved)
        cfg.support.antiIdle = true
        cfg.version = CONFIG_VERSION
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
        cfg.support.antiIdle = true
        cfg.version = CONFIG_VERSION
        sanitize(cfg, HealData.vocation(player))
    end
end

-- the choices go to disk a moment after each change, not only when the
-- client closes: closed any other way (or by the restart of an update), the
-- bot still comes back exactly as it was, every box as it was left
local diskEvent

local function save()
    if not cfg or characterKey() == '' then
        return
    end
    local all = g_settings.getNode('healbot') or {}
    all[characterKey()] = toNode(cfg)
    g_settings.setNode('healbot', all)
    if not diskEvent then
        diskEvent = scheduleEvent(function()
            diskEvent = nil
            g_settings.save()
        end, 1000)
    end
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

-- only what the character can use now, strongest first (the lists of
-- data.lua): a spell or potion his level does not reach yet is not offered
-- and shows up when he gets there (onLevelChange fills the window again).
-- A choice saved before (a level lost on death) stays, marked with its level
local function fillCombo(combo, entries, selected, label, onChange)
    local player = g_game.getLocalPlayer()
    local level = player and player:getLevel() or 0
    combo:clearOptions()
    combo:addOption(tr('None'), 0)
    local listed = false
    for _, entry in ipairs(HealData.usable(entries, level)) do
        combo:addOption(label(entry), entry.id)
        listed = listed or entry.id == selected
    end
    if selected and selected ~= 0 and not listed then
        for _, entry in ipairs(entries) do
            if entry.id == selected then
                combo:addOption(string.format('%s (lv %d)', label(entry), entry.level or 0), entry.id)
            end
        end
    end
    combo:setCurrentOptionByData(selected, true)
    combo.onOptionChange = function(_, _, data)
        onChange(data)
        save()
    end
end

local function spellLabel(spell)
    local name = HealData.ascensao(spell)
    if name then
        return string.format('%s - %s', name, spell.words)
    end
    return spell.words
end

local function bindCheck(check, rule, field)
    check:setChecked(rule[field])
    check.onCheckChange = function(_, checked)
        rule[field] = checked
        save()
    end
end

-- the slider and the box next to it set the same percentage: drag one or type
-- in the other
local function bindSlider(widget, rule)
    local edit = widget.belowEdit
    local syncing = false
    local function show(value)
        syncing = true
        edit:setText(tostring(value))
        syncing = false
    end
    widget.below:setValue(rule.below)
    show(rule.below)
    widget.below.onValueChange = function(_, value)
        rule.below = value
        if not syncing then
            show(value)
        end
        save()
    end
    edit:setTooltip(tr('Type the percentage, from %d to %d.', widget.below:getMinimum(), widget.below:getMaximum()))
    edit.onTextChange = function(_, text)
        if syncing then
            return
        end
        local digits = text:gsub('[^%d]', '')
        if digits ~= text then
            show(digits)
        end
        local value = tonumber(digits)
        if value and value >= widget.below:getMinimum() and value <= widget.below:getMaximum() then
            syncing = true
            widget.below:setValue(value)
            syncing = false
        end
    end
    -- an empty box or a number out of range goes back to the rule's value
    edit.onFocusChange = function(_, focused)
        if not focused then
            show(rule.below)
        end
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

-- who a friend rule heals: the whole party, anyone, or one of the party
-- members on screen (the chosen one stays listed while away)
local friendTargets = {}

local function partyMembersInView()
    local names = {}
    local player = g_game.getLocalPlayer()
    if not player then
        return names
    end
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), false)) do
        local shield = creature:getShield()
        if creature:isPlayer() and not creature:isLocalPlayer() and shield >= ShieldBlue and shield <= ShieldYellowNoSharedExp then
            names[#names + 1] = creature:getName()
        end
    end
    table.sort(names)
    return names
end

local function fillTargets(combo, rule)
    combo.onOptionChange = nil
    combo:clearOptions()
    combo:addOption(tr('Whole party'), FRIEND_PARTY)
    combo:addOption(tr('Anyone'), FRIEND_ANYONE)
    local listed = rule.target == FRIEND_PARTY or rule.target == FRIEND_ANYONE
    for _, name in ipairs(partyMembersInView()) do
        combo:addOption(name, name)
        listed = listed or name:lower() == rule.target:lower()
    end
    if not listed then
        combo:addOption(rule.target, rule.target)
    end
    combo:setCurrentOptionByData(rule.target, true)
    combo.onOptionChange = function(_, _, data)
        rule.target = data
        save()
    end
end

local function refreshTargets()
    for combo, rule in pairs(friendTargets) do
        if combo:isDestroyed() then
            friendTargets[combo] = nil
        else
            fillTargets(combo, rule)
        end
    end
end

local function addFriendRule(panel, rule, spells)
    local widget = g_ui.createWidget('FriendRule', panel)
    -- room for the target list at the end of the row
    widget.choice:setWidth(112)
    bindCheck(widget.enabled, rule, 'on')
    friendTargets[widget.target] = rule
    fillTargets(widget.target, rule)
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

-- the magic shield: its spell and the health it is cast at
local function addShieldRule(panel, rule, spells)
    local widget = g_ui.createWidget('ShieldRule', panel)
    widget.choice:setWidth(110)
    bindCheck(widget.enabled, rule, 'on')
    setSpellIcon(widget.icon, HealData.spell(rule.spell))
    fillCombo(widget.choice, spells, rule.spell, spellLabel, function(id)
        rule.spell = id
        HealEngine.forget(id)
        setSpellIcon(widget.icon, HealData.spell(id))
    end)
    bindSlider(widget, rule)
    widget.label:setTooltip(tr('The magic shield is cast when your health is at this percentage or less. 100 keeps it always on.'))
end

-- exana vita: only for the vocations that have it
local function addUnshieldRule(panel, rule, spell)
    if not spell then
        return
    end
    local widget = g_ui.createWidget('UnshieldRule', panel)
    bindCheck(widget.enabled, rule, 'on')
    setSpellIcon(widget.icon, spell)
    bindSlider(widget, rule)
    widget.label:setTooltip(tr('Takes the magic shield off when your health is back at this percentage or more. It must be above the health the shield comes on at.'))
end

local function addTrainRule(panel, rule, spells)
    local widget = g_ui.createWidget('TrainRule', panel)
    widget.choice:setWidth(120)
    bindCheck(widget.enabled, rule, 'on')
    setSpellIcon(widget.icon, HealData.spell(rule.spell))
    fillCombo(widget.choice, spells, rule.spell, spellLabel, function(id)
        rule.spell = id
        HealEngine.forget(id)
        setSpellIcon(widget.icon, HealData.spell(id))
    end)
    bindSlider(widget, rule)
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
    for i = page:getChildCount(), 1, -1 do
        page:getChildByIndex(i):destroy()
    end
end

-- rules the player opened with "Add rule" this session, by page and slot
-- (an empty rule in use is not hidden again under his hands)
local opened = { spells = {}, potions = {}, friends = {} }

local fill

-- Only the rules in use show; the empty slots come one at a time with the
-- "Add rule" button, where there used to be a column of "None" rows.
local function addRules(page, kind, rules, field, add)
    local nextEmpty
    for index, rule in ipairs(rules) do
        if (tonumber(rule[field]) or 0) ~= 0 or opened[kind][index] then
            add(rule)
        elseif not nextEmpty then
            nextEmpty = index
        end
    end
    if nextEmpty then
        local button = g_ui.createWidget('HealBotAdd', page)
        button:setText(tr('+ Add rule'))
        button.onClick = function()
            opened[kind][nextEmpty] = true
            fill()
        end
    end
end

-- ---------------------------------------------------------------------------
-- the Caster page: presets of attack spells and runes, in the order tried
-- ---------------------------------------------------------------------------

-- rules opened with "Add" this session and still empty: they stay in sight
local shown = setmetatable({}, { __mode = 'k' })
local fillCaster

local function casterPreset()
    local caster = cfg.caster
    return caster.presets[caster.current] or caster.presets[1]
end

local function inUse(rule, field)
    return (tonumber(rule[field]) or 0) ~= 0 or shown[rule] == true
end

-- the rules in use first, in their order: the list has no holes
local function compact(rules, field)
    local used, empty = {}, {}
    for _, rule in ipairs(rules) do
        table.insert(inUse(rule, field) and used or empty, rule)
    end
    for index = 1, #rules do
        rules[index] = used[index] or empty[index - #used]
    end
    return #used
end

-- a percentage typed in a box: the mana a rule needs left, the health its
-- target must still have, the health the caster stops at
local function bindPercent(edit, rule, field, low, high, tooltip)
    local function show()
        edit:setText(tostring(rule[field]))
    end
    edit.onTextChange = nil
    show()
    edit:setTooltip(tooltip)
    edit.onTextChange = function(_, text)
        local digits = text:gsub('[^%d]', '')
        if digits ~= text then
            edit:setText(digits)
            return
        end
        local value = tonumber(digits)
        if value and value >= low and value <= high then
            rule[field] = value
            save()
        end
    end
    edit.onFocusChange = function(_, focused)
        if not focused then
            show()
        end
    end
end

-- how many monsters a rule waits for: "1+" ... "10+"
local function bindCount(combo, rule)
    combo:clearOptions()
    for count = 1, CASTER_COUNT do
        combo:addOption(count .. '+', count)
    end
    combo:setCurrentOptionByData(tonumber(rule.count) or 1, true)
    combo.onOptionChange = function(_, _, data)
        rule.count = data
        save()
    end
    combo:setTooltip(tr('Monsters it waits for: within 3 sqm of you for a spell cast on yourself, within 2 sqm of the target for a spell with a range or a rune, the ones the wave hits for a wave or a beam.'))
end

-- the order number, the switch and the three buttons every rule has
local function bindRow(widget, rules, index, used, field, blank)
    local rule = rules[index]
    widget.order:setText(tostring(index))
    bindCheck(widget.enabled, rule, 'on')
    widget.up:setEnabled(index > 1)
    widget.down:setEnabled(index < used)
    widget.up:setTooltip(tr('Try it earlier'))
    widget.down:setTooltip(tr('Try it later'))
    widget.remove:setTooltip(tr('Remove this rule'))
    widget.up.onClick = function()
        rules[index], rules[index - 1] = rules[index - 1], rules[index]
        save()
        fillCaster()
    end
    widget.down.onClick = function()
        rules[index], rules[index + 1] = rules[index + 1], rules[index]
        save()
        fillCaster()
    end
    widget.remove.onClick = function()
        shown[rule] = nil
        for key, value in pairs(blank) do
            rule[key] = value
        end
        save()
        fillCaster()
    end
end

local function addCasterSpell(list, rules, index, used, spells)
    local rule = rules[index]
    local widget = g_ui.createWidget('CasterSpellRow', list)
    bindRow(widget, rules, index, used, 'spell', { on = false, spell = 0, below = 10, hp = 0, count = 1 })
    -- a wave or a beam says so: the character is turned for it
    local function showSpell(id)
        local spell = HealData.spell(id)
        setSpellIcon(widget.icon, spell)
        if HealData.directional(spell) then
            widget.icon:setTooltip(widget.icon:getTooltip() .. '\n' ..
                tr('The character turns to the target by itself. Not cast with the target in a diagonal or out of reach.'))
        end
    end
    showSpell(rule.spell)
    fillCombo(widget.choice, spells, rule.spell, spellLabel, function(id)
        rule.spell = id
        -- picked: it works at once, no second click on its box
        rule.on = id ~= 0
        widget.enabled:setChecked(rule.on)
        HealEngine.forget(id)
        showSpell(id)
    end)
    bindPercent(widget.below, rule, 'below', 0, 99, tr('Cast only with this much mana or more.'))
    bindPercent(widget.hp, rule, 'hp', 0, 99, tr('Used only on a target with this much health or more. 0: on any.'))
    bindCount(widget.count, rule)
end

local function addCasterRune(list, rules, index, used)
    local rule = rules[index]
    local widget = g_ui.createWidget('CasterRuneRow', list)
    bindRow(widget, rules, index, used, 'item', { on = false, item = 0, hp = 0, count = 1 })
    widget.item:setItemId(rule.item)
    fillCombo(widget.choice, HealData.runes, rule.item, function(rune)
        return rune.name
    end, function(id)
        rule.item = id
        rule.on = id ~= 0
        widget.enabled:setChecked(rule.on)
        widget.item:setItemId(id)
    end)
    bindPercent(widget.hp, rule, 'hp', 0, 99, tr('Used only on a target with this much health or more. 0: on any.'))
    bindCount(widget.count, rule)
end

-- one part of the list: its heading, the rules in use and the button that
-- opens the next one
local function addCasterPart(list, title, rules, field, addText, add)
    local used = compact(rules, field)
    local heading = g_ui.createWidget('CasterHeading', list)
    heading.title:setText(title)
    -- the names of the columns, over the boxes of the rules (none to name
    -- while the part is empty; runes have no mana box)
    heading.mana:setVisible(used > 0 and field == 'spell')
    heading.hp:setVisible(used > 0)
    heading.count:setVisible(used > 0)
    for index = 1, used do
        add(index, used)
    end
    if used < #rules then
        local button = g_ui.createWidget('HealBotAdd', list)
        button:setText(addText)
        button.onClick = function()
            shown[rules[used + 1]] = true
            fillCaster()
        end
    end
end

fillCaster = function()
    local player = g_game.getLocalPlayer()
    if not window or not cfg or not player then
        return
    end
    local page, caster = window.content.casterPage, cfg.caster
    local preset = casterPreset()
    bindCheck(page.on, caster, 'on')
    bindCheck(page.noPlayers, caster, 'noPlayers')
    bindCheck(page.runesFirst, caster, 'runesFirst')
    bindCheck(page.autoAttack, caster, 'autoAttack')
    page.autoAttack:setTooltip(tr('With no monster being attacked, attack one on screen that can be reached'))
    page.pick.onOptionChange = nil
    page.pick:clearOptions()
    for _, pick in ipairs(CASTER_PICKS) do
        page.pick:addOption(tr(CASTER_PICK_NAMES[pick]), pick)
    end
    page.pick:setCurrentOptionByData(caster.pick, true)
    page.pick.onOptionChange = function(_, _, data)
        caster.pick = data
        save()
    end
    page.pick:setTooltip(tr('Which monster the auto attack takes. Of two as good, the nearer.'))
    bindCheck(page.safe, caster, 'safeOn')
    page.safe:setTooltip(tr('With your health under this, no attack spell and no rune: the mana stays for the heals.'))
    bindPercent(page.safeHp, caster, 'safeHp', 1, 99, tr('Type the percentage, from %d to %d.', 1, 99))
    page.noPlayers:setTooltip(tr('Wait while a player who is not of my party is on screen'))

    -- the presets by number and name; the box beside it renames the one in use
    local function listPresets()
        page.preset.onOptionChange = nil
        page.preset:clearOptions()
        for index, entry in ipairs(caster.presets) do
            page.preset:addOption(index .. '. ' .. entry.name, index)
        end
        page.preset:setCurrentOptionByData(caster.current, true)
        page.preset.onOptionChange = function(_, _, data)
            caster.current = data
            save()
            fillCaster()
        end
    end
    listPresets()
    page.presetName.onTextChange = nil
    page.presetName:setText(preset.name)
    page.presetName:setTooltip(tr('The name of this preset'))
    page.presetName.onTextChange = function(_, text)
        text = text:gsub('^%s+', ''):sub(1, 16)
        preset.name = text ~= '' and text or ('Preset ' .. caster.current)
        save()
    end
    page.presetName.onFocusChange = function(_, focused)
        if not focused then
            listPresets()
        end
    end

    local list = page.list
    list:destroyChildren()
    local spells = HealData.attackSpells(HealData.vocation(player))
    addCasterPart(list, tr('Spells, tried from the top'), preset.spells, 'spell', tr('+ Add spell'), function(index, used)
        addCasterSpell(list, preset.spells, index, used, spells)
    end)
    addCasterPart(list, tr('Runes on the target'), preset.runes, 'item', tr('+ Add rune'), function(index, used)
        addCasterRune(list, preset.runes, index, used)
    end)
end

fill = function()
    local player = g_game.getLocalPlayer()
    if not player or not cfg then
        return
    end
    local vocation = HealData.vocation(player)

    local page = window.content.healingPage
    clearRules(page)
    local healSpells = HealData.healSpells(vocation)
    addRules(page, 'spells', cfg.spells, 'spell', function(rule)
        addSpellRule(page, rule, healSpells)
    end)

    page = window.content.potionsPage
    clearRules(page)
    local potions = HealData.potionsFor(vocation)
    addRules(page, 'potions', cfg.potions, 'item', function(rule)
        addPotionRule(page, rule, potions)
    end)
    local using = g_ui.createWidget('CureRule', page)
    bindCheck(using.enabled, cfg.support, 'usingMsg')
    using.note:setText(tr('Show the "Using one of ... potions" message'))
    local alert = g_ui.createWidget('CureRule', page)
    bindCheck(alert.enabled, cfg.support, 'potionAlert')
    alert.note:setText(tr('Warn me when a potion of a rule runs out'))

    page = window.content.friendsPage
    clearRules(page)
    local friendSpells = HealData.friendSpells(vocation)
    addRules(page, 'friends', cfg.friends, 'spell', function(rule)
        addFriendRule(page, rule, friendSpells)
    end)

    page = window.content.supportPage
    clearRules(page)
    addShieldRule(page, cfg.support.shield, HealData.shieldSpells(vocation))
    addUnshieldRule(page, cfg.support.unshield, HealData.unshieldSpell(vocation))
    addSupportRule(page, cfg.support.haste, HealData.hasteSpells(vocation), tr('Haste (also when paralyzed)'))
    addCureRule(page, vocation)
    local food = g_ui.createWidget('CureRule', page)
    bindCheck(food.enabled, cfg.support, 'food')
    food.note:setText(tr('Auto food'))
    addTrainRule(page, cfg.support.train, HealData.trainSpells(vocation))
    local idle = g_ui.createWidget('CureRule', page)
    bindCheck(idle.enabled, cfg.support, 'antiIdle')
    idle.note:setText(tr('Anti idle'))
    idle.note:setTooltip(tr('Turns your character every 5 minutes so the server does not log you out.'))

    fillCaster()

    fillLoot()
end

-- Tibia's "Using one of 37 great health potions..." / "Using the last ...",
-- when the bot, a hotkey or the action bar uses a potion (count before the
-- use, as Tibia shows it), so a hunt does not run out of potions unseen.
-- Off in the Potions page
function usingMessage(id)
    if not cfg or not cfg.support or cfg.support.usingMsg == false then
        return
    end
    local potion = HealData.potion(id)
    local count = potion and HealEngine.potionCount(id) or 0
    if count <= 0 or not modules.game_textmessage then
        return
    end
    local name = potion.name:lower()
    local text
    if count == 1 then
        text = string.format('Using the last %s...', name)
    else
        text = string.format('Using one of %d %ss...', count, name)
    end
    modules.game_textmessage.displayStatusMessage(text)
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
            HealEngine.isRunning() and '#60f860' or '#909090')
    end
end

local function onAction(message)
    if window then
        window.status:setText(message)
    end
end

-- what must not go unseen (a potion that ran out): the red line in the
-- middle of the screen, and the window's own line
local function onAlert(message)
    onAction(message)
    if modules.game_textmessage then
        modules.game_textmessage.displayBroadcastMessage(message)
    end
end

-- a key changed something with the window closed: the status line says what
local function say(message)
    onAction(message)
    if modules.game_textmessage then
        modules.game_textmessage.displayStatusMessage(message)
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

-- the keys (Options, Hotkeys, "Heal Bot"): the bot on and off, the caster on
-- and off, the next caster preset that has a rule
function toggleBot()
    if not cfg or not g_game.isOnline() then
        return
    end
    setRunning(not HealEngine.isRunning())
    say(HealEngine.isRunning() and tr('Heal Bot on') or tr('Heal Bot off'))
end

function toggleCaster()
    if not cfg or not g_game.isOnline() then
        return
    end
    cfg.caster.on = not cfg.caster.on
    save()
    if window and window:isVisible() then
        window.content.casterPage.on:setChecked(cfg.caster.on)
    end
    say(cfg.caster.on and tr('Caster on') or tr('Caster off'))
end

local function presetInUse(preset)
    for _, rule in ipairs(preset.spells) do
        if (tonumber(rule.spell) or 0) ~= 0 then
            return true
        end
    end
    for _, rule in ipairs(preset.runes) do
        if (tonumber(rule.item) or 0) ~= 0 then
            return true
        end
    end
    return false
end

function nextPreset()
    if not cfg or not g_game.isOnline() then
        return
    end
    local caster = cfg.caster
    local count = #caster.presets
    for step = 1, count do
        local index = (caster.current - 1 + step) % count + 1
        if index == caster.current or presetInUse(caster.presets[index]) then
            caster.current = index
            break
        end
    end
    save()
    if window and window:isVisible() then
        fillCaster()
    end
    say(tr('Caster preset: %s', caster.presets[caster.current].name))
end

local keysOn = false

local function registerKeys()
    if keysOn or not Keybind then
        return
    end
    keysOn = true
    -- a failure here never stops the bot
    pcall(function()
        for action, callback in pairs({ [KEY_BOT] = toggleBot, [KEY_CASTER] = toggleCaster, [KEY_PRESET] = nextPreset }) do
            Keybind.new(KEY_CATEGORY, action, '', '')
            Keybind.bind(KEY_CATEGORY, action, { { type = KEY_DOWN, callback = callback } })
        end
    end)
end

local function unregisterKeys()
    if not keysOn then
        return
    end
    keysOn = false
    pcall(function()
        for _, action in ipairs({ KEY_BOT, KEY_CASTER, KEY_PRESET }) do
            Keybind.delete(KEY_CATEGORY, action)
        end
    end)
end

-- a new level can open a spell or a potion: the lists follow (only when the
-- set of what he can use changes, so an open list is not closed for nothing)
local usableKey
local levelEvent
local function usableNow()
    local player = g_game.getLocalPlayer()
    if not player then
        return ''
    end
    local level = player:getLevel()
    local key = {}
    for _, list in ipairs({ HealData.potions }) do
        for _, entry in ipairs(list) do
            if (entry.level or 0) <= level then
                key[#key + 1] = entry.id
            end
        end
    end
    for _, spell in pairs(SpellInfo.Default) do
        if (spell.level or 0) <= level then
            key[#key + 1] = spell.id
        end
    end
    table.sort(key)
    return table.concat(key, ',')
end

function show()
    if not window or not g_game.isOnline() then
        return
    end
    usableKey = usableNow()
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

-- set once the vocation of this session is known: a later change is a
-- promotion in the middle of the game
local vocationKnown = false

local function onGameStart()
    local player = g_game.getLocalPlayer()
    vocationKnown = player ~= nil and (player:getVocation() or 0) ~= 0
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
-- are checked again once it is known. A promotion later on keeps the bot
-- on or off as the player left it (load() starts it on, as on every login)
local function onVocationChange()
    local promotion = vocationKnown
    local running = HealEngine.isRunning()
    vocationKnown = true
    load()
    if cfg and promotion then
        cfg.running = running
    end
    setRunning(cfg and cfg.running, true)
    if window and window:isVisible() then
        fill()
    end
end

local function onLevelChange()
    if levelEvent then
        return
    end
    levelEvent = scheduleEvent(function()
        levelEvent = nil
        local key = usableNow()
        if key == usableKey then
            return
        end
        usableKey = key
        if window and window:isVisible() then
            fill()
        end
    end, 300)
end

-- someone joins or leaves the party: the target lists follow
local targetsEvent
local function onShieldChange(creature)
    if not window or not window:isVisible() or targetsEvent or not creature:isPlayer() then
        return
    end
    targetsEvent = scheduleEvent(function()
        targetsEvent = nil
        refreshTargets()
    end, 200)
end

local function onGameEnd()
    save()
    setRunning(false, true)
    hide()
    cfg = nil
    vocationKnown = false
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
    end, onAction, onAlert)
    registerKeys()
    countEvent = cycleEvent(refreshCounts, 1000)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    connect(LocalPlayer, { onVocationChange = onVocationChange, onLevelChange = onLevelChange })
    connect(Creature, { onShieldChange = onShieldChange })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    disconnect(LocalPlayer, { onVocationChange = onVocationChange, onLevelChange = onLevelChange })
    if levelEvent then
        removeEvent(levelEvent)
        levelEvent = nil
    end
    disconnect(Creature, { onShieldChange = onShieldChange })
    save()
    -- the client writes the settings itself as it closes
    if diskEvent then
        removeEvent(diskEvent)
        diskEvent = nil
    end
    HealEngine.terminate()
    unregisterKeys()
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
