-- Ascens�o: the web window. The server (data-otservbr-global/scripts/
-- ascensao) sends the web once (its nodes and links) and the state on
-- extended opcode OPCODE; this draws the web - the three paths as its
-- spines, with their circles and relics, and the nodes between them -,
-- lets the player drag and zoom it, tells about the chosen node and buys
-- it. Every button asks the server, which answers with a message and the
-- new state.

local OPCODE = 132

local window
local state
local confirmBox
local panelButton

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

-- `text` broken into lines of at most `width` px in `label`'s font, by whole
-- words. The engine's own wrap reads the Latin-1 accents as UTF-8 (the "ã"
-- of "botão" swallows the space after it) and breaks the lines wrong
local function wrapLines(label, text, width)
    local lines, line = {}, ''
    for word in text:gmatch('%S+') do
        local candidate = line == '' and word or (line .. ' ' .. word)
        label:setText(candidate)
        if line ~= '' and label:getTextSize().width > width then
            lines[#lines + 1] = line
            line = word
        else
            line = candidate
        end
    end
    if line ~= '' then
        lines[#lines + 1] = line
    end
    return table.concat(lines, '\n')
end

local function showPreview(anchor, skill, label, use)
    hidePreview()
    local path = IMAGES .. 'previas/' .. skill
    if not g_resources.fileExists(path .. '.png') then
        return
    end
    preview = g_ui.createWidget('AscensaoPreview', rootWidget)
    preview.title:setText(label)
    preview.movie:setImageSource(path)
    -- how to cast it (the server's Ascensao.spellUse), under the picture,
    -- broken into lines here (wrapLines)
    if (use or '') ~= '' then
        local label = preview.use
        local width = preview:getWidth() - 24
        label:setText(wrapLines(label, 'Como usar: ' .. use, width))
        local height = label:getTextSize().height
        label:setWidth(width)
        label:setHeight(height)
        preview:setHeight(preview:getHeight() + height + 6)
    end
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

-- ---------------------------------------------------------------- the web

-- the web the server sent ("tree"): nodes by id, the links, who is beside
-- whom. It only changes with the server's version of it.
local web
local nodeWidgets, linkWidgets = {}, {}
local chosenId, chosenRing
local view = { zoom = 0.45, panX = 0, panY = 0, fitted = false }

local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.4, 1.6, 1.15
local SIZES = { start = 46, circle = 40, relic = 42, small = 16, notable = 26, keystone = 36 }
local KIND_NAMES = {
    start = 'Centro', circle = 'C\237rculo', relic = 'Rel\237quia',
    small = 'N\243', notable = 'Not\225vel', keystone = 'Pedra angular',
}
local TINTS = {
    owned = '#f0cf8a', open = '#c9b6ff', locked = '#4c4560',
    linkOwned = '#c9a45c', linkOpen = '#6a5aa0', linkLocked = '#2c2638',
}

local function pathState(id)
    for index, path in ipairs(state and state.paths or {}) do
        if path.id == id then
            return path, index
        end
    end
    return nil
end

local ownedNodes = {}

local function owns(node)
    if not state or not node then
        return false
    end
    if node.kind == 'start' then
        return true
    elseif node.kind == 'circle' then
        local path = pathState(node.ref)
        return path ~= nil and (path.owned or 0) >= node.circle
    elseif node.kind == 'relic' then
        return state.relic == node.ref
    end
    return ownedNodes[node.id] == true
end

-- can it be bought now, points aside? the reason when it cannot
local function reachable(node)
    if not state or not web then
        return false, ''
    end
    if node.kind == 'start' then
        return false, ''
    elseif node.kind == 'circle' then
        local path = pathState(node.ref)
        if path and node.circle == (path.owned or 0) + 1 then
            return true
        end
        return false, 'Compre antes o c\237rculo anterior deste caminho.'
    elseif node.kind == 'relic' then
        if state.relic ~= '' then
            return false, 'Outra rel\237quia j\225 foi despertada (um reset libera a escolha).'
        elseif (state.complete or 0) < #(state.paths or {}) then
            return false, 'A rel\237quia desperta com os tr\234s caminhos completos.'
        end
        return true
    end
    for _, beside in ipairs(web.next[node.id] or {}) do
        if owns(web.nodes[beside]) then
            return true
        end
    end
    return false, 'Ainda n\227o est\225 ligado \224 sua teia: compre um vizinho dele.'
end

local function nodeSize(node)
    local scale = math.max(0.7, math.min(1.5, 0.72 + (view.zoom - 0.45) * 0.95))
    return math.floor((SIZES[node.kind] or 16) * scale + 0.5)
end

-- where everything stands: the holder is a square around the web, moved
-- with the mouse; nodes and links sit in it by their own coordinates
local function layout()
    if not window or not web then
        return
    end
    local canvas = window.canvas
    local half = math.floor((web.radius + 70) * view.zoom)
    canvas.holder:setSize({ width = half * 2, height = half * 2 })
    canvas.holder:setMarginLeft(math.floor(canvas:getWidth() / 2 - half + view.panX))
    canvas.holder:setMarginTop(math.floor(canvas:getHeight() / 2 - half + view.panY))
    for id, widget in pairs(nodeWidgets) do
        local node = web.nodes[id]
        local size = nodeSize(node)
        widget:setSize({ width = size, height = size })
        widget:setMarginLeft(math.floor(half + node.x * view.zoom - size / 2))
        widget:setMarginTop(math.floor(half + node.y * view.zoom - size / 2))
        if widget.icon:isVisible() then
            local inner = math.floor(size * (node.kind == 'circle' and 0.72 or 0.8))
            widget.icon:setSize({ width = inner, height = inner })
        end
    end
    for _, entry in ipairs(linkWidgets) do
        local a, b = web.nodes[entry.a], web.nodes[entry.b]
        local dx, dy = (b.x - a.x) * view.zoom, (b.y - a.y) * view.zoom
        local length = math.max(2, math.floor(math.sqrt(dx * dx + dy * dy) + 0.5))
        local thick = entry.thick or 2
        entry.widget:setSize({ width = length, height = thick })
        entry.widget:setMarginLeft(math.floor(half + (a.x + b.x) / 2 * view.zoom - length / 2))
        entry.widget:setMarginTop(math.floor(half + (a.y + b.y) / 2 * view.zoom - thick / 2))
    end
    if chosenRing then
        local node = chosenId and web.nodes[chosenId]
        chosenRing:setVisible(node ~= nil)
        if node then
            local size = nodeSize(node) + 12
            chosenRing:setSize({ width = size, height = size })
            chosenRing:setMarginLeft(math.floor(half + node.x * view.zoom - size / 2))
            chosenRing:setMarginTop(math.floor(half + node.y * view.zoom - size / 2))
        end
    end
end

-- the whole web in the canvas, centred
function centre()
    if not window or not web then
        return
    end
    local canvas = window.canvas
    local side = math.min(canvas:getWidth(), canvas:getHeight())
    if side <= 0 then
        return
    end
    view.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, side / (2 * (web.radius + 40))))
    view.panX, view.panY = 0, 0
    view.fitted = true
    layout()
end

-- the colours of the state: what the character has, what it can reach, the rest
local function paint()
    if not window or not web or not state then
        return
    end
    local slug = vocationArt()
    for id, widget in pairs(nodeWidgets) do
        local node = web.nodes[id]
        local mine = owns(node)
        local open = not mine and reachable(node)
        local tint = mine and TINTS.owned or open and TINTS.open or TINTS.locked
        if node.kind == 'circle' and slug then
            widget:setImageSource(IMAGES .. 'moldura_' .. (mine and 'comprado' or open and 'proximo' or 'bloqueado'))
            widget:setImageColor('#ffffff')
            setLocked(widget.icon, not mine)
        elseif node.kind == 'relic' and slug then
            widget:setImageColor(tint)
            setLocked(widget.icon, not mine)
        else
            widget:setImageColor(tint)
        end
        widget:setOpacity((mine or open) and 1 or 0.85)
    end
    for _, entry in ipairs(linkWidgets) do
        local a, b = owns(web.nodes[entry.a]), owns(web.nodes[entry.b])
        local thick = 2
        if a and b then
            entry.widget:setImageColor(TINTS.linkOwned)
            thick = 3
        elseif a or b then
            entry.widget:setImageColor(TINTS.linkOpen)
        else
            entry.widget:setImageColor(TINTS.linkLocked)
        end
        if entry.thick ~= thick then
            entry.thick = thick
            entry.widget:setHeight(thick)
        end
    end
end

-- the panel on the right: the chosen node, and what the web adds up to
local function describe()
    if not window then
        return
    end
    local side = window.side
    local node = web and chosenId and web.nodes[chosenId]
    local width = side:getWidth() - 20
    side.skill:hide()
    side.skill.onHoverChange = nil
    side.buy:hide()
    side.why:setText('')
    if not node or not state then
        side.kind:setText('')
        side.name:setText('Escolha um n\243 da teia')
        side.text:setText(wrapLines(side.text, 'Clique num n\243 para ver o que ele d\225. Arraste a teia com o mouse e use a roda para aproximar.', width))
        side.text:setHeight(side.text:getTextSize().height)
    else
        local kind = KIND_NAMES[node.kind] or ''
        if node.kind == 'circle' then
            local path = pathState(node.ref)
            kind = string.format('%s  -  c\237rculo %d de 5', path and (path.name .. ' (' .. path.kind .. ')') or '', node.circle)
            if path and node.circle == 1 then
                local skill = SKILL_ICONS[path.words]
                -- its words, or how strong it is once the character has it
                if (path.owned or 0) > 0 then
                    side.skill:setText(string.format('%s  -  for\231a %d%%', path.skillshot, path.power or 0))
                else
                    side.skill:setText(string.format('%s (%s)', path.skillshot, path.words))
                end
                side.skill:show()
                if skill then
                    side.skill.onHoverChange = function(self, hovered)
                        if hovered then
                            showPreview(self, skill, path.skillshot .. '  -  ' .. path.words, path.use)
                        else
                            hidePreview()
                        end
                    end
                end
            end
        end
        side.kind:setText(kind)
        side.name:setText(node.name)
        side.text:setText(wrapLines(side.text, node.text, width))
        side.text:setHeight(side.text:getTextSize().height)
        if node.kind ~= 'start' then
            local can, why = reachable(node)
            local free = state.free or 0
            side.buy:show()
            if owns(node) then
                side.buy:setText('Voc\234 tem')
                side.buy:setEnabled(false)
            else
                side.buy:setText(string.format(node.kind == 'relic' and 'Despertar (%d pts)' or 'Aprender (%d pts)', node.cost))
                side.buy:setEnabled(can and free >= node.cost)
                if not can then
                    side.why:setText(wrapLines(side.why, why or '', width))
                elseif free < node.cost then
                    side.why:setText(string.format('Faltam pontos: voc\234 tem %d.', free))
                end
            end
        end
    end
    side.skill:setHeight(side.skill:isVisible() and 14 or 0)
    side.skill:setMarginTop(side.skill:isVisible() and 6 or 0)
    side.buy:setHeight(side.buy:isVisible() and 26 or 0)
    side.why:setHeight(math.max(0, side.why:getTextSize().height))
    side.totalsTitle:setText('B\244nus da teia')
    side.totals:destroyChildren()
    local lines = state and state.summary or {}
    if #lines == 0 then
        g_ui.createWidget('AscensaoTotal', side.totals):setText('Nenhum n\243 entre os caminhos ainda.')
    end
    for _, line in ipairs(lines) do
        g_ui.createWidget('AscensaoTotal', side.totals):setText(line)
    end
end

local function choose(id)
    chosenId = id
    hidePreview()
    layout()
    describe()
end

-- asks the server for the chosen node (the button on the right)
function buyChosen()
    local node = web and chosenId and web.nodes[chosenId]
    if not node or not state or owns(node) then
        return
    end
    if node.kind == 'circle' then
        send({ action = 'buy', path = node.ref })
    elseif node.kind == 'relic' then
        confirm('Rel\237quia', string.format('Despertar %s? S\243 uma rel\237quia pode ser despertada (um reset libera a escolha).', node.name), function()
            send({ action = 'relic', relic = node.ref })
        end)
    elseif node.kind ~= 'start' then
        send({ action = 'node', node = node.id })
    end
end

-- the widgets of the web, once per web the server sends
local function build(data)
    if not window then
        return
    end
    local holder = window.canvas.holder
    holder:destroyChildren()
    nodeWidgets, linkWidgets, chosenRing = {}, {}, nil
    web = { nodes = {}, order = {}, next = {}, radius = 0, version = data.version }
    for _, raw in ipairs(data.nodes or {}) do
        local node = { id = raw[1], x = raw[2], y = raw[3], kind = raw[4], cost = raw[5], name = raw[6], text = raw[7], ref = raw[8], circle = raw[9] }
        web.nodes[node.id] = node
        web.order[#web.order + 1] = node.id
        web.next[node.id] = {}
        web.radius = math.max(web.radius, math.sqrt(node.x * node.x + node.y * node.y))
    end
    -- links first: the nodes are drawn over them
    for _, pair in ipairs(data.links or {}) do
        local a, b = web.nodes[pair[1]], web.nodes[pair[2]]
        if a and b then
            table.insert(web.next[a.id], b.id)
            table.insert(web.next[b.id], a.id)
            local widget = g_ui.createWidget('AscensaoLink', holder)
            widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            widget:addAnchor(AnchorTop, 'parent', AnchorTop)
            widget:setRotation(math.deg(math.atan2(b.y - a.y, b.x - a.x)))
            linkWidgets[#linkWidgets + 1] = { widget = widget, a = a.id, b = b.id }
        end
    end
    chosenRing = g_ui.createWidget('UIWidget', holder)
    chosenRing:setImageSource(IMAGES .. 'teia/chosen')
    chosenRing:setImageColor('#ffffff')
    chosenRing:setPhantom(true)
    chosenRing:setFocusable(false)
    chosenRing:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    chosenRing:addAnchor(AnchorTop, 'parent', AnchorTop)
    chosenRing:hide()
    local slug = vocationArt()
    for _, id in ipairs(web.order) do
        local node = web.nodes[id]
        local widget = g_ui.createWidget('AscensaoNode', holder)
        widget:setId('node_' .. id)
        widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        widget:addAnchor(AnchorTop, 'parent', AnchorTop)
        if node.kind == 'circle' and slug then
            widget:setImageSource(IMAGES .. 'moldura_bloqueado')
            widget.icon:setImageSource(string.format('%s%s/circulo_%s_%s_%d', IMAGES, slug, slug, node.ref, node.circle))
            widget.icon:show()
        elseif node.kind == 'relic' and slug then
            widget:setImageSource(IMAGES .. 'teia/chosen')
            widget.icon:setImageSource(string.format('%s%s/reliquia_%s_%s', IMAGES, slug, slug, node.ref))
            widget.icon:show()
        elseif node.kind == 'start' then
            widget:setImageSource(IMAGES .. 'teia/core')
        elseif node.kind == 'circle' or node.kind == 'relic' then
            widget:setImageSource(IMAGES .. 'teia/keystone')
        else
            widget:setImageSource(IMAGES .. 'teia/' .. node.kind)
        end
        widget:setTooltip(node.name .. '\n' .. node.text .. (node.cost > 0 and string.format('\n%d pts', node.cost) or ''))
        widget.onClick = function()
            choose(id)
        end
        nodeWidgets[id] = widget
    end
    if chosenId and not web.nodes[chosenId] then
        chosenId = nil
    end
    view.fitted = false
end

local function refresh()
    if not window or not state then
        return
    end
    hidePreview()
    if not state.supported then
        window.titleLabel:setText('Sua voca\231\227o n\227o tem Ascens\227o.')
        window.points:setText('')
        window.resetButton:setEnabled(false)
        return
    end
    ownedNodes = {}
    for _, id in ipairs(state.nodes or {}) do
        ownedNodes[id] = true
    end
    window.titleLabel:setText(state.title ~= '' and state.title or string.format('%s - sem t\237tulo ainda (complete um caminho)', state.vocation))
    local points = string.format('Pontos: %d livres de %d', state.free or 0, state.total or 0)
    if (state.total or 0) == 0 then
        points = string.format('A Ascens\227o come\231a no level %d: 1 ponto a cada %d levels.', state.startLevel or 50, state.levelsPerPoint or 10)
    elseif state.nextLevel then
        points = points .. '  -  ' .. string.format('pr\243ximo no level %d', state.nextLevel)
    end
    window.points:setText(points)
    window.resetButton:setEnabled((state.spent or 0) > 0)
    window.resetButton:setTooltip((state.resetCost or 0) > 0 and string.format('Custa %d gold', state.resetCost) or 'O primeiro reset \233 gr\225tis')
    window.canvas.hint:setText('arraste para mover  -  roda do mouse para aproximar')
    if web then
        if not view.fitted then
            centre()
        end
        paint()
        layout()
    end
    describe()
end

local webAsked = false

-- does the client still need the web (none yet, or another version of it)?
local function needsWeb()
    return web == nil or (state ~= nil and state.treeVersion ~= nil and web.version ~= state.treeVersion)
end

-- ---------------------------------------------------------------- module

function show()
    if not window then
        return
    end
    -- the last state the server sent, until the new one comes
    refresh()
    window:show()
    window:raise()
    window:focus()
    send({ action = 'open', tree = needsWeb() or nil })
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
    if data.action == 'tree' then
        -- the web itself: asked for when the window opens without one
        webAsked = false
        build(data)
        if window and window:isVisible() and state then
            refresh()
        end
    elseif data.action == 'state' then
        state = data
        updateButton()
        if data.open and window then
            window:show()
            window:raise()
            window:focus()
        end
        -- a hidden window is drawn when it shows: a level up sends the state
        -- again, and drawing every path of a closed window was a hitch in
        -- the middle of a hunt
        if window and window:isVisible() then
            refresh()
            -- opened by the server (!ascensao) or the web changed there: ask
            -- for it, a moment later (the server takes a request every 250 ms)
            if needsWeb() and not webAsked then
                webAsked = true
                scheduleEvent(function()
                    if g_game.isOnline() and needsWeb() then
                        send({ action = 'open', tree = true })
                    else
                        webAsked = false
                    end
                end, 350)
            end
        end
    elseif data.action == 'message' and window then
        window.message:setText(data.text or '')
        window.message:setColor(data.ok and '#b6e3a6' or '#f0a0a0')
    elseif data.action == 'status' then
        -- a relic's state: its icon beside hunger and battle (status.lua)
        onStatus(data)
    end
end

local openEvent

local function onGameStart()
    if not panelButton and modules.game_brevespanel then
        panelButton = modules.game_brevespanel.addFeature('ascensao', toggle)
    end
    -- each client at its own moment (g_game.spreadDelay): a login rush
    -- brings hundreds of clients in the same minute
    removeEvent(openEvent)
    openEvent = scheduleEvent(function()
        openEvent = nil
        if g_game.isOnline() and not state then
            send({ action = 'open' })
        end
    end, g_game.spreadDelay and g_game.spreadDelay(4000, 10000) or 0)
end

local function onGameEnd()
    removeEvent(openEvent)
    openEvent = nil
    hide()
    state = nil
    -- another character, another vocation: its own web
    web, chosenId, webAsked = nil, nil, false
    nodeWidgets, linkWidgets, chosenRing = {}, {}, nil
    if window then
        window.canvas.holder:destroyChildren()
    end
    clearStatus()
end

-- the web follows the mouse: dragged to move, the wheel to zoom
local function bindCanvas()
    local canvas = window.canvas
    canvas:setDraggable(true)
    canvas.onDragEnter = function()
        return true
    end
    canvas.onDragMove = function(widget, mousePos, moved)
        view.panX = view.panX + moved.x
        view.panY = view.panY + moved.y
        layout()
        return true
    end
    canvas.onDragLeave = function()
        return true
    end
    canvas.onMouseWheel = function(widget, mousePos, direction)
        local before = view.zoom
        if direction == MouseWheelUp then
            view.zoom = math.min(ZOOM_MAX, view.zoom * ZOOM_STEP)
        else
            view.zoom = math.max(ZOOM_MIN, view.zoom / ZOOM_STEP)
        end
        -- what was in the middle stays in the middle
        view.panX = view.panX * view.zoom / before
        view.panY = view.panY * view.zoom / before
        layout()
        return true
    end
end

function init()
    window = g_ui.displayUI('ascensao')
    window:setText('Ascens\227o')
    window:hide()
    bindCanvas()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    removeEvent(openEvent)
    openEvent = nil
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    clearStatus()
    closeConfirm()
    if window then
        window:destroy()
        window = nil
    end
end
