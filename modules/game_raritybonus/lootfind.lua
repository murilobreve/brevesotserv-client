-- A rare find on screen (art and motion: the design kit "Loot raro, o valor
-- do impossivel"). The server sends it (scripts/rarity/loot.lua):
--   drop      everyone who sees the corpse: a beam and a floor mark in the
--             grade's colour, and a gem over the corpse while the item lies in
--             it; the finder also sees the item fly to them when it went
--             straight into the backpack
--   dropgone  the item left the corpse (looted, or the corpse rotted away)
--   dropmove  someone dragged the corpse to the next tile: the gem goes along
--   find      the finder's card, lower right corner of the map (the finder's
--             party gets it too, "found by")
--   banner    a Mythicus find, at the top of everyone's map
-- Each grade grows in height, geometry and duration: Communis a quick glint,
-- Mythicus a find people remember.

LOOT_GRADES = {
    uncommon = { folder = 'communis', name = 'Communis', rank = 1, color = '#63c08a', h = .72, g = .65, d = .80, ba = .48, ga = .35, gem = .27 },
    rare = { folder = 'rarus', name = 'Rarus', rank = 2, color = '#4f8fe8', h = 1.45, g = .95, d = 1.20, ba = .60, ga = .46, gem = .32 },
    epic = { folder = 'praeclarus', name = 'Praeclarus', rank = 3, color = '#af78ea', h = 2.15, g = 1.30, d = 1.70, ba = .68, ga = .53, gem = .37 },
    legendary = { folder = 'legendarius', name = 'Legendarius', rank = 4, color = '#e2a443', h = 2.95, g = 1.75, d = 2.25, ba = .76, ga = .62, gem = .43 },
    mythic = { folder = 'mythicus', name = 'Mythicus', rank = 5, color = '#e8e4ff', h = 3.85, g = 2.20, d = 3.10, ba = .84, ga = .70, gem = .49 },
}
local LOOT_LAYERS = { chao = 1, feixe = 2, gema = 3, coleta = 4 }
local LOOT_EFFECT_BASE = 3100
local NUMERALS = { 'I', 'II', 'III', 'IV', 'V' }
-- the beam's texture: 224 of its 256 px are the visible height, and its foot
-- sits 240 px down
local BEAM_SCALE = 256 / 224
-- the kit's sizes, drawn LOOT_SCALE times bigger on the game's screen
local LOOT_SCALE = 1.45
local CARD_SHOWS = 5.35
local BANNER_SHOWS = 5.7

local lootDrops = {}
local cards = {}
local bannerQueue = {}
local banner

-- the fonts draw one glyph per byte (Latin-1); the server's JSON is UTF-8
local function latin1(text)
    return (tostring(text or ''):gsub('[\194\195][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        return string.char((a - 194) * 64 + b)
    end))
end

local function clamp01(x)
    return math.max(0, math.min(1, x))
end

local function smooth(x)
    x = clamp01(x)
    return x * x * (3 - 2 * x)
end

local function titleCase(text)
    return (tostring(text or ''):gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest
    end))
end

local function lootEffectId(gradeKey, layer)
    return LOOT_EFFECT_BASE + LOOT_GRADES[gradeKey].rank * 10 + LOOT_LAYERS[layer]
end

-- the floor in the ground-border pass, under corpses and every creature; the
-- beam, the gem and the flight over them
function registerLootTextures()
    for gradeKey, grade in pairs(LOOT_GRADES) do
        for layer in pairs(LOOT_LAYERS) do
            local id = lootEffectId(gradeKey, layer)
            local path = string.format('/game_raritybonus/images/loot/%s/loot_%s_%s', grade.folder, grade.folder, layer)
            g_attachedEffects.remove(id)
            local effect = g_attachedEffects.registerByImage(id, 'Loot ' .. grade.folder .. ' ' .. layer, path, true)
            if effect then
                effect:setPermanent(true)
                effect:setOnTop(layer ~= 'chao')
                effect:setDrawOrder(layer == 'chao' and 1 or 3)
            end
        end
    end
end

function unregisterLootTextures()
    for gradeKey in pairs(LOOT_GRADES) do
        for layer in pairs(LOOT_LAYERS) do
            g_attachedEffects.remove(lootEffectId(gradeKey, layer))
        end
    end
end

