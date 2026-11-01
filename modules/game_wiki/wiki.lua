-- Mythos Wiki: what the rarity system does, inside the client. The text and
-- numbers live in pages.lua; this file only builds the window from them.

local window
local current
local history = {}
local topicButtons = {}
local section = 'tibia' -- the half of the wiki on the menu (WIKI_SECTIONS)

local BAND_BAR = 158

-- The client's bitmap fonts are cp1252: pages.lua is written in UTF-8, so
-- every string is turned into latin-1 once, when the module loads.
local function latin1(text)
    return (text:gsub('([\194\195])([\128-\191])', function(lead, cont)
        return string.char((lead:byte() - 194) * 64 + cont:byte())
    end))
end

local function convertAll(value)
    for key, v in pairs(value) do
        if type(v) == 'string' then
            value[key] = latin1(v)
        elseif type(v) == 'table' then
            convertAll(v)
        end
    end
end

-- search ignores accents: "bonus" finds "bônus"
local PLAIN = {}
for from, to in pairs({ ['àáâãä'] = 'a', ['éêè'] = 'e', ['íì'] = 'i', ['óôõò'] = 'o', ['úùü'] = 'u', ['ç'] = 'c' }) do
    for _, ch in ipairs({ latin1(from):byte(1, -1) }) do
        PLAIN[string.char(ch)] = to
    end
end

local function plain(text)
    return (text:lower():gsub('[\192-\255]', function(ch) return PLAIN[ch:lower()] or PLAIN[ch] or ch end))
end

local function T(text, ...)
    return string.format(latin1(text), ...)
end

-- 12639 -> "12.639"
local function num(n)
    local digits = tostring(math.floor(math.abs(tonumber(n) or 0)))
    local out = digits:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return ((tonumber(n) or 0) < 0 and '-' or '') .. out
end

