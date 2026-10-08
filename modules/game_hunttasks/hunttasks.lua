-- Szuszkin hunting tasks: the daily task, the Hunter's Trail and the Hunt
-- Points shop. Everything the NPC does can be done from here.
-- Talks to data-otservbr-global/scripts/hunt_tasks/03_window.lua through
-- extended opcode TASK_OPCODE with JSON payloads.

local TASK_OPCODE = 122

local window
local toolbarButton
local tickEvent
local messageEvent

local currentTab = 'tasks'
local state -- last "state" from the server
local timeOffset = 0 -- server time - local time
local trailBuilt = false

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

local function formatNumber(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    while true do
        local replaced, count = text:gsub('^(-?%d+)(%d%d%d)', '%1.%2')
        text = replaced
        if count == 0 then
            return text
        end
    end
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format('%02d:%02d:%02d', math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(TASK_OPCODE, data)
    end
end

-- server outfit array: { type, head, body, legs, feet, addons, typeEx }
local function outfitOf(raw)
    raw = raw or {}
    return {
        type = raw[1] or 0,
        head = raw[2] or 0,
        body = raw[3] or 0,
        legs = raw[4] or 0,
        feet = raw[5] or 0,
        addons = raw[6] or 0,
        auxType = raw[7] or 0,
        mount = 0,
    }
end

local function setBar(bar, value, total, color)
    total = math.max(1, total or 1)
    value = math.max(0, math.min(value or 0, total))
    local inner = bar:getWidth() - 2
    bar.fill:setWidth(math.max(1, math.floor(inner * value / total)))
    bar.fill:setBackgroundColor(color or '#4f9e36')
    bar.value:setText(string.format('%s / %s', formatNumber(value), formatNumber(total)))
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

-- ---------------------------------------------------------------- tasks tab

-- "Level recomendado: 120" plus the teleport rooms that lead to the hunt
local function levelAndRooms(level, rooms)
    local text = tr('Level recomendado: %d', level or 0)
    if type(rooms) == 'table' and #rooms > 0 then
        local names = rooms[1]
        if #rooms > 1 then
            names = table.concat(rooms, ', ', 1, #rooms - 1) .. tr(' ou ') .. rooms[#rooms]
        end
        text = text .. '\n' .. tr('Teleporte: %s', names)
    end
    return text
end

local function renderDaily()
    local card = window.tasksPanel.dailyCard
    local daily = state.daily
    card.title:setText(tr('Task diária'))
    card.action2:setVisible(false)
    card.action:setEnabled(true)

    if not daily then
        card.creature:setVisible(false)
        card.name:setText(tr('Nenhuma task hoje ainda'))
        card.info:setText(tr('Um monstro do seu level com hunt na sala de teleporte de uma cidade.'))
        card.badge:setText('')
        card.bar:setVisible(false)
        card.reward:setText(tr('Recompensa: +%s de experiência e %d+ Hunt Points.', formatNumber(state.dailyExp), state.dailyBase or 20))
        card.extra:setText(tr('A primeira troca do dia é grátis.'))
        card.action:setText(tr('Pegar task de hoje'))
        card.action.onClick = function()
            send({ action = 'take' })
        end
        return
    end

    card.creature:setVisible(true)
    card.creature:setOutfit(outfitOf(daily.outfit))
    card.name:setText(daily.monster)
    card.info:setText(levelAndRooms(daily.level, daily.rooms))
    card.badge:setText(daily.hot and tr('Em alta no Hunt Board: pontos dobrados!') or '')
    card.bar:setVisible(true)

    if daily.done then
        setBar(card.bar, daily.need, daily.need, '#c9a227')
        card.bar.value:setText(tr('Completa!'))
        card.reward:setText(tr('Você já completou a task de hoje.'))
        card.extra:setText('')
        card.action:setText(tr('Volte amanhã'))
        card.action:setEnabled(false)
        card.action.onClick = nil
        return
    end

    setBar(card.bar, daily.kills, daily.need)
    card.reward:setText(tr('Recompensa: +%s de experiência e +%d Hunt Points.', formatNumber(state.dailyExp), daily.points or 0))
    card.extra:setText(tr('Mate %d %s. Conta para todos que ajudarem na kill e para a party.', daily.need, daily.monster))
    local cost = state.rerollCost or 0
    card.action:setText(cost > 0 and tr('Trocar (%s gold)', formatNumber(cost)) or tr('Trocar monstro (grátis)'))
    card.action.onClick = function()
        if cost > 0 then
            local box
            local function close()
                if box then
                    box:destroy()
                    box = nil
                end
            end
            box = displayGeneralBox(tr('Trocar task'), tr('Trocar o monstro custa %s gold (banco ou mochila). Continuar?', formatNumber(cost)), {
                { text = tr('Sim'), callback = function()
                    close()
                    send({ action = 'reroll' })
                end },
                { text = tr('Não'), callback = close },
            }, close, close)
            return
        end
        send({ action = 'reroll' })
    end
end

local function renderTrailCard()
    local card = window.tasksPanel.trailCard
    local trail = state.trail
    local steps = trail.steps or {}
    card.action2:setVisible(false)
    card.title:setText(tr('Trilha do Caçador'))
    if trail.finished then
        card.creature:setVisible(false)
        card.name:setText(tr('Trilha completa!'))
        card.info:setText(tr('Você venceu os %d monstros da trilha.', #steps))
        card.badge:setText('')
        card.bar:setVisible(true)
        setBar(card.bar, #steps, #steps, '#c9a227')
        card.reward:setText(tr('Respeito, caçador.'))
        card.extra:setText('')
    else
        local step = steps[trail.index] or {}
        card.title:setText(tr('Trilha do Caçador, etapa %d de %d', trail.index, #steps))
        card.creature:setVisible(true)
        card.creature:setOutfit(outfitOf(step.outfit))
        card.name:setText(step.name or '?')
        card.info:setText(levelAndRooms(step.level, step.rooms))
        card.bar:setVisible(true)
        setBar(card.bar, trail.kills, step.need, '#3d7fd6')
        local points = step.points or 0
        if step.milestone then
            card.badge:setText(tr('Etapa de marco: +%d pontos de bônus!', trail.milestonePoints or 0))
        else
            local every = math.max(1, trail.milestoneEvery or 5)
            local nextMilestone = math.ceil(trail.index / every) * every
            card.badge:setText(tr('Próximo marco: etapa %d', nextMilestone))
            card.badge:setColor('#8a8a8a')
        end
        if step.milestone then
            card.badge:setColor('#ffb020')
        end
        card.reward:setText(tr('Recompensa: +%s de experiência e +%d Hunt Points.', formatNumber(trail.exp), points))
        local following = steps[trail.index + 1]
        card.extra:setText(following and tr('Depois: %s (level %d).', following.name, following.level) or tr('Última etapa!'))
    end
    card.action:setText(tr('Ver trilha completa'))
    card.action:setEnabled(true)
    card.action.onClick = function()
        selectTab('trail')
    end
end

local function renderStreak()
    local panel = window.tasksPanel
    local streak = state.streak or 0
    local max = state.streakMax or 6
    local bonus = state.streakBonus or 5
    panel.streakTitle:setText(tr('Sequência diária: %d dia%s. Cada dia seguido dá +%d pontos na task diária (até +%d)', streak, streak == 1 and '' or 's',
        bonus, bonus * max))
    panel.streakDots:destroyChildren()
    for day = 1, max + 1 do
        local dot = g_ui.createWidget('StreakDot', panel.streakDots)
        dot:setText(string.format('+%d', (day - 1) * bonus))
        dot:setTooltip(tr('Dia %d seguido: +%d pontos', day, (day - 1) * bonus))
        if day <= streak then
            dot:setBackgroundColor('#c9a22790')
            dot:setBorderColor('#ffe066')
            dot:setColor('#ffffff')
        end
    end
    panel.help:setText(tr(
        'Task diária: um monstro do seu level por dia. Se ele estiver com XP x2.0 ou mais no Hunt Board, os pontos dobram.\n' ..
        'Trilha do Caçador: %d monstros em ordem, do mais fraco ao mais forte. A cada %d etapas tem um bônus.\n' ..
        'Os Hunt Points compram poção de XP, exercise weapon, pergaminhos de raridade e ascensão, Bag of Mythical, Bag You Desire, Rarity XP, Mythicum Coins, Loot Pouch e montarias na aba Loja.',
        #(state.trail.steps or {}), state.trail.milestoneEvery or 5))
end

-- ---------------------------------------------------------------- trail tab

local function renderTrailList()
    local panel = window.trailPanel
    local trail = state.trail
    local steps = trail.steps or {}
    local done = trail.finished and #steps or trail.index - 1
    panel.summary:setText(tr('%d de %d etapas completas. Cada etapa: +%s de experiência e pontos que crescem com as kills; a cada %d etapas, +%d de bônus. A trilha inteira vale %s pontos.', done, #steps,
        formatNumber(trail.exp), trail.milestoneEvery or 5, trail.milestonePoints or 0, formatNumber(trail.totalPoints or 0)))

    if not trailBuilt then
        panel.list:destroyChildren()
        for i, step in ipairs(steps) do
            local row = g_ui.createWidget('TrailRow', panel.list)
            row:setId('step' .. i)
            row.index:setText(tostring(i))
            row.creature:setOutfit(outfitOf(step.outfit))
            row.name:setText(step.milestone and (step.name .. '  (marco)') or step.name)
            row.info:setText(tr('Level %d, mate %s, %s exp cada, +%d pontos', step.level, formatNumber(step.need), formatNumber(step.experience), step.points or 0))
        end
        trailBuilt = true
    end

    for i in ipairs(steps) do
        local row = panel.list:getChildById('step' .. i)
        if row then
            if i <= done then
                row.status:setText(tr('Completa'))
                row.status:setColor('#7fd35a')
                row.name:setColor('#7fd35a')
                row:setBackgroundColor('#7fd35a14')
            elseif i == trail.index then
                row.status:setText(tr('Em andamento: %d / %d', trail.kills or 0, steps[i].need))
                row.status:setColor('#ffe066')
                row.name:setColor('#ffe066')
                row:setBackgroundColor('#c9a22730')
            else
                row.status:setText(tr('Bloqueada'))
                row.status:setColor('#8a8a8a')
                row.name:setColor('#c8c8c8')
                row:setBackgroundColor(i % 2 == 0 and '#ffffff12' or '#00000012')
            end
        end
    end
end

local function scrollToCurrent()
    if not window or not state then
        return
    end
    local panel = window.trailPanel
    local row = panel.list:getChildById('step' .. (state.trail.index or 1))
    if row then
        panel.list:ensureChildVisible(row)
    end
end

-- ---------------------------------------------------------------- shop tab

-- name, amount and description of each offer of the server's shop (by key);
-- the server's own label is the fallback. Shown through tr(), like every
-- text of this window ("%" written "%%")
local OFFER_INFO = {
    pocao = { name = 'Poção de XP', lines = { '+50%% de experiência por 1 hora.', 'Vai para a Store Inbox.' } },
    arma = { name = 'Arma do Aprendiz', lines = { 'Uma arma aleatória de level baixo, até 28 de ataque.', 'Já vem Communis ou Rarus.', 'Escolha o tipo da arma na lista acima.' } },
    equipamento = { name = 'Equipamento do Aprendiz', lines = { 'Capacete, armadura, calça, bota ou escudo aleatório de level baixo.', 'Já vem Communis ou Rarus.' } },
    exercise = { name = 'Lasting Exercise Weapon', count = '14400x', lines = { '14.400 cargas de treino.', 'Escolha o tipo na lista acima.', 'Vai para a Store Inbox.' } },
    pergaminho = { name = 'Pergaminho de Raridade', lines = { 'Use em uma arma ou armadura para sortear uma raridade nova.', 'Chances: Communis 40%%, Rarus 32%%, Praeclarus 18%%, Legendarius 8%%, Mythicus 2%%.' } },
    ascensao = { name = 'Pergaminho de Ascensão', lines = { 'Use em um item com raridade: ele sobe um grau e ganha um bônus novo.', 'Os bônus que o item já tem ficam iguais.' } },
    mitica = { name = 'Bag of Mythical', lines = { 'Abre um item aleatório que já vem Mythicus, o grau mais alto.' } },
    desire = { name = 'Bag You Desire', lines = { 'Abre um item da Soul War: arma, armadura, calça, bota ou o Soulbastion.' } },
    coins = { name = '25 Mythicum Coins', count = '25x', lines = { 'Coins para gastar na Store.' } },
    pouch = { name = 'Loot Pouch', lines = { 'Vai para a Store Inbox.' } },
    rarityxp = { name = '500 Rarity XP', count = '500x', lines = { 'Para refazer os bônus dos itens raros que você usa, na janela Rarity Bonuses.', 'Reroll: um valor novo para um bônus. Trocar: outro bônus aleatório.', 'Também se ganha matando monstros Pale, Ashen, Obsidian e Lord of Death.' } },
    montaria = { name = 'Montaria', lines = { 'Qualquer montaria que você ainda não tem.', 'Escolha na lista acima; a montaria já sai liberada.' } },
}

local selectedOffer

-- mount picture when the player has every mount (nothing left to preview)
local FALLBACK_MOUNT_LOOK = 370

local function setOfferImage(box, offer, mountLook)
    if offer.key == 'montaria' and not (mountLook and mountLook > 0) then
        mountLook = FALLBACK_MOUNT_LOOK
    end
    box.item:setVisible(false)
    box.icon:setVisible(false)
    box.creature:setVisible(false)
    if offer.key == 'montaria' and mountLook and mountLook > 0 then
        box.creature:setVisible(true)
        box.creature:setOutfit({ type = mountLook })
    elseif offer.key == 'coins' then
        box.icon:setVisible(true)
        box.icon:setImageSource('/images/store/icon-tibiacoin')
    elseif offer.item and offer.item > 0 then
        box.item:setVisible(true)
        box.item:setItemId(offer.item)
    end
end

local function showOfferDetails(offer)
    selectedOffer = offer
    local details = window.shopPanel.details
    local info = OFFER_INFO[offer.key] or {}
    details.name:setText(info.name and tr(info.name) or offer.label)
    details.price:setText(formatNumber(offer.price))
    local affordable = (state.points or 0) >= offer.price
    details.price:setColor(affordable and '#dfdfdf' or '#ff7a6b')
    details.buy:setEnabled(affordable)
    setOfferImage(details.image, offer)

    details.descBox:destroyChildren()
    for _, line in ipairs(info.lines or { offer.label }) do
        local label = g_ui.createWidget('ShopDescLine', details.descBox)
        label:setText(info.lines and tr(line) or line)
    end
    if not affordable then
        local label = g_ui.createWidget('ShopDescLine', details.descBox)
        label:setColor('#ff7a6b')
        label:setText(tr('Faltam %s Hunt Points.', formatNumber(offer.price - (state.points or 0))))
    end

    -- a list to choose from: mounts, or the kind of weapon
    local combo = details.options
    combo.onOptionChange = nil
    combo:clearOptions()
    combo:setVisible(false)
    if offer.key == 'montaria' then
        local mounts = state.mounts or {}
        for _, mount in ipairs(mounts) do
            combo:addOption(mount[1], mount)
        end
        combo.onOptionChange = function()
            local option = combo:getCurrentOption()
            if option and option.data then
                setOfferImage(details.image, offer, option.data[2])
            end
        end
        if #mounts > 0 then
            combo:setVisible(true)
            combo:setCurrentIndex(1, true)
            combo.onOptionChange()
        else
            details.buy:setEnabled(false)
            local label = g_ui.createWidget('ShopDescLine', details.descBox)
            label:setText(tr('Você já tem todas as montarias!'))
        end
    elseif offer.options and #offer.options > 0 then
        for _, option in ipairs(offer.options) do
            combo:addOption(option[2], option)
        end
        combo.onOptionChange = function()
            local option = combo:getCurrentOption()
            if option and option.data and option.data[3] then
                details.image.item:setItemId(option.data[3])
            end
        end
        combo:setVisible(true)
        combo:setCurrentIndex(1, true)
    end

    details.buy.onClick = function()
        local option = combo:isVisible() and combo:getCurrentOption()
        if offer.key == 'montaria' then
            if option and option.data then
                send({ action = 'buy', key = offer.key, mount = option.data[1] })
            end
        elseif option and option.data then
            send({ action = 'buy', key = offer.key, option = option.data[1] })
        else
            send({ action = 'buy', key = offer.key })
        end
    end
end

local function renderShop()
    local panel = window.shopPanel
    panel.summary:setText(tr('Você tem %s Hunt Points.', formatNumber(state.points)))
    local keepKey = selectedOffer and selectedOffer.key
    panel.listBox.list:destroyChildren()
    -- after a purchase the same offer stays chosen
    local focusRow, focusOffer
    for _, offer in ipairs(state.shop or {}) do
        local info = OFFER_INFO[offer.key] or {}
        local row = g_ui.createWidget('ShopOffer', panel.listBox.list)
        row.name:setText(info.name and tr(info.name) or offer.label)
        row.count:setText(info.count or '1x')
        row.price:setText(formatNumber(offer.price))
        row.price:setColor((state.points or 0) >= offer.price and '#dfdfdf' or '#ff7a6b')
        setOfferImage(row.image, offer, offer.key == 'montaria' and state.mounts and state.mounts[1] and state.mounts[1][2])
        row.onFocusChange = function(widget, focused)
            if focused then
                showOfferDetails(offer)
            end
        end
        if not focusRow or offer.key == keepKey then
            focusRow, focusOffer = row, offer
        end
    end
    if focusRow then
        panel.listBox.list:focusChild(focusRow, KeyboardFocusReason)
        showOfferDetails(focusOffer)
    end
end

-- ---------------------------------------------------------------- render

local function render()
    if not window or not state then
        return
    end
    window.points:setText(tr('Hunt Points: %s', formatNumber(state.points)))
    renderDaily()
    renderTrailCard()
    renderStreak()
    renderTrailList()
    if currentTab == 'shop' then
        renderShop()
    end
end

local function tick()
    tickEvent = nil
    if not window or not window:isVisible() then
        return
    end
    if state and state.resetAt then
        local left = state.resetAt - (os.time() + timeOffset)
        window.tasksPanel.dailyCard.title:setText(tr('Task diária, nova em %s', formatDuration(left)))
        if left < -3 and left > -15 then
            state.resetAt = nil
            send({ action = 'open' })
        end
    end
    tickEvent = scheduleEvent(tick, 1000)
end

local function startTick()
    if tickEvent then
        removeEvent(tickEvent)
    end
    tickEvent = scheduleEvent(tick, 10)
end

-- ---------------------------------------------------------------- server messages

local handlers = {}

function handlers.state(data)
    timeOffset = (data.now or os.time()) - os.time()
    state = data
    render()
end

function handlers.progress(data)
    if not state then
        return
    end
    if data.daily and state.daily then
        state.daily.kills = data.daily.kills
        state.daily.need = data.daily.need
    end
    if data.trail then
        state.trail.index = data.trail.index or state.trail.index
        state.trail.kills = data.trail.kills or state.trail.kills
    end
    if window and window:isVisible() then
        renderDaily()
        renderTrailCard()
        renderTrailList()
    end
end

function handlers.message(data)
    showMessage(data.text, data.ok)
end

local function onTaskOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    local handler = handlers[data.action]
    if handler then
        handler(convertStrings(data))
    end
end

-- ---------------------------------------------------------------- public (otui)

function selectTab(tab)
    currentTab = tab
    window.tasksTab:setChecked(tab == 'tasks')
    window.trailTab:setChecked(tab == 'trail')
    window.shopTab:setChecked(tab == 'shop')
    window.tasksPanel:setVisible(tab == 'tasks')
    window.trailPanel:setVisible(tab == 'trail')
    window.shopPanel:setVisible(tab == 'shop')
    if state then
        if tab == 'shop' then
            renderShop()
        elseif tab == 'trail' then
            scheduleEvent(scrollToCurrent, 50)
        end
    end
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
    startTick()
end

function hide()
    if not window then
        return
    end
    window:hide()
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
    selectTab(currentTab)
    send({ action = 'open' })
end

-- ---------------------------------------------------------------- lifecycle

local function onGameStart()
    if not toolbarButton and modules.game_brevespanel then
        toolbarButton = modules.game_brevespanel.addFeature('tasks', toggle)
    end
    if not toolbarButton and modules.game_mainpanel then
        toolbarButton = modules.game_mainpanel.addToggleButton('huntTasksButton', tr('Tasks do Caçador (task diária, trilha e loja)'),
            '/game_hunttasks/images/button', toggle, false, 22)
    end
end

local function onGameEnd()
    hide()
    state = nil
    trailBuilt = false
    if window then
        window.trailPanel.list:destroyChildren()
    end
end

function init()
    window = g_ui.displayUI('hunttasks')
    window:hide()
    window:setText(tr('Tasks do Caçador'))
    window.footer:setText(tr('Mate os monstros das tasks e ganhe experiência e Hunt Points. Também dá para falar com o Szuszkin.'))

    ProtocolGame.registerExtendedJSONOpcode(TASK_OPCODE, onTaskOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedJSONOpcode(TASK_OPCODE)
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    if messageEvent then
        removeEvent(messageEvent)
        messageEvent = nil
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
