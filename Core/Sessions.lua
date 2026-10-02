--[[----------------------------------------------------------------------------
    XPLedger - Session summaries
    Archives a short summary of every finished session and prints the last
    one at login. /xpl session prints the current session compared with the
    previous one.

    A session is archived when the next login replaces it (a /reload keeps
    the session alive, so it is never archived twice).

    char.sessions = { <summary>, ... }   oldest first
    <summary> = { startedAt, endedAt, active, xp, levels, rate, source, runs }
------------------------------------------------------------------------------]]

local _, ns = ...

local Sessions = ns:NewModule("Sessions")

local MAX_SESSIONS = 30
local MIN_DURATION = 300   -- shorter sessions without experience are not kept

--------------------------------------------------------------------------------
-- Summaries
--------------------------------------------------------------------------------

local function TopKey(map)
    local best, bestValue = nil, 0
    for key, value in pairs(map or {}) do
        if value > bestValue then
            best, bestValue = key, value
        end
    end
    return best
end

local function CountRuns(record, from, to)
    local count = 0
    for _, run in ipairs(record.runs or {}) do
        if run.startedAt >= from and run.startedAt <= to then
            count = count + 1
        end
    end
    return count
end

--- Builds the summary of a session table. `endLevel` is the level reached.
function Sessions:Summarize(session, endLevel, live)
    local endedAt = live and time() or (session.lastUpdate or session.startedAt)
    local afkSeconds = ns.settings.afkThreshold * 60
    local active = session.activeTime or 0
    if live then
        active = active + ns.Clamp(time() - (session.lastGainAt or session.startedAt), 0, afkSeconds)
    end
    local xp = session.xp or 0
    return {
        startedAt = session.startedAt,
        endedAt = endedAt,
        active = active,
        xp = xp,
        levels = (endLevel and session.startLevel) and math.max(0, endLevel - session.startLevel) or 0,
        rate = (xp > 0 and active >= 60) and xp / active * 3600 or nil,
        source = TopKey(session.sources),
        runs = CountRuns(ns.char, session.startedAt, endedAt),
    }
end

--- One line describing a summary. `previous` adds the rate comparison.
function Sessions:Format(summary, previous)
    local L = ns.L
    local parts = {
        L["SESSION_DURATION"]:format(ns.FormatDuration(summary.endedAt - summary.startedAt),
            ns.FormatDuration(summary.active)),
        L["SESSION_XP"]:format(ns.FormatInteger(summary.xp)),
    }
    if summary.levels > 0 then
        parts[#parts + 1] = L["SESSION_LEVELS"]:format(summary.levels)
    end
    if summary.rate then
        local rate = L["SESSION_RATE"]:format(ns.FormatNumber(summary.rate))
        if previous and previous.rate and previous.rate > 0 then
            local change = (summary.rate / previous.rate - 1) * 100
            local color = ns.Theme.Hex(change >= 0 and ns.Theme.colors.better or ns.Theme.colors.worse)
            rate = rate .. " " .. color .. L["SESSION_VS_LAST"]:format(math.floor(change + 0.5)) .. "|r"
        end
        parts[#parts + 1] = rate
    end
    if summary.runs > 0 then
        parts[#parts + 1] = L["SESSION_RUNS"]:format(summary.runs)
    end
    if summary.source then
        parts[#parts + 1] = L["SESSION_SOURCE"]:format(L["SOURCE_" .. summary.source]:lower())
    end
    return table.concat(parts, "  ·  ")
end

--- The most recent archived summary of the logged character, or nil.
function Sessions:GetLast()
    local sessions = ns.char.sessions
    return sessions[#sessions]
end

function Sessions:Archive(session)
    local summary = self:Summarize(session, ns.char.level)
    if summary.xp <= 0 and (summary.endedAt - summary.startedAt < MIN_DURATION or ns.Compat.IsAtMaxLevel()) then
        return nil
    end
    local sessions = ns.char.sessions
    sessions[#sessions + 1] = summary
    while #sessions > MAX_SESSIONS do
        table.remove(sessions, 1)
    end
    return summary
end

--- Prints the current session compared with the last archived one.
function Sessions:PrintCurrent()
    local _, _, level = ns.Tracker:GetSnapshot()
    local summary = self:Summarize(ns.Tracker:GetSession(), level or ns.char.level, true)
    ns:Print(ns.L["SESSION_CURRENT"] .. " " .. self:Format(summary, self:GetLast()))
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Sessions:OnLogin()
    local previous = ns.Tracker.previousSession
    ns.Tracker.previousSession = nil
    local summary = previous and self:Archive(previous)
    if summary and ns.settings.sessionSummary and summary.xp > 0 then
        local sessions = ns.char.sessions
        -- Printed once the login chat burst is over.
        C_Timer.After(6, function()
            ns:Print(ns.L["SESSION_LAST"] .. " " .. self:Format(summary, sessions[#sessions - 1]))
        end)
    end
end
