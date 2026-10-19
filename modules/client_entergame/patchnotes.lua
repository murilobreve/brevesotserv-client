-- Patch notes of the site (plugins/brevesot/data/patches.php, served as JSON
-- by plugins/brevesot/patches.php). The character list gets a "Patch notes"
-- button with a "!". When a patch is new on this account the window opens by
-- itself and cannot be closed before entering the game; closing it in game
-- marks the patch as read and the "!" goes away.
PatchNotes = {}

local SEEN_KEY = 'patchnotes-seen-'

local patchWindow = nil
local button = nil
local account = nil
local notes = nil
local request = 0
local forced = false

local function endpoint()
    local site = Services and Services.website or ''
    if site == '' then
        return nil
    end
    return site:gsub('/+$', '') .. '/plugins/brevesot/patches.php'
end

-- the fonts draw one glyph per byte (Latin-1); the site's JSON is UTF-8
local function latin1(text)
    return (tostring(text or ''):gsub('[\194\195][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        return string.char((a - 194) * 64 + b)
    end))
end

local function language()
    local locale = modules.client_locales and modules.client_locales.getCurrentLocale and modules.client_locales.getCurrentLocale()
    local name = locale and locale.name or 'pt'
    return name:sub(1, 2) == 'en' and 'en' or 'pt'
end

local function seenKey()
    return SEEN_KEY .. (account or ''):lower():gsub('[^%w]', '_')
end

local function updateBadge()
    if not button or button:isDestroyed() then
        return
    end
    button:setVisible(notes ~= nil)
    local badge = button:getChildById('patchNotesBadge')
    if badge then
        local unseen = notes ~= nil and (tonumber(notes.latest) or 0) > g_settings.getNumber(seenKey(), 0)
        badge:setText('!')
        badge:setVisible(unseen)
        button:setTooltip(unseen and tr('A new patch is out. Click to see what changed.') or tr('What changed in each patch.'))
    end
end

local function fill()
    local list = patchWindow and patchWindow:getChildById('notes')
    if not list or not notes then
        return
    end
    list:destroyChildren()
    local lang = language()
    for _, patch in ipairs(notes.patches or {}) do
        local title = g_ui.createWidget('PatchNoteTitle', list)
        title:setText(latin1(patch.title and (patch.title[lang] or patch.title.pt)))
        local date = g_ui.createWidget('PatchNoteDate', list)
        local y, m, d = tostring(patch.date or ''):match('^(%d+)%-(%d+)%-(%d+)$')
        date:setText(tr('Patch %d', tonumber(patch.id) or 0) .. (y and (lang == 'en' and (', ' .. m .. '/' .. d .. '/' .. y) or (', ' .. d .. '/' .. m .. '/' .. y)) or ''))
        for _, item in ipairs(patch.items or {}) do
            local line = g_ui.createWidget('PatchNoteLine', list)
            line:setText('- ' .. latin1(item[lang] or item.pt))
        end
    end
end

local function latestId()
    return notes and tonumber(notes.latest) or 0
end

local function markSeen()
    if notes then
        g_settings.set(seenKey(), latestId())
        g_settings.save()
    end
    updateBadge()
end

-- the close button works only in game while the window is forced open
local function updateClose()
    if not patchWindow then
        return
    end
    local locked = forced and not g_game.isOnline()
    local closeButton = patchWindow:getChildById('closeButton')
    closeButton:setEnabled(not locked)
    patchWindow:getChildById('siteHint'):setText(locked
        and tr('New patch! You can close this window once you are in the game.')
        or tr('Every patch is also on the site, under Patch notes.'))
end

local function onGameStart()
    if patchWindow then
        updateClose()
        patchWindow:raise()
    end
end

function PatchNotes.init()
    connect(g_game, { onGameStart = onGameStart })
end

function PatchNotes.terminate()
    disconnect(g_game, { onGameStart = onGameStart })
    forced = false
    PatchNotes.close()
    button = nil
    notes = nil
end

-- called by the character list each time it is built
function PatchNotes.attach(window, accountName)
    button = window and window:getChildById('patchNotesButton')
    account = accountName or ''
    updateBadge()
    local url = endpoint()
    if not url then
        return
    end
    request = request + 1
    local current = request
    HTTP.get(url, function(data, err)
        if err or current ~= request then
            return
        end
        local ok, decoded = pcall(json.decode, data or '')
        if ok and type(decoded) == 'table' and type(decoded.patches) == 'table' then
            notes = decoded
            updateBadge()
            if latestId() > g_settings.getNumber(seenKey(), 0) and not g_game.isOnline() then
                PatchNotes.open(true)
            elseif patchWindow then
                fill()
            end
        end
    end)
end

function PatchNotes.open(force)
    if not notes then
        return
    end
    if force then
        forced = true
    end
    local fresh = not patchWindow
    if fresh then
        patchWindow = g_ui.displayUI('patchnotes')
    end
    fill()
    updateClose()
    patchWindow:show()
    if fresh and force then
        -- beside the character list when there is room, so its Ok stays free
        local list = rootWidget:recursiveGetChildById('charactersWindow')
        if list and list:isVisible() then
            local x = list:getX() - patchWindow:getWidth() - 12
            patchWindow:breakAnchors()
            patchWindow:setPosition({ x = math.max(8, x), y = math.max(8, list:getY()) })
        end
    end
    patchWindow:raise()
    patchWindow:focus()
    if not forced then
        markSeen()
    end
end

-- Escape and the Close button: kept open on the character list while forced
function PatchNotes.close()
    if not patchWindow then
        return
    end
    if forced and not g_game.isOnline() then
        return
    end
    if forced then
        forced = false
        markSeen()
    end
    patchWindow:destroy()
    patchWindow = nil
end
