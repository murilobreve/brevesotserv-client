-- Item card: a look at an item, or the mouse resting on one in a backpack or
-- slot, shows the item as a card in the website's colours instead of a line
-- of green text: the name and grade, the element tags, the stats, each
-- rarity bonus with a bar for how good its roll is, the requirements and who
-- found it. The server describes the item (scripts/item_card/item_card.lua);
-- this module draws it.
--
-- Opcode OPCODE, JSON both ways:
--   server -> client { action = 'card', mode = 'look' | 'hover', key, card }
--   client -> server { action = 'hover', key, id, pos = { x, y, z } }

local OPCODE = 128

-- 'both': on a look and on hover; 'look': on a look only; 'off': the old
-- green text (Interface window in the Mythos bar)
local MODE_SETTING = 'itemcard_mode'

local HOVER_DELAY = 220 -- ms the mouse rests on an item before its card shows
local SCRUB_WINDOW = 400 -- ms after a card closes when the next shows at once
local LOOK_TEXT_WINDOW = 1500 -- ms a look card takes the place of its look text
local LOOK_DISMISS_DISTANCE = 280 -- px the mouse may move away from a look card
local CACHE_TTL = 10000

local GRADES = {
    uncommon = '#63c08a',
    rare = '#4f8fe8',
    epic = '#a679e6',
    legendary = '#e2a443',
    mythic = '#e8e4ff',
}

local INK = '#f3ead9'
local DIM = '#a39cbc'
local STONE = '#655036'
local PLAIN_BAR = '#6f688a'
local GOOD = '#78d04c'
local BAD = '#d2442f'

-- the card's own words in Portuguese: the locale file translates some of
-- them as verbs ("Attack" is "Atacar" on a button)
local PT = {
    ['Attack'] = 'Ataque',
    ['Defence'] = 'Defesa',
    ['Armor'] = 'Armadura',
    ['Range'] = 'Alcance',
    ['Hit Chance'] = 'Chance de acerto',
    ['Volume'] = 'Volume',
    ['Protection'] = 'Proteção',
    ['Reflection'] = 'Reflexo de dano',
    ['Magic Shield'] = 'Escudo mágico',
    ['Perfect Shot'] = 'Tiro perfeito',
    ['Cleave'] = 'Cleave',
    ['Spell'] = 'Magia',
    ['Speed'] = 'Velocidade',
    ['Magic level'] = 'Nível mágico',
    ['Sword fighting'] = 'Espada',
    ['Axe fighting'] = 'Machado',
    ['Club fighting'] = 'Clava',
    ['Distance fighting'] = 'Distância',
    ['Fist fighting'] = 'Punhos',
    ['Shielding'] = 'Escudo',
    ['Fishing'] = 'Pesca',
    ['Critical hit chance'] = 'Chance de crítico',
    ['Critical extra damage'] = 'Dano crítico',
    ['Life leech'] = 'Roubo de vida',
    ['Mana leech'] = 'Roubo de mana',
    ['Faster regeneration'] = 'Regeneração rápida',
    ['Rarity bonuses'] = 'Bônus de raridade',
    ['Details'] = 'Detalhes',
    ['Requires'] = 'Requer',
    ['Imbuements'] = 'Imbuements',
    ['Weight'] = 'Peso',
    ['Charges'] = 'Cargas',
    ['Level'] = 'Nível',
    ['Magic Level'] = 'Nível mágico',
    ['Premium'] = 'Premium',
    ['PERFECT'] = 'PERFEITO',
    ['Found by'] = 'Achado por',
    ['and'] = 'e',
    ["+%d%% stronger in its finder's hands"] = '+%d%% mais forte nas mãos de quem achou',
}

-- the fonts draw one glyph per byte (Latin-1); this file and the server's
-- JSON are UTF-8, so every text is turned into Latin-1 once
local function latin1(text)
    return (tostring(text):gsub('[\194\195][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        return string.char((a - 194) * 64 + b)
    end))
end

local function convertStrings(value)
    for key, v in pairs(value) do
        if type(v) == 'string' then
            value[key] = latin1(v)
        elseif type(v) == 'table' then
            convertStrings(v)
        end
    end
    return value
end

convertStrings(PT)

-- between the parts of a line: "Knights · Level 55"
local SEPARATOR = latin1('  ·  ')

