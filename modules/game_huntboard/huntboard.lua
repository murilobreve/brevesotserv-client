-- Hunt Board: per-monster experience/loot rates that re-roll every few hours,
-- the hourly/daily/monthly hunting leaderboard and the online coin reward.
-- Talks to the server scripts in data-otservbr-global/scripts/huntboard
-- through extended opcode HUNT_OPCODE with JSON payloads.

local HUNT_OPCODE = 121
local PAGE_SIZE = 40

local FILTERS = {
    { key = 'all', label = 'All monsters' },
    { key = 'xp', label = 'Boosted XP (1.5x+)' },
    { key = 'loot', label = 'Boosted loot (1.5x+)' },
    { key = 'both', label = 'Double boost (2x+ both)' },
    { key = 'jackpot', label = 'Jackpot (3.5x+)' },
    { key = 'nerfed', label = 'Below normal (<1x)' },
}

local SORTS = {
    { key = 'combined', label = 'Best combined rate' },
    { key = 'xp', label = 'Highest XP rate' },
    { key = 'loot', label = 'Highest loot rate' },
    { key = 'perKill', label = 'Most XP per kill' },
    { key = 'spawns', label = 'Most spawns' },
    { key = 'exp', label = 'Base experience' },
    { key = 'name', label = 'Name' },
}

local PERIOD_LABELS = { hour = 'Hourly', day = 'Daily', month = 'Monthly' }
local MEDALS = {
    { text = '#ffe066' },
    { text = '#f0f0f0' },
    { text = '#ffc08a' },
}

local window
local toolbarButton -- old single button, when game_brevespanel is missing
local sectionButtons = {} -- rates / board rows in the Baiak Mythicum panel
local toast
local toastEvent
local tickEvent

local currentTab = 'rates'
local currentPeriod = 'hour'
local rates = { monsters = {}, nextAt = 0, interval = 7200, max = 100, lootMax = 40, slot = -1 }
local filtered = {}
local page = 1
local boards = {}
local timeOffset = 0 -- server time - local time
local online = { minutes = 0, goal = 60, amount = 1 }
local filterEvent

-- ---------------------------------------------------------------- helpers

