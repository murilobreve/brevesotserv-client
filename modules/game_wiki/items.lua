-- Item pages of the Mythos Wiki, like TibiaWiki's: every weapon, piece of
-- equipment and rune of the server, and every other item a monster of our
-- world drops, an NPC on the map sells or the Store sells
-- (data-otservbr-global/scripts/website/wiki_catalog.lua on the server).
-- The list comes once per session and each item's page when it is opened,
-- over extended opcode 134. An item page has the id "i:<item id>"; any id of
-- the item opens the same page.

WikiItems = {}

local LIST_LIMIT = 80
local ASK_AGAIN = 2500 -- ms without an answer before asking again
local FLAG_DROP, FLAG_SOLD, FLAG_BOUGHT, FLAG_RARE, FLAG_STORE = 1, 2, 4, 8, 16

-- the item pages of the menu (pages.lua), one tab per category
WIKI_ITEM_GROUPS = {
    weapons = { 'sword', 'axe', 'club', 'distance', 'ammo', 'wand', 'rod', 'fist', 'training' },
    equipment = { 'helmet', 'armor', 'legs', 'boots', 'shield', 'spellbook', 'quiver', 'amulet', 'ring' },
    supplies = { 'potion', 'rune', 'food' },
    loot = { 'product', 'valuable', 'quest', 'other' },
    otheritems = { 'tool', 'container', 'light', 'taming', 'imbuement', 'key', 'token' },
}

local CATEGORIES = {
    sword = 'Espadas', axe = 'Machados', club = 'Clavas', distance = 'Distância', ammo = 'Munição',
    wand = 'Wands', rod = 'Rods', fist = 'Punhos', training = 'Treino',
    helmet = 'Capacetes', armor = 'Armaduras', legs = 'Calças', boots = 'Botas', shield = 'Escudos',
    spellbook = 'Spellbooks', quiver = 'Aljavas', amulet = 'Amuletos', ring = 'Anéis',
    potion = 'Poções', rune = 'Runas', food = 'Comidas',
    product = 'De criaturas', valuable = 'Valiosos', quest = 'De quests', other = 'Diversos',
    tool = 'Ferramentas', container = 'Bolsas', light = 'Luz', taming = 'Domar', imbuement = 'Imbuement',
    key = 'Chaves', token = 'Tokens',
}

-- the look text's labels in the wiki's words
local STATS = {
    Attack = 'Ataque', Defence = 'Defesa', Armor = 'Armadura', Range = 'Alcance', ['Hit Chance'] = 'Chance de acerto',
    Volume = 'Capacidade', Protection = 'Proteção', Spell = 'Magia', Reflection = 'Reflexão de dano',
    ['Magic Shield'] = 'Escudo mágico', Speed = 'Velocidade', ['Magic level'] = 'Magic level',
}

local VOCATIONS = { K = 'Knight', P = 'Paladin', S = 'Sorcerer', D = 'Druid', M = 'Monk' }

local GOOD, DIM, WARM, GOLD = '#8fdc5e', '#9789b3', '#f3dcae', '#e2c35a'

local list -- { { id, name, cat, level, voc, flags, sum, value, words }, ... }
local byId = {}
local listAsked
local pages = {} -- item id -> server data, or { missing = true }
local asked = {}
local filters = {} -- list page -> { text, cat, sort, here }

local function T(text, ...)
    return WIKI_TEXT.T(text, ...)
end

local function L(text)
    return WIKI_TEXT.latin1(tostring(text or ''))
end

local function num(n)
    return WIKI_TEXT.num(n)
end

local function titleCase(text)
    return WIKI_TEXT.titleCase(text)
end

-- 2.7 -> "2,70"
local function weight(oz)
    return (string.format('%.2f', tonumber(oz) or 0):gsub('%.', ','))
end

local function vocationNames(letters)
    local names = {}
    for letter in tostring(letters or ''):gmatch('%a') do
        table.insert(names, VOCATIONS[letter] or letter)
    end
    return table.concat(names, ', ')
end

