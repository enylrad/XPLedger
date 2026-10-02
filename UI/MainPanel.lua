--[[----------------------------------------------------------------------------
    XPLedger - Main panel
    Movable window opened from the launcher. It is a shell that hosts views
    registered by the files in UI\Views; each view is a tab.

    View contract:
      view.id          unique id, also stored as the last selected tab
      view.label       locale key of the tab title
      view:Build(content)   called once, the first time the view is shown
      view:Refresh()        redraws the view with fresh data
      view:OnTick()         optional, called every second while visible
      view.followsSelection true when the view inspects the character picked
                            in the Characters tab instead of the logged one

    The panel is created lazily the first time it is opened.
------------------------------------------------------------------------------]]

local _, ns = ...

local MainPanel = ns:NewModule("MainPanel")
local Theme = ns.Theme

local WIDTH, HEIGHT = 640, 440
local REFRESH_THROTTLE = 0.5

MainPanel.views = {}

--------------------------------------------------------------------------------
-- View registry and shared state
--------------------------------------------------------------------------------

--- Registers a view. Views are shown as tabs in registration order.
function MainPanel:RegisterView(view)
    self.views[#self.views + 1] = view
end

--- Returns the key of the character inspected by the views (default: self).
function MainPanel:GetViewedKey()
    if self.viewedKey and ns.db.characters[self.viewedKey] then
        return self.viewedKey
    end
    return ns.charKey
end

--- Returns the record of the character inspected by the views.
function MainPanel:GetViewedRecord()
    return ns.db.characters[self:GetViewedKey()]
end

--- Changes the inspected character and refreshes the visible view.
function MainPanel:SetViewedKey(key)
    self.viewedKey = key
    self:UpdateHeader()
    self:Refresh()
end

--- Returns the colored display name of a character record.
function MainPanel.FormatCharacterName(record, withRealm)
    if not record then
        return "?"
    end
    local name = record.name or "?"
    if withRealm and record.realm then
        name = name .. "-" .. record.realm
    end
    return ns.ColorizeByClass(name, record.class)
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------

function MainPanel:Build()
    local frame = CreateFrame("Frame", "XPLedgerMainPanel", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = selfFrame:GetPoint(1)
        ns.settings.panel.position = { point, relativePoint, ns.Round(x, 1), ns.Round(y, 1) }
    end)
    Theme:Skin(frame, { 0.05, 0.06, 0.08, 0.96 }, { 1, 1, 1, 0.10 })
    frame:Hide()

    -- Close with Escape.
    tinsert(UISpecialFrames, frame:GetName())

    local title = Theme:CreateText(frame, 15)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(Theme.Hex(Theme.colors.accent) .. "XP|rLedger")

    frame.subtitle = Theme:CreateText(frame, 11, Theme.colors.muted)
    frame.subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -8, -8)
    close.text = Theme:CreateText(close, 16, Theme.colors.muted, "CENTER")
    close.text:SetPoint("CENTER")
    close.text:SetText("×")
    close:SetScript("OnEnter", function() close.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function()
        close.text:SetTextColor(Theme.colors.muted[1], Theme.colors.muted[2], Theme.colors.muted[3])
    end)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Tabs.
    frame.tabs = {}
    local previous
    for _, view in ipairs(self.views) do
        local tab = Theme:CreateTab(frame, view.label, function() self:SelectView(view.id) end)
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            tab:SetPoint("TOPLEFT", 10, -38)
        end
        tab.view = view
        frame.tabs[view.id] = tab
        previous = tab
    end

    local separator = Theme:CreateTexture(frame, Theme.colors.border)
    separator:SetPoint("TOPLEFT", 1, -62)
    separator:SetPoint("TOPRIGHT", -1, -62)
    separator:SetHeight(1)

    -- One content frame per view, created when the view is first shown.
    frame.contents = {}

    frame:SetScript("OnShow", function()
        self:UpdateHeader()
        self:Refresh()
    end)
    frame:SetScript("OnHide", function() Theme:CloseMenus() end)

    self.frame = frame
    self:ApplyPosition()
    self:SelectView(ns.settings.panel.tab)
end

function MainPanel:ApplyPosition()
    local position = ns.settings.panel.position
    self.frame:ClearAllPoints()
    if position then
        self.frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    else
        self.frame:SetPoint("CENTER", 0, 40)
    end
end

function MainPanel:UpdateHeader()
    if not self.frame then
        return
    end
    -- Views flagged with followsSelection inspect the selected character;
    -- the others always show the logged one.
    local record = ns.char
    if self.activeView and self.activeView.followsSelection then
        record = self:GetViewedRecord()
    end
    local level = record and record.level or 0
    self.frame.subtitle:SetText(ns.L["VIEWING_CHARACTER"]:format(
        self.FormatCharacterName(record, true) .. "  " .. ns.L["LEVEL_SHORT"]:format(level)))
    for _, tab in pairs(self.frame.tabs) do
        tab:UpdateWidth()
    end
end

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

local function FindView(self, id)
    for _, view in ipairs(self.views) do
        if view.id == id then
            return view
        end
    end
    return self.views[1]
end

function MainPanel:SelectView(id)
    local view = FindView(self, id)
    local frame = self.frame
    Theme:CloseMenus()

    local content = frame.contents[view.id]
    if not content then
        content = CreateFrame("Frame", nil, frame)
        content:SetPoint("TOPLEFT", 14, -72)
        content:SetPoint("BOTTOMRIGHT", -14, 14)
        view:Build(content)
        frame.contents[view.id] = content
    end
    for viewId, other in pairs(frame.contents) do
        other:SetShown(viewId == view.id)
    end
    for viewId, tab in pairs(frame.tabs) do
        tab:SetSelected(viewId == view.id)
    end

    self.activeView = view
    ns.settings.panel.tab = view.id
    self:UpdateHeader()
    view:Refresh()
end

--- Redraws the visible view (throttled).
function MainPanel:Refresh()
    if not self.frame or not self.frame:IsShown() or not self.activeView then
        return
    end
    local now = GetTime()
    if self.lastRefresh and now - self.lastRefresh < REFRESH_THROTTLE then
        if not self.refreshQueued then
            self.refreshQueued = true
            C_Timer.After(REFRESH_THROTTLE, function()
                self.refreshQueued = false
                self:Refresh()
            end)
        end
        return
    end
    self.lastRefresh = now
    self.activeView:Refresh()
end

function MainPanel:Toggle()
    if not self.frame then
        self:Build()
    end
    self.frame:SetShown(not self.frame:IsShown())
end

function MainPanel:Show(viewId)
    if not self.frame then
        self:Build()
    end
    self.frame:Show()
    if viewId then
        self:SelectView(viewId)
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function MainPanel:OnLogin()
    ns:RegisterMessage("XPL_XP_GAINED", function() self:Refresh() end)
    ns:RegisterMessage("XPL_STATE_CHANGED", function() self:Refresh() end)
    ns:RegisterMessage("XPL_DATA_RESET", function(_, key)
        if key == self.viewedKey and not ns.db.characters[key] then
            self.viewedKey = nil
        end
        self:UpdateHeader()
        self:Refresh()
    end)
    ns:RegisterMessage("XPL_LOCALE_CHANGED", function()
        self:UpdateHeader()
        self:Refresh()
    end)
    ns:RegisterMessage("XPL_TICK", function()
        local view = self.activeView
        if view and view.OnTick and self.frame and self.frame:IsShown() then
            view:OnTick()
        end
    end)
end
