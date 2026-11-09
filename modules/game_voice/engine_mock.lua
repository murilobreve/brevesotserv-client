-- Mock engine: a relay that lives inside the client, for UI work and the
-- tests. It answers the hello with a welcome, a join with a roster of four
-- made-up players, and makes them talk (and now and then come and go) every
-- 1-3 s. EngineMock.reply stands in for canary's opcode 142 answers, so the
-- whole panel can be clicked through on a server without voice. Picked only
-- when the g_settings node 'voice' has mock = true (developers).

EngineMock = {}
EngineMock.__index = EngineMock

local PLAYERS = {
    { sid = 2, guid = 9001, name = 'Aria Lumen', flags = 0 },
    { sid = 3, guid = 9002, name = 'Bran Tor', flags = 1 },  -- self-muted
    { sid = 4, guid = 9003, name = 'Cael', flags = 16 },     -- staff
    { sid = 5, guid = 9004, name = 'Dara Voss', flags = 64 }, -- lite
}
local VISITOR = { sid = 6, guid = 9005, name = 'Visitante', flags = 0 }
local SELF_SID = 1
local MOCK_TOKEN = 'bW9jay12b2ljZQ.bW9jay1zaWduYXR1cmU'

local DIR = {
    { 'pub:geral', 'Geral', 12, 100, 50, 0 },
    { 'pub:hunts', 'Hunts', 4, 100, 50, 0 },
    { 'pub:novatos', 'Novatos', 7, 100, 8, 0 },
    { 'ev:eventos', 'Eventos', 45, 300, 0, 1 },
}

-- canary's answer to an opcode 142 message, or nil
function EngineMock.reply(msg)
    if msg.a == 'hi' then
        return { a = 'cfg', on = true, url = 'ws://127.0.0.1:7191/voz', psl = 50 }
    elseif (msg.a == 'want' and msg.on) or msg.a == 'tok' then
        return { a = 'tok', tok = MOCK_TOKEN, exp = os.time() + 120, rooms = {
            { id = 'p:1:1', k = 'party', l = 'Party' },
            { id = 'g:7', k = 'guild', l = 'Mythos Guild' },
            { id = 'g:7:o', k = 'officers', l = 'Oficiais' },
        } }
    elseif msg.a == 'report' then
        return { a = 'rep', ok = true, code = 'sent', s = 0 }
    end
    return nil
end

-- info: { self = { cid, name } } (the local player, if there is one)
function EngineMock.create(sink, info)
    local players = {} -- a copy: moderation changes the flags
    for i, p in ipairs(PLAYERS) do
        players[i] = { sid = p.sid, guid = p.guid, name = p.name, flags = p.flags }
    end
    return setmetatable({ name = 'mock', audio = true, sink = sink, info = info or {}, events = {},
        rooms = {}, talking = {}, visitorIn = false, players = players }, EngineMock)
end

-- a one-shot event that disconnect() cancels
function EngineMock:later(ms, fn)
    local event
    event = scheduleEvent(function()
        self.events[event] = nil
        fn()
    end, ms)
    self.events[event] = true
end

function EngineMock:cancelAll()
    for event in pairs(self.events) do
        removeEvent(event)
    end
    self.events = {}
end

function EngineMock:ctl(msg)
    self.sink('ctl', json.encode(msg))
end

function EngineMock:connect(url, tok)
    self:disconnect()
    self.connected = true
    self.sink('state', 'connecting')
    self:later(150, function()
        self.sink('state', 'open')
        self:later(100, function()
            local now = os.time()
            self:ctl({ t = 'welcome', sid = SELF_SID, now = now, exp = now + 300,
                lim = { pl = 240, fps = 30, bps = 6000, lastN = 4 } })
        end)
    end)
end

function EngineMock:disconnect()
    self:cancelAll()
    -- the talk timer went with the events: the next connect arms a new one
    self.connected, self.talkArmed = false, false
    self.rooms, self.talking, self.visitorIn = {}, {}, false
end

-- the relay closing on us, for trying the reconnect screens
function EngineMock:drop(code)
    if self.connected then
        self:disconnect()
        self.sink('state', 'closed', code)
    end
end

local function row(p)
    return { p.sid, 0, p.guid, p.name, p.flags }
end

function EngineMock:roster(id)
    local me = self.info.self or {}
    local u = { { SELF_SID, me.cid or 0, me.guid or 1, me.name or 'Voce', 32 } }
    for _, p in ipairs(self.players) do
        u[#u + 1] = row(p)
    end
    self.rooms[id] = true
    self:ctl({ t = 'roster', room = id, slot = 0, u = u })
    self:scheduleTalk()
end

function EngineMock:anyRoom()
    return next(self.rooms)
end

-- one random edge every 1-3 s while a room is joined: someone starts or stops
-- talking, or the visitor comes in or goes out
function EngineMock:scheduleTalk()
    if self.talkArmed then
        return
    end
    self.talkArmed = true
    self:later(1000 + math.random(0, 2000), function()
        self.talkArmed = false
        local room = self:anyRoom()
        if not self.connected or not room then
            return
        end
        if math.random() < 0.1 then
            self.visitorIn = not self.visitorIn
            if self.visitorIn then
                self:ctl({ t = 'in', room = room, u = { row(VISITOR) } })
            else
                self:ctl({ t = 'out', room = room, sid = VISITOR.sid })
            end
        else
            local p = self.players[math.random(1, #self.players)]
            local on = not self.talking[p.sid]
            self.talking[p.sid] = on or nil
            self.sink('spk', nil, p.sid, on and 1 or 0)
        end
        self:scheduleTalk()
    end)
end

function EngineMock:send(msg)
    if not self.connected then
        return
    end
    local t = msg.t
    if t == 'join' then
        self:later(80, function()
            self:roster(msg.room)
        end)
    elseif t == 'leave' then
        self.rooms[msg.room] = nil
    elseif t == 'dir' then
        self:later(80, function()
            self:ctl({ t = 'dir', rooms = DIR })
        end)
    elseif t == 'auth' then
        self:later(50, function()
            self:ctl({ t = 'ok', exp = os.time() + 300 })
        end)
    elseif t == 'self' or t == 'deaf' then
        self[t] = (msg.m or msg.on) == 1
        local flags = 32 + (self.self and 1 or 0) + (self.deaf and 2 or 0)
        for room in pairs(self.rooms) do
            self:ctl({ t = 'st', room = room, sid = SELF_SID, f = flags })
        end
    elseif t == 'mod' then
        self:later(80, function()
            self:moderate(msg)
        end)
    end
end

-- kick takes the player out; mute, unmute, speak and nospeak change a flag
local MOD_FLAG = { mute = { 4, true }, unmute = { 4, false }, speak = { 8, true }, nospeak = { 8, false } }

function EngineMock:moderate(msg)
    if msg.op == 'kick' then
        self:ctl({ t = 'out', room = msg.room, sid = msg.sid })
        return
    end
    for _, p in ipairs(self.players) do
        local change = MOD_FLAG[msg.op]
        if p.sid == msg.sid and change then
            local bit, on = change[1], change[2]
            local has = math.floor(p.flags / bit) % 2 == 1
            if has ~= on then
                p.flags = p.flags + (on and bit or -bit)
            end
            self:ctl({ t = 'st', room = msg.room, sid = p.sid, f = p.flags })
        end
    end
end

-- the local gate follows the push-to-talk key
function EngineMock:setTransmit(slot)
    self.sink('talk', nil, slot)
end

function EngineMock:terminate()
    self:disconnect()
end
