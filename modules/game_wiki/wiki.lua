-- Mythicum Wiki: what the rarity system does, inside the client. The text and
-- numbers live in pages.lua; this file only builds the window from them.

local window
local current
local history = {}
local topicButtons = {}

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

-- ---------------------------------------------------------------- helpers

local function groupOf(id)
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

-- the hunts of one teleport room: monster, recommended level, what else lives there
function builders.hunts(parent, block)
    local tbl = g_ui.createWidget('WikiTable', parent)
    local head = g_ui.createWidget('WikiHuntHead', tbl)
    head.c1:setText('Hunt')
    head.c2:setText(T('Nível'))
    head.c3:setText(T('Também tem'))
    for i, hunt in ipairs(block[2]) do
        local row = g_ui.createWidget(i % 2 == 0 and 'WikiHuntRowEven' or 'WikiHuntRow', tbl)
        local look = hunt[5]
        if look and look.type and look.type > 0 then
            row.creature:setOutfit(look)
        end
        row.name:setText(hunt[1])
        if hunt[4] > 1 then
            row.count:setText(T('%d teleports', hunt[4]))
        else
            row.name:setMarginTop(12)
        end
        row.level:setText(tostring(hunt[2]))
        row.also:setText(hunt[3] ~= '' and hunt[3] or '-')
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
        { T('Defesa'), tier.defense }, { T('Item vira raro'), tier.affix },
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
        row.bonuses:setText(grade.bonuses == 1 and T('1 bônus') or T('%d bônus', grade.bonuses))
        row.band:setText(grade.band)
        local from, to = grade.band:match('(%d+)%% a (%d+)%%')
        from, to = tonumber(from) or 0, tonumber(to) or 100
        row.bar.fill:setMarginLeft(1 + math.floor(BAND_BAR * from / 100))
        row.bar.fill:setWidth(math.max(2, math.floor(BAND_BAR * (to - from) / 100)))
        row.bar.fill:setBackgroundColor(grade.color)
        row.bar:setTooltip(T('Os valores saem entre %s do mínimo e do máximo de cada bônus.', grade.band))
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

-- ---------------------------------------------------------------- window

local function buildTopics()
    window.topics:destroyChildren()
    topicButtons = {}
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
            topicButtons[id] = button
        end
    end
end

local function render(id)
    local page = WIKI_PAGES[id]
    local group = groupOf(id)
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
    id = WIKI_PAGES[id] and id or current or 'tiers'
    if not window then
        window = g_ui.displayUI('wiki')
        buildTopics()
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

function onSearch(text)
    if not window then
        return
    end
    text = plain(text:trim())
    local visibleGroups, any = {}, false
    for _, button in pairs(topicButtons) do
        local match = text == '' or button.words:find(text, 1, true) ~= nil
        button:setVisible(match)
        if match then
            visibleGroups[button.label.group.title] = true
            any = true
        end
    end
    for _, child in ipairs(window.topics:getChildren()) do
        if child.group then
            child:setVisible(visibleGroups[child.group.title] == true)
        end
    end
    window.noResults:setVisible(not any)
end

-- ---------------------------------------------------------------- module

local wikiButton

local function onGameStart()
    if not wikiButton and modules.game_brevespanel then
        wikiButton = modules.game_brevespanel.addFeature('wiki', toggle)
    end
    if not wikiButton and modules.game_mainpanel then
        wikiButton = modules.game_mainpanel.addToggleButton('wikiButton', tr('Mythicum Wiki'),
            '/game_wiki/images/button', toggle, false, 30)
    end
end

local function onGameEnd()
    hide()
end

function init()
    if not WIKI_CONVERTED then
        convertAll(WIKI_GRADES)
        convertAll(WIKI_TIERS)
        convertAll(WIKI_GROUPS)
        convertAll(WIKI_PAGES)
        WIKI_CONVERTED = true
    end
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    hide()
    if wikiButton then
        wikiButton:destroy()
        wikiButton = nil
    end
end
