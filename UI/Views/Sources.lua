--[[----------------------------------------------------------------------------
    XPLedger - Sources view
    Breakdown of the experience of the selected character by source (mobs,
    quests, exploration...) and by activity (open world, dungeons,
    battlegrounds...), for the current level or for everything tracked.
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = ns.Theme
local L = ns.L

local Sources = { id = "sources", label = "TAB_SOURCES", followsSelection = true }

local COLUMN_WIDTH = 296
local COLUMN_GAP = 20
local ROW_HEIGHT = 36

local SCOPES = {
    { value = "level", label = "SCOPE_LEVEL" },
    { value = "all", label = "SCOPE_ALL" },
}

--------------------------------------------------------------------------------
-- Breakdown column
--------------------------------------------------------------------------------

--- Creates a column with a title, a stacked overview bar and one row per bucket.
local function CreateColumn(parent, titleKey, buckets, colors, labelPrefix)
    local column = CreateFrame("Frame", nil, parent)
    column:SetWidth(COLUMN_WIDTH)
    column:SetHeight(60 + #buckets * ROW_HEIGHT)

    local title = Theme:CreateText(column, 12)
    title:SetPoint("TOPLEFT")
    Theme:SetLocalizedText(title, titleKey)

    -- Stacked overview bar.
    local stackTrack = Theme:CreateTexture(column, Theme.colors.track, "BACKGROUND")
    stackTrack:SetPoint("TOPLEFT", 0, -22)
    stackTrack:SetSize(COLUMN_WIDTH, 10)
    column.stackSegments = {}
    for i, bucket in ipairs(buckets) do
        local color = colors[bucket]
        column.stackSegments[i] = Theme:CreateTexture(column, { color[1], color[2], color[3], 1 })
        column.stackSegments[i]:SetHeight(10)
    end

    column.rows = {}
    for i, bucket in ipairs(buckets) do
        local color = colors[bucket]
        local top = -46 - (i - 1) * ROW_HEIGHT
        local row = {}

        row.label = Theme:CreateText(column, 12)
        row.label:SetPoint("TOPLEFT", 0, top)
        Theme:SetLocalizedText(row.label, function()
            return Theme.Swatch(color, 9) .. "  " .. L[labelPrefix .. bucket]
        end)

        row.value = Theme:CreateText(column, 11, Theme.colors.muted, "RIGHT")
        row.value:SetPoint("TOPRIGHT", 0, top)

        local track = Theme:CreateTexture(column, Theme.colors.track, "BACKGROUND")
        track:SetPoint("TOPLEFT", 0, top - 17)
        track:SetSize(COLUMN_WIDTH, 4)

        row.bar = Theme:CreateTexture(column, { color[1], color[2], color[3], 1 })
        row.bar:SetPoint("TOPLEFT", track, "TOPLEFT")
        row.bar:SetHeight(4)

        column.rows[i] = row
    end

    column.empty = Theme:CreateText(column, 11, Theme.colors.muted)
    column.empty:SetPoint("TOPLEFT", 0, -46)

    --- Fills the column with an { [bucket] = xp } map.
    function column:SetValues(values)
        local total = 0
        for _, bucket in ipairs(buckets) do
            total = total + (values[bucket] or 0)
        end

        local x = 0
        for i, bucket in ipairs(buckets) do
            local amount = values[bucket] or 0
            local share = total > 0 and amount / total or 0
            local row = self.rows[i]
            row.value:SetText(("%d%%  ·  %s"):format(math.floor(share * 100 + 0.5), ns.FormatNumber(amount)))
            row.bar:SetWidth(math.max(1, COLUMN_WIDTH * share))
            row.bar:SetShown(share > 0)

            local segment = self.stackSegments[i]
            segment:ClearAllPoints()
            segment:SetPoint("TOPLEFT", stackTrack, "TOPLEFT", x, 0)
            segment:SetWidth(math.max(1, COLUMN_WIDTH * share))
            segment:SetShown(share > 0)
            x = x + COLUMN_WIDTH * share
        end
        self.empty:SetText(total > 0 and "" or L["SOURCES_EMPTY"])
        for _, row in ipairs(self.rows) do
            row.label:SetShown(total > 0)
            row.value:SetShown(total > 0)
        end
    end

    return column
end

--------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------

function Sources:Build(content)
    self.content = content

    self.counts = Theme:CreateText(content, 11, Theme.colors.muted)
    self.counts:SetPoint("TOPLEFT", 0, -4)

    self.scope = Theme:CreateSegmented(content, SCOPES,
        function() return ns.settings.panel.sourcesScope end,
        function(value)
            ns.settings.panel.sourcesScope = value
            self:Refresh()
        end)
    self.scope:SetPoint("TOPRIGHT", 0, 0)

    self.bySource = CreateColumn(content, "SOURCES_BY_SOURCE", ns.Sources.SOURCES, Theme.sourceColors, "SOURCE_")
    self.bySource:SetPoint("TOPLEFT", 0, -40)

    self.byContext = CreateColumn(content, "SOURCES_BY_CONTEXT", ns.Sources.CONTEXTS, Theme.contextColors, "CONTEXT_")
    self.byContext:SetPoint("TOPLEFT", COLUMN_WIDTH + COLUMN_GAP, -40)
end

function Sources:Refresh()
    self.scope:Refresh()
    local record = ns.MainPanel:GetViewedRecord()
    local data
    if ns.settings.panel.sourcesScope == "level" then
        data = record.levels and record.levels[record.level]
    else
        data = record.totals
    end
    data = data or {}

    self.bySource:SetValues(data.sources or {})
    self.byContext:SetValues(data.contexts or {})
    self.counts:SetText(L["SOURCES_COUNTS"]:format(ns.FormatInteger(data.kills or 0), ns.FormatInteger(data.quests or 0)))
end

ns.MainPanel:RegisterView(Sources)
