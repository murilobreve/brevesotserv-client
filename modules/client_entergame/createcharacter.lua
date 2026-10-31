-- Character creation on the character list, like Path of Exile: a card per
-- vocation with the look the character starts with, then the sex, the town
-- (when there is more than one) and the name. The site creates it
-- (plugins/brevesot/create-character.php of the server: MyAAC's own name
-- rules, sample characters and characters per account limit) and the list
-- loads again with the new character chosen, ready to play.
CreateCharacter = {}

local window = nil
local options = nil
local cards = {}
local chosen = { vocation = nil, sex = 1, town = nil }
local request = 0
local busy = false

local OPTIONS_TIMEOUT = 5
-- creating a character takes longer on the site than HTTP.timeout (2 s)
local CREATE_TIMEOUT = 15

-- the card text of each vocation (ids of data/XML/vocations.xml)
local VOCATION_TEXT = {
    [1] = {
        role = 'Fire, energy and death magic',
        text = 'The strongest attack spells of the game, cast from afar, and the least health. Kills fast, dies fast.'
    },
    [2] = {
        role = 'Ice and earth magic, healer',
        text = 'Attacks from afar with ice and earth and heals better than anyone. The one who keeps the party alive.'
    },
    [3] = {
        role = 'Bows, crossbows, holy magic',
        text = 'Hits hard from a distance with arrows, bolts and spears, with holy magic and a good defence.'
    },
    [4] = {
        role = 'Swords, axes and clubs',
        text = 'The front line: the most health and armour, holds the monsters so the party can hit. Easy to start with.'
    },
    [9] = {
        role = 'Fists and harmony',
        text = 'Martial artist: quick combos build harmony that powers the strongest blows. Fights up close.'
    },
}

local function endpoint()
    local site = Services and Services.website or ''
    if site == '' then
        return nil
    end
    return site:gsub('/+$', '') .. '/plugins/brevesot/create-character.php'
end

local function language()
    local locale = modules.client_locales and modules.client_locales.getCurrentLocale and modules.client_locales.getCurrentLocale()
    local name = locale and locale.name or 'pt'
    return name:sub(1, 2) == 'en' and 'en' or 'pt'
end

-- the fonts draw one glyph per byte (Latin-1); the site's JSON is UTF-8
local function latin1(text)
    return (tostring(text or ''):gsub('[\194\195][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        return string.char((a - 194) * 64 + b)
    end))
end

-- a POST to the site with the account in use; the answer comes to callback
-- as a table, or nil when the site did not answer
local function post(body, timeout, callback)
    local url = endpoint()
    if not url or not g_http or not g_http.post or not G.account or G.account == '' or not G.password then
        callback(nil)
        return
    end
    body.password = G.password
    if G.account:find('@', 1, true) then
        body.email = G.account
    else
        body.accountname = G.account
    end
    body.lang = language()
    request = request + 1
    local id = request
    local answered = false
    local function finish(answer)
        if answered or id ~= request or not window then
            return
        end
        answered = true
        callback(answer)
    end
    local operation = g_http.post(url, json.encode(body), timeout, false, false)
    if not operation or operation < 0 then
        finish(nil)
        return
    end
    HTTP.operations[operation] = {
        type = 'post',
        url = url,
        callback = function(data, err)
            local ok, answer = false, nil
            if not err then
                ok, answer = pcall(json.decode, data or '')
            end
            finish(ok and type(answer) == 'table' and answer or nil)
        end
    }
    -- an answer that never comes is a site that did not answer
    scheduleEvent(function()
        finish(nil)
    end, (timeout + 3) * 1000)
end

local function child(id)
    return window and window:recursiveGetChildById(id)
end

local function setError(text)
    local label = child('errorLabel')
    if label then
        label:setText(text or '')
    end
end

local function updateCreateButton()
    local button = child('createButton')
    if not button then
        return
    end
    local full = options and (tonumber(options.count) or 0) >= (tonumber(options.max) or 0)
    button:setEnabled(options ~= nil and not busy and not full and chosen.vocation ~= nil)
    button:setText(busy and tr('Creating...') or tr('Create'))
end

local function lookOf(vocation)
    local colors = options and options.colors or {}
    local outfit = vocation.outfit or {}
    return {
        type = chosen.sex == 0 and (tonumber(outfit.female) or 136) or (tonumber(outfit.male) or 128),
        head = tonumber(colors.head) or 95,
        body = tonumber(colors.body) or 113,
        legs = tonumber(colors.legs) or 39,
        feet = tonumber(colors.feet) or 115,
        addons = 0
    }
end

-- the looks follow the sex; the chosen card walks in place
local function refreshCards()
    for _, card in ipairs(cards) do
        local selected = card.vocation.id == chosen.vocation
        card:setChecked(selected)
        card:getChildById('name'):setOn(selected)
        local preview = card:getChildById('outfit')
        preview:setOutfit(lookOf(card.vocation))
        local creature = preview:getCreature()
        if creature then
            creature:setDirection(Directions and Directions.South or 2)
            creature:setStaticWalking(selected and 1000 or 0)
        end
    end
    local info = child('vocationInfo')
    local text = VOCATION_TEXT[chosen.vocation]
    if info then
        info:setText(text and tr(text.text) or '')
    end
    local male, female = child('sexMale'), child('sexFemale')
    if male and female then
        male:setChecked(chosen.sex == 1)
        female:setChecked(chosen.sex == 0)
    end
    updateCreateButton()
