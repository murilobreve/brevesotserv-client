-- private variables
local background
local clientVersionLabel
local bgEffectEvent = nil
local toggleState = true  -- controls which effect  is active
local timeLoopBackgroundEffect = 5000 -- 5 seconds

-- public functions
function init()
    background = g_ui.displayUI('background')
    background:lower()

    clientVersionLabel = background:getChildById('clientVersionLabel')
    clientVersionLabel:hide()

    -- the artwork is shown whole (scaled to fit), the blurred copy behind it
    -- fills whatever is left when the window is not 16:9
    connect(background, { onGeometryChange = fitArtwork })
    fitArtwork()

    connect(g_game, {
        onGameStart = hide
    })
    connect(g_game, {
        onGameEnd = show
    })
    startBackgroundEffectLoop() -- start the background effect loop
end

local ARTWORK_W, ARTWORK_H = 2000, 1125

function fitArtwork()
    if not background then
        return
    end
    local artwork = background:getChildById('artwork')
    local size = background:getSize()
    if size.width <= 0 or size.height <= 0 then
        return
    end
    local scale = math.min(size.width / ARTWORK_W, size.height / ARTWORK_H)
    artwork:setSize({ width = math.floor(ARTWORK_W * scale), height = math.floor(ARTWORK_H * scale) })
end

function terminate()
    disconnect(background, { onGeometryChange = fitArtwork })
    disconnect(g_game, {
        onGameStart = hide
    })
    disconnect(g_game, {
        onGameEnd = show
    })

    if bgEffectEvent then
        removeEvent(bgEffectEvent)
        bgEffectEvent = nil
    end
    background:destroy()

    background = nil
    clientVersionLabel = nil
end

function hide()
    background:hide()
    if bgEffectEvent then
        removeEvent(bgEffectEvent)
        bgEffectEvent = nil
    end
end

function show()
    background:show()
    startBackgroundEffectLoop()
end

function hideVersionLabel()
    background:getChildById('clientVersionLabel'):hide()
end

function setVersionText(text)
    clientVersionLabel:setText(text)
end

function getBackground()
    return background
end

-- 🔄 example of how to use the particles widget
function startBackgroundEffectLoop()
    if bgEffectEvent then
        removeEvent(bgEffectEvent)
        bgEffectEvent = nil
    end

    local function switchEffect()
        if not background then
            return
        end

        local particlesWidget = background:getChildById('particles') -- background is the root widget of the background module
        if not particlesWidget then
            return
        end

        if toggleState then
            particlesWidget:setEffect('background-effect')
        else
            particlesWidget:setEffect('background2-effect')
        end
        toggleState = not toggleState

        -- repeat every 5 seconds (adjust the time you want)
        bgEffectEvent = scheduleEvent(switchEffect, timeLoopBackgroundEffect)
    end

    -- start the first effect change
    switchEffect()
end
