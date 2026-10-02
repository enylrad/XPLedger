--[[----------------------------------------------------------------------------
    XPLedger - Options panel
    Registered in the game's AddOns settings. Uses the modern Settings API
    (retail, Forever and current classic clients) and falls back to the legacy
    Interface Options when it is not available.
------------------------------------------------------------------------------]]

local _, ns = ...

local Options = ns:NewModule("Options")
local Theme = ns.Theme
local L = ns.L

local COLUMN_X = { 16, 330 }

--------------------------------------------------------------------------------
-- Setting helpers
--------------------------------------------------------------------------------

local function Notify()
    ns:SendMessage("XPL_SETTINGS_CHANGED")
end

local function LauncherGetter(key)
    return function() return ns.settings.launcher[key] end
end

local function LauncherSetter(key)
    return function(value)
        ns.settings.launcher[key] = value
        Notify()
    end
end

local function SectionTitle(parent, key, x, y)
    local title = Theme:CreateText(parent, 13, Theme.colors.accent)
    title:SetPoint("TOPLEFT", x, y)
    Theme:SetLocalizedText(title, key)
    local line = Theme:CreateTexture(parent, Theme.colors.border)
    line:SetPoint("TOPLEFT", x, y - 18)
    line:SetSize(280, 1)
    return title
end

local function Caption(parent, key, x, y)
    local caption = Theme:CreateText(parent, 11, Theme.colors.muted)
    caption:SetPoint("TOPLEFT", x, y)
    Theme:SetLocalizedText(caption, key)
    return caption
end

--------------------------------------------------------------------------------
-- Panel construction
--------------------------------------------------------------------------------

