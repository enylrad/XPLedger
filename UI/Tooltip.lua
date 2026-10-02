--[[----------------------------------------------------------------------------
    XPLedger - Summary tooltip
    Fills any GameTooltip-like object with the current experience summary.
    Shared by the launcher, the data broker feed and the addon compartment.
------------------------------------------------------------------------------]]

local _, ns = ...

local SummaryTooltip = {}
ns.SummaryTooltip = SummaryTooltip

local function Percent(part, whole)
    if not whole or whole <= 0 then
        return 0
    end
    return part / whole * 100
end

--- Adds the summary lines to a tooltip.
--- @param tooltip table GameTooltip or compatible object
--- @param hints boolean include the mouse usage hints of the launcher
function SummaryTooltip:Fill(tooltip, hints)
    local L, Theme = ns.L, ns.Theme
    local muted, accent = Theme.colors.muted, Theme.colors.accent
    local estimate = ns.Tracker:GetEstimate()

    tooltip:AddLine("XPLedger", accent[1], accent[2], accent[3])
    tooltip:AddLine(L["TOOLTIP_LEVEL"]:format(estimate.level), 1, 1, 1)

    if estimate.disabled then
        tooltip:AddLine(L["TOOLTIP_XP_DISABLED"], muted[1], muted[2], muted[3])
    elseif estimate.atMaxLevel or estimate.blocked then
        tooltip:AddLine(L["TOOLTIP_MAX_LEVEL"], muted[1], muted[2], muted[3])
    else
        local function Row(label, value)
            tooltip:AddDoubleLine(label, value, muted[1], muted[2], muted[3], 1, 1, 1)
        end

        Row(L["TOOLTIP_XP"], ("%s / %s (%.1f%%)"):format(ns.FormatInteger(estimate.xp),
            ns.FormatInteger(estimate.maxXP), estimate.progress * 100))
        Row(L["TOOLTIP_REMAINING"], ns.FormatInteger(estimate.remaining))
        if estimate.rested > 0 then
            Row(L["TOOLTIP_RESTED"], ("%s (%.0f%%)"):format(ns.FormatInteger(estimate.rested),
                Percent(estimate.rested, estimate.maxXP)))
        end

        tooltip:AddLine(" ")
        local window = L["WINDOW_LAST_MINUTES"]:format(estimate.windowMinutes)
        Row(L["TOOLTIP_RATE"]:format(window), estimate.rate and ns.FormatNumber(estimate.rate) or L["DURATION_UNKNOWN"])
        Row(L["TOOLTIP_RATE_SESSION"], estimate.sessionRate and ns.FormatNumber(estimate.sessionRate) or L["DURATION_UNKNOWN"])
        Row(L["TOOLTIP_ETA"], ns.FormatDuration(estimate.eta))
        if estimate.killsToLevel then
            Row(L["TOOLTIP_KILLS_TO_LEVEL"], ns.FormatInteger(estimate.killsToLevel))
        end
        if estimate.questsToLevel then
            Row(L["TOOLTIP_QUESTS_TO_LEVEL"], ns.FormatInteger(estimate.questsToLevel))
        end
        if not estimate.eta then
            tooltip:AddLine(L["TOOLTIP_NO_DATA"], muted[1], muted[2], muted[3], true)
        elseif estimate.idle then
            tooltip:AddLine(L["TOOLTIP_IDLE"], Theme.colors.warning[1], Theme.colors.warning[2], Theme.colors.warning[3], true)
        end

        tooltip:AddLine(" ")
        Row(L["TOOLTIP_SESSION_XP"], ns.FormatInteger(estimate.sessionXP))
        Row(L["TOOLTIP_SESSION_TIME"], ns.FormatDuration(estimate.sessionTime))
        local levelPlayed = ns.History:GetLevelPlayed(ns.char, estimate.level)
        if levelPlayed then
            Row(L["TOOLTIP_LEVEL_TIME"], ns.FormatDuration(levelPlayed))
        end
    end

    if hints then
        tooltip:AddLine(" ")
        tooltip:AddLine(L["TOOLTIP_HINT_CLICK"], muted[1], muted[2], muted[3])
        if ns.Launcher:IsLocked() then
            tooltip:AddLine(L["TOOLTIP_HINT_UNLOCK"], muted[1], muted[2], muted[3])
        else
            tooltip:AddLine(L["TOOLTIP_HINT_LOCK"], muted[1], muted[2], muted[3])
            tooltip:AddLine(L["TOOLTIP_HINT_DRAG"], muted[1], muted[2], muted[3])
        end
    end
end
