-- Monster pages of the Mythos Wiki, the same as the website's (and laid out
-- like TibiaWiki's): the list comes from the server once per session and each
-- monster's page when it is opened, over extended opcode 134
-- (data-otservbr-global/scripts/website/monster_wiki.lua on the server).
-- A monster page has the id "m:<name>" and is built from blocks, like the
-- pages in pages.lua; this file adds the block types it needs.

local OPCODE = 134
local PAGE_SIZE = 40 -- creatures per page of the list

WikiMonsters = {}

local list -- { { name, boss, health, experience, class, stars, look, words, here, elements, loot, gold, hunts }, ... }
local lookIndex -- lower name -> look, built from the list when first needed
local rowIndex -- lower name -> row, built from the list when first needed
local classes -- { { class, count } } of the creatures of our world
local listAsked -- g_clock.millis() of the last request for the list
local pages = {} -- lower name -> server data
local asked = {} -- lower name -> g_clock.millis() of the last request for that page
local ASK_AGAIN = 2500 -- ms without an answer before asking again
-- the creature list's filters, kept while the window is open:
-- scope: 'here' (our world), 'boss' (bosses with a lever here) or 'all'
local filter = { text = '', loot = '', scope = 'here', class = '', weak = '', tp = false, sort = 'name', desc = false, page = 1 }
local lootIds, lootIdsText -- the item ids whose name has the loot filter's text

local ELEMENTS = {
    physical = { '#b8bec6', 'Físico' },
    earth = { '#6cd13a', 'Terra' },
    fire = { '#ff6a2a', 'Fogo' },
    death = { '#a45ad6', 'Morte' },
    energy = { '#b56bff', 'Energia' },
    holy = { '#ffd84a', 'Sagrado' },
    ice = { '#52dcff', 'Gelo' },
    lifedrain = { '#e0485a', 'Roubo de vida' },
    manadrain = { '#6b86ff', 'Roubo de mana' },
    drown = { '#3fa0c8', 'Afogamento' },
    agony = { '#c43b8f', 'Agonia' },
    healing = { '#7ee08a', 'Cura' },
    speed = { '#e6d28a', 'Velocidade' },
    other = { '#a39a8b', 'Outros' },
}
local ABILITY_ORDER = { 'physical', 'earth', 'fire', 'energy', 'ice', 'holy', 'death', 'lifedrain', 'manadrain', 'drown', 'agony', 'healing', 'speed', 'other' }
-- the element grid: the eight of the bestiary always, these two when not 100%
local GRID = { 'physical', 'earth', 'fire', 'death', 'energy', 'holy', 'ice', 'lifedrain', 'manadrain', 'drown' }
local GRID_OPTIONAL = { manadrain = true, drown = true }

local KINDS = {
    melee = 'Corpo a corpo', shot = 'Ataque à distância', ball = 'Bola', area = 'Área ao redor',
    wave = 'Onda', beam = 'Raio', touch = 'Golpe', field = 'Cria campos', paralyze = 'Paralisa',
    haste = 'Haste', heal = 'Se cura', invisible = 'Fica invisível', outfit = 'Muda a sua aparência',
    drunk = 'Deixa bêbado', strength = 'Reduz skills',
}
local CONDITIONS = {
    poison = { 'Envenenamento', 'envenena' }, burn = { 'Queimadura', 'queima' },
    electrify = { 'Eletrificação', 'eletrifica' }, bleed = { 'Sangramento', 'causa sangramento' },
    drown = { 'Afogamento', 'afoga' }, freeze = { 'Congelamento', 'congela' },
    dazzle = { 'Ofuscação', 'ofusca' }, curse = { 'Maldição', 'amaldiçoa' },
}
local IMMUNE = {
    paralyze = 'Paralisia', invisible = 'Invisibilidade (vê invisível)', outfit = 'Mudança de aparência',
    drunk = 'Embriaguez', bleed = 'Sangramento', fire = 'Queimadura', energy = 'Eletrificação',
    earth = 'Envenenamento', poison = 'Envenenamento', ice = 'Congelamento', holy = 'Ofuscação',
    death = 'Maldição', drown = 'Afogamento',
}
local DIFFICULTY = { [0] = 'Inofensivo', 'Trivial', 'Fácil', 'Médio', 'Difícil', 'Desafiador' }
local OCCURRENCE = { [0] = 'Comum', 'Incomum', 'Raro', 'Muito raro' }
-- loot by rarity, the wiki's bands (chance out of 100000)
local BANDS = {
    { 'Sempre', 100000 }, { 'Comum', 25000 }, { 'Incomum', 5000 },
    { 'Semi-raro', 1000 }, { 'Raro', 501 }, { 'Muito raro', 0 },
}

local GOOD, BAD, DIM, WARM = '#8fdc5e', '#ef7a62', '#9789b3', '#f3dcae'

local function T(text, ...)
    return WIKI_TEXT.T(text, ...)
end

local function L(text)
    return WIKI_TEXT.latin1(tostring(text or ''))
end

-- 12639 -> "12.639"
local function num(n)
    local digits = tostring(math.floor(math.abs(tonumber(n) or 0)))
    local out = digits:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return out
end

-- 2.5 / 0.41 -> "2,5" / "0,41"
local function decimal(n, places)
    local text = string.format('%.' .. places .. 'f', tonumber(n) or 0):gsub('0+$', ''):gsub('%.$', '')
    return (text:gsub('%.', ','))
