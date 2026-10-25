-- Chuva de Juizo: the designer's art (images/juizo, from "Chuva de Juizo -
-- artes v1"). The server sends two moments of a cast (scripts/skillshot/
-- paladin.lua, fx "judgement"):
--   mark    the golden circle on the 3x3 and the centre's mark, `ms` (1 s);
--           the beam comes down in its last 0.2 s
--   impact  the light bursting from the centre

local BEAM_MS = 200

-- anchors: the centre of the area, the foot of the beam
local art = newArtSet(3600, '/game_skillshot/images/juizo/', 'Juizo')
art.add('circulo', 96, 32, 32, 1000, true)
art.add('centro', 32, 0, 0, 1000, true)
art.add('raio', { 32, 128 }, 0, 111, BEAM_MS)
art.add('impacto', 128, 48, 48, 400)

local pending = {} -- scheduled events, cancelled when the game ends

local function later(delay, callback)
    local event
    event = scheduleEvent(function()
        pending[event] = nil
        callback()
    end, math.max(0, delay))
    pending[event] = true
end

function registerJudgementArt()
    art.register()
end

function clearJudgementArt()
    for event in pairs(pending) do
        removeEvent(event)
    end
    pending = {}
end

function unregisterJudgementArt()
    clearJudgementArt()
    art.unregister()
end

local handlers = {}

function handlers.mark(data)
    local center, ms = data.p, tonumber(data.ms) or 1000
    art.burst('circulo', center)
    art.burst('centro', center)
    later(ms - BEAM_MS, function()
        art.burst('raio', center)
    end)
end

function handlers.impact(data)
    art.burst('impacto', data.p)
end

function onJudgementArt(data)
    local handler = handlers[data.k]
    if handler and type(data.p) == 'table' then
        handler(data)
    end
end
