--[[----------------------------------------------------------------------------
    XPLedger - Records
    Account-wide personal bests, announced when they are beaten, plus a
    milestone message every 10 levels.

    XPLedgerDB.records = {
        levels      = { [level] = { value = played, key, at } },  fastest level
        sessionRate = { value, key, at }    best XP/hour of a session
        bestHour    = { value, key, at }    most XP gained in 60 minutes
        biggestGain = { value, key, at }    largest single gain
        bestRun     = { value, key, at, name }  best run by XP/hour
    }
    `key` is the character that holds the record.
------------------------------------------------------------------------------]]

local _, ns = ...

local Records = ns:NewModule("Records")

-- Order and locale keys of the global records, also used by the UI.
Records.KINDS = { "sessionRate", "bestHour", "biggestGain", "bestRun" }

local MIN_SESSION_ACTIVE = 1800  -- seconds of play before a session rate counts
local HOUR = 3600
local MIN_RUN_DURATION = 300
local CHECK_THROTTLE = 30
local LEVEL_CHECK_DELAY = 6      -- waits for the refined /played after a ding
local MILESTONE_STEP = 10

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Store()
    local records = ns.db.records
    records.levels = records.levels or {}
    return records
end

--- Saves `value` as the record of `kind` when it beats the current one.
--- Lower is better when `lowerIsBetter` is set. Returns the previous record
--- when it was beaten (nil when it is the first value).
local function Submit(container, kind, value, lowerIsBetter, extra)
    local current = container[kind]
    local better = not current
        or (lowerIsBetter and value < current.value)
        or (not lowerIsBetter and value > current.value)
    if not better then
        return false
    end
    local entry = { value = value, key = ns.charKey, at = time() }
    for field, data in pairs(extra or {}) do
        entry[field] = data
    end
    container[kind] = entry
    return true, current
end

--- Announces a beaten record. First values are stored silently.
local function Announce(previous, message)
    if previous and ns.Goals then
        ns.Goals:Alert("records", message)
    end
end

--------------------------------------------------------------------------------
-- Checks
--------------------------------------------------------------------------------

function Records:CheckLevel(level)
    local entry = ns.char.levels[level]
    if not entry or entry.partial or not entry.playedEnd then
        return
    end
    local played = ns.History:GetLevelPlayed(ns.char, level)
    if not played or played <= 0 then
        return
    end
    local beaten, previous = Submit(Store().levels, level, played, true)
    if beaten then
        Announce(previous, ns.L["RECORD_LEVEL"]:format(level, ns.FormatDuration(played),
            ns.FormatDuration(previous and previous.value)))
    end
end

function Records:CheckSession()
    local L = ns.L
    local records = Store()
    local tracker = ns.Tracker
    local session = tracker:GetSession()

    local rate, active = tracker:GetSessionRate()
    if rate and active >= MIN_SESSION_ACTIVE then
        local beaten, previous = Submit(records, "sessionRate", rate)
        -- Announce once per session; later improvements are stored quietly.
        if beaten and not session.rateRecordAnnounced then
            session.rateRecordAnnounced = true
            Announce(previous, L["RECORD_SESSION_RATE"]:format(ns.FormatNumber(rate),
                ns.FormatNumber(previous and previous.value)))
        end
    end

    if time() - session.startedAt >= HOUR then
        local _, _, xp = tracker:GetWindowRate(HOUR)
        if xp and xp > 0 then
            local beaten, previous = Submit(records, "bestHour", xp)
            if beaten and not session.hourRecordAnnounced then
                session.hourRecordAnnounced = true
                Announce(previous, L["RECORD_BEST_HOUR"]:format(ns.FormatInteger(xp),
                    ns.FormatInteger(previous and previous.value)))
            end
        end
    end
end

function Records:CheckGain(gain)
    -- Rewards grow with the level, so this one is kept without announcing it.
    Submit(Store(), "biggestGain", gain.amount)
    local now = GetTime()
    if not self.lastCheck or now - self.lastCheck >= CHECK_THROTTLE then
        self.lastCheck = now
        self:CheckSession()
    end
end

function Records:CheckRun(run)
    if ns.Runs:GetDuration(run) < MIN_RUN_DURATION then
        return
    end
    local rate = ns.Runs:GetRate(run)
    if not rate then
        return
    end
    local beaten, previous = Submit(Store(), "bestRun", rate, false, { name = run.name })
    if beaten then
        Announce(previous, ns.L["RECORD_RUN"]:format(run.name or "?", ns.FormatNumber(rate),
            ns.FormatNumber(previous and previous.value)))
    end
end

function Records:CheckMilestone(level)
    if level % MILESTONE_STEP ~= 0 or ns.settings.alerts.milestones == false then
        return
    end
    local played = ns.History:GetPlayedNow() or ns.char.played
    ns:Print(ns.L["MILESTONE"]:format(level, ns.FormatDuration(played)))
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

--- Returns the record table (read only use).
function Records:Get()
    return Store()
end

--- Fastest level records as an array of { level, value, key, at }, sorted by level.
function Records:GetLevelRecords()
    local list = {}
    for level, entry in pairs(Store().levels) do
        list[#list + 1] = { level = level, value = entry.value, key = entry.key, at = entry.at }
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list
end

--- Drops the records held by a character that was deleted or reset.
function Records:ForgetCharacter(key)
    local records = Store()
    for _, kind in ipairs(self.KINDS) do
        if records[kind] and records[kind].key == key then
            records[kind] = nil
        end
    end
    for level, entry in pairs(records.levels) do
        if entry.key == key then
            records.levels[level] = nil
        end
    end
end

--- Moves the records of a character to its new key (surname migration).
function Records:RenameCharacter(oldKey, newKey)
    local records = Store()
    for _, kind in ipairs(self.KINDS) do
        if records[kind] and records[kind].key == oldKey then
            records[kind].key = newKey
        end
    end
    for _, entry in pairs(records.levels) do
        if entry.key == oldKey then
            entry.key = newKey
        end
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Records:OnInitialize()
    ns.db.records = type(ns.db.records) == "table" and ns.db.records or {}
end

function Records:OnLogin()
    ns:RegisterMessage("XPL_XP_GAINED", function(_, gain) self:CheckGain(gain) end)
    ns:RegisterMessage("XPL_RUN_FINISHED", function(_, run) self:CheckRun(run) end)
    ns:RegisterMessage("XPL_LEVEL_UP", function(_, oldLevel, newLevel)
        C_Timer.After(LEVEL_CHECK_DELAY, function() self:CheckLevel(oldLevel) end)
        self:CheckMilestone(newLevel)
    end)
    ns:RegisterMessage("XPL_DATA_RESET", function(_, key) self:ForgetCharacter(key) end)
end
