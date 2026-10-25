-- Mythos: every vocation starts on its own hotkey set ("Sorcerer", "Druid",
-- "Paladin", "Knight", "Monk") with the action bar filled with that
-- vocation's main spells and runes, on F1 to F12. A set is only filled while
-- it is still the client's stock one: a bar the player has changed is never
-- touched. A set of the player's own (any other name, or one named after the
-- character) is never switched away from.
--
-- Each entry is { words } for a spell or { itemId, useType } for a rune.
-- Runes go on the attack target, Magic Wall with the crosshair. F11 holds
-- the haste: in the browser F11 is the page's full screen.

local RUNE_SUDDEN_DEATH = 3155
local RUNE_AVALANCHE = 3161
local RUNE_GREAT_FIREBALL = 3191
local RUNE_MAGIC_WALL = 3180
local RUNE_HOLY_MISSILE = 3182

VocationHotkeyTemplates = {
    Sorcerer = {
        { 'exura vita' },
        { 'utamo vita' },
        { 'exori vis' },
        { 'exori gran vis' },
        { 'exori max vis' },
        { 'exevo gran vis lux' },
        { 'exevo gran mas vis' },
        { 'exevo vis hur' },
        { RUNE_SUDDEN_DEATH, 'UseOnTarget' },
        { RUNE_GREAT_FIREBALL, 'UseOnTarget' },
        { 'utani gran hur' },
        { RUNE_MAGIC_WALL, 'SelectUseTarget' },
    },
    Druid = {
        { 'exura vita' },
        { 'utamo vita' },
        { 'exura gran mas res' },
        { 'exori frigo' },
        { 'exori gran frigo' },
        { 'exori max frigo' },
        { 'exevo gran mas frigo' },
        { 'exevo gran frigo hur' },
        { RUNE_AVALANCHE, 'UseOnTarget' },
        { RUNE_SUDDEN_DEATH, 'UseOnTarget' },
        { 'utani gran hur' },
        { RUNE_MAGIC_WALL, 'SelectUseTarget' },
    },
    Paladin = {
        { 'exura san' },
        { 'exura gran san' },
        { 'utito tempo san' },
        { 'exori san' },
        { 'exori con' },
        { 'exori gran con' },
        { 'exevo mas san' },
        { 'utura gran' },
        { RUNE_AVALANCHE, 'UseOnTarget' },
        { RUNE_HOLY_MISSILE, 'UseOnTarget' },
        { 'utani hur' },
        { RUNE_MAGIC_WALL, 'SelectUseTarget' },
    },
    Knight = {
        { 'exura ico' },
        { 'utura gran' },
        { 'utito tempo' },
        { 'utamo tempo' },
        { 'exori' },
        { 'exori gran' },
        { 'exori mas' },
        { 'exori min' },
        { 'exori ico' },
        { 'exori gran ico' },
        { 'utani hur' },
        { 'exeta res' },
    },
    Monk = {
        { 'exura gran tio' },
        { 'exura mas nia' },
        { 'utito virtu' },
        { 'utura tio' },
        { 'exori infir pug' },
        { 'exori pug' },
        { 'exori mas pug' },
        { 'exori gran mas pug' },
        { 'exori nia' },
        { 'exori mas nia' },
        { 'utani gran hur' },
        { 'exori gran nia' },
    },
}

-- translateVocation() (const.lua) gives the promoted server id
local SET_OF_VOCATION = {
    [5] = 'Sorcerer',
    [6] = 'Druid',
    [7] = 'Paladin',
    [8] = 'Knight',
    [9] = 'Monk',
}

--- Puts the character on its vocation's hotkey set, filled from the
--- template while still stock. Returns false while the vocation is unknown.
function useVocationHotkeySet()
    local localPlayer = g_game.getLocalPlayer()
    local setName = localPlayer and SET_OF_VOCATION[translateVocation(localPlayer:getVocation())]
    if not setName then
        return false
    end
    ApiJson.useVocationHotkeySet(setName, VocationHotkeyTemplates[setName], g_game.getCharacterName())
    return true
end
