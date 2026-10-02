--[[----------------------------------------------------------------------------
    XPLedger - Characters view
    Table of every tracked character. Selecting a row makes the Levels and
    Sources views inspect that character.
------------------------------------------------------------------------------]]

local _, ns = ...

local Theme = ns.Theme
local L = ns.L

local Characters = { id = "characters", label = "TAB_CHARACTERS" }

local ROW_HEIGHT = 24
local VISIBLE_ROWS = 11

-- Column layout: locale key of the header, x offset, width and justification.
local COLUMNS = {
    { key = "CHAR_COL_NAME", x = 8, width = 184, justify = "LEFT" },
    { key = "CHAR_COL_LEVEL", x = 196, width = 40, justify = "CENTER" },
    { key = "CHAR_COL_PLAYED", x = 240, width = 90, justify = "RIGHT" },
    { key = "CHAR_COL_AVG", x = 334, width = 86, justify = "RIGHT" },
    { key = "CHAR_COL_RESTED", x = 424, width = 80, justify = "RIGHT" },
    { key = "CHAR_COL_SEEN", x = 508, width = 96, justify = "RIGHT" },
}
local RESTED_COLUMN = 5
local SEEN_COLUMN = 6

--------------------------------------------------------------------------------
-- Row data
--------------------------------------------------------------------------------

local function FormatLastSeen(record)
    if record == ns.char then
        return L["CHAR_SEEN_NOW"]
    end
    if not record.lastSeen then
        return L["DURATION_UNKNOWN"]
    end
    return L["CHAR_SEEN_AGO"]:format(ns.FormatDuration(time() - record.lastSeen))
end

--- Rested pool as a percentage of the level bar, colored like the rested bar.
local function FormatRested(record)
    local pool, fraction = ns.Rested:Estimate(record)
    if not pool then
        return L["DURATION_UNKNOWN"]
    end
    local text = ("%d%%"):format(math.floor(fraction * 100 + 0.5))
    if fraction >= 1.5 then
        return Theme.Hex(Theme.colors.rested) .. text .. "|r"
    end
    return text
end

local function ShowRowTooltip(row)
    local record = row.key and ns.db.characters[row.key]
    if not record then
        return
    end
    local muted = Theme.colors.muted
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.MainPanel.FormatCharacterName(record, true))
    local pool, fraction, fullIn, resting = ns.Rested:Estimate(record)
    if pool then
        GameTooltip:AddDoubleLine(L["TOOLTIP_RESTED"], ("%s (%d%%)"):format(ns.FormatInteger(pool),
            math.floor(fraction * 100 + 0.5)), muted[1], muted[2], muted[3], 1, 1, 1)
        GameTooltip:AddDoubleLine(L["RESTED_FULL_IN"], fullIn == 0 and L["RESTED_FULL"] or ns.FormatDuration(fullIn),
            muted[1], muted[2], muted[3], 1, 1, 1)
        GameTooltip:AddLine(resting and L["RESTED_IN_INN"] or L["RESTED_OUTSIDE"], muted[1], muted[2], muted[3], true)
        if record ~= ns.char then
            GameTooltip:AddLine(L["RESTED_ESTIMATED"], muted[1], muted[2], muted[3], true)
        end
    else
        GameTooltip:AddLine(L["RESTED_UNKNOWN"], muted[1], muted[2], muted[3], true)
    end
    GameTooltip:Show()
end

local function GetPlayed(record)
    if record == ns.char then
        return ns.History:GetPlayedNow() or record.played
    end
    return record.played
end

--------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------

function Characters:CreateRow(index)
    local row = CreateFrame("Button", nil, self.list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)

    row.selectedTexture = Theme:CreateTexture(row, Theme.colors.selection, "BACKGROUND")
    row.selectedTexture:SetAllPoints()
    local highlight = Theme:CreateTexture(row, { 1, 1, 1, 0.05 }, "HIGHLIGHT")
    highlight:SetAllPoints()

    row.cells = {}
    for i, column in ipairs(COLUMNS) do
        local cell = Theme:CreateText(row, i == 1 and "normal" or "muted", column.justify)
        cell:SetPoint("LEFT", column.x, 0)
        cell:SetWidth(column.width)
        row.cells[i] = cell
    end

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(selfRow)
        ns.MainPanel:SetViewedKey(selfRow.key)
        self:Refresh()
    end)
    return row
