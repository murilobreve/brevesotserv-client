-- to-do
-- change to ItemsDatabase.setTier(UIitem) to UIitem:setTier()
ItemsDatabase = {}

ItemsDatabase.rarityColors = {
    ["yellow"] = TextColors.yellow,
    ["purple"] = TextColors.purple,
    ["blue"] = TextColors.blue,
    ["green"] = TextColors.green,
    ["grey"] = TextColors.grey,
}

local function getColorForValue(value)
    if value >= 1000000 then
        return "yellow"
    elseif value >= 100000 then
        return "purple"
    elseif value >= 10000 then
        return "blue"
    elseif value >= 1000 then
        return "green"
    elseif value >= 50 then
        return "grey"
    else
        return "white"
    end
end

local function clipfunction(value)
    if value >= 1000000 then
        return "128 0 32 32"
    elseif value >= 100000 then
        return "96 0 32 32"
    elseif value >= 10000 then
        return "64 0 32 32"
    elseif value >= 1000 then
        return "32 0 32 32"
    elseif value >= 50 then
        return "0 0 32 32"
    end
    return ""
end

function ItemsDatabase.getClipAndImagePath(item)
    if not item then
        return nil, nil, nil
    end

    local frameOption = modules.client_options.getOption('framesRarity')
    if frameOption == "none" then
        return nil, nil, nil
    end
    local imagePath = '/images/ui/item'
    local clip = nil

    if type(item) == "number" then
        item = g_things.getThingType(item, ThingCategoryItem)
    end

    if not item then
        return nil, nil, nil
    end

    if item then
        local price = type(item) == "number" and item or (item and item:getMeanPrice()) or 0
        local itemRarity = getColorForValue(price)
        if itemRarity then
            clip = clipfunction(price)
            if clip ~= "" then
                if frameOption == "frames" then
                    imagePath = "/images/ui/rarity_frames"
                elseif frameOption == "corners" then
                    imagePath = "/images/ui/containerslot-coloredges"
                end
            else
                clip = nil
            end
        end
    end

    local clipObject = nil
    if clip then
        local x, y, w, h = clip:match("(%d+) (%d+) (%d+) (%d+)")
        clipObject = { x = tonumber(x), y = tonumber(y), width = tonumber(w), height = tonumber(h) }
    end

    return clip, imagePath, clipObject
end

-- Server rarity grades (Baiak rarity system). The server sends them in the item
-- tooltip as a "#rarity:<grade>" first line, optionally followed by an
-- "#elements:<Tag>[,<Tag>]" line with the item's element tags (Latin names).
ItemsDatabase.itemRarity = {
    uncommon  = { frame = 0, label = "Communis",    color = "#3ddc2e" },
    rare      = { frame = 1, label = "Rarus",       color = "#3d9bff" },
    epic      = { frame = 2, label = "Praeclarus",  color = "#b45cff" },
    legendary = { frame = 3, label = "Legendarius", color = "#ff9a1f" },
    mythic    = { frame = 4, label = "Mythicus",    color = "#66f0ff" },
}

-- frame gem colour per element tag
ItemsDatabase.elementColors = {
    Igneus     = "#ff6a2a",
    Terrenus   = "#6cd13a",
    Fulmineus  = "#b56bff",
    Glacialis  = "#52dcff",
    Sacer      = "#ffd84a",
    Mortifer   = "#8a3dbf",
    Corporalis = "#b8bec6",
}

function ItemsDatabase.getItemRarityGrade(item)
    if type(item) ~= "userdata" or not item.getTooltip then
        return nil
    end
    local grade = item:getTooltip():match("^#rarity:(%a+)")
    if grade and ItemsDatabase.itemRarity[grade] then
        return grade
    end
    return nil
end

-- Element tags of a rarity item, strongest first (at most two).
function ItemsDatabase.getItemElements(item)
    local elements = {}
    if type(item) ~= "userdata" or not item.getTooltip then
        return elements
    end
    local list = item:getTooltip():match("#elements:([%a,]+)")
    if list then
        for tag in list:gmatch("%a+") do
            if ItemsDatabase.elementColors[tag] then
                table.insert(elements, tag)
            end
        end
    end
    return elements
end

-- Hover text without the "#rarity:"/"#elements:" tag lines; rarity items lead
-- with their grade (and elements).
function ItemsDatabase.getItemTooltipText(item)
    if type(item) ~= "userdata" or not item.getTooltip then
        return ""
    end
    local text = item:getTooltip():gsub("^#rarity:%a+\n?", ""):gsub("#elements:[%a,]*\n?", "")
    local grade = ItemsDatabase.getItemRarityGrade(item)
    if grade then
        local label = ItemsDatabase.itemRarity[grade].label
        local elements = ItemsDatabase.getItemElements(item)
        if #elements > 0 then
            label = label .. " - " .. table.concat(elements, ", ")
        end
        text = text:len() > 0 and (label .. "\n" .. text) or label
    end
    return text
end

local GEM_CORNERS = {
    { AnchorTop, AnchorLeft },
    { AnchorTop, AnchorRight },
    { AnchorBottom, AnchorRight },
    { AnchorBottom, AnchorLeft },
}

-- Four gems in the frame corners, painted in the element colours: one
-- element colours all four, two elements alternate.
function ItemsDatabase.setFrameGems(frame, elements)
    if not frame.gems then
        if #elements == 0 then
            return
        end
        frame.gems = {}
        for i, corner in ipairs(GEM_CORNERS) do
            local gem = g_ui.createWidget('UIWidget', frame)
            gem:setPhantom(true)
            gem:setFocusable(false)
            gem:setSize({ width = 7, height = 7 })
            gem:setImageSource('/images/ui/item_rarity_gem')
            gem:addAnchor(corner[1], 'parent', corner[1])
            gem:addAnchor(corner[2], 'parent', corner[2])
            gem:setMargin(1)
            frame.gems[i] = gem
        end
    end
    for i, gem in ipairs(frame.gems) do
        local tag = elements[(i - 1) % 2 + 1] or elements[1]
        if tag then
            gem:setImageColor(ItemsDatabase.elementColors[tag])
            gem:setVisible(true)
        else
            gem:setVisible(false)
        end
    end
