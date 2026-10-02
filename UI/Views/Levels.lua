--[[----------------------------------------------------------------------------
    XPLedger - Levels view
    Played time per level of the selected character as a bar chart, optionally
    compared side by side with another character, plus summary tiles.
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = ns.Theme
local L = ns.L

local Levels = { id = "levels", label = "TAB_LEVELS", followsSelection = true }

local CONTENT_WIDTH = 612
local TILE_GAP = 8

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function ClassColor(record)
    local r, g, b = ns.Compat.GetClassColor(record and record.class)
    return { r, g, b }
end

--- Collects played time per level of a record: { [level] = seconds }.
local function CollectPlayed(record)
    local result = {}
    if not record then
        return result
    end
    for level in pairs(record.levels or {}) do
        local played = ns.History:GetLevelPlayed(record, level)
        if played then
            result[level] = played
        end
    end
    return result
end

--- Picks the axis unit so labels stay readable.
local function ChooseUnit(maxSeconds)
    if maxSeconds >= 7200 then
        return 3600, "h"
    end
    return 60, "m"
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
    if not entry.playedEnd then
        tooltip:AddLine(L["LEVELS_IN_PROGRESS"], Theme.colors.accent[1], Theme.colors.accent[2], Theme.colors.accent[3])
    elseif entry.partial then
        tooltip:AddLine(L["LEVELS_PARTIAL"], muted[1], muted[2], muted[3])
    end
end

--------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------

function Levels:Build(content)
    self.content = content

    local title = Theme:CreateText(content, "heading")
    title:SetPoint("TOPLEFT", 0, -4)
    Theme:SetLocalizedText(title, "LEVELS_TITLE")

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

    self.legend = Theme:CreateText(content, "muted")
    self.legend:SetPoint("TOPLEFT", 0, -22)

    self.graph = ns.Graph:Create(content)
    self.graph:SetPoint("TOPLEFT", 0, -40)
    self.graph:SetPoint("TOPRIGHT", 0, -40)
    self.graph:SetHeight(234)

    local tileWidth = (CONTENT_WIDTH - TILE_GAP * 3) / 4
    self.tiles = {}
    for index, key in ipairs({ "LEVELS_TOTAL", "LEVELS_AVERAGE", "LEVELS_FASTEST", "LEVELS_SLOWEST" }) do
        local tile = Theme:CreateStat(content, key)
        tile:SetWidth(tileWidth)
        tile:SetPoint("BOTTOMLEFT", (index - 1) * (tileWidth + TILE_GAP), 0)
        self.tiles[index] = tile
    end
end

function Levels:RefreshTiles(record)
    local stats = ns.History:GetCharacterStats(record)
    local function LevelValue(entry)
        if not entry then
            return L["DURATION_UNKNOWN"]
        end
        return ("%s  ·  %s"):format(L["LEVEL_SHORT"]:format(entry.level), ns.FormatDuration(entry.played))
    end
    self.tiles[1].value:SetText(stats.completed > 0 and ns.FormatDuration(stats.totalPlayed) or L["DURATION_UNKNOWN"])
    self.tiles[2].value:SetText(ns.FormatDuration(stats.average))
    self.tiles[3].value:SetText(LevelValue(stats.fastest))
    self.tiles[4].value:SetText(LevelValue(stats.slowest))
end

function Levels:Refresh()
    local record = ns.MainPanel:GetViewedRecord()
    if self.compareKey and (self.compareKey == ns.MainPanel:GetViewedKey() or not ns.db.characters[self.compareKey]) then
        self.compareKey = nil
    end
    local compare = self.compareKey and ns.db.characters[self.compareKey]
    self.compareDropdown:Refresh()

    local primaryColor = ClassColor(record)
    local compareColor = ClassColor(compare)
    if compare and compare.class == record.class then
        compareColor = { 0.62, 0.64, 0.70 }
    end

    -- Legend.
    if compare then
        self.legend:SetText(("%s %s     %s %s"):format(Theme.Swatch(primaryColor), record.name or "?",
            Theme.Swatch(compareColor), compare.name or "?"))
    else
        self.legend:SetText("")
    end

    -- Bars.
    local primaryPlayed = CollectPlayed(record)
    local comparePlayed = compare and CollectPlayed(compare) or {}
    local levelSet, maxSeconds = {}, 0
    for level, seconds in pairs(primaryPlayed) do
        levelSet[level] = true
        maxSeconds = math.max(maxSeconds, seconds)
    end
    for level, seconds in pairs(comparePlayed) do
        levelSet[level] = true
        maxSeconds = math.max(maxSeconds, seconds)
    end
    local levels = {}
    for level in pairs(levelSet) do
        levels[#levels + 1] = level
    end
    table.sort(levels)

    local unitSeconds, unitSuffix = ChooseUnit(maxSeconds)
    local groups = {}
    for _, level in ipairs(levels) do
        local stacks = { { { value = (primaryPlayed[level] or 0) / unitSeconds, color = primaryColor } } }
        if compare then
            stacks[2] = { { value = (comparePlayed[level] or 0) / unitSeconds, color = compareColor } }
        end
        groups[#groups + 1] = { label = tostring(level), level = level, stacks = stacks }
    end

    self.graph:SetData({
        kind = "bars",
        groups = groups,
        emptyText = L["LEVELS_EMPTY"],
        yFormatter = function(value) return ("%g%s"):format(ns.Round(value, 1), unitSuffix) end,
        tooltip = function(tooltip, group)
            tooltip:AddLine(ns.L["TOOLTIP_LEVEL"]:format(group.level), 1, 1, 1)
            AddCharacterLines(tooltip, record, group.level)
            if compare then
                tooltip:AddLine(" ")
                AddCharacterLines(tooltip, compare, group.level)
            end
        end,
    })

    self:RefreshTiles(record)
end

function Levels:OnTick()
    -- The in-progress level grows with played time; redraw now and then.
    self.ticks = (self.ticks or 0) + 1
    if self.ticks % 30 == 0 then
        self:Refresh()
    end
end

ns.MainPanel:RegisterView(Levels)
