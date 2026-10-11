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

local function PetGetter(key)
    return function() return ns.settings.pet[key] end
end

local function PetSetter(key)
    return function(value)
        ns.settings.pet[key] = value
        Notify()
    end
end

local function SectionTitle(parent, key, x, y)
    local title = Theme:CreateText(parent, "accent")
    title:SetPoint("TOPLEFT", x, y)
    Theme:SetLocalizedText(title, key)
    local line = Theme:CreateTexture(parent, Theme.colors.border)
    line:SetPoint("TOPLEFT", x, y - 18)
    line:SetSize(280, 1)
    return title
end

local function Caption(parent, key, x, y, role)
    local caption = Theme:CreateText(parent, role or "label")
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

    local title = Theme:CreateText(panel, "title")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(Theme:BrandTitle())

    local version = Theme:CreateText(panel, "muted")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("v" .. (ns.Compat.GetAddOnMetadata("Version") or "?"))

    local subtitle = Theme:CreateText(panel, "muted")
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

    Caption(panel, "OPT_STYLE", x, y - 80)
    widgets.style = Theme:CreateDropdown(panel, 220, function()
        local options = {}
        for _, style in ipairs(Theme.STYLES) do
            options[#options + 1] = { value = style, label = L["STYLE_" .. style] }
        end
        return options
    end, function() return ns.settings.style end, function(value)
        if value == ns.settings.style then
            return
        end
        ns.settings.style = value
        -- Template based frames cannot be reskinned live: offer a reload.
        Theme:Confirm(L["OPT_STYLE_RELOAD"], ReloadUI)
    end)
    widgets.style:SetPoint("TOPLEFT", x, y - 96)

    widgets.rateWindow = Theme:CreateSlider(panel, "OPT_RATE_WINDOW", 5, 60, 5,
        function(value) return L["MINUTES_VALUE"]:format(value) end,
        function() return ns.settings.rateWindow end,
        function(value)
            ns.settings.rateWindow = value
            Notify()
        end)
    widgets.rateWindow:SetPoint("TOPLEFT", x, y - 132)
    widgets.rateWindow:SetWidth(280)
    local rateHelp = Caption(panel, "OPT_RATE_WINDOW_DESC", x, y - 180, "small")
    rateHelp:SetWidth(280)
    rateHelp:SetWordWrap(true)

    widgets.afk = Theme:CreateSlider(panel, "OPT_AFK", 1, 30, 1,
        function(value) return L["MINUTES_VALUE"]:format(value) end,
        function() return ns.settings.afkThreshold end,
        function(value)
            ns.settings.afkThreshold = value
            Notify()
        end)
    widgets.afk:SetPoint("TOPLEFT", x, y - 212)
    widgets.afk:SetWidth(280)
    local afkHelp = Caption(panel, "OPT_AFK_DESC", x, y - 260, "small")
    afkHelp:SetWidth(280)
    afkHelp:SetWordWrap(true)

    widgets.ding = Theme:CreateCheckbox(panel, "OPT_DING_SUMMARY",
        function() return ns.settings.dingSummary end,
        function(value) ns.settings.dingSummary = value end)
    widgets.ding:SetPoint("TOPLEFT", x, y - 296)

    widgets.played = Theme:CreateCheckbox(panel, "OPT_PLAYED_SILENT",
        function() return ns.settings.silentPlayed end,
        function(value) ns.settings.silentPlayed = value end)
    widgets.played:SetPoint("TOPLEFT", x, y - 322)

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
    widgets.lock:SetPoint("TOPLEFT", x, y - 54)

    widgets.perCharacter = Theme:CreateCheckbox(panel, "OPT_LAUNCHER_PER_CHAR", LauncherGetter("perCharacter"), LauncherSetter("perCharacter"))
    widgets.perCharacter:SetPoint("TOPLEFT", x, y - 80)

    Caption(panel, "OPT_LAUNCHER_TEXT", x, y - 114)
    widgets.textMode = Theme:CreateDropdown(panel, 220, function()
        local options = {}
        for _, mode in ipairs({ "eta", "percent", "rate", "remaining" }) do
            options[#options + 1] = { value = mode, label = L["TEXT_MODE_" .. mode] }
        end
        return options
    end, LauncherGetter("textMode"), LauncherSetter("textMode"))
    widgets.textMode:SetPoint("TOPLEFT", x, y - 130)

    widgets.scale = Theme:CreateSlider(panel, "OPT_LAUNCHER_SCALE", 0.6, 2, 0.05,
        function(value) return ("%d%%"):format(value * 100 + 0.5) end,
        LauncherGetter("scale"), LauncherSetter("scale"))
    widgets.scale:SetPoint("TOPLEFT", x, y - 170)
    widgets.scale:SetWidth(280)

    widgets.alpha = Theme:CreateSlider(panel, "OPT_LAUNCHER_ALPHA", 0.2, 1, 0.05,
        function(value) return ("%d%%"):format(value * 100 + 0.5) end,
        LauncherGetter("alpha"), LauncherSetter("alpha"))
    widgets.alpha:SetPoint("TOPLEFT", x, y - 218)
    widgets.alpha:SetWidth(280)

    local resetPosition = Theme:CreateButton(panel, "OPT_RESET_POSITION", 160, 22, function()
        ns.Launcher:ResetPosition()
    end)
    resetPosition:SetPoint("TOPLEFT", x, y - 270)

    ---------------------------------------------------------- Goals and alerts
    x, y = COLUMN_X[2], -440
    SectionTitle(panel, "OPT_SECTION_ALERTS", x, y)

    local alertY = y - 28
    for _, entry in ipairs({
        { "rested", "OPT_ALERT_RESTED" },
        { "goals", "OPT_ALERT_GOALS" },
        { "records", "OPT_ALERT_RECORDS" },
        { "milestones", "OPT_ALERT_MILESTONES" },
        { "sound", "OPT_ALERT_SOUND" },
    }) do
        local kind = entry[1]
        local check = Theme:CreateCheckbox(panel, entry[2],
            function() return ns.settings.alerts[kind] end,
            function(value) ns.settings.alerts[kind] = value end)
        check:SetPoint("TOPLEFT", x, alertY)
        widgets["alert_" .. kind] = check
        alertY = alertY - 24
    end

    widgets.sessionSummary = Theme:CreateCheckbox(panel, "OPT_SESSION_SUMMARY",
        function() return ns.settings.sessionSummary end,
        function(value) ns.settings.sessionSummary = value end)
    widgets.sessionSummary:SetPoint("TOPLEFT", x, alertY)

    local goalHelp = Caption(panel, "OPT_GOALS_DESC", x, alertY - 30, "small")
    goalHelp:SetWidth(280)
    goalHelp:SetWordWrap(true)

    --------------------------------------------------------------------- Data
    x, y = COLUMN_X[1], -440
    SectionTitle(panel, "OPT_SECTION_DATA", x, y)

    widgets.dataInfo = Theme:CreateText(panel, "muted")
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
    -- Stacked: side by side they overflow into the right column.
    resetAll:SetPoint("TOPLEFT", resetCharacter, "BOTTOMLEFT", 0, -6)
end

--------------------------------------------------------------------------------
-- Pet page (subcategory)
--------------------------------------------------------------------------------

local PREVIEW_SCALE = 4
local PREVIEW_STEP = 3 -- seconds per state in the preview

function Options:BuildPetPanel(panel)
    local widgets = {}
    self.petWidgets = widgets

    local title = Theme:CreateText(panel, "title")
    title:SetPoint("TOPLEFT", 16, -16)
    Theme:SetLocalizedText(title, "OPT_SECTION_PET")

    local subtitle = Theme:CreateText(panel, "muted")
    subtitle:SetPoint("TOPLEFT", 16, -42)
    Theme:SetLocalizedText(subtitle, "OPT_PET_SUBTITLE")

    ----------------------------------------------------------------- Settings
    local x, y = COLUMN_X[1], -76
    SectionTitle(panel, "OPT_SECTION_GENERAL", x, y)

    widgets.show = Theme:CreateCheckbox(panel, "OPT_PET_SHOW", PetGetter("enabled"), function(value)
        ns.Pet:SetEnabled(value)
    end)
    widgets.show:SetPoint("TOPLEFT", x, y - 28)

    widgets.lock = Theme:CreateCheckbox(panel, "OPT_LAUNCHER_LOCK", PetGetter("locked"), function(value)
        ns.Pet:SetLocked(value)
    end)
    widgets.lock:SetPoint("TOPLEFT", x, y - 54)

    widgets.maxLevel = Theme:CreateCheckbox(panel, "OPT_PET_MAX_LEVEL", PetGetter("showAtMaxLevel"), PetSetter("showAtMaxLevel"))
    widgets.maxLevel:SetPoint("TOPLEFT", x, y - 80)

    widgets.scale = Theme:CreateSlider(panel, "OPT_PET_SCALE", 1, 4, 0.5,
        function(value) return ("%gx"):format(value) end,
        PetGetter("scale"), PetSetter("scale"))
    widgets.scale:SetPoint("TOPLEFT", x, y - 114)
    widgets.scale:SetWidth(280)

    local resetPosition = Theme:CreateButton(panel, "OPT_RESET_POSITION", 160, 22, function()
        ns.Pet:ResetPosition()
    end)
    resetPosition:SetPoint("TOPLEFT", x, y - 166)

    local demo = Theme:CreateButton(panel, "OPT_PET_DEMO", 160, 22, function()
        ns.Pet:Demo()
    end)
    demo:SetPoint("TOPLEFT", resetPosition, "BOTTOMLEFT", 0, -6)

    local help = Caption(panel, "OPT_PET_DESC", x, y - 232, "small")
    help:SetWidth(280)
    help:SetWordWrap(true)

    ------------------------------------------------------------------ Preview
    x = COLUMN_X[2]
    SectionTitle(panel, "OPT_PET_PREVIEW", x, y)

    local size = 32 * PREVIEW_SCALE
    local preview = CreateFrame("Frame", nil, panel)
    preview:SetPoint("TOPLEFT", x + (280 - size) / 2, y - 32)
    preview:SetSize(size, size)
    local background = Theme:CreateTexture(preview, Theme.colors.levelBox, "BACKGROUND")
    background:SetAllPoints()
    local sprite = ns.PetSprite.Create(preview)

    local caption = Theme:CreateText(panel, "normal", "CENTER")
    caption:SetPoint("TOP", preview, "BOTTOM", 0, -8)
    caption:SetWidth(280)

    local states = ns.Pet.STATES
    local index, elapsed = 1, 0
    local function ShowState()
        local state = states[index]
        sprite:SetStage(ns.Pet.stage or 1)
        sprite:SetAnimation(state)
        if state == "ghost" then
            sprite:SetTint(unpack(ns.Pet.GHOST_TINT))
        else
            sprite:SetTint()
        end
        caption:SetText(L["PET_STAGE_" .. sprite.stage] .. ": " .. L["PET_STATE_" .. state])
    end
    preview:SetScript("OnShow", function()
        elapsed = 0
        ShowState()
    end)
    preview:SetScript("OnUpdate", function(_, delta)
        sprite:Update(delta)
        elapsed = elapsed + delta
        if elapsed >= PREVIEW_STEP then
            elapsed = 0
            index = index % #states + 1
            ShowState()
        end
    end)
    ns:RegisterMessage("XPL_LOCALE_CHANGED", ShowState)
    ShowState()

    --------------------------------------------------------------- Experience
    y = -290
    SectionTitle(panel, "OPT_SECTION_PET_XP", x, y)

    widgets.bar = Theme:CreateCheckbox(panel, "OPT_PET_BAR", PetGetter("bar"), PetSetter("bar"))
    widgets.bar:SetPoint("TOPLEFT", x, y - 28)

    widgets.badge = Theme:CreateCheckbox(panel, "OPT_PET_BADGE", PetGetter("badge"), PetSetter("badge"))
    widgets.badge:SetPoint("TOPLEFT", x, y - 54)

    Caption(panel, "OPT_PET_TEXT", x, y - 88)
    widgets.textMode = Theme:CreateDropdown(panel, 220, function()
        local options = { { value = "none", label = L["PET_TEXT_none"] } }
        for _, mode in ipairs({ "eta", "percent", "rate", "remaining" }) do
            options[#options + 1] = { value = mode, label = L["TEXT_MODE_" .. mode] }
        end
        return options
    end, PetGetter("textMode"), PetSetter("textMode"))
    widgets.textMode:SetPoint("TOPLEFT", x, y - 104)

    Caption(panel, "OPT_PET_CLICK", x, y - 138)
    widgets.clickAction = Theme:CreateDropdown(panel, 220, function()
        return {
            { value = "poke", label = L["PET_CLICK_poke"] },
            { value = "panel", label = L["PET_CLICK_panel"] },
        }
    end, PetGetter("clickAction"), PetSetter("clickAction"))
    widgets.clickAction:SetPoint("TOPLEFT", x, y - 154)

    widgets.summaryTooltip = Theme:CreateCheckbox(panel, "OPT_PET_SUMMARY", PetGetter("summaryTooltip"), PetSetter("summaryTooltip"))
    widgets.summaryTooltip:SetPoint("TOPLEFT", x, y - 188)

    local replaceHelp = Caption(panel, "OPT_PET_REPLACE_DESC", x, y - 218, "small")
    replaceHelp:SetWidth(280)
    replaceHelp:SetWordWrap(true)
end

--- Re-reads every setting into the widgets (the values can change elsewhere,
--- for example with /xpl lock or a right-click on the launcher).
function Options:Refresh()
    for _, widgets in ipairs({ self.widgets or {}, self.petWidgets or {} }) do
        for _, widget in pairs(widgets) do
            if widget.Refresh then
                widget:Refresh()
            end
        end
    end
    if self.widgets then
        self.widgets.dataInfo:SetText(L["OPT_DATA_INFO"]:format(ns.Database:CountCharacters()))
    end
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

    -- The pet has its own page under the addon's entry.
    local petPanel = CreateFrame("Frame")
    petPanel.name = L["OPT_SECTION_PET"]
    petPanel.parent = ns.title
    petPanel:Hide()
    petPanel:SetScript("OnShow", function()
        if not self.petWidgets then
            self:BuildPetPanel(petPanel)
        end
        self:Refresh()
    end)
    petPanel:SetScript("OnHide", function() Theme:CloseMenus() end)
    self.petPanel = petPanel

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, ns.title)
        if Settings.RegisterCanvasLayoutSubcategory then
            Settings.RegisterCanvasLayoutSubcategory(category, petPanel, petPanel.name)
        end
        Settings.RegisterAddOnCategory(category)
        self.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        InterfaceOptions_AddCategory(petPanel)
    end

    local function RefreshIfShown()
        if panel:IsShown() or petPanel:IsShown() then
            self:Refresh()
        end
    end
    ns:RegisterMessage("XPL_SETTINGS_CHANGED", RefreshIfShown)
    ns:RegisterMessage("XPL_LOCALE_CHANGED", RefreshIfShown)
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