-- ---------------------------------------------------------------------------
-- on the map
-- ---------------------------------------------------------------------------

local function dropLootEffects(id)
    local entry = lootDrops[id]
    lootDrops[id] = nil
    if not entry then
        return
    end
    removeEvent(entry.event)
    local tile = g_map.getTile(entry.pos)
    if tile then
        for _, effect in pairs(entry.effects) do
            tile:detachEffect(effect)
        end
    end
end

-- a texture of `size` tiles whose point (fx, fy) (fractions of the texture)
-- sits at (x, y), in 32 px units from the tile's corner (an attached effect is
-- drawn at the tile's corner minus its offset)
local function placeLootLayer(entry, tile, layer, size, opacity, x, y, fx, fy)
    local effect = entry.effects[layer]
    if not effect then
        effect = g_attachedEffects.getById(lootEffectId(entry.grade, layer))
        if not effect then
            return
        end
        entry.effects[layer] = effect
    end
    local side = math.max(1, math.floor(size * LOOT_SCALE * 32 + 0.5))
    effect:setSize({ width = side, height = side })
    effect:setOffset(math.floor(side * fx - x + 0.5), math.floor(side * fy - y + 0.5))
    effect:setOpacity(clamp01(opacity))
    if not tile:getAttachedEffectById(effect:getId()) then
        tile:attachEffect(effect)
    end
end

local function hideLootLayer(entry, layer)
    if entry.effects[layer] then
        entry.effects[layer]:setOpacity(0)
    end
end

-- the corpse's middle: a 2x2 corpse (a dragon's) is drawn up and left of its
-- tile
local function corpseShift(pos)
    local tile = g_map.getTile(pos)
    local corpse = tile and tile:getTopUseThing()
    if corpse and corpse:isItem() then
        local thingType = g_things.getThingType(corpse:getId(), ThingCategoryItem)
        if thingType then
            return (math.max(1, math.min(2, math.max(thingType:getWidth(), thingType:getHeight()))) - 1) * 16
        end
    end
    return 0
end

function showLootDrop(data)
    local grade = LOOT_GRADES[data.grade]
    if not grade or not data.x or not data.id then
        return
    end
    local existing = lootDrops[data.id]
    if existing and data.quiet then
        return -- a gem already on screen, sent again for whoever came later
    end
    dropLootEffects(data.id)
    local pos = { x = data.x, y = data.y, z = data.z }
    local entry = {
        id = data.id,
        pos = pos,
        key = pos.x .. ':' .. pos.y .. ':' .. pos.z,
        grade = data.grade,
        marker = data.marker == true,
        -- a gem sent to someone who came into view later: no beam
        starts = g_clock.millis() - (data.quiet and 10000 or 0),
        effects = {},
        shift = corpseShift(pos),
    }
    local player = g_game.getLocalPlayer()
    if data.picked and player and data.finder == player:getId() then
        local me = player:getPosition()
        entry.travel = { dx = me.x - pos.x, dy = me.y - pos.y }
        entry.travelAt = entry.starts + 650
    end
    lootDrops[data.id] = entry

    local function frame()
        if lootDrops[data.id] ~= entry then
            return
        end
        local t = (g_clock.millis() - entry.starts) / 1000
        local beamDone = t > grade.d
        local travelDone = not entry.travel or g_clock.millis() - entry.travelAt > 750
        if beamDone and travelDone and not entry.marker then
            dropLootEffects(data.id)
            return
        end
        local tile = g_map.getTile(entry.pos)
        if tile then
            local s = entry.shift
            local cx, cy = 16 - s, 16 - s
            local presence = smooth(t / .22) * (1 - smooth((t - grade.d * .58) / (grade.d * .42)))
            if presence > 0.005 then
                -- a corpse rising as a rare monster keeps its own floor
                if reviveActiveAt and reviveActiveAt(entry.key) then
                    hideLootLayer(entry, 'chao')
                else
                    placeLootLayer(entry, tile, 'chao', grade.g * (.72 + .28 * smooth(t / (grade.d * .6))), grade.ga * presence, cx, cy + 4, .5, .5)
                end
                placeLootLayer(entry, tile, 'feixe', grade.h * BEAM_SCALE * (.38 + .62 * smooth(t / .38)), grade.ba * presence, 16 - s / 2, 28 - s / 2, .5, 240 / 256)
            else
                hideLootLayer(entry, 'chao')
                hideLootLayer(entry, 'feixe')
            end
            if entry.marker then
                local lift = .47 + .035 * math.sin(t * 2)
                placeLootLayer(entry, tile, 'gema', grade.gem * BEAM_SCALE, smooth((t - .15) / .4) * (.85 + .05 * math.sin(t * 2)), cx, cy - lift * 32, .5, .5)
            end
            if entry.travel then
                -- the item flies to its finder, only once the server put it
                -- in the backpack
                local p = (g_clock.millis() - entry.travelAt) / 700
                if p >= 0 and p <= 1 then
                    local e = smooth(p)
                    local x = cx + entry.travel.dx * 32 * e
                    local y = cy + entry.travel.dy * 32 * e - math.sin(math.pi * p) * 14
                    placeLootLayer(entry, tile, 'coleta', .7 + .08 * grade.rank, math.sin(math.pi * p), x, y, .5, .5)
                else
                    hideLootLayer(entry, 'coleta')
                end
            end
        end
        entry.event = scheduleEvent(frame, (beamDone and travelDone) and 50 or 30)
    end
    frame()
