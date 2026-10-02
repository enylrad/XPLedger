--[[----------------------------------------------------------------------------
    XPLedger - Graph widget
    Lightweight chart drawn with plain textures and Line objects (available on
    every supported client). Supports:

      line   one or more series of { x, y } points
      bars   groups of one or two stacked bars (the second one is used to
             compare against another character)

    Usage:
      local graph = ns.Graph:Create(parent)
      graph:SetData({ kind = "line", series = { { points = {...}, color = {r,g,b} } },
                      xFormatter = fn, yFormatter = fn, tooltip = fn })
------------------------------------------------------------------------------]]

local _, ns = ...

local Graph = {}
ns.Graph = Graph

local Theme = ns.Theme

local PADDING_LEFT, PADDING_RIGHT, PADDING_TOP, PADDING_BOTTOM = 44, 10, 8, 20
local GRID_LINES = 4
local MAX_LINE_POINTS = 240
local BAR_GAP_RATIO = 0.3

local GraphMixin = {}

--------------------------------------------------------------------------------
-- Object pools
--------------------------------------------------------------------------------

local function Acquire(self, poolName, factory)
    local pool = self.pools[poolName]
    pool.used = pool.used + 1
    local object = pool.objects[pool.used]
    if not object then
        object = factory()
        pool.objects[pool.used] = object
    end
    object:Show()
    return object
end

local function ReleaseAll(self)
    for _, pool in pairs(self.pools) do
        for i = 1, #pool.objects do
            pool.objects[i]:Hide()
        end
        pool.used = 0
    end
end

--------------------------------------------------------------------------------
-- Scaling helpers
--------------------------------------------------------------------------------

--- Returns a "nice" step (1, 2, 2.5, 5 x 10^n) covering the range in ~n steps.
local function NiceStep(range, steps)
    if range <= 0 then
        return 1
    end
    local raw = range / steps
    local magnitude = 10 ^ math.floor(math.log10(raw))
    local normalized = raw / magnitude
    local nice
    if normalized <= 1 then
        nice = 1
    elseif normalized <= 2 then
        nice = 2
    elseif normalized <= 2.5 then
        nice = 2.5
    elseif normalized <= 5 then
        nice = 5
    else
        nice = 10
    end
    return nice * magnitude
end

--- Expands [low, high] to nice tick boundaries.
local function NiceRange(low, high)
    if high <= low then
        high = low + 1
    end
    local step = NiceStep(high - low, GRID_LINES)
    return math.floor(low / step) * step, math.ceil(high / step) * step, step
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- Creates a graph inside `parent`. Size and anchors are set by the caller.
function Graph:Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    for key, method in pairs(GraphMixin) do
        frame[key] = method
    end

    frame.pools = {
        lines = { used = 0, objects = {} },
        textures = { used = 0, objects = {} },
        labels = { used = 0, objects = {} },
    }

    frame.plot = CreateFrame("Frame", nil, frame)
    frame.plot:SetPoint("TOPLEFT", PADDING_LEFT, -PADDING_TOP)
    frame.plot:SetPoint("BOTTOMRIGHT", -PADDING_RIGHT, PADDING_BOTTOM)
    frame.plot:EnableMouse(true)

    frame.emptyText = Theme:CreateText(frame, "muted", "CENTER")
    frame.emptyText:SetPoint("CENTER", frame.plot)

    -- Hover marker (line graphs) and highlight (bar graphs).
    frame.marker = Theme:CreateTexture(frame.plot, { 1, 1, 1, 0.25 }, "OVERLAY")
    frame.marker:SetWidth(1)
    frame.marker:Hide()
    frame.markerDot = Theme:CreateTexture(frame.plot, Theme.colors.text, "OVERLAY", 2)
    frame.markerDot:SetSize(5, 5)
    frame.markerDot:Hide()
    frame.highlight = Theme:CreateTexture(frame.plot, { 1, 1, 1, 0.05 }, "BACKGROUND")
    frame.highlight:Hide()

    frame.plot:SetScript("OnEnter", function() frame.hovering = true end)
    frame.plot:SetScript("OnLeave", function()
        frame.hovering = false
        frame:ClearHover()
    end)
    frame.plot:SetScript("OnUpdate", function()
        if frame.hovering then
            frame:UpdateHover()
        end
    end)
    frame:SetScript("OnSizeChanged", function() frame:Render() end)
    return frame
end

function GraphMixin:SetData(data)
    self.data = data
    self:Render()
end

