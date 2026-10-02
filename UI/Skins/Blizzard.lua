--[[----------------------------------------------------------------------------
    XPLedger - Blizzard skin (default)
    Native look: frames are built from the client's own templates, font
    objects and art, so the addon automatically matches the game it runs in
    (Retail's modern frames, Forever's art, Classic's dialogs).

    Every template is probed with Theme.HasTemplate before use. When a client
    lacks one, the widget falls back to classic Blizzard textures or, as a last
    resort, to the Minimal skin implementation (which then picks up this
    skin's palette and fonts).
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = ns.Theme
local Skin = {}

Skin.palette = {
    background = { 0, 0, 0, 0.85 },
    window = { 0.05, 0.05, 0.05, 0.95 },
    surface = { 0.08, 0.08, 0.08, 0.85 },
    surfaceHover = { 0.16, 0.16, 0.16, 0.9 },
    border = { 1, 0.82, 0, 0.22 },
    accent = { 1, 0.82, 0, 1 },
    xp = { 0.58, 0.0, 0.55, 1 },        -- Blizzard experience bar, normal state
    rested = { 0.0, 0.39, 0.88, 1 },    -- Blizzard experience bar, rested state
    levelBox = { 0, 0, 0, 0.35 },
    text = { 1, 1, 1, 1 },
    muted = { 0.62, 0.62, 0.62, 1 },
    grid = { 1, 1, 1, 0.07 },
    track = { 0, 0, 0, 0.55 },
    selection = { 1, 0.82, 0, 0.12 },
    warning = { 1, 0.5, 0.25, 1 },
    better = { 0.25, 1, 0.25, 1 },      -- GREEN_FONT_COLOR-like
    worse = { 1, 0.25, 0.25, 1 },       -- RED_FONT_COLOR-like
}

Skin.metrics = {
    launcher = { width = 184, height = 46, inset = 5, barHeight = 5 },
}

-- Font object of every text role. These exist in every client and carry each
-- flavor's own typeface, size and color.
local FONT_ROLES = {
    title = "GameFontNormalLarge",
    heading = "GameFontNormal",
    normal = "GameFontHighlight",
    value = "GameFontHighlightLarge",
    label = "GameFontNormalSmall",
    muted = "GameFontDisable",
    small = "GameFontDisableSmall",
    accent = "GameFontNormal",
}

local TOOLTIP_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local SLIDER_BACKDROP = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

local STATUSBAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local function Minimal()
    return Theme.skins.minimal
end

local function BackdropTemplate()
    return BackdropTemplateMixin and "BackdropTemplate" or nil
end

--------------------------------------------------------------------------------
-- Text and panels
--------------------------------------------------------------------------------

function Skin:CreateText(parent, role, justify, layer)
    local fontObject = FONT_ROLES[role] or FONT_ROLES.normal
    if not _G[fontObject] then
        fontObject = "GameFontNormal"
    end
    local text = parent:CreateFontString(nil, layer or "OVERLAY", fontObject)
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

--- Creates a frame with the game's tooltip frame (border and background).
function Skin:CreatePanel(parent, variant, frameType, name)
    if Theme.HasTemplate("TooltipBackdropTemplate") then
        local frame = CreateFrame(frameType or "Frame", name, parent, "TooltipBackdropTemplate")
        frame.nativeBackdrop = true
        return frame
    end
    local frame = CreateFrame(frameType or "Frame", name, parent, BackdropTemplate())
    if Theme.ApplyBackdrop(frame, TOOLTIP_BACKDROP) then
        frame:SetBackdropColor(0, 0, 0, variant == "menu" and 0.95 or 0.85)
        frame:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    end
    return frame
end

function Skin:SetHighlight(panel, enabled)
    local r, g, b = 0.8, 0.8, 0.8
    if enabled then
        r, g, b = 1, 0.82, 0
    elseif panel.nativeBackdrop and TOOLTIP_DEFAULT_COLOR then
        r, g, b = TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b
    end
    if panel.NineSlice and panel.NineSlice.SetBorderColor then
        panel.NineSlice:SetBorderColor(r, g, b, 1)
    elseif panel.SetBackdropBorderColor then
        panel:SetBackdropBorderColor(r, g, b, 1)
    end
end

function Skin:BrandTitle()
    return "XPLedger"
end

--------------------------------------------------------------------------------
-- Window and tabs
--------------------------------------------------------------------------------

-- Layout of the window around the content area.
local INSET_TOP, INSET_SIDE, INSET_BOTTOM, CONTENT_PADDING = 60, 6, 6, 10

local function SetTemplateTitle(frame, text)
    if frame.SetTitle then
        frame:SetTitle(text)
    elseif frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText(text)
    elseif frame.TitleText then
        frame.TitleText:SetText(text)
    elseif frame:GetName() and _G[frame:GetName() .. "TitleText"] then
        _G[frame:GetName() .. "TitleText"]:SetText(text)
    end
end

--- Classic gold dialog window, used when ButtonFrameTemplate is missing.
local function CreateDialogWindow(self, name)
    local frame = CreateFrame("Frame", name, UIParent, BackdropTemplate())
    Theme.ApplyBackdrop(frame, DIALOG_BACKDROP)

    local title = self:CreateText(frame, "title", "CENTER")
    title:SetPoint("TOP", 0, -16)
    frame.dialogTitle = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    frame.CloseButton = close

    local inset = CreateFrame("Frame", nil, frame)
    local insetBackground = Theme:CreateTexture(inset, { 0, 0, 0, 0.45 }, "BACKGROUND")
    insetBackground:SetAllPoints()
    frame.Inset = inset

    function frame:SetWindowTitle(text)
        self.dialogTitle:SetText(text)
    end
    return frame, 14, 4
end

function Skin:CreateWindow(name, contentWidth, contentHeight)
    local frame, sideExtra, topExtra
    if Theme.HasTemplate("ButtonFrameTemplate") then
        frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
        if ButtonFrameTemplate_HidePortrait then
            ButtonFrameTemplate_HidePortrait(frame)
        end
        if ButtonFrameTemplate_HideButtonBar then
            ButtonFrameTemplate_HideButtonBar(frame)
        end
        function frame:SetWindowTitle(text)
            SetTemplateTitle(self, text)
        end
        sideExtra, topExtra = 0, 0
    else
        frame, sideExtra, topExtra = CreateDialogWindow(self, name)
    end

    local side = INSET_SIDE + sideExtra
    local top = INSET_TOP + topExtra
    local bottom = INSET_BOTTOM + sideExtra
    frame:SetSize(contentWidth + (side + CONTENT_PADDING) * 2, contentHeight + top + bottom + CONTENT_PADDING * 2)

    local inset = frame.Inset
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", side, -top)
    inset:SetPoint("BOTTOMRIGHT", -side, bottom)
    frame.inset = inset

    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    end

    frame.subtitle = self:CreateText(frame, "label", "RIGHT")
    frame.subtitle:SetPoint("BOTTOMRIGHT", inset, "TOPRIGHT", -6, 8)

    frame.contentArea = CreateFrame("Frame", nil, inset)
    frame.contentArea:SetPoint("TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
    frame.contentArea:SetSize(contentWidth, contentHeight)

    frame:SetWindowTitle(self:BrandTitle())
    return frame
end

local function TabTemplate()
    if Theme.HasTemplate("PanelTopTabButtonTemplate") then
        return "PanelTopTabButtonTemplate"
    elseif Theme.HasTemplate("TabButtonTemplate") then
        return "TabButtonTemplate"
    end
end

function Skin:CreateTab(window, label, onClick)
    local template = TabTemplate()
    if not template or not PanelTemplates_SelectTab or not PanelTemplates_TabResize then
        return Minimal().CreateTab(self, window, label, onClick)
    end

    -- Named because some clients resolve tab textures through the global name.
    window.tabCount = (window.tabCount or 0) + 1
    local tab = CreateFrame("Button", window:GetName() .. "Tab" .. window.tabCount, window, template)
    tab:SetText(" ")
    tab.text = tab:GetFontString()
    self:SetLocalizedText(tab.text, label)
    tab:SetScript("OnClick", onClick)

    function tab:SetSelected(selected)
        self.selected = selected
        if selected then
            PanelTemplates_SelectTab(self)
        else
            PanelTemplates_DeselectTab(self)
        end
    end

    function tab:UpdateWidth()
        PanelTemplates_TabResize(self, 12)
    end

    tab:UpdateWidth()
    return tab
end

function Skin:PlaceTab(window, tab, previous)
    if previous then
        tab:SetPoint("LEFT", previous, "RIGHT", 2, 0)
    elseif window.inset then
        tab:SetPoint("BOTTOMLEFT", window.inset, "TOPLEFT", 4, 0)
    else
        Minimal().PlaceTab(self, window, tab, previous)
    end
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

function Skin:CreateButton(parent, label, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 100, height or 22)
    button:SetText(" ")
    button.text = button:GetFontString()
    if label then
        self:SetLocalizedText(button.text, label)
    end
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    return button
end

--- Row of panel buttons where the selected one stays highlighted.
function Skin:CreateSegmented(parent, options, getter, setter)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(22)
    holder.buttons = {}

    function holder:Refresh()
        local current = getter()
        local width = 0
        for _, button in ipairs(self.buttons) do
            if button.value == current then
                button:LockHighlight()
            else
                button:UnlockHighlight()
            end
            button:SetWidth(button.text:GetStringWidth() + 24)
            width = width + button:GetWidth()
        end
        self:SetWidth(math.max(1, width))
    end

    local previous
    for _, option in ipairs(options) do
        local button = Skin.CreateButton(Theme, holder, option.label, 60, 22, function()
            setter(option.value)
            holder:Refresh()
        end)
        button.value = option.value
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 0, 0)
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

--- Stat tile inside a tooltip style frame.
function Skin:CreateStat(parent, label)
    local tile = self:CreatePanel(parent, "tile")
    tile:SetHeight(48)

    tile.label = self:CreateText(tile, "label")
    tile.label:SetPoint("TOPLEFT", 10, -9)
    self:SetLocalizedText(tile.label, label)

    tile.value = self:CreateText(tile, "value")
    tile.value:SetPoint("BOTTOMLEFT", 10, 9)
    tile.value:SetPoint("RIGHT", -8, 0)
    tile.label:SetPoint("RIGHT", -8, 0)
    self:AttachTileTooltip(tile)
    return tile
end

--------------------------------------------------------------------------------
-- Experience bar
--------------------------------------------------------------------------------

--- Status bar textured and colored like the game's experience bar: purple in
--- the normal state, blue while rested, with a translucent rested overlay.
function Skin:CreateXPBar(parent)
    local palette = Skin.palette
    local bar = CreateFrame("StatusBar", nil, parent)   -- rested overlay
    bar:SetHeight(Theme.metrics.launcher.barHeight)
    bar:SetStatusBarTexture(STATUSBAR_TEXTURE)
    bar:SetStatusBarColor(palette.rested[1], palette.rested[2], palette.rested[3], 0.35)
    bar:SetMinMaxValues(0, 1)

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(Theme.WHITE)
    background:SetVertexColor(palette.track[1], palette.track[2], palette.track[3], palette.track[4])
    background:SetAllPoints()

    local fill = CreateFrame("StatusBar", nil, bar)
    fill:SetAllPoints()
    fill:SetStatusBarTexture(STATUSBAR_TEXTURE)
    fill:SetMinMaxValues(0, 1)

    function bar:SetProgress(progress, restedEnd)
        local color = restedEnd > progress and palette.rested or palette.xp
        fill:SetStatusBarColor(color[1], color[2], color[3], 1)
        fill:SetValue(progress)
        self:SetValue(restedEnd)
    end
    return bar
end

--------------------------------------------------------------------------------
-- Checkbox
--------------------------------------------------------------------------------

function Skin:CreateCheckbox(parent, label, getter, setter)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    -- Template labels differ between clients; use our own and blank theirs.
    for _, key in ipairs({ "Text", "text" }) do
        if check[key] and check[key].SetText then
            check[key]:SetText("")
        end
    end
    check.label = self:CreateText(check, "normal")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 1)
    self:SetLocalizedText(check.label, label)
    check:SetHitRectInsets(0, -200, 0, 0)

    function check:Refresh()
        self:SetChecked(getter() and true or false)
    end

    check:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        self:Refresh()
    end)
    check:Refresh()
    return check
end

--------------------------------------------------------------------------------
-- Slider
--------------------------------------------------------------------------------

--- Modern settings slider with stepper arrows (mainline-API clients).
local function CreateModernSlider(self, parent, label, minValue, maxValue, step, formatter, getter, setter)
    local mixin = MinimalSliderWithSteppersMixin
    if not mixin or not mixin.Event or not mixin.Label or not Theme.HasTemplate("MinimalSliderWithSteppersTemplate") then
        return nil
    end

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(280, 44)
    holder.label = self:CreateText(holder, "normal")
    holder.label:SetPoint("TOPLEFT")
    self:SetLocalizedText(holder.label, label)

    local slider = CreateFrame("Frame", nil, holder, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("BOTTOMLEFT", 0, 0)
    slider:SetPoint("BOTTOMRIGHT", -44, 0)
    slider:SetHeight(20)

    local steps = math.max(1, math.floor((maxValue - minValue) / step + 0.5))
    local formatters = { [mixin.Label.Right] = function(value) return formatter(value) end }
    local ok = pcall(slider.Init, slider, getter(), minValue, maxValue, steps, formatters)
    if not ok then
        holder:Hide()
        return nil
    end

    local updating = false
    slider:RegisterCallback(mixin.Event.OnValueChanged, function(_, value)
        if not updating then
            setter(math.floor(value / step + 0.5) * step)
        end
    end, holder)

    function holder:Refresh()
        updating = true
        slider:SetValue(getter())
        updating = false
    end

    holder.slider = slider
    return holder
end

--- Slider with the classic Blizzard options slider art.
local function CreateClassicSlider(self, parent, label, minValue, maxValue, step, formatter, getter, setter)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(280, 44)

    holder.label = self:CreateText(holder, "normal")
    holder.label:SetPoint("TOPLEFT")
    self:SetLocalizedText(holder.label, label)

    holder.value = self:CreateText(holder, "accent", "RIGHT")
    holder.value:SetPoint("TOPRIGHT")

    local slider = CreateFrame("Slider", nil, holder, BackdropTemplate())
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(17)
    slider:SetPoint("BOTTOMLEFT", 0, 2)
    slider:SetPoint("BOTTOMRIGHT", 0, 2)
    Theme.ApplyBackdrop(slider, SLIDER_BACKDROP)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end

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
    slider:SetScript("OnMouseWheel", function(selfSlider, delta)
        selfSlider:SetValue(ns.Clamp(selfSlider:GetValue() + delta * step, minValue, maxValue))
    end)

    holder.slider = slider
    holder:Refresh()
    return holder
end

function Skin:CreateSlider(parent, ...)
    return CreateModernSlider(self, parent, ...) or CreateClassicSlider(self, parent, ...)
end

--------------------------------------------------------------------------------
-- Dropdown
--------------------------------------------------------------------------------

--- Uses the client's dropdown button and menu system when available (Retail,
--- Forever and clients with the new Menu API); otherwise the self-drawn
--- dropdown built from native buttons and tooltip frames.
function Skin:CreateDropdown(parent, width, options, getter, setter)
    if Theme.HasTemplate("WowStyle1DropdownTemplate") then
        local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        if ok and dropdown and dropdown.SetupMenu then
            dropdown:SetWidth(width)
            dropdown:SetupMenu(function(_, root)
                for _, option in ipairs(options()) do
                    local text = option.color and (Theme.Hex(option.color) .. option.label .. "|r") or option.label
                    root:CreateRadio(text,
                        function() return getter() == option.value end,
                        function() setter(option.value) end)
                end
            end)
            function dropdown:Refresh()
                if self.GenerateMenu then
                    self:GenerateMenu()
                end
            end
            ns:RegisterMessage("XPL_LOCALE_CHANGED", function() dropdown:Refresh() end)
            return dropdown
        end
    end
    return Minimal().CreateDropdown(self, parent, width, options, getter, setter)
end

Theme:RegisterSkin("blizzard", Skin)
