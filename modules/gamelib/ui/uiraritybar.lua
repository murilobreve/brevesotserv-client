-- @docclass
-- The odds of a rarity roll (the Quests and Bosses windows): RarityOdds turns
-- the server's numbers into parts, one per grade (ItemsDatabase.itemRarity's
-- names and colours), and UIRarityBar draws them as a bar split by grade,
-- each part as wide as its chance.
UIRarityBar = extends(UIWidget, 'UIRarityBar')

RarityOdds = {}

local NONE_COLOR = '#3b3449'
local NONE_TEXT_COLOR = '#a39bb6'
local MIN_PART = 2 -- px: a chance of 0.05% still shows

-- 75 -> "75%", 4.5 -> "4,5%", 0.05 -> "0,05%"
function RarityOdds.percent(value)
    value = math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
    local text
    if value == math.floor(value) then
        text = string.format('%d', value)
    else
        text = string.format(value >= 1 and '%.1f' or '%.2f', value)
        if value >= 1 and tonumber(text) ~= value then
            text = string.format('%.2f', value)
        end
        text = text:gsub('0+$', ''):gsub('%.$', '')
    end
    return (text:gsub('%.', ',')) .. '%'
end

-- the parts of a roll: `grades` the server's odds of each grade ({ key,
-- name, chance } in percent), `chance` the percent that the roll gives a
-- rarity item at all (nil: it always does); the rest has no rarity
function RarityOdds.parts(grades, chance)
    local parts = {}
    local share = chance and chance / 100 or 1
    if chance and chance < 100 then
        parts[#parts + 1] = { key = 'none', label = tr('No rarity'), chance = 100 - chance, color = NONE_COLOR, textColor = NONE_TEXT_COLOR }
    end
    for _, grade in ipairs(grades or {}) do
        local look = ItemsDatabase.itemRarity[grade.key]
        parts[#parts + 1] = {
            key = grade.key,
            label = look and look.label or grade.name,
            chance = (tonumber(grade.chance) or 0) * share,
            color = look and look.color or '#ffffff',
        }
    end
    return parts
end

-- "{Communis 10%, #63c08a}   {Rarus 8%, #4f8fe8} ..." for setColoredText
function RarityOdds.legend(parts, separator)
    local out = {}
    for _, part in ipairs(parts or {}) do
        if part.chance > 0 then
            out[#out + 1] = string.format('{%s %s, %s}', part.label, RarityOdds.percent(part.chance), part.textColor or part.color)
        end
    end
    return table.concat(out, separator or '   ')
end

function UIRarityBar.create()
    local bar = UIRarityBar.internalCreate()
    bar:setFocusable(false)
    bar.cells = {}
    return bar
end

function UIRarityBar:setOdds(parts)
    self:destroyChildren()
    self.cells = {}
    for _, part in ipairs(parts or {}) do
        if part.chance > 0 then
            local cell = g_ui.createWidget('UIWidget', self)
            cell:setBackgroundColor(part.color)
            cell:setTooltip(string.format('%s %s', part.label, RarityOdds.percent(part.chance)))
            cell:addAnchor(AnchorTop, 'parent', AnchorTop)
            cell:addAnchor(AnchorBottom, 'parent', AnchorBottom)
            cell:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            cell.chance = part.chance
            table.insert(self.cells, cell)
        end
    end
    self:layoutCells()
end

-- each part as wide as its chance, at least MIN_PART; what the minimums and
-- the rounding add or leave comes off the widest part
function UIRarityBar:layoutCells()
    local width = self:getWidth() - self:getPaddingLeft() - self:getPaddingRight()
    if not self.cells or #self.cells == 0 or width <= 0 then
        return
    end
    local total = 0
    for _, cell in ipairs(self.cells) do
        total = total + cell.chance
    end
    local widths, used, widest = {}, 0, 1
    for index, cell in ipairs(self.cells) do
        widths[index] = math.max(MIN_PART, math.floor(cell.chance / total * width + 0.5))
        used = used + widths[index]
        if widths[index] > widths[widest] then
            widest = index
        end
    end
    widths[widest] = math.max(MIN_PART, widths[widest] + width - used)
    local x = 0
    for index, cell in ipairs(self.cells) do
        cell:setMarginLeft(x)
        cell:setWidth(widths[index])
        x = x + widths[index]
    end
end

function UIRarityBar:onGeometryChange(oldRect, newRect)
    if oldRect.width ~= newRect.width then
        self:layoutCells()
    end
end