function GraphMixin:Label(text, justify)
    local label = Acquire(self, "labels", function()
        return Theme:CreateText(self, "small")
    end)
    label:SetJustifyH(justify or "LEFT")
    label:ClearAllPoints()
    label:SetText(text)
    return label
end

function GraphMixin:Texture(color, layer)
    local texture = Acquire(self, "textures", function()
        return Theme:CreateTexture(self.plot, Theme.colors.grid, "ARTWORK")
    end)
    texture:SetDrawLayer(layer or "ARTWORK")
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    texture:ClearAllPoints()
    return texture
end

function GraphMixin:Line(color, thickness)
    local line = Acquire(self, "lines", function()
        local created = self.plot:CreateLine(nil, "ARTWORK", nil, 1)
        created:SetTexture("Interface\\Buttons\\WHITE8X8")
        return created
    end)
    line:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    line:SetThickness(thickness or 2)
    return line
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

function GraphMixin:Render()
    ReleaseAll(self)
    self:ClearHover()
    local data = self.data
    local width, height = self.plot:GetWidth(), self.plot:GetHeight()
    if not data or not width or width <= 0 or height <= 0 then
        return
    end

    local hasData
    if data.kind == "bars" then
        hasData = data.groups and #data.groups > 0
    else
        hasData = false
        for _, series in ipairs(data.series or {}) do
            if #series.points >= 2 then
                hasData = true
            end
        end
    end
    self.emptyText:SetText(hasData and "" or (data.emptyText or ns.L["GRAPH_NO_DATA"]))
    if not hasData then
        return
    end

    if data.kind == "bars" then
        self:RenderBars(width, height)
    else
        self:RenderLines(width, height)
    end
end

--- Draws the horizontal grid with its value labels.
function GraphMixin:RenderGrid(yMin, yMax, step, height, formatter)
    local value = yMin
    while value <= yMax + step * 0.001 do
        local y = (value - yMin) / (yMax - yMin) * height
        local line = self:Texture(Theme.colors.grid, "BACKGROUND")
        line:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, y)
        line:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", 0, y)
        line:SetHeight(1)

        local label = self:Label(formatter(value), "RIGHT")
        label:SetPoint("RIGHT", self.plot, "BOTTOMLEFT", -6, y)
        value = value + step
    end
end

