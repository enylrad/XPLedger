--[[----------------------------------------------------------------------------
    XPLedger - Minimal skin
    Flat, self-drawn look made of plain textures. It does not depend on any
    Blizzard template, which also makes it the fallback of the Blizzard skin
    for widgets a client does not provide.
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = ns.Theme
local Skin = {}

Skin.palette = {
    background = { 0.05, 0.06, 0.08, 0.92 },
    window = { 0.05, 0.06, 0.08, 0.96 },
    surface = { 0.10, 0.11, 0.14, 0.95 },
    surfaceHover = { 0.15, 0.16, 0.20, 0.95 },
    border = { 1, 1, 1, 0.08 },
    accent = { 0.31, 0.76, 0.97, 1 },
    xp = { 0.31, 0.76, 0.97, 1 },
    rested = { 0.47, 0.42, 0.96, 1 },
    levelBox = { 0.31, 0.76, 0.97, 0.14 },
    text = { 0.93, 0.94, 0.96, 1 },
    muted = { 0.58, 0.61, 0.67, 1 },
    grid = { 1, 1, 1, 0.06 },
    track = { 1, 1, 1, 0.07 },
    selection = { 0.31, 0.76, 0.97, 0.12 },
    warning = { 0.98, 0.62, 0.25, 1 },
    better = { 0.37, 0.80, 0.48, 1 },
    worse = { 0.91, 0.37, 0.34, 1 },
}

Skin.metrics = {
    launcher = { width = 172, height = 38, inset = 0, barHeight = 3 },
}

-- Font size and palette color of every text role.
local ROLES = {
    title = { 15, "text" },
    heading = { 12, "text" },
    normal = { 12, "text" },
    value = { 16, "text" },
    label = { 11, "muted" },
    muted = { 11, "muted" },
    small = { 10, "muted" },
    accent = { 12, "accent" },
}

--------------------------------------------------------------------------------
-- Flat drawing helpers (local: never dispatched through the active skin)
--------------------------------------------------------------------------------

local function Flat(frame, background, border)
    local palette = Theme.colors
    background = background or palette.background
    border = border or palette.border

    local bg = Theme:CreateTexture(frame, background, "BACKGROUND", -8)
    bg:SetAllPoints()
    frame.flatBackground = bg

    local edges = {}
    for i = 1, 4 do
        edges[i] = Theme:CreateTexture(frame, border, "BORDER", 7)
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    frame.flatEdges = edges
    frame.flatBorderColor = border
end

local function SetFlatBorder(frame, color, alpha)
    for _, edge in ipairs(frame.flatEdges or {}) do
        edge:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
    end
end

local function SetFlatBackground(frame, color)
    if frame.flatBackground then
        frame.flatBackground:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
end

--------------------------------------------------------------------------------
-- Text and panels
--------------------------------------------------------------------------------

function Skin:CreateText(parent, role, justify, layer)
    local spec = ROLES[role] or ROLES.normal
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFont(self.FONT, spec[1], "")
    local color = Theme.colors[spec[2]]
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    text:SetJustifyH(justify or "LEFT")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.7)
    text:SetWordWrap(false)
    return text
end

local PANEL_COLORS = {
    launcher = { "background", "border" },
    tile = { "surface", "border" },
    menu = { { 0.07, 0.08, 0.10, 0.98 }, { 1, 1, 1, 0.15 } },
}

function Skin:CreatePanel(parent, variant, frameType, name)
    local frame = CreateFrame(frameType or "Frame", name, parent)
    local colors = PANEL_COLORS[variant] or PANEL_COLORS.tile
    local background = type(colors[1]) == "string" and Theme.colors[colors[1]] or colors[1]
    local border = type(colors[2]) == "string" and Theme.colors[colors[2]] or colors[2]
    Flat(frame, background, border)
    return frame
end

function Skin:SetHighlight(panel, enabled)
    if enabled then
        SetFlatBorder(panel, Theme.colors.accent, 0.5)
    else
        SetFlatBorder(panel, panel.flatBorderColor or Theme.colors.border)
    end
end

function Skin:BrandTitle()
    return Theme.Hex(Theme.colors.accent) .. "XP|rLedger"
end

--------------------------------------------------------------------------------
-- Window and tabs
--------------------------------------------------------------------------------

local WINDOW_PADDING, WINDOW_HEADER = 14, 72

function Skin:CreateWindow(name, contentWidth, contentHeight)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(contentWidth + WINDOW_PADDING * 2, contentHeight + WINDOW_HEADER + WINDOW_PADDING)
    Flat(frame, Theme.colors.window, { 1, 1, 1, 0.10 })

    local title = self:CreateText(frame, "title")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(self:BrandTitle())

    frame.subtitle = self:CreateText(frame, "muted")
    frame.subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -8, -8)
    close.text = self:CreateText(close, "muted", "CENTER")
    close.text:SetFont(self.FONT, 16, "")
    close.text:SetPoint("CENTER")
    close.text:SetText("×")
    close:SetScript("OnEnter", function() close.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function()
        local muted = Theme.colors.muted
        close.text:SetTextColor(muted[1], muted[2], muted[3])
    end)
    close:SetScript("OnClick", function() frame:Hide() end)

    local separator = Theme:CreateTexture(frame, Theme.colors.border)
    separator:SetPoint("TOPLEFT", 1, -62)
    separator:SetPoint("TOPRIGHT", -1, -62)
    separator:SetHeight(1)

    frame.contentArea = CreateFrame("Frame", nil, frame)
    frame.contentArea:SetPoint("TOPLEFT", WINDOW_PADDING, -WINDOW_HEADER)
    frame.contentArea:SetSize(contentWidth, contentHeight)

    function frame:SetWindowTitle() end
    return frame
