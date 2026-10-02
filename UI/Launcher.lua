--[[----------------------------------------------------------------------------
    XPLedger - Launcher
    Small movable shortcut that shows the level, the main figure (time to level
    by default), a secondary line and a thin experience bar with the rested
    overlay.

      Left-click   toggle the main window
      Right-click  lock / unlock the position
      Drag         move (when unlocked)
------------------------------------------------------------------------------]]

local _, ns = ...

local Launcher = ns:NewModule("Launcher")
local Theme = ns.Theme

local WIDTH, HEIGHT = 172, 38
local BOX_SIZE = HEIGHT
local BAR_HEIGHT = 3
local DEFAULT_POSITION = { "CENTER", "CENTER", 0, -220 }

--------------------------------------------------------------------------------
-- Settings helpers
--------------------------------------------------------------------------------

local function Settings()
    return ns.settings.launcher
end

function Launcher:IsLocked()
    return Settings().locked
end

local function GetSavedPosition()
    if Settings().perCharacter then
        return ns.char.launcherPosition
    end
    return Settings().position
end

local function SavePosition(position)
    if Settings().perCharacter then
        ns.char.launcherPosition = position
    else
        Settings().position = position
    end
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------

function Launcher:Build()
    local frame = CreateFrame("Button", "XPLedgerLauncher", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    -- The position is stored in our saved variables, not in the layout cache.
    if frame.SetDontSavePosition then
        frame:SetDontSavePosition(true)
    end
    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:RegisterForDrag("LeftButton")
    Theme:Skin(frame)

    -- Level box on the left.
    local box = CreateFrame("Frame", nil, frame)
    box:SetPoint("TOPLEFT")
    box:SetSize(BOX_SIZE, BOX_SIZE)
    local boxBackground = Theme:CreateTexture(box, { Theme.colors.accent[1], Theme.colors.accent[2], Theme.colors.accent[3], 0.14 }, "BACKGROUND", -7)
    boxBackground:SetAllPoints()
    frame.levelText = Theme:CreateText(box, 15, Theme.colors.text, "CENTER")
    frame.levelText:SetPoint("CENTER", 0, 1)

    -- Texts on the right.
    frame.primaryText = Theme:CreateText(frame, 13, Theme.colors.text)
    frame.primaryText:SetPoint("TOPLEFT", box, "TOPRIGHT", 9, -6)
    frame.primaryText:SetPoint("RIGHT", -8, 0)

    frame.secondaryText = Theme:CreateText(frame, 10, Theme.colors.muted)
    frame.secondaryText:SetPoint("TOPLEFT", frame.primaryText, "BOTTOMLEFT", 0, -3)
    frame.secondaryText:SetPoint("RIGHT", -8, 0)

    -- Experience bar along the bottom edge.
    local track = Theme:CreateTexture(frame, Theme.colors.track, "ARTWORK", 0)
    track:SetPoint("BOTTOMLEFT", 1, 1)
    track:SetPoint("BOTTOMRIGHT", -1, 1)
    track:SetHeight(BAR_HEIGHT)
    frame.barTrack = track

    frame.restedBar = Theme:CreateTexture(frame, { Theme.colors.rested[1], Theme.colors.rested[2], Theme.colors.rested[3], 0.55 }, "ARTWORK", 1)
    frame.restedBar:SetHeight(BAR_HEIGHT)

    frame.xpBar = Theme:CreateTexture(frame, Theme.colors.accent, "ARTWORK", 2)
    frame.xpBar:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT")
    frame.xpBar:SetHeight(BAR_HEIGHT)

    -- Short border flash used as feedback when the lock state changes.
    local flash = frame:CreateAnimationGroup()
    local fade = flash:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.12)
    fade:SetOrder(1)
    local back = flash:CreateAnimation("Alpha")
    back:SetFromAlpha(0.35)
    back:SetToAlpha(1)
    back:SetDuration(0.18)
    back:SetOrder(2)
    frame.flash = flash

    self:SetupScripts(frame)
    self.frame = frame
end

function Launcher:SetupScripts(frame)
    frame:SetScript("OnDragStart", function(selfFrame)
        if not Launcher:IsLocked() then
            selfFrame.dragging = true
            selfFrame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        selfFrame.dragging = false
        selfFrame.dragStoppedAt = GetTime()
        local point, _, relativePoint, x, y = selfFrame:GetPoint(1)
        SavePosition({ point, relativePoint, ns.Round(x, 1), ns.Round(y, 1) })
    end)
    frame:SetScript("OnClick", function(selfFrame, button)
        -- Ignore the click generated when a drag ends over the frame.
        if selfFrame.dragStoppedAt and GetTime() - selfFrame.dragStoppedAt < 0.2 then
            return
        end
        if button == "RightButton" then
            Launcher:SetLocked(not Launcher:IsLocked())
        elseif ns.MainPanel then
            ns.MainPanel:Toggle()
        end
    end)
    frame:SetScript("OnEnter", function(selfFrame)
        Theme:SetBorderColor(selfFrame, Theme.colors.accent, 0.5)
        GameTooltip:SetOwner(selfFrame, "ANCHOR_NONE")
        GameTooltip:SetPoint(Launcher:GetTooltipAnchor())
        ns.SummaryTooltip:Fill(GameTooltip, true)
        GameTooltip:Show()
        selfFrame.hovered = true
    end)
    frame:SetScript("OnLeave", function(selfFrame)
        Theme:SetBorderColor(selfFrame, Theme.colors.border)
        GameTooltip:Hide()
        selfFrame.hovered = false
    end)