--- Reduces a point list to at most `limit` points keeping the shape.
local function Downsample(points, limit)
    if #points <= limit then
        return points
    end
    local result = {}
    local stride = #points / limit
    for i = 1, limit do
        result[i] = points[math.floor((i - 1) * stride) + 1]
    end
    result[#result] = points[#points]
    return result
end

function GraphMixin:RenderLines(width, height)
    local data = self.data
    local xMin, xMax, yMin, yMax = math.huge, -math.huge, math.huge, -math.huge
    for _, series in ipairs(data.series) do
        for _, point in ipairs(series.points) do
            xMin, xMax = math.min(xMin, point[1]), math.max(xMax, point[1])
            yMin, yMax = math.min(yMin, point[2]), math.max(yMax, point[2])
        end
    end
    if data.yMin then yMin = math.min(yMin, data.yMin) end
    if data.yMax then yMax = math.max(yMax, data.yMax) end
    if xMax <= xMin then
        xMax = xMin + 1
    end

    local step
    yMin, yMax, step = NiceRange(yMin, yMax)
    self:RenderGrid(yMin, yMax, step, height, data.yFormatter or ns.FormatNumber)

    local function ToScreen(point)
        return (point[1] - xMin) / (xMax - xMin) * width, (point[2] - yMin) / (yMax - yMin) * height
    end

    self.scaled = {}
    for index, series in ipairs(data.series) do
        local points = Downsample(series.points, MAX_LINE_POINTS)
        local scaled = {}
        for i, point in ipairs(points) do
            local x, y = ToScreen(point)
            scaled[i] = { x = x, y = y, point = point }
            if i > 1 then
                local line = self:Line(series.color, series.thickness or 2)
                line:SetStartPoint("BOTTOMLEFT", self.plot, scaled[i - 1].x, scaled[i - 1].y)
                line:SetEndPoint("BOTTOMLEFT", self.plot, x, y)
            end
        end
        self.scaled[index] = scaled
    end

    -- X axis labels at the start, middle and end.
    local formatter = data.xFormatter or tostring
    for i = 0, 2 do
        local xValue = xMin + (xMax - xMin) * i / 2
        local justify = i == 0 and "LEFT" or (i == 2 and "RIGHT" or "CENTER")
        local label = self:Label(formatter(xValue), justify)
        local anchor = i == 0 and "TOPLEFT" or (i == 2 and "TOPRIGHT" or "TOP")
        label:SetPoint(anchor, self.plot, "BOTTOMLEFT", width * i / 2, -5)
    end
end

function GraphMixin:RenderBars(width, height)
    local data = self.data
    local groups = data.groups
    local yMax = 0
    for _, group in ipairs(groups) do
        for _, stack in ipairs(group.stacks) do
            local total = 0
            for _, segment in ipairs(stack) do
                total = total + segment.value
            end
            yMax = math.max(yMax, total)
        end
    end

    local yMin, step
    yMin, yMax, step = NiceRange(0, yMax)
    self:RenderGrid(yMin, yMax, step, height, data.yFormatter or ns.FormatNumber)

    local slot = width / #groups
    local groupWidth = slot * (1 - BAR_GAP_RATIO)
    local labelEvery = math.max(1, math.ceil(#groups / math.max(1, math.floor(width / 26))))
    self.barSlots = {}

    for index, group in ipairs(groups) do
        local left = (index - 1) * slot + (slot - groupWidth) / 2
        local stackCount = #group.stacks
        local barWidth = math.max(1, groupWidth / stackCount - (stackCount > 1 and 1 or 0))
        for stackIndex, stack in ipairs(group.stacks) do
            local x = left + (stackIndex - 1) * (barWidth + 1)
            local base = 0
            for _, segment in ipairs(stack) do
                if segment.value > 0 then
                    local segmentHeight = segment.value / yMax * height
                    local bar = self:Texture(segment.color)
                    bar:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", x, base)
                    bar:SetSize(barWidth, math.max(1, segmentHeight))
                    base = base + segmentHeight
                end
            end
        end
        if (index - 1) % labelEvery == 0 then
            local label = self:Label(group.label, "CENTER")
            label:SetPoint("TOP", self.plot, "BOTTOMLEFT", (index - 0.5) * slot, -5)
        end
        self.barSlots[index] = { left = (index - 1) * slot, width = slot, group = group }
    end
end

--------------------------------------------------------------------------------
-- Hover
--------------------------------------------------------------------------------

function GraphMixin:ClearHover()
    self.marker:Hide()
    self.markerDot:Hide()
    self.highlight:Hide()
    if self.hoverOwner and GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
    self.hoverIndex = nil
    self.hoverOwner = nil
end

--- Returns the cursor position relative to the plot area, in plot units.
function GraphMixin:GetCursorOffset()
    local scale = self.plot:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    return cursorX / scale - self.plot:GetLeft(), cursorY / scale - self.plot:GetBottom()
end

function GraphMixin:UpdateHover()
    local data = self.data
    if not data or not data.tooltip or not self.plot:GetLeft() then
        return
    end
    local x = self:GetCursorOffset()

    if data.kind == "bars" then
        if not self.barSlots then
            return
        end
        local index = math.floor(x / (self.plot:GetWidth() / #self.barSlots)) + 1
        local slot = self.barSlots[index]
        if not slot or index == self.hoverIndex then
            return
        end
        self.hoverIndex = index
        self.highlight:ClearAllPoints()
        self.highlight:SetPoint("TOPLEFT", self.plot, "TOPLEFT", slot.left, 0)
        self.highlight:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", slot.left, 0)
        self.highlight:SetWidth(slot.width)
        self.highlight:Show()
        self:ShowTooltip(slot.group)
        return
    end

    local scaled = self.scaled and self.scaled[1]
    if not scaled or #scaled == 0 then
        return
    end
    -- Nearest point of the first series by horizontal distance.
    local bestIndex, bestDistance = 1, math.huge
    for i = 1, #scaled do
        local distance = math.abs(scaled[i].x - x)
        if distance < bestDistance then
            bestIndex, bestDistance = i, distance
        end
    end
    if bestIndex == self.hoverIndex then
        return
    end
    self.hoverIndex = bestIndex
    local entry = scaled[bestIndex]
    self.marker:ClearAllPoints()
    self.marker:SetPoint("TOP", self.plot, "TOPLEFT", entry.x, 0)
    self.marker:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", entry.x, 0)
    self.marker:Show()
    self.markerDot:ClearAllPoints()
    self.markerDot:SetPoint("CENTER", self.plot, "BOTTOMLEFT", entry.x, entry.y)
    self.markerDot:Show()
    self:ShowTooltip(entry.point)
end

function GraphMixin:ShowTooltip(item)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    self.data.tooltip(GameTooltip, item)
    GameTooltip:Show()
    self.hoverOwner = true
end
