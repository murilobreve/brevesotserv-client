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

local window, toggleButton
local sections = {} -- [slot] = { room, panel, rows = { [sid] = row }, shown, hidden, more, over }
local boxes = {}    -- party, guild, rooms: one container each, so a directory update leaves the others alone
local heads, headCount = {}, 0
local refreshEvent, roomsEvent, countdownEvent, dirEvent
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
    UI.onState()
    UI.scheduleRefresh()
end

function UI.destroy()
    UI.clearHeads()
    UI.closePopups()
    removeEvent(refreshEvent)
    removeEvent(roomsEvent)
    removeEvent(countdownEvent)
    removeEvent(dirEvent)
    refreshEvent, roomsEvent, countdownEvent, dirEvent = nil, nil, nil, nil
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

function UI.toggle()
    if not window then
        return
    end
    if window:isVisible() then
        window:close()
        return
    end
    if not window:getParent() then
        local panel = modules.game_interface.findContentPanelAvailable(window, window:getMinimumHeight())
        if not panel then
            return
        end
        panel:addChild(window)
    end
    window:open()
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

local function visible()
    return window ~= nil and window:isVisible()
end

-- the status line -------------------------------------------------------------

local function dateText(ts)
    return ts and ts > 0 and os.date('%d/%m %H:%M', ts) or '?'
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
        return tr('Voice'), COLOR_ON
    elseif state == ST.WAIT_TOKEN or state == ST.CONNECTING then
        return tr('Connecting...'), COLOR_WAIT
    elseif state == ST.BACKOFF then
        local secs = math.max(1, math.ceil(((s.retryAt or 0) - g_clock.millis()) / 1000))
        return tr('Voice unavailable'), COLOR_BAD, tr('Try now'), fmt('Trying again in %d s.', secs)
    elseif state == ST.FAILED then
        return tr('Voice unavailable'), COLOR_BAD, tr('Try again'), tr('The voice server did not answer.')
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

-- the BACKOFF countdown: one tick a second, only while it shows
local function scheduleCountdown()
    removeEvent(countdownEvent)
    countdownEvent = nil
    local s = session()
    if visible() and s and s.state == ST.BACKOFF then
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

local function header(parent, title, hint)
    local h = g_ui.createWidget('VoiceSectionHeader', parent)
    h.title:setText(title)
    h.hint:setText(hint or '')
    return h
end

local function note(parent, text)
    local label = g_ui.createWidget('VoiceNote', parent)
    label:setText(text)
    return label
end

-- "Hold F8" next to a section: only where this client can talk
local function keyHint(slot)
    local key = hasAudio() and talkKey(slot) or ''
    return key ~= '' and fmt('Hold %s', key) or ''
end

local function roomLabel(room)
    if room.kind == 'party' then
        return tr('Party')
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
    local tips = { S.latin1(m.name) }
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
    h.action:setVisible(true)
    h.action:setText(tr('Leave'))
    h.action.onClick = function()
        session():leave(room.id)
    end
end

local function partySection(parent, s)
    local h = header(parent, tr('PARTY'), keyHint(0))
    local room = s.rooms[0]
    if room then
        leaveButton(h, room)
        members(parent, room)
    elseif s.tokRooms.party then
        h.action:setVisible(true)
        h.action:setText(tr('Join'))
        h.action.onClick = function()
            s:join(s.tokRooms.party.id)
        end
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
            local label = r == officers and tr('Officers') or S.latin1(r.label or tr('Guild'))
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
    h.action:setVisible(true)
    h.action:setText(roomsOpen and tr('Hide') or tr('Show'))
    h.action.onClick = function()
        roomsOpen = not roomsOpen
        if roomsOpen then
            UI.startDir()
        else
            removeEvent(dirEvent)
            dirEvent = nil
        end
        UI.scheduleRooms()
    end
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

function UI.attachHead(key, cid)
    if heads[key] or headCount >= MAX_HEADS then
        return
    end
    local creature = g_map.getCreatureById(cid)
    if not creature or creature:isDead() or not creature:getPosition() then
        return
    end
    local widget = g_ui.createWidget('VoiceHeadIcon')
    creature:attachWidget(widget)
    heads[key] = widget
    headCount = headCount + 1
end

function UI.detachHead(key)
    local widget = heads[key]
    if not widget then
        return
    end
    heads[key] = nil
    headCount = headCount - 1
    if not widget:isDestroyed() then
        widget:destroy() -- also detaches it from the creature
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

-- a slider 0-200% for one player's volume; closes on a click outside
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
        text = fmt('Wait %d seconds before sending another report.', secs > 0 and secs or 30)
    elseif code == 'limit' then
        text = tr('You sent many reports today. Thank you! Try again tomorrow.')
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
