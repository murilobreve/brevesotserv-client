--[[
    register(id, name, thingId, thingType, config)
    config = {
        speed, disableWalkAnimation, shader, drawOnUI, opacity
        duration, loop, transform, hideOwner, followOwner, size{width, height}
        offset{x, y, onTop}, dirOffset[dir]{x, y, onTop},
        light { color, intensity}, drawOrder(only for tiles),
        bounce{minHeight, height, speed},
        pulse{minHeight, height, speed},
        fade{start, end, speed}

        onAttach, onDetach
    }
]]
--
AttachedEffectManager.register(1, 'Spoke Lighting', 12, ThingCategoryEffect, {
    speed = 0.5,
    onAttach = function(effect, owner)
        print('onAttach: ', effect:getId(), owner:getName())
    end,
    onDetach = function(effect, oldOwner)
        print('onDetach: ', effect:getId(), oldOwner:getName())
    end
})

-- Use the paperdoll system instead of attachedEffect for this kind of attachment, it’s more consistent.
AttachedEffectManager.register(2, 'Bat Wings', 307, ThingCategoryCreature, {
    speed = 5,
    disableWalkAnimation = true,
    shader = 'Outfit - Rainbow',
    followOwner = true,
    dirOffset = {
        [North] = { 0, -10, true },
        [East] = { 5, -5 },
        [South] = { -5, 0 },
        [West] = { -10, -5, true }
    },
    onAttach = function(effect, owner)
        owner:setBounce(0, 10, 5000)
    end,
    onDetach = function(effect, oldOwner)
        oldOwner:setBounce(0, 0)
    end
})

AttachedEffectManager.register(3, 'Angel Light', 50, ThingCategoryEffect, {
    opacity = 0.5,
    drawOnUI = false
})

AttachedEffectManager.register(4, 'Four Angel Light', 0, 0, {
    onAttach = function(effect, owner)
        local angelLight = g_attachedEffects.getById(3)
        local angelLight1 = angelLight:clone()
        local angelLight2 = angelLight:clone()
        local angelLight3 = angelLight:clone()
        local angelLight4 = angelLight:clone()

        angelLight1:setOffset(-50, 50, true)
        angelLight2:setOffset(50, 50, true)
        angelLight3:setOffset(50, -50, true)
        angelLight4:setOffset(-50, -50, true)

        effect:attachEffect(angelLight1)
        effect:attachEffect(angelLight2)
        effect:attachEffect(angelLight3)
        effect:attachEffect(angelLight4)
    end
})

AttachedEffectManager.register(5, 'Transform', 40, ThingCategoryCreature, {
    transform = true,
    duration = 5000,
    onAttach = function(effect, owner)
        local e = Effect.create()
        e:setId(7)
        owner:getTile():addThing(e)
    end,
    onDetach = function(effect, oldOwner)
        local e = Effect.create()
        e:setId(50)
        oldOwner:getTile():addThing(e)
    end
})

AttachedEffectManager.register(6, 'Lake Monster', 34, ThingCategoryEffect, {
    hideOwner = true,
    duration = 1500,
    -- loop = 1,
    onDetach = function(effect, oldOwner)
        local e = Effect.create()
        e:setId(54)
        oldOwner:getTile():addThing(e)
    end
})

AttachedEffectManager.register(7, 'Pentagram Aura', '/images/game/effects/pentagram', ThingExternalTexture, {
    size = { 128, 128 },
    offset = { 50, 45 }
})

-- Baiak Rarity System: the pentagram of effect 7 in black, under every
-- "Lord of Death" monster (attached by the server, RarityConfig.tiers)
AttachedEffectManager.register(20, 'Lord of Death Aura', '/images/game/effects/pentagram_black', ThingExternalTexture, {
    size = { 128, 128 },
    offset = { 50, 45 }
})

-- Baiak Rarity System: the aura of a living rare monster (design kit
-- "Renascimento, quatro presencas"), attached by the server
-- (RarityConfig.tiers attachedEffect). It shows up as the monster settles out
-- of its rise: 0.35 s after it stands up it fades in over 0.55 s. The Lord of
-- Death's broken five-point seal lies under it; the other auras float around
-- it. The sizes (the kit's, drawn 1.3 times bigger) are for a one-tile
-- creature: a bigger one (a 2x2 dragon) gets it twice as big, around the
-- middle of its sprite.
local function rareMonsterAura(id, name, folder, tiles, opacity, onTop)
    AttachedEffectManager.register(id, name, '/game_raritybonus/images/revive/' .. folder .. '/revive_' .. folder .. '_aura', ThingExternalTexture, {
        smooth = true,
        offset = { 0, 0, onTop },
        onAttach = function(effect, owner)
            local span = 1
            local outfit = owner.getOutfit and owner:getOutfit()
            local thingType = outfit and outfit.type > 0 and g_things.getThingType(outfit.type, ThingCategoryCreature)
            if thingType then
                span = math.max(1, math.min(2, math.max(thingType:getWidth(), thingType:getHeight())))
            end
            local side = math.floor(tiles * span * 32 + 0.5)
            local half = math.floor(side / 2) - 16 + (span - 1) * 16
            effect:setSize({ width = side, height = side })
            effect:setOffset(half, half + 2)
            effect:setOpacity(0)
            for step = 1, 11 do
                scheduleEvent(function()
                    local x = step / 11
                    effect:setOpacity(opacity * x * x * (3 - 2 * x))
                end, 350 + step * 50)
            end
        end
    })
end

rareMonsterAura(21, 'Pale Aura', 'pale', 1.25, 0.30, true)
rareMonsterAura(22, 'Ashen Aura', 'ashen', 1.35, 0.38, true)
rareMonsterAura(23, 'Obsidian Aura', 'obsidian', 1.50, 0.46, true)
rareMonsterAura(24, 'Lord of Death Seal', 'lord-of-death', 1.80, 0.56, false)

AttachedEffectManager.register(8, 'Ki', '/images/game/effects/ki', ThingExternalTexture, {
    size = { 140, 110 },
    offset = { 60, 75, true },
    pulse = { 0, 50, 3000 },
    --fade = { 0, 100, 1000 },
})

AttachedEffectManager.register(9, 'Thunder', '/images/game/effects/thunder', ThingExternalTexture, {
    loop = 1,
    offset = { 215, 230 }
})

AttachedEffectManager.register(10, 'Dynamic Effect', 0, 0, {
    duration = 500,
    onAttach = function(effect, owner)
        local spriteSize = g_gameConfig.getSpriteSize()
        local length = 3

        local missile = AttachedEffect.create(38, ThingCategoryMissile)
        missile:setDuration(effect:getDuration())
        missile:setDirection(5)
        missile:setOffset(spriteSize * length, 0)
        missile:setBounce(0, 15, 1000)
        missile:move(Position.translated(owner:getPosition(), -length, 0), owner:getPosition())
        effect:attachEffect(missile)

        missile = AttachedEffect.create(38, ThingCategoryMissile)
        missile:setDuration(effect:getDuration())
        missile:setDirection(3)
        missile:setOffset(-(spriteSize * length), 0)
        missile:setBounce(0, 15, 1000)
        missile:move(Position.translated(owner:getPosition(), length, 0), owner:getPosition())

        effect:attachEffect(missile)
    end,
    onDetach = function(effect, oldOwner)
        local e = Effect.create()
        e:setId(50)
        oldOwner:getTile():addThing(e)
    end
})

AttachedEffectManager.register(11, 'Bat', 307, ThingCategoryCreature, {
    speed = 0.5,
    offset = { 0, 0 },
    bounce = { 20, 20, 2000 }
})