end

-- the item left the corpse: it flies to whoever took it, if they are on
-- screen, and the finder's card says where it went
function removeLootDrop(data)
    if data.taken then
        local player = g_game.getLocalPlayer()
        if player and data.taken == player:getId() then
            updateLootCard(data.id, data.into == 'pouch' and 'pouch' or 'backpack')
        else
            updateLootCard(data.id, 'taken', data.takenBy)
        end
    end
    local entry = data.id and lootDrops[data.id]
    if not entry then
        return
    end
    local taker = data.taken and g_map.getCreatureById(data.taken)
    if not taker then
        dropLootEffects(data.id)
        return
    end
    local to = taker:getPosition()
    entry.marker = false
    if entry.effects.gema then
        entry.effects.gema:setOpacity(0)
    end
    entry.travel = { dx = to.x - entry.pos.x, dy = to.y - entry.pos.y }
    entry.travelAt = g_clock.millis()
end

-- the corpse was dragged to the next tile: the gem goes with it
function moveLootDrop(data)
    local entry = data.id and lootDrops[data.id]
    if not entry or not data.x then
        return
    end
    local tile = g_map.getTile(entry.pos)
    if tile then
        for _, effect in pairs(entry.effects) do
            tile:detachEffect(effect)
        end
    end
    entry.pos = { x = data.x, y = data.y, z = data.z }
    entry.key = entry.pos.x .. ':' .. entry.pos.y .. ':' .. entry.pos.z
    entry.shift = corpseShift(entry.pos)
end

-- ---------------------------------------------------------------------------
-- the slot the item went to lights up once
-- ---------------------------------------------------------------------------

local function destinationSlot(clientId, gradeKey, openOnly)
    local found
    for _, container in pairs(g_game.getContainers()) do
        if container.itemsPanel then
            for index, item in ipairs(container:getItems()) do
                if item:getId() == clientId and ItemsDatabase.getItemRarityGrade(item) == gradeKey then
                    found = container.itemsPanel:getChildById('item' .. (index - 1)) or found
                end
            end
        end
    end
    -- the backpack is closed: its slot in the inventory (the loot pouch has
    -- none)
    return found or (not openOnly and rootWidget:recursiveGetChildById('backpack')) or nil
end

local function pulseSlot(clientId, gradeKey, openOnly)
    local target = destinationSlot(clientId, gradeKey, openOnly)
    local grade = LOOT_GRADES[gradeKey]
    if not target or not grade then
        return
    end
    local glow = g_ui.createWidget('UIWidget', target)
    glow:setPhantom(true)
    glow:setFocusable(false)
    glow:fill('parent')
    glow:setBackgroundColor(grade.color)
    glow:setOpacity(0)
    local starts = g_clock.millis()
    local function step()
        if glow:isDestroyed() then
            return
        end
        local p = (g_clock.millis() - starts) / 550
        if p >= 1 then
            glow:destroy()
            return
        end
        glow:setOpacity(.45 * math.sin(math.pi * p))
        scheduleEvent(step, 30)
    end
    step()
end

-- ---------------------------------------------------------------------------
-- the finder's card
-- ---------------------------------------------------------------------------

