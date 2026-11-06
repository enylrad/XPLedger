--[[----------------------------------------------------------------------------
    XPLedger - Stats view
    Dozens of leveling statistics of the selected character or of the whole
    account (scope selector on the left), split in pages:
      summary   tiles built from the history (levels, sessions, runs...)
      when      experience per weekday and per hour, days played, streaks
      where     experience per zone
      prey      most killed creatures and best rewarded quests
      friends   deaths ranking of the account and the Battle.net friends who
                share (see Ranking); it has no scope
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = ns.Theme
local L = ns.L

local Stats = { id = "stats", label = "TAB_STATS", followsSelection = true }

local CONTENT_WIDTH = 612
local TILE_GAP = 8
local TILE_HEIGHT = 48
local TILE_COLUMNS = 4
local PAGE_TOP = -30
local SUMMARY_ROWS = 5
local ROW_HEIGHT = 20
local LIVE_REFRESH_SECONDS = 30   -- the running session keeps growing without gains

local SCOPES = {
    { value = "character", label = "STATS_SCOPE_CHARACTER" },
    { value = "account", label = "STATS_SCOPE_ACCOUNT" },
}

local PAGES = {
    { value = "summary", label = "STATS_PAGE_SUMMARY" },
    { value = "when", label = "STATS_PAGE_WHEN" },
    { value = "where", label = "STATS_PAGE_WHERE" },
    { value = "prey", label = "STATS_PAGE_PREY" },
    { value = "friends", label = "STATS_PAGE_FRIENDS" },
}

local TILE_WIDTH = (CONTENT_WIDTH - TILE_GAP * (TILE_COLUMNS - 1)) / TILE_COLUMNS

--------------------------------------------------------------------------------
-- Formatting helpers
--------------------------------------------------------------------------------

local UNKNOWN = function() return L["DURATION_UNKNOWN"] end

local function Percent(share)
    return share and ("%d%%"):format(math.floor(share * 100 + 0.5)) or UNKNOWN()
end

local function Count(value)
    return value and ns.FormatInteger(value) or UNKNOWN()
end

local function Rate(value)
    return value and ns.FormatNumber(value) or UNKNOWN()
end

local function WeekdayName(weekday)
    return L["STATS_WEEKDAY_" .. weekday]
end

local function HourRange(hour)
    return ("%02d:00 - %02d:00"):format(hour, (hour + 1) % 24)
end

--- Name of the character holding a value (account scope only).
local function Holder(entry)
    local record = entry and entry.key and ns.db.characters[entry.key]
    return record and ns.MainPanel.FormatCharacterName(record) or nil
end

local function AddRow(tooltip, label, value)
    local muted = Theme.colors.muted
    tooltip:AddDoubleLine(label, value, muted[1], muted[2], muted[3], 1, 1, 1)
end

--- Tooltip that names the holder of an account-wide best.
local function HolderTooltip(entry, extra)
    if not extra and Stats.scope ~= "account" then
        return nil
    end
    return function(tooltip)
        if extra then
            extra(tooltip)
        end
        local holder = Stats.scope == "account" and Holder(entry)
        if holder then
            AddRow(tooltip, L["STATS_HOLDER"], holder)
        end
    end
end

--------------------------------------------------------------------------------
-- Summary catalog: { label, function(data) return value, tooltip end }
--------------------------------------------------------------------------------

local SUMMARY = {
    { "STATS_XP_TOTAL", function(d) return ns.FormatInteger(d.xp) end },
    { "STATS_PLAYED", function(d) return ns.FormatDuration(d.totalPlayed > 0 and d.totalPlayed or nil) end },
    { "STATS_LEVELS_DONE", function(d) return ns.FormatInteger(d.completed) end },
    { "STATS_LEVEL_AVERAGE", function(d) return ns.FormatDuration(d.averageLevel) end },
    { "STATS_LEVEL_FASTEST", function(d)
        local e = d.fastest
        if not e then return UNKNOWN() end
        return ("%s · %s"):format(L["LEVEL_SHORT"]:format(e.level), ns.FormatDuration(e.value)), HolderTooltip(e)
    end },
    { "STATS_LEVEL_SLOWEST", function(d)
        local e = d.slowest
        if not e then return UNKNOWN() end
        return ("%s · %s"):format(L["LEVEL_SHORT"]:format(e.level), ns.FormatDuration(e.value)), HolderTooltip(e)
    end },
    { "STATS_RATE_AVERAGE", function(d) return Rate(d.averageRate) end },
    { "STATS_SESSION_BEST", function(d)
        local e = d.bestSession
        if not e then return UNKNOWN() end
        return Rate(e.value), HolderTooltip(e, function(tooltip)
            AddRow(tooltip, L["STATS_DATE"], date("%d/%m/%Y", e.at))
        end)
    end },
    { "STATS_SESSION_LONGEST", function(d)
        local e = d.longestSession
        if not e then return UNKNOWN() end
        return ns.FormatDuration(e.value), HolderTooltip(e, function(tooltip)
            AddRow(tooltip, L["STATS_DATE"], date("%d/%m/%Y", e.at))
        end)
    end },
    { "STATS_SESSIONS", function(d) return ns.FormatInteger(d.sessions) end },
    { "STATS_SESSION_AVERAGE", function(d) return ns.FormatDuration(d.averageSession) end },
    { "STATS_BIGGEST_GAIN", function(d)
        local e = d.biggestGain
        if not e then return UNKNOWN() end
        return ns.FormatInteger(e.value), HolderTooltip(e, function(tooltip)
            AddRow(tooltip, L["STATS_SOURCE"], L["SOURCE_" .. (e.source or "other")])
            AddRow(tooltip, L["STATS_LEVEL"], e.level or "?")
            AddRow(tooltip, L["STATS_DATE"], date("%d/%m/%Y %H:%M", e.at))
        end)
    end },
    { "STATS_RESTED_SHARE", function(d) return Percent(d.restedShare) end },
    { "STATS_DEATHS", function(d) return ns.FormatInteger(d.deaths) end },
    { "STATS_DEADLIEST", function(d)
        local e = d.deadliest
        if not e then return UNKNOWN() end
        return L["STATS_DEADLIEST_VALUE"]:format(e.level, e.value), HolderTooltip(e)
    end },
    { "STATS_KILLS", function(d) return ns.FormatInteger(d.kills) end },
    { "STATS_QUESTS", function(d) return ns.FormatInteger(d.quests) end },
    { "STATS_KILL_AVERAGE", function(d) return Rate(d.averageKill) end },
    { "STATS_QUEST_AVERAGE", function(d) return Rate(d.averageQuest) end },
    { "STATS_RUNS", function(d) return ns.FormatInteger(d.runs) end },
    { "STATS_RUN_FAVORITE", function(d)
        local e = d.favoriteRun
        if not e then return UNKNOWN() end
        return e.name, function(tooltip) AddRow(tooltip, L["STATS_TIMES"], ns.FormatInteger(e.count)) end
    end },
    { "STATS_RUN_BEST", function(d)
        local e = d.bestRun
        if not e then return UNKNOWN() end
        return ("%s · %s"):format(Rate(e.value), e.name or "?"), HolderTooltip(e)
    end },
    { "STATS_INSTANCE_SHARE", function(d) return Percent(d.instanceShare) end },
    { "STATS_TOP_SOURCE", function(d)
        local e = d.topSource
        if not e then return UNKNOWN() end
        return ("%s · %s"):format(L["SOURCE_" .. e.source], Percent(e.share))
    end },
}

--------------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------------

local function CreateTile(parent, label)
    local tile = Theme:CreateStat(parent, label)
    tile:SetWidth(TILE_WIDTH)
    return tile
end

local function SetTile(tile, value, tooltip)
    tile.value:SetText(value or UNKNOWN())
    tile.tooltip = tooltip
end

--- Small scrollable table. `columns` = { { key, width, justify }, ... }.
local function CreateTable(parent, columns, x, y, width, rows)
    local tableFrame = CreateFrame("Frame", nil, parent)
    tableFrame:SetPoint("TOPLEFT", x, y)
    tableFrame:SetSize(width, 22 + rows * ROW_HEIGHT)
    tableFrame.offset = 0
    tableFrame.entries = {}

    local offsetX = 4
    for _, column in ipairs(columns) do
        column.x = offsetX
        offsetX = offsetX + column.width + 4
        local header = Theme:CreateText(tableFrame, "label", column.justify)
        header:SetPoint("TOPLEFT", column.x, 0)
        header:SetWidth(column.width)
        Theme:SetLocalizedText(header, column.key)
    end
    local separator = Theme:CreateTexture(tableFrame, Theme.colors.border)
    separator:SetPoint("TOPLEFT", 0, -18)
    separator:SetPoint("TOPRIGHT", 0, -18)
    separator:SetHeight(1)

    tableFrame.rows = {}
    for i = 1, rows do
        local row = CreateFrame("Frame", nil, tableFrame)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -22 - (i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", 0, -22 - (i - 1) * ROW_HEIGHT)
        row:EnableMouse(true)
        local highlight = Theme:CreateTexture(row, { 1, 1, 1, 0.05 }, "HIGHLIGHT")
        highlight:SetAllPoints()
        row.cells = {}
        for c, column in ipairs(columns) do
            local cell = Theme:CreateText(row, c == 1 and "normal" or "muted", column.justify)
            cell:SetPoint("LEFT", column.x, 0)
            cell:SetWidth(column.width)
            row.cells[c] = cell
        end
        row:SetScript("OnEnter", function(self)
            if self.entry and tableFrame.tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                tableFrame.tooltip(GameTooltip, self.entry)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tableFrame.rows[i] = row
    end

    tableFrame.empty = Theme:CreateText(tableFrame, "muted", "CENTER")
    tableFrame.empty:SetPoint("TOPLEFT", 0, -22)
    tableFrame.empty:SetPoint("TOPRIGHT", 0, -22)
    tableFrame.empty:SetHeight(rows * ROW_HEIGHT)

    function tableFrame:Redraw()
        for i, row in ipairs(self.rows) do
            local entry = self.entries[i + self.offset]
            row.entry = entry
            if entry then
                local values = self.format(entry, i + self.offset)
                for c, cell in ipairs(row.cells) do
                    cell:SetText(values[c] or "")
                end
                row:Show()
            else
                row:Hide()
            end
        end
        self.empty:SetShown(#self.entries == 0)
    end

    --- `format(entry, rank)` returns the cell texts of a row.
    function tableFrame:SetEntries(entries, format, emptyKey)
        self.entries, self.format = entries, format
        self.offset = ns.Clamp(self.offset, 0, math.max(0, #entries - #self.rows))
        self.empty:SetText(L[emptyKey])
        self:Redraw()
    end

    tableFrame:EnableMouseWheel(true)
    tableFrame:SetScript("OnMouseWheel", function(self, delta)
        self.offset = ns.Clamp(self.offset - delta, 0, math.max(0, #self.entries - #self.rows))
        self:Redraw()
    end)
    return tableFrame
end

--------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------

function Stats:Build(content)
    self.content = content
    self.summaryOffset = 0

    self.scopeSelector = Theme:CreateSegmented(content, SCOPES,
        function() return ns.settings.panel.statsScope end,
        function(value)
            ns.settings.panel.statsScope = value
            self:Refresh()
        end)
    self.scopeSelector:SetPoint("TOPLEFT", 0, 0)

    self.pageSelector = Theme:CreateSegmented(content, PAGES,
        function() return ns.settings.panel.statsPage end,
        function(value)
            ns.settings.panel.statsPage = value
            self:Refresh()
        end)
    self.pageSelector:SetPoint("TOPRIGHT", 0, 0)

    self.pages = {}
    for _, page in ipairs(PAGES) do
        local frame = CreateFrame("Frame", nil, content)
        frame:SetPoint("TOPLEFT", 0, PAGE_TOP)
        frame:SetPoint("BOTTOMRIGHT", 0, 0)
        self.pages[page.value] = frame
    end
    self:BuildSummary(self.pages.summary)
    self:BuildWhen(self.pages.when)
    self:BuildWhere(self.pages.where)
    self:BuildPrey(self.pages.prey)
    self:BuildFriends(self.pages.friends)
end

function Stats:BuildSummary(page)
    self.summaryTiles = {}
    for index, entry in ipairs(SUMMARY) do
        self.summaryTiles[index] = CreateTile(page, entry[1])
    end
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, math.ceil(#SUMMARY / TILE_COLUMNS) - SUMMARY_ROWS)
        self.summaryOffset = ns.Clamp(self.summaryOffset - delta, 0, maxOffset)
        self:LayoutSummary()
    end)
    self.summaryHint = Theme:CreateText(page, "muted")
    self.summaryHint:SetPoint("BOTTOMLEFT", 0, 6)
    Theme:SetLocalizedText(self.summaryHint, "STATS_SUMMARY_HINT")
end

--- Places the visible rows of summary tiles (the wheel scrolls by rows).
function Stats:LayoutSummary()
    for index, tile in ipairs(self.summaryTiles) do
        local row = math.floor((index - 1) / TILE_COLUMNS) - self.summaryOffset
        local column = (index - 1) % TILE_COLUMNS
        tile:ClearAllPoints()
        if row >= 0 and row < SUMMARY_ROWS then
            tile:SetPoint("TOPLEFT", column * (TILE_WIDTH + TILE_GAP), -row * (TILE_HEIGHT + TILE_GAP))
            tile:Show()
        else
            tile:Hide()
        end
    end
end

function Stats:BuildWhen(page)
    local half = (CONTENT_WIDTH - 16) / 2

    local weekdayTitle = Theme:CreateText(page, "heading")
    weekdayTitle:SetPoint("TOPLEFT", 0, 0)
    Theme:SetLocalizedText(weekdayTitle, "STATS_GRAPH_WEEKDAY")
    self.weekdayGraph = ns.Graph:Create(page)
    self.weekdayGraph:SetPoint("TOPLEFT", 0, -18)
    self.weekdayGraph:SetSize(half, 150)

    local hourTitle = Theme:CreateText(page, "heading")
    hourTitle:SetPoint("TOPLEFT", half + 16, 0)
    Theme:SetLocalizedText(hourTitle, "STATS_GRAPH_HOUR")
    self.hourGraph = ns.Graph:Create(page)
    self.hourGraph:SetPoint("TOPLEFT", half + 16, -18)
    self.hourGraph:SetSize(half, 150)

    self.whenTiles = {}
    for index, key in ipairs({
        "STATS_BEST_WEEKDAY", "STATS_BEST_HOUR", "STATS_BEST_DAY", "STATS_DAYS_PLAYED",
        "STATS_STREAK_LONGEST", "STATS_STREAK_CURRENT", "STATS_NIGHT_SHARE", "STATS_DAY_AVERAGE",
    }) do
        local tile = CreateTile(page, key)
        local row, column = math.floor((index - 1) / TILE_COLUMNS), (index - 1) % TILE_COLUMNS
        tile:SetPoint("TOPLEFT", column * (TILE_WIDTH + TILE_GAP), -176 - row * (TILE_HEIGHT + TILE_GAP))
        self.whenTiles[index] = tile
    end
end

function Stats:BuildWhere(page)
    self.whereTiles = {}
    for index, key in ipairs({ "STATS_ZONE_TOP", "STATS_ZONE_FASTEST", "STATS_ZONE_KILLS", "STATS_ZONES" }) do
        local tile = CreateTile(page, key)
        tile:SetPoint("TOPLEFT", (index - 1) * (TILE_WIDTH + TILE_GAP), 0)
        self.whereTiles[index] = tile
    end
    self.zoneTable = CreateTable(page, {
        { key = "STATS_COL_ZONE", width = 236, justify = "LEFT" },
        { key = "STATS_COL_XP", width = 86, justify = "RIGHT" },
        { key = "STATS_COL_KILLS", width = 70, justify = "RIGHT" },
        { key = "STATS_COL_QUESTS", width = 70, justify = "RIGHT" },
        { key = "STATS_COL_RATE", width = 116, justify = "RIGHT" },
    }, 0, -60, CONTENT_WIDTH, 11)
    self.zoneTable.tooltip = function(tooltip, zone)
        tooltip:AddLine(zone.name, 1, 1, 1)
        AddRow(tooltip, L["STATS_COL_XP"], ns.FormatInteger(zone.xp))
        AddRow(tooltip, L["STATS_ACTIVE_TIME"], ns.FormatDuration(zone.active))
    end
end

function Stats:BuildPrey(page)
    self.preyTiles = {}
    for index, key in ipairs({ "STATS_MOB_TOP", "STATS_MOB_RICHEST", "STATS_MOBS", "STATS_QUEST_TOP" }) do
        local tile = CreateTile(page, key)
        tile:SetPoint("TOPLEFT", (index - 1) * (TILE_WIDTH + TILE_GAP), 0)
        self.preyTiles[index] = tile
    end
    local half = (CONTENT_WIDTH - 16) / 2
    self.mobTable = CreateTable(page, {
        { key = "STATS_COL_MOB", width = 150, justify = "LEFT" },
        { key = "STATS_COL_KILLS", width = 56, justify = "RIGHT" },
        { key = "STATS_COL_XP", width = 70, justify = "RIGHT" },
    }, 0, -60, half, 9)
    self.mobTable.tooltip = function(tooltip, mob)
        tooltip:AddLine(mob.name, 1, 1, 1)
        AddRow(tooltip, L["STATS_COL_KILLS"], ns.FormatInteger(mob.kills))
        AddRow(tooltip, L["STATS_COL_XP"], ns.FormatInteger(mob.xp))
        AddRow(tooltip, L["STATS_XP_PER_KILL"], ns.FormatNumber(mob.xp / math.max(1, mob.kills)))
    end

    self.questTable = CreateTable(page, {
        { key = "STATS_COL_QUEST", width = 172, justify = "LEFT" },
        { key = "STATS_COL_XP", width = 70, justify = "RIGHT" },
        { key = "STATS_COL_LEVEL", width = 34, justify = "RIGHT" },
    }, half + 16, -60, half, 9)
    self.questTable.tooltip = function(tooltip, quest)
        tooltip:AddLine(ns.Stats.QuestName(quest), 1, 1, 1, true)
        AddRow(tooltip, L["STATS_COL_XP"], ns.FormatInteger(quest.xp))
        AddRow(tooltip, L["STATS_LEVEL"], quest.level or "?")
        if quest.at then
            AddRow(tooltip, L["STATS_DATE"], date("%d/%m/%Y", quest.at))
        end
        local holder = Stats.scope == "account" and Holder(quest)
        if holder then
            AddRow(tooltip, L["STATS_HOLDER"], holder)
        end
    end

    -- Since Midnight the kill message is often hidden from addons.
    self.preyNote = Theme:CreateText(page, "muted")
    self.preyNote:SetPoint("BOTTOMLEFT", 0, 6)
    self.preyNote:SetPoint("RIGHT", 0, 0)
    Theme:SetLocalizedText(self.preyNote, "STATS_PREY_NOTE")
    self.preyNote:SetShown(ns.Compat.flavor == "retail")
end

function Stats:BuildFriends(page)
    self.friendsTable = CreateTable(page, {
        { key = "RANK_COL_RANK", width = 28, justify = "RIGHT" },
        { key = "RANK_COL_NAME", width = 250, justify = "LEFT" },
        { key = "STATS_COL_LEVEL", width = 50, justify = "RIGHT" },
        { key = "RANK_COL_DEATHS", width = 90, justify = "RIGHT" },
        { key = "RANK_COL_SEEN", width = 162, justify = "RIGHT" },
    }, 0, 0, CONTENT_WIDTH, 12)
    self.friendsTable.tooltip = function(tooltip, entry)
        tooltip:AddLine(ns.ColorizeByClass(entry.key, entry.class))
        AddRow(tooltip, L["STATS_LEVEL"], entry.level or "?")
        AddRow(tooltip, L["RANK_COL_DEATHS"], ns.FormatInteger(entry.deaths))
        local muted = Theme.colors.muted
        tooltip:AddLine(L[entry.mine and "RANK_TOOLTIP_MINE" or "RANK_TOOLTIP_FRIEND"], muted[1], muted[2], muted[3])
    end

    self.friendsNote = Theme:CreateText(page, "muted")
    self.friendsNote:SetPoint("BOTTOMLEFT", 0, 6)
    self.friendsNote:SetPoint("RIGHT", -112, 0)
    self.friendsNote:SetWordWrap(true)

    local options = Theme:CreateButton(page, "RANK_OPTIONS", 100, 22, function()
        ns.Options:Open()
    end)
    options:SetPoint("BOTTOMRIGHT", 0, 0)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function Stats:Refresh()
    self.lastRefresh = GetTime()
    self.scope = ns.settings.panel.statsScope
    local page = ns.settings.panel.statsPage
    if not self.pages[page] then
        page = "summary"
    end
    self.scopeSelector:Refresh()
    self.pageSelector:Refresh()
    for value, frame in pairs(self.pages) do
        frame:SetShown(value == page)
    end
    -- The ranking is the same whatever the scope.
    self.scopeSelector:SetShown(page ~= "friends")
    if page == "friends" then
        self:RefreshFriends()
        return
    end

    local data
    if self.scope == "account" then
        data = ns.Stats:CollectAccount()
    else
        data = ns.Stats:Collect(ns.MainPanel:GetViewedKey())
    end

    if page == "summary" then
        self:RefreshSummary(data)
    elseif page == "when" then
        self:RefreshWhen(data)
    elseif page == "where" then
        self:RefreshWhere(data)
    else
        self:RefreshPrey(data)
    end
end

function Stats:OnTick()
    if self.lastRefresh and GetTime() - self.lastRefresh < LIVE_REFRESH_SECONDS then
        return
    end
    if ns.settings.panel.statsScope == "account" or ns.MainPanel:GetViewedKey() == ns.charKey then
        self:Refresh()
    end
end

function Stats:RefreshSummary(data)
    for index, entry in ipairs(SUMMARY) do
        SetTile(self.summaryTiles[index], entry[2](data))
    end
    self:LayoutSummary()
end

local function BarGroups(buckets, first, last, label)
    local groups = {}
    local accent = Theme.colors.accent
    for key = first, last do
        local bucket = buckets[key] or { xp = 0, active = 0 }
        groups[#groups + 1] = {
            label = label(key),
            stacks = { { { value = bucket.xp, color = accent } } },
            key = key,
            xp = bucket.xp,
            active = bucket.active,
        }
    end
    return groups
end

local function HasXP(buckets)
    for _, bucket in pairs(buckets) do
        if bucket.xp > 0 then
            return true
        end
    end
    return false
end

function Stats:RefreshWhen(data)
    local function BucketTooltip(title)
        return function(tooltip, group)
            tooltip:AddLine(title(group.key), 1, 1, 1)
            AddRow(tooltip, L["STATS_COL_XP"], ns.FormatInteger(group.xp))
            AddRow(tooltip, L["STATS_ACTIVE_TIME"], ns.FormatDuration(group.active))
            if group.active >= 60 then
                AddRow(tooltip, L["STATS_COL_RATE"], ns.FormatNumber(group.xp / group.active * 3600))
            end
        end
    end
    self.weekdayGraph:SetData({
        kind = "bars",
        groups = HasXP(data.weekday) and BarGroups(data.weekday, 1, 7, function(day)
            return L["STATS_WEEKDAY_SHORT_" .. day]
        end) or {},
        emptyText = L["STATS_NO_DATA"],
        tooltip = BucketTooltip(WeekdayName),
    })
    self.hourGraph:SetData({
        kind = "bars",
        groups = HasXP(data.hour) and BarGroups(data.hour, 0, 23, tostring) or {},
        emptyText = L["STATS_NO_DATA"],
        tooltip = BucketTooltip(HourRange),
    })

    local tiles = self.whenTiles
    SetTile(tiles[1], data.bestWeekday and WeekdayName(data.bestWeekday.weekday))
    SetTile(tiles[2], data.bestHour and HourRange(data.bestHour.hour))
    SetTile(tiles[3], data.bestDay and ("%s · %s"):format(ns.Stats.FormatDay(data.bestDay.day),
        ns.FormatNumber(data.bestDay.xp)))
    SetTile(tiles[4], ns.FormatInteger(data.daysPlayed))
    SetTile(tiles[5], L["STATS_DAYS_VALUE"]:format(data.longestStreak))
    SetTile(tiles[6], L["STATS_DAYS_VALUE"]:format(data.currentStreak))
    SetTile(tiles[7], Percent(data.nightShare))
    SetTile(tiles[8], data.averageDay and ns.FormatNumber(data.averageDay))
end

function Stats:RefreshWhere(data)
    local tiles = self.whereTiles
    local top, fastest, bloodiest = data.topZone, data.fastestZone, data.bloodiestZone
    SetTile(tiles[1], top and top.name, top and function(tooltip)
        AddRow(tooltip, L["STATS_COL_XP"], ns.FormatInteger(top.xp))
    end)
    SetTile(tiles[2], fastest and fastest.name, fastest and function(tooltip)
        AddRow(tooltip, L["STATS_COL_RATE"], ns.FormatNumber(fastest.rate))
    end)
    SetTile(tiles[3], bloodiest and bloodiest.name, bloodiest and function(tooltip)
        AddRow(tooltip, L["STATS_COL_KILLS"], ns.FormatInteger(bloodiest.kills))
    end)
    SetTile(tiles[4], ns.FormatInteger(#data.zoneList))

    self.zoneTable:SetEntries(data.zoneList, function(zone)
        return { zone.name, ns.FormatInteger(zone.xp), Count(zone.kills), Count(zone.quests), Rate(zone.rate) }
    end, "STATS_NO_DATA")
end

function Stats:RefreshPrey(data)
    local tiles = self.preyTiles
    local mob, richest, quest = data.topMob, data.richestMob, data.topQuest
    SetTile(tiles[1], mob and mob.name, mob and function(tooltip)
        AddRow(tooltip, L["STATS_COL_KILLS"], ns.FormatInteger(mob.kills))
    end)
    SetTile(tiles[2], richest and richest.name, richest and function(tooltip)
        AddRow(tooltip, L["STATS_COL_XP"], ns.FormatInteger(richest.xp))
    end)
    SetTile(tiles[3], ns.FormatInteger(#data.mobList))
    SetTile(tiles[4], quest and ns.Stats.QuestName(quest), quest and HolderTooltip(quest, function(tooltip)
        AddRow(tooltip, L["STATS_COL_XP"], ns.FormatInteger(quest.xp))
    end))

    self.mobTable:SetEntries(data.mobList, function(entry)
        return { entry.name, ns.FormatInteger(entry.kills), ns.FormatInteger(entry.xp) }
    end, "STATS_NO_DATA")
    self.questTable:SetEntries(data.questList, function(entry)
        return { ns.Stats.QuestName(entry), ns.FormatInteger(entry.xp), entry.level or "?" }
    end, "STATS_NO_DATA")
end

--- Seen column: now for the logged character, else how long ago.
local function SeenText(entry)
    if entry.current then
        return L["CHAR_SEEN_NOW"]
    end
    if not entry.seen then
        return UNKNOWN()
    end
    return L["CHAR_SEEN_AGO"]:format(ns.FormatDuration(math.max(0, time() - entry.seen)))
end

function Stats:RefreshFriends()
    local ranking = ns.Ranking
    local accent = Theme.Hex(Theme.colors.accent)
    self.friendsTable:SetEntries(ranking:GetEntries(), function(entry, rank)
        local name = ns.ColorizeByClass(ranking.ShortName(entry.key), entry.class)
        if entry.mine then
            name = name .. " " .. accent .. "(" .. L["RANK_MINE"] .. ")|r"
        end
        return { rank .. ".", name, entry.level or "?", ns.FormatInteger(entry.deaths), SeenText(entry) }
    end, "STATS_NO_DATA")

    self.friendsNote:SetText(L[ranking:IsActive() and "RANK_FOOTER" or "RANK_DISABLED"])
end

ns:RegisterMessage("XPL_RANKING_CHANGED", function()
    if ns.settings.panel.statsPage == "friends" then
        ns.MainPanel:Refresh()
    end
end)
ns:RegisterMessage("XPL_DEATH", function()
    if ns.settings.panel.statsPage == "friends" then
        ns.MainPanel:Refresh()
    end
end)

ns.MainPanel:RegisterView(Stats)
