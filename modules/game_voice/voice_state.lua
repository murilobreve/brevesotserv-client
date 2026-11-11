-- Mythos Voz: the part of game_voice that knows the protocol and nothing of
-- the screen. It holds the connection state machine (opcode 142 with canary,
-- then the relay socket and its reconnects), the rooms and their members, the
-- control-message rate limit and the player's preferences (mute-for-me and
-- volume, kept by guid). It calls no g_* function and no widget: everything
-- outside goes through the `io` table given to VoiceState.new, so
-- tools/voz-luatest/game_voice_test.lua runs it in plain LuaJIT with stubs.
-- The wire formats are summed up in README.md, next to this file.
--
-- Lua 5.1 only (the browser build): no goto, no bit library, no // operator.

VoiceState = {}
local S = VoiceState

S.OPCODE = 142
S.MAX_OPCODE_BYTES = 2048 -- canary refuses more, and so do we
-- a roster entry is at most 66 bytes ([65535,4294967295,4294967295,"<29>",127]),
-- so the 500-member cap needs 33 KB; a bigger message is dropped whole
S.MAX_CTL_BYTES = 40960
S.MAX_TS = 4102444800     -- 2100-01-01: any later "until" is junk

S.ST = {
    OFF = 'off',               -- not in game
    WAIT_CFG = 'wait_cfg',     -- hi sent, the server has not answered (an old server never does)
    DISABLED = 'disabled',     -- cfg on=false: off, beta or a bad URL
    READY = 'ready',           -- voice offered, the player has not turned it on
    WAIT_TOKEN = 'wait_token', -- want or tok sent, waiting for a token
    CONNECTING = 'connecting', -- the engine is opening the socket, waiting for welcome
    ONLINE = 'online',
    BACKOFF = 'backoff',       -- waiting retryAt before the next try
    FAILED = 'failed',         -- too many failures in a row: a retry a minute, or a manual one
    BLOCKED = 'blocked',       -- banned, replaced or switched off: no retry by itself
}
local ST = S.ST

-- four slots, the audio flags' bits 0-1: party, guild or officers, a public
-- room, event or the echo test, and proximity ("Near you")
S.SLOT_PARTY, S.SLOT_GUILD, S.SLOT_ROOM, S.SLOT_NEAR = 0, 1, 2, 3
S.LAST_SLOT = 3
S.SLOT_OF = { party = 0, guild = 1, officers = 1, public = 2, stage = 2, echo = 2, near = 3 }
S.NEAR_ROOM = 'near' -- one per relay, like the public rooms

-- member flags (protocol G)
S.F_SELF_MUTED, S.F_DEAF, S.F_SERVER_MUTED = 1, 2, 4
S.F_STAGE, S.F_STAFF, S.F_MODERATOR, S.F_LITE = 8, 16, 32, 64

-- seconds; capped at 15 s so a relay back after an outage is found within
-- 20 s (the play-test: 40 s after a one-minute outage with steps up to 60 s)
S.BACKOFF_STEPS = { 1, 2, 4, 8, 15 }
S.JITTER = 0.3
-- FAILED after about 4 minutes of retries, as with the old steps (10 tries
-- up to 60 s): 1+2+4+8 s, then 16 tries 15 s apart
S.MAX_FAILURES = 20
-- FAILED still tries by itself, once a minute (+-30%): a relay restart or a
-- VPS reboot of a few minutes must not leave every player without voice
-- until each one clicks "Try again"
S.FAILED_RETRY_MS = 60000
S.STABLE_MS = 30000       -- online this long: the failure count starts again
S.TOKEN_FRESH_MS = 100000 -- tokens live 120 s; 20 s of margin for the clocks
S.TOKEN_GAP_MS = 3000     -- canary: 1 tok request per 3 s
S.TOKEN_BUDGET = 30       -- and 30 per 10 minutes
S.TOKEN_WINDOW_MS = 600000
S.TOKEN_WAIT_MS = 10000   -- no token after this: count a failure
S.CONNECT_WAIT_MS = 15000 -- no welcome after this: count a failure
S.HI_GAP_MS = 10000
S.WANT_GAP_MS = 3000
S.DIR_GAP_MS = 2000
S.JOIN_BUDGET, S.JOIN_WINDOW_MS = 10, 60000 -- the relay: 10 joins a minute, then 4429
-- the relay allows 5/s, burst 10; the queue holds one mute per muted player
-- of a big guild roster (the relay keeps up to 256 per listener)
S.CTL_RATE, S.CTL_BURST, S.CTL_QUEUE = 4, 8, 256
S.MAX_MEMBERS = 500
S.MAX_DIR = 50
S.ROW_CAP = 40
S.USERS_CAP = 500
S.CHARS_CAP = 100
S.REPORT_TXT, S.REPORT_WHO = 300, 25
S.REPORT_WHY = { ofensa = true, assedio = true, spam = true, som_alto = true, outro = true }
S.REPORT_WAIT_MS = 10000
S.MOD_OPS = { kick = true, mute = true, unmute = true, speak = true, nospeak = true }
-- proximity: the players this client shows on screen (same floor, 7 tiles
-- left and right, 5 up and down), the nearest 40, checked every 500 ms and
-- sent only when the set changed; the distance and pan of who talks near
-- us every 200 ms, given to the engine only on a change over 0.02
S.NEAR_RANGE_X, S.NEAR_RANGE_Y, S.NEAR_MAX = 7, 5, 40
S.NEAR_GAP_MS = 500
S.SPATIAL_GAP_MS = 200
S.SPATIAL_STEP = 0.02

-- helpers --------------------------------------------------------------------

function S.hasFlag(flags, bit)
    return math.floor((tonumber(flags) or 0) / bit) % 2 == 1
end

local function isInt(v, lo, hi)
    return type(v) == 'number' and v == math.floor(v) and v >= lo and v <= hi
end

local function shortString(v, maxLen)
    return type(v) == 'string' and #v >= 1 and #v <= maxLen
end

-- a name or label from the server without control characters (a line
-- break would break the row), or nil when it is not a short string
local function label(v, maxLen)
    return shortString(v, maxLen) and (v:gsub('[%z\1-\31]', '')) or nil
end