-- "Ventera, Carlin e mais 6"
local function townsText(towns)
    if type(towns) ~= 'table' then
        return L(towns)
    end
    local shown = {}
    for i = 1, math.min(#towns, 3) do
        table.insert(shown, L(towns[i]))
    end
    local text = table.concat(shown, ', ')
    if #towns > 3 then
        text = text .. T(' e mais %d', #towns - 3)
    end
    return text
end

local function askList()
    if not list and (not listAsked or g_clock.millis() - listAsked > ASK_AGAIN) then
        listAsked = g_clock.millis()
        WIKI_REQUEST({ action = 'items' })
    end
end

local function askItem(id)
    asked[id] = g_clock.millis()
    WIKI_REQUEST({ action = 'item', id = id })
    -- the server drops a page asked too soon after another: once more
    scheduleEvent(function()
        if pages[id] == nil and isOpen('i:' .. id) then
            asked[id] = g_clock.millis()
            WIKI_REQUEST({ action = 'item', id = id })
        end
    end, 800)
end

-- ---------------------------------------------------------------- list

local function filterOf(page)
    local filter = filters[page]
    if not filter then
        filter = { text = '', cat = WIKI_ITEM_GROUPS[page][1], sort = page == 'loot' and 'value' or 'level', here = true }
        filters[page] = filter
    end
    return filter
end

local function obtainable(row)
    return bit.band(row.flags, FLAG_DROP + FLAG_SOLD + FLAG_STORE) ~= 0
end

local function matches(filter)
    local text = WIKI_TEXT.plain(filter.text:trim())
    local found, hidden = {}, 0
    for _, row in ipairs(list or {}) do
        if row.cat == filter.cat and (text == '' or row.words:find(text, 1, true)) then
            if filter.here and not obtainable(row) then
                hidden = hidden + 1
            else
                table.insert(found, row)
            end
        end
    end
    local sorters = {
        name = function(a, b) return a.words < b.words end,
        level = function(a, b)
            if a.level ~= b.level then
                return a.level < b.level
            end
            return a.words < b.words
        end,
        value = function(a, b)
            if a.value ~= b.value then
                return a.value > b.value
            end
            return a.words < b.words
        end,
    }
    table.sort(found, sorters[filter.sort] or sorters.name)
    return found, hidden
end

-- where it comes from, in a few letters: "monstros, NPC, Store"
local function sourcesText(row)
    local parts = {}
    if bit.band(row.flags, FLAG_DROP) ~= 0 then
        table.insert(parts, T('monstros'))
    end
    if bit.band(row.flags, FLAG_SOLD) ~= 0 then
        table.insert(parts, T('NPC'))
    end
    if bit.band(row.flags, FLAG_STORE) ~= 0 then
        table.insert(parts, T('Store'))
    end
    return table.concat(parts, ', ')
end

local function fillList(box, page)
    local filter = filterOf(page)
    box.rows:destroyChildren()
    for _, tab in ipairs(box.tabs:getChildren()) do
        tab:setChecked(tab.cat == filter.cat)
    end
    for _, tab in ipairs({ box.tools.sortName, box.tools.sortLevel, box.tools.sortValue }) do
        tab:setChecked(tab.sort == filter.sort)
    end
    box.tools.here:setChecked(filter.here)
    if not list then
        box.tools.count:setText(T('Carregando...'))
        box.note:setVisible(false)
        return
    end
    local found, hidden = matches(filter)
    for i = 1, math.min(#found, LIST_LIMIT) do
        local row = found[i]
        local line = g_ui.createWidget(i % 2 == 0 and 'WikiItemRowEven' or 'WikiItemRow', box.rows)
        line.item:setItemId(row.id)
        line.name:setText(row.name)
        local info = {}
        if row.level > 0 then
            table.insert(info, T('Lv %d', row.level))
        end
        if row.voc ~= '' then
            table.insert(info, (vocationNames(row.voc):gsub(', ', '/')))
        end
        if row.sum ~= '' then
            table.insert(info, row.sum)
        end
        line.info:setText(table.concat(info, '  '))
        if row.value > 0 then
            line.value:setText(T('NPC paga %s', num(row.value)))
            line.value:setColor(GOLD)
        else
            line.value:setText('')
        end
        local sources = sourcesText(row)
        line.source:setText(sources ~= '' and sources or T('não se consegue aqui'))
        line.source:setColor(sources ~= '' and DIM or '#6c6380')
        line.onClick = function() show('i:' .. row.id) end
    end
    local count = #found == 1 and T('1 item') or T('%s itens', num(#found))
    box.tools.count:setText(count)
    local notes = {}
    if #found > LIST_LIMIT then
        table.insert(notes, T('Mostrando %d de %s. Busque pelo nome para achar os outros.', LIST_LIMIT, num(#found)))
    elseif #found == 0 then
        table.insert(notes, T('Nenhum item com esse filtro.'))
    end
    if hidden > 0 then
        table.insert(notes, hidden == 1 and T('1 item escondido: nenhum monstro do nosso mundo dropa, nenhum NPC e nem a Store vendem. Desligue "Só obtíveis" para ver.')
            or T('%s itens escondidos: nenhum monstro do nosso mundo dropa, nenhum NPC e nem a Store vendem. Desligue "Só obtíveis" para ver.', num(hidden)))
    end
    box.note:setText(table.concat(notes, ' '))
    box.note:setVisible(#notes > 0)
end

function WIKI_BUILDERS.itemlist(parent, block)
    askList()
    local page = block[2]
    local filter = filterOf(page)
    local box = g_ui.createWidget('WikiItemList', parent)
    for _, cat in ipairs(WIKI_ITEM_GROUPS[page]) do
        local tab = g_ui.createWidget('BrevesTab', box.tabs)
        tab.cat = cat
        tab:setText(T(CATEGORIES[cat] or cat))
        tab.onClick = function()
            filter.cat = cat
            fillList(box, page)
        end
    end
    local tools = box.tools
    tools.search:setText(filter.text)
    tools.search.onTextChange = function(_, text)
        filter.text = text
        fillList(box, page)
    end
    for _, entry in ipairs({ { tools.sortName, 'name', 'Nome' }, { tools.sortLevel, 'level', 'Level' }, { tools.sortValue, 'value', 'Valor' } }) do
        entry[1].sort = entry[2]
        entry[1]:setText(T(entry[3]))
        entry[1].onClick = function()
            filter.sort = entry[2]
            fillList(box, page)
        end
    end
    tools.here:setText(T('Só obtíveis'))
    tools.here:setTooltip(T('Esconde os itens que nenhum monstro do nosso mundo dropa e que nenhum NPC e nem a Store vendem.'))
    tools.here.onClick = function()
        filter.here = not filter.here
        fillList(box, page)
    end
    fillList(box, page)
end

-- ---------------------------------------------------------------- one item

local function statRows(d)
    local rows = {}
    for _, stat in ipairs(d.stats or {}) do
        local label = STATS[stat.label] or stat.label
        table.insert(rows, { T(label), L(stat.value ~= '' and stat.value or '-') })
    end
    local wield = d.wield or {}
    local needs = {}
    if (tonumber(wield.level) or 0) > 0 then
        table.insert(needs, T('level %d', wield.level))
    end
    if (tonumber(wield.magic) or 0) > 0 then
        table.insert(needs, T('magic level %d', wield.magic))
    end
    if wield.vocations then
        table.insert(needs, L(tostring(wield.vocations):gsub(' and ', ' e ')))
    elseif d.vocations ~= '' and d.category ~= 'rune' then
        table.insert(needs, vocationNames(d.vocations))
    end
    if #needs > 0 then
        table.insert(rows, { T('Para usar'), table.concat(needs, ', ') })
    end
    -- a rune's note repeats the level and magic level of its own table
    if d.note and d.note ~= '' and not d.rune then
        table.insert(rows, { T('Detalhe'), L(d.note) })
    end
    if (tonumber(d.slots) or 0) > 0 then
        table.insert(rows, { T('Slots de imbuement'), tostring(d.slots) })
    end
    table.insert(rows, { T('Peso'), T('%s oz', weight(d.weight)) .. (d.stackable and T(' (empilha)') or '') })
    for _, line in ipairs(d.lines or {}) do
        table.insert(rows, { T('Descrição'), L(line) })
    end
    return rows
end

local function itemBlocks(d)
    local blocks = { { 'itemhead', d } }
    table.insert(blocks, { 'table', widths = { 150, 396 }, rows = statRows(d) })

    if d.rune then
        local rune = d.rune
        table.insert(blocks, { 'h', T('Runa') })
        local rows = {
            { T('Para usar'), T('level %d e magic level %d', rune.level or 0, rune.magic or 0) },
            { T('Cargas'), tostring(rune.charges or 0) },
            { T('Quem usa'), rune.vocations ~= '' and vocationNames(rune.vocations) or T('Todas as vocações') },
        }
        local conjure = rune.conjure
        if conjure then
            table.insert(rows, { T('Como fazer'), { T('%s (%s): level %d, %s de mana, %d de soul. %s.', L(conjure.name), L(conjure.words), conjure.level or 0, num(conjure.mana), conjure.soul or 0, vocationNames(conjure.vocations)), WARM }, link = 's:' .. L(conjure.name) })
        else
            table.insert(rows, { T('Como fazer'), { T('Nenhuma magia faz esta runa.'), DIM } })
        end
        table.insert(blocks, { 'table', widths = { 150, 396 }, rows = rows })
    end

    table.insert(blocks, { 'h', T('Onde conseguir') })
    local any = false
    if #(d.drops or {}) > 0 then
        any = true
        table.insert(blocks, { 'p', T('Dropado por (%d):', #d.drops) })
        table.insert(blocks, { 'dropgrid', d.drops })
        table.insert(blocks, { 'droppers', d.name })
    end
    if #(d.sells or {}) > 0 then
        any = true
        local rows = {}
        for _, entry in ipairs(d.sells) do
            table.insert(rows, { { L(entry[1]), WARM }, T('%s %s', num(entry[2]), entry[4] ~= 0 and T('tokens') or T('gold')), townsText(entry[3]), link = 'n:' .. L(entry[1]) })
        end
        table.insert(blocks, { 'p', T('Vendido por:') })
        table.insert(blocks, { 'table', widths = { 150, 120, 276 }, head = { T('NPC'), T('Preço'), T('Onde') }, rows = rows })
    end
    if #(d.store or {}) > 0 then
        any = true
        local rows = {}
        for _, entry in ipairs(d.store) do
            table.insert(rows, { L(entry[1]), T('%s coins', num(entry[2])), T('%s unidade%s', num(entry[3]), (tonumber(entry[3]) or 1) == 1 and '' or 's') })
        end
        table.insert(blocks, { 'p', T('Na Store:') })
        table.insert(blocks, { 'table', widths = { 200, 120, 226 }, head = { T('Oferta'), T('Preço'), T('Quantidade') }, rows = rows })
    end
    if not any then
        table.insert(blocks, { 'p', T('Nenhum monstro do nosso mundo dropa este item, e nenhum NPC e nem a Store o vendem.') })
    end

    if #(d.buys or {}) > 0 then
        local rows = {}
        for _, entry in ipairs(d.buys) do
            table.insert(rows, { { L(entry[1]), WARM }, { T('%s %s', num(entry[2]), entry[4] ~= 0 and T('tokens') or T('gold')), GOLD }, townsText(entry[3]), link = 'n:' .. L(entry[1]) })
        end
        table.insert(blocks, { 'h', T('Quem compra') })
        table.insert(blocks, { 'table', widths = { 150, 120, 276 }, head = { T('NPC'), T('Paga'), T('Onde') }, rows = rows })
    end

    if #(d.imbuements or {}) > 0 then
        local rows = {}
        local levels = { 'Basic', 'Intricate', 'Powerful' }
        for _, entry in ipairs(d.imbuements) do
            table.insert(rows, { { T('%s %s', levels[entry[2]] or '', L(entry[1])), WARM }, T('%s unidades', num(entry[3])), link = 'imbuements' })
        end
        table.insert(blocks, { 'h', T('Usado em imbuements') })
        table.insert(blocks, { 'table', widths = { 300, 246 }, rows = rows })
    end

    if d.rare then
        table.insert(blocks, { 'h', T('Raridade') })
        table.insert(blocks, { 'p', T('Este item pode ter raridade, de Communis a Mythicus, com bônus sorteados. Um item raro cai de monstros raros (Pale, Ashen, Obsidian e Lord of Death).') })
        table.insert(blocks, { 'links', { 'items', 'grades', 'pools' } })
    end
    return blocks
end

-- WIKI page for "i:<id>": loading, missing or the item
function WikiItems.page(id)
    local itemId = tonumber(id:sub(3)) or 0
    local data = pages[itemId]
    if data == nil and (not asked[itemId] or g_clock.millis() - asked[itemId] > ASK_AGAIN) then
        askItem(itemId)
    end
    local row = byId[itemId]
    local name = row and row.name or T('Item')
    if not data then
        return { menu = name, title = name, blocks = { { 'p', T('Carregando...') } } }
    end
    if data.missing then
        return { menu = name, title = name, blocks = { { 'p', T('Este item não está na wiki: não é arma, equipamento nem runa, e nada no nosso mundo o dá.') } } }
    end
    if not data.blocks then
        data.blocks = itemBlocks(data)
    end
    local title = titleCase(data.name)
    return { menu = title, title = title, blocks = data.blocks }
end

-- the menu page an item page belongs to
function WikiItems.listPageOf(id)
    local itemId = tonumber(id:sub(3)) or 0
    local data = pages[itemId]
    local row = byId[itemId]
    local cat = (type(data) == 'table' and data.category) or (row and row.cat)
    for page, cats in pairs(WIKI_ITEM_GROUPS) do
        for _, key in ipairs(cats) do
            if key == cat then
                return page
            end
        end
    end
    return 'weapons'
end

-- ---------------------------------------------------------------- blocks

function WIKI_BUILDERS.itemhead(parent, block)
    local d = block[2]
    local head = g_ui.createWidget('WikiMonsterHead', parent)
    head.frame.creature:setVisible(false)
    head.frame.item:setVisible(true)
    head.frame.item:setItemId(d.id)

    local tags = { T('{%s, #f3dcae}', T(CATEGORIES[d.category] or d.category)) }
    if d.rare then
        table.insert(tags, T('{Pode vir raro, #a679e6}'))
    end
    if d.stackable then
        table.insert(tags, T('Empilhável'))
    end
    head.tags:setColoredText(table.concat(tags, '   '))

    local function line(key, value)
        return string.format('%s {%s, #f3f0fa}', T(key), value)
    end
    local left = {}
    for i, stat in ipairs(d.stats or {}) do
        if i > 4 then
            break
        end
        table.insert(left, line((STATS[stat.label] or stat.label) .. ':', L(stat.value)))
    end
    if #left == 0 then
        table.insert(left, line('Peso:', T('%s oz', weight(d.weight))))
    end
    head.left:setColoredText(table.concat(left, '\n'))

    local right = {}
    if (tonumber(d.level) or 0) > 0 then
        table.insert(right, line('Level:', tostring(d.level)))
    end
    if d.vocations ~= '' and d.category ~= 'rune' then
        table.insert(right, line('Vocações:', vocationNames(d.vocations)))
    end
    local best = 0
    for _, entry in ipairs(d.buys or {}) do
        if entry[4] == 0 then
            best = math.max(best, tonumber(entry[2]) or 0)
        end
    end
    if best > 0 then
        table.insert(right, string.format('%s {%s gold, #e2c35a}', T('NPC paga até'), num(best)))
    end
    if #(d.drops or {}) > 0 then
        table.insert(right, line('Dropado por:', T('%d monstro%s', #d.drops, #d.drops == 1 and '' or 's')))
    end
    head.right:setColoredText(table.concat(right, '\n'))
    local height = math.max(head.left:getHeight(), head.right:getHeight()) + 24
    head:setHeight(math.max(100, height))
end

-- the monsters that drop the item, with their look and the chance
function WIKI_BUILDERS.dropgrid(parent, block)
    local grid = g_ui.createWidget('WikiDropGrid', parent)
    for _, entry in ipairs(block[2]) do
        local name = L(entry[1])
        local cell = g_ui.createWidget('WikiDropCell', grid)
        local look = WikiMonsters.lookOf(name)
        if look and (look.typeEx or 0) > 0 then
            cell.creature:setVisible(false)
            cell.item:setVisible(true)
            cell.item:setItemId(look.typeEx)
        elseif look and (look.type or 0) > 0 then
            cell.creature:setOutfit(look)
            local creature = cell.creature:getCreature()
            if creature then
                creature:setDirection(Directions.South)
            end
        end
        cell.name:setText(name)
        if entry[5] == 1 then
            cell.name:setColor('#ff9a1f')
        end
        local percent = (tonumber(entry[2]) or 0) / 1000
        local chance = (percent >= 1 and string.format('%.2f', percent) or string.format('%.3f', percent)):gsub('0+$', ''):gsub('%.$', ''):gsub('%.', ',') .. '%'
        local max, min = tonumber(entry[4]) or 1, math.max(1, tonumber(entry[3]) or 1)
        if max > 1 then
            chance = chance .. T('  (%s)', min < max and (min .. '-' .. max) or tostring(max))
        end
        cell.chance:setText(chance)
        cell:setTooltip(T('%s: %s por kill. Clique para abrir o monstro.', name, chance))
        cell.onClick = function() show('m:' .. name) end
    end
end

-- ---------------------------------------------------------------- for the creature list

-- true once the item list came (asks for it the first time)
function WikiItems.ready()
    askList()
    return list ~= nil
end

function WikiItems.nameOf(id)
    local row = byId[id]
    return row and row.name or nil
end

-- what an NPC pays for it, 0 when none buys it
function WikiItems.valueOf(id)
    local row = byId[id]
    return row and row.value or 0
end

-- the ids of the items whose name has the text (already plain): id -> true
function WikiItems.idsMatching(text)
    local ids = {}
    for _, row in ipairs(list or {}) do
        if row.words:find(text, 1, true) then
            ids[row.id] = true
        end
    end
    return ids
end

-- the button that opens the creature list filtered by this item
function WIKI_BUILDERS.droppers(parent, block)
    local links = g_ui.createWidget('WikiLinks', parent)
    local button = g_ui.createWidget('WikiLinkButton', links)
    button:setText(T('Comparar na lista de criaturas'))
    button:setWidth(210)
    button:setTooltip(T('A lista de criaturas só com as que dropam este item, com vida, XP, gold por kill e fraquezas de cada uma'))
    button.onClick = function() WikiMonsters.showDroppers(L(block[2] or '')) end
end

-- ---------------------------------------------------------------- search box

-- items whose name has the text: { { name, page id }, ... }
function WikiItems.search(text, limit)
    askList()
    local found = {}
    if not list or #text < 2 then
        return found
    end
    for _, row in ipairs(list) do
        if row.words:find(text, 1, true) then
            table.insert(found, { row.name, 'i:' .. row.id })
            if #found >= limit then
                break
            end
        end
    end
    return found
end

-- ---------------------------------------------------------------- server

WIKI_HANDLERS.items = function(data)
    list, byId = {}, {}
    for _, row in ipairs(data.items or {}) do
        if type(row) == 'table' and tonumber(row[1]) and type(row[2]) == 'string' then
            local name = L(titleCase(row[2]))
            local entry = {
                id = row[1], name = name, cat = row[3] or 'other', level = tonumber(row[4]) or 0, voc = row[5] or '',
                flags = tonumber(row[6]) or 0, sum = L(row[7] or ''), value = tonumber(row[8]) or 0,
                words = WIKI_TEXT.plain(name),
            }
            table.insert(list, entry)
            byId[entry.id] = entry
        end
    end
    table.sort(list, function(a, b) return a.words < b.words end)
    for page in pairs(WIKI_ITEM_GROUPS) do
        refresh(page)
    end
    -- the creature list's loot filter and prices need the names
    refresh('monsters')
    refreshCurrent('m:')
    searchAgain()
end

WIKI_HANDLERS.item = function(data)
    local id = tonumber(data.id)
    if not id then
        return
    end
    if data.missing then
        pages[id] = { missing = true }
    elseif type(data.data) == 'table' then
        pages[id] = data.data
        local canonical = tonumber(data.data.id)
        if canonical and canonical ~= id then
            pages[canonical] = data.data
        end
    end
    refresh('i:' .. id)
end

-- ---------------------------------------------------------------- imbuements

local imbuements -- the server's list: { { name, group, levels = { { level, name, text, items } } } }
local imbuementBases
local imbuementsAsked

local function askImbuements()
    if not imbuements and (not imbuementsAsked or g_clock.millis() - imbuementsAsked > ASK_AGAIN) then
        imbuementsAsked = g_clock.millis()
        WIKI_REQUEST({ action = 'imbuements' })
    end
end

local ELEMENT_NAMES = { death = 'morte', earth = 'terra', energy = 'energia', fire = 'fogo', ice = 'gelo', holy = 'sagrado' }

-- the effect lines of imbuements.xml in the wiki's words
local IMBUEMENT_TEXTS = {
    { '^Converts (%d+)%% of the physical damage to (%a+) damage%.$', function(n, element) return T('Converte %s%% do dano físico em dano de %s.', n, T(ELEMENT_NAMES[element] or element)) end },
    { '^Converts (%d+)%% of damage to HP with a chance of (%d+)%%%.$', function(n) return T('Recupera em vida %s%% do dano que você causa.', n) end },
    { '^Converts (%d+)%% of damage to MP with a chance of (%d+)%%%.$', function(n) return T('Recupera em mana %s%% do dano que você causa.', n) end },
    { '^Raises crit hit damage by (%d+)%% and crit hit chance by (%d+)%%%.$', function(damage, chance) return T('+%s%% de dano crítico e +%s%% de chance de crítico.', damage, chance) end },
    { '^Raises (%a+) fighting skill by (%d+)%.$', function(skill, n) return T('+%s de %s fighting.', n, skill) end },
    { '^Raises shielding skill by (%d+)%.$', function(n) return T('+%s de shielding.', n) end },
    { '^Raises magic level by (%d+)%.$', function(n) return T('+%s de magic level.', n) end },
    { '^Raises capacity by (%d+)%.$', function(n) return T('+%s%% de capacidade.', n) end },
    { '^Raises walking speed by (%d+)%.$', function(n) return T('+%s de velocidade.', n) end },
    { '^Reduces (%a+) damage by (%d+)%%%.$', function(element, n) return T('Reduz em %s%% o dano de %s que você recebe.', n, T(ELEMENT_NAMES[element] or element)) end },
    { '^Removes paralysis with a chance of (%d+)%%', function(n) return T('Tira a paralisia com %s%% de chance.', n) end },
}

local function imbuementText(text)
    text = tostring(text or '')
    for _, entry in ipairs(IMBUEMENT_TEXTS) do
        local captures = { text:match(entry[1]) }
        if #captures > 0 then
            return entry[2](unpack(captures))
        end
    end
    return L(text)
end

-- 72000 s -> "20 h"
local function hours(seconds)
    seconds = tonumber(seconds) or 0
    if seconds >= 3600 then
        return T('%d h', math.floor(seconds / 3600))
    end
    return T('%d min', math.floor(seconds / 60))
end

-- every imbuement, a table each: level, effect, materials
function WIKI_BUILDERS.imbuementlist(parent)
    askImbuements()
    if not imbuements then
        g_ui.createWidget('WikiText', parent):setText(T('Carregando...'))
        return
    end
    if imbuementBases and #imbuementBases > 0 then
        local rows = {}
        for _, base in ipairs(imbuementBases) do
            table.insert(rows, { { L(base.name), WARM }, T('%s gold', num(base.price)), T('%d%%', base.percent or 0),
                T('+%s gold', num(base.protection)), hours(base.duration) })
        end
        g_ui.createWidget('WikiHeading', parent):setText(T('Níveis'))
        WIKI_BUILDERS.table(parent, { 'table', widths = { 110, 100, 90, 120, 126 },
            head = { T('Nível'), T('Taxa'), T('Chance'), T('Proteção'), T('Duração') }, rows = rows })
        g_ui.createWidget('WikiText', parent):setText(T('A taxa é cobrada no santuário de imbuement (imbuing shrine). Sem proteção o imbuement pode falhar (a chance acima); pagando a proteção ele sempre funciona. O tempo dos imbuements de combate só corre com o item equipado, em luta e fora de área protegida; os de velocidade, capacidade e paralisia correm sempre que o item está equipado.'))
    end
    for _, entry in ipairs(imbuements) do
        g_ui.createWidget('WikiHeading', parent):setText(T('%s  -  %s', L(entry.name), L(entry.group)))
        local rows = {}
        for _, level in ipairs(entry.levels or {}) do
            local materials = {}
            for _, item in ipairs(level.items or {}) do
                table.insert(materials, T('%dx %s', tonumber(item[3]) or 1, L(item[2])))
            end
            table.insert(rows, { { L(level.name), WARM }, imbuementText(level.text), table.concat(materials, ', ') })
        end
        WIKI_BUILDERS.table(parent, { 'table', widths = { 90, 220, 236 }, rows = rows })
    end
end

WIKI_HANDLERS.imbuements = function(data)
    imbuements = type(data.imbuements) == 'table' and data.imbuements or {}
    imbuementBases = type(data.bases) == 'table' and data.bases or {}
    refresh('imbuements')
end

function WikiItems.reset()
    list, byId, listAsked, pages, asked, filters = nil, {}, nil, {}, {}, {}
    imbuements, imbuementBases, imbuementsAsked = nil, nil, nil
end
