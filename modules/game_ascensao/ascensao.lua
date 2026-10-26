-- Ascensão: the talent tree window. The server (data-otservbr-global/
-- scripts/ascensao) sends the state on extended opcode OPCODE; this shows
-- the three paths with their circles, the skillshot each one teaches and
-- how strong it is, the relics, the title and the reset. Every button asks
-- the server, which answers with a message and the new state.

local OPCODE = 132

local window
local state
local confirmBox
local panelButton

local COLORS = {
    owned = { name = '#f3dcae', desc = '#d8cfbf', border = '#8a7d5c', number = '#170f24', numberBg = '#f3dcae' },
    next = { name = '#ffffff', desc = '#cbc0e0', border = '#b296f5', number = '#ffffff', numberBg = '#b296f560' },
    locked = { name = '#7d7590', desc = '#6f6782', border = '#3a3346', number = '#6f6782', numberBg = '#00000060' },
}

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(OPCODE, data)
    end
end

local function closeConfirm()
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
end

local function confirm(title, message, callback)
    closeConfirm()
    confirmBox = displayGeneralBox(title, message, {
        { text = 'Sim', callback = function() closeConfirm(); callback() end },
        { text = 'N\227o', callback = closeConfirm },
        anchor = AnchorHorizontalCenter,
    }, function() closeConfirm(); callback() end, closeConfirm)
end

local function updateButton()
    if not panelButton or not modules.game_brevespanel then
        return
    end
    local free = state and state.free or 0
    if free > 0 then
        modules.game_brevespanel.setFeatureState('ascensao', tostring(free), '#f3dcae')
    else
        modules.game_brevespanel.setFeatureState('ascensao', nil)
    end
end

-- ---------------------------------------------------------------- art

-- the designer's art (images/, from "Ascensao - artes v1"): the files are
-- 2x, drawn at half size. A vocation whose art has not come yet keeps the
-- numbers and no emblem or relic icon.
local IMAGES = '/game_ascensao/images/'
local ART_VOCATIONS = { druid = true, monk = true, paladin = true, sorcerer = true }

-- the skillshot each path teaches, by its words (images/magias)
local SKILL_ICONS = {
    ['exori tera ico'] = 'corte', ['exani gran ico'] = 'salto', ['exori grip'] = 'gancho',
    ['exori gran san vis'] = 'flecha', ['exevo gran san vis'] = 'juizo', ['exori con vis'] = 'lanca',
    ['exevo gran vis'] = 'raio', ['exevo meteor'] = 'meteoro', ['exevo vis mort'] = 'esfera',
    ['exori frigo vis'] = 'estilhaco', ['exevo frigo grav'] = 'muralha', ['exori tera vis'] = 'raizes',
    ['exori sonic pug'] = 'palma', ['exori dra pug'] = 'chute', ['exani tera pug'] = 'passo',
}

-- the spell under the mouse: the designer's preview (images/previas, the
-- stills of "Ascensao - artes v2")
local preview

local function hidePreview()
    if preview then
        preview:destroy()
        preview = nil
    end
end

local function showPreview(anchor, skill, label)
    hidePreview()
    local path = IMAGES .. 'previas/' .. skill
    if not g_resources.fileExists(path .. '.png') then
        return
    end
    preview = g_ui.createWidget('AscensaoPreview', rootWidget)
    preview.title:setText(label)
    preview.movie:setImageSource(path)
    local pos = anchor:getPosition()
    local x = math.min(pos.x, rootWidget:getWidth() - preview:getWidth() - 4)
    local y = pos.y + anchor:getHeight() + 4
    if y + preview:getHeight() > rootWidget:getHeight() then
        y = pos.y - preview:getHeight() - 4
    end
    preview:setPosition({ x = x, y = y })
    preview:raise()
end

local function vocationArt()
    local slug = state and state.vocation and state.vocation:lower() or ''
    return ART_VOCATIONS[slug] and slug or nil
end

-- what is not bought yet goes grey: the art has no grey version of its own
local function setLocked(widget, locked)
    widget:setImageColor(locked and '#6a6478' or '#ffffff')
    widget:setOpacity(locked and 0.75 or 1)
