--[[----------------------------------------------------------------------------
    XPLedger - History
    Persists the leveling history of each character:

      levels[n] = {
          startedAt, endedAt       epoch seconds (real time), may be nil
          playedStart, playedEnd   /played totals at the start and end of the level
          partial                  true when tracking started mid-level, so the
                                   xp/source figures do not cover the whole level
          xp, kills, quests, rested
          sources  = { [source]  = xp },
          contexts = { [context] = xp },
      }

    /played reports the time spent on the current level, so the played time of
    a level is exact even when the addon was installed mid-level.

    It also records "samples" (level + fraction over time) used by the graphs.
------------------------------------------------------------------------------]]

local _, ns = ...

local History = ns:NewModule("History")

local SAMPLE_INTERVAL = 60      -- at most one sample per minute
local MAX_SAMPLES = 3000
local PLAYED_TIMEOUT = 5        -- seconds to wait for TIME_PLAYED_MSG
local DING_SUMMARY_DELAY = 1.5  -- lets the last gains of the level be committed
local RECENT_LEVELS = 5          -- levels averaged by the recent pace

local suppressedChatFrames = {}
local playedRequestPending = false

--------------------------------------------------------------------------------
-- Level records
--------------------------------------------------------------------------------

--- Returns the record of a level of the logged character, creating it if needed.
function History:EnsureLevel(level, partial)
    local levels = ns.char.levels
    local record = levels[level]
    if not record then
        record = {
            startedAt = time(),
            partial = partial or false,
            xp = 0,
            kills = 0,
            quests = 0,
            rested = 0,
            sources = {},
            contexts = {},
        }
        levels[level] = record
    end
    return record
end

local function AddTo(map, key, amount)
    map[key] = (map[key] or 0) + amount
end

function History:OnExperienceGained(gain)
    local record = self:EnsureLevel(gain.level, true)
    local totals = ns.char.totals

    record.xp = record.xp + gain.amount
    record.rested = record.rested + (gain.rested or 0)
    AddTo(record.sources, gain.source, gain.amount)
    AddTo(record.contexts, gain.context, gain.amount)

    totals.xp = totals.xp + gain.amount
    AddTo(totals.sources, gain.source, gain.amount)
    AddTo(totals.contexts, gain.context, gain.amount)

    if gain.source == "mob" then
        record.kills = record.kills + 1
        totals.kills = totals.kills + 1
    elseif gain.source == "quest" then
        record.quests = record.quests + 1
        totals.quests = totals.quests + 1
    end

    self:AddSample()
end

function History:OnLevelUp(oldLevel, newLevel)
    local now = time()
    local finished = self:EnsureLevel(oldLevel, true)
    finished.endedAt = now
    finished.playedEnd = self:GetPlayedNow() or finished.playedEnd

    local started = self:EnsureLevel(newLevel, false)
    started.startedAt = now
    started.partial = false
    started.playedStart = finished.playedEnd

    ns.char.level = newLevel
    self:AddSample()

    -- Refine the played values with the exact figures from the server.
    C_Timer.After(1, function() self:RequestPlayed() end)

    if ns.settings.dingSummary then
        C_Timer.After(DING_SUMMARY_DELAY, function() self:PrintLevelSummary(oldLevel, newLevel) end)
    end
end

--------------------------------------------------------------------------------
-- Played time
--------------------------------------------------------------------------------

local function RestoreChatFrames()
    for i = 1, #suppressedChatFrames do
        pcall(suppressedChatFrames[i].RegisterEvent, suppressedChatFrames[i], "TIME_PLAYED_MSG")
    end
    wipe(suppressedChatFrames)
end