local function isPortuguese()
    local locales = modules.client_locales
    local locale = locales and locales.getCurrentLocale and locales.getCurrentLocale()
    return locale ~= nil and locale.name == 'pt'
end

local function t(text)
    return isPortuguese() and PT[text] or text
end

local card -- the card on screen (one at a time)
local cardMode -- 'look' or 'hover'
local cardAnchor -- the item widget it stands next to, or a point { point = true, x, y }
local lookEvent
local lookShownAt = 0
local lookTextTaken = true
local lastClosedAt = 0

local hoverWidget, hoverKey, hoverEvent
local cache = {}
local cacheSize = 0

-- ---------------------------------------------------------------- settings

function getMode()
    local mode = g_settings.getString(MODE_SETTING, 'both')
    if mode ~= 'look' and mode ~= 'off' then
        mode = 'both'
    end
    return mode
end

function setMode(mode)
    g_settings.set(MODE_SETTING, mode)
    if mode ~= 'both' then
        hideHover()
    end
    if mode == 'off' then
        hide()
        lookTextTaken = true
    end
end

-- ---------------------------------------------------------------- building

local SMALL_WORDS = { ['of'] = true, ['the'] = true, ['and'] = true, ['e'] = true, ['de'] = true, ['da'] = true, ['do'] = true }

local function titleCase(text)
    local first = true
    return (text:gsub("(%a)([%w']*)", function(letter, rest)
        local word = letter .. rest
        if not first and SMALL_WORDS[word:lower()] then
            return word:lower()
        end
        first = false
        return letter:upper() .. rest
    end))
end

local function percentText(quality)
    return string.format('%d%%', math.floor((quality or 0) * 100 + 0.5))
end

local function addSection(parent, title)
    local section = g_ui.createWidget('ItemCardSection', parent)
    section.title:setText(title)
    return section
end

local function addStat(parent, label, value, valueColor)
    value = value or ''
    -- a value that cannot share the line with its label goes under it
    local long = #label + #value > 34
    local row = g_ui.createWidget(long and 'ItemCardStatLong' or 'ItemCardStat', parent)
    row.label:setText(label)
    row.value:setText(value)
    if valueColor then
        row.value:setColor(valueColor)
    end
    if value == '' then
        row.label:setColor(INK)
    end
    return row
end

local function addLine(parent, text, color)
    local line = g_ui.createWidget('ItemCardLine', parent)
    line:setText(text)
    if color then
        line:setColor(color)
    end
    return line
end

local function fillHeader(widget, data, gradeColor)
    local header = g_ui.createWidget('ItemCardHeader', widget)
    local item = Item.create(data.id or 0, math.max(1, data.count or 1))
    local rarity = data.rarity
    if rarity and rarity.grade then
        -- the frame and the corner gems, as in the backpack
        local tooltip = '#rarity:' .. rarity.grade
        if rarity.tags and #rarity.tags > 0 then
            tooltip = tooltip .. '\n#elements:' .. table.concat(rarity.tags, ',')
        end
        item:setTooltip(tooltip)
    end
    header.slot:setItem(item)
    if rarity then
        ItemsDatabase.setItemRarityFrame(header.slot, item)
    end

    local name = titleCase(data.name or '')
    header.name:setText(name)
    header.name:setColor(gradeColor or INK)
    if #name > 19 then
        header.name:setFont('Verdana Bold-11px')
    end

    local sub = header.sub
    if rarity then
        local grade = g_ui.createWidget('ItemCardGrade', sub)
        local label = ItemsDatabase.itemRarity[rarity.grade] and ItemsDatabase.itemRarity[rarity.grade].label or rarity.gradeName or ''
        grade:setText(label:upper())
        grade:setColor(gradeColor or INK)
        for _, tag in ipairs(rarity.tags or {}) do
            local gem = g_ui.createWidget('ItemCardGem', sub)
            gem:setImageColor(ItemsDatabase.elementColors[tag] or '#c9c0cf')
            local text = g_ui.createWidget('ItemCardTag', sub)
            text:setText(tag)
        end
    elseif (data.count or 1) > 1 then
        g_ui.createWidget('ItemCardSubText', sub):setText('x' .. data.count)
    end
    if sub:getChildCount() == 0 then
        -- the name alone: in the middle of the slot
        header.name:breakAnchors()
        header.name:addAnchor(AnchorLeft, 'slot', AnchorRight)
        header.name:addAnchor(AnchorRight, 'parent', AnchorRight)
        header.name:addAnchor(AnchorVerticalCenter, 'slot', AnchorVerticalCenter)
        header.name:setMarginLeft(9)
    end
