-- NPC pages of the Mythos Wiki: every NPC standing on the map, where it
-- stands (the town of the nearest temple and the position of each copy),
-- what it is for (npcinfo.lua) and its shop, from the server
-- (data-otservbr-global/scripts/website/wiki_catalog.lua). An NPC page has
-- the id "n:<name>".

WikiNpcs = {}

local ASK_AGAIN = 2500
local SHOP_LIMIT = 60

local list -- { { name, town, places, sells, buys, look, role, words }, ... }
local listAsked
local pages = {} -- lower name -> server data, or { missing = true }
local asked = {}
local npcFilter = ''
local shopFilters = {} -- "<npc>|sells" -> text

local DIM, WARM, GOLD = '#9789b3', '#f3dcae', '#e2c35a'

local function T(text, ...)
    return WIKI_TEXT.T(text, ...)
end

local function L(text)
    return WIKI_TEXT.latin1(tostring(text or ''))
end

local function num(n)
    return WIKI_TEXT.num(n)
end

local function infoOf(name)
    return WIKI_NPC_INFO and WIKI_NPC_INFO[name] or nil
end

-- what the NPC is for, Latin-1, or a line built from its shop
local function roleOf(name, sells, buys)
    local info = infoOf(name)
    if info and info.role then
        return T(info.role)
    end
    if (sells or 0) > 0 and (buys or 0) > 0 then
        return T('Vende %d itens e compra %d.', sells, buys)
    elseif (sells or 0) > 0 then
        return T('Vende %d itens.', sells)
    elseif (buys or 0) > 0 then
        return T('Compra %d itens.', buys)
    end
    return ''
end

local function lookOf(look)
    look = look or {}
    return { type = look[1] or 0, head = look[2] or 0, body = look[3] or 0, legs = look[4] or 0, feet = look[5] or 0, addons = look[6] or 0, typeEx = look[7] or 0 }
end

local function setLook(creatureWidget, itemWidget, look)
    if look and (look.typeEx or 0) > 0 then
        creatureWidget:setVisible(false)
        itemWidget:setVisible(true)
        itemWidget:setItemId(look.typeEx)
    elseif look and (look.type or 0) > 0 then
        itemWidget:setVisible(false)
        creatureWidget:setVisible(true)
        creatureWidget:setOutfit(look)
        local creature = creatureWidget:getCreature()
        if creature then
            creature:setDirection(Directions.South)
        end
    else
        creatureWidget:setVisible(false)
        itemWidget:setVisible(false)
    end
end

local function askList()
    if not list and (not listAsked or g_clock.millis() - listAsked > ASK_AGAIN) then
        listAsked = g_clock.millis()
        WIKI_REQUEST({ action = 'npcs' })
    end
end

local function askNpc(name)
    local key = name:lower()
    asked[key] = g_clock.millis()
    WIKI_REQUEST({ action = 'npc', name = name })
    scheduleEvent(function()
        if pages[key] == nil and isOpen('n:' .. name) then
            asked[key] = g_clock.millis()
            WIKI_REQUEST({ action = 'npc', name = name })
        end
    end, 800)
end

-- ---------------------------------------------------------------- list

local function fillList(box)
    box.rows:destroyChildren()
    if not list then
        box.tools.count:setText(T('Carregando...'))
        return
    end
    local text = WIKI_TEXT.plain(npcFilter:trim())
    local count = 0
    for _, row in ipairs(list) do
        if text == '' or row.words:find(text, 1, true) then
            count = count + 1
            local line = g_ui.createWidget(count % 2 == 0 and 'WikiNpcRowEven' or 'WikiNpcRow', box.rows)
            setLook(line.creature, line.item, row.look)
            line.name:setText(row.name)
            line.role:setText(row.role)
            local where = row.town
            if row.places > 1 then
                where = T('%s e mais %d lugar%s', row.town, row.places - 1, row.places - 1 == 1 and '' or 'es')
            end
            line.town:setText(where)
            local shop = {}
            if row.sells > 0 then
                table.insert(shop, T('vende %d', row.sells))
            end
            if row.buys > 0 then
                table.insert(shop, T('compra %d', row.buys))
            end
            line.shop:setText(table.concat(shop, ', '))
            if row.role ~= '' then
                line:setTooltip(row.role)
            end
            line.onClick = function() show('n:' .. row.name) end
        end
    end
    box.tools.count:setText(count == 1 and T('1 NPC') or T('%d NPCs', count))