local function formatNumber(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    while true do
        local replaced, count = text:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
        text = replaced
        if count == 0 then
            return text
        end
    end
end

local function formatShort(value)
    value = tonumber(value) or 0
    if value >= 1000000000 then
        return string.format('%.2fB', value / 1000000000)
    elseif value >= 1000000 then
        return string.format('%.2fM', value / 1000000)
    elseif value >= 100000 then
        return string.format('%.1fk', value / 1000)
    end
    return formatNumber(value)
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    local secs = seconds % 60
    if days > 0 then
        return string.format('%dd %02dh %02dm', days, hours, minutes)
    end
    return string.format('%02d:%02d:%02d', hours, minutes, secs)
end

local function serverNow()
    return os.time() + timeOffset
end

-- tenths -> colour
local function multColor(tenths)
    if tenths < 10 then
        return '#e0564a'
    elseif tenths < 15 then
        return '#c8c8c8'
    elseif tenths < 30 then
        return '#7fd35a'
    elseif tenths < 60 then
        return '#3d9bff'
    end
    return '#ffb020'
end

-- loot follows the XP rate (0.8x to 4x), so its colours step sooner
local function lootColor(tenths)
    if tenths < 10 then
        return '#e0564a'
    elseif tenths < 15 then
        return '#c8c8c8'
    elseif tenths < 25 then
        return '#7fd35a'
    end
    return '#ffb020'
end

local function multText(tenths)
    return string.format('x%.1f', tenths / 10)
end

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(HUNT_OPCODE, data)
    end
end

local function outfitOf(monster)
    return {
        type = monster.type,
        auxType = monster.typeEx,
        head = monster.head,
        body = monster.body,
        legs = monster.legs,
        feet = monster.feet,
        addons = monster.addons,
        mount = 0,
    }
end

local function setBar(bar, tenths, maxTenths, colorOf)
    maxTenths = math.max(maxTenths or rates.max or 100, 10)
    local inner = bar:getWidth() - 2
    local color = (colorOf or multColor)(tenths)
    bar.fill:setWidth(math.max(1, math.floor(inner * math.min(tenths, maxTenths) / maxTenths)))
    bar.fill:setBackgroundColor(color .. 'b0')
    bar.mark:setMarginLeft(1 + math.floor(inner * 10 / maxTenths))
    bar.value:setText(multText(tenths))
end

-- ---------------------------------------------------------------- rates tab

local function matchesFilter(monster, filter, search, hideBosses)
    if hideBosses and monster.boss == 1 then
        return false
    end
    if search ~= '' and not monster.lname:find(search, 1, true) then
        return false
    end
    if filter == 'xp' then
        return monster.xp >= 15
    elseif filter == 'loot' then
        return monster.loot >= 15
    elseif filter == 'both' then
        return monster.xp >= 20 and monster.loot >= 20
    elseif filter == 'jackpot' then
        return monster.xp >= 35 or monster.loot >= 35
    elseif filter == 'nerfed' then
        return monster.xp < 10 or monster.loot < 10
    end
    return true
end

local SORTERS = {
    combined = function(a, b)
        if a.xp + a.loot ~= b.xp + b.loot then
            return a.xp + a.loot > b.xp + b.loot
        end
        return a.perKill > b.perKill
    end,
    xp = function(a, b)
        if a.xp ~= b.xp then
            return a.xp > b.xp
        end
        return a.perKill > b.perKill
    end,
    loot = function(a, b)
        if a.loot ~= b.loot then
            return a.loot > b.loot
        end
        return a.exp > b.exp
    end,
    perKill = function(a, b)
        if a.perKill ~= b.perKill then
            return a.perKill > b.perKill
        end
        return a.lname < b.lname
    end,
    spawns = function(a, b)
        if a.spawns ~= b.spawns then
            return a.spawns > b.spawns
        end
        return a.lname < b.lname
    end,
    exp = function(a, b)
        if a.exp ~= b.exp then
            return a.exp > b.exp
        end
        return a.lname < b.lname
    end,
    name = function(a, b)
        return a.lname < b.lname
    end,
}

local function renderPage()
    if not window then
        return
    end
    local panel = window.ratesPanel
    local list = panel.rateList
    list:destroyChildren()

    local pages = math.max(1, math.ceil(#filtered / PAGE_SIZE))
    page = math.max(1, math.min(page, pages))
    local first = (page - 1) * PAGE_SIZE + 1
    local last = math.min(#filtered, page * PAGE_SIZE)
    for i = first, last do
        local monster = filtered[i]
        local row = g_ui.createWidget(i % 2 == 0 and 'RateRowEven' or 'RateRow', list)
        row.rank:setText('#' .. i)
        if i <= 3 and panel.sortBox:getCurrentOption().data ~= 'name' then
            row.rank:setColor(MEDALS[i].text)
        end
        row.creature:setOutfit(outfitOf(monster))
        row.name:setText(monster.boss == 1 and (monster.name .. '  [boss]') or monster.name)
        if monster.xp >= 60 or monster.loot >= 18 then
            row.name:setColor('#ffb020')
        elseif monster.boss == 1 then
            row.name:setColor('#e07bff')
        end
        if monster.dmgMult > 1 then
            row.info:setText(tr('Exp %s  -  HP %s  -  damage x%.1f  -  %d spawns', formatNumber(monster.exp),
                formatNumber(math.floor(monster.hp * monster.hpMult)), monster.dmgMult, monster.spawns))
        else
            row.info:setText(tr('Exp %s  -  HP %s  -  %d spawns', formatNumber(monster.exp), formatNumber(monster.hp), monster.spawns))
        end
        setBar(row.xpBar, monster.xp)
        setBar(row.lootBar, monster.loot, rates.lootMax, lootColor)
        row.perKill:setText(formatShort(monster.perKill) .. ' xp')
        row.perKill:setColor(multColor(monster.xp))
        local tooltip = tr('%s\nExperience: %s x %.1f = %s per kill (before your own bonuses)\nLoot: %.1fx the normal drop chances', monster.name,
            formatNumber(monster.exp), monster.xp / 10, formatNumber(monster.perKill), monster.loot / 10)
        if monster.dmgMult > 1 then
            tooltip = tooltip .. '\n' .. tr('Tougher while this rate lasts: health x%.2f, damage x%.2f', monster.hpMult, monster.dmgMult)
        end
        row:setTooltip(tooltip)
    end

    panel.rateEmpty:setVisible(#filtered == 0)
    panel.rateEmpty:setText(#rates.monsters == 0 and tr('Loading monster rates...') or tr('No monster matches your filters.'))
    panel.pageLabel:setText(tr('Page %d of %d  (%d of %d monsters)', page, pages, #filtered, #rates.monsters))
    panel.prevPage:setEnabled(page > 1)
    panel.nextPage:setEnabled(page < pages)
    panel.rateScroll:setValue(0)
end

local function applyFilters()
    if not window then
        return
    end
    local panel = window.ratesPanel
    local search = panel.searchEdit:getText():lower():trim()
    local filterOption = panel.filterBox:getCurrentOption()
    local sortOption = panel.sortBox:getCurrentOption()
    local filter = filterOption and filterOption.data or 'all'
    local sortKey = sortOption and sortOption.data or 'combined'
    local hideBosses = panel.bossBox:isChecked()

    filtered = {}
    for _, monster in ipairs(rates.monsters) do
        if matchesFilter(monster, filter, search, hideBosses) then
            filtered[#filtered + 1] = monster
        end
    end
    table.sort(filtered, SORTERS[sortKey] or SORTERS.combined)
    page = 1
    renderPage()
end

local function renderHot()
    if not window then
        return
    end
    local hotPanel = window.ratesPanel.hotSection.hotPanel
    hotPanel:destroyChildren()
    local list = {}
    for _, monster in ipairs(rates.monsters) do
        if monster.boss ~= 1 and monster.exp > 0 then
            list[#list + 1] = monster
        end
    end
    table.sort(list, SORTERS.combined)
    for i = 1, math.min(4, #list) do
        local monster = list[i]
        local card = g_ui.createWidget('HotCard', hotPanel)
        card:setWidth(math.max(170, math.floor((hotPanel:getWidth() - 18) / 4)))
        card.medal:setText('#' .. i)
        card.medal:setColor((MEDALS[i] or MEDALS[3]).text)
        card.creature:setOutfit(outfitOf(monster))
        card.name:setText(monster.name)
        card.xp:setText(tr('XP %s', multText(monster.xp)))
        card.xp:setColor(multColor(monster.xp))
        card.loot:setText(tr('Loot %s', multText(monster.loot)))
        card.loot:setColor(lootColor(monster.loot))
        card.onClick = function()
            window.ratesPanel.searchEdit:setText(monster.name)
        end
        card:setTooltip(tr('Click to find %s in the list', monster.name))
    end
end

-- ---------------------------------------------------------------- leaderboard tab

local function valueText(category, value)
    if category == 'kills' then
        return tr('%s kills', formatNumber(value))
    end
    return tr('%s xp', formatShort(value))
end

local function fillColumn(column, category, entries, mine)
    column.list:destroyChildren()
    for i, entry in ipairs(entries or {}) do
        local row = g_ui.createWidget(i % 2 == 0 and 'BoardRowEven' or 'BoardRow', column.list)
        row.position:setText(tostring(i))
        local medal = MEDALS[i]
        if medal then
            row.position:setColor(medal.text)
        end
        row.name:setText(entry.name)
        row.info:setText(tr('Level %d %s', entry.level or 0, entry.vocation or ''))
        row.value:setText(valueText(category, entry.value))
        if entry.me then
            row:setBackgroundColor('#7fd35a22')
            row.name:setColor('#7fd35a')
        end
    end
    column.empty:setVisible(#(entries or {}) == 0)
    if mine and (mine[category] or 0) > 0 then
        column.mine:setText(tr('You: #%d with %s', mine[category .. 'Rank'] or 0, valueText(category, mine[category])))
        column.mine:setColor('#7fd35a')
    else
        column.mine:setText(tr('You have not scored in this period yet.'))
        column.mine:setColor('#7a7a7a')
    end
end

local function renderBoard()
    if not window then
        return
    end
    local panel = window.boardPanel
    panel.hourTab:setChecked(currentPeriod == 'hour')
    panel.dayTab:setChecked(currentPeriod == 'day')
    panel.monthTab:setChecked(currentPeriod == 'month')

    local board = boards[currentPeriod]
    local rewards = board and board.rewards or {}
    local prizeParts = {}
    for position, coins in ipairs(rewards) do
        prizeParts[#prizeParts + 1] = string.format('#%d: %s', position, formatNumber(coins))
    end
    panel.prize:setText(#prizeParts > 0 and tr('Prize per category  %s Mythicum Coins', table.concat(prizeParts, '  ')) or '')

    panel.killsColumn:setText(tr('Most Monsters Killed - %s', tr(PERIOD_LABELS[currentPeriod])))
    panel.expColumn:setText(tr('Most Experience - %s', tr(PERIOD_LABELS[currentPeriod])))
    if not board then
        fillColumn(panel.killsColumn, 'kills', {}, nil)
        fillColumn(panel.expColumn, 'experience', {}, nil)
        return
    end
    fillColumn(panel.killsColumn, 'kills', board.kills, board.me)
    fillColumn(panel.expColumn, 'experience', board.experience, board.me)

    panel.history:destroyChildren()
    for _, entry in ipairs(board.recent or {}) do
        local line = g_ui.createWidget('HistoryLine', panel.history)
        line:setText(tr('%s, %s: %s was #%d in %s with %s and won %s Mythicum Coins', tr(PERIOD_LABELS[entry.period] or ''), entry.when or '',
            entry.name or '?', entry.position or 1, entry.category == 'kills' and tr('kills') or tr('experience'),
            valueText(entry.category, entry.value), formatNumber(entry.coins)))
        if entry.period == 'month' then
            line:setColor('#ffb020')
        elseif entry.period == 'day' then
            line:setColor('#3d9bff')
        end
    end
    if #(board.recent or {}) == 0 then
        local line = g_ui.createWidget('HistoryLine', panel.history)
        line:setText(tr('No period has closed yet.'))
        line:setColor('#7a7a7a')
    end
end

-- ---------------------------------------------------------------- timers

local function updateOnline()
    if not window then
        return
    end
    local bar = window.onlineBar
    local goal = math.max(1, online.goal)
    local minutes = math.min(online.minutes, goal)
    bar.fill:setWidth(math.max(1, math.floor((bar:getWidth() - 2) * minutes / goal)))
    bar.value:setText(tr('%d / %d min', minutes, goal))
    bar:setTooltip(tr('You get %d Mythicum Coin(s) for every %d minutes online.', online.amount, goal))
end

local function tick()
    tickEvent = nil
    if not window or not window:isVisible() then
        return
    end
    local now = serverNow()
    if rates.nextAt > 0 then
        local left = rates.nextAt - now
        if left <= 0 then
            window.ratesPanel.countdown:setText(tr('Rolling new rates...'))
            if left < -5 and left > -20 and currentTab == 'rates' then
                rates.nextAt = 0
                send({ action = 'rates' })
            end
        else
            window.ratesPanel.countdown:setText(tr('New rates in %s', formatDuration(left)))
        end
    end
    local board = boards[currentPeriod]
    if board and board.endsAt then
        local left = board.endsAt - now
        window.boardPanel.ends:setText(left > 0 and tr('%s leaderboard ends in %s', tr(PERIOD_LABELS[currentPeriod]), formatDuration(left)) or tr('Paying the winners...'))
    end
    tickEvent = scheduleEvent(tick, 1000)
end

local function startTick()
    if tickEvent then
        removeEvent(tickEvent)
    end
    tickEvent = scheduleEvent(tick, 10)
end

-- ---------------------------------------------------------------- toast

local function hideToast()
    if toastEvent then
        removeEvent(toastEvent)
        toastEvent = nil
    end
    if toast then
        toast:destroy()
        toast = nil
    end
end

local function showToast(title, text, iconSetup, seconds)
    hideToast()
    local parent = modules.game_interface and modules.game_interface.getRootPanel() or rootWidget
    toast = g_ui.createWidget('HuntToast', parent)
    toast:addAnchor(AnchorTop, 'parent', AnchorTop)
    toast:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    toast:setMarginTop(40)
    toast.title:setText(title)
    toast.text:setText(text)
    if iconSetup then
        iconSetup(toast.icon)
    end
    toast.open.onClick = function()
        hideToast()
        if not window:isVisible() or currentTab ~= 'rates' then
            openSection('rates')
        end
    end
    toast.onClick = hideToast
    toastEvent = scheduleEvent(hideToast, (seconds or 12) * 1000)
end

-- ---------------------------------------------------------------- rate next to the monsters

-- experience rate (tenths) of each monster, by lower-case name
local rateByName = {}

local function labelCreature(creature)
    if not creature or not creature.setRateText or not creature:isMonster() then
        return
    end
    local tenths = rateByName[creature:getName():lower()]
    creature:setRateText(tenths and string.format('%.1fx', tenths / 10) or '')
end

local function labelAll()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), true)) do
        labelCreature(creature)
    end
end

-- ---------------------------------------------------------------- server messages

local handlers = {}

function handlers.rates(data)
    timeOffset = (data.now or os.time()) - os.time()
    rates.slot = data.slot or -1
    rates.nextAt = data.nextAt or 0
    rates.interval = data.interval or 7200
    rates.max = data.max or 100
    rates.lootMax = data.lootMax or 40
    local fields = data.fields or {}
    local index = {}
    for i, name in ipairs(fields) do
        index[name] = i
    end
    local monsters = {}
    for _, raw in ipairs(data.monsters or {}) do
        local monster = {}
        for name, i in pairs(index) do
            monster[name] = raw[i]
        end
        monster.name = tostring(monster.name or '?')
        monster.lname = monster.name:lower()
        monster.exp = tonumber(monster.exp) or 0
        monster.hp = tonumber(monster.hp) or 0
        monster.spawns = tonumber(monster.spawns) or 0
        monster.xp = tonumber(monster.xp) or 10
        monster.loot = tonumber(monster.loot) or 10
        monster.perKill = math.floor(monster.exp * monster.xp / 10)
        -- a monster with an experience rate above 1x is tougher (server:
        -- huntboard strength)
        monster.hpMult, monster.dmgMult = 1, 1
        local strength = data.strength
        local rate = monster.xp / 10
        if strength and rate > 1 and (monster.boss ~= 1 or strength.bosses == 1) then
            monster.hpMult = 1 + (rate - 1) * (tonumber(strength.hp) or 0) / 100
            monster.dmgMult = 1 + (rate - 1) * (tonumber(strength.dmg) or 0) / 100
        end
        monsters[#monsters + 1] = monster
    end
    rates.monsters = monsters
    rateByName = {}
    for _, monster in ipairs(monsters) do
        rateByName[monster.lname] = monster.xp
    end
    labelAll()
    if window then
        updateFooter()
        renderHot()
        applyFilters()
    end
end

function handlers.board(data)
    timeOffset = (data.now or os.time()) - os.time()
    boards[data.period or 'hour'] = data
    online.minutes = data.online or online.minutes
    online.goal = data.onlineGoal or online.goal
    online.amount = data.onlineAmount or online.amount
    updateOnline()
    if data.period == currentPeriod then
        renderBoard()
    end
end

function handlers.ratesChanged(data)
    rates.nextAt = data.nextAt or rates.nextAt
    local parts = {}
    for _, entry in ipairs(data.top or {}) do
        parts[#parts + 1] = string.format('%s (XP x%.1f / Loot x%.1f)', entry.name, entry.x / 10, entry.l / 10)
    end
    showToast(tr('Monster rates have changed!'), tr('Hottest: %s', table.concat(parts, ', ')), function(icon)
        icon:setImageSource('/images/game/prey/prey_bigxp')
        icon:setImageClip('0 0 44 44')
    end, 15)
    -- the labels on the monsters need the new rates too
    send({ action = 'rates' })
end

function handlers.coins(data)
    local text
    if data.reason == 'online' then
        online.minutes = 0
        updateOnline()
        text = tr('+%d Mythicum Coin for playing 1 hour. Thanks for playing!', data.amount or 1)
    else
        text = tr('+%s Mythicum Coins for winning the leaderboard!', formatNumber(data.amount or 0))
    end
    if data.balance then
        text = text .. '\n' .. tr('Balance: %s Mythicum Coins', formatNumber(data.balance))
    end
    showToast(tr('Mythicum Coins received'), text, function(icon)
        icon:setImageSource('/images/store/icon-tibiacoin')
        icon:setImageClip('')
    end, 8)
end

local function onHuntOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    local handler = handlers[data.action]
    if handler then
        handler(data)
    end
end

-- ---------------------------------------------------------------- public (otui)

function onFilterChanged()
    if filterEvent then
        removeEvent(filterEvent)
    end
    filterEvent = scheduleEvent(function()
        filterEvent = nil
        applyFilters()
    end, 250)
end

function changePage(delta)
    page = page + delta
    renderPage()
end

-- with the Baiak Mythicum panel, Hunt Rates and Leaderboard open as two windows
-- (the same window showing one section, without the tabs)
local SECTIONS = {
    rates = { title = 'Hunt Rates', intro = 'XP and loot rate of every monster' },
    board = { title = 'Leaderboard', intro = 'Top hunters of the hour, day and month' },
}

function updateFooter()
    if not window then
        return
    end
    local hours = math.floor(rates.interval / 3600)
    if not next(sectionButtons) then
        window.footer:setText(tr('Rates re-roll every %d hours for every monster. Leaderboard winners are paid in Mythicum Coins when the period ends.', hours))
    elseif currentTab == 'rates' then
        window.footer:setText(tr('Rates re-roll every %d hours for every monster.', hours))
    else
        window.footer:setText(tr('Leaderboard winners are paid in Mythicum Coins when the period ends.'))
    end
end

local function updateSectionButtons()
    local visible = window and window:isVisible()
    for tab, button in pairs(sectionButtons) do
        button:setOn(visible and currentTab == tab)
    end
end

function selectTab(tab)
    currentTab = tab
    window.ratesTab:setChecked(tab == 'rates')
    window.boardTab:setChecked(tab == 'board')
    window.ratesPanel:setVisible(tab == 'rates')
    window.boardPanel:setVisible(tab == 'board')
    local split = next(sectionButtons) ~= nil
    window.ratesTab:setVisible(not split)
    window.boardTab:setVisible(not split)
    window.sectionIntro:setVisible(split)
    if split then
        window:setText(tr(SECTIONS[tab].title))
        window.sectionIntro:setText(tr(SECTIONS[tab].intro))
    end
    updateFooter()
    updateSectionButtons()
    if tab == 'board' then
        renderBoard()
        send({ action = 'board', period = currentPeriod })
    end
end

function selectPeriod(period)
    currentPeriod = period
    renderBoard()
    send({ action = 'board', period = period })
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
    updateSectionButtons()
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
    updateSectionButtons()
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
    send({ action = 'open', period = currentPeriod })
end

-- open the window on one section, or close it when that section is showing
function openSection(tab)
    if not window then
        return
    end
    if window:isVisible() then
        if currentTab == tab then
            hide()
        else
            selectTab(tab)
            window:raise()
            window:focus()
        end
        return
    end
    currentTab = tab
    toggle()
end

function toggleRates()
    openSection('rates')
end

function toggleBoard()
    openSection('board')
end

-- ---------------------------------------------------------------- lifecycle

local function setupCombo(combo, options)
    combo:clearOptions()
    for _, option in ipairs(options) do
        combo:addOption(tr(option.label), option.key)
    end
    combo:setCurrentIndex(1, true)
    combo.onOptionChange = function()
        applyFilters()
    end
end

local function onGameStart()
    connect(Creature, { onAppear = labelCreature })
    scheduleEvent(function()
        if g_game.isOnline() then
            send({ action = 'rates' })
        end
    end, 1000)
    if not next(sectionButtons) and modules.game_brevespanel then
        sectionButtons.rates = modules.game_brevespanel.addFeature('rates', toggleRates)
        sectionButtons.board = modules.game_brevespanel.addFeature('board', toggleBoard)
    end
    if not next(sectionButtons) and not toolbarButton and modules.game_mainpanel then
        toolbarButton = modules.game_mainpanel.addToggleButton('huntBoardButton', tr('Hunt Board (rates & leaderboard)'),
            '/game_huntboard/images/button', toggle, false, 21)
    end
end

local function onGameEnd()
    disconnect(Creature, { onAppear = labelCreature })
    rateByName = {}
    hide()
    hideToast()
    rates.monsters = {}
    rates.nextAt = 0
    boards = {}
end

function init()
    window = g_ui.displayUI('huntboard')
    window:hide()

    setupCombo(window.ratesPanel.filterBox, FILTERS)
    setupCombo(window.ratesPanel.sortBox, SORTS)
    updateOnline()

    ProtocolGame.registerExtendedJSONOpcode(HUNT_OPCODE, onHuntOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    disconnect(Creature, { onAppear = labelCreature })
    ProtocolGame.unregisterExtendedJSONOpcode(HUNT_OPCODE)
    hideToast()
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    if filterEvent then
        removeEvent(filterEvent)
        filterEvent = nil
    end
    if toolbarButton then
        toolbarButton:destroy()
        toolbarButton = nil
    end
    for _, button in pairs(sectionButtons) do
        button:destroy()
    end
    sectionButtons = {}
    if window then
        window:destroy()
        window = nil
    end
end