-- the part of the map panel the map is drawn in (it keeps its aspect: the
-- panel can be taller or wider than the map)
local function mapRect()
    local panel = modules.game_interface and modules.game_interface.getMapPanel()
    if not panel then
        return nil
    end
    local rect = panel:getRect()
    local dim = panel:getVisibleDimension()
    if not dim or dim.width <= 0 or dim.height <= 0 then
        return rect
    end
    local tile = math.min(rect.width / dim.width, rect.height / dim.height)
    local width, height = math.floor(dim.width * tile), math.floor(dim.height * tile)
    return {
        x = rect.x + math.floor((rect.width - width) / 2),
        y = rect.y + math.floor((rect.height - height) / 2),
        width = width,
        height = height,
    }
end

-- the free part of the map: the Tasks/Hunts bar lies over its bottom
local function freeBottom(rect)
    local bottom = rect.y + rect.height
    local root = modules.game_interface and modules.game_interface.getRootPanel()
    local bar = root and root:getChildById('brevespanel')
    if bar and bar:isVisible() then
        bottom = math.min(bottom, bar:getY())
    end
    return bottom
end

local function layoutCards()
    local rect = mapRect()
    if not rect then
        return
    end
    local bottom = freeBottom(rect) - 16
    for i = #cards, 1, -1 do
        local card = cards[i]
        if not card.widget:isDestroyed() then
            bottom = bottom - card.widget:getHeight()
            card.widget:setPosition({ x = rect.x + rect.width - card.widget:getWidth() - 16, y = bottom })
            bottom = bottom - 8
        end
    end
end

local function dropCard(card)
    for i, other in ipairs(cards) do
        if other == card then
            table.remove(cards, i)
            break
        end
    end
    removeEvent(card.event)
    if not card.widget:isDestroyed() then
        card.widget:destroy()
    end
    layoutCards()
end

local DESTINATIONS = {
    backpack = 'In your backpack',
    pouch = 'In your loot pouch',
    corpse = 'In the corpse, ready to loot',
    full = 'No room or capacity: it stayed in the corpse',
}
-- the same find on a party member's card
local PARTY_DESTINATIONS = {
    backpack = 'Found by %s, in their backpack',
    corpse = 'Found by %s, in the corpse to loot',
    full = 'Found by %s, it stayed in the corpse',
}

local function destinationText(state, finder, taker)
    if state == 'taken' then
        return tr('Looted by %s', latin1(taker or '?'))
    end
    if finder then
        return tr(PARTY_DESTINATIONS[state] or PARTY_DESTINATIONS.corpse, latin1(finder))
    end
    return tr(DESTINATIONS[state] or DESTINATIONS.corpse)
end

local function fillCard(widget, data, grade)
    widget:setImageSource('/game_raritybonus/images/loot/skin_' .. grade.folder)
    widget.grade:setText(grade.name:upper() .. ' ' .. NUMERALS[grade.rank])
    widget.grade:setColor(grade.color)
    widget.name:setText(latin1(titleCase(data.name)))
    widget.dot:setBackgroundColor(grade.color)
    widget.destination:setText(destinationText(data.state, data.finder))

    local item = Item.create(tonumber(data.clientId) or 0, 1)
    if item then
        local elements = type(data.elements) == 'table' and data.elements or {}
        local tooltip = '#rarity:' .. data.grade
        if #elements > 0 then
            tooltip = tooltip .. '\n#elements:' .. table.concat(elements, ',')
        end
        item:setTooltip(tooltip)
        local shader = ItemsDatabase.itemRarity[data.grade] and ('Rarity - ' .. titleCase(data.grade))
        if shader then
            item:setShader(shader)
        end
        widget.icon:setItem(item)
        ItemsDatabase.setItemRarityFrame(widget.icon, item)
    end

    -- two columns, three rows
    for i, bonus in ipairs(type(data.bonuses) == 'table' and data.bonuses or {}) do
        if i > 6 then
            break
        end
        local label = g_ui.createWidget('LootFindText', widget.bonuses)
        local value = tonumber(bonus.value) or 0
        local text = string.format('+%s%s %s', math.floor(value) == value and tostring(math.floor(value)) or string.format('%.1f', value), bonus.unit or '', bonus.label or '')
        if bonus.perfect then
            text = text .. '  ' .. tr('perfect')
            label:setColor('#ffe7a6')
        end
        label:setText(latin1(text))
        label:addAnchor(AnchorTop, 'parent', AnchorTop)
        label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        label:setMarginTop(math.floor((i - 1) / 2) * 17)
        label:setMarginLeft(((i - 1) % 2) * 168)
    end
