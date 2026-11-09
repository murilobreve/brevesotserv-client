-- Lite engine: the relay's control messages only, over the client's own
-- HTTP.webSocket (ixwebsocket in the Windows client, the emscripten socket in
-- the browser). It gives presence, rooms, party moves and moderation in the
-- builds that have no g_voice; there is no audio, and the hello says a=0, so
-- the relay sends this session no binary frames at all.
--
-- HTTP.webSocket reports every close as "close_code::normal" or
-- "close_code::error <reason>", without the number: the session then treats
-- it as a network failure (backoff with a new token). Bans and the kill
-- switch still arrive through canary's opcode 142 (cfg on=false, err banned).

EngineLite = {}
EngineLite.__index = EngineLite

local HANDSHAKE_TIMEOUT = 10 -- seconds

function EngineLite.available()
    return HTTP ~= nil and type(HTTP.webSocket) == 'function' and g_http ~= nil and g_http.ws ~= nil
end

-- info: { build = text }
function EngineLite.create(sink, info)
    return setmetatable({ name = 'lite', audio = false, sink = sink, build = info.build, gen = 0 }, EngineLite)
end

-- a later build may put the number in the message; today there is none
local function closeCode(message)
    return tonumber(tostring(message or ''):match('close_code::(%d+)'))
end

function EngineLite:connect(url, tok)
    self:disconnect()
    local gen = self.gen
    local hello = json.encode({ t = 'hello', v = 1, tok = tok, cl = 'lite', b = self.build, a = 0 })
    self.sink('state', 'connecting')
    local ok, socket = pcall(HTTP.webSocket, url, {
        onOpen = function()
            if self.gen == gen and self.socket then
                self.open = true
                self.socket.send(hello)
                self.sink('state', 'open')
            end
        end,
        onMessage = function(message)
            if self.gen == gen and type(message) == 'string' then
                -- the browser build hands text frames over with their C terminator
                self.sink('ctl', (message:gsub('%z+$', '')))
            end
        end,
        onClose = function(message)
            self:ended(gen, 'closed', message)
        end,
        onError = function(message)
            self:ended(gen, 'error', message)
        end,
    }, HANDSHAKE_TIMEOUT)
    if ok and type(socket) == 'table' then
        self.socket = socket
    else
        -- told on the next frame, as a real socket would
        addEvent(function()
            self:ended(gen, 'error', nil)
        end)
    end
end

-- the one terminal event of a socket; later ones (an error then a close) are dropped
function EngineLite:ended(gen, state, message)
    if self.gen ~= gen then
        return
    end
    self:forget()
    self.sink('state', state, closeCode(message))
end

-- drops the socket; HTTP.operations keeps every websocket forever otherwise
function EngineLite:forget()
    local socket = self.socket
    self.gen = self.gen + 1
    self.socket, self.open = nil, false
    if socket then
        HTTP.operations[socket.id] = nil
    end
    return socket
end

function EngineLite:disconnect()
    local socket = self:forget()
    if socket then
        pcall(socket.close)
    end
end

function EngineLite:send(msg)
    if self.socket and self.open then
        self.socket.send(json.encode(msg))
    end
end

function EngineLite:terminate()
    self:disconnect()
end
