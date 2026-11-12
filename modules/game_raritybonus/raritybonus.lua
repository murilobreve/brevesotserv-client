-- Rarity: the extended opcode 123 (scripts/rarity/bonus_window.lua and the
-- loot / revive senders), the Rarity XP shop and the rare monster's revival.
-- The window itself, the Forja de Raridade, is forge.lua / forge.otui.

local OPCODE = 123

local featureButton
local refreshEvent
local xpShop -- the Rarity XP packs and the balances (buyRarityXp)
local shopWindow
local fillShop

local send = function(request) Forge.send(request) end
local confirm = function(title, message, callback) Forge.confirm(title, message, callback) end

function showXpBadge(xp)
    if modules.game_brevespanel and modules.game_brevespanel.setFeatureState then
        -- the row sits under the Rarity title: a short name leaves room for the badge
        modules.game_brevespanel.setFeatureLabel('bonus', tr('Forge'), '#dfdfdf')
        modules.game_brevespanel.setFeatureState('bonus', tr('%d XP', xp), '#e0c060')
    end
end

-- A rare monster rising from its corpse (art and motion: the design kit
-- "Renascimento, quatro presencas"). Each tier is a material coming alive: a
-- veil of mist (Pale), a flower of ash (Ashen), a crown of glass (Obsidian),
-- an eclipse (Lord of Death). Three textures follow the corpse's tile: the
-- floor under the body and every creature, the air around it, and the burst
-- when the monster stands up. The living monster's aura is an attached effect
-- the server puts on it (game_attachedeffects, ids 21 to 24). The server sends
-- the tier and the time left (scripts/rarity/revive.lua).
local REVIVE_FOLDERS = { pale = 'pale', ashen = 'ashen', obsidian = 'obsidian', deathlord = 'lord-of-death' }
local REVIVE_LAYERS = { chao = 1, ar = 2, eclosao = 3 }
local REVIVE_EFFECT_BASE = 3000
local DESIGN_REVIVE = 7       -- the curves are drawn for a 7 s wait...
local DESIGN_SETTLE = 0.9     -- ...and 0.9 s of arrival
-- sizes (side of the texture, in tiles), peak opacities, how far the air lifts
-- (the kit's sizes; the game draws the whole composition REVIVE_SCALE times
-- bigger around the corpse, and stronger than the kit so it reads from across
-- the screen). `light`: the colour (8-bit, as the map's lights) the rising
-- body glows with, which shows in the dark of a cave.
local REVIVE_SCALE = 2.4
local REVIVE_MOTION = {
    pale = { tier = 1, g = 1.9, a = 2.15, r = 2.45, go = .64, ao = .82, ro = .74, lift = .20, light = 179 },
    ashen = { tier = 2, g = 2.2, a = 2.45, r = 2.7, go = .76, ao = .88, ro = .86, lift = .16, light = 199 },
    obsidian = { tier = 3, g = 2.45, a = 2.8, r = 3.05, go = .80, ao = .94, ro = .92, lift = .20, light = 125 },
    deathlord = { tier = 4, g = 2.85, a = 3.15, r = 3.35, go = .88, ao = .97, ro = .90, lift = .16, light = 152 },
}
local REVIVE_LIGHT = 7 -- the glow's strength at its brightest (map lights go up to about 10)
-- the corpse's heart: a double beat (lub-dub) that quickens from BEAT_FROM
-- to BEAT_TO beats a second as the monster gets ready to stand up; on each
-- beat the floor flares and swells and the air brightens
local BEAT_FROM, BEAT_TO = 0.8, 2.0
local BEAT_FLOOR, BEAT_SWELL, BEAT_AIR = 0.55, 0.10, 0.30
local revivals = {}

local function clamp01(x)
    return math.max(0, math.min(1, x))
end

local function smooth(x)
    x = clamp01(x)
    return x * x * (3 - 2 * x)
end

local function reviveEffectId(tierKey, layer)
    return REVIVE_EFFECT_BASE + REVIVE_MOTION[tierKey].tier * 10 + REVIVE_LAYERS[layer]
end

-- the floor goes in the ground-border pass, under corpses and every creature;
-- the air and the burst over them
local function registerReviveTextures()
    for tierKey, folder in pairs(REVIVE_FOLDERS) do
        for layer in pairs(REVIVE_LAYERS) do
            local id = reviveEffectId(tierKey, layer)
            local path = string.format('/game_raritybonus/images/revive/%s/revive_%s_%s', folder, folder, layer)
            -- a module reload finds them still registered
            g_attachedEffects.remove(id)
            local effect = g_attachedEffects.registerByImage(id, 'Revive ' .. folder .. ' ' .. layer, path, true)
            if effect then
                effect:setPermanent(true)
                effect:setOnTop(layer ~= 'chao')
                effect:setDrawOrder(layer == 'chao' and 1 or 3)
            end
        end
    end
end

local function unregisterReviveTextures()
    for tierKey in pairs(REVIVE_FOLDERS) do
        for layer in pairs(REVIVE_LAYERS) do
            g_attachedEffects.remove(reviveEffectId(tierKey, layer))
        end
    end
end

-- 0..1: how much of a heartbeat is in the corpse at design time t
local function heartbeat(t)
    local beats = BEAT_FROM * t + (BEAT_TO - BEAT_FROM) * t * t / (2 * DESIGN_REVIVE)
    local f = beats - math.floor(beats)
    local lub, dub = (f - .08) / .09, (f - .34) / .10
    return math.min(1, math.exp(-lub * lub) + .6 * math.exp(-dub * dub))
end

-- The designer's curves: which layers show at design time t (seconds, 0 = the
-- death, 7 = the monster stands up), how big, how opaque, how far up, and
-- the glow of the air.
local function reviveLayers(t, tierKey)
    local c = REVIVE_MOTION[tierKey]
    local out = {}
    local function add(layer, size, opacity, lift)
        out[layer] = { size = size, opacity = clamp01(opacity), lift = lift or 0 }
    end
    if t < DESIGN_REVIVE then
        local p = clamp01(t / DESIGN_REVIVE)
        local entry = smooth(t / .85)
        local tension = smooth((t - 5.5) / 1.5)
        local breath = math.sin(2 * math.pi * (.35 * t + .4 * t * t / 14))
        local beat = heartbeat(t) * entry
        add('chao', c.g * (.66 + .34 * smooth(p)) * (1 + BEAT_SWELL * beat), c.go * entry * (.60 + .40 * p) * (1 + .035 * breath) * (1 + BEAT_FLOOR * beat))
        local gather = smooth((t - .55) / 5.2)
        local scale = .72 + .28 * gather
        local lift = c.lift * (.3 + .7 * gather)
        if tierKey == 'pale' then
            scale = scale * (1 + .035 * breath)
            lift = lift + .035 * math.sin(t * 1.3)
        elseif tierKey == 'ashen' then
            scale = scale * (1 + .02 * math.sin(t * 1.6))
            lift = lift + .045 * gather
        elseif tierKey == 'obsidian' then
            scale = scale * (1 - .10 * tension)
            lift = lift + .025 * math.sin(t * 1.1)
        else
            scale = scale * (1 - .06 * tension)
            lift = lift + .06 * tension
        end
        add('ar', c.a * scale, c.ao * entry * gather * (.68 + .32 * tension) * (1 + BEAT_AIR * beat), lift)
        out.ar.light = REVIVE_LIGHT * (.25 + .45 * p + .3 * beat) * entry
    else
        local q = clamp01((t - DESIGN_REVIVE) / DESIGN_SETTLE)
        local exit = 1 - smooth(q)
        local eclipse = tierKey == 'deathlord'
        -- Pale, Ashen and Obsidian open out; the Lord's shadow implodes into it
        add('chao', c.g * (eclipse and (1 - .58 * smooth(q)) or (1 + .08 * q)), c.go * exit)
        add('ar', c.a * (1 - .1 * q), c.ao * exit, c.lift + .08 * q)
        add('eclosao', c.r * (eclipse and (1 - .7 * smooth(q)) or (.74 + .26 * smooth(q))), c.ro * math.sin(math.pi * q), eclipse and 0 or .18 * q)
        out.ar.light = REVIVE_LIGHT * (1 + .3 * math.sin(math.pi * q)) * exit
    end
    return out