end

function showLootCard(data)
    local grade = LOOT_GRADES[data.grade]
    if not grade then
        return
    end
    local widget = g_ui.createWidget('LootFindCard', rootWidget)
    fillCard(widget, data, grade)
    widget:setOpacity(0)
    local card = { widget = widget, rank = grade.rank, starts = g_clock.millis(), dropId = data.dropId, clientId = tonumber(data.clientId), grade = data.grade, own = not data.finder }
    table.insert(cards, card)
    -- two at most: the lowest grade goes (the older of two alike, the new
    -- card itself when it is the lowest), so a stream of Communis never
    -- pushes a better find away
    if #cards > 2 then
        local lowest = #cards
        for i = #cards - 1, 1, -1 do
            if cards[i].rank <= cards[lowest].rank then
                lowest = i
            end
        end
        dropCard(cards[lowest])
        if widget:isDestroyed() then
            return
        end
    end
    layoutCards()

    local function step()
        if widget:isDestroyed() then
            return
        end
        local t = (g_clock.millis() - card.starts) / 1000
        if t >= CARD_SHOWS then
            dropCard(card)
            return
        end
        widget:setOpacity(smooth((t - .25) / .18) * (1 - smooth((t - 5.05) / .3)))
        card.event = scheduleEvent(step, 30)
    end
    step()

    if data.state == 'backpack' and card.own then
        scheduleEvent(function()
            pulseSlot(tonumber(data.clientId), data.grade)
        end, 1250)
    end
end

-- the item of a card on screen left the corpse: into this player's backpack
-- or loot pouch (auto loot, or they looted it), or someone else took it
function updateLootCard(dropId, state, taker)
    for _, card in ipairs(cards) do
        if card.dropId == dropId and not card.widget:isDestroyed() then
            card.widget.destination:setText(destinationText(state, nil, taker))
            if state == 'backpack' or state == 'pouch' then
                scheduleEvent(function()
                    pulseSlot(card.clientId, card.grade, state == 'pouch')
                end, 700)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- the Mythicus banner, one at a time
-- ---------------------------------------------------------------------------

local function nextBanner()
    if banner or #bannerQueue == 0 then
        return
    end
    local data = table.remove(bannerQueue, 1)
    local rect = mapRect()
    if not rect then
        return
    end
    local widget = g_ui.createWidget('LootFindBanner', rootWidget)
    widget.title:setText(latin1(tr('A Mythicus find')):upper())
    widget.line:setText(latin1(tr('%s found %s', data.finder or '', titleCase(data.name))))
    widget.note:setText(latin1(tr('A find for the history of the server.')))
    widget:setPosition({ x = rect.x + math.floor((rect.width - widget:getWidth()) / 2), y = rect.y + 12 })
    widget:setOpacity(0)
    banner = { widget = widget, starts = g_clock.millis() }
    local current = banner
    local function step()
        if widget:isDestroyed() or banner ~= current then
            return
        end
        local t = (g_clock.millis() - current.starts) / 1000
        if t >= BANNER_SHOWS then
            widget:destroy()
            banner = nil
            nextBanner()
            return
        end
        widget:setOpacity(smooth((t - .45) / .28) * (1 - smooth((t - 5.3) / .4)))
        current.event = scheduleEvent(step, 30)
    end
    step()
end

function showLootBanner(data)
    local key = tostring(data.finder) .. '|' .. tostring(data.name)
    for _, queued in ipairs(bannerQueue) do
        if queued.key == key then
            return
        end
    end
    data.key = key
    table.insert(bannerQueue, data)
    nextBanner()
end

function clearLootFinds()
    for id in pairs(lootDrops) do
        dropLootEffects(id)
    end
    for i = #cards, 1, -1 do
        dropCard(cards[i])
    end
    bannerQueue = {}
    if banner then
        removeEvent(banner.event)
        if not banner.widget:isDestroyed() then
            banner.widget:destroy()
        end
        banner = nil
    end
end