end

function Characters:Build(content)
    self.content = content
    self.offset = 0

    -- Header.
    for _, column in ipairs(COLUMNS) do
        local header = Theme:CreateText(content, "label", column.justify)
        header:SetPoint("TOPLEFT", column.x, -4)
        header:SetWidth(column.width)
        Theme:SetLocalizedText(header, column.key)
    end
    local separator = Theme:CreateTexture(content, Theme.colors.border)
    separator:SetPoint("TOPLEFT", 0, -22)
    separator:SetPoint("TOPRIGHT", 0, -22)
    separator:SetHeight(1)

    -- Scrollable list (mouse wheel).
    self.list = CreateFrame("Frame", nil, content)
    self.list:SetPoint("TOPLEFT", 0, -26)
    self.list:SetPoint("TOPRIGHT", 0, -26)
    self.list:SetHeight(ROW_HEIGHT * VISIBLE_ROWS)
    self.list:EnableMouseWheel(true)
    self.list:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #(self.entries or {}) - VISIBLE_ROWS)
        self.offset = ns.Clamp(self.offset - delta, 0, maxOffset)
        self:Refresh()
    end)
    self.rows = {}
    for i = 1, VISIBLE_ROWS do
        self.rows[i] = self:CreateRow(i)
    end

    -- Footer.
    local hint = Theme:CreateText(content, "muted")
    hint:SetPoint("BOTTOMLEFT", 0, 6)
    Theme:SetLocalizedText(hint, "CHAR_HINT")

    self.deleteButton = Theme:CreateButton(content, "CHAR_DELETE", 100, 22, function()
        local key = ns.MainPanel:GetViewedKey()
        local record = ns.db.characters[key]
        if not record or key == ns.charKey then
            return
        end
        Theme:Confirm(L["CHAR_DELETE_CONFIRM"]:format(ns.MainPanel.FormatCharacterName(record, true)), function()
            ns.Database:DeleteCharacter(key)
            ns.MainPanel:SetViewedKey(nil)
            self:Refresh()
        end)
    end)
    self.deleteButton:SetPoint("BOTTOMRIGHT", 0, 0)
end

function Characters:Refresh()
    self.entries = ns.Database:GetCharacterList()
    local maxOffset = math.max(0, #self.entries - VISIBLE_ROWS)
    self.offset = ns.Clamp(self.offset or 0, 0, maxOffset)
    local viewedKey = ns.MainPanel:GetViewedKey()

    for i, row in ipairs(self.rows) do
        local entry = self.entries[i + self.offset]
        if entry then
            local record = entry.record
            local stats = ns.History:GetCharacterStats(record)
            local name = ns.MainPanel.FormatCharacterName(record)
            local suffix = record.realm and (" |cff8a8f99- " .. record.realm .. "|r") or ""
            if entry.key == ns.charKey then
                suffix = suffix .. " " .. Theme.Hex(Theme.colors.accent) .. "(" .. L["CHAR_CURRENT"] .. ")|r"
            end
            row.key = entry.key
            row.cells[1]:SetText(name .. suffix)
            row.cells[2]:SetText(record.level or "?")
            row.cells[3]:SetText(ns.FormatDuration(GetPlayed(record)))
            row.cells[4]:SetText(ns.FormatDuration(stats.average))
            row.cells[RESTED_COLUMN]:SetText(FormatRested(record))
            row.cells[SEEN_COLUMN]:SetText(FormatLastSeen(record))
            row.selectedTexture:SetShown(entry.key == viewedKey)
            row:Show()
        else
            row:Hide()
        end
    end

    local canDelete = viewedKey ~= ns.charKey
    self.deleteButton:SetShown(canDelete)
end

ns.MainPanel:RegisterView(Characters)
