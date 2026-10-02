--[[----------------------------------------------------------------------------
    XPLedger - Tracker
    Turns PLAYER_XP_UPDATE snapshots into individual experience gains and
    computes the experience rate and the time left to level up.

    Flow of a gain:
      1. PLAYER_XP_UPDATE  -> the delta against the previous snapshot is
         computed (level rollovers are split per level) and queued.
      2. After a short delay the Sources module classifies the queued gain
         using the hints collected around it (kill message, quest turn-in...).
      3. The gain is committed to the session and broadcast as XPL_XP_GAINED
         so History and the UI can consume it.

    Session record (persisted in the character record so it survives /reload):
      startedAt, lastUpdate, lastGainAt   epoch seconds
      xp, kills, quests                   totals of the session
      activeTime                          seconds counted as playing (idle gaps clipped)
      gains = { t = {}, a = {} }          timeline of gains (epoch seconds, amount)
      sources, contexts                   xp per source / activity bucket
      recentKills, recentQuests           last amounts, for "kills to level"
------------------------------------------------------------------------------]]

local _, ns = ...

local Tracker = ns:NewModule("Tracker")
local Compat = ns.Compat

-- A session survives a /reload or a quick relog if it was updated this recently.
local SESSION_RESUME_SECONDS = 180
-- Minimum active time before a rate is considered meaningful.
local MIN_ACTIVE_SECONDS = 45
-- Hard caps that keep the saved variables small.
local MAX_SESSION_GAINS = 4000
local MAX_RECENT_AMOUNTS = 25
-- Level jumps larger than this are treated as a boost, not as earned experience.
local MAX_NATURAL_LEVEL_JUMP = 3
-- Delay that lets source hints (chat messages, quest events) arrive.
local CLASSIFY_DELAY = 0.5

local snapshot = {}      -- last known xp, maxXP, level and rested pool
local pendingGains = {}  -- gains waiting for classification
local pendingLevel       -- level announced by PLAYER_LEVEL_UP, before UnitLevel updates

--------------------------------------------------------------------------------
-- Session management
--------------------------------------------------------------------------------

local function NewSession(now)
    return {
        startedAt = now,
        lastUpdate = now,
        lastGainAt = now,
        xp = 0,
        kills = 0,
        quests = 0,
        activeTime = 0,
        gains = { t = {}, a = {} },
        sources = {},
        contexts = {},
        recentKills = {},
        recentQuests = {},
    }
end

--- Binds the session stored in the character record, starting a new one when
--- the stored session is stale (a real logout rather than a /reload).
function Tracker:BindSession()
    local now = time()
    local session = ns.char.session
    if type(session) ~= "table" or not session.startedAt
        or now - (session.lastUpdate or 0) > SESSION_RESUME_SECONDS then
        session = NewSession(now)
        ns.char.session = session
    end
    self.session = session
end

--- Returns the active session table.
function Tracker:GetSession()
    return self.session
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Tracker:OnLogin()
    self:BindSession()
    self:TakeSnapshot()

    ns:RegisterEvent("PLAYER_XP_UPDATE", function(_, unit)
        if unit == nil or unit == "player" then
            self:OnExperienceChanged()
        end
    end)
    ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, newLevel)
        pendingLevel = ns.SafeNumber(newLevel)
        -- UnitLevel may still report the old level inside this event.
        C_Timer.After(0.2, function() self:OnExperienceChanged() end)
    end)
    ns:RegisterEvent("UPDATE_EXHAUSTION", function()
        snapshot.rested = Compat.GetRestedExperience()
        ns:SendMessage("XPL_STATE_CHANGED")
    end)
    ns:RegisterEvent("PLAYER_UPDATE_RESTING", function()
        ns:SendMessage("XPL_STATE_CHANGED")
    end)
    ns:RegisterEvent("ENABLE_XP_GAIN", function() ns:SendMessage("XPL_STATE_CHANGED") end)
    ns:RegisterEvent("DISABLE_XP_GAIN", function() ns:SendMessage("XPL_STATE_CHANGED") end)
    -- Combat restrictions may hide values temporarily; resync when they end.
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if not snapshot.xp then
            self:TakeSnapshot()
        end
    end)

    ns:RegisterMessage("XPL_DATA_RESET", function(_, key)
        if key == ns.charKey then
            self:BindSession()
            self:TakeSnapshot()
        end
    end)

    -- Heartbeat: refreshes time based displays and keeps the session alive.
    local elapsed = 0
    C_Timer.NewTicker(1, function()
        elapsed = elapsed + 1
        if elapsed % 10 == 0 then
            self.session.lastUpdate = time()
        end
        ns:SendMessage("XPL_TICK")
    end)
