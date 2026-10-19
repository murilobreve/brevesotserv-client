local HOTKEY = 'Ctrl+Y'
local MAP_SHADERS = { {
    name = 'Map - Default',
    frag = nil
}, {
    name = 'Map - Fog',
    frag = 'shaders/fragment/fog.frag',
    tex1 = 'images/clouds'
}, {
    name = 'Map - Rain',
    frag = 'shaders/fragment/rain.frag'
}, {
    name = 'Map - Snow',
    frag = 'shaders/fragment/snow.frag',
    tex1 = 'images/snow'
}, {
    name = 'Map - Gray Scale',
    frag = 'shaders/fragment/grayscale.frag'
}, {
    name = 'Map - Bloom',
    frag = 'shaders/fragment/bloom.frag'
}, {
    name = 'Map - Sepia',
    frag = 'shaders/fragment/sepia.frag'
}, {
    name = 'Map - Pulse',
    frag = 'shaders/fragment/pulse.frag',
    drawViewportEdge = true
}, {
    name = 'Map - Old Tv',
    frag = 'shaders/fragment/oldtv.frag'
}, {
    name = 'Map - Party',
    frag = 'shaders/fragment/party.frag'
}, {
    name = 'Map - Radial Blur',
    frag = 'shaders/fragment/radialblur.frag',
    drawViewportEdge = true
}, {
    name = 'Map - Zomg',
    frag = 'shaders/fragment/zomg.frag',
    drawViewportEdge = true
}, {
    name = 'Map - Heat',
    frag = 'shaders/fragment/heat.frag',
    drawViewportEdge = true
}, {
    name = 'Map - Noise',
    frag = 'shaders/fragment/noise.frag'
} }

local OUTFIT_SHADERS = { {
    name = 'Outfit - Default',
    frag = nil
}, {
    name = 'Outfit - Rainbow',
    frag = 'shaders/fragment/party.frag'
}, {
    name = 'Outfit - Ghost',
    frag = 'shaders/fragment/radialblur.frag',
    drawColor = false
}, {
    name = 'Outfit - Jelly',
    frag = 'shaders/fragment/heat.frag'
}, {
    name = 'Outfit - Fragmented',
    frag = 'shaders/fragment/noise.frag'
}, {
    name = 'Outfit - cyclopedia-black',
    frag = 'shaders/fragment/cyclopedia.frag'
}, {
    name = 'Outfit - Outline',
    useFramebuffer = true,
    frag = 'shaders/fragment/outline.frag'
}, {
    name = 'Outfit - ForgeDonor',
    useFramebuffer = true,
    frag = 'shaders/fragment/forge_donor.frag'
}, {
    name = 'Outfit - ForgeSuccess',
    useFramebuffer = true,
    frag = 'shaders/fragment/forge_success.frag'
}, {
    name = 'Outfit - ForgeFailed',
    useFramebuffer = true,
    frag = 'shaders/fragment/forge_failed.frag'
}, {
    -- Baiak Rarity System: fixed hue-rotate tints, one per monster tier.
    -- Assigned server-side (monster:setShader('Rarity - Pale'/etc.) in
    -- Rarity.applyTier), not selectable from this module's own UI - these
    -- three exist in this list purely so ShaderController:onInit() picks
    -- them up and registers them with the engine the same way every other
    -- outfit shader here does.
    name = 'Rarity - Pale',
    frag = 'shaders/fragment/rarity_pale.frag'
}, {
    name = 'Rarity - Ashen',
    frag = 'shaders/fragment/rarity_ashen.frag'
}, {
    name = 'Rarity - Obsidian',
    frag = 'shaders/fragment/rarity_obsidian.frag'
}, {
    name = 'Rarity - Lord of Death',
    frag = 'shaders/fragment/rarity_lord_of_death.frag'
}, {
    -- The revive of a Pale / Ashen / Obsidian / Lord of Death monster
    -- (scripts/rarity/revive.lua): the corpse wakes (Revive), then flickers
    -- and the monster stands up made of light (Rise) before taking its tier
    -- shader. Assigned server-side, like the tier shaders above.
    name = 'Rarity - Revive Pale',
    frag = 'shaders/fragment/rarity_revive_pale.frag'
}, {
    name = 'Rarity - Rise Pale',
    frag = 'shaders/fragment/rarity_rise_pale.frag'
}, {
    name = 'Rarity - Revive Ashen',
    frag = 'shaders/fragment/rarity_revive_ashen.frag'
}, {
    name = 'Rarity - Rise Ashen',
    frag = 'shaders/fragment/rarity_rise_ashen.frag'
}, {
    name = 'Rarity - Revive Obsidian',
    frag = 'shaders/fragment/rarity_revive_obsidian.frag'
}, {
    name = 'Rarity - Rise Obsidian',
    frag = 'shaders/fragment/rarity_rise_obsidian.frag'
}, {
    name = 'Rarity - Revive Lord of Death',
    frag = 'shaders/fragment/rarity_revive_lord_of_death.frag'
}, {
    name = 'Rarity - Rise Lord of Death',
    frag = 'shaders/fragment/rarity_rise_lord_of_death.frag'
}, {
    -- Baiak Rarity System: item-rarity tints, one per grade. Assigned
    -- server-side (item:setShader(...) in scripts/rarity/loot.lua), not
    -- selectable from this module's own UI, same reasoning as the three
    -- monster-tier shaders above. These color the ITEM by its own rarity
    -- grade (uncommon/rare/epic/legendary/mythic) rather than by which
    -- monster tier it happened to drop from.
    name = 'Rarity - Uncommon',
    frag = 'shaders/fragment/rarity_uncommon.frag'
}, {
    name = 'Rarity - Rare',
    frag = 'shaders/fragment/rarity_rare.frag'
}, {
    name = 'Rarity - Epic',
    frag = 'shaders/fragment/rarity_epic.frag'
}, {
    name = 'Rarity - Legendary',
    frag = 'shaders/fragment/rarity_legendary.frag'
}, {
    name = 'Rarity - Mythic',
    frag = 'shaders/fragment/rarity_mythic.frag'
}, }

