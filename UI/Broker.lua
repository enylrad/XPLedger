--[[----------------------------------------------------------------------------
    XPLedger - Data broker and addon compartment
    Publishes a LibDataBroker feed (Titan Panel, ElvUI, Bazooka, ChocolateBar...)
    and handles the addon compartment entry of mainline-API clients (the
    compartment callbacks are declared in the TOC).
------------------------------------------------------------------------------]]

local _, ns = ...

local Broker = ns:NewModule("Broker")

local ICON = "Interface\\Icons\\INV_Misc_Book_09"

--- Builds the short text shown by broker displays.
local function BuildText()
    local estimate = ns.Tracker:GetEstimate()
    if estimate.atMaxLevel or estimate.blocked then
        return ns.L["LAUNCHER_MAX_LEVEL"]
    end
    local eta = ns.FormatDuration(estimate.eta)
    return ("%.1f%%  ·  %s"):format(estimate.progress * 100, eta)
end

local function HandleClick(button)
    if button == "RightButton" then
        ns.Options:Open()
    else
        ns.MainPanel:Toggle()
    end
end

function Broker:OnLogin()
    local LibStub = _G.LibStub
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB then
        return
    end

    self.dataObject = LDB:NewDataObject(ns.title, {
        type = "data source",
        label = "XP",
        text = "",
        icon = ICON,
        OnClick = function(_, button) HandleClick(button) end,
        OnTooltipShow = function(tooltip) ns.SummaryTooltip:Fill(tooltip, false) end,
    })

    local lastText
    local function Update()
        local text = BuildText()
        if text ~= lastText then
            lastText = text
            self.dataObject.text = text
        end
    end

    -- Broker displays redraw on every change, so update at a calmer pace.
    local ticks = 0
    ns:RegisterMessage("XPL_TICK", function()
        ticks = ticks + 1
        if ticks % 5 == 0 then
            Update()
        end
    end)
    ns:RegisterMessage("XPL_XP_GAINED", Update)
    ns:RegisterMessage("XPL_LOCALE_CHANGED", Update)
    Update()
end

--------------------------------------------------------------------------------
-- Addon compartment (globals referenced from the TOC)
--------------------------------------------------------------------------------

function XPLedger_OnAddonCompartmentClick(_, buttonName)
    HandleClick(buttonName)
end

function XPLedger_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    ns.SummaryTooltip:Fill(GameTooltip, false)
    GameTooltip:Show()
end

function XPLedger_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
