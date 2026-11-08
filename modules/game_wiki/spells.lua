-- Spell pages of the Mythos Wiki: every spell of the vocations with the
-- numbers this server uses (level, mana, cooldowns...) and how each one is
-- learned, from the server (data-otservbr-global/scripts/website/
-- wiki_catalog.lua). The list "spells" has a tab per vocation; a spell page
-- has the id "s:<name>". Every account has premium here (freePremium), so
-- the premium flag of a spell is not shown.

WikiSpells = {}

local ASK_AGAIN = 2500
local ICONS = '/images/game/spells/spell-icons-32x32'

local VOCATIONS = {
    { 'K', 'Knight' }, { 'P', 'Paladin' }, { 'S', 'Sorcerer' }, { 'D', 'Druid' }, { 'M', 'Monk' },
}
-- the player's vocation id -> its letter
local VOCATION_IDS = { [1] = 'S', [5] = 'S', [2] = 'D', [6] = 'D', [3] = 'P', [7] = 'P', [4] = 'K', [8] = 'K', [9] = 'M', [10] = 'M' }
local GROUPS = { [1] = 'Ataque', [2] = 'Cura', [3] = 'Suporte', [4] = 'Especial' }
local KINDS = { { 'all', 'Todas' }, { 'attack', 'Ataque' }, { 'healing', 'Cura' }, { 'support', 'Suporte' }, { 'rune', 'Runas' } }

local DIM, WARM, PURPLE = '#9789b3', '#f3dcae', '#a679e6'

local list -- { row from the server + words, label }
local byName = {}
local listAsked
local filter = { voc = nil, kind = 'all', text = '' }

local function T(text, ...)
    return WIKI_TEXT.T(text, ...)
end

local function L(text)
    return WIKI_TEXT.latin1(tostring(text or ''))
end

local function num(n)
    return WIKI_TEXT.num(n)
end

-- 2000 -> "2s", 1800000 -> "30 min"
local function duration(ms)
    ms = tonumber(ms) or 0
    if ms <= 0 then
        return '-'
    elseif ms >= 3600000 and ms % 3600000 == 0 then
        return T('%d h', ms / 3600000)
    elseif ms >= 60000 and ms % 60000 == 0 then
        return T('%d min', ms / 60000)
    end
    local seconds = ms / 1000
    return (string.format(seconds == math.floor(seconds) and '%d' or '%.1f', seconds):gsub('%.', ',')) .. 's'
end

local function vocationNames(letters)
    local names = {}
    for _, voc in ipairs(VOCATIONS) do
        if tostring(letters or ''):find(voc[1], 1, true) then
            table.insert(names, voc[2])
        end
    end
    return #names == 5 and T('Todas') or table.concat(names, ', ')
end

local function kindOf(row)
    if (row.rune or 0) > 0 or row.n:find('^Conjure') then
        return 'rune'
    elseif row.g == 1 then
        return 'attack'
    elseif row.g == 2 then
        return 'healing'
    end
    return 'support'
end

local function displayName(row)
    return row.label ~= '' and row.label or row.n
end

local function setIcon(widget, name)
    local info = SpellInfo and SpellInfo.Default and SpellInfo.Default[name]
    if info and tonumber(info.clientId) then
        widget:setImageSource(ICONS)
        widget:setImageClip(Spells.getImageClip(tonumber(info.clientId), 'Default'))
        widget:setVisible(true)
    else
        widget:setVisible(false)
    end
end

-- how the spell is learned
local function learnText(row)
    if row.src == 'ascensao' then
        return T('Ascensão: caminho %s, círculo %d.', L(row.path), row.circle or 1)
    elseif row.src == 'wheel' then
        return T('Roda do Destino, a partir do level %d.', row.lv)
    elseif row.src == 'level' then
        return T('Aprende sozinho ao chegar no level %d.', row.lv)
    elseif row.src == 'learn' then
        return T('Precisa ser aprendida.')
    end
    return T('É sua ao chegar no level %d.', row.lv)
end

local function manaText(row)
    if (row.mp or 0) > 0 then
        return T('%d%% da mana', row.mp)
    end
    return num(row.m)