local MOUNT_SHADERS = { {
    name = 'Mount - Default',
    frag = nil
}, {
    name = 'Mount - Rainbow',
    frag = 'shaders/fragment/party.frag'
} }

-- Text shaders for improved readability and visual effects
-- All shaders use multi-sample circular sampling for smooth outlines
local TEXT_SHADERS = { {
    name = 'Text - Default',
    frag = nil -- No shader, standard text rendering
}, {
    name = 'Text - Gold Outline',
    frag = 'shaders/fragment/text_golden_shadow_bold_fragment.frag' -- Smooth gold (#ee8413) outline
}, {
    name = 'Text - Black Outline',
    frag = 'shaders/fragment/text_black_outline.frag' -- Classic black outline, max readability
}, {
    name = 'Text - Glow',
    frag = 'shaders/fragment/text_glow.frag' -- Soft glow effect (higher GPU cost)
} }

local function attachShaders()
    local map = modules.game_interface.getMapPanel()
    map:setShader('Default')

    local player = g_game.getLocalPlayer()
    if player then
        player:setShader('Default')
        player:setMountShader('Default')
    end
end

local registerShader = function(opts, method)
    local fragmentShaderPath = resolvepath(opts.frag)

    if fragmentShaderPath ~= nil then
        --  local shader = g_shaders.createShader()
        g_shaders.createFragmentShader(opts.name, opts.frag, opts.useFramebuffer or false)

        if opts.tex1 then
            g_shaders.addMultiTexture(opts.name, opts.tex1)
        end
        if opts.tex2 then
            g_shaders.addMultiTexture(opts.name, opts.tex2)
        end

        -- Setup proper uniforms
        g_shaders[method](opts.name)
    end
end

-- Rarity items: one source, a variant per grade and element, named
-- "Rarity - <Grade> - <Element>" (the server's Rarity.itemShaderName). The
-- five "Rarity - <Grade>" shaders above stay for items not yet renamed.
local RARITY_ITEM_SOURCE = 'shaders/fragment/rarity_item.frag'
local RARITY_GRADES = { 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic' }
local RARITY_ELEMENTS = { 'None', 'Igneus', 'Terrenus', 'Fulmineus', 'Glacialis', 'Sacer', 'Mortifer', 'Corporalis' }

local function registerRarityItemShaders()
    local path = resolvepath(RARITY_ITEM_SOURCE)
    if not path or not g_resources.fileExists(path) then
        g_logger.error('Rarity item shaders: ' .. tostring(path) .. ' not found')
        return
    end
    local source = g_resources.readFileContents(path)
    for grade, gradeName in ipairs(RARITY_GRADES) do
        for element, elementName in ipairs(RARITY_ELEMENTS) do
            local name = 'Rarity - ' .. gradeName .. ' - ' .. elementName
            local code = '#define GRADE ' .. grade .. '\n#define ELEMENT ' .. (element - 1) .. '\n' .. source
            g_shaders.createFragmentShaderFromCode(name, code, false)
            g_shaders.setupOutfitShader(name)
        end
    end
end

ShaderController = Controller:new()

function ShaderController:onInit()
    for _, opts in pairs(MAP_SHADERS) do
        registerShader(opts, 'setupMapShader')
    end

    for _, opts in pairs(OUTFIT_SHADERS) do
        registerShader(opts, 'setupOutfitShader')
    end
    registerRarityItemShaders()

    for _, opts in pairs(MOUNT_SHADERS) do
        registerShader(opts, 'setupMountShader')
    end

    for _, opts in pairs(TEXT_SHADERS) do
        registerShader(opts, 'setupTextShader')
    end

    Keybind.new('Windows', 'show/hide Shader Windows', HOTKEY, '')
    Keybind.bind('Windows', 'show/hide Shader Windows', {
        {
            type = KEY_DOWN,
            callback = function()
                if ShaderController.ui then
                    ShaderController:unloadHtml()
                else
                    ShaderController:open()
                end
            end,
        }
    })
end

function ShaderController:onTerminate()
    g_shaders.clear()
    Keybind.delete('Windows', 'show/hide Shader Windows')
end

function ShaderController:onGameStart()
    attachShaders()
end

function ShaderController:onMapComboBoxChange(event)
    local map = modules.game_interface.getMapPanel()
    map:setShader(event.text)

    local data = event.target:getCurrentOption().data
    map:setDrawViewportEdge(data.drawViewportEdge == true)
end

function ShaderController:onOutfitComboBoxChange(event)
    local player = g_game.getLocalPlayer()
    if player then
        player:setShader(event.text)
        local data = event.target:getCurrentOption().data
        player:setDrawOutfitColor(data.drawColor ~= false)
    end
end

function ShaderController:onMountComboBoxChange(event)
    local player = g_game.getLocalPlayer()
    if player then
        player:setMountShader(event.text)
    end
end

function ShaderController:open()
    self:loadHtml('shaders.html', modules.game_interface.getMapPanel())

    for _, opts in pairs(MAP_SHADERS) do
        self.ui.mapComboBox:addOption(opts.name, opts)
    end

    for _, opts in pairs(OUTFIT_SHADERS) do
        self.ui.outfitComboBox:addOption(opts.name, opts)
    end

    for _, opts in pairs(MOUNT_SHADERS) do
        self.ui.mountComboBox:addOption(opts.name, opts)
    end
    for _, opts in pairs(TEXT_SHADERS) do
        self.ui.textComboBox:addOption(opts.name, opts)
    end
end

function ShaderController:onTextComboBoxChange(event)
    -- Apply text shader to local player's name
    -- This affects how the player's name is rendered above their character
    local player = g_game.getLocalPlayer()
    if player then
        -- If using widget-based name rendering
        local infoWidget = player:getWidgetInformation()
        if infoWidget then
            infoWidget:setShader(event.text)
        end
        -- Apply to engine-level name rendering (requires C++ support)
        if player.setNameShader then
            player:setNameShader(event.text)
        end
    end
end
