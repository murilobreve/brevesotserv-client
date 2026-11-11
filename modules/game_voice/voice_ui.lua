-- Mythos Voz panel: the mini window with the status, the switches and the
-- rooms (party, guild, public rooms, events) with their members; the
-- right-click menus (volume, mute for me, report, moderation); the icon over
-- the head of who is talking.
--
-- Cost rules (AGENTS.md, per-kill hot paths): the room list is rebuilt only
-- when the rooms themselves change (a roster, a join, a move), once on the
-- next frame behind a pending flag, and only while the panel is open. Member
-- rows are kept by sid and changed in place on speaking edges, flags, joins
-- and leaves. Nothing runs every frame.

VoiceUI = {}
local UI = VoiceUI
local S = VoiceState
local ST = S.ST

local COLOR_OFF, COLOR_WAIT, COLOR_ON, COLOR_BAD = '#6f688a', '#e0c050', '#78d04c', '#e0604a'
local NAME_COLOR, SELF_COLOR = '#d1ccd9', '#f3dcae'
local DIR_REFRESH_MS = 15000
local REFILL_MS = 1000 -- a big room's churn redraws the panel at most this often
local MAX_HEADS = 8
local REPORT_WAIT_MS = 8000
local MUTE_SECS = 600
local PLACE_CHECK_MS = 100 -- the side panel's layout has settled by then
local FLOAT_MARGIN = 8
local VOLUME_PAGE = 10     -- a click on the volume track or its arrows: 10%

local window, toggleButton
local sections = {} -- [slot] = { room, panel, rows = { [sid] = row }, shown, hidden, more, over }
local boxes = {}    -- party, guild, rooms: one container each, so a directory update leaves the others alone
local heads, headCount = {}, 0
local refreshEvent, roomsEvent, countdownEvent, dirEvent, placeEvent
local refreshAt = 0 -- when the pending refresh runs (g_clock.millis)
local dirty = false
local dirSig = '' -- the directory as last drawn
local roomsOpen = false
local volumePopup, reportWindow, reportWait

local function session()
    return getSession()
end

local function child(id)
    return window and window:recursiveGetChildById(id)
end

-- tr formats under pcall: a translation with a stray % shows as it is
-- instead of raising in an event handler
local function fmt(text, ...)
    return tr(text, ...)
end

-- creation --------------------------------------------------------------------

function UI.create()
    if window then
        return
    end
    window = g_ui.loadUI('/game_voice/voice')
    window:setup()
    -- the buttons of other mini windows this one has no use for
    for _, id in ipairs({ 'toggleFilterButton', 'contextMenuButton', 'newWindowButton' }) do
        local w = window:recursiveGetChildById(id)
        if w then
            w:setVisible(false)
        end
    end
    local lockButton, minimizeButton = child('lockButton'), child('minimizeButton')
    if lockButton and minimizeButton then
        lockButton:breakAnchors()
        lockButton:addAnchor(AnchorTop, 'minimizeButton', AnchorTop)
        lockButton:addAnchor(AnchorRight, 'minimizeButton', AnchorLeft)
        lockButton:setMarginRight(2)
    end
    window:setContentMinimumHeight(60)
    window:close(true)
    window:setupOnStart()
    local touch = child('pttTouch')
    touch:setVisible(g_platform.isMobile())
    touch.onMousePress = function()
        pressTalk(touchSlot())
        return true
    end
    touch.onMouseRelease = function()
        releaseTalk()
        return true
    end
    toggleButton = modules.client_topmenu.addRightGameToggleButton('voiceButton', tr('Voice'),
        '/game_voice/images/button', UI.toggle, false)
    if toggleButton then
        toggleButton:setOn(window:isVisible())
    end
    UI.connectHeads()
    UI.onState()
    UI.scheduleRefresh()
end

function UI.destroy()
    UI.clearHeads()
    UI.disconnectHeads()
    UI.closePopups()
    removeEvent(refreshEvent)
    removeEvent(roomsEvent)
    removeEvent(countdownEvent)
    removeEvent(dirEvent)
    removeEvent(placeEvent)
    refreshEvent, roomsEvent, countdownEvent, dirEvent, placeEvent = nil, nil, nil, nil, nil
    sections, boxes, roomsOpen, dirty, dirSig = {}, {}, false, false, ''
    -- a panel that went with its parent is not destroyed twice (a warning)
    if window then
        if not window:isDestroyed() then
            window:destroy()
        end
        window = nil
    end
    if toggleButton then
        if not toggleButton:isDestroyed() then
            toggleButton:destroy()
        end
        toggleButton = nil
    end
end

function UI.closePopups()
    if volumePopup then
        volumePopup:destroy()
        volumePopup = nil
    end
    if reportWindow then
        reportWindow:destroy()
        reportWindow = nil
    end
    removeEvent(reportWait)
    reportWait = nil
end

local function visible()
    return window ~= nil and window:isVisible()
end