end

-- the server's real delay maps onto the 7 s of the curves; after the rise the
-- clock runs in real seconds
local function designTime(elapsed, delay)
    if elapsed < delay then
        return elapsed / delay * DESIGN_REVIVE
    end
    return DESIGN_REVIVE + (elapsed - delay) / 1000
end

-- a corpse that is rising right now (lootfind.lua leaves it its floor)
function reviveActiveAt(key)
    return revivals[key] ~= nil
end

local function dropRevive(key)
    local entry = revivals[key]
    revivals[key] = nil
    if not entry then
        return
    end
    removeEvent(entry.event)
    local tile = g_map.getTile(entry.pos)
    for _, effect in pairs(entry.effects) do
        if tile then
            tile:detachEffect(effect)
        end
    end
end

-- a texture of `size` tiles centred on the tile, `lift` tiles up (an attached
-- effect is drawn at the tile's corner minus its offset, in 32 px units)
local function placeLayer(entry, tile, layer, state)
    local effect = entry.effects[layer]
    if not effect then
        -- getById hands out a copy of the registered effect
        effect = g_attachedEffects.getById(reviveEffectId(entry.tier, layer))
        if not effect then
            return
        end
        entry.effects[layer] = effect
    end
    local side = math.max(1, math.floor(state.size * REVIVE_SCALE * 32 + 0.5))
    local half = math.floor(side / 2) - 16
    effect:setSize({ width = side, height = side })
    effect:setOffset(half + entry.shift, half + entry.shift + math.floor(state.lift * REVIVE_SCALE * 32 + 0.5))
    effect:setOpacity(state.opacity)
    if state.light then
        effect:setLight({ intensity = math.max(0, math.floor(state.light + 0.5)), color = REVIVE_MOTION[entry.tier].light })
    end
    -- the tile is rebuilt when it leaves the screen and comes back
    if not tile:getAttachedEffectById(effect:getId()) then
        tile:attachEffect(effect)
    end
end

local function showRevive(data)
    if not data.x or not tonumber(data.ms) or not REVIVE_MOTION[data.tier] then
        return
    end
    local pos = { x = data.x, y = data.y, z = data.z }
    local key = pos.x .. ':' .. pos.y .. ':' .. pos.z
    dropRevive(key)
    local entry = {
        pos = pos,
        tier = data.tier,
        delay = math.max(1, tonumber(data.ms)),
        starts = g_clock.millis(),
        effects = {},
        shift = 0,
    }
    -- a 2x2 corpse (a dragon's) is drawn up and left of its tile: centre on it
    local tile = g_map.getTile(pos)
    local corpse = tile and tile:getTopUseThing()
    if corpse and corpse:isItem() then
        local thingType = g_things.getThingType(corpse:getId(), ThingCategoryItem)
        if thingType then
            entry.shift = (math.max(1, math.min(2, math.max(thingType:getWidth(), thingType:getHeight()))) - 1) * 16
        end
    end
    revivals[key] = entry

    local function frame()
        if revivals[key] ~= entry then
            return
        end
        local t = designTime(g_clock.millis() - entry.starts, entry.delay)
        if t >= DESIGN_REVIVE + DESIGN_SETTLE then
            dropRevive(key)
            return
        end
        local tile = g_map.getTile(pos)
        if tile then
            local layers = reviveLayers(t, entry.tier)
            for layer in pairs(REVIVE_LAYERS) do
                local state = layers[layer]
                if state and state.opacity > 0.005 then
                    placeLayer(entry, tile, layer, state)
                elseif entry.effects[layer] then
                    entry.effects[layer]:setOpacity(0)
                end
            end
        end
        entry.event = scheduleEvent(frame, 30)
    end
    frame()
end


local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    local action = data.action
    if action == 'drop' then
        showLootDrop(data)
    elseif action == 'dropgone' then
        removeLootDrop(data)
    elseif action == 'dropmove' then
        moveLootDrop(data)
    elseif action == 'find' then
        showLootCard(data)
    elseif action == 'banner' then
        showLootBanner(data)
    elseif action == 'revive' then
        showRevive(data)
    elseif action == 'xp' then
        -- the balance, after every change: shown on the Mythos bar; past a
        -- multiple of 50 a notice offers the window without opening it
        local xp = tonumber(data.xp) or 0
        showXpBadge(xp)
        Forge.onXp(xp)
        if shopWindow and shopWindow:isVisible() then
            fillShop()
        end
        local window = Forge.window()
        if data.ready and not (window and window:isVisible()) and modules.game_brevespanel then
            modules.game_brevespanel.notify('bonus',
                tr('You have %d Rarity XP! Use it to reforge your rarity items.', xp),
                tr('Open'))
        end
    elseif action == 'bonuses' then
        local window = Forge.window()
        if not window then
            return
        end
        showXpBadge(tonumber(data.rarityXp) or Forge.xp())
        xpShop = type(data.shop) == 'table' and data.shop or xpShop
        Forge.showBank(data)
        Forge.onBonuses(data)
        if shopWindow and shopWindow:isVisible() then
            fillShop()
            -- the shop says how the purchase went, where it was made
            local result = data.result
            local code = type(result) == 'table' and result.code
            if code == 'bought' or code == 'coins' or code == 'points' or code == 'pack' then
                shopWindow.status:setText(window.bottomBar.status:getText())
                shopWindow.status:setColor(data.ok == false and '#ff6464' or '#7fd35a')
            end
        end
        if not window:isVisible() then
            window:show()
            window:raise()
            window:focus()
            if featureButton then
                featureButton:setOn(true)
            end
        end
    end
end

-- the Store on its Rarity category, where Rarity XP is sold
-- ---------------------------------------------------------------------------
-- Rarity XP shop, right in the window (server: xpShop in bonus_window.lua):
-- the Store's packs for Mythos Coins and the task shop's for Hunt Points.
-- Short of coins, a pack opens the site's coins page instead.
-- ---------------------------------------------------------------------------

local function openCoinsSite()
    local url = Services and Services.getCoinsUrl or ''
    if url ~= '' then
        g_platform.openUrl(url)
    end
end

local function packPrice(pack)
    return pack.currency == 'coins' and tr('%d coins', pack.price) or tr('%d Hunt Points', pack.price)
end

fillShop = function()
    if not shopWindow or not xpShop then
        return
    end
    local balances = { coins = tonumber(xpShop.coins) or 0, points = tonumber(xpShop.points) or 0 }
    shopWindow.balance:setText(tr('You have %d Rarity XP.', Forge.xp()))
    shopWindow.coinsHave:setText(tr('you have %d', balances.coins))
    shopWindow.pointsHave:setText(tr('you have %d', balances.points))
    shopWindow.coinsList:destroyChildren()
    shopWindow.pointsList:destroyChildren()
    -- the smallest pack's price per point: the others say how much less
    local baseRate = {}
    for _, pack in ipairs(xpShop.packs or {}) do
        local rate = pack.price / math.max(1, pack.xp)
        baseRate[pack.currency] = math.max(baseRate[pack.currency] or 0, rate)
    end
    local counts = { coins = 0, points = 0 }
    for _, pack in ipairs(xpShop.packs or {}) do
        local coins = pack.currency == 'coins'
        local list = coins and shopWindow.coinsList or shopWindow.pointsList
        counts[pack.currency] = (counts[pack.currency] or 0) + 1
        local row = g_ui.createWidget('RarityXpPack', list)
        row.amount:setText(tr('%d Rarity XP', pack.xp))
        local saving = math.floor((1 - (pack.price / math.max(1, pack.xp)) / baseRate[pack.currency]) * 100 + 0.5)
        row.note:setText(saving >= 1 and tr('%d%% cheaper', saving) or '')
        local have = balances[pack.currency] or 0
        local enough = have >= pack.price
        row.buy:setText(packPrice(pack))
        if coins then
            -- short of coins: the button still works, and opens the site
            row.buy:setTooltip(enough and tr('Buy %d Rarity XP for %d Mythos Coins.', pack.xp, pack.price)
                or tr('You have %d Mythos Coins, %d short. Click to get coins on the site.', have, pack.price - have))
            row.buy.onClick = function()
                if not enough then
                    confirm(tr('Mythos Coins'), tr('This pack costs %d Mythos Coins and you have %d.\n\nOpen the site to get more coins?', pack.price, have), openCoinsSite)
                    return
                end
                confirm(tr('Buy Rarity XP'), tr('Buy %d Rarity XP for %d Mythos Coins?', pack.xp, pack.price), function()
                    send({ action = 'buyXp', pack = pack.id })
                end)
            end
        else
            row.buy:setEnabled(enough)
            row.buy:setTooltip(enough and tr('Buy %d Rarity XP for %d Hunt Points.', pack.xp, pack.price)
                or tr('You have %d Hunt Points, %d short. The daily task and the Hunter\'s Trail give more.', have, pack.price - have))
            row.buy.onClick = function()
                confirm(tr('Buy Rarity XP'), tr('Buy %d Rarity XP for %d Hunt Points?', pack.xp, pack.price), function()
                    send({ action = 'buyXp', pack = pack.id })
                end)
            end
        end
    end
    -- each list as tall as its packs, the window as tall as both
    local rowHeight = 28
    local coinsHeight = math.max(1, counts.coins) * rowHeight + 4
    local pointsHeight = math.max(1, counts.points) * rowHeight + 4
    shopWindow.coinsList:setHeight(coinsHeight)
    shopWindow.pointsList:setHeight(pointsHeight)
    shopWindow.pointsTitle:setVisible(counts.points > 0)
    shopWindow.pointsHave:setVisible(counts.points > 0)
    shopWindow.pointsList:setVisible(counts.points > 0)
    shopWindow:setHeight(30 + 16 + (10 + 14 + 4 + coinsHeight) + (counts.points > 0 and (10 + 14 + 4 + pointsHeight) or 0) + 8 + 16 + 12 + 22 + 16)
end

function buyRarityXp()
    -- a server without the shop: the Store, as before
    if not xpShop then
        if modules.game_store and modules.game_store.openCategory then
            modules.game_store.openCategory('Rarity', 'Rarity XP')
        elseif modules.game_store and modules.game_store.toggle then
            modules.game_store.toggle()
        end
        return
    end
    if not shopWindow then
        shopWindow = g_ui.createWidget('RarityXpShop', rootWidget)
        shopWindow.siteButton.onClick = openCoinsSite
    end
    shopWindow.status:setText('')
    fillShop()
    shopWindow:show()
    shopWindow:raise()
    shopWindow:focus()
end


function request()
    local window = Forge.window()
    if window then
        window.bottomBar.status:setText('')
    end
    send({ action = 'open' })
end

function hide()
    local window = Forge.window()
    if not window then
        return
    end
    -- the cards or the needle still moving: the answer would be lost
    if Forge.busy() then
        return
    end
    window:hide()
    Forge.closeConfirm()
    if featureButton then
        featureButton:setOn(false)
    end
end

function toggle()
    local window = Forge.window()
    if window and window:isVisible() then
        hide()
    else
        request()
    end
end

-- equipment changed while the window is open: ask again
local function onInventoryChange(player, slot, item, oldItem)
    local window = Forge.window()
    if not window or not window:isVisible() then
        return
    end
    -- the same item with only its count changed (an arrow shot, a charge
    -- used): its bonuses are the same
    if item and oldItem and item:getId() == oldItem:getId() and item:getCountOrSubType() ~= oldItem:getCountOrSubType() then
        return
    end
    if refreshEvent then
        removeEvent(refreshEvent)
    end
    refreshEvent = scheduleEvent(function()
        refreshEvent = nil
        send({ action = 'open' })
    end, 500)
end

local function onGameStart()
    if not featureButton and modules.game_brevespanel then
        featureButton = modules.game_brevespanel.addFeature('bonus', toggle)
    end
    -- the Rarity XP balance for the Mythos bar: the server sends it at login,
    -- but not when the game starts on a character still online
    scheduleEvent(function()
        if g_game.isOnline() then
            send({ action = 'xp' })
        end
    end, g_game.spreadDelay and g_game.spreadDelay(4000, 10000) or 1500)
end

local function onGameEnd()
    Forge.reset()
    if shopWindow then
        shopWindow:hide()
    end
    for key in pairs(revivals) do
        dropRevive(key)
    end
    clearLootFinds()
    local window = Forge.window()
    if window then
        window:hide()
    end
    if featureButton then
        featureButton:setOn(false)
    end
end

function init()
    registerReviveTextures()
    registerLootTextures()
    g_ui.importStyle('lootfind')
    g_ui.importStyle('shop')
    Forge.create()
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    connect(LocalPlayer, { onInventoryChange = onInventoryChange })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    disconnect(LocalPlayer, { onInventoryChange = onInventoryChange })
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
    end
    if featureButton then
        featureButton:destroy()
        featureButton = nil
    end
    if shopWindow then
        shopWindow:destroy()
        shopWindow = nil
    end
    Forge.destroy()
    for key in pairs(revivals) do
        dropRevive(key)
    end
    unregisterReviveTextures()
    clearLootFinds()
    unregisterLootTextures()
end
