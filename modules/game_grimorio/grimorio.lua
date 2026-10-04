-- Grimório: after level 250 the character earns 1 point every 10 levels and
-- spends them changing how its spells work (two paths per spell, three
-- ranks each, plus seals). Talks to data-otservbr-global/scripts/grimorio
-- through extended opcode GRIMORIO_OPCODE with JSON payloads.

local GRIMORIO_OPCODE = 123

local window
local toolbarButton
local messageEvent
local resetBox

local state -- last "state" from the server
local selected -- spell key, or 'seals'

-- ---------------------------------------------------------------- helpers

-- the fonts draw one glyph per byte (Latin-1); this file and the server's JSON are UTF-8
local function latin1(text)
    return (tostring(text):gsub('[\194\195][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        return string.char((a - 194) * 64 + b)
    end))
end

local function tr(text, ...)
    if select('#', ...) > 0 then
        text = string.format(text, ...)
    end
    return latin1(text)
end

local function convertStrings(value)
    if type(value) == 'string' then
        return latin1(value)
    elseif type(value) == 'table' then
        for k, v in pairs(value) do
            value[k] = convertStrings(v)
        end
    end
    return value
end

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(GRIMORIO_OPCODE, data)
    end
end

local function showMessage(text, ok)
    if not window then
        return
    end
    if messageEvent then
        removeEvent(messageEvent)
    end
    window.message:setText(text or '')
    window.message:setColor(ok and '#7fd35a' or '#ff7a6b')
    messageEvent = scheduleEvent(function()
        messageEvent = nil
        if window then
            window.message:setText('')
        end
    end, 8000)
end

local function spellOf(key)
    for _, spell in ipairs(state and state.spells or {}) do
        if spell.key == key then
            return spell
        end
    end
end

local function pointsWord(n)
    return n == 1 and tr('1 ponto') or tr('%d pontos', n)
end

-- ---------------------------------------------------------------- render

local PATH_COLOR = { A = '#e0a040', B = '#5fa8e8' }

local function renderPath(card, spell, id)
    local def = spell.paths[id]
    local taken = spell.path == id
    local rank = taken and spell.rank or 0
    local locked = spell.path ~= '' and not taken
    card:setText(tr('Caminho %s: ', id) .. def.name)
    card:setColor(locked and '#6a6a6a' or PATH_COLOR[id])
    card.summary:setText(def.summary)
    card.summary:setColor(locked and '#6a6a6a' or '#dfdfdf')
    for i = 1, 3 do
        local line = card['rank' .. i]
        line.text:setText(tr('Grau %d: ', i) .. (def.ranks[i] or ''))
        if i <= rank then
            line.text:setColor('#ffffff')
            line.dot:setBackgroundColor(PATH_COLOR[id])
        elseif not locked and i == rank + 1 then
            line.text:setColor('#bfbfbf')
            line.dot:setBackgroundColor('#00000060')
        else
            line.text:setColor('#5a5a5a')
            line.dot:setBackgroundColor('#00000060')
        end
    end

    local action = card.action
    action.onClick = nil
    if locked then
        action:setText(tr('Bloqueado'))
        action:setEnabled(false)
        card.note:setText(tr('Você escolheu %s. Faça um reset para trocar.', spell.paths[spell.path].name))
    elseif rank >= 3 then
        action:setText(tr('Grau máximo'))
        action:setEnabled(false)
        card.note:setText('')
    else
        local cost = state.rankCost[rank + 1] or 1
        action:setText(tr('Aprender grau %d (%s)', rank + 1, pointsWord(cost)))
        action:setEnabled(state.free >= cost)
        if rank == 0 and spell.path == '' then
            card.note:setText(tr('Escolher este caminho bloqueia o outro.'))
        elseif state.free < cost then
            card.note:setText(tr('Faltam %s.', pointsWord(cost - state.free)))
        else
            card.note:setText('')
        end
        action.onClick = function()
            send({ action = 'buy', spell = spell.key, path = id })
        end
    end
end

local function renderSeals()
    local panel = window.detail.seals
    panel:destroyChildren()
    window.detail.title:setText(tr('Selos do %s', state.vocation or ''))
    local open = state.spellSpent >= state.sealRequires
    window.detail.subtitle:setText(open and tr('Cada selo custa %s.', pointsWord(state.sealCost))
        or tr('Os selos abrem com %d pontos gastos nas magias (você tem %d).', state.sealRequires, state.spellSpent))
    for _, seal in ipairs(state.seals or {}) do
        local card = g_ui.createWidget('GrimorioSealCard', panel)
        card:setText(seal.name)
        card.desc:setText(seal.desc)
        if seal.owned then
            card:setColor('#e0a040')
            card.action:setText(tr('Aprendido'))
            card.action:setEnabled(false)
        else
            card:setColor(open and '#dfdfdf' or '#6a6a6a')
            card.desc:setColor(open and '#dfdfdf' or '#6a6a6a')
            card.action:setText(tr('Aprender (%s)', pointsWord(state.sealCost)))
            card.action:setEnabled(open and state.free >= state.sealCost)
            card.action.onClick = function()
                send({ action = 'seal', seal = seal.id })
            end
        end
    end
end

local function renderDetail()
    local detail = window.detail
    if selected == 'seals' then
        detail.paths:hide()
        detail.seals:show()
        renderSeals()
        return
    end
    local spell = spellOf(selected)
    if not spell then
        return
    end
    detail.seals:hide()
    detail.paths:show()
    detail.title:setText(string.format('%s (%s)', spell.name, spell.words))
    detail.subtitle:setText(tr('Estilo: %s', spell.style))
    renderPath(detail.paths.pathA, spell, 'A')
    renderPath(detail.paths.pathB, spell, 'B')
