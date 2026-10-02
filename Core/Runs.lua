--[[----------------------------------------------------------------------------
    XPLedger - Instance runs
    Records every dungeon, delve or scenario run with the experience it gave.

    A run starts when the character enters a party or scenario instance and
    ends when it leaves. Coming back to the same instance within the grace
    period (a corpse run, a quick trip to a vendor) continues the same run.

    Stored in the character record:
      activeRun                 the run in progress (survives a /reload)
      runs = { <run>, ... }     finished runs, oldest first
      <run> = { instanceID, name, kind, difficulty, level, startedAt,
                endedAt, leftAt, xp, kills, quests }
------------------------------------------------------------------------------]]

local _, ns = ...

local Runs = ns:NewModule("Runs")

local REENTRY_GRACE = 600   -- seconds outside that still continue the run
local MAX_RUNS = 200
local MIN_DURATION = 60     -- shorter runs without experience are discarded

Runs.KINDS = { party = "dungeon", scenario = "scenario" }

--------------------------------------------------------------------------------
-- Run lifecycle
--------------------------------------------------------------------------------

local function StartRun(info)
    local _, _, level = ns.Tracker:GetSnapshot()
    local run = {
        instanceID = info.instanceID,
        name = info.name,
        kind = Runs.KINDS[info.instanceType],
        difficulty = info.difficultyName,
        level = level or ns.char.level,
        startedAt = time(),
        xp = 0,
        kills = 0,
        quests = 0,
    }
    ns.char.activeRun = run
    return run
end

--- Closes the active run and keeps it when it is worth keeping.
function Runs:Finish()
    local run = ns.char.activeRun
    if not run then
        return
    end
    ns.char.activeRun = nil
    run.endedAt = run.leftAt or time()
    run.leftAt = nil
    if run.xp <= 0 and run.endedAt - run.startedAt < MIN_DURATION then
        return
    end

    local runs = ns.char.runs
    runs[#runs + 1] = run
    while #runs > MAX_RUNS do
        table.remove(runs, 1)
    end
    ns:SendMessage("XPL_RUN_FINISHED", run)
end

--- Starts, continues, pauses or finishes the active run after a zone change.
function Runs:Update()
    local now = time()
    local run = ns.char.activeRun
    local info = ns.Compat.GetInstanceInfo()
    local tracked = info and Runs.KINDS[info.instanceType]

    if run and run.leftAt and now - run.leftAt > REENTRY_GRACE then
        self:Finish()
        run = nil
    end

    if tracked then
        if run and run.instanceID == info.instanceID then
            run.leftAt = nil
        else
            self:Finish()
            StartRun(info)
        end
    elseif run and not run.leftAt then
        run.leftAt = now
        -- Close it once the grace period is over, even if nothing else happens.
        C_Timer.After(REENTRY_GRACE + 1, function() self:Update() end)
    end
    ns:SendMessage("XPL_STATE_CHANGED")
end

function Runs:OnExperienceGained(gain)
    local run = ns.char.activeRun
    if not run or run.leftAt then
        return
    end
    run.xp = run.xp + gain.amount
    if gain.source == "mob" then
        run.kills = run.kills + 1
    elseif gain.source == "quest" then
        run.quests = run.quests + 1
    end
end

--------------------------------------------------------------------------------
-- Statistics
--------------------------------------------------------------------------------

--- Duration of a run in seconds (live for the active one).
function Runs:GetDuration(run)
    return math.max(0, (run.endedAt or run.leftAt or time()) - run.startedAt)
end

--- XP/hour of a run, or nil when it is too short to say.
function Runs:GetRate(run)
    local duration = self:GetDuration(run)
    if run.xp <= 0 or duration < MIN_DURATION then
        return nil
    end
    return run.xp / duration * 3600
end

--- Aggregates the finished runs of a record. When `level` is given only the
--- runs started at that level or the previous one are counted, so the
--- averages match the current rewards.
function Runs:GetStats(record, level)
    local stats = { count = 0, xp = 0, duration = 0 }
    for _, run in ipairs(record.runs or {}) do
        if run.xp > 0 and (not level or (run.level and run.level >= level - 1 and run.level <= level)) then
            stats.count = stats.count + 1
            stats.xp = stats.xp + run.xp
            stats.duration = stats.duration + self:GetDuration(run)
            local rate = self:GetRate(run)
            if rate and (not stats.best or rate > stats.bestRate) then
                stats.best, stats.bestRate = run, rate
            end
        end
    end
    if stats.count > 0 then
        stats.averageXP = stats.xp / stats.count
        stats.averageDuration = stats.duration / stats.count
        if stats.duration > 0 then
            stats.rate = stats.xp / stats.duration * 3600
        end
    end
    return stats
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Runs:OnLogin()
    local function Update() self:Update() end
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", Update)
    ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", Update)
    ns:RegisterMessage("XPL_XP_GAINED", function(_, gain) self:OnExperienceGained(gain) end)
    ns:RegisterMessage("XPL_DATA_RESET", function(_, key)
        if key == ns.charKey then
            ns.char.activeRun = nil
        end
    end)
    Update()
end