end

-- Draws (or hides) the rarity frame over an item widget. It is a child overlay,
-- so it never replaces the widget's own background (inventory slot icons etc).
function ItemsDatabase.setItemRarityFrame(widget, item)
    if not widget then
        return false
    end
    local grade = ItemsDatabase.getItemRarityGrade(item)
    local frame = widget.rarityFrame
    if not grade then
        if frame then
            frame:setVisible(false)
        end
        return false
    end
    if not frame then
        frame = g_ui.createWidget('UIWidget', widget)
        frame:setId('rarityFrame')
        frame:setPhantom(true)
        frame:setFocusable(false)
        frame:fill('parent')
        frame:setImageSource('/images/ui/item_rarity_frames')
        -- keep it below the other overlays (tier stars, counters)
        widget:moveChildToIndex(frame, 1)
        widget.rarityFrame = frame
    end
    frame:setImageClip({ x = ItemsDatabase.itemRarity[grade].frame * 34, y = 0, width = 34, height = 34 })
    ItemsDatabase.setFrameGems(frame, ItemsDatabase.getItemElements(item))
    frame:setVisible(true)
    return true
end

function ItemsDatabase.setRarityItem(widget, item, style)
    if not widget then
        return
    end

    if ItemsDatabase.setItemRarityFrame(widget, item) then
        -- the rarity frame takes the place of the price frame
        local currentSource = widget:getImageSource()
        if currentSource == "/images/ui/rarity_frames" or currentSource == "/images/ui/containerslot-coloredges" then
            widget:setImageClip(nil)
            widget:setImageSource('/images/ui/item')
        end
        return
    end

    if not g_game.getFeature(GameColorizedLootValue) then
        return
    end

    local clip, imagePath = ItemsDatabase.getClipAndImagePath(item)

    if not imagePath then
        -- no frame applies (empty slot or frames disabled): clear a frame left by a previous item,
        -- but only if this widget is currently showing one, to avoid clobbering custom backgrounds
        local currentSource = widget:getImageSource()
        if currentSource == "/images/ui/rarity_frames" or currentSource == "/images/ui/containerslot-coloredges" then
            widget:setImageClip(nil)
            widget:setImageSource('/images/ui/item')
        end
        return
    end

    widget:setImageClip(clip)
    widget:setImageSource(imagePath)
    if style then
        widget:setStyle(style)
    end
end

function ItemsDatabase.getColorForRarity(rarity)
    return ItemsDatabase.rarityColors[rarity] or TextColors.white
end

function ItemsDatabase.setColorLootMessage(text)
    local function coloringLootName(match)
        -- {id|name|grade}: a rarity drop, painted in its rarity colour
        local rId, rName, rGrade = match:match("^(%d+)|(.+)|(%a+)$")
        local rarity = rGrade and ItemsDatabase.itemRarity[rGrade]
        if rarity then
            -- the item name already carries its grade ("a mace Mythicus")
            if not rName:find(rarity.label, 1, true) then
                rName = rName .. " [" .. rarity.label .. "]"
            end
            return "{" .. rName .. ", " .. rarity.color .. "}"
        end

        local id, itemName = match:match("(%d+)|(.+)")
        if not id or not itemName then
            -- If pattern doesn't match itemId|itemName format, return the original match with braces
            return "{" .. match .. "}"
        end

        local itemId = tonumber(id)
        if not itemId then
            return itemName or match
        end

        local thingType = g_things.getThingType(itemId, ThingCategoryItem)
        if not thingType then
            return itemName
        end

        local itemInfo = thingType:getMeanPrice()
        if itemInfo then
            local color = ItemsDatabase.getColorForRarity(getColorForValue(itemInfo))
            return "{" .. itemName .. ", " .. color .. "}"
        else
            return itemName
        end
    end
    return text:gsub("{(.-)}", coloringLootName)
end

function ItemsDatabase.getTierClip(tier)
    local xOffset = (math.min(math.max(tier, 1), 10) - 1) * 9
    return {
        x = xOffset,
        y = 0,
        width = 10,
        height = 9
    }
end

function ItemsDatabase.setTier(widget, item, isSmall)
    if not g_game.getFeature(GameThingUpgradeClassification) or not widget or not widget.tier then
        return
    end
    if isSmall == nil then
        isSmall = true
    end
    local tier = type(item) == "number" and item or (item and item:getTier()) or 0
    if tier <= 0 then
        widget.tier:setVisible(false)
        return
    end
    local config
    if isSmall then
        local normalizedTier = math.min(math.max(tier, 1), 10)
        config = {
            xOffset = (normalizedTier - 1) * 9,
            width = 10,
            height = 9,
            size = "10 9",
            source = '/images/inventory/tiers-strip'
        }
    else
        local normalizedTier = math.min(math.max(tier, 1), 18)
        local xOffset = (normalizedTier - 1) * 18 + 1
        config = {
            xOffset = xOffset,
            width = 18,
            height = 16,
            size = "18 16",
            source = '/images/inventory/tiers-strip-big'
        }
    end

    widget.tier:setImageClip({
        x = config.xOffset,
        y = 0,
        width = config.width,
        height = config.height
    })
    widget.tier:setSize(config.size)
    widget.tier:setImageSource(config.source)
    widget.tier:setImageSize(config.size)
    widget.tier:setVisible(true)
end