end

local function titleCase(text)
    return (tostring(text):gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

local function lookOf(row)
    return { type = row[7] or 0, head = row[8] or 0, body = row[9] or 0, legs = row[10] or 0, feet = row[11] or 0, addons = row[12] or 0, typeEx = row[13] or 0 }
end

local function setLook(creatureWidget, itemWidget, look)
    if look and (look.typeEx or 0) > 0 then
        creatureWidget:setVisible(false)
        itemWidget:setVisible(true)
        itemWidget:setItemId(look.typeEx)
    elseif look and (look.type or 0) > 0 then
        itemWidget:setVisible(false)
        creatureWidget:setVisible(true)
        creatureWidget:setOutfit({ type = look.type, head = look.head or 0, body = look.body or 0, legs = look.legs or 0, feet = look.feet or 0, addons = look.addons or 0 })
        local creature = creatureWidget:getCreature()
        if creature then
            creature:setDirection(Directions.South)
        end
    else
        creatureWidget:setVisible(false)
        itemWidget:setVisible(false)
    end
end

local function request(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(OPCODE, data)
    end
end

local function askList()
    if not list and (not listAsked or g_clock.millis() - listAsked > ASK_AGAIN) then
        listAsked = g_clock.millis()
        request({ action = 'list' })
    end
end

-- the server drops a page asked too soon after another: ask once more if no
-- answer came, while the page is still the one on screen
local function askMonster(name)
    local key = name:lower()
    asked[key] = g_clock.millis()
    request({ action = 'monster', name = name })
    scheduleEvent(function()
        if pages[key] == nil and isOpen('m:' .. name) then
            asked[key] = g_clock.millis()
            request({ action = 'monster', name = name })
        end
    end, 800)
end

-- ---------------------------------------------------------------- list

local ELEMENT_ICON = '/game_cyclopedia/images/bestiary/icons/monster-icon-%s-resist'
-- the element filter of the list: "fraco a ..."
local WEAK = {
    { '', 'Qualquer fraqueza' }, { 'fire', 'Fraco a fogo' }, { 'ice', 'Fraco a gelo' }, { 'earth', 'Fraco a terra' },
    { 'energy', 'Fraco a energia' }, { 'holy', 'Fraco a sagrado' }, { 'death', 'Fraco a morte' }, { 'physical', 'Fraco a físico' },
}
-- the weaknesses shown in a row, in this order
local WEAK_ORDER = { 'physical', 'fire', 'ice', 'earth', 'energy', 'holy', 'death' }

-- column -> { value of a row, biggest first }
local SORTS = {
    name = { function(row) return row.words end, false },
    health = { function(row) return row.health end, true },
    experience = { function(row) return row.experience end, true },
    gold = { function(row) return row.gold end, true },
    chance = { function(row) return row.hit and row.hit.chance or 0 end, true },
}

local function chanceText(chance)
    local percent = (tonumber(chance) or 0) / 1000
    return (percent >= 1 and decimal(percent, 2) or decimal(percent, 3)) .. '%'
end

-- the loot item of a row whose name matched, with the best chance
local function lootHit(row)
    local best
    local loot = row.loot
    for i = 1, #loot - 2, 3 do
        local id = loot[i]
        if lootIds[id] and (not best or loot[i + 1] > best.chance) then
            best = { id = id, chance = loot[i + 1], max = loot[i + 2] }
        end
    end
    return best
end

local function matches()
    local text = WIKI_TEXT.plain(filter.text:trim())
    local lootText = WIKI_TEXT.plain(filter.loot:trim())
    local byLoot = #lootText >= 2 and WikiItems.ready()
    if byLoot and lootIdsText ~= lootText then
        lootIds, lootIdsText = WikiItems.idsMatching(lootText), lootText
    end
    local found = {}
    for _, row in ipairs(list or {}) do
        row.hit = nil
        local ok = text == '' or row.words:find(text, 1, true) ~= nil
        if ok and filter.scope == 'here' then
            ok = row.here
        elseif ok and filter.scope == 'boss' then
            ok = row.boss and row.here
        end
        if ok and filter.class ~= '' then
            ok = row.class == filter.class
        end
        if ok and filter.weak ~= '' then
            ok = (row.elements[filter.weak] or 100) > 100
        end
        if ok and filter.tp then
            ok = row.hunts > 0
        end
        if ok and byLoot then
            row.hit = lootHit(row)
            ok = row.hit ~= nil
        end
        if ok then
            table.insert(found, row)
        end
    end
    local key = (SORTS[filter.sort] or SORTS.name)[1]
    table.sort(found, function(a, b)
        local va, vb = key(a), key(b)
        if va ~= vb then
            if filter.desc then
                return va > vb
            end
            return va < vb
        end
        return a.words < b.words
    end)
    return found, byLoot
end

local function setSort(sort)
    if filter.sort == sort then
        filter.desc = not filter.desc
    else
        filter.sort = sort
        filter.desc = SORTS[sort][2]
    end
    filter.page = 1
end

-- the weaknesses of a row as bestiary icons, the biggest first
local function fillWeak(box, row)
    box:destroyChildren()
    local weak = {}
    for _, key in ipairs(WEAK_ORDER) do
        local taken = row.elements[key]
        if taken and taken > 100 then
            table.insert(weak, { key = key, taken = taken })
        end
    end
    table.sort(weak, function(a, b) return a.taken > b.taken end)
    local tips = {}
    for i, entry in ipairs(weak) do
        if i <= 3 then
            local icon = g_ui.createWidget('WikiWeakIcon', box)
            icon:setImageSource(string.format(ELEMENT_ICON, entry.key))
        end
        table.insert(tips, T('%s %d%%', L(ELEMENTS[entry.key][2]), entry.taken))
    end
    if #weak > 0 then
        box:setTooltip(T('Fraco a: %s', table.concat(tips, ', ')))
    else
        box:setTooltip(T('Sem fraqueza a elemento'))
    end
end

local function fillList(box)
    box.rows:destroyChildren()
    for _, tab in ipairs({ box.scope.here, box.scope.boss, box.scope.all }) do
        tab:setChecked(tab.scope == filter.scope)
    end
    box.scope.tp:setChecked(filter.tp)
    for _, cell in ipairs(box.head:getChildren()) do
        if cell.sort then
            local active = cell.sort == filter.sort
            cell:setText(cell.label .. (active and (filter.desc and ' v' or ' ^') or ''))
            cell:setColor(active and '#f3dcae' or '#b4afc3')
        end
    end
    box.head.chance:setVisible(WIKI_TEXT.plain(filter.loot:trim()):len() >= 2)
    if not list then
        box.tools.count:setText(T('Carregando...'))
        box.pager:setVisible(false)
        return
    end
    local found, byLoot = matches()
    local pages = math.max(1, math.ceil(#found / PAGE_SIZE))
    filter.page = math.max(1, math.min(filter.page, pages))
    local first = (filter.page - 1) * PAGE_SIZE + 1
    for i = first, math.min(#found, first + PAGE_SIZE - 1) do
        local row = found[i]
        local line = g_ui.createWidget(i % 2 == 0 and 'WikiCreatureRowEven' or 'WikiCreatureRow', box.rows)
        setLook(line.creature, line.item, row.look)
        line.name:setText(row.name)
        if row.boss then
            line.name:setColor('#ff9a1f')
        end
        if row.hit then
            local itemName = WikiItems.nameOf(row.hit.id) or T('Item')
            local count = row.hit.max > 1 and (row.hit.max .. 'x ') or ''
            line.info:setText(T('%s%s  %s', count, itemName, chanceText(row.hit.chance)))
            line.info:setColor(WARM)
            line.lootItem:setItemId(row.hit.id)
            line.lootItem:setVisible(true)
        else
            local info
            if not row.here then
                info = row.boss and T('Boss, fora do nosso mundo') or T('Fora do nosso mundo')
            elseif row.boss then
                info = T('Boss com alavanca')
            else
                info = row.class ~= '' and T('%s, %s', row.class, L(DIFFICULTY[row.stars] or '')) or ''
            end
            line.info:setText(info)
        end
        line.hp:setText(num(row.health))
        line.xp:setText(num(row.experience))
        if row.gold > 0 then
            line.gold:setText(num(row.gold))
        else
            line.gold:setText('-')
            line.gold:setColor(DIM)
        end
        if row.here then
            fillWeak(line.weak, row)
        end
        if row.hunts > 0 then
            line.tp:setVisible(true)
            line.tp:setTooltip(row.hunts == 1 and T('O Hunts TP leva até a hunt dele') or T('O Hunts TP leva até %d hunts dele', row.hunts))
        end
        line.onClick = function() show('m:' .. row.name) end
    end
    local count = #found == 1 and T('1 criatura') or T('%s criaturas', num(#found))
    box.tools.count:setText(count)
    box.pager:setVisible(pages > 1)
    box.pager.label:setText(T('Página %d de %d', filter.page, pages))
    box.pager.prev:setEnabled(filter.page > 1)
    box.pager.next:setEnabled(filter.page < pages)
    local note
    if #found == 0 then
        note = byLoot and T('Nenhuma criatura dropa um item com esse nome.') or T('Nenhuma criatura com esses filtros.')
    elseif WIKI_TEXT.plain(filter.loot:trim()):len() >= 2 and not byLoot then
        note = T('Carregando os itens...')
    end
    box.note:setText(note or '')
    box.note:setVisible(note ~= nil)
end

local function onList(monsters)
    list = {}
    local classCount = {}
    for _, row in ipairs(monsters or {}) do
        if type(row) == 'table' and type(row[1]) == 'string' then
            local name = L(row[1])
            local entry = {
                name = name, boss = row[2] == 1, health = tonumber(row[3]) or 0, experience = tonumber(row[4]) or 0,
                class = L(row[5] or ''), stars = tonumber(row[6]) or 0, look = lookOf(row),
                words = WIKI_TEXT.plain(name),
                here = row[14] == 1, elements = {}, loot = type(row[16]) == 'table' and row[16] or {},
                gold = tonumber(row[17]) or 0, hunts = tonumber(row[18]) or 0,
            }
            if type(row[15]) == 'string' then
                for key, value in row[15]:gmatch('(%a+):(%d+)') do
                    entry.elements[key] = tonumber(value)
                end
            end
            if entry.here and entry.class ~= '' then
                classCount[entry.class] = (classCount[entry.class] or 0) + 1
            end
            table.insert(list, entry)
        end
    end
    table.sort(list, function(a, b) return a.words < b.words end)
    classes = {}
    for class, count in pairs(classCount) do
        table.insert(classes, { class, count })
    end
    table.sort(classes, function(a, b) return a[1] < b[1] end)
    lookIndex, rowIndex = nil, nil
    refresh('monsters')
    searchAgain()
    -- the monsters that drop an item get their look
    refreshCurrent('i:')
    -- a monster page shows its gold per kill
    refreshCurrent('m:')
end

-- the look of a monster of the list, by name (nil until the list comes)
function WikiMonsters.lookOf(name)
    askList()
    if not list then
        return nil
    end
    if not lookIndex then
        lookIndex = {}
        for _, row in ipairs(list) do
            lookIndex[row.name:lower()] = row.look
        end
    end
    return lookIndex[tostring(name):lower()]
end

-- the creature list with only the creatures that drop the item, the best
-- chance first (the "compare" button of an item page)
function WikiMonsters.showDroppers(itemName)
    filter.text, filter.loot = '', tostring(itemName or '')
    filter.scope, filter.class, filter.weak, filter.tp = 'here', '', '', false
    filter.sort, filter.desc, filter.page = 'chance', true, 1
    show('monsters')
end

-- the list's row of a monster, by name (nil until the list comes)
function WikiMonsters.rowOf(name)
    if not list then
        return nil
    end
    if not rowIndex then
        rowIndex = {}
        for _, row in ipairs(list) do
            rowIndex[row.name:lower()] = row
        end
    end
    return rowIndex[tostring(name):lower()]
end

-- ---------------------------------------------------------------- one monster

local function abilityText(ability)
    local kind = ability.kind or ''
    local name
    if kind == 'spell' then
        name = titleCase(ability.name or '')
    elseif kind == 'condition' then
        name = (CONDITIONS[ability.condition or ''] or { 'Condição' })[1]
    else
        name = KINDS[kind] or titleCase(kind)
    end
    local text = name
    local min, max = tonumber(ability.min) or 0, tonumber(ability.max) or 0
    if kind == 'paralyze' or kind == 'haste' then
        if max > 0 then
            text = text .. string.format(' (%s%s de velocidade)', kind == 'paralyze' and '-' or '+', num(max))
        end
    elseif max > 0 then
        text = text .. string.format(' (%s-%s)', num(min), num(max))
    end
    local extra = ability.extra
    if type(extra) == 'table' and extra.condition then
        local verb = (CONDITIONS[extra.condition] or { '', '' })[2]
        text = text .. ' + ' .. verb .. ((tonumber(extra.damage) or 0) > 0 and string.format(' (%s)', num(extra.damage)) or '')
    end
    return text
end

local function abilityGroup(ability)
    local kind = ability.kind or ''
    local spell = kind == 'spell' and not ability.element and (ability.name or ''):lower() or ''
    if kind == 'heal' or spell:find('heal', 1, true) then
        return 'healing'
    elseif kind == 'paralyze' or kind == 'haste' or spell:find('paralyze', 1, true) or spell:find('haste', 1, true) then
        return 'speed'
    elseif ability.element and ELEMENTS[ability.element] then
        return ability.element
    end
    return 'other'
end

local function behaviour(d, flags, ranged)
    local parts = {}
    if not flags.hostile then
        table.insert(parts, 'Pacífico: não ataca ninguém.')
    elseif (tonumber(flags.distance) or 1) > 1 then
        table.insert(parts, string.format('Combate à distância, mantendo %d sqm do alvo.', flags.distance))
    else
        table.insert(parts, ranged and 'Combate corpo a corpo e à distância.' or 'Combate corpo a corpo.')
    end
    if (tonumber(flags.runHealth) or 0) > 0 then
        table.insert(parts, string.format('Foge quando a vida cai para %s.', num(flags.runHealth)))
    end
    if flags.blockable then
        table.insert(parts, 'É possível bloquear o respawn.')
    end
    if flags.summonable then
        table.insert(parts, string.format('Pode ser sumonado (%s de mana).', num(flags.mana)))
    end
    if flags.convinceable then
        table.insert(parts, string.format('Pode ser convencido (%s de mana).', num(flags.mana)))
    end
    if flags.illusionable then
        table.insert(parts, 'Dá para virar ele com Creature Illusion.')
    end
    if d.bestiary and not d.bestiary.hidden and not flags.preyable then
        table.insert(parts, 'Não aparece no Prey.')
    end
    return table.concat(parts, ' ')
end

local function yesNo(value)
    return value and { T('Sim'), GOOD } or { T('Não'), BAD }
end

-- the page of a monster whose data came from the server
local function monsterBlocks(d)
    local flags = d.flags or {}
    local blocks = { { 'monsterhead', d } }

    local grid = {}
    for _, key in ipairs(GRID) do
        local value = tonumber((d.taken or {})[key]) or 100
        if not (GRID_OPTIONAL[key] and value == 100) then
            table.insert(grid, { key = key, value = value })
        end
    end
    table.insert(blocks, { 'h', T('Dano que ele recebe') })
    table.insert(blocks, { 'elements', grid })

    local immune = {}
    for _, cell in ipairs(grid) do
        if cell.value == 0 then
            table.insert(immune, ELEMENTS[cell.key][2])
        end
    end
    for _, condition in ipairs(d.immune or {}) do
        table.insert(immune, IMMUNE[condition] or titleCase(condition))
    end
    local passes = {}
    if flags.walkFire then table.insert(passes, 'fogo') end
    if flags.walkEnergy then table.insert(passes, 'energia') end
    if flags.walkPoison then table.insert(passes, 'veneno') end
    table.insert(blocks, { 'table', widths = { 150, 396 }, rows = {
        { T('Imunidades'), #immune > 0 and T(table.concat(immune, ', ')) or { T('Nenhuma'), DIM } },
        { T('Pode ser puxado'), yesNo(flags.pushable) },
        { T('Passa por'), #passes > 0 and T(titleCase(table.concat(passes, ', '))) or { T('Nada'), DIM } },
        { T('Empurra objetos'), yesNo(flags.pushItems) },
        { T('Empurra criaturas'), yesNo(flags.pushCreatures) },
    } })

    -- abilities by element, like the wiki: "Fogo: Bola (100-220), Onda (150-270)"
    local groups, ranged = {}, false
    for _, ability in ipairs(d.abilities or {}) do
        local group = abilityGroup(ability)
        groups[group] = groups[group] or {}
        table.insert(groups[group], abilityText(ability))
        local kind = ability.kind
        if kind == 'shot' or kind == 'ball' or kind == 'beam' or kind == 'wave' or (kind == 'spell' and ability.element) then
            ranged = true
        end
    end
    local rows = {}
    for _, key in ipairs(ABILITY_ORDER) do
        if groups[key] then
            table.insert(rows, { { T(ELEMENTS[key][2]), ELEMENTS[key][1] }, L(table.concat(groups[key], ', ')) })
        end
    end
    table.insert(blocks, { 'h', T('Habilidades') })
    if #rows > 0 then
        table.insert(blocks, { 'table', widths = { 120, 426 }, rows = rows })
    else
        table.insert(blocks, { 'p', T('Nenhuma.') })
    end

    table.insert(blocks, { 'h', T('Comportamento') })
    table.insert(blocks, { 'p', T(behaviour(d, flags, ranged)) })

    if d.summons and #d.summons > 0 then
        local names = {}
        for _, summon in ipairs(d.summons) do
            table.insert(names, L(titleCase(summon.name)))
        end
        table.insert(blocks, { 'h', (tonumber(d.maxSummons) or 0) > 0 and T('Sumona (até %d ao mesmo tempo)', d.maxSummons) or T('Sumona') })
        table.insert(blocks, { 'monsterlinks', names })
    end

    if d.voices and #d.voices > 0 then
        local voices = {}
        for _, voice in ipairs(d.voices) do
            table.insert(voices, '"' .. L(voice) .. '"')
        end
        table.insert(blocks, { 'h', T('Falas') })
        table.insert(blocks, { 'voices', table.concat(voices, '   ') })
    end

    -- where to hunt it on our map (the bestiary's "locations" are Tibia's)
    table.insert(blocks, { 'h', T('Onde caçar') })
    if type(d.hunts) == 'table' and #d.hunts > 0 then
        -- one line per town: "perto de Ventera: 3 hunts, com 82, 179 e 340 spawns"
        local towns, order = {}, {}
        for _, hunt in ipairs(d.hunts) do
            local town = L(hunt[1])
            if not towns[town] then
                towns[town] = {}
                table.insert(order, town)
            end
            if (tonumber(hunt[2]) or 0) > 0 then
                table.insert(towns[town], num(hunt[2]))
            end
        end
        local places = {}
        for _, town in ipairs(order) do
            local counts = towns[town]
            local spawns = #counts > 1 and (table.concat(counts, ', ', 1, #counts - 1) .. T(' e ') .. counts[#counts]) or counts[1]
            local hunts = 0
            for _, hunt in ipairs(d.hunts) do
                if L(hunt[1]) == town then
                    hunts = hunts + 1
                end
            end
            local text = hunts > 1 and T('perto de %s: %d hunts', town, hunts) or T('perto de %s', town)
            if spawns then
                text = text .. (hunts > 1 and T(', com %s spawns', spawns) or T(' (%s spawns)', spawns))
            end
            table.insert(places, text)
        end
        table.insert(blocks, { 'p', T('O Hunts TP do Hunt Board leva direto até %s %s.', #d.hunts == 1 and T('a hunt') or T('as hunts'), table.concat(places, '; ')) })
        table.insert(blocks, { 'links', { 'hunts', 'travel' } })
    else
        table.insert(blocks, { 'p', T('Nenhum teleport de hunt leva até este monstro.') })
    end

    if d.xpRate then
        table.insert(blocks, { 'h', T('Hunt Board agora') })
        table.insert(blocks, { 'p', T('XP x%s e loot x%s. A taxa muda a cada sorteio do Hunt Board; quanto maior a de XP, mais vida e dano ele tem enquanto ela durar. A vida e o dano desta página são os de base.', decimal(d.xpRate / 10, 1), decimal((d.lootRate or 10) / 10, 1)) })
    end

    table.insert(blocks, { 'h', T('Loot') })
    local bands = {}
    local items = {}
    for _, item in ipairs(d.loot or {}) do
        table.insert(items, item)
    end
    table.sort(items, function(a, b) return (a.chance or 0) > (b.chance or 0) end)
    for _, item in ipairs(items) do
        local chance = tonumber(item.chance) or 0
        for i, band in ipairs(BANDS) do
            if chance >= band[2] then
                bands[i] = bands[i] or {}
                table.insert(bands[i], item)
                break
            end
        end
    end
    local any = false
    for i, band in ipairs(BANDS) do
        if bands[i] then
            any = true
            table.insert(blocks, { 'loot', T(band[1]), bands[i] })
        end
    end
    if any then
        table.insert(blocks, { 'p', T('Chance de cada item por kill, antes da taxa de loot do Hunt Board. Qualquer item de equipamento ainda pode cair raro (Communis a Mythicus).') })
    else
        table.insert(blocks, { 'p', T('Não dropa nada.') })
    end
    return blocks
end

-- WIKI page for "m:<name>": loading, missing or the monster
function WikiMonsters.page(id)
    local name = id:sub(3)
    local key = name:lower()
    -- the loot's prices and the gold per kill come with the two lists
    askList()
    WikiItems.ready()
    local data = pages[key]
    if data == nil and (not asked[key] or g_clock.millis() - asked[key] > ASK_AGAIN) then
        askMonster(name)
    end
    if not data then
        return { menu = name, title = name, blocks = { { 'p', T('Carregando...') } } }
    end
    if data.missing then
        return { menu = name, title = name, blocks = { { 'p', T('Nenhum monstro com esse nome.') } } }
    end
    if not data.blocks then
        data.blocks = monsterBlocks(data)
    end
    return { menu = data.name, title = data.name, blocks = data.blocks }
end

-- ---------------------------------------------------------------- blocks

function WIKI_BUILDERS.monsterlist(parent)
    askList()
    WikiItems.ready()
    local box = g_ui.createWidget('WikiCreatureTable', parent)
    local tools = box.tools
    tools.search:setText(filter.text)
    tools.search.onTextChange = function(_, text)
        filter.text = text
        filter.page = 1
        fillList(box)
    end
    tools.loot:setText(filter.loot)
    tools.loot.onTextChange = function(_, text)
        local was = WIKI_TEXT.plain(filter.loot:trim()):len() >= 2
        filter.loot = text
        local now = WIKI_TEXT.plain(text:trim()):len() >= 2
        -- by the item's chance while a loot filter is on
        if now and not was and filter.sort == 'name' then
            filter.sort, filter.desc = 'chance', true
        elseif was and not now and filter.sort == 'chance' then
            filter.sort, filter.desc = 'name', false
        end
        filter.page = 1
        fillList(box)
    end

    local scope = box.scope
    for _, entry in ipairs({ { scope.here, 'here', 'Nosso mundo', 'As criaturas que vivem no nosso mapa e os bosses com alavanca' },
        { scope.boss, 'boss', 'Bosses', 'Os bosses que têm alavanca no nosso mapa' },
        { scope.all, 'all', 'Todas', 'Todas as criaturas do jogo, até as que não existem no nosso mapa' } }) do
        entry[1].scope = entry[2]
        entry[1]:setText(T(entry[3]))
        entry[1]:setTooltip(T(entry[4]))
        entry[1].onClick = function()
            filter.scope = entry[2]
            filter.page = 1
            fillList(box)
        end
    end
    scope.tp:setText(T('Com TP'))
    scope.tp:setTooltip(T('Só as que o Hunts TP do Hunt Board leva até a hunt'))
    scope.tp.onClick = function()
        filter.tp = not filter.tp
        filter.page = 1
        fillList(box)
    end

    local classBox = scope.class
    classBox:addOption(T('Todas as classes'), '')
    for _, entry in ipairs(classes or {}) do
        classBox:addOption(T('%s (%d)', entry[1], entry[2]), entry[1])
    end
    classBox:setCurrentOptionByData(filter.class, true)
    classBox.onOptionChange = function(_, _, data)
        filter.class = data or ''
        filter.page = 1
        fillList(box)
    end
    local weakBox = scope.weak
    for _, entry in ipairs(WEAK) do
        weakBox:addOption(T(entry[2]), entry[1])
    end
    weakBox:setCurrentOptionByData(filter.weak, true)
    weakBox.onOptionChange = function(_, _, data)
        filter.weak = data or ''
        filter.page = 1
        fillList(box)
    end

    for _, entry in ipairs({ { box.head.name, 'name', 'Criatura' }, { box.head.hp, 'health', 'Vida' }, { box.head.xp, 'experience', 'XP' },
        { box.head.gold, 'gold', 'Gold/kill' }, { box.head.chance, 'chance', 'Chance' } }) do
        entry[1].sort = entry[2]
        entry[1].label = T(entry[3])
        entry[1].onClick = function()
            setSort(entry[2])
            fillList(box)
        end
    end
    box.head.gold:setTooltip(T('O que uma kill rende em média vendendo o loot ao Gersao, na taxa de loot do servidor (sem o bônus do Hunt Board)'))
    box.head.weak:setText(T('Fraco a'))

    box.pager.prev.onClick = function()
        filter.page = filter.page - 1
        fillList(box)
        scrollTop()
    end
    box.pager.next.onClick = function()
        filter.page = filter.page + 1
        fillList(box)
        scrollTop()
    end
    fillList(box)
end

function WIKI_BUILDERS.monsterhead(parent, block)
    local d = block[2]
    local head = g_ui.createWidget('WikiMonsterHead', parent)
    setLook(head.frame.creature, head.frame.item, d.look)

    local tags = {}
    if d.boss then
        table.insert(tags, '{BOSS, #ff9a1f}')
    end
    if d.bossClass then
        table.insert(tags, L('Bosstiário: ' .. d.bossClass))
    end
    if d.bestiary then
        table.insert(tags, L(d.bestiary.class))
    end
    table.insert(tags, L(titleCase(d.race or '')))
    head.tags:setColoredText(table.concat(tags, '   '))

    local function line(key, value, note)
        return string.format('%s {%s, #f3f0fa}%s', T(key), value, note and ('  ' .. note) or '')
    end
    local left = {
        line('Vida:', num(d.health)),
        line('Experiência:', num(d.experience)),
    }
    if d.xpRate and d.xpRate ~= 10 and (d.experience or 0) > 0 then
        table.insert(left, T('{%s com o bônus de agora (x%s), #8fdc5e}', num(math.floor(d.experience * d.xpRate / 10)), decimal(d.xpRate / 10, 1)))
    end
    table.insert(left, line('Velocidade:', num(d.speed)))
    table.insert(left, line('Armadura:', num(d.armor)))
    if (tonumber(d.mitigation) or 0) > 0 then
        table.insert(left, line('Mitigação:', decimal(d.mitigation, 2) .. '%'))
    end
    head.left:setColoredText(table.concat(left, '\n'))

    local right = {}
    if d.bestiary then
        local stars = math.max(0, math.min(5, tonumber(d.bestiary.stars) or 0))
        table.insert(right, line('Dificuldade:', T(DIFFICULTY[stars]), string.format('(%d/5)', stars)))
        table.insert(right, line('Ocorrência:', T(OCCURRENCE[math.max(0, math.min(3, tonumber(d.bestiary.occurrence) or 0))])))
        if d.bestiary.hidden then
            -- a creature of Tibia that lives nowhere on our map
            table.insert(right, T('{Fora do bestiário, #ef7a62}'))
            table.insert(right, T('{(não vive no nosso mundo), #9789b3}'))
        else
            table.insert(right, line('Charms:', num(d.bestiary.charms), T('(%s kills)', num(d.bestiary.kills))))
        end
    else
        table.insert(right, T('{Sem bestiário, #9789b3}'))
    end
    -- what a kill is worth (the list's number, the Hunt Board's)
    local row = WikiMonsters.rowOf(d.name)
    if row and row.gold > 0 then
        table.insert(right, string.format('%s {%s gold, #e2c35a}', T('Loot médio:'), num(row.gold)))
        if d.lootRate and d.lootRate ~= 10 then
            table.insert(right, T('{%s gold com o loot de agora (x%s), #8fdc5e}', num(math.floor(row.gold * d.lootRate / 10)), decimal(d.lootRate / 10, 1)))
        end
    end
    head.right:setColoredText(table.concat(right, '\n'))
    local height = math.max(head.left:getHeight(), head.right:getHeight()) + 24
    head:setHeight(math.max(100, height))
end

function WIKI_BUILDERS.elements(parent, block)
    local grid = g_ui.createWidget('WikiElements', parent)
    for _, cell in ipairs(block[2]) do
        local widget = g_ui.createWidget('WikiElementCell', grid)
        widget.gem:setBackgroundColor(ELEMENTS[cell.key][1])
        widget.name:setText(T(ELEMENTS[cell.key][2]))
        widget.value:setText(cell.value .. '%')
        if cell.value == 0 then
            widget.value:setColor('#9aa3ad')
            widget:setBorderColor('#5a5a5a')
            widget:setTooltip(T('Imune'))
        elseif cell.value < 100 then
            widget.value:setColor('#f1c84b')
            widget:setBackgroundColor('#2c261080')
            widget:setBorderColor('#5b4d17')
            widget:setTooltip(T('Resiste: toma %d%% do dano', cell.value))
        elseif cell.value > 100 then
            widget.value:setColor(GOOD)
            widget:setBackgroundColor('#1b2b1580')
            widget:setBorderColor('#3a5a2a')
            widget:setTooltip(T('Fraco: toma %d%% do dano', cell.value))
        end
    end
end

function WIKI_BUILDERS.loot(parent, block)
    g_ui.createWidget('WikiLootBand', parent):setText(block[2])
    local grid = g_ui.createWidget('WikiLootGrid', parent)
    for _, item in ipairs(block[3]) do
        local cell = g_ui.createWidget('WikiLootCell', grid)
        cell.item:setItemId(item.id)
        local max, min = tonumber(item.max) or 1, math.max(1, tonumber(item.min) or 1)
        if max > 1 then
            -- a pile of coins looks like one
            cell.item:setItemCount(max)
        end
        local count = max > 1 and ((min < max and (min .. '-' .. max) or tostring(max)) .. ' ') or ''
        local name = count .. L(titleCase(item.name or ''))
        cell.name:setText(name)
        local percent = (tonumber(item.chance) or 0) / 1000
        local chance = (percent >= 1 and decimal(percent, 2) or decimal(percent, 3)) .. '%'
        local value = WikiItems.valueOf(tonumber(item.id) or 0)
        if value > 0 then
            cell.chance:setText(T('%s   NPC: %s', chance, num(value)))
            cell:setTooltip(T('%s - %s. Um NPC paga %s gold. Clique para abrir o item.', name, chance, num(value)))
        else
            cell.chance:setText(chance)
            cell:setTooltip(T('%s - %s. Clique para abrir o item.', name, chance))
        end
        cell.onClick = function() show('i:' .. item.id) end
    end
end

function WIKI_BUILDERS.voices(parent, block)
    g_ui.createWidget('WikiVoices', parent):setText(block[2])
end

function WIKI_BUILDERS.monsterlinks(parent, block)
    local links = g_ui.createWidget('WikiMonsterLinks', parent)
    for _, name in ipairs(block[2]) do
        local button = g_ui.createWidget('WikiLinkButton', links)
        button:setText(name)
        button.onClick = function() show('m:' .. name) end
    end
end

-- ---------------------------------------------------------------- hunts by level

local hunts -- { { name, level, experience, towns, count, look }, ... }
local huntsAsked
local huntFilter = { text = '', near = false }
-- the daily task's window: hunts from 55% to 110% of the player's level
local NEAR = { 0.55, 1.1 }

local function askHunts()
    if not hunts and (not huntsAsked or g_clock.millis() - huntsAsked > ASK_AGAIN) then
        huntsAsked = g_clock.millis()
        request({ action = 'hunts' })
    end
end

local function fillHunts(box)
    box.table:destroyChildren()
    box.tools.near:setChecked(huntFilter.near)
    if not hunts then
        box.tools.count:setText(T('Carregando...'))
        return
    end
    local head = g_ui.createWidget('WikiHuntHead', box.table)
    head.c1:setText(T('Monstro'))
    head.c2:setText(T('Nível'))
    head.c3:setText(T('Perto de'))
    local player = g_game.getLocalPlayer()
    local level = player and player:getLevel() or 0
    local text = WIKI_TEXT.plain(huntFilter.text:trim())
    local count = 0
    for _, hunt in ipairs(hunts) do
        local near = level > 0 and hunt.level >= level * NEAR[1] and hunt.level <= level * NEAR[2]
        if (text == '' or hunt.words:find(text, 1, true)) and (not huntFilter.near or near) then
            count = count + 1
            local row = g_ui.createWidget(count % 2 == 0 and 'WikiHuntRowEven' or 'WikiHuntRow', box.table)
            if hunt.look.type > 0 then
                row.creature:setOutfit(hunt.look)
            end
            row.name:setText(hunt.name)
            if hunt.count > 1 then
                row.count:setText(T('%d hunts', hunt.count))
            else
                row.name:setMarginTop(12)
            end
            row.level:setText(tostring(hunt.level))
            row.also:setText(hunt.towns ~= '' and hunt.towns or '-')
            row:setTooltip(T('%s XP. Clique para abrir o monstro.', num(hunt.experience)))
            row.onClick = function() show('m:' .. hunt.name) end
        end
    end
    box.tools.count:setText(count == 1 and T('1 hunt') or T('%d hunts', count))
end

function WIKI_BUILDERS.huntlist(parent)
    askHunts()
    local box = g_ui.createWidget('WikiHuntList', parent)
    box.tools.search:setText(huntFilter.text)
    box.tools.search.onTextChange = function(_, text)
        huntFilter.text = text
        fillHunts(box)
    end
    box.tools.near:setText(T('Perto do meu level'))
    box.tools.near:setTooltip(T('Só as hunts de 55%% a 110%% do seu level, a mesma faixa da tarefa diária.'))
    box.tools.near.onClick = function()
        huntFilter.near = not huntFilter.near
        fillHunts(box)
    end
    fillHunts(box)
end

-- ---------------------------------------------------------------- search box

-- monsters whose name has the text, for the wiki's own search box
function WikiMonsters.search(text, limit)
    askList()
    local found = {}
    if not list or #text < 2 then
        return found
    end
    for _, row in ipairs(list) do
        if row.words:find(text, 1, true) then
            table.insert(found, row.name)
            if #found >= limit then
                break
            end
        end
    end
    return found
end

-- ---------------------------------------------------------------- module

local function onHunts(data)
    hunts = {}
    for _, row in ipairs(data.hunts or {}) do
        if type(row) == 'table' and type(row[1]) == 'string' then
            local towns = {}
            for _, town in ipairs(type(row[4]) == 'table' and row[4] or {}) do
                table.insert(towns, L(town))
            end
            local name = L(row[1])
            table.insert(hunts, {
                name = name, level = tonumber(row[2]) or 0, experience = tonumber(row[3]) or 0,
                towns = table.concat(towns, ', '), count = tonumber(row[5]) or 1,
                look = { type = row[6] or 0, head = row[7] or 0, body = row[8] or 0, legs = row[9] or 0, feet = row[10] or 0, addons = row[11] or 0 },
                words = WIKI_TEXT.plain(name .. ' ' .. table.concat(towns, ' ')),
            })
        end
    end
    refresh('hunts')
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    if data.action == 'hunts' then
        onHunts(data)
        return
    end
    -- the items, NPCs and spells of the wiki (items.lua, npcs.lua, spells.lua)
    local handler = type(data.action) == 'string' and WIKI_HANDLERS[data.action]
    if handler then
        handler(data)
        return
    end
    if data.action == 'list' then
        onList(data.monsters)
    elseif data.action == 'monster' and type(data.name) == 'string' then
        local key = L(data.name):lower()
        if data.missing then
            pages[key] = { missing = true }
        elseif type(data.data) == 'table' then
            local d = data.data
            d.name = L(d.name or data.name)
            pages[key] = d
        end
        refresh('m:' .. L(data.name))
    end
end

function WikiMonsters.reset()
    list, listAsked, pages, asked, lookIndex = nil, nil, {}, {}, nil
    hunts, huntsAsked = nil, nil
    huntFilter = { text = '', near = false }
end

function WikiMonsters.init()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
end

function WikiMonsters.terminate()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    WikiMonsters.reset()
end
