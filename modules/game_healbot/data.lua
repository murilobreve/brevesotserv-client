-- What the heal bot can use: potions (with the vocation and level rules the
-- server checks in data/scripts/actions/items/potions.lua) and spells taken
-- from SpellInfo, filtered by the character's vocation.

HealData = {}

-- base vocation ids, as the server and SpellInfo use them
local SORCERER, DRUID, PALADIN, KNIGHT, MONK = 1, 2, 3, 4, 9

HealData.potions = {
    { id = 7876, name = 'Small Health Potion', stat = 'hp' },
    { id = 266, name = 'Health Potion', stat = 'hp' },
    { id = 236, name = 'Strong Health Potion', stat = 'hp', level = 50, vocations = { PALADIN, KNIGHT, MONK } },
    { id = 239, name = 'Great Health Potion', stat = 'hp', level = 80, vocations = { KNIGHT } },
    { id = 7643, name = 'Ultimate Health Potion', stat = 'hp', level = 130, vocations = { KNIGHT } },
    { id = 23375, name = 'Supreme Health Potion', stat = 'hp', level = 200, vocations = { KNIGHT } },
    { id = 268, name = 'Mana Potion', stat = 'mp' },
    { id = 237, name = 'Strong Mana Potion', stat = 'mp', level = 50 },
    { id = 238, name = 'Great Mana Potion', stat = 'mp', level = 80, vocations = { SORCERER, DRUID, PALADIN, MONK } },
    { id = 23373, name = 'Ultimate Mana Potion', stat = 'mp', level = 130, vocations = { SORCERER, DRUID } },
    { id = 7642, name = 'Great Spirit Potion', stat = 'hp', level = 80, vocations = { PALADIN, MONK } },
    { id = 23374, name = 'Ultimate Spirit Potion', stat = 'hp', level = 130, vocations = { PALADIN, MONK } },
}

-- condition the player has -> spell that removes it
HealData.cures = {
    { state = 'Poison', words = 'exana pox' },
    { state = 'Burn', words = 'exana flam' },
    { state = 'Energy', words = 'exana vis' },
    { state = 'Cursed', words = 'exana mort' },
    { state = 'Bleeding', words = 'exana kor' },
}

local HEALING_GROUP = 2

-- the client gets Tibia's own vocation ids (1 knight ... 5 monk, +10 when
-- promoted); SpellInfo and the server use their base ids
local CLIENT_VOCATIONS = {
    [1] = KNIGHT, [11] = KNIGHT,
    [2] = PALADIN, [12] = PALADIN,
    [3] = SORCERER, [13] = SORCERER,
    [4] = DRUID, [14] = DRUID,
    [5] = MONK, [15] = MONK,
}

function HealData.vocation(player)
    return CLIENT_VOCATIONS[player:getVocation()] or 0
end

function HealData.potion(id)
    for _, potion in ipairs(HealData.potions) do
        if potion.id == id then
            return potion
        end
    end
end

function HealData.potionsFor(vocation)
    local list = {}
    for _, potion in ipairs(HealData.potions) do
        if not potion.vocations or table.contains(potion.vocations, vocation) then
            list[#list + 1] = potion
        end
    end
    return list
end

local spellCache = {}

-- 0 means "none": SpellInfo has a real spell with id 0
function HealData.spell(id)
    if not id or id == 0 then
        return nil
    end
    if spellCache[id] == nil then
        spellCache[id] = Spells.getSpellDataById(id) or false
    end
    return spellCache[id] or nil
end

local function vocationSpells(vocation, accept)
    local list = {}
    for _, spell in pairs(SpellInfo.Default) do
        if table.contains(spell.vocations, vocation) and accept(spell) then
            list[#list + 1] = spell
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then
            return a.level < b.level
        end
        return a.words < b.words
    end)
    return list
end

local function isHealing(spell)
    return Spells.getPrimaryGroup(spell) == HEALING_GROUP and not spell.words:find('^exana')
end

-- spells that heal the caster
function HealData.healSpells(vocation)
    return vocationSpells(vocation, function(spell)
        return isHealing(spell) and not spell.parameter
    end)
end

-- spells cast on another player: exura sio "name"
function HealData.friendSpells(vocation)
    return vocationSpells(vocation, function(spell)
        return isHealing(spell) and spell.parameter
    end)
end

function HealData.hasteSpells(vocation)
    return vocationSpells(vocation, function(spell)
        return spell.words:find('^utani') ~= nil
    end)
end

function HealData.shieldSpells(vocation)
    return vocationSpells(vocation, function(spell)
        return spell.words == 'utamo vita'
    end)
end

local curesCache = {}

function HealData.curesFor(vocation)
    if curesCache[vocation] then
        return curesCache[vocation]
    end
    local list = {}
    for _, cure in ipairs(HealData.cures) do
        local spell = Spells.getSpellByWords(cure.words)
        if spell and table.contains(spell.vocations, vocation) then
            list[#list + 1] = { state = PlayerStates[cure.state], spell = spell }
        end
    end
    curesCache[vocation] = list
    return list
end

-- the strongest entry of a list the character can already use
function HealData.best(list, level, accept)
    local found
    for _, entry in ipairs(list) do
        if (entry.level or 0) <= level and (not accept or accept(entry)) then
            found = entry
        end
    end
    return found
end
