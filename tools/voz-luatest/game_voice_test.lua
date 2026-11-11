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

test('backoff steps stay within +-30%, capped at 15 s', function()
    local steps = { 1, 2, 4, 8, 15, 15, 15, 15, 15, 15, 15 }
    for n, step in ipairs(steps) do
        for _, r in ipairs({ 0, 0.25, 0.5, 0.75, 0.999999 }) do
            local d = S.backoffDelay(n, r)
            assert(d >= step * 700 and d <= step * 1300, string.format('n=%d r=%s d=%d', n, r, d))
        end
        eq(S.backoffDelay(n, 0.5), step * 1000, 'no jitter at r=0.5')
    end
    eq(S.backoffDelay(0, 0.5), 1000, 'n=0 counts as the first step')
    for n = 1, 100 do
        assert(S.backoffDelay(n, 0.999999) <= 19500, 'never past 15 s +30% (n=' .. n .. ')')
    end
    for _, r in ipairs({ 0, 0.5, 0.999999 }) do
        local d = S.failedDelay(r)
        assert(d >= 42000 and d <= 78000, 'the slow retry of FAILED: ' .. d)
    end
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

-- online, then a token that came while connecting (kept for the auth) and a
-- close before welcome: BACKOFF holding a fresh unused token
local function backoffWithToken()
    local w = online()
    w.s:onEngineState('closed', 4429)
    w.advance(w.timers.retry - w.t) -- the token of online() is used: asks one
    eq(w.s.state, ST.WAIT_TOKEN)
    w.s:onOpcode(tokMsg())
    eq(w.s.state, ST.CONNECTING)
    w.s:onOpcode(tokMsg()) -- kept, unused
    w.s:onEngineState('closed', 4429)
    eq(w.s.state, ST.BACKOFF)
    assert(w.s:freshToken(), 'a fresh unused token kept')
    return w
end

test('the retry reuses a fresh unused token, else asks', function()
    local w = backoffWithToken()
    local asked, connects = #w.sent142, #w.connects
    w.advance(w.timers.retry - w.t)
    eq(w.s.state, ST.CONNECTING, 'connected with the kept token')
    eq(#w.sent142, asked, 'no token request')
    eq(#w.connects, connects + 1)
    w.s:onEngineState('closed', 4429)
    w.advance(w.timers.retry - w.t)
    eq(w.s.state, ST.WAIT_TOKEN, 'the token is used: asks again')
    eq(w.last142().a, 'tok')
end)

test('a stale token is not reused', function()
    local w = backoffWithToken()
    local connects = #w.connects
    -- the retry comes only after the kept token aged
    w.timers.retry = nil
    w.advance(S.TOKEN_FRESH_MS + 1)
    w.s:onTimer('retry')
    eq(w.s.state, ST.WAIT_TOKEN)
    eq(w.last142().a, 'tok')
    eq(#w.connects, connects)
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

-- fails `n` times in a row from ONLINE: each retry asks a token and connects
local function failTimes(w, n)
    for i = 1, n do
        w.s:onEngineState('error', nil)
        if i < n then
            eq(w.s.state, w.s.failures >= S.MAX_FAILURES and ST.FAILED or ST.BACKOFF, 'failure ' .. i)
            w.advance(w.timers.retry - w.t)
            eq(w.s.state, ST.WAIT_TOKEN, 'retry ' .. i .. ' asks a token')
            w.s:onOpcode(tokMsg())
            eq(w.s.state, ST.CONNECTING, 'retry ' .. i)
        end
    end
end

test('failures in a row: failed after about 4 minutes, still retrying once a minute', function()
    local w = online()
    failTimes(w, S.MAX_FAILURES)
    eq(w.s.state, ST.FAILED)
    -- as long as the old 10 failures took (1+2+4+8+16+30+60*3 s = 241 s)
    assert(w.t >= 200000 and w.t <= 300000, 'FAILED after ' .. w.t / 1000 .. ' s')
    local wait = w.timers.retry - w.t
    assert(wait >= 42000 and wait <= 78000, 'the slow retry is armed: ' .. tostring(wait))
    eq(w.s.retryAt, w.timers.retry)
    local connects = #w.connects
    w.advance(wait)
    eq(w.s.state, ST.WAIT_TOKEN, 'tried again by itself')
    eq(w.last142().a, 'tok')
    w.s:onOpcode(tokMsg())
    eq(#w.connects, connects + 1)
    -- still down: FAILED again, and again a minute later
    w.s:onEngineState('error', nil)
    eq(w.s.state, ST.FAILED)
    assert(w.timers.retry, 'retry armed again')
    w.advance(w.timers.retry - w.t)
    eq(w.s.state, ST.WAIT_TOKEN)
    w.s:onOpcode(tokMsg())
    w.relay({ t = 'welcome', sid = 9 })
    eq(w.s.state, ST.ONLINE, 'back without a click')
    -- the button still works too
    local m = online()
    failTimes(m, S.MAX_FAILURES)
    assert(m.s:retryNow())
    eq(m.timers.retry, nil, 'the slow retry is replaced by the manual one')
    eq(m.s.state, ST.WAIT_TOKEN)
end)

test('a token from canary while waiting to retry: the retry is now', function()
    -- in BACKOFF
    local w = online()
    w.s:onEngineState('error', nil)
    eq(w.s.state, ST.BACKOFF)
    local connects = #w.connects
    w.s:onOpcode(tokMsg())
    eq(w.s.state, ST.CONNECTING, 'BACKOFF: connected at once')
    eq(#w.connects, connects + 1)
    eq(w.connects[#w.connects].tok, TOK)
    eq(w.timers.retry, nil, 'the backoff timer is gone')
    eq(w.s.retryAt, nil)
    -- in FAILED
    local f = online()
    failTimes(f, S.MAX_FAILURES)
    eq(f.s.state, ST.FAILED)
    connects = #f.connects
    f.s:onOpcode(tokMsg())
    eq(f.s.state, ST.CONNECTING, 'FAILED: connected at once')
    eq(#f.connects, connects + 1)
    eq(f.timers.retry, nil)
    f.relay({ t = 'welcome', sid = 9 })
    eq(f.s.state, ST.ONLINE)
    -- a malformed token changes nothing
    local b = online()
    b.s:onEngineState('error', nil)
    b.s:onOpcode({ a = 'tok', tok = 'short' })
    eq(b.s.state, ST.BACKOFF)
end)

test('cfg on from canary while waiting to retry: the retry is now, at its url', function()
    for _, failures in ipairs({ 1, S.MAX_FAILURES }) do
        local w = online()
        failTimes(w, failures)
        eq(w.s.state, failures == 1 and ST.BACKOFF or ST.FAILED)
        local before = #w.sent142
        w.s:onOpcode({ a = 'cfg', on = true, url = 'wss://voz2.mythosot.com.br/voz', psl = 50 })
        eq(w.s.state, ST.WAIT_TOKEN, 'tries at once: asks a token')
        eq(w.timers.retry, nil, 'not waiting for the backoff')
        eq(w.s.retryAt, nil)
        -- the request keeps canary's 3 s from the last one
        if w.timers.tokreq then
            w.advance(w.timers.tokreq - w.t)
        end
        eq(#w.sent142, before + 1)
        eq(w.last142().a, 'tok')
        w.s:onOpcode(tokMsg())
        eq(w.s.state, ST.CONNECTING)
        eq(w.connects[#w.connects].url, 'wss://voz2.mythosot.com.br/voz', 'the new address')
    end
end)

-- a relay outage of `downMs` while online: canary answers every token
-- request 100 ms later; a connect before the relay is up is refused 100 ms
-- later, one after it gets welcome. Returns how long after the relay came
-- back the session was online again (nil: never in 10 minutes), the world,
-- and the times of the token requests.
local function relayOutage(downMs, rand)
    local w = online()
    w.rand = rand
    local relayUp, pending, tokTimes = false, {}, {}
    w.s.io.send142 = function(t)
        w.sent142[#w.sent142 + 1] = t
        if t.a == 'tok' then
            tokTimes[#tokTimes + 1] = w.t
            pending[#pending + 1] = tokMsg()
        end
    end
    w.s.io.connect = function(url, tok)
        w.connects[#w.connects + 1] = { url = url, tok = tok }
        pending[#pending + 1] = relayUp and 'welcome' or 'refused'
    end
    w.s:onEngineState('error', nil) -- the relay goes down
    local upAt = w.t + downMs
    while w.t < upAt + 600000 do
        relayUp = w.t >= upAt
        local batch = pending
        pending = {}
        for _, p in ipairs(batch) do
            if p == 'welcome' then
                w.relay({ t = 'welcome', sid = 9 })
            elseif p == 'refused' then
                w.s:onEngineState('error', nil)
            else
                w.s:onOpcode(p)
            end
        end
        if relayUp and w.s.state == ST.ONLINE then
            return w.t - upAt, w, tokTimes
        end
        assert(w.s.state ~= ST.READY and w.s.state ~= ST.BLOCKED, 'gave up: ' .. w.s.state)
        w.advance(100)
    end
    return nil, w, tokTimes
end

test('a relay outage: back within 20 s, or a minute once FAILED, never only by hand', function()
    -- the play-test: a one-minute outage came back only 39.8 s after the relay
    for _, rand in ipairs({ 0, 0.5, 0.999999 }) do
        -- short of FAILED (at least 168 s of retries, at the fastest jitter)
        for _, downS in ipairs({ 10, 41, 62, 90, 120, 160 }) do
            local lag, w = relayOutage(downS * 1000, rand)
            assert(lag, string.format('down %d s, r=%s: never back (%s)', downS, rand, w.s.state))
            assert(lag <= 20000, string.format('down %d s, r=%s: back after %.1f s', downS, rand, lag / 1000))
        end
        for _, downS in ipairs({ 241, 300, 600 }) do
            local lag, w, tokTimes = relayOutage(downS * 1000, rand)
            assert(lag, string.format('down %d s, r=%s: never back (%s)', downS, rand, w.s.state))
            assert(lag <= 79000, string.format('down %d s, r=%s: back after %.1f s', downS, rand, lag / 1000))
            -- canary's token limits hold all along
            for i = 2, #tokTimes do
                assert(tokTimes[i] - tokTimes[i - 1] >= S.TOKEN_GAP_MS, 'token gap')
            end
            for i = S.TOKEN_BUDGET + 1, #tokTimes do
                assert(tokTimes[i] - tokTimes[i - S.TOKEN_BUDGET] >= S.TOKEN_WINDOW_MS, 'token budget')
            end
        end
    end
end)

test('the failure count resets after 30 s online', function()
    local w = online()
    w.s:onEngineState('error', nil)
    w.s:onEngineState('error', nil) -- ignored: in backoff
    eq(w.s.failures, 1)
    w.s:onOpcode(tokMsg()) -- connects at once
    eq(w.s.state, ST.CONNECTING)
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
    w.s:onOpcode(tokMsg()) -- a fresh token in the backoff: connects at once
    eq(w.s.state, ST.CONNECTING)
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

-- every English string the module shows: tr('...') and fmt('...') in the Lua
-- and the otui, and the English kept in tables or handed to a helper that
-- translates it
local function moduleStrings()
    local out, seen = {}, {}
    local function add(s)
        if not seen[s] then
            seen[s] = true
            out[#out + 1] = s
        end
    end
    for _, file in ipairs({ 'voice.lua', 'voice_ui.lua', 'voice_settings.lua', 'voice.otui', 'voicesettings.otui',
        'voiceonboard.otui' }) do
        local src = io.open(MODULE .. file):read('*a')
        for s in src:gmatch("[%W]tr%(%s*'([^']*)'") do
            add(s)
        end
        for s in src:gmatch("fmt%(%s*'([^']*)'") do
            add(s)
        end
        for s in src:gmatch("slider%([^,]+,[^,]+,%s*'([^']*)'") do
            add(s)
        end
        for block in src:gmatch('local %u+_?%u* = (%b{})') do
            for s in block:gmatch("= '([^']*)'") do
                add(s)
            end
            for s in block:gmatch(", '([^']*)' }") do
                add(s)
            end
        end
    end
    return out
end

-- the Portuguese the client shows: pt.lua, then the voice strings it lacks
-- (merged as voice.lua does). pt.lua runs in a box of its own: it calls
-- client_locales at its end.
local function portuguese()
    local env = setmetatable({}, { __index = _G })
    env.modules = setmetatable({}, { __index = function()
        return setmetatable({}, { __index = function() return function() end end })
    end })
    local chunk = assert(loadfile(ROOT .. '/data/locales/pt.lua'))
    setfenv(chunk, env)
    assert(pcall(chunk))
    local pt = {}
    for k, v in pairs(env.locale.translation) do
        pt[k] = v
    end
    for k, v in pairs(dofile(MODULE .. 'voice_locale.lua')) do
        if pt[k] == nil then
            pt[k] = v
        end
    end
    return pt
end

-- words spelled the same in Portuguese: the only strings whose text may stay
local SAME_IN_PT = { ['Spam'] = true, ['Normal'] = true, ['Volume: %d%%'] = true, ['Mouse 4'] = true,
    ['Mouse 5'] = true }

test('every string of the module has its Portuguese', function()
    local pt = dofile(MODULE .. 'voice_locale.lua')
    local missing = {}
    for _, s in ipairs(moduleStrings()) do
        if not pt[s] then
            missing[#missing + 1] = s
        end
    end
    for _, v in pairs(pt) do
        assert(not v:find('[\128-\255][\128-\191]'), 'UTF-8 left in a translation: ' .. v)
    end
    assert(#missing == 0, 'no Portuguese for: ' .. table.concat(missing, ' | '))
end)

test('no string of the module stays in English in Portuguese', function()
    local pt = portuguese()
    local same = {}
    for _, s in ipairs(moduleStrings()) do
        if pt[s] == s and not SAME_IN_PT[s] then
            same[#same + 1] = s
        end
    end
    assert(#same == 0, 'still English in Portuguese: ' .. table.concat(same, ' | '))
    -- the section headers the owner saw: "PARTY" read as English
    eq(pt['PARTY'], 'SUA PARTY')
    eq(pt['GUILD'], 'SUA GUILD')
    eq(pt['ROOMS'], 'SALAS')
    eq(pt['EVENTS'], 'EVENTOS')
    -- the word the client uses for a party: "party" (the bosses window's
    -- "Sua party", game_hunttasks, pt.lua's "Entrar na party do %s")
    for _, s in ipairs({ 'No party', 'Party room', 'In the party', 'Join the party room by itself' }) do
        assert(pt[s]:find('party'), s .. ': ' .. pt[s])
    end
    -- every unused entry is gone from the voice locale (a renamed key left behind)
    local used = {}
    for _, s in ipairs(moduleStrings()) do
        used[s] = true
    end
    local stale = {}
    for k in pairs(dofile(MODULE .. 'voice_locale.lua')) do
        if not used[k] then
            stale[#stale + 1] = k
        end
    end
    table.sort(stale)
    assert(#stale == 0, 'voice_locale.lua keys no file uses: ' .. table.concat(stale, ' | '))
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

test('push-to-talk keys: the key of an empty action bar button is free; a free key is offered', function()
    KeyShift, KeyControl, KeyCtrlCmd, KeyAltOpt, KeyMeta, KeyEscape = 22, 24, 21, 23, 25, 1
    CHAT_MODE = { ON = 1, OFF = 2 }
    KEY_CATEGORY = 'Voz'
    KEY_TALK = { [0] = 'Falar na party', [1] = 'Falar na guild', [2] = 'Falar na sala/evento' }
    local actions = {}
    Keybind = { currentPreset = 'Druid', hotkeys = { [1] = {}, [2] = {} },
        isKeyComboUsed = function(combo) return actions[combo] == true end }
    g_platform = { isBrowser = function() return false end }
    -- a new profile (the play-test): the bar has F1-F12 on its first twelve
    -- buttons, spells on F1-F8 only
    local hotkeys, mappings = {}, {}
    for i = 1, 12 do
        hotkeys[i] = { actionsetting = { action = 'TriggerActionButton_1.' .. i }, keysequence = 'F' .. i }
    end
    for i = 1, 8 do
        mappings['1.' .. i] = { actionBar = 1, actionButton = i,
            actionsetting = { chatText = 'exura vita', sendAutomatically = true } }
    end
    -- F9: no mapping at all; F10: emptied; F11: a multi action; F12: only a use type left
    mappings['1.10'] = { actionBar = 1, actionButton = 10, actionsetting = {} }
    mappings['1.11'] = { actionBar = 1, actionButton = 11,
        actionsetting = { multiActions = { {}, { useObject = 3155, useType = 'UseOnTarget' }, {} } } }
    mappings['1.12'] = { actionBar = 1, actionButton = 12, actionsetting = { useType = 'UseOnTarget', upgradeTier = 0 } }
    hotkeys[#hotkeys + 1] = { keysequence = 'Ctrl+F1' } -- a hotkey of the bar that is no button's
    hotkeys[#hotkeys + 1] = { actionsetting = { action = 'TriggerActionButton_2.1' }, keysequence = 'Ctrl+F2' }
    mappings['2.1'] = { actionBar = 2, actionButton = 1, actionsetting = { useObject = 0, chatText = '' } }
    modules = { game_actionbar = { ApiJson = { hasCurrentHotkeySet = function() return true end,
        getHotkeyEntries = function() return hotkeys end,
        getMapping = function(bar, button) return mappings[bar .. '.' .. button] end } } }
    dofile(MODULE .. 'voice_settings.lua')
    local taken = VoiceSettings.keyTaken
    for i = 1, 8 do
        assert(taken('F' .. i, 0, false), 'F' .. i .. ' casts a spell')
    end
    assert(not taken('F9', 0, false), 'F9: a button with nothing on it')
    assert(not taken('F10', 0, false), 'F10: an emptied button')
    assert(taken('F11', 0, false), 'F11: a multi action')
    assert(not taken('F12', 0, false), 'F12: only its use type left')
    assert(taken('Ctrl+F1', 0, false), 'a hotkey of the bar that is no button\'s')
    assert(not taken('Ctrl+F2', 0, false), 'an item 0 and an empty text are nothing')
    -- the key offered to a new player
    eq(VoiceSettings.freeKey(0), 'Insert')
    actions.Insert = true
    eq(VoiceSettings.freeKey(0), 'Pause', 'the next one when Insert is taken')
    actions.Pause = true
    eq(VoiceSettings.freeKey(0), nil, 'none left')
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
    Creature, LocalPlayer = {}, {}
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
        isKeyComboUsed = function() return false end,
        setPrimaryActionKey = function() end,
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
        eq(pt.translation['Mute microphone'], 'Desligar microfone', 'voice text added')
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

-- the panel, its popups and the onboarding over fake widgets ------------------

-- a widget with the few behaviours these tests look at: text and its width
-- (6 px a character), size, position, parent and children, anchors, and a
-- side panel that stacks its visible children from its top (the client's
-- UIMiniWindowContainer). Any other field is a child that does nothing
-- when called.
local Widget = {}
local WidgetMeta = {}
-- state of the fake itself, never a child
local WIDGET_STATE = { parent = true, tip = true, savedAt = true, dead = true, marginRight = true, checked = true,
    onValueChange = true, marginTop = true, onGeometryChange = true, baseMarginTop = true, marginLeft = true,
    opacity = true, cid = true, onKeyPress = true, onKeyDown = true }
WidgetMeta.__index = function(t, k)
    if Widget[k] then
        return Widget[k]
    end
    if WIDGET_STATE[k] then
        return nil
    end
    local c = Widget.new({ id = k })
    rawset(t, k, c)
    return c
end
WidgetMeta.__call = function() return nil end

function Widget.new(p)
    local w = setmetatable({ id = '', text = '', x = 0, y = 0, width = 100, height = 20, shown = true,
        kids = {}, anchors = {}, class = 'UIWidget', minHeight = 0, saved = 0 }, WidgetMeta)
    for k, v in pairs(p or {}) do
        rawset(w, k, v)
    end
    return w
end
function Widget:getId() return self.id end
function Widget:getClassName() return self.class end
function Widget:setText(t) self.text = tostring(t) end
function Widget:getText() return self.text end
function Widget:getTextSize() return { width = 6 * #self.text, height = 14 } end
function Widget:setTooltip(t) rawset(self, 'tip', t) end
function Widget:setVisible(v) self.shown = v and true or false end
function Widget:isVisible() return self.shown and (not self.parent or self.parent:isVisible()) end
function Widget:getWidth() return self.width end
function Widget:getHeight() return self.height end
function Widget:setHeight(h) self.height = h end
function Widget:getMinimumHeight() return self.minHeight end
function Widget:setPosition(p) self.x, self.y = p.x, p.y end
function Widget:getPosition() return { x = self.x, y = self.y } end
function Widget:getX() return self:getRect().x end
function Widget:getParent() return self.parent end
function Widget:getChildren() return self.kids end
function Widget:getChildById(id)
    for _, c in ipairs(self.kids) do
        if c.id == id then
            return c
        end
    end
    return rawget(self, id)
end
function Widget:recursiveGetChildById(id) return self:getChildById(id) or self[id] end
function Widget:getChildIndex(c)
    for i, k in ipairs(self.kids) do
        if k == c then
            return i
        end
    end
    return -1
end
function Widget:insertChild(i, c)
    assert(c.parent == nil, 'insertChild of a widget that has a parent')
    table.insert(self.kids, math.max(1, math.min(i, #self.kids + 1)), c)
    c.parent = self
end
function Widget:addChild(c) self:insertChild(#self.kids + 1, c) end
function Widget:removeChild(c)
    local i = self:getChildIndex(c)
    assert(i > 0, 'removeChild of a widget that is not a child')
    table.remove(self.kids, i)
    c.parent = nil
end
function Widget:destroyChildren() self.kids = {} end
function Widget:destroy() rawset(self, 'dead', true) end
function Widget:isDestroyed() return rawget(self, 'dead') == true end
function Widget:addAnchor(edge, id, hooked) self.anchors[edge] = { id, hooked } end
function Widget:setMarginRight(m) rawset(self, 'marginRight', m) end
function Widget:getMarginTop() return rawget(self, 'marginTop') or 0 end
function Widget:setMarginTop(m) rawset(self, 'marginTop', m) end
function Widget:getPaddingRect() return self:getRect() end
function Widget:getMarginLeft() return rawget(self, 'marginLeft') or 0 end
function Widget:setMarginLeft(m) rawset(self, 'marginLeft', m) end
function Widget:getOpacity() return rawget(self, 'opacity') or 1 end
function Widget:setOpacity(o) rawset(self, 'opacity', o) end
function Widget:saveChildren() self.saved = self.saved + 1 end
function Widget:saveParentPosition(id, pos) rawset(self, 'savedAt', { id = id, x = pos.x, y = pos.y }) end
-- a side panel stacks its visible children; anything else is where it was put
function Widget:getRect()
    local parent = self.parent
    if parent and parent.class == 'UIMiniWindowContainer' then
        local pr = parent:getRect()
        local y = pr.y
        for _, c in ipairs(parent.kids) do
            if c == self then
                break
            end
            if c.shown then
                y = y + c.height
            end
        end
        return { x = pr.x, y = y, width = pr.width, height = self.height }
    end
    return { x = self.x, y = self.y, width = self.width, height = self.height }
end
-- the client's fits(): the room left for a child at its minimum height, or -1
function Widget:fits(child, minHeight)
    local used = 0
    for _, c in ipairs(self.kids) do
        if c.shown then
            used = used + c.height
        end
    end
    local left = self.height - used
    return left >= minHeight and left or -1
end

-- a scroll bar as the client's UIScrollBar: a value clamped to its range, the
-- arrows move `incrementValue`, a click on the track calls onClickSlider
local function fakeSlider()
    local bar = Widget.new({ id = 'slider', class = 'UIScrollBar', x = 6, y = 26, width = 158, height = 10,
        value = 0, minimum = 0, maximum = 200, step = 10, incrementValue = 1 })
    local thumb = Widget.new({ id = 'sliderButton', width = 57, height = 8 })
    bar:addChild(thumb)
    function bar:getValue() return self.value end
    function bar:setValue(v)
        v = math.max(self.minimum, math.min(self.maximum, v))
        if v ~= self.value then
            self.value = v
            -- the thumb as the client places it: its share of the range
            thumb.x = self.x + 10 + math.floor((v - self.minimum) / (self.maximum - self.minimum) * (138 - 57))
            if self.onValueChange then
                self.onValueChange(self, v)
            end
        end
    end
    function bar:setIncrementStep(n) self.incrementValue = n end
    function bar:onClickSlider() end -- the stock jump, not modelled
    function bar:clickTrack() self:onClickSlider() end
    function bar:clickArrow(dir) self:setValue(self.value + dir * self.incrementValue) end
    return bar, thumb
end

-- the client globals voice_ui.lua and voice_settings.lua read, and a session
local function uiWorld(opts)
    opts = opts or {}
    local created = {}
    local root = Widget.new({ id = 'root', width = 1280, height = 720 })
    rootWidget = root
    local gameRoot = Widget.new({ id = 'gameRootPanel', width = 1280, height = 720 })
    root:addChild(gameRoot)
    local map = Widget.new({ id = 'gameMapPanel', x = 176, y = 20, width = 928, height = 500 })
    local function sidePanel(id, x, top, height)
        local panel = Widget.new({ id = id, class = 'UIMiniWindowContainer', x = x, y = top, width = 176,
            height = height })
        gameRoot:addChild(panel)
        return panel
    end
    -- 1280x720: the right panel under the minimap and inventory
    local right = sidePanel('gameRightPanel', 1104, opts.rightTop or 200, opts.rightHeight or 500)
    local left = sidePanel('gameLeftPanel', 0, 0, 720)
    local panels = { right, left }
    for _, h in ipairs(opts.rightWindows or { 200, 150, 150 }) do -- Battle List, Unjustified Points, VIP
        right:addChild(Widget.new({ class = 'UIMiniWindow', height = h }))
    end
    for _, h in ipairs(opts.leftWindows or { 720 }) do
        left:addChild(Widget.new({ class = 'UIMiniWindow', height = h }))
    end
    modules = {
        game_interface = {
            -- as gameinterface.lua: the selected panel, another with room, else the selected one
            findContentPanelAvailable = function(child, minHeight)
                if right:isVisible() and right:fits(child, minHeight) >= 0 then
                    return right
                end
                for _, panel in ipairs(panels) do
                    if panel ~= right and panel:isVisible() and panel:fits(child, minHeight) >= 0 then
                        return panel
                    end
                end
                return right
            end,
            getSelectedPanel = function() return right end,
            getRootPanel = function() return gameRoot end,
            getMapPanel = function() return map end,
        },
        client_topmenu = { addRightGameToggleButton = function() return Widget.new({ id = 'voiceButton' }) end },
        game_textmessage = { displayGameMessage = function() end },
    }
    g_ui = {
        loadUI = function()
            local w = Widget.new({ id = 'voiceWindow', class = 'UIMiniWindow', width = 176, height = 220,
                minHeight = 85 })
            -- as UIMiniWindow: no saved place puts it at the end of the right panel
            function w:setupOnStart()
                if opts.noParent then
                    return -- a saved index the panel could not take yet (scheduleInsert)
                end
                right:addChild(self)
            end
            function w:open()
                self.shown = true
                VoiceUI.onPanelOpen()
            end
            function w:close() self.shown = false end
            created.window = w
            return w
        end,
        createWidget = function(style, parent)
            local w
            if style == 'VoiceVolumePopup' then
                w = Widget.new({ id = style, width = 170, height = 66 })
                w.slider, w.thumb = fakeSlider()
                w:addChild(w.slider)
            elseif style == 'VoiceSectionHeader' then
                w = Widget.new({ id = style, width = 160, height = 18 })
            else
                w = Widget.new({ id = style })
            end
            created[style] = created[style] or {}
            table.insert(created[style], w)
            if parent then
                parent:addChild(w)
            end
            return w
        end,
        importStyle = function() end,
    }
    -- corelib's connect and disconnect: one slot or a list of them
    function connect(obj, slots)
        for k, v in pairs(slots) do
            local old = obj[k]
            obj[k] = old == nil and v or type(old) == 'table' and old or { old, v }
            if type(old) == 'table' then
                old[#old + 1] = v
            end
        end
    end
    function disconnect(obj, slots)
        for k, v in pairs(slots) do
            local old = obj[k]
            if old == v then
                obj[k] = nil
            elseif type(old) == 'table' then
                for i = #old, 1, -1 do
                    if old[i] == v then
                        table.remove(old, i)
                    end
                end
            end
        end
    end
    Creature, LocalPlayer = {}, {}
    local mouse = { x = 0, y = 0 }
    g_window = { getMousePosition = function() return mouse end, getDisplayDensity = function() return 1 end }
    g_clock = { millis = function() return events.now or 0 end }
    g_platform = { isBrowser = function() return opts.browser == true end, isMobile = function() return false end }
    g_game = { getLocalPlayer = function() return nil end }
    g_map = { getCreatureById = function() return nil end }
    tr = function(text, ...)
        local ok, out = pcall(string.format, text, ...)
        return ok and out or text
    end
    AnchorTop, AnchorBottom, AnchorLeft, AnchorRight, MouseRightButton, KeyEscape = 1, 2, 3, 4, 2, 1
    KeyShift, KeyControl, KeyCtrlCmd, KeyAltOpt, KeyMeta = 22, 24, 21, 23, 25
    CHAT_MODE = { ON = 1, OFF = 2 }
    KEY_CATEGORY = 'Voz'
    KEY_TALK = { [0] = 'Falar na party', [1] = 'Falar na guild', [2] = 'Falar na sala/evento' }
    local keys, used = {}, opts.usedKeys or {}
    Keybind = { chatMode = CHAT_MODE.OFF, currentPreset = 'Druid', hotkeys = { [1] = {}, [2] = {} },
        isKeyComboUsed = function(combo) return used[combo] == true end,
        setPrimaryActionKey = function(category, action, preset, combo, mode)
            keys[#keys + 1] = { action = action, combo = combo, mode = mode }
        end }
    determineKeyComboDesc = function(keyCode)
        return ({ [65] = 'A', [137] = 'F9', [6] = 'Insert' })[keyCode]
    end
    local w = opts.world or online()
    local prefs, set, wants = w.s.prefs, {}, {}
    getSession = function() return w.s end
    getPrefs = function() return prefs end
    getEngineName = function() return opts.engine or 'full' end
    hasAudio = function() return true end
    isTesting = function() return false end
    talkKey = function() return opts.talkKey or '' end
    setPref = function(k, v) prefs[k] = v set[#set + 1] = { k, v } end
    setWant = function(on) wants[#wants + 1] = on end
    applyEnginePrefs = function() end
    callEngine = function() end
    notify = function() end
    dofile(MODULE .. 'voice_ui.lua')
    dofile(MODULE .. 'voice_settings.lua')
    return { w = w, created = created, root = root, gameRoot = gameRoot, right = right, left = left, map = map,
        mouse = mouse, keys = keys, used = used, set = set, wants = wants }
end

local function inside(r, root)
    return r.x >= root.x and r.y >= root.y and r.x + r.width <= root.x + root.width and
        r.y + r.height <= root.y + root.height
end

test('the panel opens where it shows: a side panel with room, else on top, else over the map', function()
    -- 1280x720, Battle List, Unjustified Points and VIP fill the right panel,
    -- the left one is full too: the top of the right (selected) panel
    local u = uiWorld()
    VoiceUI.create()
    local win = u.created.window
    eq(win:getParent(), u.right, 'made at the end of the right panel')
    VoiceUI.toggle()
    assert(win:isVisible(), 'opened')
    eq(u.right:getChildIndex(win), 1, 'on top of the right panel, not under the screen')
    assert(u.right.saved > 0, 'the place is kept for the next login')
    runEvents(200)
    eq(win:getParent(), u.right, 'it shows there: stays')
    assert(inside(win:getRect(), u.root:getRect()), 'ends inside the screen')
    VoiceUI.toggle()
    assert(not win:isVisible(), 'closed again')
    VoiceUI.destroy()

    -- the left panel has room: it goes there
    u = uiWorld({ leftWindows = { 300 } })
    VoiceUI.create()
    win = u.created.window
    VoiceUI.toggle()
    eq(win:getParent(), u.left, 'a side panel with room')
    runEvents(200)
    assert(inside(win:getRect(), u.root:getRect()))
    VoiceUI.destroy()

    -- the right panel has room itself: nothing moves
    u = uiWorld({ rightWindows = { 200 } })
    VoiceUI.create()
    win = u.created.window
    VoiceUI.toggle()
    eq(win:getParent(), u.right)
    eq(u.right:getChildIndex(win), 2, 'stays at its place')
    VoiceUI.destroy()

    -- not in any panel yet (a saved index the panel could not take): the top
    u = uiWorld({ noParent = true })
    VoiceUI.create()
    win = u.created.window
    eq(win:getParent(), nil)
    VoiceUI.toggle()
    eq(u.right:getChildIndex(win), 1)
    VoiceUI.destroy()

    -- a screen so short the top of the panel still ends under it: over the map
    u = uiWorld({ rightTop = 600, rightHeight = 120, rightWindows = { 120 } })
    VoiceUI.create()
    win = u.created.window
    VoiceUI.toggle()
    runEvents(200)
    eq(win:getParent(), u.gameRoot, 'floats')
    assert(win:isVisible())
    assert(inside(win:getRect(), u.root:getRect()), 'inside the screen')
    assert(inside(win:getRect(), u.map:getRect()), 'over the map')
    eq(win.savedAt and win.savedAt.id, 'gameRootPanel', 'the floating place is kept')
    VoiceUI.toggle()
    VoiceUI.toggle()
    eq(win:getParent(), u.gameRoot, 'opened again where it floats')
    VoiceUI.destroy()
end)

test('the party header hint stops at its button, the key alone when narrow, whole in the tooltip', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8 } })
    local u = uiWorld({ world = w, talkKey = 'Insert' })
    VoiceUI.create()
    u.created.window.shown = true
    VoiceUI.refresh()
    local headers = u.created.VoiceSectionHeader
    assert(headers and #headers >= 2, 'party and rooms headers')
    local party = headers[1]
    eq(party.title.text, 'PARTY')
    eq(party.action.text, 'Leave')
    eq(party.hint.anchors[AnchorRight] and party.hint.anchors[AnchorRight][1], 'action',
        'the hint ends where the button starts')
    eq(party.tip, 'Hold Insert', 'the whole hint in the tooltip')
    -- the layout gives the hint 60 px: "Hold Insert" needs 66, the key alone 36
    party.hint.width = 60
    party.hint.onGeometryChange(party.hint)
    eq(party.hint.text, 'Insert', 'the key alone, never a cut "Hold In..."')
    -- room again: whole
    party.hint.width = 120
    party.hint.onGeometryChange(party.hint)
    eq(party.hint.text, 'Hold Insert')
    -- no room even for the key: nothing (the tooltip has it)
    party.hint.width = 30
    party.hint.onGeometryChange(party.hint)
    eq(party.hint.text, '')
    eq(party.tip, 'Hold Insert')
    -- no width at all (not laid out yet): the text is set once, not again
    -- on each geometry change (a label with no width takes its text's size)
    local sets = 0
    local setText = party.hint.setText
    party.hint.setText = function(self, t)
        sets = sets + 1
        setText(self, t)
    end
    party.hint.width = 0
    party.hint.onGeometryChange(party.hint)
    eq(party.hint.text, 'Hold Insert')
    party.hint.onGeometryChange(party.hint)
    party.hint.onGeometryChange(party.hint)
    eq(sets, 1, 'set once')
    -- the rooms header has its button too
    local rooms = headers[#headers]
    eq(rooms.title.text, 'ROOMS')
    eq(rooms.hint.anchors[AnchorRight] and rooms.hint.anchors[AnchorRight][1], 'action')
    VoiceUI.destroy()
    -- the otui: the hint does not grow with its text
    local otui = io.open(MODULE .. 'voice.otui'):read('*a')
    local block = otui:match('VoiceSectionHeader < UIWidget(.-)\nVoiceMemberIcon')
    local hint = block:match('id: hint(.-)VoiceSmallButton')
    assert(hint:find('text%-auto%-resize: false'), 'the hint has a fixed width')
    assert(hint:find('anchors%.right:'), 'the hint has a right edge')
end)

-- every text and tooltip of a fake widget and of the widgets under it
local function widgetTexts(roots)
    local out, seen = {}, {}
    local function walk(w)
        if type(w) ~= 'table' or seen[w] or getmetatable(w) ~= WidgetMeta then
            return
        end
        seen[w] = true
        for _, t in ipairs({ rawget(w, 'text'), rawget(w, 'tip'), rawget(w, 'caption') }) do
            if type(t) == 'string' and t ~= '' then
                out[#out + 1] = t
            end
        end
        for _, k in ipairs(rawget(w, 'kids') or {}) do
            walk(k)
        end
        for k, v in pairs(w) do
            if k ~= 'parent' then
                walk(v)
            end
        end
    end
    for _, r in ipairs(roots) do
        walk(r)
    end
    return out
end

test('the panel, its menus, the report and the settings in Portuguese: no English left', function()
    local pt = portuguese()
    -- the English the module shows whose Portuguese differs, as patterns:
    -- "Hold %s" also catches "Hold Insert"
    local english = {}
    for _, s in ipairs(moduleStrings()) do
        if pt[s] and pt[s] ~= s then
            local pat = s:gsub('[%^%$%(%)%.%[%]%*%+%-%?]', '%%%0'):gsub('%%(.)', function(c)
                return c == 'd' and '%d+' or c == 's' and '.+' or '%' .. c
            end)
            english[#english + 1] = { s, '^' .. pat .. '$' }
        end
    end
    local function englishIn(texts)
        local found = {}
        for _, t in ipairs(texts) do
            for line in (t .. '\n'):gmatch('([^\n]*)\n') do
                for _, e in ipairs(english) do
                    if line:find(e[2]) then
                        found[#found + 1] = line .. ' (' .. e[1] .. ')'
                    end
                end
            end
        end
        return found
    end
    -- party, guild and officers in the token; we are staff (the moderation
    -- entries), Ana has every flag
    local w = online(nil, { { id = 'p:10:5', k = 'party', l = 'Party' }, { id = 'g:7', k = 'guild' },
        { id = 'g:7:o', k = 'officers', l = 'Oficiais' } })
    roster(w, 'p:10:5', { { 7, 0, nil, nil, 16 }, { 8, 0, 4242, 'Ana', 1 + 2 + 4 + 16 + 64 } })
    local u = uiWorld({ world = w, talkKey = 'Insert' })
    tr = function(text, ...)
        local t = pt[text] or text
        local ok, out = pcall(string.format, t, ...)
        return ok and out or t
    end
    local menus = {}
    local createWidget = g_ui.createWidget
    g_ui.createWidget = function(style, parent)
        local widget = createWidget(style, parent)
        if style == 'PopupMenu' then
            local menu = { texts = {} }
            menus[#menus + 1] = menu
            function widget:addOption(text) menu.texts[#menu.texts + 1] = text end
        elseif style == 'VoiceReportWindow' then
            -- its text box is the child "text": the window's own text goes aside
            rawset(widget, 'text', Widget.new({ id = 'text' }))
            function widget:setText(t) rawset(self, 'caption', t) end
        elseif style == 'VoiceSettingsWindow' then
            for _, id in ipairs({ 'preset', 'inDevice', 'outDevice', 'mouse' }) do
                local combo = id == 'mouse' and widget.keys.mouse or widget.audio[id]
                function combo:addOption(text) menus[#menus + 1] = { texts = { text } } end
            end
        end
        return widget
    end
    local voiceButton
    modules.client_topmenu.addRightGameToggleButton = function(id, text)
        voiceButton = Widget.new({ id = id, tip = text })
        return voiceButton
    end
    VoiceUI.create()
    u.created.window.shown = true
    VoiceUI.refresh()
    -- connected: the state, not "Voz" again under the title "Voz"
    VoiceUI.onState()
    eq(u.created.window.statusText.text, 'Conectado', 'the status row')
    eq(voiceButton.tip, 'Voz: Conectado', 'the Voz button')
    -- the switches over the rooms and a member's row say the same thing:
    -- "Desligar microfone" / "Microfone desligado", "Desligar \225udio" /
    -- "\193udio desligado"
    for _, pair in ipairs({ { 'Mute microphone', 'Microphone off', 'microfone' },
        { 'Unmute microphone', 'Microphone off', 'microfone' }, { 'Deafen', 'Sound off', '\225udio' },
        { 'Undeafen', 'Sound off', '\225udio' } }) do
        local button, row = pt[pair[1]], pt[pair[2]]:gsub('^\193', '\225'):lower()
        assert(button:lower():find(pair[3], 1, true) and row:find(pair[3], 1, true),
            'the same word in "' .. button .. '" and "' .. pt[pair[2]] .. '"')
    end
    local headers = u.created.VoiceSectionHeader
    eq(headers[1].title.text, 'SUA PARTY')
    eq(headers[1].tip, 'Segure Insert')
    eq(headers[2].title.text, 'SUA GUILD')
    eq(headers[3].title.text, 'SALAS')
    -- the rooms unfolded, with a public room, an event and the echo test
    headers[3].action.onClick()
    w.relay({ t = 'dir', rooms = { { 'pub:geral', 'Geral', 12, 100, 50, 0 }, { 'ev:eventos', 'Eventos', 45, 300, 0, 1 } } })
    runEvents(50)
    local titles = {}
    for _, h in ipairs(u.created.VoiceSectionHeader) do
        titles[#titles + 1] = h.title.text
    end
    assert(table.concat(titles, ','):find('EVENTOS'), 'the events header: ' .. table.concat(titles, ','))
    -- the right-click menu, the volume popup, the report window, the settings
    VoiceUI.memberMenu('p:10:5', 8, { x = 10, y = 10 })
    VoiceUI.volumePopup('p:10:5', 8, { x = 10, y = 10 })
    VoiceUI.reportWindowFor('p:10:5', 8)
    local report = u.created.VoiceReportWindow[1]
    report.sendButton.onClick() -- no reason picked: a status line
    VoiceSettings.show()
    local roots = { u.created.window, voiceButton }
    for _, list in pairs(u.created) do
        if type(list) == 'table' and getmetatable(list) ~= WidgetMeta then
            for _, widget in ipairs(list) do
                roots[#roots + 1] = widget
            end
        end
    end
    local texts = widgetTexts(roots)
    for _, menu in ipairs(menus) do
        for _, t in ipairs(menu.texts) do
            texts[#texts + 1] = t
        end
    end
    assert(#texts > 30, 'texts seen: ' .. #texts)
    local found = englishIn(texts)
    assert(#found == 0, 'English in the Portuguese client: ' .. table.concat(found, ' | '))
    -- and the check itself sees English when tr does not translate
    eq(#englishIn({ 'PARTY', 'Hold Insert', 'Mute for me' }), 3)
    VoiceSettings.hide()
    VoiceUI.destroy()
end)

test('volume popup: 10% a click on the track or the arrows, 0% and 100% buttons', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8, 0, 4242, 'Ana' } })
    local u = uiWorld({ world = w })
    VoiceUI.volumePopup('p:10:5', 8, { x = 100, y = 100 })
    local popup = u.created.VoiceVolumePopup[1]
    local slider, thumb = popup.slider, popup.thumb
    eq(slider:getValue(), 100)
    -- the play-test: 12 clicks took it to 88%
    u.mouse.x = thumb:getX() - 5 -- left of the thumb
    slider:clickTrack()
    eq(slider:getValue(), 90, 'a click left of the thumb: 10% down')
    eq(S.userPref(w.s.prefs, 4242).v, 90, 'saved for the player')
    for _ = 1, 9 do
        u.mouse.x = thumb:getX() - 5
        slider:clickTrack()
    end
    eq(slider:getValue(), 0, '10 clicks from 100% to 0%')
    u.mouse.x = thumb:getX() + thumb:getWidth() + 5
    slider:clickTrack()
    eq(slider:getValue(), 10, 'right of the thumb: up')
    slider:setValue(88) -- a drag leaves it anywhere
    u.mouse.x = thumb:getX() - 5
    slider:clickTrack()
    eq(slider:getValue(), 80, 'back on the 10% grid')
    slider:clickArrow(1)
    eq(slider:getValue(), 90, 'an arrow: 10%')
    popup.zeroButton.onClick()
    eq(slider:getValue(), 0, '0% at once')
    eq(S.userPref(w.s.prefs, 4242).v, 0)
    local last = w.engineCalls[#w.engineCalls]
    eq(last[1], 'setUserVolume')
    eq(last[3], 0)
    popup.fullButton.onClick()
    eq(slider:getValue(), 100, '100% at once')
    eq(S.userPref(w.s.prefs, 4242), nil, 'back at the default: dropped')
    VoiceUI.destroy()
    -- the otui has the two buttons
    local otui = io.open(MODULE .. 'voice.otui'):read('*a')
    local block = otui:match('VoiceVolumePopup < UIWidget(.-)\nVoiceReportReason')
    assert(block:find('id: zeroButton') and block:find('id: fullButton'), 'the buttons in voice.otui')
end)

test('onboarding: a free key offered (Insert), the chat hint without F1-F12, Mouse 4 in the browser', function()
    local function onboardWorld(opts)
        local u = uiWorld(opts)
        local origCreate = g_ui.createWidget
        g_ui.createWidget = function(style, parent)
            local w = origCreate(style, parent)
            if style == 'VoiceOnboardWindow' then
                w.keyBox.grab = 0
                function w.keyBox:grabKeyboard() end
                function w.keyBox:ungrabKeyboard() end
                function w.keyBox:focus() end
                function w.mouseCheck:setChecked(v) self.checked = v end
                function w.mouseCheck:isChecked() return self.checked == true end
            end
            return w
        end
        VoiceSettings.showOnboarding()
        return u, u.created.VoiceOnboardWindow[1]
    end
    -- a new profile: Insert is offered and set when voice is turned on
    local u, win = onboardWorld()
    eq(win.keyBox.text, 'Insert', 'the box shows the free key')
    assert(win.keyHint.text:find('Insert'), 'the hint says it is a suggestion: ' .. win.keyHint.text)
    eq(win.mouseCheck.shown, false, 'no mouse option outside the browser')
    VoiceSettings.closeOnboarding(true)
    eq(#u.keys, 2, 'the party key, chat on and off')
    eq(u.keys[1].combo, 'Insert')
    eq(u.keys[1].action, 'Falar na party')
    eq(u.wants[1], true)
    -- "Not now": the suggestion is not taken
    u, win = onboardWorld()
    VoiceSettings.closeOnboarding(false)
    eq(#u.keys, 0, 'no key the player did not choose')
    -- Insert taken: Pause; a key already set: shown as it is, nothing offered
    u, win = onboardWorld({ usedKeys = { Insert = true } })
    eq(win.keyBox.text, 'Pause')
    VoiceSettings.closeOnboarding(true)
    u, win = onboardWorld({ talkKey = 'F8' })
    eq(win.keyBox.text, 'F8')
    eq(win.keyHint.text, '')
    VoiceSettings.closeOnboarding(true)
    eq(#u.keys, 0, 'the key the player had stays')
    -- the chat hint and the "taken" message point to a free key, not to F1-F12
    u, win = onboardWorld({ usedKeys = { F9 = true } })
    Keybind.chatMode = CHAT_MODE.ON
    win.keyBox.onClick()
    win.keyBox.onKeyDown(win.keyBox, 65, 0) -- A types in the chat
    assert(not win.keyStatus.text:find('F1%-F12'), 'no F1-F12 in: ' .. win.keyStatus.text)
    assert(win.keyStatus.text:find('Insert'), 'Insert in: ' .. win.keyStatus.text)
    win.keyBox.onClick()
    win.keyBox.onKeyDown(win.keyBox, 137, 0) -- F9 (KeyF9), taken
    eq(win.keyStatus.text, 'F9 is already used by another action. Try Insert.')
    eq(win.keyBox.text, 'Insert', 'the suggestion stays in the box')
    win.keyBox.onClick()
    win.keyBox.onKeyDown(win.keyBox, 6, 0) -- Insert picked by hand
    eq(win.keyHint.text, '', 'no longer a suggestion')
    VoiceSettings.closeOnboarding(false)
    eq(#u.keys, 2, 'a key the player picked is kept even with "Not now"')
    -- the browser with the full engine: Mouse 4 can be the push-to-talk
    u, win = onboardWorld({ browser = true })
    eq(win.mouseCheck.shown, true)
    win.mouseCheck:setChecked(true)
    VoiceSettings.closeOnboarding(true)
    local mouse
    for _, s in ipairs(u.set) do
        if s[1] == 'pttMouse' then
            mouse = s[2]
        end
    end
    eq(mouse, 3, 'Mouse 4 (the back button)')
    -- left unticked: a side button set before is not touched
    u, win = onboardWorld({ browser = true })
    getPrefs().pttMouse = 4
    VoiceSettings.closeOnboarding(true)
    eq(getPrefs().pttMouse, 4, 'Mouse 5 stays')
    u, win = onboardWorld({ browser = true, engine = 'lite' })
    eq(win.mouseCheck.shown, false, 'presence mode cannot talk')
    getPrefs().pttMouse = 3
    VoiceSettings.closeOnboarding(true)
    eq(getPrefs().pttMouse, 3, 'a box that did not show changes nothing')
end)

-- The client's keyboard for a key box: a key's down goes to the widget that
-- grabbed the keyboard, and its press follows at once (PlatformWindow::
-- processKeyDown) to that widget, or with nothing grabbed down the focus
-- chain: the focused box, then its window (UIWindow:onKeyPress: Escape
-- calls onEscape, Enter onEnter).
local function fakeKeyboard(window, box)
    local kb = { receiver = nil }
    function box:grabKeyboard() kb.receiver = self end
    function box:ungrabKeyboard()
        if kb.receiver == self then
            kb.receiver = nil
        end
    end
    function box:focus() end
    function kb.press(keyCode)
        local r = kb.receiver
        if r and r.onKeyDown then
            r.onKeyDown(r, keyCode, 0)
        end
        r = kb.receiver
        if r then
            if r.onKeyPress then
                r.onKeyPress(r, keyCode, 0, 0)
            end
            return
        end
        if box.onKeyPress and box.onKeyPress(box, keyCode, 0, 0) then
            return
        end
        if keyCode == KeyEscape and window.onEscape then
            window.onEscape(window)
        elseif keyCode == KeyEnter and window.onEnter then
            window.onEnter(window)
        end
    end
    return kb
end

test('Escape during a key capture only cancels it: the window stays, the onboarding is not over', function()
    KeyEnter = 5
    -- the onboarding: its Escape is "Not now"
    local u = uiWorld()
    local createWidget = g_ui.createWidget
    local kb
    g_ui.createWidget = function(style, parent)
        local w = createWidget(style, parent)
        if style == 'VoiceOnboardWindow' then
            kb = fakeKeyboard(w, w.keyBox)
            w.onEscape = function() VoiceSettings.closeOnboarding(false) end
        elseif style == 'VoiceSettingsWindow' then
            local box = w.keys.keyParty.value
            kb = fakeKeyboard(w, box)
            w.onEscape = function() VoiceSettings.hide() end
        end
        return w
    end
    VoiceSettings.showOnboarding()
    local win = u.created.VoiceOnboardWindow[1]
    win.keyBox.onClick()
    eq(kb.receiver, win.keyBox, 'the box has the keyboard')
    kb.press(KeyEscape)
    eq(kb.receiver, nil, 'the keyboard let go after the press')
    eq(win.keyBox.text, 'Insert', 'the capture cancelled: the suggestion again')
    eq(win:isDestroyed(), false, 'the onboarding stays')
    for _, set in ipairs(u.set) do
        assert(set[1] ~= 'onboarded', 'the onboarding is not over')
    end
    -- a key picked, then Escape with nothing captured: "Not now"
    win.keyBox.onClick()
    kb.press(6) -- Insert
    eq(kb.receiver, nil)
    eq(win.keyBox.text, 'Insert')
    kb.press(KeyEscape)
    local over = false
    for _, set in ipairs(u.set) do
        over = over or set[1] == 'onboarded'
    end
    assert(over, 'Escape outside a capture still closes it')
    -- the settings window: Escape and Enter while capturing close nothing
    u = uiWorld({ talkKey = 'F8' })
    createWidget = g_ui.createWidget
    g_ui.createWidget = function(style, parent)
        local w = createWidget(style, parent)
        if style == 'VoiceSettingsWindow' then
            kb = fakeKeyboard(w, w.keys.keyParty.value)
            w.onEscape = function() VoiceSettings.hide() end
            w.onEnter = function() VoiceSettings.hide() end
        end
        return w
    end
    VoiceSettings.show()
    local settings = u.created.VoiceSettingsWindow[1]
    local row = settings.keys.keyParty
    row.change.onClick()
    kb.press(KeyEscape)
    eq(settings:isDestroyed(), false, 'Escape: the settings window stays')
    eq(row.value.text, 'F8', 'the key unchanged')
    row.change.onClick()
    kb.press(KeyEnter)
    eq(settings:isDestroyed(), false, 'Enter: the settings window stays')
    -- a press that never comes: the keyboard is let go on the next frame
    row.change.onClick()
    row.value.onKeyDown(row.value, KeyEscape, 0)
    eq(kb.receiver, row.value)
    runEvents(16)
    eq(kb.receiver, nil, 'let go a frame later')
    eq(row.value.onKeyPress, nil)
    -- outside a capture Escape closes it, as before
    kb.press(KeyEscape)
    eq(settings:isDestroyed(), true, 'Escape outside a capture closes the window')
end)

-- a bitmap font's glyph widths as the client works them out
-- (BitmapFont::calculateGlyphsWidthsAutomatically): the rightmost column
-- with a pixel in the glyph's cell over the font's height (the whole cell
-- when empty), space-width for the space. The PNG goes through zlib with
-- LuaJIT's ffi; with no zlib the measuring tests say SKIP.
local zlib
do
    local okFfi, ffi = pcall(require, 'ffi')
    if okFfi then
        pcall(ffi.cdef, 'int uncompress(uint8_t *dest, unsigned long *destLen, const char *source, unsigned long sourceLen);')
        for _, name in ipairs({ 'z', 'libz.so.1', 'zlib1', 'zlib' }) do
            local okLib, lib = pcall(ffi.load, name)
            if okLib then
                zlib = { ffi = ffi, lib = lib }
                break
            end
        end
    end
end

-- an 8-bit RGBA PNG: width, height and its pixels (an ffi byte array)
local function readPng(path)
    local f = assert(io.open(path, 'rb'))
    local data = f:read('*a')
    f:close()
    assert(data:sub(1, 8) == '\137PNG\r\n\26\n', path .. ' is not a PNG')
    local function u32(i)
        local a, b, c, d = data:byte(i, i + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    local pos, w, h, idat = 9, nil, nil, {}
    while pos <= #data do
        local len, kind = u32(pos), data:sub(pos + 4, pos + 7)
        if kind == 'IHDR' then
            w, h = u32(pos + 8), u32(pos + 12)
            assert(data:byte(pos + 16) == 8 and data:byte(pos + 17) == 6 and data:byte(pos + 20) == 0,
                path .. ': 8-bit RGBA, not interlaced')
        elseif kind == 'IDAT' then
            idat[#idat + 1] = data:sub(pos + 8, pos + 7 + len)
        elseif kind == 'IEND' then
            break
        end
        pos = pos + 12 + len
    end
    local ffi, src, stride = zlib.ffi, table.concat(idat), w * 4
    local size = h * (stride + 1)
    local raw, n = ffi.new('uint8_t[?]', size), ffi.new('unsigned long[1]', size)
    assert(zlib.lib.uncompress(raw, n, src, #src) == 0 and n[0] == size, path .. ': inflate')
    local px = ffi.new('uint8_t[?]', h * stride)
    for y = 0, h - 1 do
        local filter, from, to = raw[y * (stride + 1)], y * (stride + 1) + 1, y * stride
        for x = 0, stride - 1 do
            local v = raw[from + x]
            local a = x >= 4 and px[to + x - 4] or 0
            local b = y > 0 and px[to - stride + x] or 0
            local c = (x >= 4 and y > 0) and px[to - stride + x - 4] or 0
            if filter == 1 then
                v = v + a
            elseif filter == 2 then
                v = v + b
            elseif filter == 3 then
                v = v + math.floor((a + b) / 2)
            elseif filter == 4 then
                local p = a + b - c
                local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
                v = v + ((pa <= pb and pa <= pc) and a or (pb <= pc and b or c))
            end
            px[to + x] = v % 256
        end
    end
    return w, h, px
end

local fonts = {}
-- the width of a Latin-1 text in a font of data/fonts/otfont, as the client draws it
local function textWidth(font, text)
    local glyphs = fonts[font]
    if not glyphs then
        local f = assert(io.open(ROOT .. '/data/fonts/otfont/' .. font .. '.otfont'))
        local def = f:read('*a')
        f:close()
        local texture = def:match('texture: ([^\r\n]+)')
        local height = tonumber(def:match('height: (%d+)'))
        local gw, gh = def:match('glyph%-size: (%d+) (%d+)')
        gw, gh = tonumber(gw), tonumber(gh)
        local first = tonumber(def:match('first%-glyph: (%d+)')) or 32
        local spacing = tonumber(def:match('\n%s*spacing: (%d+)')) or 0
        local w, h, px = readPng(ROOT .. '/data/fonts/otfont/' .. texture .. '.png')
        local cols = math.floor(w / gw)
        glyphs = { spacing = spacing }
        for g = first, 255 do
            local x0, y0 = ((g - first) % cols) * gw, math.floor((g - first) / cols) * gh
            local width = gw
            for x = 0, gw - 1 do
                for y = y0, math.min(y0 + height, h) - 1 do
                    if px[(y * w + x0 + x) * 4 + 3] ~= 0 then
                        width = x + 1
                        break
                    end
                end
            end
            glyphs[g] = width
        end
        glyphs[32] = tonumber(def:match('space%-width: (%d+)')) or gw
        glyphs[127] = 1
        fonts[font] = glyphs
    end
    local total = 0
    for i = 1, #text do
        total = total + (glyphs[text:byte(i)] or 0) + glyphs.spacing
    end
    return total
end

local REGULAR, BOLD = 'verdana-11px-antialised', 'Verdana Bold-11px'

test('the font measure agrees with the client', function()
    if not zlib then
        print('SKIP the font measure: no zlib for LuaJIT ffi')
        return
    end
    -- widths seen in the client (AGENTS.md: rightmost filled column + 1)
    eq(textWidth(REGULAR, 'Insert'), 36, 'Insert')
    eq(textWidth(REGULAR, 'Na sala / evento'), 99, 'Na sala / evento')
    eq(textWidth(REGULAR, 'Aperte uma tecla...'), 111, 'Aperte uma tecla...')
    eq(textWidth(BOLD, 'SUA PARTY'), 72, 'SUA PARTY')
    assert(textWidth(REGULAR, '\193') < 16, 'the font has an A with acute (an empty cell is 16 wide)')
end)

test('the Portuguese texts fit their boxes: the key rows, the onboarding key box, the party header', function()
    if not zlib then
        print('SKIP the Portuguese texts fit: no zlib for LuaJIT ffi')
        return
    end
    local pt = portuguese()
    local function read(file)
        local f = assert(io.open(file))
        local text = f:read('*a')
        f:close()
        return text
    end
    local settings = read(MODULE .. 'voicesettings.otui')
    local voice = read(MODULE .. 'voice.otui')
    local styles = read(ROOT .. '/data/styles/50-breves.otui')
    local function num(text, pattern, what)
        return assert(tonumber(text:match(pattern)), 'no ' .. what .. ' in the otui')
    end
    local row = settings:match('VoiceKeyRow < UIWidget(.-)\nVoiceSettingsWindow')
    local labelWidth = num(row, 'id: label.-width: (%d+)', 'key label width')
    local boxGap = num(row, 'id: value.-margin%-left: (%d+)', 'key box margin') +
        num(row, 'id: value.-margin%-right: (%d+)', 'key box margin')
    local keysWidth = num(settings, 'id: keys.-width: (%d+)', 'keys column width')
    local audioWidth = num(settings, 'id: audio.-width: (%d+)', 'audio column width')
    local windowWidth = num(settings, 'VoiceSettingsWindow < MythosWindow.-size: (%d+) %d+', 'window size')
    local mythos = styles:match('MythosWindow < MainWindow(.-)\n%S')
    local content = windowWidth - num(mythos, 'padding%-left: (%d+)', 'padding') -
        num(mythos, 'padding%-right: (%d+)', 'padding')
    assert(audioWidth + keysWidth + 8 <= content, 'the two columns fit the window with a gap')
    -- the change button: "Trocar" and its padding (VoiceSmallButton, text-auto-resize)
    local small = voice:match('VoiceSmallButton < UIButton(.-)\n%S')
    local pr, pl = small:match('padding: %d+ (%d+) %d+ (%d+)')
    local function button(text)
        return textWidth(REGULAR, text) + tonumber(pl) + tonumber(pr)
    end
    local box = keysWidth - labelWidth - boxGap - button(pt['Change'])
    -- the text is centred and cut to the box's rect on both sides
    for _, text in ipairs({ pt['Press a key...'], 'Ctrl+Shift+Insert', 'Ctrl+Shift+PageDown', 'Alt+Shift+Insert',
        'Ctrl+PageDown', 'Shift+Pause' }) do
        local tw = textWidth(REGULAR, text)
        assert(tw <= box, string.format('"%s" (%d px) in the %d px key box', text, tw, box))
    end
    for _, key in ipairs({ 'In the party', 'In the guild', 'In a room / event' }) do
        local tw = textWidth(REGULAR, pt[key])
        assert(tw <= labelWidth, string.format('"%s" (%d px) in the %d px label', pt[key], tw, labelWidth))
    end
    -- the check boxes of the keys column (text after the box: text-offset 18)
    for _, key in ipairs({ 'Join the party room by itself', 'Join the guild room by itself',
        'Show an icon over who is talking', 'Lower the game sounds while someone talks',
        'Push to talk with the game in the background' }) do
        local tw = textWidth(REGULAR, pt[key]) + 18
        assert(tw <= keysWidth, string.format('"%s" (%d px) in the %d px column', pt[key], tw, keysWidth))
    end
    -- the onboarding key box (bold)
    local onboard = read(MODULE .. 'voiceonboard.otui')
    local keyBox = num(onboard, 'id: keyBox.-size: (%d+) %d+', 'onboarding key box')
    for _, text in ipairs({ pt['Press a key...'], 'Ctrl+Shift+Insert', pt['Click here'] }) do
        local tw = textWidth(BOLD, text)
        assert(tw <= keyBox, string.format('"%s" (%d px) in the %d px onboarding box', text, tw, keyBox))
    end
    -- the party header at the side panel's content width (150 px in a 176 px
    -- panel): the title, the key alone and "Sair" side by side. An edge
    -- anchored to another shares its last pixel (Rect::right is x + width - 1),
    -- so the hint gets 2 px more than the sum: 37 px in the client for
    -- "SUA PARTY" and "Sair", read from the live panel
    local header = voice:match('VoiceSectionHeader < UIWidget(.-)\nVoiceMemberIcon')
    local hintGap = num(header:match('id: hint(.-)VoiceSmallButton'), 'margin%-left: (%d+)', 'hint margin')
    for _, title in ipairs({ 'PARTY', 'GUILD' }) do
        local room = 150 - textWidth(BOLD, pt[title]) - hintGap - 4 - button(pt['Leave']) + 2
        local tw = textWidth(REGULAR, 'Insert')
        assert(tw <= room, string.format('%s, Insert (%d px) and %s: %d px of room', pt[title], tw, pt['Leave'], room))
    end
end)

test('a member row says its icons in words: staff, microphone off, sound off', function()
    local w = online()
    roster(w, 'p:10:5', { { 7 }, { 8, 0, 4242, 'Ana', 1 + 2 + 16 }, { 9, 0, 4243, 'Bia' } })
    local u = uiWorld({ world = w })
    VoiceUI.create()
    u.created.window.shown = true
    VoiceUI.refresh()
    local tips = {}
    for _, row in ipairs(u.created.VoiceMemberRow or {}) do
        tips[row.name.text] = row.tip
    end
    eq(tips.Ana, 'Ana\nStaff member\nMicrophone off\nSound off')
    eq(tips.Bia, 'Bia', 'no flags: the name alone')
    VoiceUI.destroy()
end)

-- The map as the engine draws it, over the fake map widget: W x H visible
-- tiles of T screen px in a rect centred in the padding rect (letterboxed
-- when the window has another shape), the camera in the middle tile.
-- UIMap:getPosition answers only inside that rect, UIMap:isInRange as the
-- names do (the camera's floor, inside the view). Each frame the engine
-- places an attached widget at its creature's point plus the widget's
-- margins and calls onGeometryChange when that moved it: the point is a
-- quarter tile right of the tile's left and 10/32 of a tile above its top,
-- a floor of difference moves it a tile down-right (below) or up-left
-- (above), and a creature with no position is not placed at all. The ring
-- of tiles around the view (column or row -1, W, H) is placed, never seen.
local function fire(object, name, ...)
    local slot = object[name]
    if type(slot) == 'function' then
        slot(...)
    elseif type(slot) == 'table' then
        for _, fn in ipairs(slot) do
            fn(...)
        end
    end
end

local function engineMap(u)
    local m = { camera = { x = 100, y = 100, z = 7 } }
    function m:layout(x, y, width, height, W, H, T)
        u.map.x, u.map.y, u.map.width, u.map.height = x, y, width, height
        self.W, self.H, self.T = W, H, T
        local w, h = math.min(width, W * T), math.min(height, H * T)
        self.rect = { x = x + math.floor((width - w) / 2), y = y + math.floor((height - h) / 2), width = w, height = h }
    end
    function u.map:getCameraPosition() return m.camera end
    function u.map:getVisibleDimension() return { width = m.W, height = m.H } end
    function u.map:getPosition(p)
        local r = m.rect
        if p.x < r.x or p.y < r.y or p.x >= r.x + r.width or p.y >= r.y + r.height then
            return nil
        end
        return { x = m.camera.x - (m.W - 1) / 2 + math.floor((p.x - r.x) / m.T),
            y = m.camera.y - (m.H - 1) / 2 + math.floor((p.y - r.y) / m.T), z = m.camera.z }
    end
    function u.map:isInRange(pos)
        return pos.z == m.camera.z and math.abs(pos.x - m.camera.x) <= (m.W - 1) / 2 and
            math.abs(pos.y - m.camera.y) <= (m.H - 1) / 2
    end
    -- the tile's top left and the point of a creature at pos
    function m:tile(pos)
        local dz = self.camera.z - pos.z
        local col = pos.x - self.camera.x + (self.W - 1) / 2 - dz
        local row = pos.y - self.camera.y + (self.H - 1) / 2 - dz
        return self.rect.x + col * self.T, self.rect.y + row * self.T
    end
    function m:point(pos)
        local tx, ty = self:tile(pos)
        return tx + math.floor(self.T / 4), ty - math.floor(10 * self.T / 32 + 0.5)
    end
    -- the position at a row and column of the view (0 is the top left tile)
    function m:at(row, col, z)
        return { x = self.camera.x - (self.W - 1) / 2 + col, y = self.camera.y - (self.H - 1) / 2 + row, z = z or 7 }
    end
    return m
end

test('the over-head icon: drawn with the speaker, over the name, under the feet in the top rows, none outside the view', function()
    local u = uiWorld()
    local density = 1
    g_window.getDisplayDensity = function() return density end
    -- the engine's attached effects: one registration, a copy each time
    local registered, registrationErrors = {}, 0
    g_attachedEffects = {
        registerByImage = function(id, name, path, smooth)
            if registered[id] then
                registrationErrors = registrationErrors + 1 -- the client logs an error
                return nil
            end
            registered[id] = { path = path, smooth = smooth }
            return {}
        end,
        getById = function(id)
            if not registered[id] then
                return nil
            end
            local e = { id = id }
            function e:setOffset(x, y) self.ox, self.oy = x, y end
            function e:setOnTop(v) self.onTop = v end
            function e:setFollowOwner(v) self.follow = v end
            function e:setDrawOrder(v) self.order = v end
            return e
        end,
    }
    g_things = { getThingType = function() return { getDisplacementX = function() return 8 end,
        getDisplacementY = function() return 8 end } end }
    g_game.getFeature = function() return false end
    ThingCategoryCreature, GameNegativeOffset = 1, 116
    VoiceHeadEffectRegistered = nil
    VoiceUI.create()
    local m = engineMap(u)
    -- 1280x720 in the browser: 29x15 tiles of 32 px in the 928x500 map,
    -- 10 px of bar above and under them
    m:layout(176, 20, 928, 500, 29, 15, 32)
    local function newCreature(id)
        local c = { id = id, effects = {}, dead = false }
        function c:getId() return self.id end
        function c:isLocalPlayer() return false end
        function c:isDead() return self.dead end
        function c:getPosition() return self.pos end
        function c:getOutfit() return { type = 128 } end
        function c:attachEffect(e) self.effects[#self.effects + 1] = e end
        function c:detachEffect(e)
            for i, x in ipairs(self.effects) do
                if x == e then
                    table.remove(self.effects, i)
                    return true
                end
            end
            return false
        end
        return c
    end
    local creature = newCreature(5)
    creature.pos = m:at(7, 14)
    local me = newCreature(1)
    function me:isLocalPlayer() return true end
    local known = { [5] = creature }
    g_map = { getCreatureById = function(cid) return known[cid] end }
    VoiceUI.attachHead('k', 5)
    eq(#creature.effects, 1, 'the icon is drawn with the creature')
    local effect = creature.effects[1]
    eq(registered[effect.id].path, '/game_voice/images/speaker_head')
    assert(effect.onTop and effect.follow and effect.order == 4, 'over the creature, following its jumps, over walls')
    -- where the engine draws it: the creature's tile, minus the offsets in
    -- sprite px (the map scales them); the name is centred on the point
    -- and ends there, its letters start about 5 px lower
    local function icon()
        local e = creature.effects[1]
        if not e then
            return nil
        end
        local S = m.T / 32
        local tx, ty = m:tile(creature.pos)
        return { x = tx - e.ox * S, y = ty - e.oy * S, w = 18 * S, h = 16 * S, S = S, tx = tx, ty = ty }
    end
    local function frame()
        runEvents(16)
    end
    local function move(row, col, z)
        local old = creature.pos
        creature.pos = m:at(row, col or 14, z)
        fire(Creature, 'onPositionChange', creature, creature.pos, old)
        frame()
        return icon()
    end
    local function checkAbove(r, what)
        assert(r, what .. ': drawn')
        local px, py = m:point(creature.pos)
        assert(math.abs(r.x + r.w / 2 - px) <= 1, what .. ': centred over the name (' .. (r.x + r.w / 2) .. ' / ' .. px .. ')')
        local bottom = r.y + r.h
        assert(bottom <= py - 9 + r.S and bottom >= py - 9 - r.S, what .. ': just above the name (' .. bottom .. ', point ' .. py .. ')')
        assert(r.y >= m.rect.y, what .. ': inside the drawn map')
    end
    local function checkUnder(r, what)
        assert(r, what .. ': drawn')
        local feet = r.ty + 24 * r.S -- an outfit drawn 8 sprite px above its tile's bottom
        assert(r.y >= feet and r.y <= feet + 2 + r.S, what .. ': under the feet (' .. r.y .. ', feet ' .. feet .. ')')
        assert(r.y >= m.rect.y, what .. ': inside the drawn map')
    end
    checkAbove(icon(), 'the middle')
    -- third row: room above the name; second and first: under the feet
    checkAbove(move(2), 'third row')
    checkUnder(move(1), 'second row')
    checkUnder(move(0), 'first row')
    -- the row the client keeps above the visible map: not drawn, no icon
    eq(move(-1), nil, 'the hidden row above')
    checkAbove(move(3), 'fourth row')
    -- the hidden columns and the hidden row under the map
    eq(move(3, -1), nil, 'the hidden column on the left')
    eq(move(3, 29), nil, 'the hidden column on the right')
    checkAbove(move(3, 28), 'the last column')
    eq(move(15), nil, 'the hidden row under the map')
    checkAbove(move(14), 'the last row')
    -- another floor: no name there, no icon (the engine would draw it over
    -- the creature seen through a hole, a tile off the name's place)
    eq(move(5, 14, 8), nil, 'a floor below')
    eq(move(5, 14, 6), nil, 'a floor above')
    checkAbove(move(5, 14, 7), 'the camera\'s floor')
    eq(#creature.effects, 1, 'one icon, never two')
    -- the camera changes floor and the speaker does not move: our move checks
    m.camera = { x = 101, y = 101, z = 6 }
    fire(LocalPlayer, 'onPositionChange', me, m.camera, { x = 100, y = 100, z = 7 })
    frame()
    eq(icon(), nil, 'the speaker is a floor under the camera now')
    m.camera = { x = 100, y = 100, z = 7 }
    fire(LocalPlayer, 'onPositionChange', me, m.camera, { x = 101, y = 101, z = 6 })
    frame()
    checkAbove(icon(), 'the same floor again')
    -- the speaker leaves in mid-sentence: the engine calls onDisappear and
    -- then drops the position; it comes back as a new creature object
    fire(Creature, 'onDisappear', creature)
    local old = creature
    old.pos = nil
    frame()
    eq(#old.effects, 0, 'gone: no icon')
    creature = newCreature(5)
    creature.pos = m:at(6, 10)
    known[5] = creature
    fire(Creature, 'onAppear', creature)
    frame()
    checkAbove(icon(), 'back in view, on the new creature')
    -- dead in mid-sentence: no icon over the corpse
    creature.dead = true
    fire(Creature, 'onDeath', creature)
    frame()
    eq(icon(), nil, 'dead')
    creature.dead = false
    fire(Creature, 'onAppear', creature)
    frame()
    checkAbove(icon(), 'alive again')
    -- made anew within one frame (dropped from the known creatures and back)
    local older = creature
    creature = newCreature(5)
    creature.pos = m:at(6, 10)
    known[5] = creature
    fire(Creature, 'onDisappear', older)
    fire(Creature, 'onAppear', creature)
    frame()
    eq(#older.effects, 0, 'not left on the old object')
    checkAbove(icon(), 'on the new object in the same frame')
    -- other creatures walking schedule nothing
    local pending = #events
    local other = newCreature(9)
    fire(Creature, 'onPositionChange', other, m:at(3, 3), m:at(3, 4))
    eq(#events, pending, 'a creature that is not talking: nothing')

    -- the classic view in a window of another shape: 15x11 tiles of 44 px
    -- in 660x524, letterboxed 20 px above and under. On the second row the
    -- icon above the name would start in the bar, under the padding rect's
    -- top but over the drawn map's: under the feet
    m:layout(176, 20, 660, 524, 15, 11, 44)
    eq(m.rect.y, 40, 'the drawn rect')
    local _, ty = m:tile(m:at(1, 7))
    local aboveTop = ty - (16 + 8 + 2 + 9 / (44 / 32)) * 44 / 32
    assert(aboveTop >= 20 and aboveTop < 40, 'the case: above would be in the bar (' .. aboveTop .. ')')
    checkUnder(move(1, 7), 'second row in the classic view')
    checkAbove(move(2, 7), 'third row in the classic view')
    -- a big window on the desktop: 15x11 tiles of 77 px (2.4 times)
    m:layout(0, 0, 1155, 847, 15, 11, 77)
    checkUnder(move(0, 7), 'first row at 77 px a tile')
    checkAbove(move(1, 7), 'second row at 77 px a tile')
    checkAbove(move(5, 7), 'the middle at 77 px a tile')
    -- the fill view cuts the edge tiles: 21x11 tiles of 64 px in 1300x704
    m:layout(0, 0, 1300, 704, 21, 11, 64)
    eq(m.rect.width, 1300, 'the fill view draws the whole width')
    checkUnder(move(0, 10), 'the fill view, first row')
    checkAbove(move(4, 10), 'the fill view')
    -- no camera yet: the 32 px offsets, still centred over the name
    m:layout(176, 20, 928, 500, 29, 15, 32)
    local getPosition = u.map.getPosition
    u.map.getPosition = function() return nil end
    VoiceUI.clearHeads()
    VoiceUI.attachHead('k', 5)
    checkAbove(move(5), 'no camera')
    u.map.getPosition = getPosition
    -- a speaker the client does not know: no icon
    VoiceUI.attachHead('gone', 6)
    -- a speaker on another floor when it starts: not drawn from the start
    VoiceUI.clearHeads()
    eq(#creature.effects, 0, 'cleared')
    creature.pos = m:at(5, 14, 8)
    VoiceUI.attachHead('k', 5)
    eq(#creature.effects, 0, 'another floor from the start')
    -- a module reload keeps the registration (registering again is an error)
    VoiceUI.destroy()
    eq(#creature.effects, 0, 'nothing left at the end')
    eq(LocalPlayer.onPositionChange, nil, 'disconnected')
    eq(Creature.onDisappear, nil)
    dofile(MODULE .. 'voice_ui.lua')
    VoiceUI.create()
    creature.pos = m:at(5, 14)
    VoiceUI.attachHead('k', 5)
    eq(#creature.effects, 1, 'after a reload')
    VoiceUI.destroy()
    eq(registrationErrors, 0, 'registered once')
    -- a reload that lost the global: the id is taken, and used
    VoiceHeadEffectRegistered = nil
    dofile(MODULE .. 'voice_ui.lua')
    VoiceUI.create()
    VoiceUI.attachHead('k', 5)
    eq(#creature.effects, 1, 'the registered image is used')
    VoiceUI.destroy()
end)

test('every image the module draws exists at the size its widget gives it', function()
    -- the width and height from a PNG's header, and its colour type (6: RGBA)
    local function png(path)
        local f = io.open(path, 'rb')
        if not f then
            return nil
        end
        local head = f:read(29)
        f:close()
        assert(head and head:sub(2, 4) == 'PNG', path .. ' is not a PNG')
        local function u32(i)
            local a, b, c, d = head:byte(i, i + 3)
            return ((a * 256 + b) * 256 + c) * 256 + d
        end
        return u32(17), u32(21), head:byte(26)
    end
    local SIZES = {
        mic = '16x16', mic_off = '16x16', headset = '16x16', headset_off = '16x16', gear = '16x16',
        s_mic = '12x12', s_selfmuted = '12x12', s_deaf = '12x12', s_srvmuted = '12x12', s_mutedforme = '12x12',
        s_staff = '12x12', lite = '12x12', dot = '12x12', speaking_ring = '12x12',
        speaker_head = '18x16', button = '40x20', ptt_touch = '48x48',
    }
    local used = {}
    for _, file in ipairs({ 'voice.lua', 'voice_ui.lua', 'voice_settings.lua', 'voice.otui', 'voicesettings.otui',
        'voiceonboard.otui' }) do
        local src = io.open(MODULE .. file):read('*a')
        for name in src:gmatch('/game_voice/images/([%w_]+)') do
            used[name] = true
        end
    end
    for name in pairs(used) do
        assert(SIZES[name], 'an image with no size here: ' .. name)
    end
    for name, size in pairs(SIZES) do
        assert(used[name], 'an image nothing draws: ' .. name)
        local w, h, kind = png(MODULE .. 'images/' .. name .. '.png')
        assert(w, 'missing: images/' .. name .. '.png')
        eq(w .. 'x' .. h, size, name)
        eq(kind, 6, name .. ': RGBA, a transparent background')
    end
    -- the sizes the otui gives them
    local otui = io.open(MODULE .. 'voice.otui'):read('*a')
    assert(otui:match('VoiceIconButton < UIButton.-image%-size: 16 16'), 'header buttons draw 16x16')
    assert(otui:match('VoiceMemberIcon < UIWidget%s+size: 12 12'), 'member icons are 12x12')
end)

test('every widget the Lua reads by id exists in its otui', function()
    local function read(file)
        local f = assert(io.open(MODULE .. file))
        local text = f:read('*a')
        f:close()
        return text
    end
    local function ids(block)
        local out = {}
        for id in block:gmatch('id: ([%w_]+)') do
            out[id] = true
        end
        return out
    end
    local onboard = ids(read('voiceonboard.otui'))
    for id in read('voice_settings.lua'):gmatch('onboard%.([%a_][%w_]*)') do
        assert(onboard[id], 'voiceonboard.otui has no ' .. id)
    end
    local otui = read('voice.otui')
    local popup = ids(otui:match('VoiceVolumePopup < UIWidget(.-)\nVoiceReportReason'))
    for id in read('voice_ui.lua'):gmatch('volumePopup%.([%a_][%w_]*)') do
        if id ~= 'onMousePress' and id ~= 'onKeyPress' then
            assert(popup[id], 'VoiceVolumePopup has no ' .. id)
        end
    end
    local headerIds = ids(otui:match('VoiceSectionHeader < UIWidget(.-)\nVoiceMemberIcon'))
    for id in read('voice_ui.lua'):gmatch('%f[%w_]h%.([%a_][%w_]*)[:%.]') do
        assert(headerIds[id], 'VoiceSectionHeader has no ' .. id)
    end
end)

print(string.format('%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
