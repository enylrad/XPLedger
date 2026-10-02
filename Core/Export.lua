--[[----------------------------------------------------------------------------
    XPLedger - Export
    Turns the leveling history and the runs of a character into CSV text that
    can be copied out of the game and pasted into a spreadsheet.
------------------------------------------------------------------------------]]

local _, ns = ...

local Export = ns:NewModule("Export")

--- Quotes a CSV field when it contains separators, quotes or line breaks.
local function Field(value)
    if value == nil then
        return ""
    end
    local text = tostring(value)
    if text:find('[,"\n]') then
        text = '"' .. text:gsub('"', '""') .. '"'
    end
    return text
end

local function Line(fields)
    local out = {}
    for i = 1, #fields do
        out[i] = Field(fields[i])
    end
    return table.concat(out, ",")
end

local function Round(value)
    return value and math.floor(value + 0.5) or nil
end

local function FormatDate(epoch)
    return epoch and date("%Y-%m-%d %H:%M", epoch) or nil
end

--- CSV of the levels of a character record, one row per level.
function Export:LevelsCSV(record)
    local sources, contexts = ns.Sources.SOURCES, ns.Sources.CONTEXTS
    local header = { "level", "played_seconds", "real_seconds", "started", "ended", "xp", "kills",
        "quests", "rested_xp", "partial" }
    for _, source in ipairs(sources) do
        header[#header + 1] = "xp_" .. source
    end
    for _, context in ipairs(contexts) do
        header[#header + 1] = "xp_" .. context
    end
    local lines = { Line(header) }

    local levels = {}
    for level in pairs(record.levels or {}) do
        levels[#levels + 1] = level
    end
    table.sort(levels)
    for _, level in ipairs(levels) do
        local entry = record.levels[level]
        local realTime = (not entry.partial and entry.startedAt and entry.endedAt)
            and entry.endedAt - entry.startedAt or nil
        local row = {
            level, Round(ns.History:GetLevelPlayed(record, level)), realTime,
            FormatDate(entry.startedAt), FormatDate(entry.endedAt), entry.xp, entry.kills,
            entry.quests, entry.rested, entry.partial and "yes" or "no",
        }
        for _, source in ipairs(sources) do
            row[#row + 1] = (entry.sources and entry.sources[source]) or 0
        end
        for _, context in ipairs(contexts) do
            row[#row + 1] = (entry.contexts and entry.contexts[context]) or 0
        end
        lines[#lines + 1] = Line(row)
    end
    return table.concat(lines, "\n")
end

--- CSV of the instance runs of a character record, oldest first.
function Export:RunsCSV(record)
    local lines = { Line({ "instance", "type", "difficulty", "level", "started", "duration_seconds",
        "xp", "kills", "quests", "xp_per_hour" }) }
    for _, run in ipairs(record.runs or {}) do
        lines[#lines + 1] = Line({
            run.name, run.kind, run.difficulty, run.level, FormatDate(run.startedAt),
            Round(ns.Runs:GetDuration(run)), run.xp, run.kills, run.quests, Round(ns.Runs:GetRate(run)),
        })
    end
    return table.concat(lines, "\n")
end

--- Opens the copy dialog with the levels ("levels") or runs ("runs") of a
--- character key (the logged character by default).
function Export:Show(kind, key)
    key = key or ns.charKey
    local record = ns.db.characters[key]
    if not record then
        return
    end
    local text = kind == "runs" and self:RunsCSV(record) or self:LevelsCSV(record)
    local titleKey = kind == "runs" and "EXPORT_RUNS_TITLE" or "EXPORT_LEVELS_TITLE"
    ns.Theme:ShowTextDialog(ns.L[titleKey]:format(record.name or key), text)
end