end

function Skin:CreateTab(window, label, onClick)
    local tab = CreateFrame("Button", nil, window)
    tab:SetHeight(24)
    tab.text = self:CreateText(tab, "normal", "CENTER")
    tab.text:SetPoint("CENTER", 0, 1)
    self:SetLocalizedText(tab.text, label)

    tab.underline = Theme:CreateTexture(tab, Theme.colors.accent)
    tab.underline:SetPoint("BOTTOMLEFT", 4, 0)
    tab.underline:SetPoint("BOTTOMRIGHT", -4, 0)
    tab.underline:SetHeight(2)
    tab.underline:Hide()

    function tab:SetSelected(selected)
        self.selected = selected
        self.underline:SetShown(selected)
        local color = selected and Theme.colors.text or Theme.colors.muted
        self.text:SetTextColor(color[1], color[2], color[3])
    end

    function tab:UpdateWidth()
        self:SetWidth(math.max(60, self.text:GetStringWidth() + 20))
    end

    tab:SetScript("OnEnter", function(self)
        local color = Theme.colors.text
        self.text:SetTextColor(color[1], color[2], color[3])
    end)
    tab:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    tab:SetScript("OnClick", onClick)
    tab:SetSelected(false)
    tab:UpdateWidth()
    return tab
end

function Skin:PlaceTab(window, tab, previous)
    if previous then
        tab:SetPoint("LEFT", previous, "RIGHT", 4, 0)
    else
        tab:SetPoint("TOPLEFT", window, "TOPLEFT", 10, -38)
    end
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

function Skin:CreateButton(parent, label, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 100, height or 22)
    Flat(button, Theme.colors.surface)

    button.text = self:CreateText(button, "normal", "CENTER")
    button.text:SetFont(self.FONT, 11, "")
    button.text:SetPoint("CENTER")
    if label then
        self:SetLocalizedText(button.text, label)
    end

    button:SetScript("OnEnter", function(selfButton) SetFlatBackground(selfButton, Theme.colors.surfaceHover) end)
    button:SetScript("OnLeave", function(selfButton) SetFlatBackground(selfButton, Theme.colors.surface) end)
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    return button
end

