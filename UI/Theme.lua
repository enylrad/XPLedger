--[[----------------------------------------------------------------------------
    XPLedger - Theme and widgets
    Minimalist flat look shared by every frame of the addon, plus a small set
    of self-drawn widgets (buttons, checkboxes, sliders, dropdowns).

    Widgets are built from plain textures on purpose: Blizzard templates differ
    between flavors and get renamed or removed between expansions.
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = {}
ns.Theme = Theme

local WHITE = "Interface\\Buttons\\WHITE8X8"

Theme.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

Theme.colors = {
    background = { 0.05, 0.06, 0.08, 0.92 },
    surface = { 0.10, 0.11, 0.14, 0.95 },
    surfaceHover = { 0.15, 0.16, 0.20, 0.95 },
    border = { 1, 1, 1, 0.08 },
    accent = { 0.31, 0.76, 0.97, 1 },
    rested = { 0.47, 0.42, 0.96, 1 },
    text = { 0.93, 0.94, 0.96, 1 },
    muted = { 0.58, 0.61, 0.67, 1 },
    grid = { 1, 1, 1, 0.06 },
    track = { 1, 1, 1, 0.07 },
    warning = { 0.98, 0.62, 0.25, 1 },
}

Theme.sourceColors = {
    mob = { 0.91, 0.37, 0.34 },
    quest = { 0.98, 0.77, 0.27 },
    exploration = { 0.37, 0.80, 0.48 },
    petbattle = { 0.71, 0.51, 0.96 },
    other = { 0.55, 0.58, 0.64 },
}

Theme.contextColors = {
    world = { 0.37, 0.80, 0.48 },
    dungeon = { 0.31, 0.60, 0.97 },
    raid = { 0.96, 0.56, 0.26 },
    battleground = { 0.91, 0.37, 0.34 },
    scenario = { 0.40, 0.85, 0.85 },
}

--- Returns the color as a "|cffrrggbb" escape sequence.
function Theme.Hex(color)
    return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

--- Creates a solid color texture.
function Theme:CreateTexture(parent, color, layer, sublevel)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
    texture:SetTexture(WHITE)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return texture
end

--- Gives a frame a flat background and a 1px border (no backdrop template needed).
function Theme:Skin(frame, background, border)
    background = background or self.colors.background
    border = border or self.colors.border

    local bg = self:CreateTexture(frame, background, "BACKGROUND", -8)
    bg:SetAllPoints()
    frame.skinBackground = bg

    local edges = {}
    for i = 1, 4 do
        edges[i] = self:CreateTexture(frame, border, "BORDER", 7)
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    frame.skinEdges = edges
end

--- Changes the color of a skinned frame's border.
function Theme:SetBorderColor(frame, color, alpha)
    for _, edge in ipairs(frame.skinEdges or {}) do
        edge:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
    end
end

--- Changes the color of a skinned frame's background.
function Theme:SetBackgroundColor(frame, color)
    if frame.skinBackground then
        frame.skinBackground:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
end

--- Creates a font string with the addon font.
function Theme:CreateText(parent, size, color, justify, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFont(self.FONT, size or 12, "")
    color = color or self.colors.text
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    text:SetJustifyH(justify or "LEFT")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.7)
    text:SetWordWrap(false)
    return text
end

--------------------------------------------------------------------------------
-- Localized texts (refreshed when the language changes at runtime)
--------------------------------------------------------------------------------

local localizedTexts = setmetatable({}, { __mode = "k" })

--- Sets a localized text and remembers the key to refresh it later.
--- `key` may also be a function returning the text.
function Theme:SetLocalizedText(fontString, key)
    localizedTexts[fontString] = key
    fontString:SetText(type(key) == "function" and key() or ns.L[key])
end

ns:RegisterMessage("XPL_LOCALE_CHANGED", function()
    for fontString, key in pairs(localizedTexts) do
        fontString:SetText(type(key) == "function" and key() or ns.L[key])
    end
end)

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

--- Creates a flat text button. `label` is a locale key or a function.
function Theme:CreateButton(parent, label, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 100, height or 22)
    self:Skin(button, self.colors.surface)

    button.text = self:CreateText(button, 11, self.colors.text, "CENTER")
    button.text:SetPoint("CENTER")
    if label then
        self:SetLocalizedText(button.text, label)
    end

    button:SetScript("OnEnter", function(selfButton)
        Theme:SetBackgroundColor(selfButton, Theme.colors.surfaceHover)
    end)
    button:SetScript("OnLeave", function(selfButton)
        Theme:SetBackgroundColor(selfButton, Theme.colors.surface)
    end)
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    return button
end

--- Creates a tab style button with a selected state (accent underline).
function Theme:CreateTab(parent, label, onClick)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetHeight(24)
    tab.text = self:CreateText(tab, 12, self.colors.muted, "CENTER")
    tab.text:SetPoint("CENTER", 0, 1)
    self:SetLocalizedText(tab.text, label)

    tab.underline = self:CreateTexture(tab, self.colors.accent)
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
        self.text:SetTextColor(Theme.colors.text[1], Theme.colors.text[2], Theme.colors.text[3])
    end)
    tab:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    tab:SetScript("OnClick", onClick)
    tab:UpdateWidth()
    return tab
end

--- Creates a row of small toggle buttons where exactly one is selected.
--- `options` is an array of { value = any, label = locale key }.
function Theme:CreateSegmented(parent, options, getter, setter)
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
            Theme:SetBorderColor(button, selected and Theme.colors.accent or Theme.colors.border,
                selected and 0.6 or nil)
            button:SetWidth(button.text:GetStringWidth() + 16)
            width = width + button:GetWidth() + 2
        end
        self:SetWidth(math.max(1, width - 2))
    end

    local previous
    for _, option in ipairs(options) do
        local button = Theme:CreateButton(holder, option.label, 40, 20, function()
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

--- Creates a stat tile: a small caption above a large value.
function Theme:CreateStat(parent, label)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetHeight(46)
    self:Skin(tile, self.colors.surface)

    tile.label = self:CreateText(tile, 10, self.colors.muted)
    tile.label:SetPoint("TOPLEFT", 10, -8)
    self:SetLocalizedText(tile.label, label)

    tile.value = self:CreateText(tile, 16)
    tile.value:SetPoint("BOTTOMLEFT", 10, 8)
    tile.value:SetPoint("RIGHT", -8, 0)
    return tile
end

--------------------------------------------------------------------------------
-- Checkbox
--------------------------------------------------------------------------------

--- Creates a checkbox bound to a getter/setter pair.
function Theme:CreateCheckbox(parent, label, getter, setter)
    local check = CreateFrame("Button", nil, parent)
    check:SetHeight(20)

    local box = CreateFrame("Frame", nil, check)
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    self:Skin(box, self.colors.surface, { 1, 1, 1, 0.2 })

    local mark = self:CreateTexture(box, self.colors.accent)
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)

    check.text = self:CreateText(check, 12)
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
    check:SetScript("OnEnter", function() Theme:SetBorderColor(box, Theme.colors.accent) end)
    check:SetScript("OnLeave", function() Theme:SetBorderColor(box, { 1, 1, 1, 0.2 }) end)
    check:Refresh()
    return check
end

--------------------------------------------------------------------------------
-- Slider
--------------------------------------------------------------------------------

--- Creates a horizontal slider with a label and a formatted value.
--- @param formatter fun(value: number): string
function Theme:CreateSlider(parent, label, minValue, maxValue, step, formatter, getter, setter)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(220, 40)

    holder.label = self:CreateText(holder, 12)
    holder.label:SetPoint("TOPLEFT")
    self:SetLocalizedText(holder.label, label)

    holder.value = self:CreateText(holder, 12, self.colors.accent, "RIGHT")
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

    local track = self:CreateTexture(slider, self.colors.track, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetVertexColor(unpack(self.colors.accent))
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

local openMenu

--- Closes the dropdown menu that is currently open, if any.
function Theme:CloseMenus()
    if openMenu then
        openMenu:Hide()
        openMenu = nil
    end
end

-- Full screen catcher that closes an open menu when clicking elsewhere.
local menuBlocker

local function GetMenuBlocker()
    if not menuBlocker then
        menuBlocker = CreateFrame("Button", nil, UIParent)
        menuBlocker:SetAllPoints(UIParent)
        menuBlocker:SetFrameStrata("FULLSCREEN_DIALOG")
        menuBlocker:RegisterForClicks("AnyUp")
        menuBlocker:SetScript("OnClick", function() Theme:CloseMenus() end)
        menuBlocker:Hide()
    end
    return menuBlocker
end

--- Creates a dropdown. `options` is a function returning an array of
--- { value = any, label = string, color = {r,g,b}? } evaluated on open.
function Theme:CreateDropdown(parent, width, options, getter, setter)
    local dropdown = self:CreateButton(parent, nil, width, 22)
    dropdown.text:ClearAllPoints()
    dropdown.text:SetPoint("LEFT", 8, 0)
    dropdown.text:SetPoint("RIGHT", -20, 0)
    dropdown.text:SetJustifyH("LEFT")

    local arrow = self:CreateText(dropdown, 10, self.colors.muted, "RIGHT")
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")

    local menu = CreateFrame("Frame", nil, dropdown)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(width)
    menu:EnableMouse(true)
    self:Skin(menu, { 0.07, 0.08, 0.10, 0.98 }, { 1, 1, 1, 0.15 })
    menu:Hide()
    menu:SetScript("OnHide", function()
        if menuBlocker then
            menuBlocker:Hide()
        end
    end)
    menu.items = {}

    function dropdown:Refresh()
        local current = getter()
        for _, option in ipairs(options()) do
            if option.value == current then
                self.text:SetText(option.label)
                return
            end
        end
        self.text:SetText(tostring(current))
    end

    local function OpenMenu()
        local list = options()
        local current = getter()
        for i, option in ipairs(list) do
            local item = menu.items[i]
            if not item then
                item = CreateFrame("Button", nil, menu)
                item:SetHeight(20)
                item.highlight = Theme:CreateTexture(item, { 1, 1, 1, 0.08 }, "HIGHLIGHT")
                item.highlight:SetAllPoints()
                item.text = Theme:CreateText(item, 11)
                item.text:SetPoint("LEFT", 8, 0)
                item.text:SetPoint("RIGHT", -8, 0)
                menu.items[i] = item
            end
            item:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
            item:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 20)
            item.text:SetText(option.label)
            local color = option.value == current and Theme.colors.accent or (option.color or Theme.colors.text)
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
        menu:SetHeight(#list * 20 + 2)

        Theme:CloseMenus()
        local blocker = GetMenuBlocker()
        blocker:Show()
        menu:SetFrameLevel(blocker:GetFrameLevel() + 10)
        menu:Show()
        openMenu = menu
    end

    dropdown:SetScript("OnClick", function()
        if menu:IsShown() then
            Theme:CloseMenus()
        else
            OpenMenu()
        end
    end)
    dropdown:SetScript("OnHide", function() menu:Hide() end)

    ns:RegisterMessage("XPL_LOCALE_CHANGED", function() dropdown:Refresh() end)
    dropdown:Refresh()
    return dropdown
end

--------------------------------------------------------------------------------
-- Confirmation dialog
--------------------------------------------------------------------------------

StaticPopupDialogs["XPLEDGER_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        if data and data.onAccept then
            data.onAccept()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--- Shows a yes/no confirmation and runs `onAccept` when confirmed.
function Theme:Confirm(message, onAccept)
    StaticPopup_Show("XPLEDGER_CONFIRM", message, nil, { onAccept = onAccept })
end
