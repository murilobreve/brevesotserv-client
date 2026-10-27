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

-- what the auto food eats: id = { regeneration seconds, name }. It is the
-- server's list (data/scripts/actions/items/foods.lua, its value x 12 s)
-- without the decorative cakes, the event eggs and the cookie tray, what
-- gives no regeneration, and the special foods of 20 minutes or more: the
-- server only lets those go down an empty stomach
HealData.foods = {
    [3606] = { 72, 'Egg' },
    [3250] = { 60, 'Carrot' },
    [3577] = { 180, 'Meat' },
    [21145] = { 180, 'Bottle of Glooth Wine' },
    [21144] = { 180, 'Bowl of Glooth Soup' },
    [21143] = { 120, 'Bowl of Glooth Soup' },
    [3578] = { 144, 'Fish' },
    [3579] = { 120, 'Salmon' },
    [23535] = { 360, 'Energy Bar' },
    [23545] = { 360, 'Energy Drink' },
    [3580] = { 204, 'Northern Pike' },
    [3581] = { 48, 'Shrimp' },
    [3582] = { 360, 'Ham' },
    [3583] = { 720, 'Dragon Ham' },
    [3584] = { 60, 'Pear' },
    [3585] = { 72, 'Red Apple' },
    [3586] = { 156, 'Orange' },
    [3587] = { 96, 'Banana' },
    [3588] = { 12, 'Blueberry' },
    [3589] = { 216, 'Coconut' },
    [3590] = { 12, 'Cherry' },
    [3591] = { 24, 'Strawberry' },
    [3592] = { 108, 'Grapes' },
    [904] = { 108, 'Cream Cake' },
    [3593] = { 240, 'Melon' },
    [3594] = { 204, 'Pumpkin' },
    [3595] = { 60, 'Carrot' },
    [3596] = { 72, 'Tomato' },
    [3597] = { 108, 'Corncob' },
    [3598] = { 24, 'Cookie' },
    [3599] = { 24, 'Candy Cane' },
    [3600] = { 120, 'Bread' },
    [3601] = { 36, 'Roll' },
    [3602] = { 96, 'Brown Bread' },
    [3607] = { 108, 'Cheese' },
    [3723] = { 108, 'White Mushroom' },
    [3724] = { 48, 'Red Mushroom' },
    [3725] = { 264, 'Brown Mushroom' },
    [3726] = { 360, 'Orange Mushroom' },
    [3727] = { 108, 'Wood Mushroom' },
    [3728] = { 72, 'Dark Mushroom' },
    [3729] = { 144, 'Some Mushrooms' },
    [3730] = { 36, 'Some Mushrooms' },
    [3731] = { 432, 'Fire Mushroom' },
    [3732] = { 60, 'Green Mushroom' },
    [5096] = { 48, 'Mango' },
    [5678] = { 96, 'Tortoise Egg' },
    [6125] = { 96, 'Tortoise Egg from Nargor' },
    [6277] = { 120, 'Cake' },
    [6393] = { 180, 'Cream Cake' },
    [6500] = { 240, 'Gingerbread Man' },
    [6569] = { 12, 'Candy' },
    [6574] = { 60, 'Bar of Chocolate' },
    [7158] = { 180, 'Rainbow Trout' },
    [7159] = { 156, 'Green Perch' },
    [229] = { 24, 'Ice Cream Cone' },
    [7373] = { 24, 'Ice Cream Cone' },
    [7374] = { 24, 'Ice Cream Cone' },
    [7375] = { 24, 'Ice Cream Cone' },
    [7376] = { 24, 'Ice Cream Cone' },
    [7377] = { 24, 'Ice Cream Cone' },
    [836] = { 48, 'Walnut' },
    [841] = { 48, 'Peanut' },
    [901] = { 720, 'Marlin' },
    [169] = { 108, 'Scarab Cheese' },
    [8010] = { 120, 'Potato' },
    [8011] = { 60, 'Plum' },
    [8012] = { 12, 'Raspberry' },
    [8013] = { 12, 'Lemon' },
    [8014] = { 84, 'Cucumber' },
    [8015] = { 60, 'Onion' },
    [8016] = { 12, 'Jalapeno Pepper' },
    [8017] = { 60, 'Beetroot' },
    [8019] = { 132, 'Chocolate Cake' },
    [8177] = { 84, 'Yummy Gummy Worm' },
    [8197] = { 60, 'Bulb of Garlic' },
    [10329] = { 180, 'Rice Ball' },
    [10453] = { 36, 'Terramite Eggs' },
    [10219] = { 120, 'Crocodile Steak' },
    [11459] = { 240, 'Pineapple' },
    [11460] = { 120, 'Aubergine' },
    [11461] = { 96, 'Broccoli' },
    [11462] = { 108, 'Cauliflower' },
    [11681] = { 660, 'Ectoplasmic Sushi' },
    [11682] = { 216, 'Dragonfruit' },
    [11683] = { 24, 'Peas' },
    [12310] = { 240, 'Haunch of Boar' },
    [13992] = { 660, 'Sandfish' },
    [14084] = { 168, 'Larvae' },
    [14085] = { 180, 'Deepling Filet' },
    [16103] = { 396, 'Mushroom Pie' },
    [17457] = { 120, 'Insectoid Eggs' },
    [17820] = { 180, 'Soft Cheese' },
    [17821] = { 144, 'Rat Cheese' },
    [21146] = { 300, 'Glooth Steak' },
    [22187] = { 300, 'Roasted Meat' },
    [22185] = { 96, 'Pickle Pear' },
    [24382] = { 240, 'Bug Meat' },
    [24383] = { 120, 'Cave Turnip' },
    [24948] = { 120, 'Bottle of Tibian Wine' },
    [25692] = { 180, 'Fresh Fruit' },
    [30198] = { 480, 'Meringue Cake' },
    [30202] = { 180, 'Winterberry Liquor' },
    [31560] = { 480, 'Goanna Meat' },
    [32069] = { 180, 'Candy Floss' },
    [37530] = { 120, 'Bottle of Champagne' },
    [37531] = { 60, 'Candy Floss' },
    [37532] = { 180, 'Ice Cream Cone' },
    [48116] = { 420, 'Gummy Rotworms' },
    [48251] = { 300, 'Wafer Paper Flower' },
    [48252] = { 540, 'Brigadeiro' },
    [48253] = { 540, 'Beijinho' },
    [48254] = { 780, 'Churro Heart' },
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

-- 0 means "none": SpellInfo has a real spell with id 0. Two spells can share
-- an id (Magic Patch "exura infir" and Mud Attack "exori infir tera" are both
-- 174, on the server too), so the healing one wins: rules only hold spells
-- from the lists below, never an attack
function HealData.spell(id)
    if not id or id == 0 then
        return nil
    end
    if spellCache[id] == nil then
        local found
        for _, spell in pairs(SpellInfo.Default) do
            if spell.id == id and (not found or Spells.getPrimaryGroup(spell) == HEALING_GROUP) then
                found = spell
            end
        end
        spellCache[id] = found or false
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

-- spells that only spend mana on the caster (utana vid, utevo lux, the
-- heals): what the bot casts to train magic level. Runes are left out:
-- they need a blank rune in the hand
function HealData.trainSpells(vocation)
    return vocationSpells(vocation, function(spell)
        return Spells.getPrimaryGroup(spell) ~= 1 and not spell.parameter and (spell.mana or 0) > 0
            and spell.type ~= 'Conjure' and not spell.words:find('^ad')
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