--- Asks the server for /played. When the silent option is on, chat frames stop
--- listening to the reply until it arrives so nothing is printed.
function History:RequestPlayed()
    if playedRequestPending or not RequestTimePlayed then
        return
    end
    playedRequestPending = true

    if ns.settings.silentPlayed then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local frame = _G["ChatFrame" .. i]
            if frame and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
                if pcall(frame.UnregisterEvent, frame, "TIME_PLAYED_MSG") then
                    suppressedChatFrames[#suppressedChatFrames + 1] = frame
                end
            end
        end
    end

    RequestTimePlayed()

    C_Timer.After(PLAYED_TIMEOUT, function()
        playedRequestPending = false
        RestoreChatFrames()
    end)
end

function History:OnTimePlayed(totalPlayed, levelPlayed)
    playedRequestPending = false
    -- Restore on the next frame so the chat frames skip this reply.
    C_Timer.After(0, RestoreChatFrames)

    totalPlayed = ns.SafeNumber(totalPlayed)
    levelPlayed = ns.SafeNumber(levelPlayed)
    if not totalPlayed or not levelPlayed then
        return
    end

    local char = ns.char
    char.played = totalPlayed
    char.playedAt = time()
    self.playedReadAt = GetTime()

    local _, _, level = ns.Tracker:GetSnapshot()
    level = level or char.level
    if not level then
        return
    end
    local record = self:EnsureLevel(level, true)
    record.playedStart = totalPlayed - levelPlayed

    -- The previous level ended exactly when this one started.
    local previous = char.levels[level - 1]
    if previous and previous.endedAt then
        previous.playedEnd = record.playedStart
    end
    ns:SendMessage("XPL_STATE_CHANGED")
end

--- Returns the current /played total, extrapolated since the last reading.
--- Nil until /played has been read during this login.
function History:GetPlayedNow()
    if not self.playedReadAt or not ns.char.played then
        return nil
    end
    return ns.char.played + (GetTime() - self.playedReadAt)
end

--- Returns the played seconds spent on a level of a character record, or nil.
--- The in-progress level of the logged character is extrapolated live.
function History:GetLevelPlayed(record, level)
    local entry = record.levels and record.levels[level]
    if not entry or not entry.playedStart then
        return nil
    end
    if entry.playedEnd then
        return math.max(0, entry.playedEnd - entry.playedStart)
    end
    if record == ns.char and level == record.level then
        local now = self:GetPlayedNow()
        return now and math.max(0, now - entry.playedStart)
    end
    return nil
end

--- Returns aggregated leveling statistics of a character record.
function History:GetCharacterStats(record)
    local stats = { levels = {}, completed = 0, totalPlayed = 0 }
    for level in pairs(record.levels or {}) do
        stats.levels[#stats.levels + 1] = level
    end
    table.sort(stats.levels)

    for i = 1, #stats.levels do
        local level = stats.levels[i]
        local entry = record.levels[level]
        local played = self:GetLevelPlayed(record, level)
        if played and entry.playedEnd then
            stats.completed = stats.completed + 1
            stats.totalPlayed = stats.totalPlayed + played
            if not stats.fastest or played < stats.fastest.played then
                stats.fastest = { level = level, played = played }
            end
            if not stats.slowest or played > stats.slowest.played then
                stats.slowest = { level = level, played = played }
            end
        end
    end
    if stats.completed > 0 then
        stats.average = stats.totalPlayed / stats.completed
    end
    return stats
end

--- Recent pace of a record: the last completed level ({ level, played }),
--- the average played of the levels before it and the average of the last
--- `count` completed levels (5 by default). Any of them may be nil.
function History:GetRecentPace(record, count)
    count = count or RECENT_LEVELS
    local levels = {}
    for level in pairs(record.levels or {}) do
        levels[#levels + 1] = level
    end
    table.sort(levels)

    local completed = {}
    for _, level in ipairs(levels) do
        local entry = record.levels[level]
        local played = entry.playedEnd and self:GetLevelPlayed(record, level)
        if played then
            completed[#completed + 1] = { level = level, played = played }
        end
    end
    local last = completed[#completed]
    local sum, previousCount = 0, 0
    for i = #completed - 1, math.max(1, #completed - count), -1 do
        sum, previousCount = sum + completed[i].played, previousCount + 1
    end
    local recentSum, recentCount = 0, 0
    for i = #completed, math.max(1, #completed - count + 1), -1 do
        recentSum, recentCount = recentSum + completed[i].played, recentCount + 1
    end
    return last, previousCount > 0 and sum / previousCount or nil,
        recentCount > 0 and recentSum / recentCount or nil
end

--------------------------------------------------------------------------------
-- Samples (progress over time)
--------------------------------------------------------------------------------

--- Thins the oldest half of the samples by dropping every other point.
local function CompactSamples(samples)
    local t, v = samples.t, samples.v
    local half = math.floor(#t / 2)
    local newT, newV = {}, {}
    for i = 1, #t do
        if i > half or i % 2 == 1 then
            newT[#newT + 1] = t[i]
            newV[#newV + 1] = v[i]
        end
    end
    samples.t, samples.v = newT, newV
end

--- Records the current progress (level + fraction). Keeps at most one point
--- per SAMPLE_INTERVAL by moving the newest point while inside the interval.
function History:AddSample()
    local xp, maxXP, level = ns.Tracker:GetSnapshot()
    if not xp or not maxXP or not level or maxXP <= 0 then
        return
    end
    local samples = ns.char.samples
    local t, v = samples.t, samples.v
    local now = time()
    local value = level + xp / maxXP
    local count = #t

    if count >= 2 and now - t[count - 1] < SAMPLE_INTERVAL then
        t[count], v[count] = now, value
    else
        t[count + 1], v[count + 1] = now, value
    end
    if #samples.t > MAX_SAMPLES then
        CompactSamples(samples)
    end
end

--------------------------------------------------------------------------------
-- Level up summary
--------------------------------------------------------------------------------

local function TopEntry(map)
    local bestKey, bestValue, total = nil, 0, 0
    for key, value in pairs(map or {}) do
        total = total + value
        if value > bestValue then
            bestKey, bestValue = key, value
        end
    end
    return bestKey, bestValue, total
end

--- Returns the source that gave the most experience on a level entry and its
--- share of the level (0-1), or nil when nothing was recorded.
function History:GetTopSource(entry)
    local source, amount, total = TopEntry(entry and entry.sources)
    if source and total > 0 then
        return source, amount / total
    end
    return nil
end

function History:PrintLevelSummary(oldLevel, newLevel)
    local L = ns.L
    local record = ns.char.levels[oldLevel]
    if not record then
        return
    end
    local played = self:GetLevelPlayed(ns.char, oldLevel)
    local realTime = (not record.partial and record.startedAt and record.endedAt)
        and (record.endedAt - record.startedAt) or nil
    ns:Print(L["DING_SUMMARY"], newLevel, ns.FormatDuration(played), ns.FormatDuration(realTime))

    local source, share = self:GetTopSource(record)
    local context = TopEntry(record.contexts)
    if source then
        ns:Print(L["DING_MAIN_SOURCE"], L["SOURCE_" .. source], math.floor(share * 100 + 0.5),
            L["CONTEXT_" .. (context or "world")])
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function History:OnLogin()
    local _, _, level = ns.Tracker:GetSnapshot()
    if level then
        local xp = ns.Tracker:GetSnapshot()
        self:EnsureLevel(level, (xp or 0) > 0)
        self:AddSample()
    end

    ns:RegisterMessage("XPL_XP_GAINED", function(_, gain) self:OnExperienceGained(gain) end)
    ns:RegisterMessage("XPL_LEVEL_UP", function(_, oldLevel, newLevel) self:OnLevelUp(oldLevel, newLevel) end)
    ns:RegisterMessage("XPL_LEVEL_CHANGED", function(_, _, newLevel)
        ns.char.level = newLevel
        self:EnsureLevel(newLevel, true)
    end)
    ns:RegisterMessage("XPL_DATA_RESET", function(_, key)
        if key == ns.charKey then
            local xp, _, current = ns.Tracker:GetSnapshot()
            if current then
                self:EnsureLevel(current, (xp or 0) > 0)
            end
        end
    end)

    ns:RegisterEvent("TIME_PLAYED_MSG", function(_, total, thisLevel) self:OnTimePlayed(total, thisLevel) end)
    ns:RegisterEvent("PLAYER_LOGOUT", function()
        ns.char.lastSeen = time()
        local played = self:GetPlayedNow()
        if played then
            ns.char.played = played
            ns.char.playedAt = time()
        end
        self:AddSample()
    end)

    -- Read /played once the login burst is over (other addons request it too).
    C_Timer.After(4, function() self:RequestPlayed() end)
end
