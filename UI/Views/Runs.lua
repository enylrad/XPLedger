--[[----------------------------------------------------------------------------
    XPLedger - Runs view
    Two modes, picked with a selector at the top:
      runs      dungeon, delve and scenario runs of the selected character:
                summary tiles and a table of the latest runs
      records   level goal of the selected character, account-wide records
                and the fastest time of every level
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = ns.Theme
local L = ns.L

local Runs = { id = "runs", label = "TAB_RUNS", followsSelection = true }

local CONTENT_WIDTH = 612
local TILE_GAP = 8
local ROW_HEIGHT = 20
local VISIBLE_ROWS = 9
local TILES_TOP = -28
local TABLE_TOP = -110
local RECORD_ROWS = 9
local COLUMN_WIDTH = 296

local MODES = {
    { value = "runs", label = "RUNS_MODE_RUNS" },
    { value = "records", label = "RUNS_MODE_RECORDS" },
}

-- Column layout: locale key of the header, x offset, width and justification.
local COLUMNS = {
    { key = "RUNS_COL_NAME", x = 4, width = 204, justify = "LEFT" },
    { key = "RUNS_COL_LEVEL", x = 212, width = 40, justify = "CENTER" },
    { key = "RUNS_COL_DURATION", x = 256, width = 76, justify = "RIGHT" },
    { key = "RUNS_COL_XP", x = 336, width = 86, justify = "RIGHT" },
    { key = "RUNS_COL_RATE", x = 426, width = 80, justify = "RIGHT" },
    { key = "RUNS_COL_DATE", x = 510, width = 98, justify = "RIGHT" },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Runs of a record, newest first, with the active run on top.
local function CollectRuns(record)
    local list = {}
    if record.activeRun then
        list[1] = record.activeRun
    end
    local runs = record.runs or {}
    for i = #runs, 1, -1 do
        list[#list + 1] = runs[i]
    end
    return list
end

local function FormatRate(rate)
    return rate and ns.FormatNumber(rate) or L["DURATION_UNKNOWN"]
end

local function ShowRunTooltip(row)
    local run = row.run
    if not run then
        return
    end
    local muted = Theme.colors.muted
    local function Row(label, value)
        GameTooltip:AddDoubleLine(label, value, muted[1], muted[2], muted[3], 1, 1, 1)
    end
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    GameTooltip:AddLine(run.name or "?", 1, 1, 1)
    if run.difficulty then
        GameTooltip:AddLine(run.difficulty, muted[1], muted[2], muted[3])
    end
    Row(L["RUNS_KIND"], L["RUNS_KIND_" .. (run.kind or "dungeon")])
    Row(L["RUNS_STARTED"], date("%d/%m %H:%M", run.startedAt))
    Row(L["RUNS_COL_DURATION"], ns.FormatDuration(ns.Runs:GetDuration(run)))
    Row(L["RUNS_COL_XP"], ns.FormatInteger(run.xp))
    Row(L["RUNS_KILLS"], ns.FormatInteger(run.kills))
    Row(L["RUNS_QUESTS"], ns.FormatInteger(run.quests))
    if not run.endedAt then
        GameTooltip:AddLine(run.leftAt and L["RUNS_OUTSIDE"] or L["RUNS_IN_PROGRESS"],
            Theme.colors.accent[1], Theme.colors.accent[2], Theme.colors.accent[3], true)
    end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------

function Runs:CreateRow(index)
    local row = CreateFrame("Button", nil, self.list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
    local highlight = Theme:CreateTexture(row, { 1, 1, 1, 0.05 }, "HIGHLIGHT")
    highlight:SetAllPoints()

    row.cells = {}
    for i, column in ipairs(COLUMNS) do
        local cell = Theme:CreateText(row, i == 1 and "normal" or "muted", column.justify)
        cell:SetPoint("LEFT", column.x, 0)
        cell:SetWidth(column.width)
        row.cells[i] = cell
    end
    row:SetScript("OnEnter", ShowRunTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function Runs:Build(content)
    self.content = content
    self.offset = 0

    self.title = Theme:CreateText(content, "heading")
    self.title:SetPoint("TOPLEFT", 0, -4)

    self.mode = Theme:CreateSegmented(content, MODES,
        function() return ns.settings.panel.runsMode end,
        function(value)
            ns.settings.panel.runsMode = value
            self:Refresh()
        end)
    self.mode:SetPoint("TOPRIGHT", 0, 0)

    self.runsFrame = CreateFrame("Frame", nil, content)
    self.runsFrame:SetAllPoints()
    self:BuildRuns(self.runsFrame)

    self.recordsFrame = CreateFrame("Frame", nil, content)
    self.recordsFrame:SetAllPoints()
    self:BuildRecords(self.recordsFrame)
end

function Runs:BuildRuns(content)
    local tileWidth = (CONTENT_WIDTH - TILE_GAP * 3) / 4
    self.tiles = {}
    for index, key in ipairs({ "RUNS_COUNT", "RUNS_AVG_RATE", "RUNS_AVG_XP", "RUNS_BEST" }) do
        local tile = Theme:CreateStat(content, key)
        tile:SetWidth(tileWidth)
        tile:SetPoint("TOPLEFT", (index - 1) * (tileWidth + TILE_GAP), TILES_TOP)
        self.tiles[index] = tile
    end

    self.headers = {}
    for i, column in ipairs(COLUMNS) do
        local header = Theme:CreateText(content, "label", column.justify)
        header:SetPoint("TOPLEFT", column.x, TABLE_TOP + 22)
        header:SetWidth(column.width)
        Theme:SetLocalizedText(header, column.key)
        self.headers[i] = header
    end
    local separator = Theme:CreateTexture(content, Theme.colors.border)
    separator:SetPoint("TOPLEFT", 0, TABLE_TOP + 4)
    separator:SetPoint("TOPRIGHT", 0, TABLE_TOP + 4)
    separator:SetHeight(1)

    self.list = CreateFrame("Frame", nil, content)
    self.list:SetPoint("TOPLEFT", 0, TABLE_TOP)
    self.list:SetPoint("TOPRIGHT", 0, TABLE_TOP)
    self.list:SetHeight(ROW_HEIGHT * VISIBLE_ROWS)
    self.list:EnableMouseWheel(true)
    self.list:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #(self.entries or {}) - VISIBLE_ROWS)
        self.offset = ns.Clamp(self.offset - delta, 0, maxOffset)
        self:RefreshTable()
    end)
    self.rows = {}
    for i = 1, VISIBLE_ROWS do
        self.rows[i] = self:CreateRow(i)
    end
    self.empty = Theme:CreateText(self.list, "muted", "CENTER")
    self.empty:SetPoint("CENTER")
    Theme:SetLocalizedText(self.empty, "RUNS_EMPTY")

    self.footer = Theme:CreateText(content, "muted")
    self.footer:SetPoint("BOTTOMLEFT", 0, 6)
    Theme:SetLocalizedText(self.footer, "RUNS_HINT")

    local exportButton = Theme:CreateButton(content, "EXPORT_RUNS", 100, 22, function()
        ns.Export:Show("runs", ns.MainPanel:GetViewedKey())
    end)
    exportButton:SetPoint("BOTTOMRIGHT", 0, 0)
end

function Runs:RefreshTiles(record)
    local stats = ns.Runs:GetStats(record)
    local tiles = self.tiles
    tiles[1].value:SetText(ns.FormatInteger(stats.count))
    tiles[2].value:SetText(FormatRate(stats.rate))
    tiles[3].value:SetText(stats.averageXP and ns.FormatNumber(stats.averageXP) or L["DURATION_UNKNOWN"])
    tiles[3].tooltip = stats.averageDuration and function(tooltip)
        local muted = Theme.colors.muted
        tooltip:AddDoubleLine(L["RUNS_AVG_DURATION"], ns.FormatDuration(stats.averageDuration),
            muted[1], muted[2], muted[3], 1, 1, 1)
    end or nil

    local best = stats.best
    if best then
        tiles[4].value:SetText(("%s · %s"):format(FormatRate(stats.bestRate), best.name or "?"))
        tiles[4].tooltip = function(tooltip)
            local muted = Theme.colors.muted
            tooltip:AddLine(best.name or "?", 1, 1, 1)
            tooltip:AddDoubleLine(L["RUNS_COL_RATE"], FormatRate(stats.bestRate), muted[1], muted[2], muted[3], 1, 1, 1)
            tooltip:AddDoubleLine(L["RUNS_COL_DURATION"], ns.FormatDuration(ns.Runs:GetDuration(best)),
                muted[1], muted[2], muted[3], 1, 1, 1)
            tooltip:AddDoubleLine(L["RUNS_COL_LEVEL"], best.level or "?", muted[1], muted[2], muted[3], 1, 1, 1)
        end
    else
        tiles[4].value:SetText(L["DURATION_UNKNOWN"])
        tiles[4].tooltip = nil
    end
end

function Runs:RefreshTable()
    local entries = self.entries
    local maxOffset = math.max(0, #entries - VISIBLE_ROWS)
    self.offset = ns.Clamp(self.offset or 0, 0, maxOffset)
    local accent = Theme.Hex(Theme.colors.accent)

    for i, row in ipairs(self.rows) do
        local run = entries[i + self.offset]
        row.run = run
        if run then
            local name = run.name or "?"
            if not run.endedAt then
                name = accent .. "> |r" .. name
            end
            row.cells[1]:SetText(name)
            row.cells[2]:SetText(run.level or "?")
            row.cells[3]:SetText(ns.FormatDuration(ns.Runs:GetDuration(run)))
            row.cells[4]:SetText(ns.FormatInteger(run.xp))
            row.cells[5]:SetText(FormatRate(ns.Runs:GetRate(run)))
            row.cells[6]:SetText(date("%d/%m %H:%M", run.startedAt))
            row:Show()
        else
            row:Hide()
        end
    end
    self.empty:SetShown(#entries == 0)
end

function Runs:Refresh()
    local record = ns.MainPanel:GetViewedRecord()
    if not record then
        return
    end
    local mode = ns.settings.panel.runsMode == "records" and "records" or "runs"
    self.mode:Refresh()
    self.runsFrame:SetShown(mode == "runs")
    self.recordsFrame:SetShown(mode == "records")
    self.title:SetText(L[mode == "runs" and "RUNS_TITLE" or "RECORDS_TITLE"])
    if mode == "runs" then
        self.entries = CollectRuns(record)
        self:RefreshTiles(record)
        self:RefreshTable()
    else
        self:RefreshRecords(record)
    end
end

function Runs:OnTick()
    -- Keeps the duration and rate of the active run live.
    local record = ns.MainPanel:GetViewedRecord()
    if record and record.activeRun and self.runsFrame:IsShown() then
        self:RefreshTable()
    end
end

--------------------------------------------------------------------------------
-- Records mode
--------------------------------------------------------------------------------

-- Formats the value of each account record.
local RECORD_FORMATS = {
    sessionRate = function(entry) return ns.FormatNumber(entry.value) .. " /h" end,
    bestHour = function(entry) return ns.FormatInteger(entry.value) .. " XP" end,
    biggestGain = function(entry) return ns.FormatInteger(entry.value) .. " XP" end,
    bestRun = function(entry) return ns.FormatNumber(entry.value) .. " /h" end,
}

--- Colored name of the character holding a record.
local function HolderName(key)
    local record = key and ns.db.characters[key]
    if record then
        return ns.MainPanel.FormatCharacterName(record)
    end
    return key and key:match("^[^-]+") or "?"
end

--- Row of a records list. `widths` holds { width, justify } per cell.
local function CreateRecordRow(parent, x, top, widths)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", x, top)
    row:SetWidth(COLUMN_WIDTH)
    local highlight = Theme:CreateTexture(row, { 1, 1, 1, 0.05 }, "HIGHLIGHT")
    highlight:SetAllPoints()
    row.cells = {}
    local cellX = 4
    for i, spec in ipairs(widths) do
        local cell = Theme:CreateText(row, i == 1 and "normal" or "muted", spec[2])
        cell:SetPoint("LEFT", cellX, 0)
        cell:SetWidth(spec[1])
        row.cells[i] = cell
        cellX = cellX + spec[1] + 4
    end
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function ShowAccountRecordTooltip(row)
    local entry = ns.Records:Get()[row.kind]
    if not entry then
        return
    end
    local muted = Theme.colors.muted
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    GameTooltip:AddLine(L["RECORD_KIND_" .. row.kind], 1, 1, 1)
    GameTooltip:AddLine(L["RECORD_KIND_" .. row.kind .. "_DESC"], muted[1], muted[2], muted[3], true)
    if entry.name then
        GameTooltip:AddDoubleLine(L["RUNS_COL_NAME"], entry.name, muted[1], muted[2], muted[3], 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(L["RECORDS_HOLDER"], HolderName(entry.key), muted[1], muted[2], muted[3], 1, 1, 1)
    GameTooltip:AddDoubleLine(L["RUNS_COL_DATE"], date("%d/%m/%Y", entry.at), muted[1], muted[2], muted[3], 1, 1, 1)
    GameTooltip:Show()
end

--- Adds a section title with an underline at the given position.
local function SectionTitle(parent, key, x, y)
    local title = Theme:CreateText(parent, "heading")
    title:SetPoint("TOPLEFT", x, y)
    Theme:SetLocalizedText(title, key)
    local line = Theme:CreateTexture(parent, Theme.colors.border)
    line:SetPoint("TOPLEFT", x, y - 18)
    line:SetSize(COLUMN_WIDTH, 1)
end

function Runs:BuildRecords(content)
    -- Level goal of the selected character and session goal.
    local goalTitle = Theme:CreateText(content, "label")
    goalTitle:SetPoint("TOPLEFT", 0, -32)
    Theme:SetLocalizedText(goalTitle, "RECORDS_GOAL")
    self.goalText = Theme:CreateText(content, "normal")
    self.goalText:SetPoint("TOPLEFT", 0, -50)
    self.goalText:SetPoint("RIGHT", 0, 0)
    self.sessionGoalText = Theme:CreateText(content, "muted")
    self.sessionGoalText:SetPoint("TOPLEFT", 0, -68)
    self.sessionGoalText:SetPoint("RIGHT", 0, 0)

    -- Account records (left column).
    local top = -98
    SectionTitle(content, "RECORDS_ACCOUNT", 0, top)
    self.accountRows = {}
    for i, kind in ipairs(ns.Records.KINDS) do
        local row = CreateRecordRow(content, 0, top - 22 - (i - 1) * ROW_HEIGHT,
            { { 124, "LEFT" }, { 76, "RIGHT" }, { 80, "RIGHT" } })
        row.kind = kind
        Theme:SetLocalizedText(row.cells[1], "RECORD_KIND_" .. kind)
        row:SetScript("OnEnter", ShowAccountRecordTooltip)
        self.accountRows[i] = row
    end

    -- Fastest time of every level (right column, scrollable).
    local x = COLUMN_WIDTH + 20
    SectionTitle(content, "RECORDS_LEVELS", x, top)
    self.levelList = CreateFrame("Frame", nil, content)
    self.levelList:SetPoint("TOPLEFT", x, top - 22)
    self.levelList:SetSize(COLUMN_WIDTH, ROW_HEIGHT * RECORD_ROWS)
    self.levelList:EnableMouseWheel(true)
    self.levelOffset = 0
    self.levelList:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #(self.levelEntries or {}) - RECORD_ROWS)
        self.levelOffset = ns.Clamp(self.levelOffset - delta, 0, maxOffset)
        self:RefreshLevelRecords()
    end)
    self.levelRows = {}
    for i = 1, RECORD_ROWS do
        self.levelRows[i] = CreateRecordRow(self.levelList, 0, -(i - 1) * ROW_HEIGHT,
            { { 60, "LEFT" }, { 80, "RIGHT" }, { 140, "RIGHT" } })
    end
    self.levelEmpty = Theme:CreateText(self.levelList, "muted", "CENTER")
    self.levelEmpty:SetPoint("CENTER")
    Theme:SetLocalizedText(self.levelEmpty, "RECORDS_EMPTY")

    local hint = Theme:CreateText(content, "muted")
    hint:SetPoint("BOTTOMLEFT", 0, 6)
    Theme:SetLocalizedText(hint, "RECORDS_HINT")
end

function Runs:RefreshLevelRecords()
    local entries = self.levelEntries
    self.levelOffset = ns.Clamp(self.levelOffset, 0, math.max(0, #entries - RECORD_ROWS))
    for i, row in ipairs(self.levelRows) do
        local entry = entries[i + self.levelOffset]
        if entry then
            row.cells[1]:SetText(L["LEVEL_SHORT"]:format(entry.level))
            row.cells[2]:SetText(ns.FormatDuration(entry.value))
            row.cells[3]:SetText(HolderName(entry.key))
            row:Show()
        else
            row:Hide()
        end
    end
    self.levelEmpty:SetShown(#entries == 0)
end

function Runs:RefreshRecords(record)
    self.goalText:SetText(ns.Goals:FormatGoal(record) or L["GOAL_NONE"])
    local sessionGoal = ns.settings.goals.sessionXP
    if record == ns.char and sessionGoal > 0 then
        self.sessionGoalText:SetText(L["GOAL_SESSION_STATUS"]:format(
            ns.FormatInteger(ns.Tracker:GetSession().xp), ns.FormatInteger(sessionGoal)))
    else
        self.sessionGoalText:SetText(L["GOAL_SESSION_HINT"])
    end

    local records = ns.Records:Get()
    for _, row in ipairs(self.accountRows) do
        local entry = records[row.kind]
        row.cells[2]:SetText(entry and RECORD_FORMATS[row.kind](entry) or L["DURATION_UNKNOWN"])
        row.cells[3]:SetText(entry and HolderName(entry.key) or "")
    end

    self.levelEntries = ns.Records:GetLevelRecords()
    self:RefreshLevelRecords()
end

ns.MainPanel:RegisterView(Runs)