end

local function askList()
    if not list and (not listAsked or g_clock.millis() - listAsked > ASK_AGAIN) then
        listAsked = g_clock.millis()
        WIKI_REQUEST({ action = 'spells' })
    end
end

local function defaultVocation()
    local player = g_game.getLocalPlayer()
    local vocation = player and player:getVocation() or 0
    return VOCATION_IDS[vocation] or 'K'
end

-- ---------------------------------------------------------------- list

local function fillList(box)
    box.rows:destroyChildren()
    for _, tab in ipairs(box.vocations:getChildren()) do
        tab:setChecked(tab.voc == filter.voc)
    end
    for _, tab in ipairs(box.kinds:getChildren()) do
        tab:setChecked(tab.kind == filter.kind)
    end
    if not list then
        box.kinds.count:setText(T('Carregando...'))
        return
    end
    local text = WIKI_TEXT.plain(filter.text:trim())
    local count = 0
    for _, row in ipairs(list) do
        if row.v:find(filter.voc, 1, true) and (filter.kind == 'all' or kindOf(row) == filter.kind)
            and (text == '' or row.words:find(text, 1, true)) then
            count = count + 1
            local line = g_ui.createWidget(count % 2 == 0 and 'WikiSpellRowEven' or 'WikiSpellRow', box.rows)
            setIcon(line.icon, row.n)
            line.name:setText(displayName(row))
            line.words:setText(L(row.w))
            line.level:setText(T('Lv %d', row.lv))
            line.mana:setText(T('%s mana', manaText(row)))
            local tag, color = '', DIM
            if row.src == 'ascensao' then
                tag, color = T('Ascensão'), PURPLE
            elseif row.src == 'wheel' then
                tag, color = T('Roda do Destino'), PURPLE
            end
            line.tag:setText(tag)
            line.tag:setColor(color)
            line.onClick = function() show('s:' .. row.n) end
        end
    end
    box.kinds.count:setText(count == 1 and T('1 magia') or T('%d magias', count))
end

function WIKI_BUILDERS.spelllist(parent)
    askList()
    filter.voc = filter.voc or defaultVocation()
    local box = g_ui.createWidget('WikiSpellList', parent)
    for _, voc in ipairs(VOCATIONS) do
        local tab = g_ui.createWidget('BrevesTab', box.vocations)
        tab:setWidth(104)
        tab.voc = voc[1]
        tab:setText(voc[2])
        tab.onClick = function()
            filter.voc = voc[1]
            fillList(box)
        end
    end
    for _, kind in ipairs(KINDS) do
        local tab = g_ui.createWidget('WikiKindTab', box.kinds)
        tab.kind = kind[1]
        tab:setText(T(kind[2]))
        tab.onClick = function()
            filter.kind = kind[1]
            fillList(box)
        end
    end
    -- the count stays last in the row of kinds
    local count = g_ui.createWidget('WikiCountLabel', box.kinds)
    count:setId('count')
    box.kinds.count = count
    box.search:setText(filter.text)
    box.search.onTextChange = function(_, text)
        filter.text = text
        fillList(box)
    end
    fillList(box)
end

-- ---------------------------------------------------------------- one spell