end

local function fill()
    local panel = child('cards')
    if not panel or not options then
        return
    end
    panel:destroyChildren()
    cards = {}
    for _, vocation in ipairs(options.vocations or {}) do
        local card = g_ui.createWidget('CreateCharacterCard', panel)
        card.vocation = vocation
        card:getChildById('name'):setText(latin1(vocation.name))
        local text = VOCATION_TEXT[tonumber(vocation.id)]
        card:getChildById('role'):setText(text and tr(text.role) or '')
        card.onClick = function()
            chosen.vocation = vocation.id
            refreshCards()
        end
        cards[#cards + 1] = card
    end
    if not chosen.vocation and cards[1] then
        chosen.vocation = cards[1].vocation.id
    end

    -- town: a list when there is a choice, its name when there is one
    local towns = options.towns or {}
    local townBox, townName = child('townBox'), child('townName')
    townBox:clearOptions()
    if #towns > 1 then
        for _, town in ipairs(towns) do
            townBox:addOption(latin1(town.name), town.id)
        end
        townBox.onOptionChange = function(_, _, data)
            chosen.town = data
        end
        chosen.town = towns[1].id
        townBox:setVisible(true)
        townName:setVisible(false)
    else
        chosen.town = towns[1] and towns[1].id or nil
        townBox:setVisible(false)
        townName:setVisible(true)
        townName:setText(towns[1] and latin1(towns[1].name) or '-')
    end

    local nameMin, nameMax = tonumber(options.nameMin) or 3, tonumber(options.nameMax) or 21
    child('nameEdit'):setMaxLength(nameMax)
    child('nameHint'):setText(tr('Letters and spaces, %d to %d characters.', nameMin, nameMax))

    local count, max = tonumber(options.count) or 0, tonumber(options.max) or 0
    child('countLabel'):setText(tr('Characters on the account: %d/%d', count, max))
    if count >= max then
        setError(tr('Your account already has the most characters it can have (%d). Delete one on the site to create another.', max))
    end
    child('loading'):setVisible(false)
    refreshCards()
    child('nameEdit'):focus()
end

local function loadOptions()
    options = nil
    child('loading'):setText(tr('Loading...'))
    child('loading'):setVisible(true)
    updateCreateButton()
    post({ action = 'options' }, OPTIONS_TIMEOUT, function(answer)
        if not answer or not answer.vocations then
            child('loading'):setText(tr('The site did not answer. Try again in a moment.'))
            return
        end
        options = answer
        fill()
    end)
end

function CreateCharacter.isAvailable()
    return endpoint() ~= nil and G.account ~= nil and G.account ~= ''
end

function CreateCharacter.show()
    if window then
        window:raise()
        window:focus()
        return
    end
    window = g_ui.displayUI('createcharacter')
    cards = {}
    busy = false
    chosen.vocation = nil
    chosen.sex = 1
    chosen.town = nil
    window:raise()
    window:focus()
    refreshCards()
    loadOptions()
end

function CreateCharacter.hide()
    request = request + 1
    if window then
        window:destroy()
        window = nil
    end
    cards = {}
    options = nil
    busy = false
end

function CreateCharacter.isVisible()
    return window ~= nil
end

function CreateCharacter.setSex(sex)
    chosen.sex = sex
    refreshCards()
end

function CreateCharacter.clearError()
    if not busy then
        setError('')
    end
end

function CreateCharacter.submit()
    if not window or busy or not options then
        return
    end
    local button = child('createButton')
    if button and not button:isEnabled() then
        return
    end
    local name = child('nameEdit'):getText():trim()
    if name == '' then
        setError(tr('Type a name for the character.'))
        child('nameEdit'):focus()
        return
    end
    busy = true
    setError('')
    updateCreateButton()
    post({
        action = 'create',
        name = name,
        sex = chosen.sex,
        vocation = chosen.vocation,
        town = chosen.town
    }, CREATE_TIMEOUT, function(answer)
        busy = false
        if not answer then
            -- the site may have created it all the same: the list tells
            setError(tr('The site did not answer. Loading the list again to check...'))
            updateCreateButton()
            scheduleEvent(function()
                CreateCharacter.hide()
                CharacterList.reload()
            end, 1500)
            return
        end
        if not answer.ok then
            setError(latin1(answer.error or tr('Could not create the character.')))
            updateCreateButton()
            if answer.field == 'name' then
                child('nameEdit'):focus()
            end
            return
        end
        CreateCharacter.hide()
        CharacterList.reload(latin1(answer.name or name))
    end)
end

function CreateCharacter.terminate()
    CreateCharacter.hide()
end
