--[[----------------------------------------------------------------------------
    XPLedger - Theme
    Facade over the interface skins. The rest of the UI only talks to `Theme`;
    the active skin provides the actual widgets.

    Skins (UI\Skins):
      blizzard  native look built from the client's own templates, fonts and
                art, so every flavor (Retail, Forever, Classic) looks like itself
      minimal   flat self-drawn look

    Skin contract (every function is called with `self` = Theme):
      palette, metrics                     colors and launcher/window sizes
      CreateText(parent, role, justify)    roles: title, heading, normal, value,
                                           label, muted, small, accent
      CreatePanel(parent, variant, frameType, name)
                                           variants: launcher, tile, menu
      SetHighlight(panel, enabled)         hover feedback of a panel
      CreateWindow(name, contentWidth, contentHeight)
                                           returns a frame with .contentArea,
                                           .subtitle and SetWindowTitle(text)
      CreateTab(window, label, onClick), PlaceTab(window, tab, previous)
      CreateButton, CreateCheckbox, CreateSlider, CreateDropdown,
      CreateSegmented, CreateStat, CreateXPBar, BrandTitle

    The skin is chosen once at load (Theme:Init) because template based frames
    cannot be reskinned at runtime; changing it requires a /reload.
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = { skins = {} }
ns.Theme = Theme

Theme.WHITE = "Interface\\Buttons\\WHITE8X8"
Theme.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
Theme.STYLES = { "blizzard", "minimal" }

-- Shared data colors (identical in every skin so charts read the same).
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

--------------------------------------------------------------------------------
-- Skin registry
--------------------------------------------------------------------------------

--- Registers a skin table. Called by the files in UI\Skins.
function Theme:RegisterSkin(id, skin)
    self.skins[id] = skin
end

--- Activates a skin: copies its widget functions onto Theme and adopts its
--- palette and metrics. Unknown ids fall back to the Blizzard skin (or to
--- the Minimal one if, for any reason, the Blizzard skin is not loaded).
function Theme:Init(style)
    local id = self.skins[style] and style or (self.skins.blizzard and "blizzard" or "minimal")
    local skin = self.skins[id]
    for key, value in pairs(skin) do
        if type(value) == "function" then
            self[key] = value
        end
    end
    self.style = id
    self.colors = skin.palette
    self.metrics = skin.metrics
end

--------------------------------------------------------------------------------
-- Template probing
--------------------------------------------------------------------------------

-- Templates present in every client since the original game.
local UNIVERSAL_TEMPLATES = {
    UIPanelButtonTemplate = true,
    UICheckButtonTemplate = true,
    UIPanelCloseButton = true,
}

--- Returns true when the running client defines an XML template.
function Theme.HasTemplate(name)
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        return C_XMLUtil.GetTemplateInfo(name) ~= nil
    end
    return UNIVERSAL_TEMPLATES[name] == true
end

--- Gives any frame backdrop support (mixin on modern clients, native on old
--- ones) and applies the backdrop description.
function Theme.ApplyBackdrop(frame, backdrop)
    if not frame.SetBackdrop and BackdropTemplateMixin and Mixin then
        Mixin(frame, BackdropTemplateMixin)
        frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
    end
    if frame.SetBackdrop then
        frame:SetBackdrop(backdrop)
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Color helpers
--------------------------------------------------------------------------------

--- Returns the color as a "|cffrrggbb" escape sequence.
function Theme.Hex(color)
    return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

--- Returns an inline color square usable inside any text ("|T...|t" escape).
function Theme.Swatch(color, size)
    size = size or 10
    return ("|TInterface\\Buttons\\WHITE8X8:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(size, size,
        color[1] * 255, color[2] * 255, color[3] * 255)
end

--- Creates a solid color texture.
function Theme:CreateTexture(parent, color, layer, sublevel)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
    texture:SetTexture(self.WHITE)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return texture
end

--------------------------------------------------------------------------------
-- Stat tile tooltips
--------------------------------------------------------------------------------

--- Returns true when a font string does not fit in its width.
local function IsTruncated(fontString)
    if fontString.IsTruncated then
        return fontString:IsTruncated()
    end
    local width = fontString:GetWidth()
    return width > 0 and fontString:GetStringWidth() > width + 0.5
end

--- Gives a stat tile a hover tooltip. It shows the full label and value when
--- either is cut off, and always shows `tile.tooltip(tooltip)` when a view
--- sets it to add details.
function Theme:AttachTileTooltip(tile)
    tile:EnableMouse(true)
    tile:SetScript("OnEnter", function(selfTile)
        local truncated = IsTruncated(selfTile.label) or IsTruncated(selfTile.value)
        if not truncated and not selfTile.tooltip then
            return
        end
        GameTooltip:SetOwner(selfTile, "ANCHOR_TOP")
        local accent = Theme.colors.accent
        GameTooltip:AddLine(selfTile.label:GetText() or "", accent[1], accent[2], accent[3])
        if selfTile.tooltip then
            selfTile.tooltip(GameTooltip)
        else
            GameTooltip:AddLine(selfTile.value:GetText() or "", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    tile:SetScript("OnLeave", function(selfTile)
        if GameTooltip:IsOwned(selfTile) then
            GameTooltip:Hide()
        end
    end)
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
-- Popup menus (shared by the self-drawn dropdowns of both skins)
--------------------------------------------------------------------------------

--- Closes the self-drawn dropdown menu that is currently open, if any.
function Theme:CloseMenus()
    if self.openMenu then
        self.openMenu:Hide()
        self.openMenu = nil
    end
end

local menuBlocker

--- Full screen catcher that closes an open menu when clicking elsewhere.
function Theme:GetMenuBlocker()
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

--------------------------------------------------------------------------------
-- Text dialog (copy and paste)
--------------------------------------------------------------------------------

local textDialog

local function CreateTextDialog()
    local dialog = Theme:CreatePanel(UIParent, "menu", "Frame", "XPLedgerTextDialog")
    dialog:SetSize(560, 360)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetToplevel(true)
    dialog:SetClampedToScreen(true)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:Hide()
    tinsert(UISpecialFrames, dialog:GetName())

    dialog.title = Theme:CreateText(dialog, "heading")
    dialog.title:SetPoint("TOPLEFT", 14, -12)

    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    dialog.hint = Theme:CreateText(dialog, "muted")
    dialog.hint:SetPoint("BOTTOMLEFT", 14, 12)
    Theme:SetLocalizedText(dialog.hint, "EXPORT_HINT")

    local scroll = CreateFrame("ScrollFrame", "XPLedgerTextDialogScroll", dialog, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -36)
    scroll:SetPoint("BOTTOMRIGHT", -32, 34)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    editBox:SetWidth(500)
    editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
    -- Read only: any edit restores the exported text.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(dialog.text or "")
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(editBox)
    dialog.editBox = editBox
    return dialog
end

--- Shows a dialog with a read only text, selected so it can be copied.
function Theme:ShowTextDialog(title, text)
    textDialog = textDialog or CreateTextDialog()
    textDialog.title:SetText(title)
    textDialog.text = text
    textDialog.editBox:SetText(text)
    textDialog:Show()
    textDialog.editBox:SetFocus()
    textDialog.editBox:HighlightText()
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
