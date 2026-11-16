--[[----------------------------------------------------------------------------
    XPLedger - Instance runs
    Records every dungeon, delve or scenario run with the experience it gave.

    A run starts when the character enters a party or scenario instance and
    ends when it leaves. Coming back to the same instance within the grace
    period (a corpse run, a quick trip to a vendor) continues the same run,
    unless it is a new run of the same instance:
      - the instance was reset (system message, INSTANCE_RESET_SUCCESS);
      - the run was completed (LFG_COMPLETION_REWARD, SCENARIO_COMPLETED);
      - the creatures belong to another copy of the instance. The copy is
        read from creature GUIDs (Creature-0-<server>-<map>-<copy>-...): after
        a re-entry the run goes on provisionally, counting what is gained in
        `resume`, until a creature tells whether the copy is the same. If it
        is not, the run is closed when it was left and a new one starts with
        what was gained since the re-entry.

    Stored in the character record:
      activeRun                 the run in progress (survives a /reload)
      runs = { <run>, ... }     finished runs, oldest first
      <run> = { instanceID, name, kind, difficulty, level, startedAt,
                endedAt, leftAt, xp, kills, quests,
                copy, completed, pausedAt, resume = { at, xp, kills, quests } }
------------------------------------------------------------------------------]]

local _, ns = ...

local Runs = ns:NewModule("Runs")

local REENTRY_GRACE = 600   -- seconds outside that still continue the run
local MAX_RUNS = 200
local MIN_DURATION = 60     -- shorter runs without experience are discarded

Runs.KINDS = { party = "dungeon", scenario = "scenario" }

local closeScheduled = false  -- a timer will re-check the run after the grace period
local resetPattern

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
    run.leftAt, run.pausedAt, run.resume = nil, nil, nil
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
    -- Runs at the level cap give no experience and are not recorded.
    local tracked = info and Runs.KINDS[info.instanceType] and not ns.Compat.IsAtMaxLevel()

    if run and run.leftAt and now - run.leftAt > REENTRY_GRACE then
        self:Finish()
        run = nil
    end

    if tracked then
        if run and run.instanceID == info.instanceID and not run.completed then
            if run.leftAt then
                -- Back in: the same run unless the creatures say otherwise.
                run.pausedAt = run.leftAt
                run.resume = { at = now, xp = 0, kills = 0, quests = 0 }
                run.leftAt = nil
            end
        else
            self:Finish()
            StartRun(info)
        end
    elseif run then
        run.leftAt = run.leftAt or now
        -- Close it once the grace period is over, even if nothing else happens.
        if not closeScheduled then
            closeScheduled = true
            C_Timer.After(math.max(1, REENTRY_GRACE - (now - run.leftAt) + 1), function()
                closeScheduled = false
                self:Update()
            end)
        end
    end
    ns:SendMessage("XPL_STATE_CHANGED")
end

local function Count(target, gain)
    target.xp = target.xp + gain.amount
    if gain.source == "mob" then
        target.kills = target.kills + 1
    elseif gain.source == "quest" then
        target.quests = target.quests + 1
    end
end

function Runs:OnExperienceGained(gain)
    local run = ns.char.activeRun
    if not run or run.leftAt then
        return
    end
    Count(run, gain)
    if run.resume then
        Count(run.resume, gain)
    end
end

--------------------------------------------------------------------------------
-- New runs of the same instance
--------------------------------------------------------------------------------

--- Copy of the instance a creature GUID belongs to, or nil.
function Runs.ParseCopy(guid)
    guid = ns.SafeString(guid)
    if not guid then
        return nil
    end
    local kind, server, map, copy = guid:match("^(%a+)%-%d+%-(%d+)%-(%d+)%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then
        return nil
    end
    return ("%s-%s-%s"):format(server, map, copy)
end

--- Splits the active run: the part before the re-entry is finished when the
--- instance was left, the part after it becomes a new run.
function Runs:SplitAtResume(copy)
    local run = ns.char.activeRun
    local resume = run.resume
    run.xp = run.xp - resume.xp
    run.kills = run.kills - resume.kills
    run.quests = run.quests - resume.quests
    run.leftAt = run.pausedAt
    self:Finish()

    local info = ns.Compat.GetInstanceInfo()
    local new = StartRun(info or { instanceID = run.instanceID, name = run.name })
    new.kind = new.kind or run.kind
    new.startedAt = resume.at
    new.xp, new.kills, new.quests = resume.xp, resume.kills, resume.quests
    new.copy = copy
    ns:SendMessage("XPL_STATE_CHANGED")
end

--- Learns the instance copy from a unit of the run.
function Runs:OnUnitSeen(unit)
    local run = ns.char.activeRun
    if not run or run.leftAt or (run.copy and not run.resume) then
        return
    end
    local copy = Runs.ParseCopy(UnitGUID(unit))
    if not copy then
        return
    end
    if not run.copy then
        run.copy = copy
        run.resume, run.pausedAt = nil, nil
    elseif copy == run.copy then
        run.resume, run.pausedAt = nil, nil
    else
        self:SplitAtResume(copy)
    end
end

--- The instance was reset: a paused run of it is over.
function Runs:OnSystemMessage(text)
    text = ns.SafeString(text)
    local run = ns.char.activeRun
    if not text or not resetPattern or not run or not run.leftAt then
        return
    end
    -- A reset clears every instance of the character (or of the party), so
    -- whatever the name in the message, the paused run is over.
    if text:match(resetPattern) then
        self:Finish()
        ns:SendMessage("XPL_STATE_CHANGED")
    end
end

function Runs:OnCompleted()
    local run = ns.char.activeRun
    if run and not run.leftAt then
        run.completed = true
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
    -- Logging out counts as leaving: the offline time must not extend the run.
    ns:RegisterEvent("PLAYER_LOGOUT", function()
        local run = ns.char.activeRun
        if run and not run.leftAt then
            run.leftAt = time()
        end
    end)

    if type(_G.INSTANCE_RESET_SUCCESS) == "string" then
        resetPattern = ns.FormatToPattern(_G.INSTANCE_RESET_SUCCESS)
    end
    ns:RegisterEvent("CHAT_MSG_SYSTEM", function(_, text) self:OnSystemMessage(text) end)
    ns:RegisterEvent("LFG_COMPLETION_REWARD", function() self:OnCompleted() end)
    ns:RegisterEvent("SCENARIO_COMPLETED", function() self:OnCompleted() end)
    ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() self:OnUnitSeen("target") end)
    ns:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() self:OnUnitSeen("mouseover") end)
    ns:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) self:OnUnitSeen(unit) end)

    ns:RegisterMessage("XPL_XP_GAINED", function(_, gain) self:OnExperienceGained(gain) end)
    ns:RegisterMessage("XPL_DATA_RESET", function(_, key)
        if key == ns.charKey then
            ns.char.activeRun = nil
        end
    end)
    Update()
end
