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

-- Size of the area handed to the views; the skin builds the window around it.
local CONTENT_WIDTH, CONTENT_HEIGHT = 612, 354
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

local function PlayWindowSound(kit)
    if PlaySound and SOUNDKIT and SOUNDKIT[kit] then
        PlaySound(SOUNDKIT[kit])
    end
end

function MainPanel:Build()
    local frame = Theme:CreateWindow("XPLedgerMainPanel", CONTENT_WIDTH, CONTENT_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    if frame.SetDontSavePosition then
        frame:SetDontSavePosition(true)
    end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = selfFrame:GetPoint(1)
        ns.settings.panel.position = { point, relativePoint, ns.Round(x, 1), ns.Round(y, 1) }
    end)
    frame:Hide()

    -- Close with Escape.
    tinsert(UISpecialFrames, frame:GetName())

    -- Tabs.
    frame.tabs = {}
    local previous
    for _, view in ipairs(self.views) do
        local tab = Theme:CreateTab(frame, view.label, function()
            PlayWindowSound("IG_CHARACTER_INFO_TAB")
            self:SelectView(view.id)
        end)
        Theme:PlaceTab(frame, tab, previous)
        tab.view = view
        frame.tabs[view.id] = tab
        previous = tab
    end

    -- One content frame per view, created when the view is first shown.
    frame.contents = {}

    -- Hooked rather than set: native window templates have their own scripts.
    frame:HookScript("OnShow", function()
        PlayWindowSound("IG_CHARACTER_INFO_OPEN")
        self:UpdateHeader()
        self:Refresh()
    end)
    frame:HookScript("OnHide", function()
        PlayWindowSound("IG_CHARACTER_INFO_CLOSE")
        Theme:CloseMenus()
    end)

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
    local levelText = "  " .. ns.L["LEVEL_SHORT"]:format(level)
    for _, tab in pairs(self.frame.tabs) do
        tab:UpdateWidth()
    end
    -- Shorter forms of the subtitle, used when the full one reaches the tabs.
    local forms = {
        ns.L["VIEWING_CHARACTER"]:format(self.FormatCharacterName(record, true) .. levelText),
        self.FormatCharacterName(record, true) .. levelText,
        self.FormatCharacterName(record, false) .. levelText,
    }
    local subtitle = self.frame.subtitle
    for _, text in ipairs(forms) do
        subtitle:SetText(text)
        if not self:SubtitleOverlapsTabs() then
            break
        end
    end
end

--- True when the subtitle shares the tab row and runs into the last tab.
function MainPanel:SubtitleOverlapsTabs()
    local subtitle, lastTab = self.frame.subtitle, self.frame.tabs[self.views[#self.views].id]
    local right = lastTab and lastTab:GetRight()
    local subtitleRight = subtitle:GetRight()
    if not right or not subtitleRight or not subtitle:GetTop() or not lastTab:GetTop() then
        return false
    end
    local sameRow = subtitle:GetBottom() < lastTab:GetTop() and subtitle:GetTop() > lastTab:GetBottom()
    return sameRow and subtitleRight - subtitle:GetStringWidth() < right + 8
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
        content = CreateFrame("Frame", nil, frame.contentArea)
        content:SetAllPoints(frame.contentArea)
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
    ns:RegisterMessage("XPL_RUN_FINISHED", function() self:Refresh() end)
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
