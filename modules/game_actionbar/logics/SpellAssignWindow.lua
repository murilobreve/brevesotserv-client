-- The Assign Spell window (otui/spellassign.otui): puts a spell on an action
-- button. The spells of the vocation are split by kind (all, attack,
-- healing, support and the Ascensão's), the ones the character can't use yet
-- are greyed out (a checkbox hides them) and the chosen spell's details
-- show below: mana, level, cooldowns, group, target and range, and whether
-- the character already has it. The Ascensão and the Wheel of Destiny
-- spells say where they come from, with a button to that window.
--
-- The numbers come from the server (data-otservbr-global/scripts/custom/
-- spell_details.lua, extended opcode OPCODE): the spells of the vocation as the
-- server has them and which of them the character has learned. Until the
-- answer comes (or on a server without it) the client's own SpellInfo
-- (modules/gamelib/spells.lua) is used.

SpellAssign = {}

local OPCODE = 138
local SETTING_TAB = 'spellAssignTab'
local SETTING_USABLE = 'spellAssignOnlyUsable'

local COLORS = {
    text = '#dcdcdc',
    words = '#9a9a9a',
    need = '#e08a6a',
    ascensao = '#f0c96a',
    wheel = '#9cc0f0',
    value = '#e8e8e8',
}

local STATUS_STYLE = {
    ok = { color = '#a8e6a8', background = '#2f3a2f', border = '#5fbf5f' },
    level = { color = '#f0c08a', background = '#3c3326', border = '#d0904c' },
    ascensao = { color = '#f0d79a', background = '#3a3424', border = '#c9a243' },
    wheel = { color = '#bcd6f5', background = '#28303c', border = '#5b7fb0' },
}

local TABS = {
    { id = 'all', title = 'All' },
    { id = 'attack', title = 'Attack', clip = '0 0 20 20' },
    { id = 'healing', title = 'Healing', clip = '20 0 20 20' },
    { id = 'support', title = 'Support', clip = '40 0 20 20' },
    { id = 'ascensao', title = 'Ascension', image = '/game_brevespanel/images/ascensao' },
}

local GROUP_CLIP = { attack = '0 0 20 20', healing = '20 0 20 20', support = '40 0 20 20' }
local GROUP_NAME = { [1] = 'Attack', [2] = 'Healing', [3] = 'Support', [4] = 'Special', [6] = 'Crippling',
    [7] = 'Focus', [8] = 'Ultimate Strikes', [9] = 'Bursts of Nature', [10] = 'Great Beams', [11] = 'Virtue' }

-- a word of this window: its own key in the locale ("Spell kind: Attack"
-- is "Ataque", where the shared "Attack" is "Atacar"), the word itself in
-- English
local function word(context, text)
    local key = context .. ': ' .. text
    local translated = tr(key)
    if translated == key then
        return text
    end
    return translated
end

local window = nil
local radio = nil
local rows = {}
local tabs = {}
local currentTab = 'all'
local target = nil -- the action button and the multi action slot
local book = nil -- what the server sent: byWords, ascensao

-- ------------------------------------------------------------------ data

local function send(data)
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedJSONOpcode(OPCODE, data)
    end
end

local function request()
    if g_game.isOnline() then
        send({ action = 'get' })
    end
end

local function playerLevel()
    local localPlayer = g_game.getLocalPlayer()
    return localPlayer and localPlayer:getLevel() or 0
end

local function seconds(ms)
    ms = tonumber(ms) or 0
    if ms <= 0 then
        return '-'
    end
    if ms >= 3600000 and ms % 3600000 == 0 then
        return string.format('%dh', ms / 3600000)
    end
    if ms >= 60000 and ms % 60000 == 0 then
        return string.format('%dmin', ms / 60000)
    end
    if ms % 1000 == 0 then
        return string.format('%ds', ms / 1000)
    end
    local text = string.format('%.1fs', ms / 1000)
    local locale = modules.client_locales and modules.client_locales.getCurrentLocale and modules.client_locales.getCurrentLocale()
    if locale and locale.decimalSeperator then
        text = text:gsub('%.', locale.decimalSeperator)
    end
    return text
end

-- the numbers of a spell: the server's when it sent them, else SpellInfo's
local function infoOf(spellData)
    local entry = book and book.byWords[spellData.words:lower()]
    if entry then
        return entry
    end
    local group = Spells.getPrimaryGroup(spellData)
    return {
        n = spellData.name,
        w = spellData.words,
        lv = spellData.level or 0,
        ml = spellData.maglevel or 0,
        m = spellData.mana or 0,
        mp = 0,
        s = spellData.soul or 0,
        cd = spellData.exhaustion or 0,
        g = group,
        gcd = spellData.group and spellData.group[group] or 0,
        r = spellData.range or -1,
        t = spellData.needTarget,
        par = spellData.parameter,
        a = group == 1,
    }
end

local function kindOf(info)
    if info.src == 'ascensao' then
        return 'ascensao'
    end
    if info.g == 1 then
        return 'attack'
    elseif info.g == 2 then
        return 'healing'
    end
    return 'support'
end

-- ok, level (too low), ascensao or wheel (not unlocked yet)
local function statusOf(info)
    if (info.src == 'ascensao' or info.src == 'wheel') and not info.owned then
        return info.src
    end
    if playerLevel() < (tonumber(info.lv) or 0) then
        return 'level'
    end
    return 'ok'
end

local function displayName(spellData, info)
    return info.label or spellData.name
end

-- ------------------------------------------------------------------ details

local function targetText(info)
    local skillshot = modules.game_skillshot and modules.game_skillshot.isSkillshot
    if skillshot and skillshot(info.w or '') then
        return tr('aimed with the mouse')
    end
    if info.t then
        return tr('needs a target')
    end
    if info.tod then
        return tr('target or ahead')
    end
    if info.d then
        return tr('ahead of you')
    end
    if info.self then
        return tr('on yourself')
    end
    if info.pn then
        return tr("a player's name")
    end
    if info.a then
        return tr('area')
    end
    return tr('on yourself')
end

local function addStat(panel, key, value)
    local label = g_ui.createWidget('SpellAssignStat', panel)
    label:setColoredText(string.format('%s {%s, %s}', key, value, COLORS.value))
end

local function showDetails(row)
    if not window then
        return
    end
    local details = window.details
    if not row then
        details:setVisible(false)
        return
    end
    details:setVisible(true)
    local spellData, info = row.spellData, row.info
    local kind = kindOf(info)
    local groupKind = info.g == 1 and 'attack' or (info.g == 2 and 'healing' or 'support')
    if kind == 'ascensao' then
        details.groupIcon:setImageSource('/game_brevespanel/images/ascensao')
        details.groupIcon:setImageClip('0 0 16 16')
        details.groupIcon:setSize({ width = 16, height = 16 })
    else
        details.groupIcon:setImageSource('/images/game/spells/spellgroup-icons-20x20')
        details.groupIcon:setImageClip(GROUP_CLIP[groupKind])
        details.groupIcon:setSize({ width = 20, height = 20 })
    end
    details.name:setText(displayName(spellData, info))
    details.words:setText('"' .. (info.w or spellData.words) .. '"')

    local stats = details.stats
    stats:destroyChildren()
    local cells = 0
    local function stat(key, value)
        addStat(stats, key, value)
        cells = cells + 1
    end
    local mana = tonumber(info.m) or 0
    if (tonumber(info.mp) or 0) > 0 then
        stat(tr('Mana:'), string.format('%d%%', info.mp))
    else
        stat(tr('Mana:'), tostring(mana))
    end
    stat(tr('Level:'), tostring(info.lv or 0))
    stat(tr('Cooldown:'), seconds(info.cd))
    stat(tr('Group:'), string.format('%s %s', word('Spell kind', GROUP_NAME[info.g] or 'Support'), seconds(info.gcd)))
    stat(tr('Target:'), targetText(info))
    if (tonumber(info.r) or 0) > 0 then
        stat(tr('Range:'), tr('%d sqm', info.r))
    end
    if (tonumber(info.ml) or 0) > 0 then
        stat(tr('Magic level:'), tostring(info.ml))
    end
    if (tonumber(info.s) or 0) > 0 then
        stat(tr('Soul:'), tostring(info.s))
    end

    local status = statusOf(info)
    local text
    local action = details.action
    action:setVisible(false)
    action.onClick = nil
    local style = STATUS_STYLE[status]
    if info.src == 'ascensao' then
        style = STATUS_STYLE.ascensao
        local start = book and book.ascensao and book.ascensao.start or 50
        local every = book and book.ascensao and book.ascensao.every or 10
        local circle = tonumber(info.circle) or 1
        if info.owned then
            text = tr('Ascension spell of the %s path: you already have it.', info.path or '?')
        else
            text = tr('Ascension spell of the %s path, not unlocked yet.', info.path or '?')
        end
        if circle <= 1 then
            text = text .. '\n' .. tr('The 1st circle of the path teaches it and every circle after it makes it stronger.')
        else
            text = text .. '\n' .. tr('Circle %d of the path teaches it.', circle)
        end
        text = text .. '\n' .. tr('Ascension points come with the level: 1 every %d levels from level %d.', every, start)
        action:setText(tr('Open Ascension'))
        action:setWidth(130)
        action:setVisible(true)
        action.onClick = function()
            if modules.game_ascensao and modules.game_ascensao.show then
                modules.game_ascensao.show()
            end
        end
    elseif info.src == 'wheel' then
        style = info.owned and STATUS_STYLE.ok or STATUS_STYLE.wheel
        if info.owned then
            text = tr('Wheel of Destiny spell: unlocked on your wheel.')
        else
            text = tr('Wheel of Destiny spell: it unlocks when you put points in the part of the wheel that gives it (level %d or more).', info.lv or 0)
        end
        action:setText(tr('Open the Wheel of Destiny'))
        action:setWidth(170)
        action:setVisible(true)
        action.onClick = function()
            if modules.game_wheel and modules.game_wheel.show then
                modules.game_wheel.show()
            end
        end
    elseif status == 'level' then
        local need = tonumber(info.lv) or 0
        text = tr('You can use it from level %d (%d levels to go).', need, need - playerLevel())
    else
        text = tr('You can already use this spell.')
    end
    -- three numbers a line
    stats:setHeight(math.ceil(cells / 3) * 16)
    local box = details.statusBox
    box.status:setText(text)
    box.status:setColor(style.color)
    box:setHeight(box.status:getHeight() + 8)
    box:setBackgroundColor(style.background)
    box:setBorderColorLeft(style.border)
end

-- ------------------------------------------------------------------ list

local function setPreview(row)
    if not window then
        return
    end
    if not row then
        window.previewText:setText(tr('No spell selected'))
        window.previewIcon:setImageClip('0 0 32 32')
        return
    end
    window.previewText:setText(displayName(row.spellData, row.info) .. '\n' .. row.spellData.words)
    window.previewIcon:setImageSource(SpelllistSettings['Default'].iconFile)
    window.previewIcon:setImageClip(Spells.getImageClip(row.spellData.clientId, 'Default'))
end

local function styleRow(row)
    local info = row.info
    local status = statusOf(info)
    local usable = status == 'ok'
    row.widget.icon.gray:setVisible(not usable)
    local dim = usable and 1 or 0.55
    row.widget.name:setOpacity(dim)
    row.widget.words:setOpacity(dim)
    row.widget.name:setText(displayName(row.spellData, info))
    row.widget.words:setText(row.spellData.words)

    local tag = row.widget.tag
    if info.src == 'ascensao' then
        tag:setText(tr('ASCENSION'))
        tag:setColor(COLORS.ascensao)
        tag:setBorderColor('#a07f2f')
        tag:setVisible(true)
    elseif info.src == 'wheel' then
        tag:setText(tr('WHEEL'))
        tag:setColor(COLORS.wheel)
        tag:setBorderColor('#5b7fb0')
        tag:setVisible(true)
    else
        tag:setVisible(false)
    end

    local right = row.widget.right
    if info.src == 'ascensao' then
        right:setText(info.path or '')
        right:setColor(info.owned and COLORS.text or COLORS.need)
    else
        right:setText(tr('Level %d', tonumber(info.lv) or 0))
        right:setColor(playerLevel() < (tonumber(info.lv) or 0) and COLORS.need or COLORS.text)
    end
    right:setOpacity(usable and 1 or 0.8)
end

-- shows the rows of the chosen kind that pass the search and the checkbox,
-- and counts each kind with the same rules
local function applyFilters()
    if not window then
        return
    end
    local search = window.searchText:getText():lower():trim()
    local onlyUsable = window.usableFilter:isChecked()
    local counts = {}
    for _, tab in ipairs(TABS) do
        counts[tab.id] = 0
    end
    -- a search looks in every kind (the counts say where it found them)
    local tab = search ~= '' and 'all' or currentTab
    local shown = 0
    for _, row in ipairs(rows) do
        local matches = search == '' or row.searchText:find(search, 1, true) ~= nil
        local passes = matches and (not onlyUsable or statusOf(row.info) == 'ok')
        if passes then
            counts.all = counts.all + 1
            counts[row.kind] = counts[row.kind] + 1
        end
        local visible = passes and (tab == 'all' or tab == row.kind)
        row.widget:setVisible(visible)
        if visible then
            shown = shown + 1
        end
    end
    for _, entry in ipairs(TABS) do
        local widget = tabs[entry.id]
        if widget then
            widget.count:setText(tostring(counts[entry.id]))
            local on = entry.id == tab
            widget:setChecked(on)
            widget.title:setColor(entry.id == 'ascensao' and COLORS.ascensao or (on and '#ffffff' or '#bdbdbd'))
            widget.count:setColor(on and '#d0d0d0' or '#8c8c8c')
        end
    end
    -- the Ascensão tab only for a vocation that has it
    if tabs.ascensao then
        local has = false
        for _, row in ipairs(rows) do
            if row.kind == 'ascensao' then
                has = true
                break
            end
        end
        tabs.ascensao:setVisible(has)
    end
    window.emptyLabel:setVisible(shown == 0)
    window.emptyLabel:setText(onlyUsable and tr('No spell here you can use yet.') or tr('No spell here.'))
    local selected = radio and radio:getSelectedWidget()
    if selected and selected:isVisible() then
        window.spellList:ensureChildVisible(selected)
    end
end

local function selectTab(id)
    currentTab = id
    g_settings.set(SETTING_TAB, id)
    -- a kind chosen during a search ends the search
    if window and window.searchText:getText() ~= '' then
        window.searchText:setText('')
    end
    applyFilters()
end

local function rowByWords(words)
    for _, row in ipairs(rows) do
        if row.spellData.words == words then
            return row
        end
    end
end

-- the spells of the vocation, from SpellInfo, that the server knows for it
local function buildRows(selectWords)
    if not window then
        return
    end
    local list = window.spellList
    if radio then
        radio:destroy()
    end
    radio = UIRadioGroup.create()
    list:destroyChildren()
    rows = {}

    local localPlayer = g_game.getLocalPlayer()
    local vocation = localPlayer and translateVocation(localPlayer:getVocation()) or 0
    local showAll = vocation == 0
    local spells = modules.gamelib.SpellInfo['Default']
    for _, spellData in pairs(spells) do
        local words = spellData.words:lower()
        local known
        if book and not showAll then
            known = book.byWords[words] ~= nil
        else
            known = showAll or table.contains(spellData.vocations or {}, vocation)
        end
        if known then
            local info = infoOf(spellData)
            local widget = g_ui.createWidget('SpellAssignRow', list)
            widget.icon:setImageSource(SpelllistSettings['Default'].iconFile)
            widget.icon:setImageClip(Spells.getImageClip(spellData.clientId, 'Default'))
            local row = {
                widget = widget,
                spellData = spellData,
                info = info,
                kind = kindOf(info),
                searchText = (displayName(spellData, info) .. ' ' .. spellData.name .. ' ' .. words):lower(),
            }
            widget.row = row
            styleRow(row)
            radio:addWidget(widget)
            rows[#rows + 1] = row
        end
    end

    -- by kind, then the level, then the name
    local order = { attack = 1, healing = 2, support = 3, ascensao = 4 }
    table.sort(rows, function(a, b)
        if a.kind ~= b.kind then
            return order[a.kind] < order[b.kind]
        end
        local la, lb = tonumber(a.info.lv) or 0, tonumber(b.info.lv) or 0
        if la ~= lb then
            return la < lb
        end
        return a.spellData.name < b.spellData.name
    end)
    for index, row in ipairs(rows) do
        list:moveChildToIndex(row.widget, index)
    end

    radio.onSelectionChange = function(_, selected)
        local row = selected and selected.row
        setPreview(row)
        showDetails(row)
        if row then
            local param = row.spellData.parameter and true or false
            window.paramLabel:setOn(param)
            window.paramText:setEnabled(param)
            if not window.keepParam then
                window.paramText:clearText()
                if row.spellData.words:lower():find('exani hur', 1, true) then
                    window.paramText:setText('up|down')
                end
            end
            window.keepParam = false
        end
    end

    local selected = selectWords and rowByWords(selectWords)
    if selected then
        radio:selectWidget(selected.widget)
    elseif rows[1] then
        radio:selectWidget(rows[1].widget)
    else
        setPreview(nil)
        showDetails(nil)
    end
    applyFilters()
end

-- ------------------------------------------------------------------ assign

local function close()
    if radio then
        radio:destroy()
        radio = nil
    end
    rows = {}
    tabs = {}
    target = nil
    if window then
        window:destroy()
        window = nil
    end
end

local function assign(destroy)
    if not window or not target then
        return
    end
    local selected = radio and radio:getSelectedWidget()
    if not selected or not selected.row then
        close()
        return
    end
    local button, slot = target.button, target.slot
    local barId, buttonId = string.match(button:getId(), '(.*)%.(.*)')
    local param = selected.row.spellData.words
    local paramValue = window.paramText:getText()
    local check = param .. ' ' .. paramValue
    if check:find('utevo res ina') then
        param = 'utevo res ina'
        paramValue = paramValue:gsub('ina ', '')
    end
    if paramValue:lower():find('up|down') then
        paramValue = ''
    end
    if paramValue ~= '' then
        param = param .. ' "' .. paramValue:gsub('"', '') .. '"'
    end
    if slot then
        if not button.cache.multiActions then
            button.cache.multiActions = { {}, {}, {} }
        end
        button.cache.multiActions[slot] = { chatText = param, sendAutomatically = true }
        ApiJson.createOrUpdateMultiText(tonumber(barId), tonumber(buttonId), slot, param, true)
        if updateMultiButtonState then
            updateMultiButtonState(button)
        end
        if assignMultiAction then
            assignMultiAction(button, true)
        end
    else
        ApiJson.createOrUpdateText(tonumber(barId), tonumber(buttonId), param, true)
        updateButton(button)
    end
    if destroy then
        close()
    end
end

-- ------------------------------------------------------------------ module

function SpellAssign.open(button, multiSlotIndex)
    close()
    if ActionBarController.ui then
        ActionBarController:unloadHtml()
    end
    target = { button = button, slot = multiSlotIndex }
    window = g_ui.createWidget('SpellAssignWindow', g_ui.getRootWidget())
    if not window then
        target = nil
        return
    end
    local suffix = multiSlotIndex and (' (Slot ' .. multiSlotIndex .. ')') or ''
    window:setText(tr('Assign Spell to Action Button %s', button:getId() .. suffix))
    window.onEscape = close
    -- back from the Ascens�o or the Wheel of Destiny: what changed there
    window.onFocusChange = function(_, focused)
        if focused then
            request()
        end
    end
    window.cancelButton.onClick = close
    window.okButton.onClick = function()
        assign(true)
    end
    window.applyButton.onClick = function()
        assign(false)
    end
    window.clearSearch.onClick = function()
        window.searchText:setText('')
    end
    window.searchText.onTextChange = applyFilters
    window.usableFilter:setChecked(g_settings.getBoolean(SETTING_USABLE, false))
    window.usableFilter.onCheckChange = function(widget, checked)
        g_settings.set(SETTING_USABLE, checked)
        applyFilters()
    end

    tabs = {}
    for _, tab in ipairs(TABS) do
        local widget = g_ui.createWidget('SpellAssignTab', window.tabs)
        widget.title:setText(word('Spell kind', tab.title))
        if tab.clip then
            widget.icon:setImageSource('/images/game/spells/spellgroup-icons-20x20')
            widget.icon:setImageClip(tab.clip)
        elseif tab.image then
            widget.icon:setImageSource(tab.image)
            widget.icon:setSize({ width = 16, height = 16 })
            widget.icon:setMarginLeft(6)
        else
            widget.icon:setWidth(0)
        end
        if tab.id == 'ascensao' then
            widget.title:setColor(COLORS.ascensao)
        end
        widget.onClick = function()
            selectTab(tab.id)
        end
        tabs[tab.id] = widget
    end

    -- the spell already on the button, with its parameter
    local preselect, preselectParam
    local cache = button.cache or {}
    if multiSlotIndex and cache.multiActions then
        local slot = cache.multiActions[multiSlotIndex]
        if slot and slot.chatText then
            local spellData, param = Spells.getSpellDataByParamWords(slot.chatText:lower())
            if spellData then
                preselect = spellData
                preselectParam = param and param:gsub('"', '')
            end
        end
    elseif cache.spellData and not cache.isRuneSpell then
        preselect = cache.spellData
        preselectParam = cache.castParam
    end

    currentTab = g_settings.getString(SETTING_TAB)
    local valid = false
    for _, tab in ipairs(TABS) do
        valid = valid or tab.id == currentTab
    end
    if not valid then
        currentTab = 'all'
    end
    buildRows(preselect and preselect.words)
    if preselect then
        local row = rowByWords(preselect.words)
        if row and currentTab ~= 'all' and currentTab ~= row.kind then
            currentTab = row.kind
            applyFilters()
        end
        if preselect.parameter and preselectParam then
            window.paramText:setText(preselectParam)
            window.paramText:setCursorPos(#preselectParam)
        end
    end
    window:show()
    window:raise()
    window:focus()
    window.searchText:focus()
    request()
end

function SpellAssign.close()
    close()
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' or data.action ~= 'spells' or type(data.spells) ~= 'table' then
        return
    end
    local byWords = {}
    for _, entry in ipairs(data.spells) do
        if type(entry) == 'table' and type(entry.w) == 'string' then
            byWords[entry.w:lower()] = entry
        end
    end
    book = { byWords = byWords, ascensao = data.ascensao }
    if not window then
        return
    end
    local selected = radio and radio:getSelectedWidget()
    local localPlayer = g_game.getLocalPlayer()
    local showAll = not localPlayer or translateVocation(localPlayer:getVocation()) == 0
    -- the same spells: only their numbers and states change, in place
    local same = showAll
    if not same then
        -- the spells the list would have now against the ones it has
        local expected = 0
        for _, spellData in pairs(modules.gamelib.SpellInfo['Default']) do
            if byWords[spellData.words:lower()] then
                expected = expected + 1
            end
        end
        local inList = 0
        for _, row in ipairs(rows) do
            if byWords[row.spellData.words:lower()] then
                inList = inList + 1
            end
        end
        same = inList == #rows and inList == expected
    end
    if same then
        for _, row in ipairs(rows) do
            row.info = infoOf(row.spellData)
            row.kind = kindOf(row.info)
            row.searchText = (displayName(row.spellData, row.info) .. ' ' .. row.spellData.name .. ' ' .. row.spellData.words):lower()
            styleRow(row)
        end
        applyFilters()
        if selected and selected.row then
            setPreview(selected.row)
            showDetails(selected.row)
        end
        return
    end
    -- else the list again, with the same spell chosen and its parameter
    window.keepParam = true
    buildRows(selected and selected.row and selected.row.spellData.words)
    window.keepParam = false
end

function SpellAssign.init()
    g_ui.importStyle('/game_actionbar/otui/spellassign.otui')
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
end

function SpellAssign.terminate()
    close()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    book = nil
end

function SpellAssign.onGameStart()
    book = nil
    -- ready before the window opens the first time (it asks again on open)
    scheduleEvent(request, 3000)
end

function SpellAssign.onGameEnd()
    close()
    book = nil
end
