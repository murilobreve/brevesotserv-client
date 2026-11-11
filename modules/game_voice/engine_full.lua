-- Full engine: audio and control through the g_voice binding (WebCodecs in
-- the browser build, src/framework/voice/voiceengine_web.cpp with
-- browser/voice/mythos-voice.js; libopus, OpenAL and ixwebsocket on Windows,
-- src/framework/voice/voiceengine_native.cpp). A build without g_voice, or
-- whose engine has no audio (voiceengine_null.cpp), has
-- EngineFull.available() false and voice.lua picks the lite engine instead.
-- voice.lua sends every setting again on each change, so each setter must do
-- nothing when its value did not change. Events come back through
-- g_voice.onVoiceEvent(type, s, a, b), the same shape the other engines hand
-- to their sink:
--   'state' s = connecting|open|closed|error, a = close code
--   'ctl'   s = one control message from the relay (JSON text)
--   'spk'   a = sid, b = 1|0 (speaking edges)
--   'talk'  a = slot or -1 (the local gate)
--   'level' a = dBFS (only while the meter is on)
--   'mic'   s = ok|denied|nodevice|encoder; 'devices', 'stats', 'caps'

EngineFull = {}
EngineFull.__index = EngineFull

function EngineFull.available()
    return g_voice ~= nil and type(g_voice.isSupported) == 'function' and g_voice.isSupported() == true
end

-- info: { cl = 'win'|'web', build = text }
function EngineFull.create(sink, info)
    local self = setmetatable({ name = 'full', audio = true, sink = sink, info = info, live = false }, EngineFull)
    -- proximity's distance and pan came with the slot-3 engines: an older
    -- executable has no such binding (looked up once, here)
    local spatial = g_voice.setUserSpatial
    self.spatial = type(spatial) == 'function'
    self.spatialFn = self.spatial and spatial or nil
    self.handler = function(kind, s, a, b)
        self:onEvent(kind, s, a, b)
    end
    connect(g_voice, { onVoiceEvent = self.handler })
    return self
end

function EngineFull:onEvent(kind, s, a, b)
    if kind == 'state' and (s == 'closed' or s == 'error') then
        if not self.live then
            return -- the end of a socket we closed ourselves
        end
        self.live = false
    end
    self.sink(kind, s, a, b)
end

-- the engine sends the hello itself once the socket is open
function EngineFull:connect(url, tok)
    self.live = true
    g_voice.connect(url, tok, self.info.cl, self.info.build)
end

function EngineFull:disconnect()
    self.live = false
    g_voice.disconnect()
end

function EngineFull:send(msg)
    g_voice.sendControl(json.encode(msg))
end

-- the rest maps one to one onto g_voice; a call the binding lacks is skipped
for _, name in ipairs({ 'setTransmit', 'setMode', 'setVadThreshold', 'setPreset', 'setInputDevice',
    'setOutputDevice', 'getInputDevices', 'getOutputDevices', 'setInputGain', 'setOutputVolume',
    'setUserVolume', 'setSlotVolume', 'setDeafened', 'setSelfMuted', 'setMeter', 'setPttMouse',
    'setGlobalPtt', 'startLocalTest' }) do
    EngineFull[name] = function(self, ...)
        local f = g_voice[name]
        if f then
            return f(...)
        end
    end
end

-- a near speaker's gain (0-1) and pan (-1 left, 1 right), for its slot-3
-- frames only; nothing on an executable without it
function EngineFull:setUserSpatial(sid, gain, pan)
    if self.spatialFn then
        self.spatialFn(sid, gain, pan)
    end
end

function EngineFull:terminate()
    if self.live then
        self:disconnect()
    end
    disconnect(g_voice, { onVoiceEvent = self.handler })
end