end

local function selectRow(key)
    selected = key
    for _, row in ipairs(window.spellList:getChildren()) do
        if row:getId() == key then
            window.spellList:focusChild(row)
        end
    end
    renderDetail()
end

local function renderList()
    local list = window.spellList
    list:destroyChildren()
    for _, spell in ipairs(state.spells or {}) do
        local row = g_ui.createWidget('GrimorioSpellRow', list)
        row:setId(spell.key)
        row.name:setText(spell.name)
        row.words:setText(spell.words)
        if spell.path ~= '' then
            row.rank:setText(string.format('%s %d/3', spell.path, spell.rank))
            row.rank:setColor(PATH_COLOR[spell.path])
        else
            row.rank:setText(tr('livre'))
        end
        row.onClick = function() selectRow(spell.key) end
    end
    local row = g_ui.createWidget('GrimorioSpellRow', list)
    row:setId('seals')
    row.name:setText(tr('Selos'))
    local owned = 0
    for _, seal in ipairs(state.seals or {}) do
        if seal.owned then
            owned = owned + 1
        end
    end
    row.words:setText(tr('%d de %d', owned, #(state.seals or {})))
    row.rank:setText(state.spellSpent >= state.sealRequires and tr('aberto') or tr('%d/%d', state.spellSpent, state.sealRequires))
    row.onClick = function() selectRow('seals') end
end

local function render()
    if not window or not state then
        return
    end
    if not state.supported then
        window.points:setText(tr('Grimório em teste: por enquanto só o Knight.'))
        window.pointsNote:setText('')
        window.resetButton:hide()
        window.spellList:destroyChildren()
        window.detail:hide()
        return
    end
    window.detail:show()
    window.resetButton:show()
    if state.total == 0 then
        window.points:setText(tr('Sem pontos ainda (level %d).', state.level))
        window.pointsNote:setText(tr('O primeiro ponto chega no level %d. Depois, 1 ponto a cada %d levels.', state.startLevel + state.levelsPerPoint, state.levelsPerPoint))
    else
        window.points:setText(tr('%s livres de %d (level %d)', pointsWord(state.free), state.total, state.level))
        window.pointsNote:setText(tr('Próximo ponto no level %d.', state.nextLevel))
    end
    window.points:setColor(state.free > 0 and '#7fd35a' or '#ffffff')
    window.resetButton:setText(state.resetCost > 0 and tr('Reset (%d ruby coin%s)', state.resetCost, state.resetCost > 1 and 's' or '') or tr('Reset (grátis)'))
    window.resetButton:setEnabled(state.spent > 0)
    renderList()
    if not selected then
        selected = state.spells[1] and state.spells[1].key
    end
    selectRow(selected)
end

-- ---------------------------------------------------------------- server

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    data = convertStrings(data)
    if data.action == 'state' then
        state = data
        if data.open then
            show()
        end
        render()
    elseif data.action == 'message' then
        showMessage(data.text, data.ok)
    end
end

-- ---------------------------------------------------------------- public (otui)

function askReset()
    if not state or resetBox then
        return
    end
    local text = state.resetCost > 0
        and tr('Devolver os %d pontos gastos por %d ruby coin%s?', state.spent, state.resetCost, state.resetCost > 1 and 's' or '')
        or tr('Devolver os %d pontos gastos? O primeiro reset é grátis, os próximos custam ruby coins.', state.spent)
    local function close()
        if resetBox then
            resetBox:destroy()
            resetBox = nil
        end
    end
    resetBox = displayGeneralBox(tr('Reset do Grimório'), text, {
        { text = tr('Resetar'), callback = function() close(); send({ action = 'reset' }) end },
        { text = tr('Cancelar'), callback = close },
        anchor = AnchorHorizontalCenter,
    }, function() close(); send({ action = 'reset' }) end, close)
end

function selectSpell(key)
    selectRow(key)
end

function show()
    if not window then
        return
    end
    window:show()
    window:raise()
    window:focus()
    if toolbarButton then
        toolbarButton:setOn(true)
    end
end

function hide()
    if not window then
        return
    end
    window:hide()
    if resetBox then
        resetBox:destroy()
        resetBox = nil
    end
    if toolbarButton then
        toolbarButton:setOn(false)
    end
end

function toggle()
    if not window then
        return
    end
    if window:isVisible() then
        hide()
        return
    end
    show()
    send({ action = 'open' })
end

-- ---------------------------------------------------------------- lifecycle

local function onGameStart()
    if not toolbarButton and modules.game_brevespanel then
        toolbarButton = modules.game_brevespanel.addFeature('grimorio', toggle)
    end
end

local function onGameEnd()
    hide()
    state = nil
    selected = nil
end

function init()
    window = g_ui.displayUI('grimorio')
    window:hide()
    window:setText(tr('Grimório'))
    window.footer:setText(tr('A partir do level 250: 1 ponto a cada 10 levels. Cada magia segue um caminho, A ou B.'))

    ProtocolGame.registerExtendedJSONOpcode(GRIMORIO_OPCODE, onOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedJSONOpcode(GRIMORIO_OPCODE)
    if messageEvent then
        removeEvent(messageEvent)
        messageEvent = nil
    end
    if resetBox then
        resetBox:destroy()
        resetBox = nil
    end
    if toolbarButton then
        toolbarButton:destroy()
        toolbarButton = nil
    end
    if window then
        window:destroy()
        window = nil
    end
end