-- a whole number from the server within [lo, hi], else `default`: text,
-- tables, NaN ("nan" reads as a number) and infinities never reach the
-- timers, string.format or os.date
function S.num(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v then
        return default
    end
    return math.max(lo, math.min(hi, math.floor(v)))
end

-- the fonts draw one glyph per byte (Latin-1); the server sends UTF-8
function S.latin1(text)
    return (tostring(text or ''):gsub('[\192-\255][\128-\191]*', function(seq)
        local a, b = seq:byte(1, 2)
        if #seq == 2 and (a == 194 or a == 195) then
            return string.char((a - 194) * 64 + b)
        end
        return '?'
    end))
end

-- room ids: [a-z0-9:_-]{1,40} (protocol K)
function S.roomKind(id)
    if type(id) ~= 'string' or #id > 40 or not id:find('^[a-z0-9:_%-]+$') then
        return nil
    end
    if id == 'echo' then
        return 'echo'
    elseif id == 'near' then
        return 'near'
    elseif id:find('^p:%d+:%d+$') then
        return 'party'
    elseif id:find('^g:%d+:o$') then
        return 'officers'
    elseif id:find('^g:%d+$') then
        return 'guild'
    elseif id:find('^pub:[a-z0-9_%-]+$') then
        return 'public'
    elseif id:find('^ev:[a-z0-9_%-]+$') then
        return 'stage'
    end
    return nil -- 'prox' and anything newer: not handled by this client
end

-- a JSON object from the server or the relay, or nil: never raises
function S.decode(text, maxBytes)
    if type(text) ~= 'string' or #text < 2 or #text > (maxBytes or S.MAX_CTL_BYTES) then
        return nil
    end
    if not text:find('^%s*{') then
        return nil
    end
    local ok, data = pcall(json.decode, text)
    if ok and type(data) == 'table' then
        return data
    end
    return nil
end

-- a websocket URL from cfg, or nil
function S.checkUrl(url)
    if type(url) == 'string' and #url <= 200 and
        url:find('^wss?://[%w%.%-]+:?%d*/[%w%._~/%-]*$') then
        return url
    end
    return nil
end

local function jitter(ms, rand)
    return math.floor(ms * (1 + (rand * 2 - 1) * S.JITTER))
end

-- the wait before the n-th retry, in ms: 1, 2, 4, 8, then 15 s, +-30%
function S.backoffDelay(failures, rand)
    local step = S.BACKOFF_STEPS[math.max(1, math.min(failures, #S.BACKOFF_STEPS))]
    return jitter(step * 1000, rand)
end

-- the wait between the slow retries of FAILED, in ms: 60 s +-30%
function S.failedDelay(rand)
    return jitter(S.FAILED_RETRY_MS, rand)
end

-- what a close code asks of us (protocol H)
function S.closeAction(code)
    if code == 4401 then
        return 'reauth'
    elseif code == 4403 then
        return 'block', 'banned'
    elseif code == 4409 then
        return 'block', 'replaced'
    elseif code == 4503 then
        return 'block', 'off'
    elseif code == 1012 then
        return 'restart'
    end
    return 'backoff' -- 4429, 4408, 1000 from the relay, network errors, unknown
end

-- a key that types in the chat while it is on (letters, digits, Enter,
-- arrows...), unless Ctrl or Alt is held: no good for push-to-talk then
local KEY_TAB, KEY_BACKSPACE, KEY_ENTER, KEY_DELETE = 2, 3, 5, 7
local KEY_UP, KEY_RIGHT = 14, 17
local KEY_NUMPAD0, KEY_NUMPAD9 = 141, 150
local MOD_CTRL, MOD_ALT = 1, 2

function S.isChatKey(keyCode, modifiers)
    modifiers = modifiers or 0
    if S.hasFlag(modifiers, MOD_CTRL) or S.hasFlag(modifiers, MOD_ALT) then
        return false
    end
    return (keyCode >= 32 and keyCode <= 126) or (keyCode >= KEY_UP and keyCode <= KEY_RIGHT) or
        (keyCode >= KEY_NUMPAD0 and keyCode <= KEY_NUMPAD9) or keyCode == KEY_TAB or keyCode == KEY_BACKSPACE or
        keyCode == KEY_ENTER or keyCode == KEY_DELETE
end

-- the Windows virtual-key code of a key name, for push-to-talk with the game
-- in the background (letters, digits, F1-F24, Space); 0 if there is none
function S.virtualKey(desc)
    desc = tostring(desc or '')
    if desc:find('^%u$') or desc:find('^%d$') then
        return desc:byte()
    elseif desc == 'Space' then
        return 0x20
    end
    local n = tonumber(desc:match('^F(%d%d?)$'))
    if n and n >= 1 and n <= 24 then
        return 0x6F + n
    end
    return 0
end

-- preferences (g_settings node 'voice') ---------------------------------------

-- Per installation: the hardware, the keys and the players muted for me.
-- The opt-in is per character (prefs.chars): on a shared computer the next
-- player's character must not join rooms and hear them by itself.
S.DEFAULT_PREFS = {
    onboarded = false,
    -- voice activation by default (2026-11-11, the owner: no key to hold);
    -- modeV 1 moved every saved 'ptt' to it once
    mode = 'vad', modeV = 1, vadDb = -45, inGain = 100, outVol = 100, preset = 'normal',
    autoParty = true, autoGuild = false, autoNear = true, overheadIcon = true, ducking = false,
    globalPtt = false, pttMouse = 0, selfMuted = false, deafened = false,
    inDevice = '', outDevice = '', -- '' is the system default
}
local PRESETS = { normal = true, eco = true, high = true }

-- OTML gives back booleans, numbers or strings depending on how a value reads
local function toBool(v, default)
    if type(v) == 'boolean' then
        return v
    elseif v == 'true' or v == 1 or v == '1' then
        return true
    elseif v == 'false' or v == 0 or v == '0' then
        return false
    end
    return default
end

local function toInt(v, lo, hi, default)
    if type(v) == 'boolean' then
        v = v and 1 or 0
    end
    v = tonumber(v)
    if not v or v ~= v then
        return default
    end
    return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

function S.normalizePrefs(raw)
    raw = type(raw) == 'table' and raw or {}
    local d = S.DEFAULT_PREFS
    local p = {}
    for _, key in ipairs({ 'onboarded', 'autoParty', 'autoGuild', 'autoNear', 'overheadIcon', 'ducking',
        'globalPtt', 'selfMuted', 'deafened' }) do
        p[key] = toBool(raw[key], d[key])
    end
    p.mode = (raw.mode == 'ptt') and 'ptt' or 'vad'
    p.modeV = toInt(raw.modeV, 0, 99, 0)
    if p.modeV < 1 then
        p.mode, p.modeV = 'vad', 1 -- push-to-talk was the default before
    end
    p.vadDb = toInt(raw.vadDb, -60, -20, d.vadDb)
    p.inGain = toInt(raw.inGain, 0, 200, d.inGain)
    p.outVol = toInt(raw.outVol, 0, 200, d.outVol)
    p.preset = PRESETS[raw.preset] and raw.preset or d.preset
    -- the browser's side buttons: 3 (back) or 4 (forward), 0 for none
    local mouse = toInt(raw.pttMouse, 0, 4, 0)
    p.pttMouse = (mouse == 3 or mouse == 4) and mouse or 0
    for _, key in ipairs({ 'inDevice', 'outDevice' }) do
        local v = raw[key]
        -- OTML reads a device named "2" or "true" back as a number or a boolean
        if type(v) == 'number' or type(v) == 'boolean' then
            v = tostring(v)
        end
        p[key] = (type(v) == 'string' and #v <= 128) and v or ''
    end
    p.users = {}
    local users = type(raw.users) == 'table' and raw.users or {}
    for key, entry in pairs(users) do
        if type(key) == 'string' and key:find('^g%d+$') and type(entry) == 'table' then
            local v = toInt(entry.v, 0, 200, 100)
            local m = toBool(entry.m, false)
            if v ~= 100 or m then
                p.users[key] = { v = v, m = m, t = toInt(entry.t, 0, 2 ^ 31, 0) }
            end
        end
    end
    S.prune(p.users, S.USERS_CAP)
    -- the characters that turned voice on: later logins send want by themselves
    p.chars = {}
    local chars = type(raw.chars) == 'table' and raw.chars or {}
    for name, entry in pairs(chars) do
        if type(name) == 'string' and #name >= 1 and #name <= 40 and type(entry) == 'table' then
            p.chars[name] = { t = toInt(entry.t, 0, 2 ^ 31, 0) }
        end
    end
    S.prune(p.chars, S.CHARS_CAP)
    return p
end

-- a plain copy for g_settings (string keys only: OTML loses numeric ones)
function S.serializePrefs(p)
    local out = {}
    for key in pairs(S.DEFAULT_PREFS) do
        out[key] = p[key]
    end
    out.users = {}
    for key, entry in pairs(p.users) do
        out.users[key] = { v = entry.v, m = entry.m, t = entry.t }
    end
    out.chars = {}
    for name, entry in pairs(p.chars) do
        out.chars[name] = { t = entry.t }
    end
    return out
end

-- at most `cap` entries ({ t = stamp } each): the least recently used go first
function S.prune(entries, cap)
    local list = {}
    for key, entry in pairs(entries) do
        list[#list + 1] = { key = key, t = entry.t or 0 }
    end
    if #list <= cap then
        return
    end
    table.sort(list, function(a, b)
        if a.t ~= b.t then
            return a.t < b.t
        end
        return a.key < b.key
    end)
    for i = 1, #list - cap do
        entries[list[i].key] = nil
    end
end

function S.userPref(prefs, guid)
    return prefs.users['g' .. tostring(guid)]
end

-- changes a player's volume (v, 0-200) or mute-for-me (m); `stamp` orders
-- the entries for pruning. An entry back at the defaults is dropped.
function S.setUserPref(prefs, guid, field, value, stamp)
    local key = 'g' .. tostring(guid)
    local entry = prefs.users[key] or { v = 100, m = false }
    entry[field] = value
    entry.t = stamp
    if entry.v == 100 and not entry.m then
        prefs.users[key] = nil
    else
        prefs.users[key] = entry
        S.prune(prefs.users, S.USERS_CAP)
    end
end

-- members ---------------------------------------------------------------------

-- [sid, cid, guid, "Name", flags] -> member table, or nil if malformed
function S.parseMember(u)
    if type(u) ~= 'table' then
        return nil
    end
    local sid, cid, guid, name, flags = u[1], u[2], u[3], u[4], u[5]
    if not (isInt(sid, 1, 65535) and isInt(cid, 0, 2 ^ 32 - 1) and isInt(guid, 0, 2 ^ 32 - 1) and
        shortString(name, 40) and isInt(flags or 0, 0, 255)) then
        return nil
    end
    return { sid = sid, cid = cid, guid = guid, name = label(name, 40), flags = flags or 0,
        speaking = false, mutedForMe = false }
end

local function rank(m)
    if m.speaking then
        return 0
    elseif S.hasFlag(m.flags, S.F_MODERATOR) or S.hasFlag(m.flags, S.F_STAFF) then
        return 1
    end
    return 2
end

-- the rows a room shows: speaking first, then moderators, then by name;
-- at most `cap`, and how many are left out ("+N in the room")
function S.visibleMembers(room, cap)
    local list = {}
    for _, m in pairs(room.members) do
        list[#list + 1] = m
    end
    table.sort(list, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then
            return ra < rb
        end
        local na, nb = a.name:lower(), b.name:lower()
        if na ~= nb then
            return na < nb
        end
        return a.sid < b.sid
    end)
    local hidden = 0
    if #list > cap then
        hidden = #list - cap
        for i = #list, cap + 1, -1 do
            list[i] = nil
        end
    end
    return list, hidden
end

-- the opcode 142 report, within canary's 2048 bytes, or nil and why
function S.buildReport(room, target, why, text)
    if not S.REPORT_WHY[why] then
        return nil, 'why'
    end
    if not room or not target then
        return nil, 'target'
    end
    text = tostring(text or ''):gsub('[%z\1-\31]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #text > S.REPORT_TXT then
        text = text:sub(1, S.REPORT_TXT)
    end
    -- who was in the room: the reported player first
    local who = { target.name }
    for _, m in pairs(room.members) do
        if #who >= S.REPORT_WHO then
            break
        end
        if m.sid ~= target.sid then
            who[#who + 1] = m.name
        end
    end
    local msg = { a = 'report', c = target.guid, n = target.name, room = room.id, why = why, txt = text, who = who }
    while #json.encode(msg) > S.MAX_OPCODE_BYTES and #who > 1 do
        who[#who] = nil
    end
    if #json.encode(msg) > S.MAX_OPCODE_BYTES then
        return nil, 'size'
    end
    return msg
end

-- proximity ---------------------------------------------------------------------

-- The creature ids of the players this client shows around `me` ({ id, pos },
-- the local player): the same floor, at most NEAR_RANGE_X tiles left or
-- right and NEAR_RANGE_Y up or down, never `me`; nearest first (then by id),
-- at most NEAR_MAX. `creatures` come from the map (getId, getPosition,
-- isPlayer, isLocalPlayer, isDead): a dead one or one without a position is
-- skipped (AGENTS.md, dead creatures in deferred code).
function S.nearList(me, creatures)
    local found, seen = {}, {}
    local at = type(me) == 'table' and me.pos
    if not at or type(creatures) ~= 'table' then
        return found
    end
    for _, c in ipairs(creatures) do
        if c:isPlayer() and not c:isLocalPlayer() and not c:isDead() then
            local id, pos = c:getId(), c:getPosition()
            if pos and pos.z == at.z and isInt(id, 1, 2 ^ 32 - 1) and id ~= me.id and not seen[id] then
                local dx, dy = pos.x - at.x, pos.y - at.y
                if math.abs(dx) <= S.NEAR_RANGE_X and math.abs(dy) <= S.NEAR_RANGE_Y then
                    seen[id] = true
                    found[#found + 1] = { id = id, d = dx * dx + dy * dy }
                end
            end
        end
    end
    table.sort(found, function(a, b)
        if a.d ~= b.d then
            return a.d < b.d
        end
        return a.id < b.id
    end)
    local ids = {}
    for i = 1, math.min(#found, S.NEAR_MAX) do
        ids[i] = found[i].id
    end
    return ids
end

-- the gain (1 up to 1.5 tiles away, then 0.11 less a tile, never under 0.2)
-- and the pan (-0.75 left to 0.75 right, full at 7 tiles) of a speaker
-- dx, dy tiles from us
-- off: near voices play like any other (no distance, no left/right); the
-- code stays for a later try (voice.lua's canSpatial reads this)
S.SPATIAL = false

function S.spatial(dx, dy)
    local d = math.sqrt(dx * dx + dy * dy)
    local gain = math.max(0.2, math.min(1, 1 - math.max(0, d - 1.5) * 0.11))
    local pan = math.max(-1, math.min(1, dx / 7)) * 0.75
    return gain, pan
end

-- the session -----------------------------------------------------------------

local Session = {}
Session.__index = Session

-- io: now() ms, time() unix s, random() [0,1), send142(t), connect(url, tok),
-- disconnect(), sendCtl(t), schedule(name, ms), cancel(name), savePrefs(p),
-- emit(what, ...), engine(method, ...); for proximity: nearby() (the ids of
-- S.nearList), offset(cid) (dx, dy in tiles, or nil when that creature is
-- not on our floor, gone or dead) and canSpatial() (the engine pans)
function S.new(io, prefs)
    local self = setmetatable({ io = io, prefs = prefs or S.normalizePrefs(nil) }, Session)
    self.lastHi, self.lastWant, self.lastDir = -1e12, -1e12, -1e12
    self.tokReqs = {} -- times of the token requests in the last 10 minutes
    self:reset()
    return self
end

local TIMERS = { 'hi', 'want', 'tokreq', 'tokwait', 'connect', 'retry', 'ctl', 'near', 'spatial' }

-- everything that belongs to one login
function Session:reset()
    self.state, self.why, self.untilTs = ST.OFF, nil, nil
    self.cfg, self.everOn, self.shown, self.hello, self.char = nil, false, false, nil, nil
    self.tok, self.tokRooms, self.tokSig = nil, {}, ''
    self.failures, self.onlineAt, self.reauthUsed, self.retryAt = 0, nil, false, nil
    self.pendingWant, self.reportAt = nil, nil
    -- what to join again after a reconnect: [slot] = room id (slots 1 to 3)
    self.intents = {}
    -- party/guild rooms and near the player left by hand: no auto-join back into them
    self.optOut = {}
    self:clearSession()
end

-- everything that belongs to one relay session
function Session:clearSession()
    self.sid = nil
    self.rooms = {} -- [slot] = room
    self.dir = {}
    self.speaking, self.speakingCount = {}, 0
    self.talkSlot = -1
    self.joining = {} -- [id] = true: rooms an auto-join asked for, until their roster
    self.joins = {} -- times of the joins sent in this relay session (the last minute)
    self.queue, self.bucket, self.bucketAt = {}, S.CTL_BURST, nil
    self.mutedUntil = 0
    -- proximity: { lvl } from welcome when this relay has it (else nil)
    self.near = nil
    self.nearHold = false -- refused or sent out: no auto-join until the next welcome
    self.nearSig, self.nearSentAt = nil, -1e12 -- the list as last sent, and when
    self.spatial, self.spatialOn = {}, false -- [sid] = { gain, pan } as given to the engine
end

-- `force`: tell the UI even if only retryAt changed
function Session:setState(state, why, untilTs, force)
    if not force and self.state == state and self.why == why and self.untilTs == untilTs then
        return
    end
    self.state, self.why, self.untilTs = state, why, untilTs
    self.io.emit('state')
end

function Session:isActive()
    local s = self.state
    return s == ST.WAIT_TOKEN or s == ST.CONNECTING or s == ST.ONLINE or s == ST.BACKOFF or s == ST.FAILED
end

-- the UI shows once voice was offered in this login, or to tell of a ban
function Session:isVisible()
    return self.everOn or (self.state == ST.BLOCKED and self.why == 'banned')
end

-- this character turned voice on in this installation (see DEFAULT_PREFS)
function Session:optedIn()
    return self.char ~= nil and self.prefs.chars[self.char] ~= nil
end

-- the first time something shows in this login (voice offered, or a ban to
-- tell of) the UI is made: 'cfg' for voice.lua
function Session:show()
    if not self.shown and self:isVisible() then
        self.shown = true
        self.io.emit('cfg')
    end
end

-- game ------------------------------------------------------------------------

-- char: the character's name, the key of its opt-in
function Session:gameStart(cl, eng, char)
    self:gameEnd()
    self.hello = { cl = cl, eng = eng }
    self.char = type(char) == 'string' and #char >= 1 and #char <= 40 and char or nil
    self.state = ST.WAIT_CFG
    self:sendHi()
end

function Session:sendHi()
    local wait = self.lastHi + S.HI_GAP_MS - self.io.now()
    if wait > 0 then
        self.io.schedule('hi', wait)
        return
    end
    self.lastHi = self.io.now()
    self.io.send142({ a = 'hi', v = 1, cl = self.hello.cl, eng = self.hello.eng })
end

function Session:gameEnd()
    local wasOff = self.state == ST.OFF
    self:dropConnection(true)
    for _, name in ipairs(TIMERS) do
        self.io.cancel(name)
    end
    self:reset()
    if not wasOff then
        self.io.emit('state')
    end
end

-- forgets the relay session; `close`: the socket is still open, close it
function Session:dropConnection(close)
    if close and (self.state == ST.CONNECTING or self.state == ST.ONLINE) then
        self.io.disconnect()
    end
    for _, name in ipairs({ 'connect', 'ctl', 'near', 'spatial' }) do
        self.io.cancel(name)
    end
    local hadRooms = next(self.rooms) ~= nil
    local wasSpeaking = self.speakingCount > 0
    self:clearSession()
    if wasSpeaking then
        self.io.emit('speakers', 0)
    end
    if hadRooms then
        self.io.emit('rooms')
    end
end

-- opcode 142 ------------------------------------------------------------------

function Session:onOpcode(data)
    if type(data) ~= 'table' or self.state == ST.OFF then
        return
    end
    local a = data.a
    if a == 'cfg' then
        self:onCfg(data)
    elseif a == 'tok' then
        self:onTok(data)
    elseif a == 'err' then
        self:onServerErr(data)
    elseif a == 'rep' and self.reportAt then -- only the answer to a report we sent
        self.reportAt = nil
        self.io.emit('report', data.ok == true, type(data.code) == 'string' and data.code or '',
            S.num(data.s, 0, 86400, 0))
    end
end

function Session:stopTrying()
    self:dropConnection(true)
    for _, name in ipairs({ 'tokreq', 'tokwait', 'retry' }) do
        self.io.cancel(name)
    end
    self.tok, self.retryAt = nil, nil
end

function Session:onCfg(data)
    if data.on == true then
        local url = S.checkUrl(data.url)
        if not url then
            self:stopTrying()
            self:setState(ST.DISABLED, 'url')
            return
        end
        self.cfg = { url = url, psl = S.num(data.psl, 0, 1000, 50) }
        self.everOn = true
        self:show()
        -- canary says voice is on (a restart, a new relay address) while we
        -- wait to retry: the retry is now
        if self.state == ST.BACKOFF or self.state == ST.FAILED then
            self:retryNow()
            return
        end
        -- a session replaced by another window stays so until the player
        -- reconnects by hand: two windows would replace each other forever
        if not self:isActive() and not (self.state == ST.BLOCKED and self.why == 'replaced') then
            -- also the way back from the kill switch or the end of a ban
            self:setState(ST.READY)
            if self:optedIn() then
                self:setWant(true)
            end
        end
    elseif data.on == false then
        self:stopTrying()
        local why = type(data.why) == 'string' and data.why or 'off'
        if why == 'banned' then
            self:setState(ST.BLOCKED, 'banned', S.num(data['until'], 0, S.MAX_TS, 0))
            self:show()
        elseif self.everOn then
            -- switched off while the panel was there: it says so
            self:setState(ST.BLOCKED, 'off')
        else
            self:setState(ST.DISABLED, why == 'beta' and 'beta' or 'off')
        end
    end
end

local ROOM_KINDS_IN_TOK = { party = true, guild = true, officers = true }

function Session:onTok(data)
    local tok = data.tok
    if type(tok) ~= 'string' or #tok < 16 or #tok > 1024 or not tok:find('^[%w_%-]+%.[%w_%-]+$') then
        return
    end
    if not self:isActive() then
        return -- want is off: a late token is of no use
    end
    self.io.cancel('tokwait')
    self.tok = { tok = tok, at = self.io.now(), used = false }
    local rooms = {}
    if type(data.rooms) == 'table' then
        for i = 1, math.min(#data.rooms, 8) do
            local r = data.rooms[i]
            if type(r) == 'table' and ROOM_KINDS_IN_TOK[r.k] and S.roomKind(r.id) == r.k then
                rooms[r.k] = { id = r.id, label = label(r.l, 64) }
            end
        end
    end
    -- canary pushes a token every 240 s: the panel is drawn again only when
    -- the rooms it lists changed
    local sig = {}
    for _, kind in ipairs({ 'party', 'guild', 'officers' }) do
        local r = rooms[kind]
        sig[#sig + 1] = r and (r.id .. '=' .. (r.label or '')) or ''
    end
    sig = table.concat(sig, ',')
    self.tokRooms = rooms
    if sig ~= self.tokSig then
        self.tokSig = sig
        self.io.emit('tok')
    end
    if self.state == ST.WAIT_TOKEN then
        self:connectNow()
    elseif self.state == ST.BACKOFF or self.state == ST.FAILED then
        -- a fresh token while we wait to retry (canary pushes one every
        -- 240 s, or answers a late request): the retry is now, with it
        self:retryNow()
    elseif self.state == ST.ONLINE then
        self:useTokenForAuth()
        self:autoJoin()
    end
    -- CONNECTING: kept, and used for an auth right after welcome
end

function Session:onServerErr(data)
    local code = data.code
    local secs = S.num(data.s, 1, S.MAX_TS, 3)
    if code == 'rate' then
        if self.state == ST.WAIT_TOKEN then
            self.io.cancel('tokwait')
            self.io.schedule('tokreq', math.min(secs, 600) * 1000)
        end
    elseif code == 'off' then
        self:stopTrying()
        self:setState(ST.BLOCKED, 'off')
    elseif code == 'banned' then
        self:stopTrying()
        self:setState(ST.BLOCKED, 'banned', math.min(self.io.time() + secs, S.MAX_TS))
        self:show()
    end
end

-- the player's switch ("Turn voice on"); canary answers want=true with a token
function Session:setWant(on)
    if not self.everOn or self.state == ST.DISABLED or (self.state == ST.BLOCKED and self.why ~= 'replaced') then
        return false
    end
    if self.char and self:optedIn() ~= on then
        self.prefs.chars[self.char] = on and { t = self.io.time() } or nil
        S.prune(self.prefs.chars, S.CHARS_CAP)
        self.io.savePrefs(self.prefs)
    end
    self:stopTrying()
    if on then
        self.failures, self.reauthUsed = 0, false
        self:setState(ST.WAIT_TOKEN)
        -- the want is the token request: the next {a='tok'} keeps 3 s from it
        local delay = math.max(0, self.lastWant + S.WANT_GAP_MS - self.io.now())
        self.tokReqs[#self.tokReqs + 1] = self.io.now() + delay
        self.io.schedule('tokwait', S.TOKEN_WAIT_MS + delay)
    else
        self:setState(ST.READY)
    end
    -- last: the answer may come at once
    self.pendingWant = on
    self:flushWant()
    return true
end

-- sends the pending want now, or arms its timer
function Session:flushWant()
    if self.pendingWant == nil then
        return
    end
    local wait = self.lastWant + S.WANT_GAP_MS - self.io.now()
    if wait > 0 then
        self.io.schedule('want', wait)
        return
    end
    local on = self.pendingWant
    self.lastWant = self.io.now()
    self.pendingWant = nil
    self.io.send142({ a = 'want', on = on })
end

-- asks canary for a token, within its limits (1 per 3 s, 30 per 10 min)
function Session:requestToken()
    self:setState(ST.WAIT_TOKEN)
    local now = self.io.now()
    local reqs = self.tokReqs
    while #reqs > 0 and now - reqs[1] >= S.TOKEN_WINDOW_MS do
        table.remove(reqs, 1)
    end
    local earliest = now
    if #reqs > 0 then
        earliest = math.max(earliest, reqs[#reqs] + S.TOKEN_GAP_MS)
    end
    if #reqs >= S.TOKEN_BUDGET then
        earliest = math.max(earliest, reqs[1] + S.TOKEN_WINDOW_MS)
    end
    if earliest > now then
        self.io.schedule('tokreq', earliest - now)
        return
    end
    reqs[#reqs + 1] = now
    self.io.send142({ a = 'tok' })
    self.io.schedule('tokwait', S.TOKEN_WAIT_MS)
end

function Session:freshToken()
    local t = self.tok
    return t ~= nil and not t.used and self.io.now() - t.at < S.TOKEN_FRESH_MS
end

-- connects with the last token if it is still good, else asks for one
function Session:connectNow()
    if not self:freshToken() then
        self:requestToken()
        return
    end
    self.tok.used = true
    self:setState(ST.CONNECTING)
    self.io.schedule('connect', S.CONNECT_WAIT_MS)
    self.io.connect(self.cfg.url, self.tok.tok)
end

function Session:useTokenForAuth()
    if self:freshToken() then
        self.tok.used = true
        self:send({ t = 'auth', tok = self.tok.tok })
    end
end

-- timers ----------------------------------------------------------------------

function Session:onTimer(name)
    if name == 'hi' then
        if self.state == ST.WAIT_CFG then
            self:sendHi()
        end
    elseif name == 'want' then
        self:flushWant()
    elseif name == 'tokreq' then
        if self.state == ST.WAIT_TOKEN then
            self:requestToken()
        end
    elseif name == 'tokwait' then
        if self.state == ST.WAIT_TOKEN then
            self:fail(nil)
        end
    elseif name == 'connect' then
        if self.state == ST.CONNECTING then
            self:dropConnection(true)
            self:fail(nil)
        end
    elseif name == 'retry' then
        if self.state == ST.BACKOFF or self.state == ST.FAILED then
            self:connectNow()
        end
    elseif name == 'ctl' then
        self:drainQueue()
    elseif name == 'near' then
        self:nearTick()
    elseif name == 'spatial' then
        self:spatialTick()
    end
end

-- engine ----------------------------------------------------------------------

-- 'connecting' and 'open' need nothing: welcome is what counts
function Session:onEngineState(s, code)
    if s ~= 'closed' and s ~= 'error' then
        return
    end
    if self.state ~= ST.CONNECTING and self.state ~= ST.ONLINE then
        return -- a socket we already gave up on
    end
    local stable = self.state == ST.ONLINE and self.io.now() - self.onlineAt >= S.STABLE_MS
    self:dropConnection(false)
    if stable then
        self.failures, self.reauthUsed = 0, false
    end
    self:fail(tonumber(code))
end

-- a failed try: what next depends on the close code (protocol H)
function Session:fail(code)
    local action, why = S.closeAction(code)
    if action == 'reauth' and not self.reauthUsed then
        self.reauthUsed = true
        self.tok = nil
        self:requestToken()
        return
    elseif action == 'block' then
        self.tok, self.retryAt = nil, nil
        self:setState(ST.BLOCKED, why)
        return
    elseif action == 'restart' then
        self:backoff(1000 + math.floor(self.io.random() * 4000))
        return
    end
    self.failures = self.failures + 1
    if self.failures >= S.MAX_FAILURES then
        -- still tries, once a minute: never only by hand
        self:backoff(S.failedDelay(self.io.random()), ST.FAILED)
        return
    end
    self:backoff(S.backoffDelay(self.failures, self.io.random()))
end

-- waits `delay` ms in BACKOFF (or FAILED) before the next try
function Session:backoff(delay, state)
    self.retryAt = self.io.now() + delay
    self.io.schedule('retry', delay)
    self:setState(state or ST.BACKOFF, nil, nil, true)
end

-- "Try again now", in backoff, failed or replaced; also a fresh token or a
-- cfg on from canary while waiting to retry
function Session:retryNow()
    local s = self.state
    if s == ST.BACKOFF or s == ST.FAILED or (s == ST.BLOCKED and self.why == 'replaced') then
        self.io.cancel('retry')
        self.retryAt = nil
        if s == ST.BLOCKED then
            self.failures = 0
        end
        self:connectNow()
        return true
    end
    return false
end

-- relay control messages --------------------------------------------------------

-- handlers by message type (t), after welcome
local CTL = {}

function Session:onControl(text)
    local msg = S.decode(text, S.MAX_CTL_BYTES)
    if not msg or type(msg.t) ~= 'string' then
        return
    end
    local t = msg.t
    if t == 'welcome' then
        self:onWelcome(msg)
        return
    end
    if self.state ~= ST.ONLINE then
        return
    end
    local handler = CTL[t]
    if handler then
        handler(self, msg)
    end
end

function Session:onWelcome(msg)
    if self.state ~= ST.CONNECTING or not isInt(msg.sid, 1, 65535) then
        return
    end
    self.io.cancel('connect')
    self.sid = msg.sid
    self.onlineAt = self.io.now()
    self.retryAt = nil
    -- this relay has proximity (absent: it has none, and the panel shows nothing of it)
    if type(msg.near) == 'table' then
        self.near = { lvl = S.num(msg.near.lvl, 0, 65535, 8) }
    else
        self.intents[S.SLOT_NEAR] = nil
    end
    self:setState(ST.ONLINE)
    -- a token that came while connecting carries newer rights
    self:useTokenForAuth()
    if self.prefs.deafened then
        self:send({ t = 'deaf', on = 1 })
    end
    if self.prefs.selfMuted then
        self:send({ t = 'self', m = 1 })
    end
    self:autoJoin()
    -- the guild/officers room and the public room or event of before the drop
    local guild, officers = self.tokRooms.guild, self.tokRooms.officers
    local id = self.intents[1]
    if id and (guild and guild.id == id or officers and officers.id == id) then
        self:sendJoin(id)
    else
        self.intents[1] = nil
    end
    if self.intents[2] then
        self:sendJoin(self.intents[2])
    end
end

-- a join within the relay's budget; false when it would be over
function Session:sendJoin(id)
    local now, joins = self.io.now(), self.joins
    while #joins > 0 and now - joins[1] >= S.JOIN_WINDOW_MS do
        table.remove(joins, 1)
    end
    if #joins >= S.JOIN_BUDGET then
        return false
    end
    joins[#joins + 1] = now
    self:send({ t = 'join', room = id })
    return true
end

-- the party room, the guild room if the player wants it, and near (with
-- autoNear, or joined before a reconnect) when this relay has it, unless the
-- player left that very room by hand
function Session:autoJoinTarget(slot)
    if slot == 0 and self.prefs.autoParty and self.tokRooms.party then
        return self.tokRooms.party.id
    elseif slot == 1 and self.prefs.autoGuild and self.tokRooms.guild and not self.intents[1] then
        return self.tokRooms.guild.id
    elseif slot == S.SLOT_NEAR and self.near and not self.nearHold and (self.prefs.autoNear or self.intents[slot]) then
        return S.NEAR_ROOM
    end
    return nil
end

local AUTO_SLOTS = { S.SLOT_PARTY, S.SLOT_GUILD, S.SLOT_NEAR }

function Session:autoJoin()
    for _, slot in ipairs(AUTO_SLOTS) do
        local id = self:autoJoinTarget(slot)
        -- a room already in the slot moves with the rights (the relay's moved)
        if id and not self.rooms[slot] and self.optOut[slot] ~= id and not self.joining[id] and self:sendJoin(id) then
            self.joining[id] = true
        end
    end
end

-- where the one talk key talks: the first room joined, party, guild, room
-- or event, near you; -1 in none
function Session:targetSlot()
    for slot = 0, S.LAST_SLOT do
        if self.rooms[slot] then
            return slot
        end
    end
    return -1
end

function Session:roomById(id)
    for slot = 0, S.LAST_SLOT do
        local room = self.rooms[slot]
        if room and room.id == id then
            return room
        end
    end
    return nil
end

function Session:labelOf(kind, id)
    if kind == 'guild' or kind == 'officers' then
        local r = self.tokRooms[kind]
        return r and r.id == id and r.label or nil
    end
    for _, d in ipairs(self.dir) do
        if d.id == id then
            return d.name
        end
    end
    return nil
end

-- a member arrived: apply the saved mute-for-me and volume
function Session:applyPrefs(member)
    local pref = S.userPref(self.prefs, member.guid)
    if not pref then
        return
    end
    member.mutedForMe = pref.m
    if pref.m then
        self:send({ t = 'mute', sid = member.sid, on = 1 })
    end
    if pref.v ~= 100 then
        self.io.engine('setUserVolume', member.sid, pref.v / 100)
    end
end

function Session:addMember(room, member)
    local sid = member.sid
    member.speaking = self.speaking[sid] == true
    local twin = room.members[sid]
    if twin then
        -- the same sid twice in one message: the last entry wins
        member.mutedForMe = twin.mutedForMe
        room.members[sid] = member
        return
    end
    if room.count >= S.MAX_MEMBERS then
        return
    end
    -- the relay keeps one mute per speaker for the whole session: a player
    -- met again in another room (party and guild) needs nothing sent again
    local known = sid ~= self.sid and self:memberAnywhere(sid)
    room.members[sid] = member
    room.count = room.count + 1
    if known then
        member.mutedForMe = known.mutedForMe
    elseif sid ~= self.sid then
        self:applyPrefs(member)
    end
end

function CTL.roster(self, msg)
    local kind = S.roomKind(msg.room)
    local slot = kind and S.SLOT_OF[kind]
    if not slot or type(msg.u) ~= 'table' then
        return
    end
    self.joining[msg.room] = nil
    local room = { id = msg.room, kind = kind, slot = slot, label = self:labelOf(kind, msg.room),
        members = {}, count = 0, over = 0 }
    -- joining a room leaves the other one of the same slot
    local old = self.rooms[slot]
    self.rooms[slot] = room
    for i = 1, math.min(#msg.u, S.MAX_MEMBERS) do
        local m = S.parseMember(msg.u[i])
        if m then
            self:addMember(room, m)
        end
    end
    if old then
        for sid in pairs(old.members) do
            if not self:memberAnywhere(sid) then
                self:dropSpeaker(sid)
            end
            if slot == S.SLOT_NEAR and not room.members[sid] then
                self.spatial[sid] = nil
            end
        end
    end
    if slot > 0 and kind ~= 'echo' then
        self.intents[slot] = room.id
    end
    self.io.emit('rooms')
    if slot == S.SLOT_NEAR then
        self:nearJoined()
    end
end

-- 'in' is a Lua keyword
CTL['in'] = function(self, msg)
    local room = self:roomById(msg.room)
    if not room or type(msg.u) ~= 'table' then
        return
    end
    for i = 1, math.min(#msg.u, S.MAX_MEMBERS) do
        local m = S.parseMember(msg.u[i])
        if m and not room.members[m.sid] then
            self:addMember(room, m)
            if room.members[m.sid] then
                self.io.emit('in', room, m)
                -- already talking in our party: placed at once
                if room.slot == S.SLOT_NEAR and m.speaking then
                    self:spatialSoon(m.sid)
                end
            end
        end
    end
end

-- in near this comes whenever someone walks out of sight: the member, its
-- speaking state (unless it is in another of our rooms) and its spatial
-- values are forgotten
function CTL.out(self, msg)
    local room = self:roomById(msg.room)
    local m = room and room.members[msg.sid]
    if not m then
        return
    end
    room.members[msg.sid] = nil
    room.count = room.count - 1
    if room.slot == S.SLOT_NEAR then
        self.spatial[msg.sid] = nil
    end
    self.io.emit('out', room, m)
    if not self:memberAnywhere(msg.sid) then
        self:dropSpeaker(msg.sid)
    end
end

function CTL.st(self, msg)
    local room = self:roomById(msg.room)
    local m = room and room.members[msg.sid]
    if m and isInt(msg.f, 0, 255) then
        m.flags = msg.f
        self.io.emit('member', room, m)
    end
end

function CTL.moved(self, msg)
    local room = self:roomById(msg.from)
    local kind = S.roomKind(msg.to)
    if room and kind == room.kind then
        room.id = msg.to
        self.io.emit('rooms') -- the roster of the new room follows
    end
end

function CTL.left(self, msg)
    local room = self:roomById(msg.room)
    if not room then
        return
    end
    -- kicked from near, or near switched off: not joined again by itself
    -- until the next welcome
    if room.slot == S.SLOT_NEAR then
        self.nearHold = true
    end
    self:removeRoom(room)
    self.io.emit('notice', 'left', type(msg.why) == 'string' and msg.why or '', room)
end

function Session:removeRoom(room)
    self.rooms[room.slot] = nil
    if self.intents[room.slot] == room.id then
        self.intents[room.slot] = nil
    end
    if room.slot == S.SLOT_NEAR then
        self:nearLeft()
    end
    for sid in pairs(room.members) do
        if not self:memberAnywhere(sid) then
            self:dropSpeaker(sid)
        end
    end
    self.io.emit('rooms')
end

function CTL.over(self, msg)
    local room = self:roomById(msg.room)
    if room then
        room.over = S.num(msg.n, 0, 999, 0)
        self.io.emit('over', room)
    end
end

function CTL.dir(self, msg)
    if type(msg.rooms) ~= 'table' then
        return
    end
    local list = {}
    for i = 1, math.min(#msg.rooms, S.MAX_DIR) do
        local r = msg.rooms[i]
        if type(r) == 'table' then
            local kind = S.roomKind(r[1])
            local name = label(r[2], 64)
            if (kind == 'public' or kind == 'stage') and name then
                list[#list + 1] = { id = r[1], name = name, members = S.num(r[3], 0, 99999, 0),
                    cap = S.num(r[4], 0, 99999, 0), minLevel = S.num(r[5], 0, 99999, 0),
                    stage = r[6] == 1 or r[6] == true or kind == 'stage' }
            end
        end
    end
    self.dir = list
    local room = self.rooms[2]
    if room and not room.label then
        room.label = self:labelOf(room.kind, room.id)
    end
    self.io.emit('dir')
end

function CTL.muted(self, msg)
    self.mutedUntil = S.num(msg['until'], 0, S.MAX_TS, 0)
    self.io.emit('notice', 'muted', self.mutedUntil)
end

function CTL.err(self, msg)
    local code = type(msg.code) == 'string' and msg.code or 'bad_msg'
    if msg.room and (code == 'room_denied' or code == 'room_full' or code == 'kick_block') then
        for slot = 1, S.LAST_SLOT do
            if self.intents[slot] == msg.room and not (self.rooms[slot] and self.rooms[slot].id == msg.room) then
                self.intents[slot] = nil
            end
        end
        self.joining[msg.room] = nil
        -- near refused a join (not a talk spurt under its level, which comes
        -- while we are in it): no auto-join again until the next welcome
        if msg.room == S.NEAR_ROOM and not self.rooms[S.SLOT_NEAR] then
            self.nearHold = true
        end
    end
    self.io.emit('notice', 'err', code, msg.room)
end

-- speaking edges and the local gate --------------------------------------------

function Session:memberAnywhere(sid)
    for slot = 0, S.LAST_SLOT do
        local room = self.rooms[slot]
        if room and room.members[sid] then
            return room.members[sid]
        end
    end
    return nil
end

function Session:onSpeaking(sid, on)
    on = on == true or on == 1
    if (self.speaking[sid] == true) == on then
        return
    end
    local member = self:memberAnywhere(sid)
    if on and not member then
        return -- not in any of our rooms (left a moment ago)
    end
    self.speaking[sid] = on or nil
    self.speakingCount = self.speakingCount + (on and 1 or -1)
    for slot = 0, S.LAST_SLOT do
        local room = self.rooms[slot]
        local m = room and room.members[sid]
        if m then
            m.speaking = on
        end
    end
    self.io.emit('speaking', sid, on, member)
    if self.speakingCount == (on and 1 or 0) then
        self.io.emit('speakers', self.speakingCount)
    end
    local near = self.rooms[S.SLOT_NEAR]
    if on and near and near.members[sid] then
        self:spatialSoon(sid)
    end
end

function Session:dropSpeaker(sid)
    if self.speaking[sid] then
        self:onSpeaking(sid, false)
    end
end

function Session:onTalk(slot)
    self.talkSlot = tonumber(slot) or -1
    self.io.emit('talk', self.talkSlot)
end

-- proximity: the near list and the spatial values -------------------------------
--
-- Both run only while we are in the near room (scheduleEvent through io,
-- never per frame) and stop when we leave it, on a drop and at game end
-- (dropConnection and gameEnd cancel 'near' and 'spatial'). The spatial
-- tick runs only while someone near us talks.

-- the near roster came (a join, or a join again): the relay knows nothing of
-- what we see yet, so the list goes now (500 ms after the last one at the
-- earliest), then every 500 ms when it changed
function Session:nearJoined()
    self.nearHold = false
    self.nearSig = nil
    self.io.cancel('near')
    self:nearTick()
    local room = self.rooms[S.SLOT_NEAR]
    for sid in pairs(self.speaking) do
        if room.members[sid] then
            self:spatialSoon(sid)
        end
    end
end

function Session:nearLeft()
    self.io.cancel('near')
    self.io.cancel('spatial')
    self.spatialOn = false
    self.nearSig = nil
    self.spatial = {}
end

function Session:nearTick()
    if self.state ~= ST.ONLINE or not self.rooms[S.SLOT_NEAR] then
        return
    end
    local wait = self.nearSentAt + S.NEAR_GAP_MS - self.io.now()
    -- nil: the map could not be read this time; the last list stands
    local ids = wait <= 0 and self.io.nearby()
    if ids then
        local list, sorted = {}, {}
        for i = 1, math.min(#ids, S.NEAR_MAX) do
            list[i], sorted[i] = ids[i], ids[i]
        end
        -- the set, not the order: the nearest moving changes nothing
        table.sort(sorted)
        local sig = table.concat(sorted, ',')
        if sig ~= self.nearSig then
            self.nearSig, self.nearSentAt = sig, self.io.now()
            self:send({ t = 'near', c = list })
        end
    end
    if wait <= 0 then
        wait = S.NEAR_GAP_MS
    end
    self.io.schedule('near', wait)
end

function Session:canSpatial()
    local can = self.io.canSpatial
    return can == nil or can() == true
end

-- a near member started talking (or came near while talking): placed at
-- once, then every 200 ms with the others while anyone near us talks
function Session:spatialSoon(sid)
    local room = self.rooms[S.SLOT_NEAR]
    local m = room and room.members[sid]
    if self.state ~= ST.ONLINE or not m or sid == self.sid or not self:canSpatial() then
        return
    end
    self:spatialUpdate(sid, m)
    if not self.spatialOn then
        self.spatialOn = true
        self.io.schedule('spatial', S.SPATIAL_GAP_MS)
    end
end

function Session:spatialTick()
    self.spatialOn = false
    local room = self.rooms[S.SLOT_NEAR]
    if self.state ~= ST.ONLINE or not room or not self:canSpatial() then
        return
    end
    local any = false
    for sid in pairs(self.speaking) do
        local m = room.members[sid]
        if m and sid ~= self.sid then
            any = true
            self:spatialUpdate(sid, m)
        end
    end
    -- nobody near us talks any more: nothing runs until someone does
    if any then
        self.spatialOn = true
        self.io.schedule('spatial', S.SPATIAL_GAP_MS)
    end
end

-- the creature not on our floor (gone, dead, another floor): gain 0, the pan
-- kept; the engine is told only of a change over SPATIAL_STEP
function Session:spatialUpdate(sid, m)
    local last = self.spatial[sid]
    local gain, pan = 0, last and last.pan or 0
    local dx, dy = self.io.offset(m.cid)
    if dx and dy then
        gain, pan = S.spatial(dx, dy)
    end
    if last and math.abs(gain - last.gain) <= S.SPATIAL_STEP and math.abs(pan - last.pan) <= S.SPATIAL_STEP then
        return
    end
    self.spatial[sid] = { gain = gain, pan = pan }
    self.io.engine('setUserSpatial', sid, gain, pan)
end

-- player actions --------------------------------------------------------------

function Session:join(id)
    local kind = S.roomKind(id)
    local slot = kind and S.SLOT_OF[kind]
    if self.state ~= ST.ONLINE or not slot then
        return false
    end
    if self.rooms[slot] and self.rooms[slot].id == id then
        return false
    end
    if not self:sendJoin(id) then
        self.io.emit('notice', 'err', 'rate') -- "too fast; wait a moment"
        return false
    end
    if self.optOut[slot] == id then
        self.optOut[slot] = nil
    end
    return true
end

function Session:leave(id)
    local room = self:roomById(id)
    if not room then
        return false
    end
    self:send({ t = 'leave', room = id })
    if room.slot <= 1 or room.slot == S.SLOT_NEAR then
        self.optOut[room.slot] = id
    end
    self:removeRoom(room)
    return true
end

function Session:setSelfMuted(on)
    self.prefs.selfMuted = on
    self.io.savePrefs(self.prefs)
    self.io.engine('setSelfMuted', on)
    if on then
        self.io.engine('setTransmit', -1)
    end
    self:send({ t = 'self', m = on and 1 or 0 })
    self.io.emit('self')
end

-- deafened hears nothing and does not talk either (as on Discord)
function Session:setDeafened(on)
    self.prefs.deafened = on
    self.io.savePrefs(self.prefs)
    self.io.engine('setDeafened', on)
    if on then
        self.io.engine('setTransmit', -1)
    end
    self:send({ t = 'deaf', on = on and 1 or 0 })
    self.io.emit('self')
end

function Session:setUserMuted(member, on)
    S.setUserPref(self.prefs, member.guid, 'm', on, self.io.time())
    self.io.savePrefs(self.prefs)
    for slot = 0, S.LAST_SLOT do
        local room = self.rooms[slot]
        local m = room and room.members[member.sid]
        if m then
            m.mutedForMe = on
            self.io.emit('member', room, m)
        end
    end
    self:send({ t = 'mute', sid = member.sid, on = on and 1 or 0 })
end

function Session:setUserVolume(member, percent)
    percent = math.max(0, math.min(200, math.floor(percent + 0.5)))
    S.setUserPref(self.prefs, member.guid, 'v', percent, self.io.time())
    self.io.savePrefs(self.prefs)
    self.io.engine('setUserVolume', member.sid, percent / 100)
end

function Session:requestDir()
    if self.state ~= ST.ONLINE or self.io.now() - self.lastDir < S.DIR_GAP_MS then
        return false
    end
    self.lastDir = self.io.now()
    self:send({ t = 'dir' })
    return true
end

function Session:moderate(op, roomId, sid, secs)
    if not S.MOD_OPS[op] or not self:roomById(roomId) or not isInt(sid, 1, 65535) then
        return false
    end
    local msg = { t = 'mod', op = op, room = roomId, sid = sid }
    if secs then
        msg.s = math.max(60, math.min(math.floor(secs), 86400))
    end
    self:send(msg)
    return true
end

function Session:report(roomId, sid, why, text)
    local now = self.io.now()
    if self.reportAt and now - self.reportAt < S.REPORT_WAIT_MS then
        return nil, 'pending'
    end
    local room = self:roomById(roomId)
    local msg, err = S.buildReport(room, room and room.members[sid], why, text)
    if not msg then
        return nil, err
    end
    self.reportAt = now
    self.io.send142(msg)
    return msg
end

-- control messages to the relay, at most CTL_RATE a second ----------------------

-- pending messages that a newer one replaces: one mute per player, one of each
-- switch, one directory request, one near list
local function queueKey(msg)
    if msg.t == 'mute' then
        return 'mute' .. msg.sid
    elseif msg.t == 'self' or msg.t == 'deaf' or msg.t == 'dir' or msg.t == 'auth' or msg.t == 'near' then
        return msg.t
    end
    return nil
end

function Session:refill()
    local now = self.io.now()
    if self.bucketAt then
        self.bucket = math.min(S.CTL_BURST, self.bucket + (now - self.bucketAt) * S.CTL_RATE / 1000)
    end
    self.bucketAt = now
end

function Session:send(msg)
    if self.state ~= ST.ONLINE then
        return
    end
    self:refill()
    if #self.queue == 0 and self.bucket >= 1 then
        self.bucket = self.bucket - 1
        self.io.sendCtl(msg)
        return
    end
    local key = queueKey(msg)
    if key then
        for i, pending in ipairs(self.queue) do
            if queueKey(pending) == key then
                self.queue[i] = msg
                return
            end
        end
    end
    if #self.queue >= S.CTL_QUEUE then
        table.remove(self.queue, 1)
    end
    self.queue[#self.queue + 1] = msg
    if #self.queue == 1 then
        self.io.schedule('ctl', math.ceil((1 - self.bucket) * 1000 / S.CTL_RATE))
    end
end

function Session:drainQueue()
    if self.state ~= ST.ONLINE then
        self.queue = {}
        return
    end
    self:refill()
    while #self.queue > 0 and self.bucket >= 1 do
        self.bucket = self.bucket - 1
        self.io.sendCtl(table.remove(self.queue, 1))
    end
    if #self.queue > 0 then
        self.io.schedule('ctl', math.ceil((1 - self.bucket) * 1000 / S.CTL_RATE))
    end
end
