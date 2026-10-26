-- Skillshots: some spells are aimed with the mouse, like in a MOBA. Right
-- before one of them is said (action bar, hotkey or chat) this module tells
-- the server which tile is under the mouse (opcode OPCODE); the server
-- (scripts/skillshot) sends the spell toward it. The mouse on a creature's
-- body aims at the sqm the creature stands on (a big one is drawn over the
-- sqm above and to the left of its own); on the character, at its own sqm
-- (the spells that land on the ground fall on it). With the mouse off the
-- map, or over a window on it, the spell goes at the creature being
-- attacked (said so, t = 1: the Salto do Tita does not leap onto it, it
-- goes the way the character faces), else the way the character faces.
-- The server says at login which words are skillshots; the client answers
-- with the spells it has art for (ART) and the server then sends their
-- moments to draw (hook.lua, meteor.lua, palm.lua, arrow.lua,
-- judgement.lua, wall.lua, orb.lua, seed.lua, shard.lua, crack.lua, step.lua,
-- leap.lua, beam.lua, spear.lua, kick.lua, and the Translocacao's
-- transloc.lua) instead of the Tibia effects. All have the art v2: layers
-- the engine animates by the designer's curves (layers.lua).
-- The same way it draws the boss spells of the risen monsters (rare.lua,
-- fx "rare_<tier>", scripts/rarity/spells.lua).

local OPCODE = 131
local ART = { 'hook', 'meteor', 'palm', 'arrow', 'judgement', 'wall', 'orb', 'seed', 'shard', 'crack', 'step', 'leap', 'beam', 'spear', 'kick', 'transloc' }
for _, fx in ipairs(rareArtNames()) do
    table.insert(ART, fx)
end

local words = {}
local originalTalk, originalTalkChannel

local function normalize(text)
    return tostring(text or ''):lower():gsub('^%s+', ''):gsub('%s+$', ''):gsub('^"', '')
end

-- How many sqm a creature is drawn over, up and to the left of its own: 2
-- for the big ones (a dragon covers the sqm above and to the left of the one
-- it stands on), else 1.
local function spanOf(creature)
    local outfit = creature.getOutfit and creature:getOutfit()
    local thingType = outfit and outfit.type and outfit.type > 0 and g_things.getThingType(outfit.type, ThingCategoryCreature)
    if not thingType then
        return 1
    end
    return math.max(thingType:getWidth(), thingType:getHeight())
end

-- The creature drawn under the mouse on `pos`: the one standing (or walking
-- out of) that sqm, else a big one to the right or below whose body is drawn
-- over it. The one being attacked wins.
local function creatureUnder(pos)
    local tile = g_map.getTile(pos)
    local creature = tile and tile:getTopCreature(true)
    if creature then
        return creature
    end
    local attacking = g_game.getAttackingCreature()
    local found
    for _, side in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
        local near = g_map.getTile({ x = pos.x + side[1], y = pos.y + side[2], z = pos.z })
        local other = near and near:getTopCreature(false)
        if other and spanOf(other) > 1 then
            if attacking and other:getId() == attacking:getId() then
                return other
            end
            found = found or other
        end
    end
    return found
end

-- a window (a container, the trade, a dialog) over the map under the mouse
local function overWindow(mouse)
    local widget = g_ui.getRootWidget():recursiveGetChildByPos(mouse, false)
    while widget do
        if widget:getClassName() == 'UIWindow' then
            return true
        end
        widget = widget:getParent()
    end
    return false
end

