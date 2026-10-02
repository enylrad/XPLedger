--[[----------------------------------------------------------------------------
    XPLedger - Levels view
    Leveling progress of the selected character:
      - a cumulative played time line (one line per character when comparing)
      - a scrollable table with the details of every level
      - summary tiles (total, current level, recent pace, comparison)
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = ns.Theme
local L = ns.L

local Levels = { id = "levels", label = "TAB_LEVELS", followsSelection = true }

local CONTENT_WIDTH = 612
local TILE_GAP = 8
local ROW_HEIGHT = 20
local VISIBLE_ROWS = 6
local RECENT_LEVELS = 5
local BAR_WIDTH = 80

-- Column layout: locale key of the header, x offset, width and justification.
local COLUMNS = {
    { key = "LEVELS_COL_LEVEL", x = 4, width = 60, justify = "LEFT" },
    { key = "LEVELS_COL_PLAYED", x = 64, width = 70, justify = "RIGHT" },
    { key = "LEVELS_COL_REAL", x = 236, width = 80, justify = "RIGHT" },
    { key = "LEVELS_COL_XP", x = 322, width = 84, justify = "RIGHT" },
    { key = "LEVELS_COL_SOURCE", x = 420, width = 110, justify = "LEFT" },
    { key = "LEVELS_COL_DIFF", x = 530, width = 78, justify = "RIGHT" },
}
local DIFF_COLUMN = 6
local BAR_X = 144

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function ClassColor(record)
    local r, g, b = ns.Compat.GetClassColor(record and record.class)
    return { r, g, b }
end

local function SortedLevels(record)
    local levels = {}
    for level in pairs(record and record.levels or {}) do
        levels[#levels + 1] = level
    end
    table.sort(levels)
    return levels
end

--- Played seconds of a level only when the level is finished, or nil.
local function CompletedPlayed(record, level)
    local entry = record.levels and record.levels[level]
    if entry and entry.playedEnd then
        return ns.History:GetLevelPlayed(record, level)
    end
    return nil
end

--- Picks the axis unit so labels stay readable.
local function ChooseUnit(maxSeconds)
    if maxSeconds >= 7200 then
        return 3600, "h"
    end
    return 60, "m"
end

--- Formats a signed duration difference as "+1h 20m" / "-5m".
local function FormatDiff(seconds)
    local sign = seconds < 0 and "-" or "+"
    return sign .. ns.FormatDuration(math.abs(seconds))
end

--- Color of a difference: less time than the reference is better.
local function DiffColor(seconds)
    if seconds < 0 then
        return Theme.colors.better
    elseif seconds > 0 then
        return Theme.colors.worse
    end
    return Theme.colors.muted
end

--- Builds the cumulative played time lines of a record. Every run of
--- consecutive tracked levels becomes its own series (gaps break the line).
--- Points are { x = level reached, y = seconds since the run started,
--- level = level the point closes (nil for the start of a run) }.
local function CollectCumulative(record)
    local runs = {}
    local run, previous
    for _, level in ipairs(SortedLevels(record)) do
        local entry = record.levels[level]
        local played = ns.History:GetLevelPlayed(record, level)
        if not played then
            run = nil
        else
            if not run or level ~= previous + 1 then
                run = { points = { { level, 0 } }, total = 0 }
                runs[#runs + 1] = run
            end
            if entry.playedEnd then
                run.total = run.total + played
                run.points[#run.points + 1] = { level + 1, run.total, level = level }
            elseif record == ns.char then
                -- Level in progress: place the point at the current fraction.
                local xp, maxXP = ns.Tracker:GetSnapshot()
                if xp and maxXP and maxXP > 0 then
                    run.points[#run.points + 1] = { level + xp / maxXP, run.total + played, level = level }
                end
            end
        end
        previous = level
    end
    return runs
end

--- Recent pace: last completed level against the average of the previous ones.
local function RecentPace(record)
    local completed = {}
    for _, level in ipairs(SortedLevels(record)) do
        local played = CompletedPlayed(record, level)
        if played then
            completed[#completed + 1] = { level = level, played = played }
        end
    end
    local last = completed[#completed]
    local sum, count = 0, 0
    for i = #completed - 1, math.max(1, #completed - RECENT_LEVELS), -1 do
        sum, count = sum + completed[i].played, count + 1
    end
    local recentSum, recentCount = 0, 0
    for i = #completed, math.max(1, #completed - RECENT_LEVELS + 1), -1 do
        recentSum, recentCount = recentSum + completed[i].played, recentCount + 1
    end
    return last, count > 0 and sum / count or nil, recentCount > 0 and recentSum / recentCount or nil
end

local function AddCharacterLines(tooltip, record, level)
    local entry = record.levels and record.levels[level]
    if not entry then
        return
    end
    local muted = Theme.colors.muted
    tooltip:AddLine(ns.MainPanel.FormatCharacterName(record))
    tooltip:AddDoubleLine(L["LEVEL_PLAYED"], ns.FormatDuration(ns.History:GetLevelPlayed(record, level)),
        muted[1], muted[2], muted[3], 1, 1, 1)
    if not entry.partial and entry.startedAt and entry.endedAt then
        tooltip:AddDoubleLine(L["LEVEL_REAL"], ns.FormatDuration(entry.endedAt - entry.startedAt),
            muted[1], muted[2], muted[3], 1, 1, 1)
    end
    if (entry.xp or 0) > 0 then
        tooltip:AddDoubleLine(L["LEVEL_XP"], ns.FormatInteger(entry.xp), muted[1], muted[2], muted[3], 1, 1, 1)
    end
    if (entry.kills or 0) > 0 or (entry.quests or 0) > 0 then
        tooltip:AddLine(L["SOURCES_COUNTS"]:format(ns.FormatInteger(entry.kills or 0),
            ns.FormatInteger(entry.quests or 0)), muted[1], muted[2], muted[3])
    end
    if (entry.rested or 0) > 0 then
        tooltip:AddDoubleLine(L["TOOLTIP_RESTED"], ns.FormatInteger(entry.rested), muted[1], muted[2], muted[3], 1, 1, 1)
    end
    if not entry.playedEnd then
        tooltip:AddLine(L["LEVELS_IN_PROGRESS"], Theme.colors.accent[1], Theme.colors.accent[2], Theme.colors.accent[3])
    elseif entry.partial then
        tooltip:AddLine(L["LEVELS_PARTIAL"], muted[1], muted[2], muted[3])
    end
end

--------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------

function Levels:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
    row:EnableMouse(true)

    local highlight = Theme:CreateTexture(row, { 1, 1, 1, 0.05 }, "HIGHLIGHT")
    highlight:SetAllPoints()

    row.cells = {}
    for i, column in ipairs(COLUMNS) do
        local cell = Theme:CreateText(row, i == 1 and "normal" or "muted", column.justify)
        cell:SetPoint("LEFT", column.x, 0)
        cell:SetWidth(column.width)
        cell:SetWordWrap(false)
        row.cells[i] = cell
    end

    local track = Theme:CreateTexture(row, Theme.colors.track, "BACKGROUND")
    track:SetPoint("LEFT", BAR_X, 0)
    track:SetSize(BAR_WIDTH, 4)
    row.bar = Theme:CreateTexture(row, Theme.colors.accent)
    row.bar:SetPoint("LEFT", track, "LEFT")
    row.bar:SetHeight(4)

    row:SetScript("OnEnter", function(selfRow)
        if not selfRow.level then
            return
        end
        GameTooltip:SetOwner(selfRow, "ANCHOR_CURSOR")
        GameTooltip:AddLine(L["TOOLTIP_LEVEL"]:format(selfRow.level), 1, 1, 1)
        AddCharacterLines(GameTooltip, ns.MainPanel:GetViewedRecord(), selfRow.level)
        local compare = self:GetCompareRecord()
        if compare and compare.levels and compare.levels[selfRow.level] then
            GameTooltip:AddLine(" ")
            AddCharacterLines(GameTooltip, compare, selfRow.level)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function Levels:Build(content)
    self.content = content
    self.offset = 0

    local title = Theme:CreateText(content, "heading")
    title:SetPoint("TOPLEFT", 0, -4)
    Theme:SetLocalizedText(title, "LEVELS_TITLE")

    self.legend = Theme:CreateText(content, "muted")
    self.legend:SetPoint("LEFT", title, "RIGHT", 16, 0)

    self.compareDropdown = Theme:CreateDropdown(content, 170, function()
        local options = { { value = false, label = L["LEVELS_COMPARE_NONE"] } }
        local viewedKey = ns.MainPanel:GetViewedKey()
        for _, entry in ipairs(ns.Database:GetCharacterList()) do
            if entry.key ~= viewedKey then
                options[#options + 1] = {
                    value = entry.key,
                    label = ("%s (%d)"):format(entry.record.name or entry.key, entry.record.level or 0),
                    color = ClassColor(entry.record),
                }
            end
        end
        return options
    end, function() return self.compareKey or false end, function(value)
        self.compareKey = value or nil
        self:Refresh()
    end)
    self.compareDropdown:SetPoint("TOPRIGHT", 0, 0)

    local compareLabel = Theme:CreateText(content, "label", "RIGHT")
    compareLabel:SetPoint("RIGHT", self.compareDropdown, "LEFT", -8, 0)
    Theme:SetLocalizedText(compareLabel, "LEVELS_COMPARE")

    -- Cumulative played time.
    self.graph = ns.Graph:Create(content)
    self.graph:SetPoint("TOPLEFT", 0, -24)
    self.graph:SetPoint("TOPRIGHT", 0, -24)
    self.graph:SetHeight(110)

    -- Level table.
    self.headers = {}
    for i, column in ipairs(COLUMNS) do
        local header = Theme:CreateText(content, "label", column.justify)
        header:SetPoint("TOPLEFT", column.x, -142)
        header:SetWidth(column.width)
        Theme:SetLocalizedText(header, column.key)
        self.headers[i] = header
    end
    local separator = Theme:CreateTexture(content, Theme.colors.border)
    separator:SetPoint("TOPLEFT", 0, -158)
    separator:SetPoint("TOPRIGHT", 0, -158)
    separator:SetHeight(1)

    self.list = CreateFrame("Frame", nil, content)
    self.list:SetPoint("TOPLEFT", 0, -160)
    self.list:SetPoint("TOPRIGHT", 0, -160)
    self.list:SetHeight(ROW_HEIGHT * VISIBLE_ROWS)
    self.list:EnableMouseWheel(true)
    self.list:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #(self.rowLevels or {}) - VISIBLE_ROWS)
        self.offset = ns.Clamp(self.offset - delta, 0, maxOffset)
        self:RefreshTable()
    end)
    self.rows = {}
    for i = 1, VISIBLE_ROWS do
        self.rows[i] = self:CreateRow(i)
    end
    self.tableEmpty = Theme:CreateText(self.list, "muted", "CENTER")
    self.tableEmpty:SetPoint("CENTER")

    -- Summary tiles.
    local tileWidth = (CONTENT_WIDTH - TILE_GAP * 3) / 4
    self.tiles = {}
    for index, key in ipairs({ "LEVELS_TOTAL", "LEVELS_CURRENT", "LEVELS_RECENT", "LEVELS_RECENT_AVG" }) do
        local tile = Theme:CreateStat(content, key)
        tile:SetWidth(tileWidth)
        tile:SetPoint("BOTTOMLEFT", (index - 1) * (tileWidth + TILE_GAP), 0)
        self.tiles[index] = tile
    end
    Theme:SetLocalizedText(self.tiles[4].label, function()
        return self.compareKey and L["LEVELS_DIFF_TOTAL"] or L["LEVELS_RECENT_AVG"]
    end)
end

function Levels:GetCompareRecord()
    return self.compareKey and ns.db.characters[self.compareKey]
end

function Levels:RefreshGraph(record, compare, primaryColor, compareColor)
    local primaryRuns = CollectCumulative(record)
    local compareRuns = compare and CollectCumulative(compare) or {}

    local maxSeconds = 0
    for _, runs in ipairs({ primaryRuns, compareRuns }) do
        for _, run in ipairs(runs) do
            maxSeconds = math.max(maxSeconds, run.points[#run.points][2])
        end
    end
    local unitSeconds, unitSuffix = ChooseUnit(maxSeconds)

    local series = {}
    -- The compared lines go first so the selected character is drawn on top.
    for _, runs in ipairs({ compareRuns, primaryRuns }) do
        local isPrimary = runs == primaryRuns
        for _, run in ipairs(runs) do
            local points = {}
            for i, point in ipairs(run.points) do
                points[i] = { point[1], point[2] / unitSeconds, level = point.level, seconds = point[2] }
            end
            series[#series + 1] = {
                points = points,
                color = isPrimary and primaryColor or compareColor,
                thickness = isPrimary and 2 or 1.5,
                hover = isPrimary,
            }
        end
    end

    self.graph:SetData({
        kind = "line",
        series = series,
        yMin = 0,
        emptyText = L["LEVELS_EMPTY"],
        xFormatter = function(value) return L["LEVEL_SHORT"]:format(math.floor(value + 0.5)) end,
        yFormatter = function(value) return ("%g%s"):format(ns.Round(value, 1), unitSuffix) end,
        tooltip = function(tooltip, point)
            local muted = Theme.colors.muted
            if not point.level then
                tooltip:AddLine(L["TOOLTIP_LEVEL"]:format(point[1]), 1, 1, 1)
                tooltip:AddLine(L["LEVELS_RUN_START"], muted[1], muted[2], muted[3])
                return
            end
            tooltip:AddLine(L["TOOLTIP_LEVEL"]:format(point.level), 1, 1, 1)
            tooltip:AddDoubleLine(L["LEVELS_CUMULATIVE"], ns.FormatDuration(point.seconds),
                muted[1], muted[2], muted[3], 1, 1, 1)
            AddCharacterLines(tooltip, record, point.level)
            if compare then
                tooltip:AddLine(" ")
                AddCharacterLines(tooltip, compare, point.level)
            end
        end,
    })
end

function Levels:RefreshTable()
    local record = ns.MainPanel:GetViewedRecord()
    local compare = self:GetCompareRecord()
    local levels = self.rowLevels or {}
    local maxOffset = math.max(0, #levels - VISIBLE_ROWS)
    self.offset = ns.Clamp(self.offset or 0, 0, maxOffset)

    local maxPlayed = 0
    for _, level in ipairs(levels) do
        maxPlayed = math.max(maxPlayed, ns.History:GetLevelPlayed(record, level) or 0)
    end

    self.headers[DIFF_COLUMN]:SetShown(compare and true or false)
    self.tableEmpty:SetText(#levels == 0 and L["LEVELS_EMPTY"] or "")

    local accent, muted, text = Theme.colors.accent, Theme.colors.muted, Theme.colors.text
    for i, row in ipairs(self.rows) do
        local level = levels[i + self.offset]
        row.level = level
        if level then
            local entry = record.levels[level]
            local played = ns.History:GetLevelPlayed(record, level)
            local cells = row.cells

            -- In progress: accent color. Partially tracked: muted with "*".
            local levelText = L["LEVEL_SHORT"]:format(level)
            local levelColor = text
            if not entry.playedEnd then
                levelColor = accent
            elseif entry.partial then
                levelText = levelText .. "*"
                levelColor = muted
            end
            cells[1]:SetText(levelText)
            cells[1]:SetTextColor(levelColor[1], levelColor[2], levelColor[3])

            cells[2]:SetText(ns.FormatDuration(played))
            local realTime = not entry.partial and entry.startedAt and entry.endedAt
                and entry.endedAt - entry.startedAt or nil
            cells[3]:SetText(ns.FormatDuration(realTime))
            cells[4]:SetText((entry.xp or 0) > 0 and ns.FormatInteger(entry.xp) or L["DURATION_UNKNOWN"])

            local source, share = ns.History:GetTopSource(entry)
            if source then
                cells[5]:SetText(("%s %s %d%%"):format(Theme.Swatch(Theme.sourceColors[source] or muted, 8),
                    L["SOURCE_" .. source], math.floor(share * 100 + 0.5)))
            else
                cells[5]:SetText(L["DURATION_UNKNOWN"])
            end

            local diffText = ""
            if compare then
                local mine, theirs = CompletedPlayed(record, level), CompletedPlayed(compare, level)
                if mine and theirs then
                    local diff = mine - theirs
                    diffText = Theme.Hex(DiffColor(diff)) .. FormatDiff(diff) .. "|r"
                else
                    diffText = L["DURATION_UNKNOWN"]
                end
            end
            cells[DIFF_COLUMN]:SetText(diffText)

            local fill = maxPlayed > 0 and (played or 0) / maxPlayed or 0
            row.bar:SetWidth(math.max(1, BAR_WIDTH * fill))
            row.bar:SetShown(fill > 0)
            row:Show()
        else
            row:Hide()
        end
    end
end

function Levels:RefreshTiles(record, compare)
    local stats = ns.History:GetCharacterStats(record)
    local tiles = self.tiles

    tiles[1].value:SetText(stats.completed > 0 and ns.FormatDuration(stats.totalPlayed) or L["DURATION_UNKNOWN"])

    local current = record.level and ns.History:GetLevelPlayed(record, record.level)
    tiles[2].value:SetText(current
        and ("%s  ·  %s"):format(L["LEVEL_SHORT"]:format(record.level), ns.FormatDuration(current))
        or L["DURATION_UNKNOWN"])

    local last, previousAverage, recentAverage = RecentPace(record)
    if last then
        local text = ("%s · %s"):format(L["LEVEL_SHORT"]:format(last.level), ns.FormatDuration(last.played))
        if previousAverage and previousAverage > 0 then
            local change = (last.played / previousAverage - 1) * 100
            text = ("%s %s(%+d%%)|r"):format(text, Theme.Hex(DiffColor(change)), math.floor(change + 0.5))
        end
        tiles[3].value:SetText(text)
    else
        tiles[3].value:SetText(L["DURATION_UNKNOWN"])
    end

    tiles[4].label:SetText(compare and L["LEVELS_DIFF_TOTAL"] or L["LEVELS_RECENT_AVG"])
    if compare then
        local diff, common = 0, 0
        for _, level in ipairs(SortedLevels(record)) do
            local mine, theirs = CompletedPlayed(record, level), CompletedPlayed(compare, level)
            if mine and theirs then
                diff, common = diff + mine - theirs, common + 1
            end
        end
        if common > 0 then
            local key = diff <= 0 and "LEVELS_AHEAD" or "LEVELS_BEHIND"
            tiles[4].value:SetText(Theme.Hex(DiffColor(diff)) .. L[key]:format(ns.FormatDuration(math.abs(diff))) .. "|r")
        else
            tiles[4].value:SetText(L["DURATION_UNKNOWN"])
        end
    else
        tiles[4].value:SetText(ns.FormatDuration(recentAverage))
    end
end

function Levels:Refresh()
    local record = ns.MainPanel:GetViewedRecord()
    if self.compareKey and (self.compareKey == ns.MainPanel:GetViewedKey() or not ns.db.characters[self.compareKey]) then
        self.compareKey = nil
    end
    local compare = self:GetCompareRecord()
    self.compareDropdown:Refresh()

    local primaryColor = ClassColor(record)
    local compareColor = ClassColor(compare)
    if compare and compare.class == record.class then
        compareColor = { 0.62, 0.64, 0.70 }
    end

    if compare then
        self.legend:SetText(("%s %s     %s %s"):format(Theme.Swatch(primaryColor), record.name or "?",
            Theme.Swatch(compareColor), compare.name or "?"))
    else
        self.legend:SetText("")
    end

    -- Table rows: newest level first.
    local levels = SortedLevels(record)
    local rowLevels = {}
    for i = #levels, 1, -1 do
        rowLevels[#rowLevels + 1] = levels[i]
    end
    if self.viewedRecord ~= record then
        self.offset = 0
        self.viewedRecord = record
    end
    self.rowLevels = rowLevels

    self:RefreshGraph(record, compare, primaryColor, compareColor)
    self:RefreshTable()
    self:RefreshTiles(record, compare)
end

function Levels:OnTick()
    -- The in-progress level grows with played time; redraw now and then.
    self.ticks = (self.ticks or 0) + 1
    if self.ticks % 30 == 0 then
        self:Refresh()
    end
end

ns.MainPanel:RegisterView(Levels)