end

-- ---------------------------------------------------------------- drawing

local function fillCircle(widget, index, circle, owned, cost, soon, pathId)
    local look = index <= owned and COLORS.owned or index == owned + 1 and COLORS.next or COLORS.locked
    local slug = vocationArt()
    widget.art:setVisible(slug ~= nil)
    widget.number:setVisible(slug == nil)
    if slug then
        widget.art.icon:setImageSource(string.format('%s%s/circulo_%s_%s_%d', IMAGES, slug, slug, pathId, index))
        setLocked(widget.art.icon, index > owned)
        local frame = index <= owned and 'comprado' or index == owned + 1 and 'proximo' or 'bloqueado'
        widget.art.frame:setImageSource(IMAGES .. 'moldura_' .. frame)
        widget.name:setMarginLeft(8)
    end
    widget.number:setText(tostring(index))
    widget.number:setColor(look.number)
    widget.number:setBackgroundColor(look.numberBg)
    widget:setBorderColor(look.border)
    widget.name:setText(circle.name)
    widget.name:setColor(look.name)
    widget.cost:setText(index <= owned and 'ok' or (tostring(cost) .. ' pts'))
    local desc = circle.desc
    if soon then
        desc = desc .. ' ' .. '(efeito em breve)'
    end
    widget.desc:setText(desc)
    widget.desc:setColor(look.desc)
end

