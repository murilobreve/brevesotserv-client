-- Passo Fantasma: the designer's art (images/passo, from "Passo Fantasma -
-- artes v1"). The server sends one moment per dash (scripts/skillshot/
-- monk.lua, fx "step", k "dash"): the departure, the trail over the one it
-- goes through, the cut on it and the arrival, all at once, and the bonus
-- on the monk (1 to 4) for as long as the chain lasts (`ms`).

local BONUS_LEVELS = 4

-- anchors: the centre of the sqm
local art = newArtSet(4200, '/game_skillshot/images/passo/', 'Passo')
art.add('saida', 64, 16, 16, 300)
art.add('corte', 64, 16, 16, 300)
art.add('chegada', 64, 16, 16, 300)
for _, way in ipairs({ 'h', 'v', 'ne', 'nw' }) do
    art.add('rastro_' .. way, 32, 0, 0, 150)
end
for level = 1, BONUS_LEVELS do
    art.add('bonus_' .. level, 32, 0, 0)
end

local bonuses = {} -- creature id -> placed

function registerStepArt()
    art.register()
end

function clearStepArt()
    for _, placed in pairs(bonuses) do
        detachArt(placed)
    end
    bonuses = {}
end

function unregisterStepArt()
    clearStepArt()
    art.unregister()
end

local handlers = {}

function handlers.dash(data)
    local from, to = data.f, data.t
    if not from or not to then
        return
    end
    art.burst('saida', from)
    local dx, dy = to.x - from.x, to.y - from.y
    local steps = math.max(math.abs(dx), math.abs(dy))
    local trail = 'rastro_' .. ART_LINE_OF[artDirection(dx, dy)]
    for step = 1, steps - 1 do
        art.burst(trail, {
            x = from.x + math.floor(dx * step / steps + 0.5),
            y = from.y + math.floor(dy * step / steps + 0.5),
            z = from.z
        })
    end
    if data.p then
        art.burst('corte', data.p)
    end
    art.burst('chegada', to)
    local id, level = tonumber(data.id), tonumber(data.n)
    if id then
        detachArt(bonuses[id])
        bonuses[id] = nil
        local monk = g_map.getCreatureById(id)
        if monk and level and level >= 1 then
            bonuses[id] = art.attach('bonus_' .. math.min(level, BONUS_LEVELS), monk, tonumber(data.ms) or 4000)
        end
    end
end

function onStepArt(data)
    local handler = handlers[data.k]
    if handler then
        handler(data)
    end
end
