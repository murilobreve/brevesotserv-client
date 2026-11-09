-- Tests for modules/game_voice without the client: the state machine and
-- every close code, the backoff bounds, the token rules, auto-join and moves,
-- the roster model and the 40-row cap, mute persistence by guid, the report
-- limits, opcode/control parsing with malformed JSON, the control rate limit,
-- and the lite and mock engines over stubs.
--
--   luajit tools/voz-luatest/game_voice_test.lua      (from the client repo)

local ROOT = (arg and arg[0] or ''):match('^(.*)/tools/voz%-luatest/') or '.'
local MODULE = ROOT .. '/modules/game_voice/'

dofile(ROOT .. '/modules/corelib/json.lua')
dofile(MODULE .. 'voice_state.lua')
local S = VoiceState
local ST = S.ST

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print('FAIL ' .. name .. ': ' .. tostring(err))
    end
end

local function eq(a, b, what)
    if a ~= b then
        error(string.format('%s: expected %s, got %s', what or 'value', tostring(b), tostring(a)), 2)
    end
end

-- a fake io: a clock we move by hand, named timers, and logs of what went out
local function newWorld(prefs)
    local w = { t = 0, timers = {}, sent142 = {}, ctl = {}, connects = {}, disconnects = 0, emits = {},
        engineCalls = {}, saves = 0, rand = 0.5 }
    local io = {
        now = function() return w.t end,
        time = function() return 1700000000 + math.floor(w.t / 1000) end,
        random = function() return w.rand end,
        send142 = function(t) w.sent142[#w.sent142 + 1] = t end,
        connect = function(url, tok) w.connects[#w.connects + 1] = { url = url, tok = tok } end,
        disconnect = function() w.disconnects = w.disconnects + 1 end,
        sendCtl = function(t) w.ctl[#w.ctl + 1] = t end,
        schedule = function(name, ms) w.timers[name] = w.t + ms end,
        cancel = function(name) w.timers[name] = nil end,
        savePrefs = function() w.saves = w.saves + 1 end,
        emit = function(what, a, b, c) w.emits[#w.emits + 1] = { what, a, b, c } end,
        engine = function(method, a, b) w.engineCalls[#w.engineCalls + 1] = { method, a, b } end,
    }
    w.s = S.new(io, prefs)
    -- moves the clock, firing due timers in order
    function w.advance(ms)
        local target = w.t + ms
        while true do
            local name, due
            for n, d in pairs(w.timers) do
                if d <= target and (not due or d < due) then
                    name, due = n, d
                end
            end
            if not name then
                break
            end
            w.t = math.max(w.t, due)
            w.timers[name] = nil
            w.s:onTimer(name)
        end
        w.t = target
    end
    function w.last142() return w.sent142[#w.sent142] end
    function w.lastCtl() return w.ctl[#w.ctl] end
    function w.ctlOf(t)
        local out = {}
        for _, m in ipairs(w.ctl) do
            if m.t == t then
                out[#out + 1] = m
            end
        end
        return out
    end
    function w.relay(msg) w.s:onControl(json.encode(msg)) end
    return w
end

local TOK = 'eyJ2IjoxLCJhIjoxfQ.c2lnbmF0dXJlLXNpZ25hdHVyZQ'
local function tokMsg(rooms)
    return { a = 'tok', tok = TOK, exp = 1700000120, rooms = rooms or { { id = 'p:10:5', k = 'party', l = 'Party' } } }
end
local CFG = { a = 'cfg', on = true, url = 'wss://mythosot.com.br:7190/voz', psl = 50 }

-- a session that reached ONLINE through the whole handshake
local ME = 'Eu Mesmo' -- the local character
local OPTED_IN = { chars = { [ME] = { t = 1 } } }

local function online(prefs, rooms)
    local w = newWorld(prefs)
    w.s:gameStart('win', 'lite', ME)
    w.s:onOpcode(CFG)
    if w.s.state == ST.READY then
        w.s:setWant(true)
    end
    w.s:onOpcode(tokMsg(rooms))
    w.relay({ t = 'welcome', sid = 7, now = 1700000000, exp = 1700000300 })
    assert(w.s.state == ST.ONLINE, 'online: ' .. tostring(w.s.state))
    return w
end

local function roster(w, id, members)
    local u = {}
    for _, m in ipairs(members) do
        u[#u + 1] = { m[1], m[2] or 0, m[3] or m[1] + 1000, m[4] or ('P' .. m[1]), m[5] or 0 }
    end
    w.relay({ t = 'roster', room = id, slot = 0, u = u })
end

-- helpers ---------------------------------------------------------------------

test('decode never raises on malformed input', function()
    for _, bad in ipairs({ nil, 42, '', '{', '{bad', 'null', '[]', '[1,2]', '"x"', '{"a":}', '{"a":1}garbage',
        string.rep(' ', 10) .. '{', '{"a":"' .. string.rep('x', 3000) .. '"}' }) do
        local ok, res = pcall(S.decode, bad, S.MAX_OPCODE_BYTES)
        assert(ok, 'raised on ' .. tostring(bad))
        eq(res, nil, 'decode(' .. tostring(bad):sub(1, 20) .. ')')
    end
    local t = S.decode('  {"a":"cfg","on":true}', 2048)
    eq(t.a, 'cfg')
end)

test('room ids follow the grammar', function()
    eq(S.roomKind('p:123:1700000000'), 'party')
    eq(S.roomKind('g:45'), 'guild')
    eq(S.roomKind('g:45:o'), 'officers')
    eq(S.roomKind('pub:geral'), 'public')
    eq(S.roomKind('ev:eventos'), 'stage')
    eq(S.roomKind('echo'), 'echo')
    eq(S.roomKind('prox'), nil)
    eq(S.roomKind('P:1:2'), nil)
    eq(S.roomKind('pub:' .. string.rep('a', 40)), nil)
    eq(S.roomKind('pub:a b'), nil)
    eq(S.roomKind(12), nil)
    eq(S.SLOT_OF.officers, 1)
    eq(S.SLOT_OF.stage, 2)
end)

test('urls from cfg are checked', function()
    eq(S.checkUrl('wss://mythosot.com.br:7190/voz'), 'wss://mythosot.com.br:7190/voz')
    eq(S.checkUrl('ws://127.0.0.1:7191/voz'), 'ws://127.0.0.1:7191/voz')
    eq(S.checkUrl('http://x/voz'), nil)
    eq(S.checkUrl('wss://x/voz?a=1'), nil)
    eq(S.checkUrl('wss://x y/voz'), nil)
end)

test('latin1 keeps Portuguese and replaces the rest', function()
    eq(S.latin1('Com\195\169rcio'), 'Com\233rcio')
    eq(S.latin1('\195\163o'), '\227o')
    eq(S.latin1('a\226\152\133b'), 'a?b') -- a 3-byte character
    eq(S.latin1('plain'), 'plain')
end)

test('flags', function()
    assert(S.hasFlag(1 + 4 + 32, S.F_SELF_MUTED))
    assert(not S.hasFlag(1 + 4 + 32, S.F_DEAF))
    assert(S.hasFlag(1 + 4 + 32, S.F_SERVER_MUTED))
    assert(S.hasFlag(64, S.F_LITE))
    assert(not S.hasFlag(nil, S.F_LITE))
end)

-- backoff ---------------------------------------------------------------------

test('backoff steps stay within +-30%', function()
    local steps = { 1, 2, 4, 8, 16, 30, 60, 60, 60, 60, 60 }
    for n, step in ipairs(steps) do
        for _, r in ipairs({ 0, 0.25, 0.5, 0.75, 0.999999 }) do
            local d = S.backoffDelay(n, r)
            assert(d >= step * 700 and d <= step * 1300, string.format('n=%d r=%s d=%d', n, r, d))
        end
        eq(S.backoffDelay(n, 0.5), step * 1000, 'no jitter at r=0.5')
    end
    eq(S.backoffDelay(0, 0.5), 1000, 'n=0 counts as the first step')
end)

-- the state machine -----------------------------------------------------------

test('hi at game start, at most one per 10 s', function()
    local w = newWorld()
    w.s:gameStart('web', 'lite')
    eq(w.s.state, ST.WAIT_CFG)
    eq(w.last142().a, 'hi')
    eq(w.last142().cl, 'web')
    eq(w.last142().eng, 'lite')
    w.advance(2000)
    w.s:gameEnd()
    eq(w.s.state, ST.OFF)
    w.s:gameStart('web', 'lite')
    eq(#w.sent142, 1, 'second hi waits')
    w.advance(7999)
    eq(#w.sent142, 1)
    w.advance(1)
    eq(#w.sent142, 2, 'hi after 10 s')
end)

test('no cfg: nothing visible, nothing more sent', function()
    local w = newWorld()
    w.s:gameStart('win', 'lite')
    w.advance(600000)
    eq(#w.sent142, 1)
    eq(w.s:isVisible(), false)
    eq(next(w.timers), nil, 'no timer left running')
end)

test('cfg on, opt in, token, welcome, party auto-join', function()
    local w = newWorld()
    w.s:gameStart('win', 'lite', ME)
    w.s:onOpcode(CFG)
    eq(w.s.state, ST.READY)
    assert(w.s:isVisible())
    w.s:setWant(true)
    eq(w.last142().a, 'want')
    eq(w.last142().on, true)
    assert(w.s:optedIn(), 'the opt-in is kept for this character')
    eq(w.s.state, ST.WAIT_TOKEN)
    w.s:onOpcode(tokMsg())
    eq(w.s.state, ST.CONNECTING)
    eq(#w.connects, 1)
    eq(w.connects[1].url, CFG.url)
    eq(w.connects[1].tok, TOK)
    w.relay({ t = 'welcome', sid = 7, now = 1700000000 })
    eq(w.s.state, ST.ONLINE)
    local joins = w.ctlOf('join')
    eq(#joins, 1)
    eq(joins[1].room, 'p:10:5')
end)

test('remembered opt-in sends want by itself, for that character only', function()
    local prefs = S.normalizePrefs(OPTED_IN)
    local w = newWorld(prefs)
    w.s:gameStart('win', 'lite', ME)
    w.s:onOpcode(CFG)
    eq(w.last142().a, 'want')
    eq(w.s.state, ST.WAIT_TOKEN)
    -- another character on the same computer: offered, not turned on
    local other = newWorld(prefs)
    other.s:gameStart('win', 'lite', 'Outro Jogador')
    other.s:onOpcode(CFG)
    eq(other.s.state, ST.READY)
    eq(other.last142().a, 'hi', 'no want sent')
end)

test('cfg off: disabled and invisible; banned: blocked and visible', function()
    local w = newWorld()
    w.s:gameStart('win', 'lite')
    w.s:onOpcode({ a = 'cfg', on = false, why = 'beta' })
    eq(w.s.state, ST.DISABLED)
    eq(w.s.why, 'beta')
    eq(w.s:isVisible(), false)
    eq(w.s:setWant(true), false)
    w.s:onOpcode({ a = 'cfg', on = false, why = 'banned', ['until'] = 1700086400 })
    eq(w.s.state, ST.BLOCKED)
    eq(w.s.why, 'banned')
    eq(w.s.untilTs, 1700086400)
    assert(w.s:isVisible())
end)

test('a bad url in cfg disables voice', function()
    local w = newWorld()
    w.s:gameStart('win', 'lite')
    w.s:onOpcode({ a = 'cfg', on = true, url = 'javascript:alert(1)' })
    eq(w.s.state, ST.DISABLED)
    eq(w.s.why, 'url')
end)

test('kill switch while online: blocked off, then on again', function()
    local w = online(S.normalizePrefs(OPTED_IN))
    w.s:onOpcode({ a = 'cfg', on = false, why = 'off' })
    eq(w.s.state, ST.BLOCKED)
    eq(w.s.why, 'off')
    eq(w.disconnects, 1)
    w.advance(5000)
    w.s:onOpcode(CFG)
    eq(w.s.state, ST.WAIT_TOKEN, 'want again')
end)

test('close 4401: a new token once, at once; again: backoff', function()
    local w = online()
    w.advance(5000)
    local before = #w.sent142
    w.s:onEngineState('closed', 4401)
    eq(w.s.state, ST.WAIT_TOKEN)
    eq(#w.sent142, before + 1)
    eq(w.last142().a, 'tok')
    w.s:onOpcode(tokMsg())
    eq(w.s.state, ST.CONNECTING)
    eq(#w.connects, 2)
    w.s:onEngineState('closed', 4401)
    eq(w.s.state, ST.BACKOFF, 'second 4401 backs off')
    eq(w.s.failures, 1)
end)

test('close 4403, 4409, 4503: blocked, no retry timer', function()
    for code, why in pairs({ [4403] = 'banned', [4409] = 'replaced', [4503] = 'off' }) do
        local w = online()
        w.s:onEngineState('closed', code)
        eq(w.s.state, ST.BLOCKED, tostring(code))
        eq(w.s.why, why, tostring(code))
        eq(w.timers.retry, nil, tostring(code) .. ' retry')
        w.advance(600000)
        eq(#w.connects, 1, tostring(code) .. ' never reconnects by itself')
    end
end)

test('replaced: the player may reconnect by hand', function()
    local w = online()
    w.s:onEngineState('closed', 4409)
    assert(w.s:retryNow())
    eq(w.s.state, ST.WAIT_TOKEN, 'the token was used: asks a new one')
end)

test('close 4429, 4408, network: backoff with jitter bounds', function()
    for _, code in ipairs({ 4429, 4408, 1000, false }) do
        local w = online()
        w.rand = 0
        w.s:onEngineState(code and 'closed' or 'error', code or nil)
        eq(w.s.state, ST.BACKOFF, tostring(code))
        eq(w.s.failures, 1)
        eq(w.timers.retry, w.t + 700, tostring(code) .. ' first wait 1 s -30%')
    end
end)

test('close 1012: retry in 1-5 s, not counted as a failure', function()
    for _, r in ipairs({ 0, 0.5, 0.9999 }) do
        local w = online()
        w.rand = r
        w.s:onEngineState('closed', 1012)
        eq(w.s.state, ST.BACKOFF)
        eq(w.s.failures, 0)
        local d = w.timers.retry - w.t
        assert(d >= 1000 and d <= 5000, 'restart delay ' .. d)
    end
end)

test('the retry reuses a fresh unused token, else asks', function()
    local w = online()
    w.s:onEngineState('closed', 4429)
    -- a pushed token arrives during the backoff: kept unused
    w.s:onOpcode(tokMsg())
    local asked = #w.sent142
    w.advance(1000)
    eq(w.s.state, ST.CONNECTING, 'connected with the kept token')
    eq(#w.sent142, asked, 'no token request')
    w.s:onEngineState('closed', 4429)
    w.advance(3000)
    eq(w.s.state, ST.WAIT_TOKEN, 'the token is used: asks again')
    eq(w.last142().a, 'tok')
end)

test('a stale token is not reused', function()
    local w = online()
    w.s:onEngineState('closed', 4429)
    w.s:onOpcode(tokMsg())
    -- the retry comes only after the kept token aged
    w.timers.retry = nil
    w.advance(S.TOKEN_FRESH_MS + 1)
    w.s:onTimer('retry')
    eq(w.s.state, ST.WAIT_TOKEN)
    eq(w.last142().a, 'tok')
    eq(#w.connects, 1)
end)

test('token requests: 3 s apart and 30 per 10 minutes', function()
    local w = online()
    local times = {}
    -- every token request answered by a close: the worst case
    for i = 1, 40 do
        w.s.state = ST.BACKOFF
        w.s.tok = nil
        w.s:connectNow()
        local last = w.last142()
        if last.a == 'tok' and w.timers.tokwait == w.t + S.TOKEN_WAIT_MS then
            times[#times + 1] = w.t
        end
        w.timers.tokwait = nil
        w.advance(1000)
        while w.timers.tokreq do
            w.advance(w.timers.tokreq - w.t)
            if w.last142().a == 'tok' and w.timers.tokwait then
                times[#times + 1] = w.t
                w.timers.tokwait = nil
            end
        end
    end
    for i = 2, #times do
        assert(times[i] - times[i - 1] >= S.TOKEN_GAP_MS, 'gap at ' .. i)
    end
    for i = S.TOKEN_BUDGET + 1, #times do
        assert(times[i] - times[i - S.TOKEN_BUDGET] >= S.TOKEN_WINDOW_MS, 'budget at ' .. i)
    end
end)

test('ten failures in a row: failed, manual retry only', function()
    local w = online()
    for i = 1, S.MAX_FAILURES do
        w.s:onEngineState('error', nil)
        if i < S.MAX_FAILURES then
            eq(w.s.state, ST.BACKOFF, 'failure ' .. i)
            w.s:onOpcode(tokMsg())
            w.advance(w.timers.retry - w.t)
            eq(w.s.state, ST.CONNECTING, 'retry ' .. i)
        end
    end
    eq(w.s.state, ST.FAILED)
    eq(w.timers.retry, nil)
    w.advance(3600000)
    eq(w.s.state, ST.FAILED, 'stays failed')
    w.s:onOpcode(tokMsg())
    assert(w.s:retryNow())
    eq(w.s.state, ST.CONNECTING)
end)

test('the failure count resets after 30 s online', function()
    local w = online()
    w.s:onEngineState('error', nil)
    w.s:onEngineState('error', nil) -- ignored: in backoff
    eq(w.s.failures, 1)
    w.s:onOpcode(tokMsg())
    w.advance(w.timers.retry - w.t)
    w.relay({ t = 'welcome', sid = 8 })
    w.advance(S.STABLE_MS)
    w.s:onEngineState('error', nil)
    eq(w.s.failures, 1, 'counted again from zero')
end)

test('no welcome in 15 s: closed and counted', function()
    local w = newWorld()
    w.s:gameStart('win', 'lite')
    w.s:onOpcode(CFG)
    w.s:setWant(true)
    w.s:onOpcode(tokMsg())
    w.advance(S.CONNECT_WAIT_MS)
    eq(w.s.state, ST.BACKOFF)
    eq(w.disconnects, 1)
end)

test('no token in 10 s: counted, then asked again', function()
    local w = newWorld()
    w.s:gameStart('win', 'lite')
    w.s:onOpcode(CFG)
    w.s:setWant(true)
    w.advance(S.TOKEN_WAIT_MS)
    eq(w.s.state, ST.BACKOFF)
    w.advance(w.timers.retry - w.t)
    eq(w.s.state, ST.WAIT_TOKEN)
    eq(w.last142().a, 'tok')
end)

test('server err rate delays the token request', function()
    local w = online()
    w.s:onEngineState('closed', 4401)
    w.s:onOpcode({ a = 'err', code = 'rate', s = 7 })
    eq(w.timers.tokreq, w.t + 7000)
    w.s:onOpcode({ a = 'err', code = 'banned', s = 86400 })
    eq(w.s.state, ST.BLOCKED)
    eq(w.s.untilTs, w.s.io.time() + 86400)
end)

test('want off: back to ready, socket closed, nothing pending', function()
    local w = online()
    w.advance(4000)
    w.s:setWant(false)
    eq(w.s.state, ST.READY)
    eq(w.last142().on, false)
    eq(w.disconnects, 1)
    eq(w.timers.retry, nil)
    eq(w.s:optedIn(), false)
end)

test('game end: off, closed, timers gone', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8 } })
    w.s:onSpeaking(8, true)
    w.s:gameEnd()
    eq(w.s.state, ST.OFF)
    eq(w.disconnects, 1)
    eq(next(w.timers), nil)
    eq(next(w.s.rooms), nil)
    eq(w.s.speakingCount, 0)
end)

test('a stale close after we gave up is ignored', function()
    local w = online()
    w.s:setWant(false)
    w.s:onEngineState('closed', 4403)
    eq(w.s.state, ST.READY)
end)

-- tokens while connected ------------------------------------------------------

test('a token while online becomes an auth', function()
    local w = online()
    w.s:onOpcode(tokMsg())
    local auth = w.ctlOf('auth')
    eq(#auth, 1)
    eq(auth[1].tok, TOK)
    eq(w.s.tok.used, true)
end)

test('a token while connecting is used after welcome', function()
    local w = newWorld()
    w.s:gameStart('win', 'lite')
    w.s:onOpcode(CFG)
    w.s:setWant(true)
    w.s:onOpcode(tokMsg())
    w.s:onOpcode(tokMsg())
    eq(#w.ctl, 0)
    w.relay({ t = 'welcome', sid = 7 })
    eq(#w.ctlOf('auth'), 1)
end)

test('malformed tokens are ignored', function()
    local w = newWorld()
    w.s:gameStart('win', 'lite')
    w.s:onOpcode(CFG)
    w.s:setWant(true)
    for _, bad in ipairs({ 'short', 'no-dot-' .. string.rep('a', 20), 'a.b c' .. string.rep('d', 20), 12 }) do
        w.s:onOpcode({ a = 'tok', tok = bad })
        eq(w.s.state, ST.WAIT_TOKEN)
    end
end)

-- auto-join and moves ---------------------------------------------------------

test('a party appears while online: joined', function()
    local w = online(nil, {})
    eq(#w.ctlOf('join'), 0)
    w.s:onOpcode(tokMsg({ { id = 'p:3:9', k = 'party', l = 'Party' } }))
    local joins = w.ctlOf('join')
    eq(#joins, 1)
    eq(joins[1].room, 'p:3:9')
    w.s:onOpcode(tokMsg({ { id = 'p:3:9', k = 'party', l = 'Party' } }))
    eq(#w.ctlOf('join'), 1, 'not twice before the roster')
end)

test('a party room left by hand is not joined again', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8 } })
    w.s:leave('p:10:5')
    eq(w.lastCtl().t, 'leave')
    eq(w.s.rooms[0], nil)
    w.s:onOpcode(tokMsg())
    eq(#w.ctlOf('join'), 1, 'same room: stays out')
    w.s:onOpcode(tokMsg({ { id = 'p:10:6', k = 'party', l = 'Party' } }))
    eq(#w.ctlOf('join'), 2, 'a new party key: joined')
end)

test('auto-join off for the party, on for the guild', function()
    local prefs = S.normalizePrefs({ autoParty = false, autoGuild = true })
    local w = online(prefs, { { id = 'p:10:5', k = 'party' }, { id = 'g:45', k = 'guild', l = 'Os Bravos' },
        { id = 'g:45:o', k = 'officers', l = 'Oficiais' } })
    local joins = w.ctlOf('join')
    eq(#joins, 1)
    eq(joins[1].room, 'g:45')
end)

test('moved keeps the slot and takes the new roster; left removes', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8 }, { 9 } })
    w.relay({ t = 'moved', from = 'p:10:5', to = 'p:10:6', slot = 0 })
    eq(w.s.rooms[0].id, 'p:10:6')
    roster(w, 'p:10:6', { { 7 }, { 8 } })
    eq(w.s.rooms[0].count, 2)
    w.relay({ t = 'moved', from = 'p:10:6', to = 'g:1', slot = 0 })
    eq(w.s.rooms[0].id, 'p:10:6', 'a move across kinds is refused')
    w.relay({ t = 'left', room = 'p:10:6', why = 'party' })
    eq(w.s.rooms[0], nil)
    local notice = w.emits[#w.emits]
    eq(notice[1], 'notice')
    eq(notice[2], 'left')
    eq(notice[3], 'party')
end)

test('reconnect joins the room of before again', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 } })
    assert(w.s:join('pub:geral'))
    roster(w, 'pub:geral', { { 7 }, { 20 } })
    w.s:onEngineState('closed', 1012)
    w.s:onOpcode(tokMsg())
    w.advance(w.timers.retry - w.t)
    local n = #w.ctl
    w.relay({ t = 'welcome', sid = 9 })
    local rejoined = {}
    for i = n + 1, #w.ctl do
        if w.ctl[i].t == 'join' then
            rejoined[w.ctl[i].room] = true
        end
    end
    assert(rejoined['p:10:5'], 'party')
    assert(rejoined['pub:geral'], 'public room')
end)

test('a denied room is not joined again after a reconnect', function()
    local w = online()
    w.s:join('ev:eventos')
    w.relay({ t = 'err', code = 'room_denied', room = 'ev:eventos' })
    w.s:join('pub:geral')
    roster(w, 'pub:geral', { { 7 } })
    w.s:leave('pub:geral')
    eq(w.s.intents[2], nil)
end)

-- the roster model ------------------------------------------------------------

test('roster, in, out, st and malformed entries', function()
    local w = online()
    w.relay({ t = 'roster', room = 'p:10:5', slot = 0, u = {
        { 7, 100, 1007, 'Me', 0 }, { 8, 101, 1008, 'Ana', 1 }, { 'x', 1, 2, 'Bad', 0 }, { 9, 1, 2 }, 'junk',
        { 10, 102, 1010, string.rep('n', 41), 0 }, { 11, 103, 1011, 'Bo', 300 } } })
    local room = w.s.rooms[0]
    eq(room.count, 2, 'only the two good rows')
    w.relay({ t = 'in', room = 'p:10:5', u = { { 12, 104, 1012, 'Caio', 64 } } })
    eq(room.count, 3)
    eq(room.members[12].name, 'Caio')
    w.relay({ t = 'in', room = 'p:10:5', u = { { 12, 104, 1012, 'Caio', 64 } } })
    eq(room.count, 3, 'a repeated in is not counted twice')
    w.relay({ t = 'st', room = 'p:10:5', sid = 8, f = 5 })
    eq(room.members[8].flags, 5)
    w.relay({ t = 'st', room = 'p:10:5', sid = 8, f = 'x' })
    eq(room.members[8].flags, 5)
    w.relay({ t = 'out', room = 'p:10:5', sid = 12 })
    eq(room.count, 2)
    eq(room.members[12], nil)
    w.relay({ t = 'out', room = 'p:10:5', sid = 99 })
    eq(room.count, 2)
    w.relay({ t = 'over', room = 'p:10:5', n = 3 })
    eq(room.over, 3)
    w.relay({ t = 'roster', room = 'nope', u = {} })
    w.relay({ t = 'whatever', room = 'p:10:5' })
    eq(w.s.rooms[0], room)
end)

test('control messages before welcome and garbage are ignored', function()
    local w = newWorld()
    w.s:gameStart('win', 'lite')
    w.s:onControl('{"t":"roster","room":"p:1:1","u":[[2,0,1,"A",0]]}')
    eq(next(w.s.rooms), nil)
    for _, bad in ipairs({ '', '{', 'null', '{"t":5}', '[]', string.rep('{', 20000) }) do
        assert(pcall(w.s.onControl, w.s, bad), 'raised on ' .. bad:sub(1, 10))
    end
    local o = online()
    o.s:onControl('{"t":"welcome","sid":3}')
    eq(o.s.sid, 7, 'a second welcome is ignored')
end)

test('speaking edges, counted once per player', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8 }, { 9 } })
    roster(w, 'g:45', { { 7 }, { 8 } })
    w.s:onSpeaking(8, true)
    w.s:onSpeaking(8, true)
    eq(w.s.speakingCount, 1)
    eq(w.s.rooms[0].members[8].speaking, true)
    eq(w.s.rooms[1].members[8].speaking, true)
    w.s:onSpeaking(9, 1)
    eq(w.s.speakingCount, 2)
    w.s:onSpeaking(50, true)
    eq(w.s.speakingCount, 2, 'not in our rooms')
    w.relay({ t = 'out', room = 'p:10:5', sid = 8 })
    eq(w.s.speakingCount, 2, 'still in the guild room')
    w.relay({ t = 'out', room = 'g:45', sid = 8 })
    eq(w.s.speakingCount, 1)
    w.relay({ t = 'left', room = 'p:10:5', why = 'kicked' })
    eq(w.s.speakingCount, 0)
end)

test('a joining member who is already speaking shows it', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8 } })
    w.s:onSpeaking(8, true)
    roster(w, 'pub:geral', { { 7 }, { 8 } })
    eq(w.s.rooms[2].members[8].speaking, true)
end)

test('rows: speaking, moderators, then names; at most 40', function()
    local room = { members = {}, count = 0 }
    for i = 1, 55 do
        room.members[i] = { sid = i, name = string.format('n%02d', 56 - i), flags = 0, speaking = false }
    end
    room.members[50].speaking = true
    room.members[10].flags = S.F_MODERATOR
    local list, hidden = S.visibleMembers(room, S.ROW_CAP)
    eq(#list, 40)
    eq(hidden, 15)
    eq(list[1].sid, 50, 'speaking first')
    eq(list[2].sid, 10, 'moderator next')
    eq(list[3].name, 'n01', 'then by name')
    local small = { members = { [1] = { sid = 1, name = 'b', flags = 0 }, [2] = { sid = 2, name = 'A', flags = 0 } } }
    local l2, h2 = S.visibleMembers(small, 40)
    eq(#l2, 2)
    eq(h2, 0)
    eq(l2[1].name, 'A', 'names ignore case')
end)

test('a room is capped at 500 members', function()
    local w = online()
    local u = {}
    for i = 1, 600 do
        u[i] = { i, 0, i, 'P' .. i, 0 }
    end
    w.relay({ t = 'roster', room = 'ev:eventos', u = u })
    eq(w.s.rooms[2].count, S.MAX_MEMBERS)
end)

test('dir is validated and capped', function()
    local w = online()
    local rooms = { { 'pub:geral', 'Geral', 12, 100, 50, 0 }, { 'ev:eventos', 'Eventos', 45, 300, 0, 1 },
        { 'p:1:1', 'Party', 1, 1, 0, 0 }, { 'pub:x' }, 'junk' }
    for i = 1, 80 do
        rooms[#rooms + 1] = { 'pub:r' .. i, 'R' .. i, 0, 100, 0, 0 }
    end
    w.relay({ t = 'dir', rooms = rooms })
    eq(w.s.dir[1].id, 'pub:geral')
    eq(w.s.dir[2].stage, true)
    eq(w.s.dir[3].id, 'pub:r1', 'the bad entries are skipped')
    assert(#w.s.dir <= S.MAX_DIR)
    assert(w.s:requestDir() == true)
    assert(w.s:requestDir() == false, '1 per 2 s')
    w.advance(2000)
    assert(w.s:requestDir() == true)
end)

-- hostile or broken input, and the limits behind it -----------------------------

local function emitCount(w, what)
    local n = 0
    for _, e in ipairs(w.emits) do
        if e[1] == what then
            n = n + 1
        end
    end
    return n
end

local function isWhole(v)
    return type(v) == 'number' and v == v and v == math.floor(v) and v > -math.huge and v < math.huge
end

test('server numbers: NaN, infinities, text and tables are clamped or dropped', function()
    eq(S.num('nan', 0, 10, 7), 7)
    eq(S.num(0 / 0, 0, 10, 7), 7)
    eq(S.num(math.huge, 0, 10, 7), 10)
    eq(S.num(-math.huge, 0, 10, 7), 0)
    eq(S.num('12', 0, 100, 0), 12)
    eq(S.num({}, 0, 10, 3), 3)
    eq(S.num(true, 0, 10, 3), 3)
    eq(S.num(5.9, 0, 10, 0), 5)
    local w = newWorld()
    w.s:gameStart('win', 'lite', ME)
    w.s:onOpcode({ a = 'cfg', on = true, url = CFG.url, psl = 'nan' })
    eq(w.s.cfg.psl, 50)
    w.s:onOpcode({ a = 'cfg', on = false, why = 'banned', ['until'] = math.huge })
    eq(w.s.untilTs, S.MAX_TS, 'a ban "until" past 2100 is clamped')
    w.s:onOpcode({ a = 'err', code = 'banned', s = 'nan' })
    assert(isWhole(w.s.untilTs), 'err banned with s=nan')
    -- the relay, as text: rxi's json reads 1e999 as an infinity
    local o = online()
    roster(o, 'p:10:5', { { 7 }, { 8 } })
    assert(o.s:report('p:10:5', 8, 'spam', 'x'))
    o.s:onOpcode({ a = 'rep', ok = false, code = 'wait', s = math.huge })
    local rep = o.emits[#o.emits]
    eq(rep[1], 'report')
    eq(rep[4], 86400)
    o.s:onControl('{"t":"over","room":"p:10:5","n":1e999}')
    eq(o.s.rooms[0].over, 999)
    o.s:onControl('{"t":"over","room":"p:10:5","n":"nan"}')
    eq(o.s.rooms[0].over, 0)
    o.s:onControl('{"t":"dir","rooms":[["pub:a","A","nan",1e999,-1e999,0],["pub:b","B",{},[],"x",1]]}')
    for _, d in ipairs(o.s.dir) do
        assert(isWhole(d.members) and isWhole(d.cap) and isWhole(d.minLevel), 'dir ' .. d.id)
    end
    eq(o.s.dir[1].cap, 99999)
    o.s:onControl('{"t":"muted","until":1e999}')
    eq(o.s.mutedUntil, S.MAX_TS)
    o.s:onControl('{"t":"welcome","sid":7,"now":"x"}') -- a second welcome: ignored
    eq(o.s.state, ST.ONLINE)
end)

test('names and labels from the server lose control characters', function()
    local w = online(nil, { { id = 'g:3', k = 'guild', l = 'Os\nBravos\0' } })
    eq(w.s.tokRooms.guild.label, 'OsBravos')
    w.relay({ t = 'dir', rooms = { { 'pub:a', 'Ge\r\nral', 1, 100, 0, 0 } } })
    eq(w.s.dir[1].name, 'Geral')
    eq(S.parseMember({ 2, 1, 1, 'A\tna\27', 0 }).name, 'Ana')
end)

test('a roster of 500 members with the longest names is read', function()
    local w = online()
    local u = {}
    for i = 1, S.MAX_MEMBERS do
        u[i] = { i + 1, 4294967295, 4294967295, string.rep('W', 29), 127 }
    end
    local text = json.encode({ t = 'roster', room = 'ev:eventos', slot = 2, u = u })
    assert(#text <= S.MAX_CTL_BYTES, 'roster of ' .. #text .. ' bytes')
    w.s:onControl(text)
    eq(w.s.rooms[2].count, S.MAX_MEMBERS)
    eq(S.parseMember({ 2, 4294967296, 1, 'x', 0 }), nil, 'a creature id past 32 bits')
end)

test('deeply nested or oversized JSON is refused without raising', function()
    local deep = '{"t":"roster","room":"p:10:5","u":' .. string.rep('[', 18000) .. string.rep(']', 18000) .. '}'
    local ok = pcall(S.decode, deep, S.MAX_CTL_BYTES)
    assert(ok, 'decode raised on deep nesting')
    local w = online()
    assert(pcall(w.s.onControl, w.s, deep), 'onControl raised on deep nesting')
    local big = '{"t":"roster","room":"p:10:5","u":[' .. string.rep('[9,1,1,"a",0],', 4000) .. '[9,1,1,"a",0]]}'
    assert(#big > S.MAX_CTL_BYTES)
    eq(S.decode(big, S.MAX_CTL_BYTES), nil)
    w.s:onControl(big)
    eq(w.s.rooms[0], nil)
end)

test('a ban at the first contact shows the panel once; cfg off shows nothing', function()
    local w = newWorld()
    w.s:gameStart('win', 'lite', ME)
    w.s:onOpcode({ a = 'cfg', on = false, why = 'beta' })
    eq(emitCount(w, 'cfg'), 0, 'beta: no panel')
    w.s:onOpcode({ a = 'cfg', on = false, why = 'banned', ['until'] = 1700086400 })
    eq(emitCount(w, 'cfg'), 1, 'banned: the panel tells of it')
    eq(w.s.everOn, false, 'not offered: no onboarding')
    w.s:onOpcode({ a = 'cfg', on = false, why = 'banned', ['until'] = 1700086400 })
    w.s:onOpcode(CFG) -- the ban ended meanwhile
    eq(emitCount(w, 'cfg'), 1, 'one panel per login')
    eq(w.s.state, ST.READY)
    w.s:gameEnd()
    w.s:gameStart('win', 'lite', ME)
    w.advance(S.HI_GAP_MS)
    w.s:onOpcode(CFG)
    eq(emitCount(w, 'cfg'), 2, 'made again in the next login')
end)

test('cfg on while replaced: no reconnect by itself', function()
    local w = online(S.normalizePrefs(OPTED_IN))
    w.s:onEngineState('closed', 4409)
    w.s:onOpcode(CFG)
    eq(w.s.state, ST.BLOCKED)
    eq(w.s.why, 'replaced')
    w.advance(600000)
    eq(#w.connects, 1)
end)

test('a pushed token with the same rooms does not redraw the panel', function()
    local w = online()
    local n = emitCount(w, 'tok')
    w.advance(240000)
    w.s:onOpcode(tokMsg())
    eq(emitCount(w, 'tok'), n, 'same rooms')
    eq(w.lastCtl().t, 'auth', 'the token is still used')
    w.s:onOpcode(tokMsg({ { id = 'p:10:6', k = 'party', l = 'Party' } }))
    eq(emitCount(w, 'tok'), n + 1, 'a new party epoch')
end)

test('one mute per player in party and guild; a sid twice in a roster counts once', function()
    local prefs = S.normalizePrefs(nil)
    S.setUserPref(prefs, 4242, 'm', true, 1)
    local w = online(prefs)
    roster(w, 'p:10:5', { { 7 }, { 8, 0, 4242, 'Ana' } })
    roster(w, 'g:3', { { 7 }, { 8, 0, 4242, 'Ana' } })
    eq(#w.ctlOf('mute'), 1, 'the relay keeps it for the whole session')
    eq(w.s.rooms[1].members[8].mutedForMe, true)
    w.s:onSpeaking(8, true)
    roster(w, 'p:10:5', { { 8, 0, 4242, 'Ana' }, { 8, 0, 4242, 'Ana' }, { 7 } })
    eq(w.s.rooms[0].count, 2)
    eq(w.s.rooms[0].members[8].speaking, true, 'still speaking after the duplicate')
    eq(w.s.rooms[0].members[8].mutedForMe, true)
    eq(w.s.speakingCount, 1)
end)

test('joins keep the relay budget of 10 a minute', function()
    local w = online() -- the party auto-join is the first
    local okCount = 0
    for i = 1, 12 do
        if w.s:join('pub:r' .. i) then
            okCount = okCount + 1
        end
    end
    eq(okCount, S.JOIN_BUDGET - 1)
    w.advance(10000)
    eq(#w.ctlOf('join'), S.JOIN_BUDGET, 'never over the budget')
    local last = w.emits[#w.emits]
    eq(last[1], 'notice')
    eq(last[3], 'rate', 'the player is told to wait')
    w.advance(S.JOIN_WINDOW_MS)
    assert(w.s:join('pub:later'), 'a minute later')
end)

test('every mute of a big guild reaches the relay, at its rate', function()
    local prefs = S.normalizePrefs(nil)
    local u = { { 7 } }
    for i = 1, 150 do
        S.setUserPref(prefs, 5000 + i, 'm', true, i)
        u[#u + 1] = { 100 + i, 0, 5000 + i, 'G' .. i }
    end
    local w = online(prefs, {})
    roster(w, 'g:3', u)
    w.advance(60000)
    eq(#w.ctlOf('mute'), 150, 'none dropped from the queue')
end)

-- preferences -----------------------------------------------------------------

test('mute-for-me by guid survives a reconnect with a new sid', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8, 0, 4242, 'Ana' } })
    w.s:setUserMuted(w.s.rooms[0].members[8], true)
    eq(w.lastCtl().t, 'mute')
    eq(w.lastCtl().sid, 8)
    eq(w.lastCtl().on, 1)
    assert(S.userPref(w.s.prefs, 4242).m)
    -- the next login: the prefs went through g_settings
    local saved = S.normalizePrefs(S.serializePrefs(w.s.prefs))
    local w2 = online(saved)
    roster(w2, 'p:10:5', { { 3 }, { 15, 0, 4242, 'Ana' } })
    local mutes = w2.ctlOf('mute')
    eq(#mutes, 1)
    eq(mutes[1].sid, 15)
    eq(w2.s.rooms[0].members[15].mutedForMe, true)
    w2.s:setUserMuted(w2.s.rooms[0].members[15], false)
    eq(S.userPref(w2.s.prefs, 4242), nil, 'back to the defaults: dropped')
end)

test('volume by guid goes to the engine on join', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8, 0, 77, 'Bo' } })
    w.s:setUserVolume(w.s.rooms[0].members[8], 150)
    local call = w.engineCalls[#w.engineCalls]
    eq(call[1], 'setUserVolume')
    eq(call[2], 8)
    eq(call[3], 1.5)
    w.s:setUserVolume(w.s.rooms[0].members[8], 999)
    eq(S.userPref(w.s.prefs, 77).v, 200, 'clamped')
    local w2 = online(S.normalizePrefs(S.serializePrefs(w.s.prefs)))
    roster(w2, 'g:1', { { 30, 0, 77, 'Bo' } })
    call = w2.engineCalls[#w2.engineCalls]
    eq(call[1], 'setUserVolume')
    eq(call[2], 30)
    eq(call[3], 2)
end)

test('prefs read back from OTML types and junk', function()
    local p = S.normalizePrefs({ chars = { [ME] = { t = '5' }, [''] = { t = 1 }, Bad = 'x' }, autoParty = 0,
        vadDb = '-90', inGain = '150', preset = 'loud', inDevice = 2, outDevice = 'nan',
        mode = 'vad', users = { g12 = { v = '50', m = 'false', t = '9' }, g13 = { v = 100, m = false },
            x14 = { v = 10 }, g15 = 'junk', g16 = { m = 1, v = true } } })
    eq(p.chars[ME].t, 5)
    eq(p.chars[''], nil, 'an empty name is junk')
    eq(p.chars.Bad, nil)
    eq(p.inDevice, '2', 'a device name OTML read as a number')
    eq(p.outDevice, 'nan')
    eq(p.autoParty, false)
    eq(p.vadDb, -60)
    eq(p.inGain, 150)
    eq(p.preset, 'normal')
    eq(p.mode, 'vad')
    eq(p.users.g12.v, 50)
    eq(p.users.g12.m, false)
    eq(p.users.g13, nil, 'defaults are not kept')
    eq(p.users.x14, nil)
    eq(p.users.g15, nil)
    eq(p.users.g16.m, true)
    eq(p.users.g16.v, 1, 'a volume read back as true is 1')
    local d = S.normalizePrefs(nil)
    eq(d.autoParty, true)
    eq(d.autoGuild, false)
    eq(d.overheadIcon, true)
end)

test('at most 500 players kept, the least recently used go first', function()
    local p = S.normalizePrefs(nil)
    for i = 1, 520 do
        S.setUserPref(p, i, 'm', true, i)
    end
    local n = 0
    for _ in pairs(p.users) do
        n = n + 1
    end
    eq(n, S.USERS_CAP)
    eq(p.users.g1, nil)
    eq(p.users.g20, nil)
    assert(p.users.g21 and p.users.g520)
    S.setUserPref(p, 21, 'v', 50, 600) -- used again: now the newest
    S.setUserPref(p, 600, 'm', true, 601)
    assert(p.users.g21, 'touched entry kept')
    eq(p.users.g22, nil, 'the oldest went')
end)

test('self-mute and deafen: saved, told to the relay and the engine', function()
    local w = online()
    w.s:setDeafened(true)
    eq(w.lastCtl().t, 'deaf')
    eq(w.lastCtl().on, 1)
    eq(w.s.prefs.deafened, true)
    local methods = {}
    for _, c in ipairs(w.engineCalls) do
        methods[c[1]] = c[2]
    end
    eq(methods.setDeafened, true)
    eq(methods.setTransmit, -1, 'deafened stops talking')
    w.s:setSelfMuted(true)
    eq(w.lastCtl().t, 'self')
    -- after a reconnect both are sent again
    local w2 = online(S.normalizePrefs(S.serializePrefs(w.s.prefs)))
    eq(#w2.ctlOf('deaf'), 1)
    eq(#w2.ctlOf('self'), 1)
end)

-- reports ---------------------------------------------------------------------

test('report: reason, text and names within 2048 bytes', function()
    local room = { id = 'pub:geral', members = {} }
    for i = 1, 60 do
        room.members[i] = { sid = i, guid = 1000 + i, name = string.rep(string.char(64 + i % 26), 30), flags = 0 }
    end
    local target = room.members[5]
    eq(select(2, S.buildReport(room, target, 'bad', 'x')), 'why')
    local msg = S.buildReport(room, target, 'ofensa', string.rep('\233', 500))
    eq(msg.a, 'report')
    eq(msg.c, 1005)
    eq(msg.n, target.name)
    eq(#msg.txt, S.REPORT_TXT)
    eq(msg.who[1], target.name, 'the reported player first')
    assert(#msg.who <= S.REPORT_WHO)
    assert(#json.encode(msg) <= S.MAX_OPCODE_BYTES)
    local huge = { id = 'pub:geral', members = {} }
    for i = 1, 30 do
        huge.members[i] = { sid = i, guid = i, name = string.rep('"', 40), flags = 0 }
    end
    local m2 = S.buildReport(huge, huge.members[1], 'spam', string.rep('\\', 300))
    assert(m2 and #json.encode(m2) <= S.MAX_OPCODE_BYTES, 'escaped text trimmed to fit')
    local m3 = S.buildReport(room, target, 'outro', '  linha\nnova\0  ')
    eq(m3.txt, 'linha nova', 'control characters and edges')
end)

test('one report at a time', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8 } })
    assert(w.s:report('p:10:5', 8, 'spam', 'alto'))
    eq(w.last142().a, 'report')
    local ok, err = w.s:report('p:10:5', 8, 'spam', 'alto')
    eq(ok, nil)
    eq(err, 'pending')
    w.s:onOpcode({ a = 'rep', ok = true, code = 'sent' })
    assert(w.s:report('p:10:5', 8, 'spam', 'alto'), 'after the answer')
    eq(select(2, w.s:report('nope', 8, 'spam', '')), 'pending')
end)

test('an answer to no report is ignored', function()
    local w = online()
    local n = #w.emits
    w.s:onOpcode({ a = 'rep', ok = false, code = 'limit' })
    eq(#w.emits, n, 'nothing to tell the player')
end)

test('moderation messages are checked', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8 } })
    assert(w.s:moderate('mute', 'p:10:5', 8, 600))
    eq(w.lastCtl().t, 'mod')
    eq(w.lastCtl().s, 600)
    assert(not w.s:moderate('ban', 'p:10:5', 8))
    assert(not w.s:moderate('kick', 'g:1', 8), 'not in that room')
end)

-- the control rate limit --------------------------------------------------------

test('control messages: a burst of 8, then 4 a second, mutes merged', function()
    local w = online(nil, {})
    local base = #w.ctl
    for i = 1, 20 do
        w.s:send({ t = 'join', room = 'pub:r' .. i })
    end
    eq(#w.ctl - base, S.CTL_BURST, 'the burst')
    w.s:send({ t = 'mute', sid = 5, on = 1 })
    w.s:send({ t = 'mute', sid = 5, on = 0 })
    eq(#w.s.queue, 13, 'twelve joins and one mute')
    eq(w.s.queue[13].on, 0, 'the newer mute replaced the older')
    w.advance(1000)
    eq(#w.ctl - base, S.CTL_BURST + 4, 'four in the next second')
    w.advance(10000)
    eq(#w.s.queue, 0)
    eq(#w.ctl - base, 21)
    for i = 1, 200 do
        w.s:send({ t = 'join', room = 'pub:q' .. i })
    end
    assert(#w.s.queue <= S.CTL_QUEUE, 'queue bounded')
end)

-- keys and translations --------------------------------------------------------

test('push-to-talk keys that type in the chat', function()
    assert(S.isChatKey(65, 0), 'A')
    assert(S.isChatKey(65, 4), 'Shift+A types an A')
    assert(not S.isChatKey(65, 1), 'Ctrl+A')
    assert(not S.isChatKey(65, 2), 'Alt+A')
    assert(S.isChatKey(48, 0), '0')
    assert(S.isChatKey(32, 0), 'Space')
    assert(S.isChatKey(5, 0), 'Enter')
    assert(S.isChatKey(14, 0) and S.isChatKey(17, 0), 'arrows')
    assert(S.isChatKey(141, 0), 'numpad')
    assert(not S.isChatKey(128, 0), 'F1')
    assert(not S.isChatKey(140, 0), 'F12')
end)

test('virtual keys for push-to-talk in the background', function()
    eq(S.virtualKey('V'), 0x56)
    eq(S.virtualKey('5'), 0x35)
    eq(S.virtualKey('F1'), 0x70)
    eq(S.virtualKey('F12'), 0x7B)
    eq(S.virtualKey('Space'), 0x20)
    eq(S.virtualKey('Ctrl+V'), 0)
    eq(S.virtualKey(''), 0)
    eq(S.virtualKey(nil), 0)
end)

test('every string of the module has its Portuguese', function()
    local pt = dofile(MODULE .. 'voice_locale.lua')
    local missing = {}
    local function need(s)
        if not pt[s] then
            missing[#missing + 1] = s
        end
    end
    for _, file in ipairs({ 'voice.lua', 'voice_ui.lua', 'voice_settings.lua', 'voice.otui', 'voicesettings.otui',
        'voiceonboard.otui' }) do
        local src = io.open(MODULE .. file):read('*a')
        for s in src:gmatch("[%W]tr%(%s*'([^']*)'") do
            need(s)
        end
        for s in src:gmatch("fmt%(%s*'([^']*)'") do
            need(s)
        end
        -- English kept in tables or passed to a helper that translates it
        for s in src:gmatch("slider%([^,]+,[^,]+,%s*'([^']*)'") do
            need(s)
        end
        for block in src:gmatch('local %u+_?%u* = (%b{})') do
            for s in block:gmatch("= '([^']*)'") do
                need(s)
            end
            for s in block:gmatch(", '([^']*)' }") do
                need(s)
            end
        end
    end
    for _, v in pairs(pt) do
        assert(not v:find('[\128-\255][\128-\191]'), 'UTF-8 left in a translation: ' .. v)
    end
    assert(#missing == 0, 'no Portuguese for: ' .. table.concat(missing, ' | '))
end)

test('push-to-talk keys taken elsewhere: actions, hotkeys, the hotkeys manager, the action bar', function()
    -- the client globals voice_settings.lua reads
    KeyShift, KeyControl, KeyCtrlCmd, KeyAltOpt, KeyMeta, KeyEscape = 22, 24, 21, 23, 25, 1
    CHAT_MODE = { ON = 1, OFF = 2 }
    KEY_CATEGORY = 'Voz'
    KEY_TALK = { [0] = 'Falar na party', [1] = 'Falar na guild', [2] = 'Falar na sala/evento' }
    local actions = { ['Ctrl+K'] = true }
    Keybind = {
        currentPreset = 'Druid',
        hotkeys = { [1] = { Druid = { { primary = 'F1', secondary = '' } } }, [2] = { Druid = { { primary = 'F2' } } } },
        isKeyComboUsed = function(combo) return actions[combo] == true end,
    }
    local browser = false
    g_platform = { isBrowser = function() return browser end }
    local manager = { F5 = true }
    local bars = { chatOn = { { keysequence = 'F6' } }, chatOff = { { keysequence = 'f7' }, 'junk' } }
    modules = {
        game_hotkeys = { isHotkeyUsedByManager = function(c) return manager[c] == true end },
        game_actionbar = { ApiJson = { hasCurrentHotkeySet = function() return true end,
            getHotkeyEntries = function(chat) return bars[chat] end } },
    }
    dofile(MODULE .. 'voice_settings.lua')
    local taken = VoiceSettings.keyTaken
    assert(taken('Ctrl+K', 0, false), 'another Keybind action')
    assert(taken('F1', 0, false), 'a hotkey of the chat-on mode')
    assert(not taken('F1', 0, true), 'a chat-off-only key meets only chat-off hotkeys')
    assert(taken('F2', 0, true))
    assert(taken('F5', 0, false), 'the hotkeys manager')
    assert(taken('F6', 0, false), 'an action bar button, chat on')
    assert(not taken('F6', 0, true))
    assert(taken('F7', 0, true), 'an action bar button, any case')
    assert(not taken('F8', 0, false))
    assert(not taken('F11', 0, false))
    browser = true
    assert(taken('F11', 0, false), 'the browser page keeps F11')
    modules.game_actionbar.ApiJson.getHotkeyEntries = function() error('a broken action bar') end
    modules.game_hotkeys.isHotkeyUsedByManager = function() error('a broken manager') end
    assert(not taken('F8', 0, false), 'other modules failing never break the capture')
    modules, Keybind, g_platform = nil, nil, nil
end)

test('the voice strings never change the text of other windows', function()
    -- pt.lua runs in a box of its own: it calls client_locales at its end
    local env = setmetatable({}, { __index = _G })
    env.modules = setmetatable({}, { __index = function()
        return setmetatable({}, { __index = function() return function() end end })
    end })
    local chunk = assert(loadfile(ROOT .. '/data/locales/pt.lua'))
    setfenv(chunk, env)
    assert(pcall(chunk))
    local pt = env.locale.translation
    local voice = dofile(MODULE .. 'voice_locale.lua')
    for english, text in pairs(voice) do
        if pt[english] ~= nil then
            eq(text, pt[english], 'pt.lua already has "' .. english .. '"')
        end
    end
end)

-- the engines -----------------------------------------------------------------

-- client globals the engines use
local events = {}
function scheduleEvent(fn, ms)
    local e = { fn = fn, at = (events.now or 0) + ms }
    events[#events + 1] = e
    return e
end
function removeEvent(e)
    if e then
        e.cancelled = true
    end
end
function addEvent(fn)
    return scheduleEvent(fn, 0)
end
local function runEvents(ms)
    local target = (events.now or 0) + ms
    while true do
        local best
        for _, e in ipairs(events) do
            if not e.cancelled and not e.done and e.at <= target and (not best or e.at < best.at) then
                best = e
            end
        end
        if not best then
            break
        end
        events.now = best.at
        best.done = true
        best.fn()
    end
    events.now = target
end

test('lite engine: hello with a=0, one terminal event, no leak', function()
    local sockets = {}
    HTTP = { operations = {} }
    g_http = { ws = true }
    function HTTP.webSocket(url, callbacks, timeout)
        local id = #sockets + 1
        HTTP.operations[id] = { callbacks = callbacks }
        local s = { id = id, url = url, sent = {}, callbacks = callbacks, closed = false }
        s.send = function(m) s.sent[#s.sent + 1] = m end
        s.close = function() s.closed = true end
        sockets[id] = s
        return s
    end
    dofile(MODULE .. 'engine_lite.lua')
    assert(EngineLite.available())
    local got = {}
    local e = EngineLite.create(function(kind, s, a, b) got[#got + 1] = { kind, s, a, b } end, { build = '4.2 abc' })
    eq(e.audio, false)
    e:connect('wss://x/voz', TOK)
    local s1 = sockets[1]
    s1.callbacks.onOpen('code::websocket_open')
    local hello = json.decode(s1.sent[1])
    eq(hello.t, 'hello')
    eq(hello.v, 1)
    eq(hello.tok, TOK)
    eq(hello.cl, 'lite')
    eq(hello.a, 0)
    eq(hello.b, '4.2 abc')
    s1.callbacks.onMessage('{"t":"welcome","sid":3}\0')
    eq(got[#got][1], 'ctl')
    eq(got[#got][2], '{"t":"welcome","sid":3}', 'the browser\'s C terminator is cut')
    e:send({ t = 'dir' })
    eq(json.decode(s1.sent[2]).t, 'dir')
    s1.callbacks.onError('close_code::error websocket')
    s1.callbacks.onClose('close_code::normal')
    local terminal = 0
    for _, g in ipairs(got) do
        if g[1] == 'state' and (g[2] == 'closed' or g[2] == 'error') then
            terminal = terminal + 1
            eq(g[3], nil, 'no close code from HTTP.webSocket')
        end
    end
    eq(terminal, 1, 'one terminal event')
    eq(HTTP.operations[1], nil, 'operation dropped')
    -- our own disconnect: no event from the old socket afterwards
    e:connect('wss://x/voz', TOK)
    local s2 = sockets[2]
    e:disconnect()
    assert(s2.closed)
    local n = #got
    s2.callbacks.onClose('close_code::normal')
    s2.callbacks.onMessage('{"t":"roster"}')
    eq(#got, n, 'nothing after our disconnect')
    eq(HTTP.operations[2], nil)
    -- a code, if a later build sends one
    e:connect('wss://x/voz', TOK)
    sockets[3].callbacks.onClose('close_code::4403')
    eq(got[#got][3], 4403)
end)

test('lite engine: a websocket that cannot be created is an error next frame', function()
    function HTTP.webSocket() error('WebSocket is not supported') end
    local got = {}
    local e = EngineLite.create(function(kind, s, a) got[#got + 1] = { kind, s, a } end, { build = '' })
    e:connect('wss://x/voz', TOK)
    eq(got[#got][2], 'connecting')
    runEvents(1)
    eq(got[#got][2], 'error')
end)

test('mock engine: welcome, roster, speaking, then a whole session over it', function()
    dofile(MODULE .. 'engine_mock.lua')
    local w = newWorld()
    local engine = EngineMock.create(function(kind, s, a, b)
        if kind == 'state' then
            w.s:onEngineState(s, a)
        elseif kind == 'ctl' then
            w.s:onControl(s)
        elseif kind == 'spk' then
            w.s:onSpeaking(a, b == 1)
        end
    end, { self = { cid = 5, name = 'Eu' } })
    -- wire the session to the mock: canary's answers and the relay
    local io = w.s.io
    io.send142 = function(t)
        w.sent142[#w.sent142 + 1] = t
        local r = EngineMock.reply(t)
        if r then
            w.s:onOpcode(r)
        end
    end
    io.connect = function(url, tok) engine:connect(url, tok) end
    io.sendCtl = function(t) engine:send(t) end
    w.s:gameStart('win', 'full')
    eq(w.s.state, ST.READY)
    w.s:setWant(true)
    eq(w.s.state, ST.CONNECTING)
    runEvents(300)
    eq(w.s.state, ST.ONLINE)
    runEvents(100)
    local room = w.s.rooms[0]
    assert(room, 'party roster from the mock')
    eq(room.id, 'p:1:1')
    eq(room.count, 5)
    runEvents(60000)
    assert(w.s.speakingCount >= 0 and w.s.speakingCount <= 4)
    local edges = 0
    for _, e in ipairs(w.emits) do
        if e[1] == 'speaking' then
            edges = edges + 1
        end
    end
    assert(edges >= 10, 'speaking edges: ' .. edges)
    w.s:moderate('mute', 'p:1:1', 3, 600)
    runEvents(100)
    assert(S.hasFlag(room.members[3].flags, S.F_SERVER_MUTED), 'mock moderation')
    engine:drop(4409)
    eq(w.s.state, ST.BLOCKED)
    local pending = 0
    for _, e in ipairs(events) do
        if not e.cancelled and not e.done then
            pending = pending + 1
        end
    end
    eq(pending, 0, 'the mock leaves no event behind')
end)

test('mock engine: speaking edges come back after a reconnect', function()
    local edges = 0
    local e = EngineMock.create(function(kind)
        if kind == 'spk' then
            edges = edges + 1
        end
    end, {})
    local function session()
        e:connect('ws://x/voz', TOK)
        runEvents(300)
        e:send({ t = 'join', room = 'p:1:1' })
        runEvents(20000)
    end
    session()
    assert(edges > 0, 'edges in the first session')
    e:disconnect()
    edges = 0
    session()
    assert(edges > 0, 'edges after the reconnect')
    e:terminate()
end)

-- the whole module in a stub client ---------------------------------------------

test('voice.lua in a stub client: nothing until cfg, nothing left at game end', function()
    local realDofile = dofile
    local base = #events
    local function pending()
        local n = 0
        for i = base + 1, #events do
            if not events[i].cancelled and not events[i].done then
                n = n + 1
            end
        end
        return n
    end
    -- widgets: any field is a child or a method; the top-level ones (no
    -- parent, or the root) are tracked and must all be destroyed at game end
    local tracked, errors, keybinds, sent, handlers = {}, {}, {}, {}, {}
    local Fake = {}
    local function fake(top)
        local w = setmetatable({}, Fake)
        if top then
            tracked[#tracked + 1] = w
        end
        return w
    end
    Fake.__call = function() return fake() end
    Fake.__index = function(t, k)
        local f
        if k == 'destroy' then
            f = function(self) rawset(self, '_dead', true) end
        elseif k == 'isDestroyed' then
            f = function(self) return rawget(self, '_dead') == true end
        elseif k == 'isVisible' then
            f = function() return false end -- the panel stays closed
        else
            f = fake()
        end
        rawset(t, k, f)
        return f
    end
    rootWidget = fake()
    g_ui = {
        loadUI = function() return fake(true) end,
        createWidget = function(style, parent) return fake(parent == nil or parent == rootWidget) end,
        importStyle = function() end,
    }
    local store = {}
    g_settings = {
        getNode = function(k) return store[k] end,
        setNode = function(k, v) store[k] = v end,
        getValue = function() return '' end,
    }
    ProtocolGame = {
        registerExtendedOpcode = function(op, fn) assert(not handlers[op], 'taken') handlers[op] = fn end,
        unregisterExtendedOpcode = function(op) handlers[op] = nil end,
    }
    local protocol = { sendExtendedOpcode = function(self, op, buf) sent[#sent + 1] = { op = op, msg = json.decode(buf) } end }
    g_game = {
        isOnline = function() return true end,
        getProtocolGame = function() return protocol end,
        getCharacterName = function() return ME end,
        getLocalPlayer = function() return nil end,
    }
    function connect(obj, slots) for k, v in pairs(slots) do obj[k] = v end end
    function disconnect(obj, slots) for k in pairs(slots) do obj[k] = nil end end
    g_platform = { isBrowser = function() return false end, isMobile = function() return false end }
    g_app = { getVersion = function() return '1.0' end }
    g_clock = { millis = function() return events.now or 0 end }
    g_logger = { error = function(m) errors[#errors + 1] = m end }
    tr = function(text, ...)
        local ok, out = pcall(string.format, text, ...)
        return ok and out or text
    end
    AnchorTop, AnchorBottom, AnchorLeft, AnchorRight, MouseRightButton = 1, 2, 3, 4, 2
    KEY_UP, KEY_DOWN = 1, 2
    SoundChannels = {}
    Keybind = {
        chatMode = 1, currentPreset = 'Druid', hotkeys = {},
        new = function(c, a) keybinds[c .. '_' .. a] = 'new' end,
        bind = function(c, a) keybinds[c .. '_' .. a] = 'bound' end,
        delete = function(c, a) keybinds[c .. '_' .. a] = nil end,
        getKeybindKeys = function() return { primary = '', secondary = '' } end,
    }
    -- a key the voice locale also has, with other words: pt.lua's stay
    local pt = { translation = { ['Turn voice on'] = 'Ligar a voz' } }
    modules = {
        client_locales = { getInstalledLocales = function() return { pt = pt } end },
        client_topmenu = { addRightGameToggleButton = function() return fake(true) end },
        game_textmessage = { displayGameMessage = function() end },
    }
    local sockets = {}
    HTTP = { operations = {} }
    g_http = { ws = true }
    function HTTP.webSocket(url, callbacks)
        local so = { id = #sockets + 1, callbacks = callbacks, sent = {}, closed = false }
        so.send = function(m) so.sent[#so.sent + 1] = json.decode(m) end
        so.close = function() so.closed = true end
        sockets[so.id] = so
        HTTP.operations[so.id] = { callbacks = callbacks }
        return so
    end
    g_voice = nil
    dofile = function(path) return realDofile((path:gsub('^/game_voice/', MODULE))) end
    for _, f in ipairs({ 'voice_state', 'engine_full', 'engine_lite', 'engine_mock', 'voice_ui', 'voice_settings',
        'voice' }) do
        realDofile(MODULE .. f .. '.lua')
    end
    local ok, err = pcall(function()
        init()
        eq(#sent, 1, 'one hi at login')
        eq(sent[1].op, 142)
        eq(sent[1].msg.a, 'hi')
        eq(sent[1].msg.cl, 'win')
        eq(sent[1].msg.eng, 'lite')
        local handler = handlers[142]
        assert(handler, 'opcode 142 registered')
        -- a server without voice, or one sending junk
        for _, junk in ipairs({ '', '{', 'null', '[1]', string.rep('{', 3000), '{"a":"cfg","on":"yes"}',
            '{"a":"tok","tok":[]}', '{"a":"err","code":{},"s":"nan"}', '{"a":"rep","ok":1}', '{"a":5}',
            '{"a":"cfg","on":true,"url":5}' }) do
            handler(protocol, 142, junk)
        end
        handler(protocol, 142, nil)
        runEvents(600000)
        eq(#tracked, 0, 'no widget without cfg')
        eq(next(keybinds), nil, 'no keybind without cfg')
        eq(pending(), 0, 'no event without cfg')
        eq(#sent, 1, 'nothing more sent')
        eq(#errors, 0, 'errors: ' .. table.concat(errors, ' | '))
        -- voice offered
        handler(protocol, 142, json.encode(CFG))
        eq(#tracked, 2, 'the panel and its top-menu button')
        eq(keybinds['Voz_Falar na party'], 'bound')
        eq(pt.translation['Turn voice on'], 'Ligar a voz', 'pt.lua text kept')
        eq(pt.translation['Mute microphone'], 'Silenciar microfone', 'voice text added')
        runEvents(3000)
        eq(#tracked, 3, 'the onboarding window')
        -- turned on: want, token, the lite socket, welcome and a roster
        setWant(true)
        eq(sent[#sent].msg.a, 'want')
        handler(protocol, 142, json.encode(tokMsg()))
        eq(#sockets, 1)
        sockets[1].callbacks.onOpen()
        eq(sockets[1].sent[1].t, 'hello')
        eq(sockets[1].sent[1].a, 0)
        sockets[1].callbacks.onMessage(json.encode({ t = 'welcome', sid = 7 }))
        eq(getSession().state, ST.ONLINE)
        sockets[1].callbacks.onMessage(json.encode({ t = 'roster', room = 'p:10:5',
            u = { { 7, 0, 1, ME, 0 }, { 8, 0, 2, 'Ana', 0 } } }))
        eq(getSession().rooms[0].count, 2)
        -- the game ends
        g_game.onGameEnd()
        for i, w in ipairs(tracked) do
            assert(w:isDestroyed(), 'top-level widget ' .. i .. ' left behind')
        end
        assert(sockets[1].closed, 'socket closed')
        eq(HTTP.operations[1], nil, 'socket forgotten')
        runEvents(2000) -- the debounced save of the opt-in
        eq(pending(), 0, 'no event left')
        assert(store.voice and store.voice.chars[ME], 'the opt-in saved for this character')
        terminate()
        eq(next(keybinds), nil, 'keybinds deleted')
        eq(handlers[142], nil, 'opcode released')
        eq(g_game.onGameStart, nil, 'g_game disconnected')
        eq(#errors, 0, 'errors: ' .. table.concat(errors, ' | '))
    end)
    dofile = realDofile
    assert(ok, err)
end)

-- the full engine over g_voice, as src/framework/luafunctions.cpp binds it
-- (the browser build); runs after the stub-client test and keeps its stubs

test('engine_full over the g_voice binding: every call bound, events end to end', function()
    local file = io.open(ROOT .. '/src/framework/luafunctions.cpp')
    local cpp = file and file:read('*a') or ''
    if file then
        file:close()
    end
    local bound = {}
    for name in cpp:gmatch('bindSingletonFunction%("g_voice", "([%w_]+)"') do
        bound[name] = true
    end
    assert(bound.isSupported and bound.connect and bound.sendControl, 'g_voice bound in luafunctions.cpp')
    -- every g_voice function engine_full.lua calls is one the C++ binds
    local src = io.open(MODULE .. 'engine_full.lua'):read('*a')
    for name in src:gmatch('g_voice%.([%a_]+)%(') do
        -- onVoiceEvent is the Lua callback the C++ calls, not a binding
        assert(bound[name] or name == 'onVoiceEvent', 'engine_full calls g_voice.' .. name .. ', which is not bound')
    end
    local list = src:match('for _, name in ipairs%((%b{})%)')
    for name in list:gmatch("'([%a_]+)'") do
        assert(bound[name], 'engine_full maps ' .. name .. ', which is not bound')
    end
    -- a fake binding: records the calls, answers the device lists
    local calls = {}
    g_voice = {}
    for name in pairs(bound) do
        g_voice[name] = function(...)
            calls[#calls + 1] = { name, ... }
        end
    end
    g_voice.isSupported = function() return true end
    g_voice.getInputDevices = function() return { 'Fake Mic' } end
    g_voice.getOutputDevices = function() return {} end
    local function last(name)
        for i = #calls, 1, -1 do
            if calls[i][1] == name then
                return calls[i]
            end
        end
    end
    local function count(name)
        local n = 0
        for _, call in ipairs(calls) do
            n = n + (call[1] == name and 1 or 0)
        end
        return n
    end
    local handlers, sent, errors = {}, {}, {}
    ProtocolGame = {
        registerExtendedOpcode = function(op, fn) handlers[op] = fn end,
        unregisterExtendedOpcode = function(op) handlers[op] = nil end,
    }
    local protocol = { sendExtendedOpcode = function(self, op, buf) sent[#sent + 1] = json.decode(buf) end }
    g_game = {
        isOnline = function() return true end,
        getProtocolGame = function() return protocol end,
        getCharacterName = function() return ME end,
        getLocalPlayer = function() return nil end,
    }
    g_platform = { isBrowser = function() return true end, isMobile = function() return false end }
    g_logger = { error = function(m) errors[#errors + 1] = m end }
    local realDofile = dofile
    dofile = function(path) return realDofile((path:gsub('^/game_voice/', MODULE))) end
    local ok, err = pcall(function()
        init()
        eq(sent[1].a, 'hi')
        eq(sent[1].cl, 'web')
        eq(sent[1].eng, 'full', 'the full engine chosen')
        handlers[142](protocol, 142, json.encode(CFG))
        setWant(true)
        handlers[142](protocol, 142, json.encode(tokMsg()))
        local c = last('connect')
        assert(c, 'g_voice.connect called')
        eq(c[2], CFG.url)
        eq(c[3], TOK)
        eq(c[4], 'web')
        assert(last('setMode') and last('setPreset') and last('setPttMouse'), 'the engine settings sent')
        g_voice.onVoiceEvent('state', 'connecting', 0, 0)
        g_voice.onVoiceEvent('state', 'open', 0, 0)
        g_voice.onVoiceEvent('ctl', json.encode({ t = 'welcome', sid = 7, now = 1700000000, exp = 1700000300 }), 0, 0)
        eq(getSession().state, ST.ONLINE)
        local join = json.decode(last('sendControl')[2])
        eq(join.t, 'join')
        eq(join.room, 'p:10:5')
        g_voice.onVoiceEvent('ctl', json.encode({ t = 'roster', room = 'p:10:5', slot = 0,
            u = { { 7, 0, 1, ME, 0 }, { 8, 0, 2, 'Ana', 0 } } }), 0, 0)
        eq(getSession().rooms[0].count, 2)
        g_voice.onVoiceEvent('spk', '', 8, 1)
        eq(getSession().rooms[0].members[8].speaking, true, 'speaking edge')
        g_voice.onVoiceEvent('spk', '', 8, 0)
        eq(getSession().rooms[0].members[8].speaking, false)
        g_voice.onVoiceEvent('talk', '', 0, 0)
        eq(getSession().talkSlot, 0)
        g_voice.onVoiceEvent('talk', '', -1, 0)
        -- the two microphone notices reach the player's screen
        local shown = {}
        local realDisplay = modules.game_textmessage.displayGameMessage
        modules.game_textmessage.displayGameMessage = function(text) shown[#shown + 1] = text end
        g_voice.onVoiceEvent('mic', 'denied', 0, 0)
        g_voice.onVoiceEvent('mic', 'encoder', 0, 0)
        g_voice.onVoiceEvent('mic', 'ok', 0, 0)
        modules.game_textmessage.displayGameMessage = realDisplay
        eq(#shown, 2, 'one notice each for denied and encoder, none for ok')
        assert(shown[2]:find('encode') or shown[2]:find('codificar'), 'the encoder notice: ' .. tostring(shown[2]))
        g_voice.onVoiceEvent('devices', '', 0, 0)
        g_voice.onVoiceEvent('level', '', -30, 0)
        g_voice.onVoiceEvent('stats', '{}', 0, 0)
        -- push-to-talk goes to g_voice.setTransmit
        pressTalk(0)
        eq(last('setTransmit')[2], 0)
        releaseTalk()
        eq(last('setTransmit')[2], -1)
        -- the mic test on, then the relay restarts: the test ends in the
        -- engine too (the page does not end it on a relay close)
        toggleMicTest()
        eq(last('startLocalTest')[2], true, 'mic test on')
        -- the relay restarts: backoff, then a fresh token and one new connect
        local connects = count('connect')
        g_voice.onVoiceEvent('state', 'closed', 1012, 0)
        eq(getSession().state, ST.BACKOFF)
        eq(isTesting(), false)
        eq(last('startLocalTest')[2], false, 'the engine is told the mic test ended')
        runEvents(6000)
        handlers[142](protocol, 142, json.encode(tokMsg()))
        eq(count('connect'), connects + 1, 'one new connect after the backoff')
        -- game end: disconnect; a late closed of that socket changes nothing
        g_game.onGameEnd()
        assert(last('disconnect'), 'g_voice.disconnect called')
        g_voice.onVoiceEvent('state', 'closed', 1000, 0)
        eq(getSession().state, ST.OFF)
        terminate()
        eq(g_voice.onVoiceEvent, nil, 'disconnected from g_voice')
        eq(#errors, 0, 'errors: ' .. table.concat(errors, ' | '))
    end)
    dofile = realDofile
    g_voice = nil
    assert(ok, err)
end)

print(string.format('%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