local function spellBlocks(row)
    local blocks = { { 'spellhead', row } }
    local rows = {
        { T('Palavras'), { L(row.w), WARM } },
        { T('Vocações'), vocationNames(row.v) },
        { T('Level'), tostring(row.lv) },
    }
    if (row.ml or 0) > 0 then
        table.insert(rows, { T('Magic level'), tostring(row.ml) })
    end
    table.insert(rows, { T('Mana'), manaText(row) })
    if (row.s or 0) > 0 then
        table.insert(rows, { T('Soul'), tostring(row.s) })
    end
    table.insert(rows, { T('Cooldown'), duration(row.cd) })
    if (row.gcd or 0) > 0 then
        table.insert(rows, { T('Cooldown do grupo'), T('%s (%s)', duration(row.gcd), T(GROUPS[row.g] or 'Suporte')) })
    end
    if (row.r or 0) > 0 then
        table.insert(rows, { T('Alcance'), T('%d sqm', row.r) })
    end
    table.insert(rows, { T('Como aprender'), learnText(row) })
    table.insert(blocks, { 'table', widths = { 150, 396 }, rows = rows })

    if (row.rune or 0) > 0 then
        table.insert(blocks, { 'h', T('Runa') })
        table.insert(blocks, { 'p', T('Esta magia transforma uma blank rune na runa abaixo. Clique para ver o que a runa faz e quem a vende.') })
        table.insert(blocks, { 'table', widths = { 300, 246 }, rows = { { { T('Abrir a runa'), WARM }, T('cargas, level e magic level para usar'), link = 'i:' .. row.rune } } })
    end
    -- how to cast it (the Ascensão's spells: aimed with the mouse, charged,
    -- the way you face; Ascensao.spellUse on the server)
    if (row.use or '') ~= '' then
        table.insert(blocks, { 'h', T('Como usar') })
        table.insert(blocks, { 'p', L(row.use) })
    end
    if row.src == 'ascensao' then
        table.insert(blocks, { 'h', T('Ascensão') })
        table.insert(blocks, { 'p', T('Esta magia vem do sistema de Ascensão: gaste os pontos no caminho %s para liberar. O botão Ascensão na barra Mythos abre a janela dos caminhos.', L(row.path)) })
    elseif row.src == 'wheel' then
        table.insert(blocks, { 'p', T('Esta magia vem da Roda do Destino (Wheel of Destiny), a partir do level %d.', row.lv) })
    end
    return blocks
end

function WikiSpells.page(id)
    local name = id:sub(3)
    askList()
    local row = byName[name:lower()]
    if not list then
        return { menu = name, title = name, blocks = { { 'p', T('Carregando...') } } }
    end
    if not row then
        return { menu = name, title = name, blocks = { { 'p', T('Nenhuma magia com esse nome.') } } }
    end
    row.blocks = row.blocks or spellBlocks(row)
    return { menu = displayName(row), title = displayName(row), blocks = row.blocks }
end

function WIKI_BUILDERS.spellhead(parent, block)
    local row = block[2]
    local head = g_ui.createWidget('WikiSpellHead', parent)
    setIcon(head.icon, row.n)
    head.words:setText(L(row.w))
    local tags = { T(GROUPS[row.g] or 'Suporte') }
    if row.src == 'ascensao' then
        table.insert(tags, T('Ascensão'))
    elseif row.src == 'wheel' then
        table.insert(tags, T('Roda do Destino'))
    end
    head.info:setText(T('%s  -  %s', table.concat(tags, ', '), vocationNames(row.v)))
end

-- ---------------------------------------------------------------- search box

function WikiSpells.search(text, limit)
    askList()
    local found = {}
    if not list or #text < 2 then
        return found
    end
    for _, row in ipairs(list) do
        if row.words:find(text, 1, true) then
            table.insert(found, { displayName(row), 's:' .. row.n })
            if #found >= limit then
                break
            end
        end
    end
    return found
end

-- ---------------------------------------------------------------- server

WIKI_HANDLERS.spells = function(data)
    list, byName = {}, {}
    for _, row in ipairs(data.spells or {}) do
        if type(row) == 'table' and type(row.n) == 'string' then
            row.n = L(row.n)
            row.w = row.w or ''
            row.v = row.v or ''
            row.label = L(row.label or '')
            row.src = row.src or ''
            for _, key in ipairs({ 'lv', 'ml', 'm', 'mp', 's', 'cd', 'g', 'gcd', 'r', 'p', 'rune', 'circle' }) do
                row[key] = tonumber(row[key]) or 0
            end
            row.words = WIKI_TEXT.plain(displayName(row) .. ' ' .. row.n .. ' ' .. row.w)
            table.insert(list, row)
            byName[row.n:lower()] = row
        end
    end
    refresh('spells')
    searchAgain()
    -- a spell page opened before the list came
    refreshCurrent('s:')
end

function WikiSpells.reset()
    list, byName, listAsked = nil, {}, nil
    filter = { voc = nil, kind = 'all', text = '' }
end