--- Row of small toggle buttons where exactly one is selected.
function Skin:CreateSegmented(parent, options, getter, setter)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(20)
    holder.buttons = {}

    function holder:Refresh()
        local current = getter()
        local width = 0
        for _, button in ipairs(self.buttons) do
            local selected = button.value == current
            local color = selected and Theme.colors.accent or Theme.colors.muted
            button.text:SetTextColor(color[1], color[2], color[3])
            SetFlatBorder(button, selected and Theme.colors.accent or Theme.colors.border, selected and 0.6 or nil)
            button:SetWidth(button.text:GetStringWidth() + 16)
            width = width + button:GetWidth() + 2
        end
        self:SetWidth(math.max(1, width - 2))
    end

    local previous
    for _, option in ipairs(options) do
        local button = Skin.CreateButton(Theme, holder, option.label, 40, 20, function()
            setter(option.value)
            holder:Refresh()
        end)
        button.text:SetFont(Theme.FONT, 10, "")
        button.value = option.value
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            button:SetPoint("LEFT")
        end
        holder.buttons[#holder.buttons + 1] = button
        previous = button
    end

    ns:RegisterMessage("XPL_LOCALE_CHANGED", function() holder:Refresh() end)
    holder:Refresh()
    return holder
end

--- Stat tile: a small caption above a large value.
function Skin:CreateStat(parent, label)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetHeight(46)
    Flat(tile, Theme.colors.surface)

    tile.label = self:CreateText(tile, "label")
    tile.label:SetFont(self.FONT, 10, "")
    tile.label:SetPoint("TOPLEFT", 10, -8)
    self:SetLocalizedText(tile.label, label)

    tile.value = self:CreateText(tile, "value")
    tile.value:SetPoint("BOTTOMLEFT", 10, 8)
    tile.value:SetPoint("RIGHT", -8, 0)
    tile.label:SetPoint("RIGHT", -8, 0)
    self:AttachTileTooltip(tile)
    return tile
end

--------------------------------------------------------------------------------
-- Experience bar
--------------------------------------------------------------------------------

function Skin:CreateXPBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(Theme.metrics.launcher.barHeight)

    local track = Theme:CreateTexture(bar, Theme.colors.track, "ARTWORK", 0)
    track:SetAllPoints()
    local rested = Theme:CreateTexture(bar, { Theme.colors.rested[1], Theme.colors.rested[2], Theme.colors.rested[3], 0.55 }, "ARTWORK", 1)
    rested:SetPoint("TOP")
    rested:SetPoint("BOTTOM")
    local fill = Theme:CreateTexture(bar, Theme.colors.xp, "ARTWORK", 2)
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")

    --- Updates the bar. Both values are fractions of the level (0..1).
    function bar:SetProgress(progress, restedEnd)
        local width = self:GetWidth()
        if not width or width <= 0 then
            return
        end
        fill:SetWidth(math.max(1, width * progress))
        fill:SetShown(progress > 0)
        rested:ClearAllPoints()
        rested:SetPoint("TOPLEFT", self, "TOPLEFT", width * progress, 0)
        rested:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", width * progress, 0)
        rested:SetWidth(math.max(1, width * (restedEnd - progress)))
        rested:SetShown(restedEnd > progress)
    end
    return bar
end

--------------------------------------------------------------------------------
-- Checkbox
--------------------------------------------------------------------------------

function Skin:CreateCheckbox(parent, label, getter, setter)
    local check = CreateFrame("Button", nil, parent)
    check:SetHeight(20)

    local box = CreateFrame("Frame", nil, check)
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    Flat(box, Theme.colors.surface, { 1, 1, 1, 0.2 })

    local mark = Theme:CreateTexture(box, Theme.colors.accent)
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)

    check.text = self:CreateText(check, "normal")
    check.text:SetPoint("LEFT", box, "RIGHT", 8, 0)
    self:SetLocalizedText(check.text, label)

    function check:Refresh()
        mark:SetShown(getter() and true or false)
        self:SetWidth(22 + self.text:GetStringWidth())
    end

    check:SetScript("OnClick", function(self)
        setter(not getter())
        self:Refresh()
    end)
    check:SetScript("OnEnter", function() SetFlatBorder(box, Theme.colors.accent) end)
    check:SetScript("OnLeave", function() SetFlatBorder(box, { 1, 1, 1, 0.2 }) end)
    check:Refresh()
    return check
end

--------------------------------------------------------------------------------
-- Slider
--------------------------------------------------------------------------------