-- where the panel opens ------------------------------------------------------
--
-- The play-test at 1280x720 with Battle List, Unjustified Points and VIP
-- open: the panel went to the end of a side panel with no room left, under
-- the bottom of the screen, and nothing showed. Now it goes where it fits;
-- else to the top of the selected side panel (the windows under it give
-- way as the game's own rules say); and once the layout settled, a panel
-- that still does not end inside the screen floats over the map.

local function isContainer(widget)
    return widget ~= nil and widget:getClassName() == 'UIMiniWindowContainer'
end

-- room in a side panel for the panel at its minimum height (it is closed
-- here, so its own height is not counted)
local function hasRoom(panel)
    return isContainer(panel) and panel:isVisible() and panel:fits(window, window:getMinimumHeight(), 0) >= 0
end

-- moves the panel into a side panel (at `index`, or at the end) and keeps
-- the place for the next login (CharMiniWindows)
local function moveTo(panel, index)
    local old = window:getParent()
    if old then
        old:removeChild(window)
    end
    if index then
        panel:insertChild(index, window)
    else
        panel:addChild(window)
    end
    if isContainer(old) and old ~= panel then
        old:saveChildren()
    end
    panel:saveChildren()
end

local function placeWindow()
    local parent = window:getParent()
    if parent and not isContainer(parent) then
        return true -- floating where the player left it (checked on screen after)
    end
    if hasRoom(parent) then
        return true
    end
    local game = modules.game_interface
    local panel = game and game.findContentPanelAvailable and
        game.findContentPanelAvailable(window, window:getMinimumHeight())
    if hasRoom(panel) then
        moveTo(panel)
        return true
    end
    -- no side panel has room: the top of the selected one (or of where it is)
    local selected = game and game.getSelectedPanel and game.getSelectedPanel() or panel
    for _, top in ipairs({ selected or false, parent or false }) do
        if isContainer(top) and top:isVisible() then
            moveTo(top, 1)
            return true
        end
    end
    return false
end

function UI.onScreen()
    local r, root = window:getRect(), rootWidget:getRect()
    return r.width > 0 and r.height > 0 and r.x >= root.x and r.y >= root.y and r.x + r.width <= root.x + root.width and
        r.y + r.height <= root.y + root.height
end

-- over the map, at its top right: a spot that always shows
function UI.float()
    local game = modules.game_interface
    local host = game and game.getRootPanel and game.getRootPanel() or rootWidget
    local map = game and game.getMapPanel and game.getMapPanel()
    local root = rootWidget:getRect()
    local area = map and map:isVisible() and map:getRect() or root
    local old = window:getParent()
    if old ~= host then
        if old then
            old:removeChild(window)
        end
        host:addChild(window)
        if isContainer(old) then
            old:saveChildren()
        end
    end
    -- shorter only when it does not fit (a minimized panel stays so)
    local height = window:getHeight()
    if height > area.height - 2 * FLOAT_MARGIN then
        height = math.max(window:getMinimumHeight(), area.height - 2 * FLOAT_MARGIN)
        window:setHeight(height)
    end
    local width = window:getWidth()
    local x = math.max(root.x, math.min(area.x + area.width - width - FLOAT_MARGIN, root.x + root.width - width))
    local y = math.max(root.y, math.min(area.y + FLOAT_MARGIN, root.y + root.height - height))
    window:setPosition({ x = x, y = y })
    window:raise()
    window:saveParentPosition(host:getId(), window:getPosition())
end

function UI.toggle()
    if not window then
        return
    end
    if window:isVisible() then
        window:close()
        return
    end
    if not placeWindow() then
        UI.float()
    end
    window:open()
    removeEvent(placeEvent)
    placeEvent = scheduleEvent(function()
        placeEvent = nil
        if visible() and not UI.onScreen() then
            UI.float()
        end
    end, PLACE_CHECK_MS)
end

function UI.onPanelOpen()
    if toggleButton then
        toggleButton:setOn(true)
    end
    UI.onState()
    if dirty then
        UI.refresh()
    end
    if roomsOpen then
        UI.startDir()
    end
end

function UI.onPanelClose()
    if toggleButton then
        toggleButton:setOn(false)
    end
    removeEvent(dirEvent)
    dirEvent = nil
    removeEvent(countdownEvent)
    countdownEvent = nil
end

-- the status line -------------------------------------------------------------

local function dateText(ts)
    return ts and ts > 0 and os.date('%d/%m %H:%M', ts) or '?'
end

-- whole seconds until the next automatic try
local function secondsLeft(s)
    return math.max(1, math.ceil(((s.retryAt or 0) - g_clock.millis()) / 1000))
end

-- a short headline for the status row, its color, the retry button's text
-- (if any) and a longer line for the note under the switches
local function statusOf(s)
    local state = s.state
    if state == ST.ONLINE then
        if getEngineName() == 'lite' then
            return tr('Presence mode'), COLOR_ON, nil,
                tr('Presence mode: update the client (or use Chrome, Edge or Firefox) to talk and listen.')
        end
        return tr('Connected'), COLOR_ON
    elseif state == ST.WAIT_TOKEN or state == ST.CONNECTING then
        return tr('Connecting...'), COLOR_WAIT
    elseif state == ST.BACKOFF then
        return tr('Voice unavailable'), COLOR_BAD, tr('Try now'), fmt('Trying again in %d s.', secondsLeft(s))
    elseif state == ST.FAILED then
        -- it still tries by itself, once a minute
        local detail = tr('The voice server did not answer.')
        if s.retryAt then
            detail = detail .. ' ' .. fmt('Trying again in %d s.', secondsLeft(s))
        end
        return tr('Voice unavailable'), COLOR_BAD, tr('Try again'), detail
    elseif state == ST.BLOCKED then
        if s.why == 'banned' then
            return tr('Banned from voice'), COLOR_BAD, nil, fmt('Until %s.', dateText(s.untilTs))
        elseif s.why == 'replaced' then
            return tr('Voice disconnected'), COLOR_BAD, tr('Reconnect'), tr('Voice was opened in another window.')
        end
        return tr('Voice switched off'), COLOR_OFF, nil, tr('Voice was switched off by the server.')
    elseif state == ST.READY then
        return tr('Voice is off.'), COLOR_OFF
    end
    return tr('Voice unavailable'), COLOR_OFF
end

-- the BACKOFF and FAILED countdown: one tick a second, only while it shows
local function scheduleCountdown()
    removeEvent(countdownEvent)
    countdownEvent = nil
    local s = session()
    if visible() and s and s.retryAt and (s.state == ST.BACKOFF or s.state == ST.FAILED) then
        countdownEvent = scheduleEvent(function()
            countdownEvent = nil
            UI.onState()
        end, 1000)
    end
end

function UI.onState()
    local s = session()
    if not window or not s then
        return
    end
    local text, color, retry, detail = statusOf(s)
    if toggleButton then
        toggleButton:setTooltip(tr('Voice') .. ': ' .. (detail or text))
    end
    if not visible() then
        dirty = true
        return
    end
    child('statusDot'):setBackgroundColor(color)
    child('statusText'):setText(text)
    local retryButton = child('retryButton')
    retryButton:setVisible(retry ~= nil)
    if retry then
        retryButton:setText(retry)
    end
    local online = s.state == ST.ONLINE
    local prefs = getPrefs()
    local mute, deaf = child('muteButton'), child('deafButton')
    mute:setOn(prefs.selfMuted)
    mute:setImageSource(prefs.selfMuted and '/game_voice/images/mic_off' or '/game_voice/images/mic')
    mute:setTooltip(prefs.selfMuted and tr('Unmute microphone') or tr('Mute microphone'))
    deaf:setOn(prefs.deafened)
    deaf:setImageSource(prefs.deafened and '/game_voice/images/headset_off' or '/game_voice/images/headset')
    deaf:setTooltip(prefs.deafened and tr('Undeafen') or tr('Deafen'))
    child('settingsButton'):setTooltip(tr('Voice settings'))
    local test = child('testButton')
    test:setVisible(online and hasAudio())
    test:setText(isTesting() and tr('Stop') or tr('Test'))
    local note = child('note')
    note:setVisible(detail ~= nil)
    note:setText(detail or '')
    child('onButton'):setVisible(s.state == ST.READY)
    scheduleCountdown()
    if dirty or s.state ~= ST.ONLINE then
        UI.scheduleRefresh()
    end
end

-- rooms -----------------------------------------------------------------------

-- a full redraw on the next frame, or after `delay` ms; a sooner request
-- replaces a later one, so many changes still cost one redraw
function UI.scheduleRefresh(delay)
    delay = delay or 1
    local at = g_clock.millis() + delay
    if refreshEvent then
        if refreshAt <= at then
            return
        end
        removeEvent(refreshEvent)
    end
    refreshAt = at
    refreshEvent = scheduleEvent(function()
        refreshEvent = nil
        UI.refresh()
    end, delay)
end

-- the hint ("Hold Insert") ends where the header's button starts. When it
-- does not fit (a long title or key name, a narrow panel) only the key
-- shows ("Insert"), and when not even the key fits, nothing: a cut text
-- ("Hold I...") read as a broken label. The header's tooltip has it whole.
-- Run again on each change of the hint's width. The text is set only when
-- it changes: a label without a width yet takes the size of a new text, and
-- that must not start another round.
function UI.fitHint(h)
    local hint, full = h.hint, h.fullHint or ''
    local function put(text)
        if hint:getText() ~= text then
            hint:setText(text)
        end
    end
    local room = hint:getWidth()
    put(full)
    if full == '' or room <= 0 or hint:getTextSize().width <= room then
        return
    end
    -- measured by the label itself: the font has no call to measure from Lua
    local short = h.shortHint or ''
    if short ~= '' and short ~= full then
        put(short)
        if hint:getTextSize().width <= room then
            return
        end
    end
    put('')
end

-- hint: the whole key hint ("Hold Insert"); short: the key alone, shown when
-- the whole one does not fit
local function header(parent, title, hint, short)
    local h = g_ui.createWidget('VoiceSectionHeader', parent)
    h.title:setText(title)
    h.fullHint = hint or ''
    h.shortHint = short or ''
    if h.fullHint ~= '' then
        h:setTooltip(h.fullHint)
    end
    h.hint.onGeometryChange = function()
        UI.fitHint(h)
    end
    UI.fitHint(h)
    return h
end

-- the header's button (Join, Leave, Show, Hide); the hint stops before it
local function headerAction(h, text, onClick)
    h.action:setVisible(true)
    h.action:setText(text)
    h.action.onClick = onClick
    h.hint:addAnchor(AnchorRight, 'action', AnchorLeft)
    h.hint:setMarginRight(4)
end

local function note(parent, text)
    local label = g_ui.createWidget('VoiceNote', parent)
    label:setText(text)
    return label
end

-- "Hold F8" next to a section, and the key alone for a narrow header: only
-- where this client can talk
local function keyHint(slot)
    local key = hasAudio() and talkKey(slot) or ''
    if key == '' then
        return '', ''
    end
    return fmt('Hold %s', key), key
end

local function roomLabel(room)
    if room.kind == 'party' then
        return tr('Party room')
    elseif room.kind == 'officers' then
        return tr('Officers')
    elseif room.kind == 'echo' then
        return tr('Echo test')
    end
    return S.latin1(room.label or room.id)
end

local function updateRow(row, m)
    local s = session()
    local f = m.flags
    local isSelf = m.sid == s.sid
    row.ring:setOn(m.speaking or (isSelf and s.talkSlot >= 0))
    row.icons.selfmuted:setVisible(S.hasFlag(f, S.F_SELF_MUTED))
    row.icons.deaf:setVisible(S.hasFlag(f, S.F_DEAF))
    row.icons.srvmuted:setVisible(S.hasFlag(f, S.F_SERVER_MUTED))
    row.icons.mutedforme:setVisible(m.mutedForMe)
    row.icons.lite:setVisible(S.hasFlag(f, S.F_LITE))
    row.icons.staff:setVisible(S.hasFlag(f, S.F_STAFF))
    -- the icons are 12 px and phantom: the row's tooltip says each in words
    -- (the slashed mic and the slashed headset look alike at that size)
    local tips = { S.latin1(m.name) }
    if S.hasFlag(f, S.F_STAFF) then
        tips[#tips + 1] = tr('Staff member')
    end
    if S.hasFlag(f, S.F_SELF_MUTED) then
        tips[#tips + 1] = tr('Microphone off')
    end
    if S.hasFlag(f, S.F_DEAF) then
        tips[#tips + 1] = tr('Sound off')
    end
    if S.hasFlag(f, S.F_SERVER_MUTED) then
        tips[#tips + 1] = tr('Muted by the staff')
    end
    if m.mutedForMe then
        tips[#tips + 1] = tr('Muted for you')
    end
    if S.hasFlag(f, S.F_LITE) then
        tips[#tips + 1] = tr('Presence mode: does not hear or talk')
    end
    row:setTooltip(table.concat(tips, '\n'))
end

local function createRow(sec, m)
    local row = g_ui.createWidget('VoiceMemberRow', sec.panel)
    local isSelf = m.sid == session().sid
    row.name:setText(S.latin1(m.name))
    row.name:setColor(isSelf and SELF_COLOR or NAME_COLOR)
    local roomId, sid = sec.room.id, m.sid
    row.onMousePress = function(widget, mousePos, mouseButton)
        if mouseButton == MouseRightButton then
            UI.memberMenu(roomId, sid, mousePos)
            return true
        end
        return false
    end
    sec.rows[m.sid] = row
    sec.shown = sec.shown + 1
    updateRow(row, m)
    return row
end

local function updateMore(sec)
    if sec.hidden > 0 then
        if not sec.more then
            sec.more = note(sec.panel:getParent(), '')
        end
        sec.more:setText(fmt('+%d in the room', sec.hidden))
    elseif sec.more then
        sec.more:destroy()
        sec.more = nil
    end
end

local function updateOver(sec)
    local n = sec.room.over or 0
    if n > 0 then
        if not sec.over then
            sec.over = note(sec.panel:getParent(), '')
            sec.over:setColor('#e0c050')
        end
        sec.over:setText(fmt('+%d talking', n))
    elseif sec.over then
        sec.over:destroy()
        sec.over = nil
    end
end

-- the members of a joined room, under its header or its list entry
local function members(parent, room)
    -- the rows, then the "+N" notes under them
    local box = g_ui.createWidget('VoiceMembers', parent)
    local sec = { room = room, panel = g_ui.createWidget('VoiceMembers', box), rows = {}, shown = 0, hidden = 0 }
    local list, hidden = S.visibleMembers(room, S.ROW_CAP)
    for _, m in ipairs(list) do
        createRow(sec, m)
    end
    sec.hidden = hidden
    updateMore(sec)
    updateOver(sec)
    sections[room.slot] = sec
end

local function leaveButton(h, room)
    headerAction(h, tr('Leave'), function()
        session():leave(room.id)
    end)
end

local function partySection(parent, s)
    local h = header(parent, tr('PARTY'), keyHint(0))
    local room = s.rooms[0]
    if room then
        leaveButton(h, room)
        members(parent, room)
    elseif s.tokRooms.party then
        headerAction(h, tr('Join'), function()
            s:join(s.tokRooms.party.id)
        end)
    else
        note(parent, tr('No party'))
    end
end

-- an entry of a room list: "# Name (12)"; a click joins it
local function dirRow(parent, s, id, text, joined)
    local row = g_ui.createWidget('VoiceDirRow', parent)
    row:setText(text)
    row:setOn(joined)
    if not joined then
        row.onClick = function()
            s:join(id)
        end
    end
    return row
end

local function guildSection(parent, s)
    local guild, officers = s.tokRooms.guild, s.tokRooms.officers
    if not guild and not officers then
        return
    end
    local h = header(parent, tr('GUILD'), keyHint(1))
    local room = s.rooms[1]
    if room then
        leaveButton(h, room)
    end
    for _, r in ipairs({ guild or false, officers or false }) do
        if r then
            local joined = room ~= nil and room.id == r.id
            local label = r == officers and tr('Officers') or S.latin1(r.label or tr('Guild room'))
            dirRow(parent, s, r.id, '# ' .. label, joined)
            if joined then
                members(parent, room)
            end
        end
    end
end

-- public rooms and events, from the relay's directory (only while unfolded)
local function roomsSection(parent, s)
    local h = header(parent, tr('ROOMS'), keyHint(2))
    headerAction(h, roomsOpen and tr('Hide') or tr('Show'), function()
        roomsOpen = not roomsOpen
        if roomsOpen then
            UI.startDir()
        else
            removeEvent(dirEvent)
            dirEvent = nil
        end
        UI.scheduleRooms()
    end)
    local joined = s.rooms[2]
    if joined and (joined.kind == 'echo' or not roomsOpen) then
        dirRow(parent, s, joined.id, '# ' .. roomLabel(joined), true)
        members(parent, joined)
    end
    if not roomsOpen then
        return
    end
    local cfg = s.cfg
    if cfg and cfg.psl > 0 then
        note(parent, fmt('Talking in public rooms: level %d+', cfg.psl))
    end
    local events = {}
    for _, d in ipairs(s.dir) do
        if d.stage then
            events[#events + 1] = d
        else
            local isIn = joined ~= nil and joined.id == d.id
            dirRow(parent, s, d.id, string.format('# %s (%d)', S.latin1(d.name), d.members), isIn)
            if isIn then
                members(parent, joined)
            end
        end
    end
    if #events > 0 then
        header(parent, tr('EVENTS'))
        for _, d in ipairs(events) do
            local isIn = joined ~= nil and joined.id == d.id
            dirRow(parent, s, d.id, string.format('* %s (%d) - %s', S.latin1(d.name), d.members, tr('stage')), isIn)
            if isIn then
                members(parent, joined)
            end
        end
    end
    if #s.dir == 0 then
        note(parent, tr('Loading the rooms...'))
    end
    -- the relay plays our own voice back after 1.5 s
    if hasAudio() and not (joined and joined.kind == 'echo') then
        dirRow(parent, s, 'echo', '# ' .. tr('Echo test'), false)
    end
end

-- asks the relay for the room list now and every 15 s while it shows
function UI.startDir()
    removeEvent(dirEvent)
    dirEvent = nil
    local s = session()
    if not (roomsOpen and visible() and s and s.state == ST.ONLINE) then
        return
    end
    s:requestDir()
    dirEvent = scheduleEvent(UI.startDir, DIR_REFRESH_MS)
end

function UI.refresh()
    if not window then
        return
    end
    if not visible() then
        dirty = true
        return
    end
    dirty = false
    local list = child('rooms')
    list:destroyChildren()
    sections, boxes = {}, {}
    local s = session()
    if not s or s.state ~= ST.ONLINE then
        return
    end
    for _, name in ipairs({ 'party', 'guild', 'rooms' }) do
        boxes[name] = g_ui.createWidget('VoiceMembers', list)
    end
    partySection(boxes.party, s)
    guildSection(boxes.guild, s)
    UI.refreshRooms()
end

-- the directory changes every 15 s: only the rooms part is drawn again
local function directorySig(s)
    local parts = { tostring(roomsOpen) }
    for _, d in ipairs(s.dir) do
        parts[#parts + 1] = d.id .. '=' .. d.members
    end
    return table.concat(parts, ',')
end

function UI.refreshRooms()
    local s = session()
    local box = boxes.rooms
    if not box or box:isDestroyed() or not s or s.state ~= ST.ONLINE then
        return
    end
    dirSig = directorySig(s)
    box:destroyChildren()
    sections[2] = nil
    roomsSection(box, s)
end

function UI.scheduleRooms()
    if roomsEvent or refreshEvent then
        return
    end
    roomsEvent = scheduleEvent(function()
        roomsEvent = nil
        UI.refreshRooms()
    end, 1)
end

-- events from the session -----------------------------------------------------

function UI.onEvent(what, a, b, c)
    if what == 'speaking' then
        UI.onSpeaking(a, b, c)
        return
    elseif what == 'talk' then
        UI.onTalk(a)
        return
    elseif what == 'speakers' then
        if a == 0 then
            UI.clearHeads(true)
        end
        return
    elseif what == 'notice' then
        UI.notice(a, b, c)
        return
    elseif what == 'report' then
        UI.onReport(a, b, c)
        return
    elseif what == 'self' then
        UI.onState()
        return
    end
    if not window then
        return
    end
    if not visible() then
        dirty = true
        return
    end
    if what == 'rooms' or what == 'tok' then
        UI.scheduleRefresh()
        return
    elseif what == 'dir' then
        if directorySig(session()) ~= dirSig then
            UI.scheduleRooms()
        end
        return
    end
    -- in place: a, b = room, member
    local sec = a and sections[a.slot]
    if not sec or sec.room ~= a then
        return
    end
    if what == 'member' then
        local row = sec.rows[b.sid]
        if row then
            updateRow(row, b)
        end
    elseif what == 'in' then
        if sec.shown < S.ROW_CAP and sec.hidden == 0 then
            createRow(sec, b)
        else
            sec.hidden = sec.hidden + 1
            updateMore(sec)
        end
    elseif what == 'out' then
        local row = sec.rows[b.sid]
        if row then
            row:destroy()
            sec.rows[b.sid] = nil
            sec.shown = sec.shown - 1
            if sec.hidden > 0 then
                UI.scheduleRefresh(REFILL_MS) -- someone hidden gets the free row
            end
        elseif sec.hidden > 0 then
            sec.hidden = sec.hidden - 1
            updateMore(sec)
        end
    elseif what == 'over' then
        updateOver(sec)
    end
end

function UI.onSpeaking(sid, on, member)
    if visible() then
        for slot = 0, 2 do
            local sec = sections[slot]
            local row = sec and sec.rows[sid]
            if row then
                row.ring:setOn(on)
            end
        end
    end
    -- our own voice coming back from the echo room has the 'self' icon already
    local s = session()
    if on and member and member.cid > 0 and member.sid ~= (s and s.sid) and getPrefs().overheadIcon then
        UI.attachHead(sid, member.cid)
    elseif not on then
        UI.detachHead(sid)
    end
end

-- the local gate: our own ring and our own head icon
function UI.onTalk(slot)
    local s = session()
    if visible() and s.sid then
        for i = 0, 2 do
            local sec = sections[i]
            local row = sec and sec.rows[s.sid]
            if row then
                row.ring:setOn(slot >= 0)
            end
        end
    end
    local player = g_game.getLocalPlayer()
    if slot >= 0 and player and getPrefs().overheadIcon then
        UI.attachHead('self', player:getId())
    else
        UI.detachHead('self')
    end
end

-- over-head icons (edges only; a dead or vanished creature gets none) --------
--
-- The icon is an image the engine draws with the speaker (an attached effect
-- of the creature), not a widget attached to it: Map::updateAttachedWidgets
-- reads the draw pool's scale factor while no pool is selected (one past the
-- end of its pool list). The browser build read 0 there and left such a
-- widget at the tile's corner, 10 px left of the name and 13 px lower; in a
-- 64-bit desktop build that read goes through a wild pointer. An effect is
-- drawn inside the map's pool, follows the walk and the jumps, and goes with
-- the creature: out of the map, dead or gone.
--
-- Its offsets are sprite px from the creature's tile (the map scales them):
-- centred over the name, its bottom NAME_GAP screen px over the creature's
-- point (where the name's box ends: Creature::drawInformation), so it sits
-- just above the letters. In the map's top rows that would leave the drawn
-- map, so there it goes under the feet (the outfit is drawn its displacement
-- above its tile's bottom). Shown only while the speaker's name is (on the
-- camera's floor, inside the view: UIMap:isInRange); an icon in the ring of
-- tiles around the view would show inside the map over nobody.

local HEAD_EFFECT = 65021 -- an attached-effect id nothing else registers (game_attachedeffects uses 1-99)
local HEAD_IMAGE = '/game_voice/images/speaker_head'
local HEAD_W, HEAD_H = 18, 16 -- the image, in sprite px
local NAME_GAP = 9            -- screen px between the icon and the creature's point
local FEET_GAP = 2            -- screen px between the feet and the icon under them
local DRAW_ABOVE_ALL = 4      -- DrawOrder FIFTH: over walls and roofs, like a missile

local checkEvent -- the pending check of every icon (checkHeadsSoon)

-- a new icon for a creature. The image is registered once per client run
-- (registering an id again logs an error): the flag lives in the real
-- globals, which a module reload keeps (this module's own are new then);
-- an id taken already is used as it is
local function newHeadEffect()
    if not g_attachedEffects then
        return nil
    end
    if _G.VoiceHeadEffectRegistered == nil then
        _G.VoiceHeadEffectRegistered = g_attachedEffects.registerByImage(HEAD_EFFECT, 'Mythos Voz', HEAD_IMAGE, false) ~= nil or
            g_attachedEffects.getById(HEAD_EFFECT) ~= nil
    end
    if not _G.VoiceHeadEffectRegistered then
        return nil
    end
    local effect = g_attachedEffects.getById(HEAD_EFFECT)
    if effect then
        effect:setOnTop(true)
        effect:setFollowOwner(true) -- jumps too
        effect:setDrawOrder(DRAW_ABOVE_ALL)
    end
    return effect
end

-- The map's drawn rect and its tile in UI px. UIMap:getPosition answers a
-- point outside the drawn rect with nothing (MapView::getPosition), and the
-- rect is centred in the padding rect (letterboxed in the classic view), so
-- its edges are found by halving from the centre; a new frame checks them
-- again with two calls an edge and looks for them anew only when one moved.
-- The tile: the engine fits the drawn rect into the visible tiles keeping
-- its shape (MapView::calcFramebufferSource), so it is the larger ratio.
local drawn = { at = -1 }

local function inMap(map, x, y)
    return map:getPosition({ x = x, y = y })
end

-- the last coordinate inside from `inside` towards `outside`
local function edge(test, inside, outside)
    while math.abs(outside - inside) > 1 do
        local mid = math.floor((inside + outside) / 2)
        if test(mid) then
            inside = mid
        else
            outside = mid
        end
    end
    return inside
end

local function mapView(map)
    local now = g_clock.millis()
    if drawn.at == now and drawn.map == map then
        return drawn.ok and drawn or nil
    end
    drawn.at, drawn.map = now, map
    local function row(x) return inMap(map, x, drawn.cy) ~= nil end
    local function column(y) return inMap(map, drawn.cx, y) ~= nil end
    if not (drawn.ok and column(drawn.top) and not column(drawn.top - 1) and column(drawn.bottom) and
            not column(drawn.bottom + 1) and row(drawn.left) and not row(drawn.left - 1) and row(drawn.right) and
            not row(drawn.right + 1)) then
        local pad = map:getPaddingRect()
        drawn.cx, drawn.cy = pad.x + math.floor(pad.width / 2), pad.y + math.floor(pad.height / 2)
        drawn.ok = pad.width > 0 and pad.height > 0 and column(drawn.cy)
        if not drawn.ok then
            return nil -- no camera yet
        end
        drawn.top = edge(column, drawn.cy, pad.y - 1)
        drawn.bottom = edge(column, drawn.cy, pad.y + pad.height)
        drawn.left = edge(row, drawn.cx, pad.x - 1)
        drawn.right = edge(row, drawn.cx, pad.x + pad.width)
    end
    local dim = map:getVisibleDimension()
    if not dim or dim.width <= 0 or dim.height <= 0 then
        return nil
    end
    drawn.tile = math.max((drawn.right - drawn.left + 1) / dim.width, (drawn.bottom - drawn.top + 1) / dim.height)
    return drawn
end

-- the screen y where the row `y` of the camera's floor starts (the drawn top
-- when it starts above it)
local function rowTop(map, view, y)
    local first = inMap(map, view.cx, view.top)
    if not first or first.y >= y then
        return view.top
    end
    return edge(function(at)
        local pos = inMap(map, view.cx, at)
        return pos ~= nil and pos.y < y
    end, view.top, view.bottom + 1) + 1
end

-- the outfit's displacement, the mount's when it rides (the creature is
-- drawn that far up and left; the name's point leaves it out on servers
-- with negative offsets)
local function displacement(creature)
    local outfit = creature:getOutfit()
    local id = outfit and ((outfit.mount or 0) > 0 and outfit.mount or outfit.type)
    local kind = id and g_things.getThingType(id, ThingCategoryCreature)
    if not kind or g_game.getFeature(GameNegativeOffset) then
        return 8, 8
    end
    return kind:getDisplacementX(), kind:getDisplacementY()
end

-- shows, hides and places one icon
function UI.placeHead(head)
    local creature = g_map.getCreatureById(head.cid)
    local pos = creature and not creature:isDead() and creature:getPosition()
    local map = modules.game_interface.getMapPanel()
    local seen = pos and map and map:isInRange(pos) or false
    -- a creature the client made anew (out of view and back) gets it again
    if head.on and (not seen or creature ~= head.creature) then
        head.creature:detachEffect(head.effect)
        head.on = false
    end
    if not seen then
        return
    end
    -- UI px a sprite px (32 px a tile until the map is measured), and the
    -- screen px of the UI's: the name is drawn in screen px
    local view = mapView(map)
    local scale = view and view.tile / 32 or 1
    local screen = scale * g_window.getDisplayDensity()
    local dx, dy = displacement(creature)
    local ox = HEAD_W / 2 - (16 - dx)
    local oy = HEAD_H + dy + 2 + NAME_GAP / screen
    if view and rowTop(map, view, pos.y) - oy * scale < view.top then
        oy = -(32 - dy) - FEET_GAP / screen
    end
    ox, oy = math.floor(ox + 0.5), math.floor(oy + 0.5)
    if head.ox ~= ox or head.oy ~= oy then
        head.ox, head.oy = ox, oy
        head.effect:setOffset(ox, oy)
    end
    if not head.on then
        creature:attachEffect(head.effect)
        head.creature, head.on = creature, true
    end
end

function UI.attachHead(key, cid)
    if heads[key] or headCount >= MAX_HEADS then
        return
    end
    local creature = g_map.getCreatureById(cid)
    if not creature or creature:isDead() or not creature:getPosition() then
        return
    end
    local effect = newHeadEffect()
    if not effect then
        return
    end
    local head = { cid = cid, effect = effect, creature = creature, on = false }
    heads[key] = head
    headCount = headCount + 1
    UI.placeHead(head)
end

function UI.detachHead(key)
    local head = heads[key]
    if not head then
        return
    end
    heads[key] = nil
    headCount = headCount - 1
    if head.on then
        head.creature:detachEffect(head.effect)
    end
end

-- keepSelf: our own icon stays while our key is down
function UI.clearHeads(keepSelf)
    for key in pairs(heads) do
        if not (keepSelf and key == 'self') then
            UI.detachHead(key)
        end
    end
end

-- A speaker who walks, changes floor, leaves or comes back, and our own
-- moves (the camera), check the icons once on the next frame, when the
-- creature's new position is known (a creature's position is dropped only
-- after its onDisappear).
local function checkHeadsSoon()
    if headCount == 0 or checkEvent then
        return
    end
    checkEvent = scheduleEvent(function()
        checkEvent = nil
        for _, head in pairs(heads) do
            UI.placeHead(head)
        end
    end, 1)
end

local function onCreatureChange(creature)
    if headCount == 0 then
        return
    end
    if creature:isLocalPlayer() then
        checkHeadsSoon()
        return
    end
    local cid = creature:getId()
    for _, head in pairs(heads) do
        if head.cid == cid then
            checkHeadsSoon()
            return
        end
    end
end

local CREATURE_EVENTS = { onAppear = onCreatureChange, onDisappear = onCreatureChange, onDeath = onCreatureChange,
    onPositionChange = onCreatureChange }
local PLAYER_EVENTS = { onPositionChange = checkHeadsSoon }

function UI.connectHeads()
    connect(Creature, CREATURE_EVENTS)
    connect(LocalPlayer, PLAYER_EVENTS)
end

function UI.disconnectHeads()
    disconnect(Creature, CREATURE_EVENTS)
    disconnect(LocalPlayer, PLAYER_EVENTS)
    removeEvent(checkEvent)
    checkEvent = nil
end

-- messages --------------------------------------------------------------------

local LEFT_TEXT = {
    party = 'Voice: you are no longer in the party room.',
    guild = 'Voice: you are no longer in the guild room.',
    kicked = 'Voice: you were kicked from the room.',
    rights = 'Voice: you no longer have access to this room.',
}

local ERR_TEXT = {
    room_denied = 'Voice: you cannot join this room.',
    room_full = 'Voice: the room is full.',
    floor_busy = 'Voice: too many people talking; wait a moment.',
    rate = 'Voice: too fast; wait a moment.',
    muted = 'Voice: you are muted.',
    kick_block = 'Voice: you were kicked from this room a moment ago.',
}

function UI.notice(kind, a, b)
    if kind == 'left' then
        -- leaving the party in the game already says it: no second message
        if a ~= 'party' and LEFT_TEXT[a] then
            notify(tr(LEFT_TEXT[a]))
        end
    elseif kind == 'err' then
        local s = session()
        -- refused while talking in a room already joined (level, stage)
        if a == 'room_denied' and b and s and s:roomById(b) then
            notify(tr('Voice: you cannot talk in this room.'))
        elseif ERR_TEXT[a] then
            notify(tr(ERR_TEXT[a]))
        end
    elseif kind == 'muted' then
        if (a or 0) > 0 then
            notify(fmt('Voice: you are muted until %s.', dateText(a)))
        else
            notify(tr('Voice: your mute was lifted.'))
        end
    end
end

-- the member menu -------------------------------------------------------------

function UI.memberMenu(roomId, sid, pos)
    local s = session()
    local room = s and s:roomById(roomId)
    local m = room and room.members[sid]
    if not m or sid == s.sid then
        return
    end
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    if hasAudio() then
        local pref = S.userPref(getPrefs(), m.guid)
        menu:addOption(fmt('Volume: %d%%', pref and pref.v or 100), function()
            UI.volumePopup(roomId, sid, pos)
        end)
    end
    menu:addOption(m.mutedForMe and tr('Unmute for me') or tr('Mute for me'), function()
        local member = s:memberAnywhere(sid)
        if member then
            s:setUserMuted(member, not member.mutedForMe)
        end
    end)
    menu:addOption(tr('Report'), function()
        UI.reportWindowFor(roomId, sid)
    end)
    -- moderation, for who may (the relay checks it again)
    local me = room.members[s.sid]
    local myFlags = me and me.flags or 0
    local staff = S.hasFlag(myFlags, S.F_STAFF)
    if staff or S.hasFlag(myFlags, S.F_MODERATOR) then
        menu:addSeparator()
        -- the party leader may only mute in the party room
        if staff or room.kind ~= 'party' then
            menu:addOption(tr('Kick from the room'), function()
                s:moderate('kick', roomId, sid)
            end)
        end
        if S.hasFlag(m.flags, S.F_SERVER_MUTED) then
            menu:addOption(tr('Lift the mute'), function()
                s:moderate('unmute', roomId, sid)
            end)
        else
            menu:addOption(tr('Mute for 10 minutes'), function()
                s:moderate('mute', roomId, sid, MUTE_SECS)
            end)
        end
        if room.kind == 'stage' then
            if S.hasFlag(m.flags, S.F_STAGE) then
                menu:addOption(tr('Take the floor'), function()
                    s:moderate('nospeak', roomId, sid)
                end)
            else
                menu:addOption(tr('Give the floor'), function()
                    s:moderate('speak', roomId, sid)
                end)
            end
        end
    end
    menu:display(pos)
end

-- a click on the volume track moves one page toward it, on the 10% grid
-- (it moved 1% a click: about 100 clicks down to 0); the thumb still drags
-- freely
function UI.volumePage(slider)
    local thumb = slider:getChildById('sliderButton')
    if not thumb then
        return
    end
    local value = slider:getValue()
    if g_window.getMousePosition().x < thumb:getX() + thumb:getWidth() / 2 then
        value = math.ceil(value / VOLUME_PAGE) * VOLUME_PAGE - VOLUME_PAGE
    else
        value = math.floor(value / VOLUME_PAGE) * VOLUME_PAGE + VOLUME_PAGE
    end
    slider:setValue(value)
end

-- a slider 0-200% for one player's volume, 0% and 100% buttons; closes on a
-- click outside
function UI.volumePopup(roomId, sid, pos)
    local s = session()
    local m = s and s:memberAnywhere(sid)
    if not m then
        return
    end
    UI.closePopups()
    volumePopup = g_ui.createWidget('VoiceVolumePopup', rootWidget)
    volumePopup:setPosition(pos or g_window.getMousePosition())
    volumePopup:bindRectToParent()
    local pref = S.userPref(getPrefs(), m.guid)
    local slider, label = volumePopup.slider, volumePopup.label
    local function show(value)
        label:setText(string.format('%s: %d%%', S.latin1(m.name), value))
    end
    slider:setValue(pref and pref.v or 100)
    show(slider:getValue())
    slider.onValueChange = function(widget, value)
        show(value)
        local member = s:memberAnywhere(sid)
        if member then
            s:setUserVolume(member, value)
        end
    end
    -- the arrows and the track: 10% a click (the scroll bar's own click
    -- handler calls onClickSlider)
    slider:setIncrementStep(VOLUME_PAGE)
    slider.onClickSlider = UI.volumePage
    volumePopup.zeroButton.onClick = function()
        slider:setValue(0)
    end
    volumePopup.fullButton.onClick = function()
        slider:setValue(100)
    end
    volumePopup.onMousePress = function(widget, mousePos)
        if not widget:containsPoint(mousePos) then
            UI.closePopups()
        end
        return true
    end
    volumePopup:grabMouse()
    volumePopup:focus()
    volumePopup.onKeyPress = function(widget, keyCode)
        if keyCode == KeyEscape then
            UI.closePopups()
            return true
        end
        return false
    end
end

-- reports ---------------------------------------------------------------------

-- own English keys: pt.lua already has "Offense" and "Other" with other meanings
local REASONS = {
    { 'ofensa', 'Insults' }, { 'assedio', 'Harassment' }, { 'spam', 'Spam' },
    { 'som_alto', 'Loud noise' }, { 'outro', 'Other reason' },
}

function UI.reportWindowFor(roomId, sid)
    local s = session()
    local room = s and s:roomById(roomId)
    local m = room and room.members[sid]
    if not m then
        return
    end
    UI.closePopups()
    local w = g_ui.createWidget('VoiceReportWindow', rootWidget)
    reportWindow = w
    w:setText(fmt('Report %s', S.latin1(m.name)))
    w.help:setText(tr('Tell the staff what happened. Who was in the room goes with the report.'))
    local why
    for _, r in ipairs(REASONS) do
        local b = g_ui.createWidget('VoiceReportReason', w.reasons)
        b:setText(tr(r[2]))
        b.onClick = function()
            why = r[1]
            for _, other in ipairs(w.reasons:getChildren()) do
                other:setChecked(other == b)
            end
        end
    end
    w.sendButton.onClick = function()
        if not why then
            w.status:setText(tr('Pick a reason.'))
            return
        end
        local sent, err = s:report(roomId, sid, why, w.text:getText())
        if not sent then
            w.status:setText(err == 'pending' and tr('Wait for the answer to your last report.') or
                tr('This player left the room.'))
            return
        end
        w.sendButton:setEnabled(false)
        w.status:setColor('#a39cbc')
        w.status:setText(tr('Sending...'))
        removeEvent(reportWait)
        reportWait = scheduleEvent(function()
            reportWait = nil
            if reportWindow == w then
                w.sendButton:setEnabled(true)
                w.status:setColor('#e0604a')
                w.status:setText(tr('The server did not answer. Try again in a moment.'))
            end
        end, REPORT_WAIT_MS)
    end
    w.onDestroy = function()
        if reportWindow == w then
            reportWindow = nil
        end
    end
    w:raise()
    w:focus()
    w.text:focus()
end

function UI.onReport(ok, code, secs)
    removeEvent(reportWait)
    reportWait = nil
    local text
    if code == 'sent' then
        text = tr('Report sent to the staff. Thank you!')
    elseif code == 'wait' then
        -- keys of their own: pt.lua's "another report" ones belong to the bug
        -- report (game_feedback) and say "relato"; a voice report is a denuncia
        text = fmt('Wait %d seconds before reporting again.', secs > 0 and secs or 30)
    elseif code == 'limit' then
        text = tr('You reported many players today. Thank you! Try again tomorrow.')
    else
        text = tr('The report could not be sent.')
    end
    if reportWindow and ok then
        reportWindow:destroy()
        reportWindow = nil
    elseif reportWindow then
        reportWindow.sendButton:setEnabled(true)
        reportWindow.status:setColor('#e0604a')
        reportWindow.status:setText(text)
        return
    end
    notify(text)
end
