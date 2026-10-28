-- Monster pages of the Mythos Wiki, the same as the website's (and laid out
-- like TibiaWiki's): the list comes from the server once per session and each
-- monster's page when it is opened, over extended opcode 134
-- (data-otservbr-global/scripts/website/monster_wiki.lua on the server).
-- A monster page has the id "m:<name>" and is built from blocks, like the
-- pages in pages.lua; this file adds the block types it needs.

local OPCODE = 134
local LIST_LIMIT = 60

WikiMonsters = {}

local list -- { { name, boss, health, experience, class, stars, look, words }, ... }
local listAsked -- g_clock.millis() of the last request for the list
local pages = {} -- lower name -> server data
local asked = {} -- lower name -> g_clock.millis() of the last request for that page
local ASK_AGAIN = 2500 -- ms without an answer before asking again
local filter = { text = '', view = 'all' }

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

local function matches()
    local text = WIKI_TEXT.plain(filter.text:trim())
    local found = {}
    for _, row in ipairs(list or {}) do
        if (text == '' or row.words:find(text, 1, true))
            and (filter.view ~= 'boss' or row.boss)
            and (filter.view ~= 'bestiary' or row.class ~= '') then
            table.insert(found, row)
        end
    end
    return found
end

local function fillList(box)
    box.rows:destroyChildren()
    for _, tab in ipairs({ box.tools.tabAll, box.tools.tabBestiary, box.tools.tabBoss }) do
        tab:setChecked(tab.view == filter.view)
    end
    if not list then
        box.tools.count:setText(T('Carregando...'))
        return
    end
    local found = matches()
    for i = 1, math.min(#found, LIST_LIMIT) do
        local row = found[i]
        local line = g_ui.createWidget(i % 2 == 0 and 'WikiMonsterRowEven' or 'WikiMonsterRow', box.rows)
        setLook(line.creature, line.item, row.look)
        line.name:setText(row.name .. (row.boss and '  BOSS' or ''))
        local info = row.class ~= '' and T('%s, %s', row.class, DIFFICULTY[row.stars] or '') or (row.boss and T('Boss') or T('Sem bestiário'))
        line.info:setText(L(info))
        line.xp:setText(T('%s XP', num(row.experience)))
        line.hp:setText(T('%s de vida', num(row.health)))
        line.onClick = function() show('m:' .. row.name) end
    end
    box.tools.count:setText(#found == 1 and T('1 monstro') or T('%s monstros', num(#found)))
    if #found == 0 then
        box.note:setText(T('Nenhum monstro com esse filtro.'))
    elseif #found > LIST_LIMIT then
        box.note:setText(T('Mostrando %d de %s. Busque pelo nome para achar os outros.', LIST_LIMIT, num(#found)))
    end
    box.note:setVisible(#found == 0 or #found > LIST_LIMIT)
end

local function onList(monsters)
    list = {}
    for _, row in ipairs(monsters or {}) do
        if type(row) == 'table' and type(row[1]) == 'string' then
            local name = L(row[1])
            table.insert(list, {
                name = name, boss = row[2] == 1, health = row[3] or 0, experience = row[4] or 0,
                class = L(row[5] or ''), stars = row[6] or 0, look = lookOf(row),
                words = WIKI_TEXT.plain(name),
            })
        end
    end
    table.sort(list, function(a, b) return a.words < b.words end)
    refresh('monsters')
    searchAgain()
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

    if d.bestiary and (d.bestiary.locations or '') ~= '' then
        table.insert(blocks, { 'h', T('Locais') })
        table.insert(blocks, { 'p', L(d.bestiary.locations) })
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
    local box = g_ui.createWidget('WikiMonsterList', parent)
    local tools = box.tools
    tools.search:setText(filter.text)
    tools.search.onTextChange = function(_, text)
        filter.text = text
        fillList(box)
    end
    for _, tab in ipairs({ { tools.tabAll, 'all', 'Todos' }, { tools.tabBestiary, 'bestiary', 'Bestiário' }, { tools.tabBoss, 'boss', 'Bosses' } }) do
        tab[1].view = tab[2]
        tab[1]:setText(T(tab[3]))
        tab[1].onClick = function()
            filter.view = tab[2]
            fillList(box)
        end
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
        cell.chance:setText((percent >= 1 and decimal(percent, 2) or decimal(percent, 3)) .. '%')
        cell:setTooltip(name .. ' - ' .. cell.chance:getText())
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

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
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
    list, listAsked, pages, asked = nil, nil, {}, {}
end

function WikiMonsters.init()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
end

function WikiMonsters.terminate()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    WikiMonsters.reset()
end
