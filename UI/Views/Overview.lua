--[[----------------------------------------------------------------------------
    XPLedger - Overview view
    Live figures of the logged character: stat tiles, level progress over a
    selectable time range and the XP/hour of the session in time blocks.
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = ns.Theme
local L = ns.L

local Overview = { id = "overview", label = "TAB_OVERVIEW" }

local CONTENT_WIDTH = 612
local TILE_GAP = 8
local MAX_RATE_BLOCKS = 36
local GRAPH_REFRESH_SECONDS = 30

local RANGES = {
    { value = "session", label = "RANGE_SESSION" },
    { value = "day", label = "RANGE_DAY" },
    { value = "week", label = "RANGE_WEEK" },
    { value = "all", label = "RANGE_ALL" },
}

--------------------------------------------------------------------------------
-- Formatting helpers
--------------------------------------------------------------------------------

--- Formats a level value without trailing zeros (34.50 -> 34.5, 35.00 -> 35).
local function FormatLevelValue(value)
    local text = ("%.2f"):format(value)
    text = text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return text
end

local function GetRangeStart(range)
    local now = time()
    if range == "day" then
        return now - 86400
    elseif range == "week" then
        return now - 7 * 86400
    elseif range == "all" then
        return 0
    end
    return ns.Tracker:GetSession().startedAt
end

--------------------------------------------------------------------------------
-- Data builders
--------------------------------------------------------------------------------

--- Builds the level progress points (time, level + fraction) of the range.
local function BuildProgressPoints(range)
    local since = GetRangeStart(range)
    local samples = ns.char.samples
    local points = {}
    for i = 1, #samples.t do
        if samples.t[i] >= since then
            points[#points + 1] = { samples.t[i], samples.v[i] }
        end
    end
    -- Live point so the line always reaches "now".
    local xp, maxXP, level = ns.Tracker:GetSnapshot()
    if xp and maxXP and level and maxXP > 0 then
        points[#points + 1] = { time(), level + xp / maxXP }
    end
    return points
end

--- Groups the session gains into time blocks expressed as XP/hour.
local function BuildRateBlocks()
    local session = ns.Tracker:GetSession()
    local now = time()
    local elapsed = math.max(60, now - session.startedAt)
    local blockMinutes = math.max(5, 5 * math.ceil(elapsed / 60 / MAX_RATE_BLOCKS / 5))
    local blockSeconds = blockMinutes * 60
    local count = math.max(1, math.ceil(elapsed / blockSeconds))

    local sums = {}
    local t, a = session.gains.t, session.gains.a
    for i = 1, #t do
        local index = math.floor((t[i] - session.startedAt) / blockSeconds) + 1
        if index >= 1 and index <= count then
            sums[index] = (sums[index] or 0) + a[i]
        end
    end

    local groups = {}
    local accent = Theme.colors.accent
    for index = 1, count do
        local blockStart = session.startedAt + (index - 1) * blockSeconds
        local blockEnd = math.min(now, blockStart + blockSeconds)
        local duration = math.max(60, blockEnd - blockStart)
        local xp = sums[index] or 0
        local rate = xp * 3600 / duration
        groups[index] = {
            label = date("%H:%M", blockStart),
            stacks = { { { value = rate, color = accent } } },
            blockStart = blockStart,
            blockEnd = blockEnd,
            xp = xp,
            rate = rate,
        }
    end
    return groups, blockMinutes
end

--------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------

function Overview:Build(content)
    self.content = content

    local tileWidth = (CONTENT_WIDTH - TILE_GAP * 3) / 4
    self.tiles = {}
    for index, key in ipairs({ "STAT_RATE", "STAT_ETA", "STAT_SESSION_XP", "STAT_SESSION_TIME" }) do
        local tile = Theme:CreateStat(content, key)
        tile:SetWidth(tileWidth)
        tile:SetPoint("TOPLEFT", (index - 1) * (tileWidth + TILE_GAP), 0)
        self.tiles[index] = tile
    end

    -- Actions left to level up, under the tiles.
    self.actions = Theme:CreateText(content, "muted")
    self.actions:SetPoint("TOPLEFT", 2, -54)
    self.actions:SetPoint("RIGHT", 0, 0)

    local progressTitle = Theme:CreateText(content, "heading")
    progressTitle:SetPoint("TOPLEFT", 0, -76)
    Theme:SetLocalizedText(progressTitle, "GRAPH_PROGRESS_TITLE")

    self.range = Theme:CreateSegmented(content, RANGES,
        function() return ns.settings.panel.range end,
        function(value)
            ns.settings.panel.range = value
            self:RefreshGraphs()
        end)
    self.range:SetPoint("TOPRIGHT", 0, -72)

    self.progressGraph = ns.Graph:Create(content)
    self.progressGraph:SetPoint("TOPLEFT", 0, -96)
    self.progressGraph:SetPoint("TOPRIGHT", 0, -96)
    self.progressGraph:SetHeight(126)

    self.rateTitle = Theme:CreateText(content, "heading")
    self.rateTitle:SetPoint("TOPLEFT", 0, -232)

    self.rateGraph = ns.Graph:Create(content)
    self.rateGraph:SetPoint("TOPLEFT", 0, -250)
    self.rateGraph:SetPoint("BOTTOMRIGHT", 0, 0)
end

function Overview:RefreshStats()
    local estimate = ns.Tracker:GetEstimate()
    local rate = estimate.rate or estimate.sessionRate
    self.tiles[1].value:SetText(rate and ns.FormatNumber(rate) or L["DURATION_UNKNOWN"])
    if estimate.atMaxLevel or estimate.blocked then
        self.tiles[2].value:SetText(L["LAUNCHER_MAX_LEVEL"])
    else
        self.tiles[2].value:SetText(ns.FormatDuration(estimate.eta))
    end
    self.tiles[3].value:SetText(ns.FormatInteger(estimate.sessionXP))
    self.tiles[4].value:SetText(ns.FormatDuration(estimate.sessionTime))
    self.actions:SetText(self:FormatActions(estimate))
end

--- "About 42 kills · 6 quests · 2 runs to level up", or an empty string.
function Overview:FormatActions(estimate)
    if estimate.atMaxLevel or estimate.blocked then
        return ""
    end
    local parts = {}
    local function Add(count, key)
        if count then
            parts[#parts + 1] = L[key]:format(ns.FormatInteger(count))
        end
    end
    Add(estimate.killsToLevel, "ACTIONS_KILLS")
    Add(estimate.questsToLevel, "ACTIONS_QUESTS")
    Add(estimate.runsToLevel, "ACTIONS_RUNS")
    if #parts == 0 then
        return ""
    end
    return L["ACTIONS_TO_LEVEL"]:format(table.concat(parts, "  ·  "))
end

function Overview:RefreshGraphs()
    local range = ns.settings.panel.range
    local points = BuildProgressPoints(range)
    local span = #points > 1 and (points[#points][1] - points[1][1]) or 0
    local timeFormat = span > 2 * 86400 and "%d/%m" or "%H:%M"

    self.progressGraph:SetData({
        kind = "line",
        series = { { points = points, color = Theme.colors.accent } },
        yFormatter = FormatLevelValue,
        xFormatter = function(value) return date(timeFormat, value) end,
        tooltip = function(tooltip, point)
            tooltip:AddLine(date("%d/%m %H:%M", point[1]), 1, 1, 1)
            tooltip:AddLine(L["GRAPH_POINT_LEVEL"]:format(point[2]), Theme.colors.accent[1],
                Theme.colors.accent[2], Theme.colors.accent[3])
        end,
    })

    local groups, blockMinutes = BuildRateBlocks()
    self.rateTitle:SetText(L["GRAPH_RATE_TITLE"]:format(blockMinutes))
    self.rateGraph:SetData({
        kind = "bars",
        groups = groups,
        yFormatter = ns.FormatNumber,
        tooltip = function(tooltip, group)
            local muted = Theme.colors.muted
            tooltip:AddLine(("%s - %s"):format(date("%H:%M", group.blockStart), date("%H:%M", group.blockEnd)), 1, 1, 1)
            tooltip:AddDoubleLine(L["TOOLTIP_XP"], ns.FormatInteger(group.xp), muted[1], muted[2], muted[3], 1, 1, 1)
            tooltip:AddDoubleLine(L["STAT_RATE"], ns.FormatNumber(group.rate), muted[1], muted[2], muted[3], 1, 1, 1)
        end,
    })
    self.lastGraphRefresh = GetTime()
end

function Overview:Refresh()
    self.range:Refresh()
    self:RefreshStats()
    self:RefreshGraphs()
end

function Overview:OnTick()
    self:RefreshStats()
    if not self.lastGraphRefresh or GetTime() - self.lastGraphRefresh >= GRAPH_REFRESH_SECONDS then
        self:RefreshGraphs()
    end
end

ns.MainPanel:RegisterView(Overview)