end

local function fillBonuses(widget, rarity)
    addSection(widget, t('Rarity bonuses'))
    for _, bonus in ipairs(rarity.bonuses or {}) do
        local row = g_ui.createWidget('ItemCardBonus', widget)
        local color = bonus.color or nil
        row.text:setText(bonus.text or '')
        row.text:setColor(color or INK)
        row.gem:setImageColor(color or PLAIN_BAR)
        if bonus.quality then
            local fill = row.track.fill
            fill:setBackgroundColor(color or PLAIN_BAR)
            fill:setWidth(math.max(1, math.floor((row.track:getWidth() - 2) * math.min(1, bonus.quality) + 0.5)))
            row.percent:setText(percentText(bonus.quality))
        else
            row.track:hide()
        end
        if bonus.perfect then
            row.percent:hide()
            local ribbon = g_ui.createWidget('ItemCardPerfect', row)
            ribbon:setId('perfect')
            ribbon:setText(t('PERFECT'))
            ribbon:addAnchor(AnchorRight, 'parent', AnchorRight)
            ribbon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
            row.track:breakAnchors()
            row.track:addAnchor(AnchorRight, 'perfect', AnchorLeft)
            row.track:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
            row.track:setMarginRight(5)
        end
    end
end

local function wieldText(wield)
    local player = g_game.getLocalPlayer()
    local parts, short = {}, false
    if wield.vocations then
        parts[#parts + 1] = titleCase((wield.vocations:gsub(' and ', ' ' .. t('and') .. ' ')))
    end
    if wield.level then
        parts[#parts + 1] = t('Level') .. ' ' .. wield.level
        short = short or (player and player:getLevel() < wield.level)
    end
    if wield.magic then
        parts[#parts + 1] = t('Magic Level') .. ' ' .. wield.magic
        short = short or (player and player:getMagicLevel() < wield.magic)
    end
    if wield.premium then
        parts[#parts + 1] = t('Premium')
    end
    return table.concat(parts, SEPARATOR), short
end

local function fill(widget, data)
    local rarity = data.rarity
    local gradeColor = rarity and GRADES[rarity.grade] or nil

    local accent = g_ui.createWidget('ItemCardAccent', widget)
    accent:setBackgroundColor(gradeColor or STONE)

    fillHeader(widget, data, gradeColor)
    g_ui.createWidget('ItemCardDivider', widget)

    for _, stat in ipairs(data.stats or {}) do
        addStat(widget, t(stat.label or ''), stat.value)
    end

    if rarity and rarity.bonuses and #rarity.bonuses > 0 then
        fillBonuses(widget, rarity)
    end

    local details = {}
    if data.wield then
        local text, short = wieldText(data.wield)
        if text ~= '' then
            details[#details + 1] = { t('Requires'), text, short and BAD or nil }
        end
    end
    if data.imbuements and #data.imbuements > 0 then
        details[#details + 1] = { t('Imbuements'), table.concat(data.imbuements, ', ') }
    end
    local lines = data.lines or {}
    -- the charges as a detail, like the weight; the note only said them
    local note = data.note
    if tonumber(data.charges) then
        details[#details + 1] = { t('Charges'), tostring(data.charges) }
        note = nil
    end
    if #details > 0 or note or #lines > 0 or data.weight then
        addSection(widget, t('Details'))
        for _, detail in ipairs(details) do
            addStat(widget, detail[1], detail[2], detail[3])
        end
        if note then
            addLine(widget, note, INK)
        end
        for _, line in ipairs(lines) do
            addLine(widget, line)
        end
        if data.weight then
            addStat(widget, t('Weight'), data.weight)
        end
    end

    -- who found it, last, as the site's Hall of Fame signs a find
    local finder = rarity and rarity.finder
    if finder then
        local text = t('Found by') .. ' ' .. (finder.name or '?')
        if finder.date then
            text = text .. SEPARATOR .. finder.date
        end
        g_ui.createWidget('ItemCardFinder', widget):setText(text)
        if finder.bonus and finder.bonus > 0 then
            -- green when the finder is the one looking
            addLine(widget, string.format(t("+%d%% stronger in its finder's hands"), finder.bonus), finder.you and GOOD or DIM)
        end
    end
end

-- ---------------------------------------------------------------- placing

local function rectOf(anchor)
    if not anchor then
        return nil
    elseif anchor.point then
        return { x = anchor.x, y = anchor.y, width = 0, height = 0 }
    elseif anchor:isDestroyed() then
        return nil
    end
    local pos = anchor:getPosition()
    return { x = pos.x, y = pos.y, width = anchor:getWidth(), height = anchor:getHeight() }
end

local placing = false
local function place()
    if not card or placing then
        return
    end
    local rect = rectOf(cardAnchor)
    if not rect then
        return
    end
    placing = true
    local width, height = card:getWidth(), card:getHeight()
    local screenWidth, screenHeight = rootWidget:getWidth(), rootWidget:getHeight()
    local gap = rect.width > 0 and 8 or 18
    local x = rect.x + rect.width + gap
    if x + width > screenWidth - 4 then
        x = rect.x - width - (rect.width > 0 and 8 or 12)
    end
    x = math.max(4, math.min(x, screenWidth - width - 4))
    local y = rect.width > 0 and rect.y or (rect.y - 12)
    y = math.max(4, math.min(y, screenHeight - height - 4))
    card:setPosition({ x = x, y = y })
    placing = false
end

local function onMouseMove(widget, mousePos)
    if card and cardMode == 'look' and cardAnchor and cardAnchor.point then
        local dx, dy = mousePos.x - cardAnchor.x, mousePos.y - cardAnchor.y
        if dx * dx + dy * dy > LOOK_DISMISS_DISTANCE * LOOK_DISMISS_DISTANCE then
            hide()
        end
    end
end

-- ---------------------------------------------------------------- showing

function hide()
    removeEvent(lookEvent)
    lookEvent = nil
    disconnect(rootWidget, { onMouseMove = onMouseMove })
    if card then
        g_effects.cancelFade(card)
        card:destroy()
        card = nil
        lastClosedAt = g_clock.millis()
    end
    cardMode, cardAnchor = nil, nil
end

local function show(data, mode, anchor)
    hide()
    card = g_ui.createWidget('ItemCard', rootWidget)
    card:setOpacity(0)
    local ok, err = pcall(fill, card, data)
    if not ok then
        g_logger.warning('[ItemCard] ' .. tostring(err))
        hide()
        return false
    end
    cardMode, cardAnchor = mode, anchor
    card.onGeometryChange = place
    place()
    card:raise()
    g_effects.fadeIn(card, 120)
    return true
end

local function lookDuration(data)
    local rows = #(data.stats or {}) + #(data.lines or {})
    if data.rarity then
        rows = rows + #(data.rarity.bonuses or {}) + 2
    end
    return math.min(12000, 5000 + rows * 450)
end

local function showLook(data)
    if getMode() == 'off' then
        return
    end
    -- looked at in a backpack: next to the item; on the map: by the mouse
    local anchor
    if hoverWidget and not hoverWidget:isDestroyed() and hoverWidget:isHovered() then
        local item = hoverWidget:getItem()
        if item and item:getId() == data.id then
            anchor = hoverWidget
        end
    end
    if not anchor then
        local mouse = g_window.getMousePosition()
        anchor = { point = true, x = mouse.x, y = mouse.y }
    end
    removeEvent(hoverEvent)
    hoverEvent = nil
    if not show(data, 'look', anchor) then
        return
    end
    lookShownAt = g_clock.millis()
    lookTextTaken = false
    lookEvent = scheduleEvent(function()
        lookEvent = nil
        if card and cardMode == 'look' then
            local closing = card
            g_effects.fadeOut(closing, 250)
            lookEvent = scheduleEvent(function()
                lookEvent = nil
                if card == closing then
                    hide()
                end
            end, 260)
        end
    end, lookDuration(data))
    if anchor.point then
        connect(rootWidget, { onMouseMove = onMouseMove })
    end
end

-- the look message of an item whose card is on screen goes to the console
-- only (game_textmessage asks)
function takeLookText()
    if lookTextTaken or g_clock.millis() - lookShownAt > LOOK_TEXT_WINDOW then
        return false
    end
    lookTextTaken = true
    return true
end

-- ---------------------------------------------------------------- hover

local function clearCache()
    cache = {}
    cacheSize = 0
end

local function keyOf(item)
    local pos = item:getPosition()
    return string.format('%d:%d:%d:%d:%d:%s', item:getId(), item:getCountOrSubType(), pos.x, pos.y, pos.z, item:getTooltip() or '')
end

local function cached(key)
    local entry = cache[key]
    if entry and g_clock.millis() - entry.at < CACHE_TTL then
        return entry.card
    end
    return nil
end

function hideHover()
    removeEvent(hoverEvent)
    hoverEvent = nil
    hoverKey = nil
    if card and cardMode == 'hover' then
        hide()
    end
end

local function showHover(widget, key)
    local data = cached(key)
    if data then
        show(data, 'hover', widget)
        return
    end
    local protocol = g_game.getProtocolGame()
    local item = widget:getItem()
    if not protocol or not item then
        return
    end
    local pos = item:getPosition()
    protocol:sendExtendedJSONOpcode(OPCODE, {
        action = 'hover',
        key = key,
        id = item:getId(),
        pos = { x = pos.x, y = pos.y, z = pos.z },
    })
end

local function wantsCard(widget)
    if getMode() ~= 'both' or not g_game.isOnline() or widget:isVirtual() then
        return nil
    end
    local item = widget:getItem()
    if not item then
        return nil
    end
    local pos = item:getPosition()
    -- an inventory slot or a backpack slot: the server can find it
    if not pos or pos.x ~= 65535 then
        return nil
    end
    return item
end

-- UIItem:onHoverChange asks first; true means the card takes the place of the
-- plain tooltip
function onItemHover(widget, hovered)
    if not hovered then
        if hoverWidget == widget then
            hideHover()
        end
        return wantsCard(widget) ~= nil
    end
    hoverWidget = widget
    local item = wantsCard(widget)
    if not item then
        return false
    end
    if g_mouse.isPressed() or g_ui.getDraggingWidget() then
        return true
    end
    -- a look card stays until it times out; the hover card replaces it
    local key = keyOf(item)
    hoverKey = key
    removeEvent(hoverEvent)
    local delay = (card or g_clock.millis() - lastClosedAt < SCRUB_WINDOW) and 0 or HOVER_DELAY
    hoverEvent = scheduleEvent(function()
        hoverEvent = nil
        if hoverWidget == widget and hoverKey == key and not widget:isDestroyed() and widget:isHovered()
            and not g_mouse.isPressed() and not g_ui.getDraggingWidget() then
            showHover(widget, key)
        end
    end, delay)
    return true
end

-- ---------------------------------------------------------------- opcode

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' or data.action ~= 'card' or type(data.card) ~= 'table' then
        return
    end
    convertStrings(data.card)
    if data.mode == 'look' then
        showLook(data.card)
    elseif data.mode == 'hover' and data.key then
        if cacheSize > 300 then
            clearCache()
        end
        if not cache[data.key] then
            cacheSize = cacheSize + 1
        end
        cache[data.key] = { card = data.card, at = g_clock.millis() }
        if hoverKey == data.key and hoverWidget and not hoverWidget:isDestroyed() and hoverWidget:isHovered() then
            show(data.card, 'hover', hoverWidget)
        end
    end
end

local function onGameEnd()
    hide()
    hideHover()
    clearCache()
    hoverWidget = nil
end

function init()
    g_ui.importStyle('itemcard')
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameEnd = onGameEnd })
    -- anything that moves or changes in the bags makes the cached cards old
    -- (first in line: a handler before it that returns true stops the rest)
    connect(Container, { onAddItem = clearCache, onRemoveItem = clearCache, onUpdateItem = clearCache }, true)
    connect(LocalPlayer, { onInventoryChange = clearCache }, true)
end

function terminate()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    disconnect(g_game, { onGameEnd = onGameEnd })
    disconnect(Container, { onAddItem = clearCache, onRemoveItem = clearCache, onUpdateItem = clearCache })
    disconnect(LocalPlayer, { onInventoryChange = clearCache })
    onGameEnd()
end