local function drawPath(path)
    local widget = g_ui.createWidget('AscensaoPath', window.paths)
    widget:setText(path.name .. '  -  ' .. path.kind)
    local owned = path.owned or 0
    widget.skillshot:setText(path.skillshot)
    widget.words:setText(path.words)
    -- the seal: the skillshot's icon, a segment lit per circle, all of it
    -- with the relic
    local skill = SKILL_ICONS[path.words]
    if skill then
        widget.seal.icon:setImageSource(IMAGES .. 'magias/' .. skill)
        setLocked(widget.seal.icon, owned == 0)
        widget.previewArea.onHoverChange = function(self, hovered)
            if hovered then
                showPreview(self, skill, path.skillshot .. '  -  ' .. path.words)
            else
                hidePreview()
            end
        end
    end
    widget.seal.ring:setImageSource(IMAGES .. (state.relic ~= '' and owned >= #path.circles and 'selo_reliquia' or ('selo_' .. owned)))
    local slug = vocationArt()
    if slug then
        widget.emblem:setImageSource(string.format('%s%s/emblema_%s_%s', IMAGES, slug, slug, path.id))
    else
        widget.emblem:hide()
    end
    if owned > 0 then
        widget.power:setText(string.format('For\231a %d%%', path.power))
    else
        widget.power:setText('Aprende no 1\186 c\237rculo')
    end
    for index, circle in ipairs(path.circles) do
        local row = g_ui.createWidget('AscensaoCircle', widget.circles)
        fillCircle(row, index, circle, owned, state.circleCost[index] or 0, circle.soon, path.id)
    end
    local button = widget.buy
    if owned >= #path.circles then
        button:setText(string.format('Completo: %s', path.title))
        button:setEnabled(false)
    else
        local cost = state.circleCost[owned + 1] or 0
        button:setText(string.format('Comprar c\237rculo %d (%d pts)', owned + 1, cost))
        button:setEnabled((state.free or 0) >= cost)
        button.onClick = function()
            send({ action = 'buy', path = path.id })
        end
    end
end

local function drawRelic(relic)
    local widget = g_ui.createWidget('AscensaoRelic', window.relicBox.relics)
    widget.name:setText(relic.name)
    local slug = vocationArt()
    if slug then
        widget.icon:setImageSource(string.format('%s%s/reliquia_%s_%s', IMAGES, slug, slug, relic.id))
        setLocked(widget.icon, state.relic ~= relic.id)
    else
        widget.icon:hide()
        widget.name:setMarginLeft(0)
    end
    local desc = relic.desc
    if relic.soon then
        desc = desc .. ' ' .. '(efeito em breve)'
    end
    widget.desc:setText(desc)
    local owned = state.relic == relic.id
    local action = widget.action
    if owned then
        widget:setBorderColor('#f3dcae')
        widget.name:setColor('#f3dcae')
        action:setText('Despertada')
        action:setEnabled(false)
    elseif state.relic ~= '' then
        action:setText('Outra rel\237quia despertada')
        action:setEnabled(false)
    elseif (state.complete or 0) < #state.paths then
        action:setText('Precisa dos 3 caminhos completos')
        action:setEnabled(false)
    else
        action:setText(string.format('Despertar (%d pts)', state.relicCost or 0))
        action:setEnabled((state.free or 0) >= (state.relicCost or 0))
        action.onClick = function()
            confirm('Rel\237quia', string.format('Despertar %s? S\243 uma rel\237quia pode ser despertada (um reset libera a escolha).', relic.name), function()
                send({ action = 'relic', relic = relic.id })
            end)
        end
    end
end

local function refresh()
    if not window or not state then
        return
    end
    hidePreview()
    window.paths:destroyChildren()
    window.relicBox.relics:destroyChildren()
    if not state.supported then
        window.titleLabel:setText('Sua voca\231\227o n\227o tem Ascens\227o.')
        window.points:setText('')
        window.resetButton:setEnabled(false)
        return
    end
    window.titleLabel:setText(state.title ~= '' and state.title or string.format('%s - sem t\237tulo ainda (complete um caminho)', state.vocation))
    local points = string.format('Pontos: %d livres de %d', state.free or 0, state.total or 0)
    if (state.total or 0) == 0 then
        points = string.format('A Ascens\227o come\231a no level %d: 1 ponto a cada %d levels.', state.startLevel or 50, state.levelsPerPoint or 10)
    elseif state.nextLevel then
        points = points .. '  -  ' .. string.format('pr\243ximo no level %d', state.nextLevel)
    end
    window.points:setText(points)
    for _, path in ipairs(state.paths or {}) do
        drawPath(path)
    end
    for _, relic in ipairs(state.relics or {}) do
        drawRelic(relic)
    end
    window.resetButton:setEnabled((state.spent or 0) > 0)
    window.resetButton:setTooltip((state.resetCost or 0) > 0 and string.format('Custa %d gold', state.resetCost) or 'O primeiro reset \233 gr\225tis')
end

-- ---------------------------------------------------------------- module

function show()
    if not window then
        return
    end
    window:show()
    window:raise()
    window:focus()
    send({ action = 'open' })
end

function hide()
    closeConfirm()
    hidePreview()
    if window then
        window:hide()
    end
end

function toggle()
    if window and window:isVisible() then
        hide()
    else
        show()
    end
end

function askReset()
    if not state or (state.spent or 0) == 0 then
        return
    end
    local cost = state.resetCost or 0
    local text = cost > 0 and string.format('Resetar a Ascens\227o por %d gold? Todos os pontos voltam e as magias que ela ensinou s\227o esquecidas.', cost)
        or 'Resetar a Ascens\227o? O primeiro reset \233 gr\225tis. Todos os pontos voltam e as magias que ela ensinou s\227o esquecidas.'
    confirm('Reset', text, function()
        send({ action = 'reset' })
    end)
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    if data.action == 'state' then
        state = data
        updateButton()
        if data.open and window then
            window:show()
            window:raise()
            window:focus()
        end
        refresh()
    elseif data.action == 'message' and window then
        window.message:setText(data.text or '')
        window.message:setColor(data.ok and '#b6e3a6' or '#f0a0a0')
    end
end

local function onGameStart()
    if not panelButton and modules.game_brevespanel then
        panelButton = modules.game_brevespanel.addFeature('ascensao', toggle)
    end
    send({ action = 'open' })
end

local function onGameEnd()
    hide()
    state = nil
end

function init()
    window = g_ui.displayUI('ascensao')
    window:setText('Ascens\227o')
    window.relicBox:setText('Rel\237quias')
    window:hide()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    closeConfirm()
    if window then
        window:destroy()
        window = nil
    end
end