end

--- Places the tooltip above or below the launcher depending on screen space.
function Launcher:GetTooltipAnchor()
    local frame = self.frame
    local _, centerY = frame:GetCenter()
    if centerY and centerY > UIParent:GetHeight() / 2 then
        return "TOP", frame, "BOTTOM", 0, -4
    end
    return "BOTTOM", frame, "TOP", 0, 4
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function Launcher:ApplyPosition()
    local position = GetSavedPosition() or DEFAULT_POSITION
    self.frame:ClearAllPoints()
    self.frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
end

function Launcher:ApplySettings()
    local frame = self.frame
    if not frame then
        return
    end
    frame:SetScale(Settings().scale)
    frame:SetAlpha(Settings().alpha)
    self:ApplyPosition()
    self:UpdateVisibility()
    self:Update()
end

function Launcher:UpdateVisibility()
    local settings = Settings()
    local shown = settings.shown
    if shown and settings.hideAtMax and ns.Compat.IsExperienceBlocked() and not ns.Compat.IsExperienceDisabledByUser() then
        shown = false
    end
    self.frame:SetShown(shown)
end

--- Locks or unlocks the position, with visual and chat feedback.
function Launcher:SetLocked(locked)
    Settings().locked = locked and true or false
    if self.frame then
        self.frame.flash:Play()
        if self.frame.hovered then
            self.frame:GetScript("OnEnter")(self.frame)
        end
    end
    ns:Print(locked and ns.L["LAUNCHER_LOCKED"] or ns.L["LAUNCHER_UNLOCKED"])
    ns:SendMessage("XPL_SETTINGS_CHANGED")
end

--- Shows or hides the launcher permanently (saved setting).
function Launcher:SetShown(shown)
    Settings().shown = shown and true or false
    self:UpdateVisibility()
    if not shown then
        ns:Print(ns.L["LAUNCHER_HIDDEN"])
    end
    ns:SendMessage("XPL_SETTINGS_CHANGED")
end

function Launcher:ResetPosition()
    SavePosition(nil)
    self:ApplyPosition()
    ns:Print(ns.L["LAUNCHER_POSITION_RESET"])
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------

local function FormatRate(rate)
    return rate and (ns.FormatNumber(rate) .. "/h") or ("-- /h")
end

--- Returns the primary and secondary texts for the configured text mode.
local function BuildTexts(estimate)
    local L = ns.L
    if estimate.disabled then
        return L["TOOLTIP_XP_DISABLED"], ""
    end
    if estimate.atMaxLevel or estimate.blocked then
        return L["LAUNCHER_MAX_LEVEL"], ""
    end

    local percent = ("%.1f%%"):format(estimate.progress * 100)
    local rate = estimate.rate or estimate.sessionRate
    local eta = estimate.eta and ns.FormatDuration(estimate.eta) or L["DURATION_UNKNOWN"]
    if estimate.idle and estimate.eta then
        eta = L["LAUNCHER_IDLE"]
    end

    local mode = Settings().textMode
    if mode == "percent" then
        return percent, eta .. "  ·  " .. FormatRate(rate)
    elseif mode == "rate" then
        return FormatRate(rate), percent .. "  ·  " .. eta
    elseif mode == "remaining" then
        return ns.FormatNumber(estimate.remaining) .. " XP", percent .. "  ·  " .. eta
    end
    return eta, percent .. "  ·  " .. FormatRate(rate)
end

function Launcher:Update()
    local frame = self.frame
    if not frame or not frame:IsShown() then
        return
    end
    local estimate = ns.Tracker:GetEstimate()
    frame.levelText:SetText(estimate.level)

    local primary, secondary = BuildTexts(estimate)
    frame.primaryText:SetText(primary)
    frame.secondaryText:SetText(secondary)

    local width = frame.barTrack:GetWidth()
    if width and width > 0 then
        local progress = ns.Clamp(estimate.progress, 0, 1)
        local restedEnd = estimate.maxXP > 0 and ns.Clamp((estimate.xp + estimate.rested) / estimate.maxXP, 0, 1) or 0
        frame.xpBar:SetWidth(math.max(1, width * progress))
        frame.xpBar:SetShown(progress > 0)

        frame.restedBar:ClearAllPoints()
        frame.restedBar:SetPoint("BOTTOMLEFT", frame.barTrack, "BOTTOMLEFT", width * progress, 0)
        frame.restedBar:SetWidth(math.max(1, width * (restedEnd - progress)))
        frame.restedBar:SetShown(restedEnd > progress)
    end

    if frame.hovered and GameTooltip:IsOwned(frame) then
        GameTooltip:ClearLines()
        ns.SummaryTooltip:Fill(GameTooltip, true)
        GameTooltip:Show()
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Launcher:OnLogin()
    self:Build()
    self:ApplySettings()

    local function Refresh()
        self:UpdateVisibility()
        self:Update()
    end
    ns:RegisterMessage("XPL_TICK", function() self:Update() end)
    ns:RegisterMessage("XPL_STATE_CHANGED", Refresh)
    ns:RegisterMessage("XPL_XP_GAINED", Refresh)
    ns:RegisterMessage("XPL_LOCALE_CHANGED", Refresh)
    ns:RegisterMessage("XPL_SETTINGS_CHANGED", function() self:ApplySettings() end)
end