local function titleCase(text)
    return (tostring(text or ''):gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

-- for monsters.lua, items.lua, npcs.lua and spells.lua (pages built from
-- what the server sends)
WIKI_TEXT = { T = T, latin1 = latin1, plain = plain, num = num, titleCase = titleCase }

-- the wiki's server answers (extended opcode 134, registered by monsters.lua):
-- action -> function(data)
WIKI_HANDLERS = {}

function WIKI_REQUEST(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(134, data)
    end
end

-- ---------------------------------------------------------------- helpers

-- a page of pages.lua, or one built from the server's data: a monster
-- ("m:<name>", monsters.lua), an item ("i:<id>", items.lua), an NPC
-- ("n:<name>", npcs.lua) or a spell ("s:<name>", spells.lua)
local function pageOf(id)
    if type(id) ~= 'string' then
        return nil
    end
    local prefix = id:sub(1, 2)
    if prefix == 'm:' then
        return WikiMonsters.page(id)
    elseif prefix == 'i:' then
        return WikiItems.page(id)
    elseif prefix == 'n:' then
        return WikiNpcs.page(id)
    elseif prefix == 's:' then
        return WikiSpells.page(id)
    end
    return WIKI_PAGES[id]
end

local function groupOf(id)
    local prefix = id:sub(1, 2)
    if prefix == 'm:' then
        id = 'monsters'
    elseif prefix == 'i:' then
        id = WikiItems.listPageOf(id)
    elseif prefix == 'n:' then
        id = 'npcs'
    elseif prefix == 's:' then
        id = 'spells'
    end
    for _, group in ipairs(WIKI_GROUPS) do
        for _, pageId in ipairs(group.pages) do
            if pageId == id then
                return group
            end
        end
    end
end

local function cellText(cell)
    if type(cell) == 'table' then
        return cell[1], cell[2]
    end
    return tostring(cell or ''), nil
end

local function previewCreature(widget, tier)
    widget:setOutfit({ type = tier.outfit })
    local creature = widget:getCreature()
    if not creature then
        return
    end
    creature:setDirection(Directions.South)
    if tier.shader then
        creature:setShader(tier.shader)
    end
    if tier.effect and g_attachedEffects then
        local effect = g_attachedEffects.getById(tier.effect)
        if effect then
            creature:attachEffect(effect)
        end
    end
end

-- all the words of a page, for the search box
local function pageWords(page)
    local parts = { page.title, page.menu }
    local function add(value)
        if type(value) == 'string' then
            table.insert(parts, value)
        elseif type(value) == 'table' then
            for _, v in pairs(value) do
                add(v)
            end
        end
    end
    add(page.blocks)
    for _, block in ipairs(page.blocks) do
        if block[1] == 'tier' then
            local tier = WIKI_TIERS[block[2]]
            add({ tier.name, tier.monster, tier.arrival })
        end
    end
    return plain(table.concat(parts, ' '))
end

-- ---------------------------------------------------------------- blocks

local builders = {}
WIKI_BUILDERS = builders

function builders.lead(parent, block)
    g_ui.createWidget('WikiLead', parent):setText(block[2])
end

function builders.p(parent, block)
    g_ui.createWidget('WikiText', parent):setText(block[2])
end

function builders.h(parent, block)
    g_ui.createWidget('WikiHeading', parent):setText(block[2])
end

function builders.note(parent, block)
    local note = g_ui.createWidget('WikiNote', parent)
    note.text:setText(block[2])
    note:setHeight(note.text:getHeight() + 12)
end

function builders.table(parent, block)
    local tbl = g_ui.createWidget('WikiTable', parent)
    local widths = block.widths
    if block.head then
        local head = g_ui.createWidget('WikiTableHead', tbl)
        local x = 0
        for i, text in ipairs(block.head) do
            local cell = g_ui.createWidget('WikiHeadCell', head)
            cell:addAnchor(AnchorTop, 'parent', AnchorTop)
            cell:addAnchor(AnchorBottom, 'parent', AnchorBottom)
            cell:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            cell:setMarginLeft(x)
            cell:setWidth(widths[i])
            cell:setText(text)
            x = x + widths[i]
        end
    end
    for r, row in ipairs(block.rows) do
        local line = g_ui.createWidget(r % 2 == 0 and 'WikiTableRowEven' or 'WikiTableRow', tbl)
        local x, height = 0, 18
        for i = 1, #widths do
            local text, color = cellText(row[i])
            local cell = g_ui.createWidget('WikiCell', line)
            cell:addAnchor(AnchorTop, 'parent', AnchorTop)
            cell:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            cell:setMarginLeft(x)
            cell:setWidth(widths[i])
            cell:setText(text)
            if color then
                cell:setColor(color)
            end
            height = math.max(height, cell:getHeight())
            x = x + widths[i]
        end
        line:setHeight(height)
        if row.link then
            line:setTooltip(T('Abrir %s', cellText(row[1])))
            line.onClick = function() show(row.link) end
        end
    end
end

function builders.tierstrip(parent)
    local strip = g_ui.createWidget('WikiStrip', parent)
    for _, key in ipairs(WIKI_TIER_ORDER) do
        local tier = WIKI_TIERS[key]
        local cell = g_ui.createWidget('WikiStripCell', strip)
        -- the same monster under each tier, so only the tier changes
        previewCreature(cell.creature, { outfit = 25, shader = tier.shader })
        cell.name:setText(tier.name)
        cell.name:setColor(tier.color)
        cell.chance:setText(T('%s das mortes', tier.chance))
        cell.onClick = function() show(key) end
    end
end

function builders.tier(parent, block)
    local tier = WIKI_TIERS[block[2]]
    local card = g_ui.createWidget('WikiTierCard', parent)
    previewCreature(card.stage.creature, tier)
    card.monster:setText(T('%s %s', tier.name, tier.monster))
    card.chance:setText(tier.chance)
    card.chance:setColor(tier.color)
    card.chanceText:setText(T('das mortes de monstros comuns voltam como %s.', tier.name))
    local stats = {
        { T('Vida'), tier.hp }, { T('Loot'), tier.loot },
        { T('Ataque'), tier.attack }, { T('Rolagens extras'), tier.rolls },
        { T('Ouro'), tier.gold }, { T('Itens raros'), tier.affix },
        { T('Experiência'), tier.xp }, { T('Caveira'), tier.skull },
    }
    for _, stat in ipairs(stats) do
        local box = g_ui.createWidget('WikiStat', card.stats)
        box.key:setText(stat[1])
        box.value:setText(stat[2])
    end
    card.arrival:setText(T('Chegada: %s', tier.arrival))
end

function builders.grades(parent)
    for _, grade in ipairs(WIKI_GRADES) do
        local row = g_ui.createWidget('WikiGradeRow', parent)
        row.frame:setImageClip({ x = grade.frame * 34, y = 0, width = 34, height = 34 })
        row.frame.item:setItemId(grade.item)
        local item = row.frame.item:getItem()
        if item and grade.shader then
            item:setShader(grade.shader)
        end
        row.name:setText(grade.name)
        row.name:setColor(grade.color)
        if grade.minBonuses and grade.minBonuses < grade.bonuses then
            row.bonuses:setText(T('%d a %d bônus', grade.minBonuses, grade.bonuses))
        else
            row.bonuses:setText(grade.bonuses == 1 and T('1 bônus') or T('%d bônus', grade.bonuses))
        end
        row.band:setText(grade.band)
        local from, to = grade.band:match('(%d+)%% a (%d+)%%')
        from, to = tonumber(from) or 0, tonumber(to) or 100
        row.bar.fill:setMarginLeft(1 + math.floor(BAND_BAR * from / 100))
        row.bar.fill:setWidth(math.max(2, math.floor(BAND_BAR * (to - from) / 100)))
        row.bar.fill:setBackgroundColor(grade.color)
        row.bar:setTooltip(T('Os valores saem entre %s do mínimo e do máximo de cada bônus.', grade.band))
        -- a real roll of this grade, under its row
        if grade.example then
            local example = g_ui.createWidget('WikiText', parent)
            example:setText(T('Exemplo: %s %s: %s', grade.example[1], grade.name, grade.example[2]))
            example:setColor(grade.color)
        end
    end
end

function builders.links(parent, block)
    local links = g_ui.createWidget('WikiLinks', parent)
    for _, id in ipairs(block[2]) do
        local page = WIKI_PAGES[id]
        if page then
            local button = g_ui.createWidget('WikiLinkButton', links)
            button:setText(page.menu)
            button.onClick = function() show(id) end
        end
    end
end

-- big links with a picture: { page, title, text, outfit | item (+ shader) | tier }
function builders.cards(parent, block)
    local grid = g_ui.createWidget('WikiCards', parent)
    for _, card in ipairs(block[2]) do
        if WIKI_PAGES[card.page] then
            local widget = g_ui.createWidget('WikiCard', grid)
            widget.title:setText(card.title or WIKI_PAGES[card.page].menu)
            widget.text:setText(card.text or '')
            if card.tier and WIKI_TIERS[card.tier] then
                widget.creature:setVisible(true)
                previewCreature(widget.creature, WIKI_TIERS[card.tier])
            elseif card.outfit then
                widget.creature:setVisible(true)
                widget.creature:setOutfit({ type = card.outfit, head = card.colors and card.colors[1] or 0, body = card.colors and card.colors[2] or 0,
                    legs = card.colors and card.colors[3] or 0, feet = card.colors and card.colors[4] or 0 })
                local creature = widget.creature:getCreature()
                if creature then
                    creature:setDirection(Directions.South)
                end
            elseif card.item then
                widget.item:setVisible(true)
                widget.item:setItemId(card.item)
                local item = widget.item:getItem()
                if item and card.shader then
                    item:setShader(card.shader)
                end
            end
            widget.onClick = function() show(card.page) end
        end
    end
end

-- ---------------------------------------------------------------- window

local function buildTopics()
    window.topics:destroyChildren()
    topicButtons = {}
    -- monsters, items, NPCs and spells whose name matches the search, above
    -- the pages
    window.topics.monsterHits = g_ui.createWidget('WikiMonsterHits', window.topics)
    -- every group of both halves; the menu shows one half (applyTopics)
    for _, group in ipairs(WIKI_GROUPS) do
        local label = g_ui.createWidget('WikiGroupLabel', window.topics)
        label:setText(group.title)
        label.group = group
        for _, id in ipairs(group.pages) do
            local button = g_ui.createWidget('WikiTopic', window.topics)
            button:setText(WIKI_PAGES[id].menu)
            button.onClick = function() show(id) end
            button.words = pageWords(WIKI_PAGES[id])
            button.label = label
            button.section = group.section or 'tibia'
            topicButtons[id] = button
        end
    end
end

-- the menu: the pages of the open half, or with a search the pages of both
-- halves that have the text; true when any page is shown
local function applyTopics(text)
    local shownLabels, any = {}, false
    for _, button in pairs(topicButtons) do
        local match
        if text == '' then
            match = button.section == section
        else
            match = button.words:find(text, 1, true) ~= nil
        end
        button:setVisible(match)
        if match then
            -- by the group's table: a widget is not the same key every time
            shownLabels[button.label.group] = true
            any = true
        end
    end
    for _, child in ipairs(window.topics:getChildren()) do
        if child.group then
            child:setVisible(shownLabels[child.group] == true)
        end
    end
    return any
end

local function sectionOf(id)
    local group = groupOf(id)
    return group and group.section or 'tibia'
end

local function updateSectionTabs()
    for _, entry in ipairs(WIKI_SECTIONS) do
        local tab = window['section_' .. entry.key]
        if tab then
            tab:setChecked(entry.key == section)
        end
    end
end

local function render(id)
    local page = pageOf(id)
    local group = groupOf(id)
    local half = sectionOf(id)
    if half ~= section then
        section = half
        applyTopics(plain(window.searchEdit:getText():trim()))
    end
    updateSectionTabs()
    window.group:setText(group and group.title or '')
    window.title:setText(page.title)
    window.page:destroyChildren()
    for _, block in ipairs(page.blocks) do
        local builder = builders[block[1]]
        if builder then
            builder(window.page, block)
        end
    end
    window.pageScroll:setValue(0)
    for pageId, button in pairs(topicButtons) do
        button:setChecked(pageId == id)
    end
    window.backButton:setEnabled(#history > 0)
end

function show(id)
    id = pageOf(id) and id or current or 'home'
    if not window then
        window = g_ui.displayUI('wiki')
        for _, entry in ipairs(WIKI_SECTIONS) do
            local tab = window['section_' .. entry.key]
            if tab then
                tab:setText(entry.tab)
                tab:setTooltip(entry.title)
                tab.onClick = function() showSection(entry.key) end
            end
        end
        buildTopics()
        applyTopics('')
    end
    if current and current ~= id then
        table.insert(history, current)
    end
    current = id
    render(id)
    window:show()
    window:raise()
    window:focus()
end

-- the server answered: draw the page again if it is the one open
function refresh(id)
    if window and current == id then
        local scroll = window.pageScroll:getValue()
        render(id)
        window.pageScroll:setValue(scroll)
    end
end

function isOpen(id)
    return window ~= nil and current == id
end

-- a half of the wiki: its home page
function showSection(key)
    for _, entry in ipairs(WIKI_SECTIONS) do
        if entry.key == key then
            section = key
            if window then
                applyTopics(plain(window.searchEdit:getText():trim()))
            end
            show(entry.home)
            return
        end
    end
end

-- the open page back to its top (the creature list's pages)
function scrollTop()
    if window then
        window.pageScroll:setValue(0)
    end
end

-- draw the open page again if its id starts with `prefix` (a list it uses
-- arrived: monster looks on an item page, the spells)
function refreshCurrent(prefix)
    if window and current and current:sub(1, #prefix) == prefix then
        refresh(current)
    end
end

function back()
    local id = table.remove(history)
    if id and window then
        current = id
        render(id)
    end
end

function hide()
    if window then
        window:destroy()
        window = nil
    end
    history = {}
    topicButtons = {}
end

function toggle()
    if window and window:isVisible() then
        hide()
    else
        show(current)
    end
end

-- what the search box finds in the server's lists: { title, hits = { { text, page id } } }
local function searchSections(text)
    local sections = {}
    local function add(title, hits)
        if #hits > 0 then
            table.insert(sections, { title = title, hits = hits })
        end
    end
    local monsters = {}
    for _, name in ipairs(WikiMonsters.search(text, 10)) do
        table.insert(monsters, { name, 'm:' .. name })
    end
    add(T('Monstros'), monsters)
    add(T('Itens'), WikiItems.search(text, 12))
    add(T('NPCs'), WikiNpcs.search(text, 8))
    add(T('Magias'), WikiSpells.search(text, 8))
    return sections
end

local function showMonsterHits(text)
    local box = window.topics.monsterHits
    box:destroyChildren()
    local sections = searchSections(text)
    if #sections == 0 then
        box:setVisible(false)
        return false
    end
    box:setVisible(true)
    for _, section in ipairs(sections) do
        g_ui.createWidget('WikiGroupLabel', box):setText(section.title)
        for _, hit in ipairs(section.hits) do
            local button = g_ui.createWidget('WikiTopic', box)
            button:setText(hit[1])
            button:setChecked(current == hit[2])
            button.onClick = function() show(hit[2]) end
        end
    end
    return true
end

function onSearch(text)
    if not window then
        return
    end
    text = plain(text:trim())
    local monsters = showMonsterHits(text)
    local any = applyTopics(text)
    window.noResults:setVisible(not any and not monsters)
end

-- a list arrived (monsters, items, NPCs, spells) while something was typed
-- in the search box
function searchAgain()
    if window then
        onSearch(window.searchEdit:getText())
    end
end

-- ---------------------------------------------------------------- module

local wikiButton

local function onGameStart()
    if not wikiButton and modules.game_brevespanel then
        wikiButton = modules.game_brevespanel.addFeature('wiki', toggle)
    end
    if not wikiButton and modules.game_mainpanel then
        wikiButton = modules.game_mainpanel.addToggleButton('wikiButton', tr('Mythos Wiki'),
            '/game_wiki/images/button', toggle, false, 30)
    end
end

local function onGameEnd()
    hide()
    WikiMonsters.reset()
    WikiItems.reset()
    WikiNpcs.reset()
    WikiSpells.reset()
    WikiSystems.reset()
end

function init()
    if not WIKI_CONVERTED then
        convertAll(WIKI_GRADES)
        convertAll(WIKI_TIERS)
        convertAll(WIKI_GROUPS)
        convertAll(WIKI_PAGES)
        convertAll(WIKI_SECTIONS)
        WIKI_CONVERTED = true
    end
    WikiMonsters.init()
    WikiItems.reset()
    WikiNpcs.reset()
    WikiSpells.reset()
    WikiSystems.reset()
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    hide()
    WikiMonsters.terminate()
    if wikiButton then
        wikiButton:destroy()
        wikiButton = nil
    end
end
