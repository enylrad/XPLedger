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

    -- Level up summary. It only pops up on its own in WoW Forever, but it is
    -- configurable everywhere (and /xpl levelup demo works in every client).
    do
        alertY = alertY - 24
        local parts = {}
        local function UpdateParts()
            local enabled = ns.settings.levelUpSplash and true or false
            for _, check in ipairs(parts) do
                check:SetEnabled(enabled)
                -- The label is .label in the Blizzard skin and .text in Minimal.
                local label = check.label or check.text
                if label then
                    label:SetAlpha(enabled and 1 or 0.4)
                end
            end
        end
        widgets.levelUpSplash = Theme:CreateCheckbox(panel, "OPT_LEVELUP_SPLASH",
            function() return ns.settings.levelUpSplash end,
            function(value)
                ns.settings.levelUpSplash = value
                UpdateParts()
            end)
        widgets.levelUpSplash:SetPoint("TOPLEFT", x, alertY)

        -- What the summary shows, indented under it.
        for _, entry in ipairs({
            { "portrait", "OPT_LEVELUP_PORTRAIT" },
            { "stats", "OPT_LEVELUP_STATS" },
            { "spells", "OPT_LEVELUP_SPELLS" },
            { "zones", "OPT_LEVELUP_ZONES" },
        }) do
            local key = entry[1]
            alertY = alertY - 24
            local check = Theme:CreateCheckbox(panel, entry[2],
                function() return ns.settings.levelUpParts[key] end,
                function(value) ns.settings.levelUpParts[key] = value end)
            check:SetPoint("TOPLEFT", x + 20, alertY)
            widgets["levelUp_" .. key] = check
            parts[#parts + 1] = check
        end

        widgets.levelUpScale = Theme:CreateSlider(panel, "OPT_LEVELUP_SCALE", 0.6, 1.2, 0.05,
            function(value) return ("%d%%"):format(value * 100 + 0.5) end,
            function() return ns.settings.levelUpScale end,
            function(value)
                ns.settings.levelUpScale = value
                -- Resize a summary on screen right away, to see the result.
                local shown = _G.XPLedgerLevelUpFrame
                if shown and shown:IsShown() then
                    shown:SetScale(value)
                end
            end)
        widgets.levelUpScale:SetPoint("TOPLEFT", x + 20, alertY - 30)
        widgets.levelUpScale:SetWidth(260)
        alertY = alertY - 54
        UpdateParts()

        if ns.Compat.flavor ~= "forever" then
            local note = Caption(panel, "OPT_LEVELUP_FOREVER_ONLY", x + 20, alertY - 28, "small")
            note:SetWidth(260)
            note:SetWordWrap(true)
            alertY = alertY - 28 - note:GetStringHeight()
        end
    end

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

    Caption(panel, "OPT_PET_SPECIES", x, y - 114)
    widgets.species = Theme:CreateDropdown(panel, 220, function()
        local options = {}
        for _, species in ipairs(ns.PetSprite.SPECIES) do
            options[#options + 1] = { value = species, label = L["PET_SPECIES_" .. species] }
        end
        return options
    end, function() return ns.Pet:GetSpecies() end, function(value)
        ns.Pet:SetSpecies(value)
        if self.refreshPetPreview then
            self.refreshPetPreview()
        end
        if self.updatePetHarsh then
            self.updatePetHarsh()
        end
    end)
    widgets.species:SetPoint("TOPLEFT", x, y - 130)

    widgets.scale = Theme:CreateSlider(panel, "OPT_PET_SCALE", 1, 4, 0.5,
        function(value) return ("%gx"):format(value) end,
        PetGetter("scale"), PetSetter("scale"))
    widgets.scale:SetPoint("TOPLEFT", x, y - 180)
    widgets.scale:SetWidth(280)

    local resetPosition = Theme:CreateButton(panel, "OPT_RESET_POSITION", 160, 22, function()
        ns.Pet:ResetPosition()
    end)
    resetPosition:SetPoint("TOPLEFT", x, y - 232)

    local demo = Theme:CreateButton(panel, "OPT_PET_DEMO", 160, 22, function()
        ns.Pet:Demo()
    end)
    demo:SetPoint("TOPLEFT", resetPosition, "BOTTOMLEFT", 0, -6)

    local help = Caption(panel, "OPT_PET_DESC", x, y - 298, "small")
    help:SetWidth(280)
    help:SetWordWrap(true)

    ------------------------------------------------------------ What it says
    -- Below the help text, whatever its height in each language.
    local talk = CreateFrame("Frame", nil, panel)
    talk:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -24)
    talk:SetSize(300, 326)
    SectionTitle(talk, "OPT_SECTION_PET_TALK", 0, 0)

    Caption(talk, "OPT_PET_LANGUAGE", 0, -30)
    widgets.petLocale = Theme:CreateDropdown(talk, 220, function()
        local options = { { value = "auto", label = L["OPT_PET_LANGUAGE_AUTO"] } }
        for _, code in ipairs(ns.AVAILABLE_LOCALES) do
            if code ~= "auto" then
                options[#options + 1] = { value = code, label = L["LANGUAGE_" .. code] }
            end
        end
        return options
    end, PetGetter("locale"), PetSetter("locale"))
    widgets.petLocale:SetPoint("TOPLEFT", 0, -46)

    -- Unfiltered voice: only the species that have one (Nihil) can use it.
    widgets.harsh = Theme:CreateCheckbox(talk, "OPT_PET_HARSH", PetGetter("harsh"), PetSetter("harsh"))
    widgets.harsh:SetPoint("TOPLEFT", 0, -82)
    local harshHelp = Caption(talk, "OPT_PET_HARSH_DESC", 26, -106, "small")
    harshHelp:SetWidth(254)
    harshHelp:SetWordWrap(true)
    -- Who the unfiltered voice was made for (Pet.DEDICATIONS).
    local dedication = Theme:CreateText(talk, "small")
    dedication:SetPoint("TOPLEFT", harshHelp, "BOTTOMLEFT", 0, -4)
    dedication:SetTextColor(1, 0.62, 0.82)
    local function UpdateHarsh()
        local species = ns.Pet:GetSpecies()
        local available = ns.PetTalk:HasHarshVoice(species)
        widgets.harsh:SetEnabled(available)
        widgets.harsh:SetAlpha(available and 1 or 0.4)
        harshHelp:SetAlpha(available and 1 or 0.4)
        local key = ns.Pet.DEDICATIONS[species]
        dedication:SetText(available and key and (L[key] .. " " .. ns.Pet.HeartIcon(12)) or "")
    end
    self.updatePetHarsh = UpdateHarsh
    UpdateHarsh()

    local function UpdateCheer()
        widgets.cheerInterval:SetAlpha(ns.settings.pet.cheer and 1 or 0.4)
    end
    widgets.cheer = Theme:CreateCheckbox(talk, "OPT_PET_CHEER", PetGetter("cheer"), function(value)
        ns.settings.pet.cheer = value
        UpdateCheer()
    end)
    widgets.cheer:SetPoint("TOPLEFT", 0, -158)

    -- The slider moves over the steps of PetTalk.INTERVALS (20 s to 30 min).
    local intervals = ns.PetTalk.INTERVALS
    local function IntervalText(step)
        local seconds = intervals[step] or intervals[#intervals]
        if seconds < 60 then
            return L["OPT_PET_CHEER_SECONDS"]:format(seconds)
        end
        return L["OPT_PET_CHEER_MINUTES"]:format(seconds / 60)
    end
    widgets.cheerInterval = Theme:CreateSlider(talk, "OPT_PET_CHEER_INTERVAL", 1, #intervals, 1,
        function(step) return IntervalText(math.floor(step + 0.5)) end,
        function()
            -- The step closest to the saved number of seconds.
            local seconds, best = ns.PetTalk:GetInterval(), 1
            for step, value in ipairs(intervals) do
                if math.abs(value - seconds) < math.abs(intervals[best] - seconds) then
                    best = step
                end
            end
            return best
        end,
        function(step)
            ns.settings.pet.cheerSeconds = intervals[math.floor(step + 0.5)] or intervals[#intervals]
            ns.PetTalk:Reschedule()
        end)
    widgets.cheerInterval:SetPoint("TOPLEFT", 20, -192)
    widgets.cheerInterval:SetWidth(260)
    UpdateCheer()

    local testCheer = Theme:CreateButton(talk, "OPT_PET_CHEER_TEST", 160, 22, function()
        if not ns.PetTalk:Cheer() then
            ns:Print(L["OPT_PET_CHEER_HIDDEN"])
        end
    end)
    testCheer:SetPoint("TOPLEFT", 0, -238)

    local talkHelp = Caption(talk, "OPT_PET_CHEER_DESC", 0, -270, "small")
    talkHelp:SetWidth(280)
    talkHelp:SetWordWrap(true)

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
        sprite:SetSpecies(ns.Pet:GetSpecies())
        sprite:SetAnimation(state)
        if state == "ghost" then
            sprite:SetTint(unpack(ns.Pet.GHOST_TINT))
        else
            sprite:SetTint()
        end
        caption:SetText(L["PET_STATE_" .. state])
    end
    self.refreshPetPreview = ShowState
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

--- Gives a settings page a vertical scroll: the widgets are built inside a
--- scroll child, so a page taller than the settings window is not cut off.
local function CreateScrollPage(page)
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
    end)
    -- Open dropdown menus would stay behind while the page moves.
    scroll:HookScript("OnVerticalScroll", function() Theme:CloseMenus() end)
    page.scroll, page.content = scroll, content
    return content
end

--- Sizes the scroll child to its lowest visible element.
local function FitContent(content)
    local top = content:GetTop()
    if not top then
        return
    end
    local lowest = top
    local function Check(...)
        for i = 1, select("#", ...) do
            local object = select(i, ...)
            local bottom = object:IsShown() and object:GetBottom()
            if bottom and bottom < lowest then
                lowest = bottom
            end
        end
    end
    Check(content:GetChildren())
    Check(content:GetRegions())
    content:SetHeight(math.max(1, top - lowest + 16))
end

--- Creates a settings page that builds its widgets on first show.
local function CreatePage(name, build, isBuilt)
    local page = CreateFrame("Frame")
    page.name = name
    page:Hide()
    local content = CreateScrollPage(page)
    page:SetScript("OnShow", function()
        content:SetWidth(page.scroll:GetWidth())
        if not isBuilt() then
            build(content)
        end
        Options:Refresh()
        -- Positions are only known once the frame is laid out.
        C_Timer.After(0, function() FitContent(content) end)
    end)
    page:SetScript("OnHide", function() Theme:CloseMenus() end)
    return page
end

function Options:OnLogin()
    local panel = CreatePage(ns.title,
        function(content) self:BuildPanel(content) end,
        function() return self.widgets ~= nil end)
    self.panel = panel

    -- The pet has its own page under the addon's entry.
    local petPanel = CreatePage(L["OPT_SECTION_PET"],
        function(content) self:BuildPetPanel(content) end,
        function() return self.petWidgets ~= nil end)
    petPanel.parent = ns.title
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