function Options:BuildPanel(panel)
    local widgets = {}
    self.widgets = widgets

    local title = Theme:CreateText(panel, 18)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(Theme.Hex(Theme.colors.accent) .. "XP|rLedger")

    local version = Theme:CreateText(panel, 11, Theme.colors.muted)
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("v" .. (ns.Compat.GetAddOnMetadata("Version") or "?"))

    local subtitle = Theme:CreateText(panel, 12, Theme.colors.muted)
    subtitle:SetPoint("TOPLEFT", 16, -42)
    Theme:SetLocalizedText(subtitle, "OPTIONS_SUBTITLE")

    ------------------------------------------------------------------ General
    local x, y = COLUMN_X[1], -76
    SectionTitle(panel, "OPT_SECTION_GENERAL", x, y)

    Caption(panel, "OPT_LANGUAGE", x, y - 30)
    widgets.language = Theme:CreateDropdown(panel, 220, function()
        local options = {}
        for _, code in ipairs(ns.AVAILABLE_LOCALES) do
            options[#options + 1] = { value = code, label = L["LANGUAGE_" .. code] }
        end
        return options
    end, function() return ns.settings.locale end, function(value)
        ns.settings.locale = value
        ns:SetLocale(value)
    end)
    widgets.language:SetPoint("TOPLEFT", x, y - 46)

    widgets.rateWindow = Theme:CreateSlider(panel, "OPT_RATE_WINDOW", 5, 60, 5,
        function(value) return L["MINUTES_VALUE"]:format(value) end,
        function() return ns.settings.rateWindow end,
        function(value)
            ns.settings.rateWindow = value
            Notify()
        end)
    widgets.rateWindow:SetPoint("TOPLEFT", x, y - 82)
    widgets.rateWindow:SetWidth(280)
    local rateHelp = Caption(panel, "OPT_RATE_WINDOW_DESC", x, y - 124)
    rateHelp:SetWidth(280)
    rateHelp:SetWordWrap(true)

    widgets.afk = Theme:CreateSlider(panel, "OPT_AFK", 1, 30, 1,
        function(value) return L["MINUTES_VALUE"]:format(value) end,
        function() return ns.settings.afkThreshold end,
        function(value)
            ns.settings.afkThreshold = value
            Notify()
        end)
    widgets.afk:SetPoint("TOPLEFT", x, y - 156)
    widgets.afk:SetWidth(280)
    local afkHelp = Caption(panel, "OPT_AFK_DESC", x, y - 198)
    afkHelp:SetWidth(280)
    afkHelp:SetWordWrap(true)

    widgets.ding = Theme:CreateCheckbox(panel, "OPT_DING_SUMMARY",
        function() return ns.settings.dingSummary end,
        function(value) ns.settings.dingSummary = value end)
    widgets.ding:SetPoint("TOPLEFT", x, y - 236)

    widgets.played = Theme:CreateCheckbox(panel, "OPT_PLAYED_SILENT",
        function() return ns.settings.silentPlayed end,
        function(value) ns.settings.silentPlayed = value end)
    widgets.played:SetPoint("TOPLEFT", x, y - 260)

    ----------------------------------------------------------------- Launcher
    x, y = COLUMN_X[2], -76
    SectionTitle(panel, "OPT_SECTION_LAUNCHER", x, y)

    widgets.show = Theme:CreateCheckbox(panel, "OPT_LAUNCHER_SHOW", LauncherGetter("shown"), function(value)
        ns.Launcher:SetShown(value)
    end)
    widgets.show:SetPoint("TOPLEFT", x, y - 28)

    widgets.lock = Theme:CreateCheckbox(panel, "OPT_LAUNCHER_LOCK", LauncherGetter("locked"), function(value)
        ns.Launcher:SetLocked(value)
    end)
    widgets.lock:SetPoint("TOPLEFT", x, y - 52)

    widgets.hideAtMax = Theme:CreateCheckbox(panel, "OPT_LAUNCHER_HIDE_MAX", LauncherGetter("hideAtMax"), LauncherSetter("hideAtMax"))
    widgets.hideAtMax:SetPoint("TOPLEFT", x, y - 76)

    widgets.perCharacter = Theme:CreateCheckbox(panel, "OPT_LAUNCHER_PER_CHAR", LauncherGetter("perCharacter"), LauncherSetter("perCharacter"))
    widgets.perCharacter:SetPoint("TOPLEFT", x, y - 100)

    Caption(panel, "OPT_LAUNCHER_TEXT", x, y - 132)
    widgets.textMode = Theme:CreateDropdown(panel, 220, function()
        local options = {}
        for _, mode in ipairs({ "eta", "percent", "rate", "remaining" }) do
            options[#options + 1] = { value = mode, label = L["TEXT_MODE_" .. mode] }
        end
        return options
    end, LauncherGetter("textMode"), LauncherSetter("textMode"))
    widgets.textMode:SetPoint("TOPLEFT", x, y - 148)

    widgets.scale = Theme:CreateSlider(panel, "OPT_LAUNCHER_SCALE", 0.6, 2, 0.05,
        function(value) return ("%d%%"):format(value * 100 + 0.5) end,
        LauncherGetter("scale"), LauncherSetter("scale"))
    widgets.scale:SetPoint("TOPLEFT", x, y - 184)
    widgets.scale:SetWidth(280)

    widgets.alpha = Theme:CreateSlider(panel, "OPT_LAUNCHER_ALPHA", 0.2, 1, 0.05,
        function(value) return ("%d%%"):format(value * 100 + 0.5) end,
        LauncherGetter("alpha"), LauncherSetter("alpha"))
    widgets.alpha:SetPoint("TOPLEFT", x, y - 228)
    widgets.alpha:SetWidth(280)

    local resetPosition = Theme:CreateButton(panel, "OPT_RESET_POSITION", 160, 22, function()
        ns.Launcher:ResetPosition()
    end)
    resetPosition:SetPoint("TOPLEFT", x, y - 276)

    --------------------------------------------------------------------- Data
    x, y = COLUMN_X[1], -380
    SectionTitle(panel, "OPT_SECTION_DATA", x, y)

    widgets.dataInfo = Theme:CreateText(panel, 12, Theme.colors.muted)
    widgets.dataInfo:SetPoint("TOPLEFT", x, y - 30)

    local resetCharacter = Theme:CreateButton(panel, "OPT_RESET_CHAR", 180, 22, function()
        Theme:Confirm(L["OPT_RESET_CHAR_CONFIRM"], function()
            ns.Database:ResetCharacter(ns.charKey)
            self:Refresh()
        end)
    end)
    resetCharacter:SetPoint("TOPLEFT", x, y - 54)

    local resetAll = Theme:CreateButton(panel, "OPT_RESET_ALL", 180, 22, function()
        Theme:Confirm(L["OPT_RESET_ALL_CONFIRM"], function()
            ns.Database:ResetAll()
            self:Refresh()
        end)
    end)
    resetAll:SetPoint("LEFT", resetCharacter, "RIGHT", 8, 0)
end

--- Re-reads every setting into the widgets (the values can change elsewhere,
--- for example with /xpl lock or a right-click on the launcher).
function Options:Refresh()
    if not self.widgets then
        return
    end
    for _, widget in pairs(self.widgets) do
        if widget.Refresh then
            widget:Refresh()
        end
    end
    self.widgets.dataInfo:SetText(L["OPT_DATA_INFO"]:format(ns.Database:CountCharacters()))
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

function Options:OnLogin()
    local panel = CreateFrame("Frame")
    panel.name = ns.title
    panel:Hide()
    panel:SetScript("OnShow", function()
        if not self.widgets then
            self:BuildPanel(panel)
        end
        self:Refresh()
    end)
    panel:SetScript("OnHide", function() Theme:CloseMenus() end)
    self.panel = panel

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, ns.title)
        Settings.RegisterAddOnCategory(category)
        self.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    ns:RegisterMessage("XPL_SETTINGS_CHANGED", function()
        if panel:IsShown() then
            self:Refresh()
        end
    end)
    ns:RegisterMessage("XPL_LOCALE_CHANGED", function()
        if panel:IsShown() then
            self:Refresh()
        end
    end)
end

--- Opens the game settings on this addon's page.
function Options:Open()
    if self.category and Settings and Settings.OpenToCategory then
        local id = self.category.GetID and self.category:GetID() or self.category.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice: the first call may only open the frame on legacy clients.
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel)
    end
end