end

function WIKI_BUILDERS.npclist(parent)
    askList()
    local box = g_ui.createWidget('WikiNpcList', parent)
    box.tools.search:setText(npcFilter)
    box.tools.search.onTextChange = function(_, text)
        npcFilter = text
        fillList(box)
    end
    fillList(box)
end

-- ---------------------------------------------------------------- one NPC

local function npcBlocks(d)
    local blocks = { { 'npchead', d } }
    local info = infoOf(d.name)
    if info and info.quest then
        table.insert(blocks, { 'links', { 'quests' } })
    elseif info and info.page then
        table.insert(blocks, { 'links', { info.page } })
    end

    local rows = {}
    for _, place in ipairs(d.places or {}) do
        table.insert(rows, { { L(place[1]), WARM }, T('%d, %d, andar %d', place[2], place[3], place[4]),
            (tonumber(place[5]) or 0) > 60 and { T('longe do templo'), DIM } or { T('perto do templo'), DIM } })
    end
    table.insert(blocks, { 'h', #rows == 1 and T('Onde fica') or T('Onde fica (%d lugares)', #rows) })
    table.insert(blocks, { 'table', widths = { 150, 200, 196 }, head = { T('Cidade'), T('Posição'), '' }, rows = rows })
    table.insert(blocks, { 'p', T('A cidade é a do templo mais perto do NPC. Para ir até outra cidade, entre no teleport Teleportes do templo de Ventera: as salas de teleport levam às cidades.') })

    local currency = (tonumber(d.currency) or 0) ~= 0 and L(d.currencyName ~= '' and d.currencyName or 'tokens') or 'gold'
    if #(d.sells or {}) > 0 then
        table.insert(blocks, { 'h', T('Vende (%d)', #d.sells) })
        table.insert(blocks, { 'shoplist', d.name, 'sells', d.sells, currency })
    end
    if #(d.buys or {}) > 0 then
        table.insert(blocks, { 'h', T('Compra (%d)', #d.buys) })
        table.insert(blocks, { 'shoplist', d.name, 'buys', d.buys, currency })
    end
    if #(d.sells or {}) == 0 and #(d.buys or {}) == 0 then
        table.insert(blocks, { 'h', T('Loja') })
        table.insert(blocks, { 'p', T('Não tem loja.') })
    end
    return blocks
end

function WikiNpcs.page(id)
    local name = id:sub(3)
    local key = name:lower()
    local data = pages[key]
    if data == nil and (not asked[key] or g_clock.millis() - asked[key] > ASK_AGAIN) then
        askNpc(name)
    end
    if not data then
        return { menu = name, title = name, blocks = { { 'p', T('Carregando...') } } }
    end
    if data.missing then
        return { menu = name, title = name, blocks = { { 'p', T('Nenhum NPC com esse nome no mapa.') } } }
    end
    if not data.blocks then
        data.blocks = npcBlocks(data)
    end
    return { menu = data.name, title = data.name, blocks = data.blocks }
end

-- ---------------------------------------------------------------- blocks

function WIKI_BUILDERS.npchead(parent, block)
    local d = block[2]
    local head = g_ui.createWidget('WikiMonsterHead', parent)
    setLook(head.frame.creature, head.frame.item, lookOf(d.look))
    local towns, seen = {}, {}
    for _, place in ipairs(d.places or {}) do
        if not seen[place[1]] then
            seen[place[1]] = true
            table.insert(towns, L(place[1]))
        end
    end
    local where = table.concat(towns, ', ', 1, math.min(#towns, 4))
    if #towns > 4 then
        where = where .. T(' e mais %d', #towns - 4)
    end
    head.tags:setColoredText(T('{NPC, #f3dcae}   %s', where))
    local role = roleOf(d.name, #(d.sells or {}), #(d.buys or {}))
    head.left:setWidth(450)
    head.left:setTextWrap(true)
    head.left:setColoredText(string.format('{%s, #e6e0f2}', role ~= '' and role or T('Sem descrição.')))
    head.right:setText('')
    local height = head.left:getHeight() + 24
    head:setHeight(math.max(100, height))
end

-- a shop: search box, item, price; each row opens the item
local function fillShop(box, key, offers, currency)
    box.rows:destroyChildren()
    local text = WIKI_TEXT.plain((shopFilters[key] or ''):trim())
    local count, shown = 0, 0
    for _, offer in ipairs(offers) do
        local name = L(WIKI_TEXT.titleCase(offer[2] or ''))
        if text == '' or WIKI_TEXT.plain(name):find(text, 1, true) then
            count = count + 1
            if shown < SHOP_LIMIT then
                shown = shown + 1
                local line = g_ui.createWidget(shown % 2 == 0 and 'WikiShopRowEven' or 'WikiShopRow', box.rows)
                line.item:setItemId(offer[1])
                local amount = tonumber(offer[4]) or 1
                line.name:setText(amount > 1 and T('%dx %s', amount, name) or name)
                line.price:setText(T('%s %s', num(offer[3]), currency))
                line.onClick = function() show('i:' .. offer[1]) end
            end
        end
    end
    box.tools.count:setText(count == 1 and T('1 item') or T('%s itens', num(count)))
    box.note:setText(T('Mostrando %d de %s. Busque pelo nome para achar os outros.', SHOP_LIMIT, num(count)))
    box.note:setVisible(count > SHOP_LIMIT)
end

function WIKI_BUILDERS.shoplist(parent, block)
    local key = block[2] .. '|' .. block[3]
    local offers, currency = block[4], block[5]
    local box = g_ui.createWidget('WikiShopList', parent)
    box.tools.search:setText(shopFilters[key] or '')
    box.tools.search:setVisible(#offers > 12)
    box.tools.search.onTextChange = function(_, text)
        shopFilters[key] = text
        fillShop(box, key, offers, currency)
    end
    box.tools.price:setText(block[3] == 'buys' and T('Paga') or T('Preço'))
    fillShop(box, key, offers, currency)
end

-- NPCs of a quest line: { { label, npc name }, ... } -> what, who, where
function WIKI_BUILDERS.npcrows(parent, block)
    askList()
    local towns = {}
    for _, row in ipairs(list or {}) do
        towns[row.name] = row.places > 1 and T('%s e mais %d', row.town, row.places - 1) or row.town
    end
    local rows = {}
    for _, entry in ipairs(block[2]) do
        local name = entry[2]
        table.insert(rows, { entry[1], { name, WARM }, towns[name] or (list and { T('fora do mapa'), DIM } or T('...')), link = 'n:' .. name })
    end
    WIKI_BUILDERS.table(parent, { 'table', widths = { 120, 170, 256 }, head = { T('O quê'), T('NPC'), T('Cidade') }, rows = rows })
end

-- ---------------------------------------------------------------- search box

function WikiNpcs.search(text, limit)
    askList()
    local found = {}
    if not list or #text < 2 then
        return found
    end
    for _, row in ipairs(list) do
        if row.words:find(text, 1, true) then
            table.insert(found, { row.name, 'n:' .. row.name })
            if #found >= limit then
                break
            end
        end
    end
    return found
end

-- ---------------------------------------------------------------- server

WIKI_HANDLERS.npcs = function(data)
    list = {}
    for _, row in ipairs(data.npcs or {}) do
        if type(row) == 'table' and type(row[1]) == 'string' then
            local name = L(row[1])
            local entry = {
                name = name, town = L(row[2] or ''), places = tonumber(row[3]) or 1,
                sells = tonumber(row[4]) or 0, buys = tonumber(row[5]) or 0,
                look = lookOf({ row[6], row[7], row[8], row[9], row[10], row[11], row[12] }),
            }
            entry.role = roleOf(name, entry.sells, entry.buys)
            entry.words = WIKI_TEXT.plain(name .. ' ' .. entry.town .. ' ' .. entry.role)
            table.insert(list, entry)
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    refresh('npcs')
    refresh('quests')
    searchAgain()
end

WIKI_HANDLERS.npc = function(data)
    if type(data.name) ~= 'string' then
        return
    end
    local key = L(data.name):lower()
    if data.missing then
        pages[key] = { missing = true }
    elseif type(data.data) == 'table' then
        local d = data.data
        d.name = L(d.name or data.name)
        pages[key] = d
    end
    refresh('n:' .. L(data.name))
end

function WikiNpcs.reset()
    list, listAsked, pages, asked, npcFilter, shopFilters = nil, nil, {}, {}, '', {}
end