--- Horizontal slider with a label and a formatted value.
function Skin:CreateSlider(parent, label, minValue, maxValue, step, formatter, getter, setter)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(220, 40)

    holder.label = self:CreateText(holder, "normal")
    holder.label:SetPoint("TOPLEFT")
    self:SetLocalizedText(holder.label, label)

    holder.value = self:CreateText(holder, "accent", "RIGHT")
    holder.value:SetPoint("TOPRIGHT")

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("BOTTOMLEFT", 0, 6)
    slider:SetPoint("BOTTOMRIGHT", 0, 6)
    slider:SetHeight(12)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end

    local track = Theme:CreateTexture(slider, Theme.colors.track, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(Theme.WHITE)
    thumb:SetVertexColor(unpack(Theme.colors.accent))
    thumb:SetSize(8, 12)
    slider:SetThumbTexture(thumb)

    local updating = false
    function holder:Refresh()
        updating = true
        slider:SetValue(getter())
        updating = false
        holder.value:SetText(formatter(getter()))
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        holder.value:SetText(formatter(value))
        if not updating then
            setter(value)
        end
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(ns.Clamp(self:GetValue() + delta * step, minValue, maxValue))
    end)

    holder.slider = slider
    holder:Refresh()
    return holder
end

--------------------------------------------------------------------------------
-- Dropdown
--------------------------------------------------------------------------------

--- Self-drawn dropdown. `options` is a function returning an array of
--- { value = any, label = string, color = {r,g,b}? } evaluated on open.
--- The button and the menu panel come from the active skin, so the Blizzard
--- skin reuses this implementation with native looking parts.
function Skin:CreateDropdown(parent, width, options, getter, setter)
    local dropdown = self:CreateButton(parent, nil, width, 22)
    local text = dropdown.text or dropdown:GetFontString()
    text:ClearAllPoints()
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", -20, 0)
    text:SetJustifyH("LEFT")

    local arrow = self:CreateText(dropdown, "small", "RIGHT")
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")

    local menu = self:CreatePanel(dropdown, "menu")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(width)
    menu:EnableMouse(true)
    menu:Hide()
    menu:SetScript("OnHide", function() Theme:GetMenuBlocker():Hide() end)
    menu.items = {}

    function dropdown:Refresh()
        local current = getter()
        for _, option in ipairs(options()) do
            if option.value == current then
                text:SetText(option.label)
                return
            end
        end
        text:SetText(tostring(current))
    end

    local function OpenMenu()
        local list = options()
        local current = getter()
        local palette = Theme.colors
        for i, option in ipairs(list) do
            local item = menu.items[i]
            if not item then
                item = CreateFrame("Button", nil, menu)
                item:SetHeight(20)
                item.highlight = Theme:CreateTexture(item, { 1, 1, 1, 0.08 }, "HIGHLIGHT")
                item.highlight:SetAllPoints()
                item.text = Theme:CreateText(item, "normal")
                item.text:SetPoint("LEFT", 8, 0)
                item.text:SetPoint("RIGHT", -8, 0)
                menu.items[i] = item
            end
            item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
            item:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 20)
            item.text:SetText(option.label)
            local color = option.value == current and palette.accent or (option.color or palette.text)
            item.text:SetTextColor(color[1], color[2], color[3])
            item:SetScript("OnClick", function()
                setter(option.value)
                Theme:CloseMenus()
                dropdown:Refresh()
            end)
            item:Show()
        end
        for i = #list + 1, #menu.items do
            menu.items[i]:Hide()
        end
        menu:SetHeight(#list * 20 + 8)

        Theme:CloseMenus()
        local blocker = Theme:GetMenuBlocker()
        blocker:Show()
        menu:SetFrameLevel(blocker:GetFrameLevel() + 10)
        menu:Show()
        Theme.openMenu = menu
    end

    dropdown:SetScript("OnClick", function()
        if menu:IsShown() then
            Theme:CloseMenus()
        else
            OpenMenu()
        end
    end)
    dropdown:HookScript("OnHide", function() menu:Hide() end)

    ns:RegisterMessage("XPL_LOCALE_CHANGED", function() dropdown:Refresh() end)
    dropdown:Refresh()
    return dropdown
end

Theme:RegisterSkin("minimal", Skin)
