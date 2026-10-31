-- Patch notes of the site (plugins/brevesot/data/patches.php, served as JSON
-- by plugins/brevesot/patches.php). The character list gets a "Patch notes"
-- button, with a red "!" while this account has a patch it has not opened.
-- The window opens only from that button; opening it marks the patches as
-- read and the "!" goes away.
PatchNotes = {}

local SEEN_KEY = 'patchnotes-seen-'

local patchWindow = nil
local button = nil
local account = nil
local notes = nil
local request = 0

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

function PatchNotes.init()
end

function PatchNotes.terminate()
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
            if patchWindow then
                fill()
            end
        end
    end)
end

function PatchNotes.open()
    if not notes then
        return
    end
    if not patchWindow then
        patchWindow = g_ui.displayUI('patchnotes')
    end
    fill()
    patchWindow:show()
    patchWindow:raise()
    patchWindow:focus()
    markSeen()
end

-- Escape and the Close button
function PatchNotes.close()
    if not patchWindow then
        return
    end
    patchWindow:destroy()
    patchWindow = nil
end