end

--------------------------------------------------------------------------------
-- Gain detection
--------------------------------------------------------------------------------

--- Stores the current experience values as the comparison baseline.
function Tracker:TakeSnapshot()
    local xp, maxXP, level = Compat.GetPlayerExperience()
    snapshot.xp, snapshot.maxXP, snapshot.level = xp, maxXP, level
    snapshot.rested = Compat.GetRestedExperience()
end

--- Returns the last known experience values: xp, maxXP, level.
function Tracker:GetSnapshot()
    return snapshot.xp, snapshot.maxXP, snapshot.level
end

local function QueueGain(amount, level, restedUsed)
    local gain = {
        amount = amount,
        level = level,
        time = time(),
        clock = GetTime(),
        rested = restedUsed or 0,
        context = Compat.GetActivityContext(),
        inCombat = Compat.InCombat(),
        inPetBattle = Compat.InPetBattle(),
    }
    pendingGains[#pendingGains + 1] = gain
    C_Timer.After(CLASSIFY_DELAY, function() Tracker:FlushPendingGains() end)
end

--- Handles a change of the player's experience or level.
function Tracker:OnExperienceChanged()
    local xp, maxXP, level = Compat.GetPlayerExperience()
    if not xp or not maxXP or not level then
        return -- secret values: keep the old snapshot and retry on the next update
    end
    if pendingLevel and pendingLevel > level and xp < (snapshot.xp or 0) then
        level = pendingLevel -- the xp bar already rolled over but UnitLevel lags
    end

    local oldXP, oldMax, oldLevel = snapshot.xp, snapshot.maxXP, snapshot.level
    local rested = Compat.GetRestedExperience()
    local restedUsed = math.max(0, (snapshot.rested or rested) - rested)

    if not oldXP or not oldLevel then
        self:TakeSnapshot()
        return
    end

    if level == oldLevel then
        local delta = xp - oldXP
        if delta > 0 then
            QueueGain(delta, level, restedUsed)
        end
    elseif level > oldLevel and level - oldLevel <= MAX_NATURAL_LEVEL_JUMP then
        -- Split the gain: the rest of the old level, then the new level progress.
        local remainder = math.max(0, (oldMax or 0) - oldXP)
        if remainder > 0 then
            QueueGain(remainder, oldLevel, restedUsed)
        end
        for reached = oldLevel + 1, level do
            ns:SendMessage("XPL_LEVEL_UP", reached - 1, reached)
        end
        if xp > 0 then
            QueueGain(xp, level, 0)
        end
    elseif level ~= oldLevel then
        -- Boosts, level squishes or any jump we cannot explain: just resync.
        ns:SendMessage("XPL_LEVEL_CHANGED", oldLevel, level)
    end

    if level >= (pendingLevel or 0) then
        pendingLevel = nil
    end
    snapshot.xp, snapshot.maxXP, snapshot.level, snapshot.rested = xp, maxXP, level, rested
    ns:SendMessage("XPL_STATE_CHANGED")
end

--- Classifies and commits the gains whose hint window has elapsed.
function Tracker:FlushPendingGains()
    local now = GetTime()
    local remaining = {}
    for i = 1, #pendingGains do
        local gain = pendingGains[i]
        if now - gain.clock >= CLASSIFY_DELAY - 0.05 then
            if ns.Sources then
                ns.Sources:Classify(gain)
            end
            gain.source = gain.source or "other"
            self:CommitGain(gain)
        else
            remaining[#remaining + 1] = gain
        end
    end
    pendingGains = remaining
end

local function PushCapped(list, value, cap)
    list[#list + 1] = value
    if #list > cap then
        table.remove(list, 1)
    end
end

--- Adds a classified gain to the session and broadcasts it.
function Tracker:CommitGain(gain)
    local session = self.session
    local afkSeconds = ns.settings.afkThreshold * 60
    local gap = gain.time - (session.lastGainAt or session.startedAt)

    session.activeTime = session.activeTime + ns.Clamp(gap, 0, afkSeconds)
    session.lastGainAt = gain.time
    session.xp = session.xp + gain.amount
    session.sources[gain.source] = (session.sources[gain.source] or 0) + gain.amount
    session.contexts[gain.context] = (session.contexts[gain.context] or 0) + gain.amount

    if gain.source == "mob" then
        session.kills = session.kills + 1
        PushCapped(session.recentKills, gain.amount, MAX_RECENT_AMOUNTS)
    elseif gain.source == "quest" then
        session.quests = session.quests + 1
        PushCapped(session.recentQuests, gain.amount, MAX_RECENT_AMOUNTS)
    end

    local timeline = session.gains
    timeline.t[#timeline.t + 1] = gain.time
    timeline.a[#timeline.a + 1] = gain.amount
    if #timeline.t > MAX_SESSION_GAINS then
        -- Drop the oldest quarter in one pass instead of shifting on every gain.
        local drop = math.floor(MAX_SESSION_GAINS / 4)
        local t, a = {}, {}
        for i = drop + 1, #timeline.t do
            t[#t + 1] = timeline.t[i]
            a[#a + 1] = timeline.a[i]
        end
        timeline.t, timeline.a = t, a
    end

    ns:SendMessage("XPL_XP_GAINED", gain)
end

--------------------------------------------------------------------------------
-- Rate and estimates
--------------------------------------------------------------------------------

--- Computes the XP/hour over the last `windowSeconds` of the session.
--- Idle gaps longer than the AFK threshold only count up to the threshold.
--- @return number|nil rate, number activeSeconds, number xp
function Tracker:GetWindowRate(windowSeconds)
    local session = self.session
    local now = time()
    local afkSeconds = ns.settings.afkThreshold * 60
    local windowStart = math.max(now - windowSeconds, session.startedAt)
    local t, a = session.gains.t, session.gains.a

    local first = #t + 1
    while first > 1 and t[first - 1] >= windowStart do
        first = first - 1
    end

    local xp, active, previous = 0, 0, windowStart
    for i = first, #t do
        xp = xp + a[i]
        active = active + ns.Clamp(t[i] - previous, 0, afkSeconds)
        previous = t[i]
    end
    active = active + ns.Clamp(now - previous, 0, afkSeconds)

    if xp <= 0 or active < MIN_ACTIVE_SECONDS then
        return nil, active, xp
    end
    return xp / active * 3600, active, xp
end

--- Computes the XP/hour over the whole session.
function Tracker:GetSessionRate()
    local session = self.session
    local afkSeconds = ns.settings.afkThreshold * 60
    local active = session.activeTime + ns.Clamp(time() - (session.lastGainAt or session.startedAt), 0, afkSeconds)
    if session.xp <= 0 or active < MIN_ACTIVE_SECONDS then
        return nil, active
    end
    return session.xp / active * 3600, active
end

local function Average(list)
    if #list == 0 then
        return nil
    end
    local sum = 0
    for i = 1, #list do
        sum = sum + list[i]
    end
    return sum / #list
end

--- Returns a snapshot of everything the UI needs to display.
function Tracker:GetEstimate()
    local session = self.session
    local xp, maxXP, level = self:GetSnapshot()
    local estimate = {
        level = level or ns.SafeNumber(UnitLevel("player")) or 0,
        xp = xp or 0,
        maxXP = maxXP or 0,
        rested = Compat.GetRestedExperience(),
        maxLevel = Compat.GetMaxLevel(),
        blocked = Compat.IsExperienceBlocked(),
        disabled = Compat.IsExperienceDisabledByUser(),
        sessionXP = session.xp,
        sessionTime = time() - session.startedAt,
        windowMinutes = ns.settings.rateWindow,
    }
    estimate.remaining = math.max(0, estimate.maxXP - estimate.xp)
    estimate.progress = estimate.maxXP > 0 and estimate.xp / estimate.maxXP or 0
    estimate.atMaxLevel = estimate.level >= estimate.maxLevel

    estimate.rate = self:GetWindowRate(ns.settings.rateWindow * 60)
    estimate.sessionRate = self:GetSessionRate()
    estimate.idle = time() - (session.lastGainAt or session.startedAt) > ns.settings.afkThreshold * 60

    -- Prefer the rolling rate; fall back to the session average.
    local rate = estimate.rate or estimate.sessionRate
    if rate and rate > 0 and not estimate.blocked then
        estimate.eta = estimate.remaining / rate * 3600
    end

    local averageKill = Average(session.recentKills)
    local averageQuest = Average(session.recentQuests)
    if averageKill and averageKill > 0 then
        estimate.killsToLevel = math.ceil(estimate.remaining / averageKill)
    end
    if averageQuest and averageQuest > 0 then
        estimate.questsToLevel = math.ceil(estimate.remaining / averageQuest)
    end
    return estimate
end