-- Where the spell goes: the sqm under the mouse on the map (the creature's
-- own sqm when the mouse is on its body, the player's when it is on him);
-- with the mouse off the map (a click on the action bar, a window over the
-- map), the creature being attacked, and true after it. nil: the server
-- sends it the way the character faces.
function aimPosition(mapPanel)
    local mouse = g_window.getMousePosition()
    if mapPanel:containsPoint(mouse) and not overWindow(mouse) then
        local pos = mapPanel:getPosition(mouse)
        if pos and pos.x ~= 0 then
            local creature = creatureUnder(pos)
            return creature and creature:getPosition() or pos, false
        end
    end
    local target = g_game.getAttackingCreature()
    local player = g_game.getLocalPlayer()
    local pos = target and target:getPosition()
    if pos and player and pos.z == player:getPosition().z then
        return pos, true
    end
    return nil
end

local function sendAim(text)
    if not words[normalize(text)] then
        return
    end
    local mapPanel = modules.game_interface and modules.game_interface.getMapPanel()
    local protocol = g_game.getProtocolGame()
    if not mapPanel or not protocol then
        return
    end
    local pos, fromTarget = aimPosition(mapPanel)
    if not pos then
        return
    end
    protocol:sendExtendedJSONOpcode(OPCODE, { x = pos.x, y = pos.y, z = pos.z, t = fromTarget and 1 or nil })
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    if data.fx == 'hook' then
        onHookArt(data)
    elseif data.fx == 'meteor' then
        onMeteorArt(data)
    elseif data.fx == 'palm' then
        onPalmArt(data)
    elseif data.fx == 'arrow' then
        onArrowArt(data)
    elseif data.fx == 'judgement' then
        onJudgementArt(data)
    elseif data.fx == 'wall' then
        onWallArt(data)
    elseif data.fx == 'orb' then
        onOrbArt(data)
    elseif data.fx == 'seed' then
        onSeedArt(data)
    elseif data.fx == 'shard' then
        onShardArt(data)
    elseif data.fx == 'crack' then
        onCrackArt(data)
    elseif data.fx == 'step' then
        onStepArt(data)
    elseif data.fx == 'leap' then
        onLeapArt(data)
    elseif data.fx == 'beam' then
        onBeamArt(data)
    elseif data.fx == 'spear' then
        onSpearArt(data)
    elseif data.fx == 'kick' then
        onKickArt(data)
    elseif data.fx == 'transloc' then
        onTranslocArt(data)
    elseif isRareArt(data.fx) then
        onRareArt(data)
    elseif type(data.words) == 'table' then
        words = {}
        for _, spell in ipairs(data.words) do
            words[normalize(spell)] = true
        end
        protocol:sendExtendedJSONOpcode(OPCODE, { art = ART })
    end
end

function clearArt()
    clearHookArt()
    clearMeteorArt()
    clearPalmArt()
    clearArrowArt()
    clearJudgementArt()
    clearWallArt()
    clearOrbArt()
    clearSeedArt()
    clearShardArt()
    clearCrackArt()
    clearStepArt()
    clearLeapArt()
    clearBeamArt()
    clearSpearArt()
    clearKickArt()
    clearTranslocArt()
    clearRareArt()
end

local warmUpEvent

local function warmUp()
    removeEvent(warmUpEvent)
    warmUpEvent = scheduleEvent(function()
        local player = g_game.getLocalPlayer()
        if player then
            warmUpArt(player:getPosition())
            warmUpLayers(player:getPosition())
        end
    end, 2000)
end

function init()
    registerHookArt()
    registerMeteorArt()
    registerPalmArt()
    registerArrowArt()
    registerJudgementArt()
    registerWallArt()
    registerOrbArt()
    registerSeedArt()
    registerShardArt()
    registerCrackArt()
    registerStepArt()
    registerLeapArt()
    registerBeamArt()
    registerSpearArt()
    registerKickArt()
    registerTranslocArt()
    registerRareArt()
    connect(g_game, { onGameStart = warmUp, onGameEnd = clearArt })
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    -- every spell goes through one of these two: the action bar and hotkeys
    -- call talk, the chat calls talkChannel with the say mode
    originalTalk = g_game.talk
    originalTalkChannel = g_game.talkChannel
    g_game.talk = function(text, ...)
        sendAim(text)
        return originalTalk(text, ...)
    end
    g_game.talkChannel = function(mode, channel, text, ...)
        if mode == MessageModes.Say then
            sendAim(text)
        end
        return originalTalkChannel(mode, channel, text, ...)
    end
end

function terminate()
    disconnect(g_game, { onGameStart = warmUp, onGameEnd = clearArt })
    removeEvent(warmUpEvent)
    unregisterHookArt()
    unregisterMeteorArt()
    unregisterPalmArt()
    unregisterArrowArt()
    unregisterJudgementArt()
    unregisterWallArt()
    unregisterOrbArt()
    unregisterSeedArt()
    unregisterShardArt()
    unregisterCrackArt()
    unregisterStepArt()
    unregisterLeapArt()
    unregisterBeamArt()
    unregisterSpearArt()
    unregisterKickArt()
    unregisterTranslocArt()
    unregisterRareArt()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    if originalTalk then
        g_game.talk = originalTalk
        g_game.talkChannel = originalTalkChannel
    end
end
