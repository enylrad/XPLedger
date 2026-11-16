--[[----------------------------------------------------------------------------
    XPLedger - Friends view
    The friends ranking (see Ranking): the account's characters and the
    Battle.net friends who share, in a table that can be sorted by deaths,
    level or leveling speed. Clicking a row shows its breakdown under the
    table: level, deaths, XP/hour, optimization (levels per active hour), time to
    level, time played, speed, kills,
    quests, runs and the share of experience earned by source.
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = ns.Theme
local L = ns.L
local Blocks = ns.StatsBlocks

local Friends = { id = "friends", label = "TAB_FRIENDS" }

local CONTENT_WIDTH = ns.MainPanel.CONTENT_WIDTH
local TABLE_TOP = -30
local TABLE_ROWS = 8
local DETAIL_TOP = -220

local SORTS = {
    { value = "deaths", label = "RANK_SORT_DEATHS" },
    { value = "level", label = "RANK_SORT_LEVEL" },
    { value = "speed", label = "RANK_SORT_SPEED" },
    { value = "optimization", label = "RANK_SORT_OPTIMIZATION" },
}
local DETAIL_COLUMNS = 5

-- Breakdown tiles: { label, function(entry) return value end }.
local DETAILS

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

local UNKNOWN = function() return L["DURATION_UNKNOWN"] end

--- Level with the part of it done: "23 (45%)".
local function LevelText(entry)
    if not entry.level then
        return "?"
    end
    if not entry.progress then
        return tostring(entry.level)
    end
    return ("%d (%d%%)"):format(entry.level, math.floor(entry.progress / 10))
end

local function RateText(entry)
    return entry.rate and ns.FormatNumber(entry.rate) or UNKNOWN()
end

local function PlayedText(entry)
    return entry.played and ns.FormatDuration(entry.played) or UNKNOWN()
end

local function CountText(value)
    return value and ns.FormatInteger(value) or UNKNOWN()
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

local function SpeedText(entry)
    local speed = ns.Ranking.GetSpeed(entry)
    return speed and L["RANK_SPEED_VALUE"]:format(speed) or UNKNOWN()
end

DETAILS = {
    { "STATS_COL_LEVEL", LevelText },
    { "RANK_COL_DEATHS", function(entry) return ns.FormatInteger(entry.deaths) end },
    { "STATS_COL_RATE", RateText },
    { "RANK_EFFICIENCY", function(entry) return entry.efficiency and L["RANK_EFFICIENCY_VALUE"]:format(entry.efficiency) or UNKNOWN() end },
    { "STAT_ETA", function(entry) return entry.eta and ns.FormatDuration(entry.eta) or UNKNOWN() end },
    { "RANK_PLAYED", PlayedText },
    { "RANK_SPEED", SpeedText },
    { "STATS_KILLS", function(entry) return CountText(entry.kills) end },
    { "STATS_QUESTS", function(entry) return CountText(entry.quests) end },
    { "STATS_RUNS", function(entry) return CountText(entry.runs) end },
}

--- "Enemigos 62% · Misiones 30% · ..." with the source colors, skipping
--- the sources under 1%.
local function SharesText(entry)
    if not entry.shares then
        return L["RANK_SHARES_NONE"]
    end
    local parts = {}
    for _, item in ipairs(ns.Ranking.SOURCES) do
        local share = entry.shares[item.key] or 0
        if share > 0 then
            local color = Theme.sourceColors[item.source] or Theme.colors.muted
            parts[#parts + 1] = ("%s %s %d%%"):format(Theme.Swatch(color), L["SOURCE_" .. item.source], share)
        end
    end
    return #parts > 0 and table.concat(parts, "   ") or L["RANK_SHARES_NONE"]
end

local function DisplayName(entry, withRealm)
    return ns.ColorizeByClass(ns.Ranking.ShortName(entry.key, withRealm), entry.class)
end

--------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------

function Friends:Build(content)
    self.content = content

    self.sortSelector = Theme:CreateSegmented(content, SORTS,
        function() return ns.settings.panel.rankingSort end,
        function(value)
            ns.settings.panel.rankingSort = value
            self:Refresh()
        end)
    self.sortSelector:SetPoint("TOPLEFT", 0, 0)

    local options = Theme:CreateButton(content, "RANK_OPTIONS", 100, 22, function()
        ns.Options:Open()
    end)
    options:SetPoint("TOPRIGHT", 0, 0)

    self.table = Blocks.CreateTable(content, {
        { key = "RANK_COL_RANK", width = 24, justify = "RIGHT" },
        { key = "RANK_COL_NAME", width = 160 + ns.MainPanel.EXTRA_WIDTH, justify = "LEFT" },
        { key = "STATS_COL_LEVEL", width = 76, justify = "RIGHT" },
        { key = "RANK_COL_DEATHS", width = 58, justify = "RIGHT" },
        { key = "RANK_COL_RATE", width = 70, justify = "RIGHT" },
        { key = "RANK_COL_PLAYED", width = 90, justify = "RIGHT" },
        { key = "RANK_COL_SEEN", width = 106, justify = "RIGHT" },
    }, 0, TABLE_TOP, CONTENT_WIDTH, TABLE_ROWS)
    self.table.tooltip = function(tooltip, entry)
        tooltip:AddLine(DisplayName(entry, true))
        local muted = Theme.colors.muted
        tooltip:AddLine(L[entry.mine and "RANK_TOOLTIP_MINE" or "RANK_TOOLTIP_FRIEND"], muted[1], muted[2], muted[3])
        tooltip:AddLine(L["RANK_CLICK_HINT"], muted[1], muted[2], muted[3])
    end
    self.table.onClick = function(entry)
        self.selectedKey = entry.key
        self:Refresh()
    end
    self.table.isSelected = function(entry)
        return entry.key == self.selectedKey
    end

    self.detailTitle = Theme:CreateText(content, "heading")
    self.detailTitle:SetPoint("TOPLEFT", 0, DETAIL_TOP)
    self.detailTitle:SetPoint("RIGHT", 0, 0)

    self.tiles = {}
    local tileWidth = (CONTENT_WIDTH - Blocks.TILE_GAP * (DETAIL_COLUMNS - 1)) / DETAIL_COLUMNS
    for index, detail in ipairs(DETAILS) do
        local tile = Blocks.CreateTile(content, detail[1])
        tile:SetWidth(tileWidth)
        local column = (index - 1) % DETAIL_COLUMNS
        local row = math.floor((index - 1) / DETAIL_COLUMNS)
        tile:SetPoint("TOPLEFT", column * (tileWidth + Blocks.TILE_GAP),
            DETAIL_TOP - 20 - row * (Blocks.TILE_HEIGHT + Blocks.TILE_GAP))
        self.tiles[index] = tile
    end

    local tilesBottom = DETAIL_TOP - 20 - 2 * Blocks.TILE_HEIGHT - Blocks.TILE_GAP
    self.shares = Theme:CreateText(content, "normal")
    self.shares:SetPoint("TOPLEFT", 0, tilesBottom - 8)
    self.shares:SetPoint("RIGHT", 0, 0)

    self.note = Theme:CreateText(content, "muted")
    self.note:SetPoint("BOTTOMLEFT", 0, 2)
    self.note:SetPoint("RIGHT", 0, 0)
    self.note:SetWordWrap(true)
end

function Friends:Refresh()
    self.lastRefresh = GetTime()
    local ranking = ns.Ranking
    self.sortSelector:Refresh()

    local entries = ranking:GetEntries(ns.settings.panel.rankingSort)
    local selected
    for _, entry in ipairs(entries) do
        if entry.key == self.selectedKey then
            selected = entry
        end
    end
    if not selected then
        -- The logged character by default.
        for _, entry in ipairs(entries) do
            if entry.current then
                selected = entry
            end
        end
        selected = selected or entries[1]
        self.selectedKey = selected and selected.key
    end

    local accent = Theme.Hex(Theme.colors.accent)
    self.table:SetEntries(entries, function(entry, rank)
        local name = DisplayName(entry)
        if entry.mine then
            name = name .. " " .. accent .. "(" .. L["RANK_MINE"] .. ")|r"
        end
        return { rank .. ".", name, LevelText(entry), ns.FormatInteger(entry.deaths), RateText(entry),
            PlayedText(entry), SeenText(entry) }
    end, "STATS_NO_DATA")

    for index, detail in ipairs(DETAILS) do
        Blocks.SetTile(self.tiles[index], selected and detail[2](selected) or UNKNOWN())
    end
    if selected then
        self.detailTitle:SetText(("%s  %s"):format(DisplayName(selected, true),
            L["LEVEL_SHORT"]:format(selected.level or 0) .. (selected.progress
                and (" (%d%%)"):format(math.floor(selected.progress / 10)) or "")))
    else
        self.detailTitle:SetText("")
    end
    self.shares:SetText(selected and (L["RANK_SHARES"] .. "  " .. SharesText(selected)) or "")
    self.note:SetText(L[ranking:IsActive() and "RANK_FOOTER" or "RANK_DISABLED"])
end

local LIVE_REFRESH_SECONDS = 30

function Friends:OnTick()
    if not self.lastRefresh or GetTime() - self.lastRefresh >= LIVE_REFRESH_SECONDS then
        self:Refresh()
    end
end

local function RefreshIfShown()
    if ns.MainPanel.activeView == Friends then
        ns.MainPanel:Refresh()
    end
end

for _, message in ipairs({ "XPL_RANKING_CHANGED", "XPL_DEATH", "XPL_DEATH_SYNC", "XPL_LEVEL_UP" }) do
    ns:RegisterMessage(message, RefreshIfShown)
end

--- The tab only shows while sharing is on (see MainPanel:UpdateTabs).
function Friends:IsAvailable()
    return ns.Ranking:IsActive()
end

ns.MainPanel:RegisterView(Friends)
