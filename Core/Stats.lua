--[[----------------------------------------------------------------------------
    XPLedger - Statistics
    Collects when, where and from what each character earns its experience,
    and aggregates every statistic shown by the Stats view, for one character
    or for the whole account.

    Stored in the character record (filled from this version on):
      stats = {
          weekday[1..7]  = { xp, active }      1 = Monday
          hour[0..23]    = { xp, active }
          days["YYYY-MM-DD"] = xp
          zones[name]    = { xp, kills, quests, active }
          mobs[name]     = { kills, xp }       only when the kill message is readable
          quests         = { { id, title, xp, level, at }, ... }   best rewards first
          biggestGain    = { amount, source, level, at }
          deaths, deathLevels[level]           deaths while leveling
      }
    `active` is playing time: the gap since the previous gain, clipped to the
    idle threshold (the same rule as the session rate).
------------------------------------------------------------------------------]]

local _, ns = ...

local Stats = ns:NewModule("Stats")

local MAX_DAYS = 400
local MAX_ZONES = 150
local MAX_MOBS = 300
local MAX_QUESTS = 15
local MIN_ZONE_ACTIVE = 600     -- seconds before a zone rate is meaningful
local MIN_SESSION_ACTIVE = 600
local NIGHT_END_HOUR = 6        -- 00:00 to 05:59 counts as night
local DAY = 86400

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

local function Store(record)
    local stats = record.stats
    if type(stats) ~= "table" then
        stats = {}
        record.stats = stats
    end
    stats.weekday = stats.weekday or {}
    stats.hour = stats.hour or {}
    stats.days = stats.days or {}
    stats.zones = stats.zones or {}
    stats.mobs = stats.mobs or {}
    stats.quests = stats.quests or {}
    stats.deathLevels = stats.deathLevels or {}
    stats.deaths = stats.deaths or 0
    return stats
end

local function Bucket(map, key, template)
    local bucket = map[key]
    if not bucket then
        bucket = {}
        for field in pairs(template) do
            bucket[field] = 0
        end
        map[key] = bucket
    end
    return bucket
end

--- Removes the entry with the lowest `field` once a map grows past `limit`.
local function Trim(map, limit, field)
    local count, lowestKey, lowest = 0, nil, math.huge
    for key, entry in pairs(map) do
        count = count + 1
        local value = type(entry) == "table" and entry[field] or entry
        if value < lowest then
            lowestKey, lowest = key, value
        end
    end
    if count > limit and lowestKey then
        map[lowestKey] = nil
    end
end

--- Monday-first weekday of an epoch time (1 = Monday ... 7 = Sunday).
local function Weekday(t)
    local day = tonumber(date("%w", t))
    return day == 0 and 7 or day
end

local function DayKey(t)
    return date("%Y-%m-%d", t)
end

--- Epoch time of the noon of a "YYYY-MM-DD" key (noon avoids DST edges).
local function DayTime(key)
    local year, month, day = key:match("^(%d+)-(%d+)-(%d+)$")
    if not year then
        return nil
    end
    return time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 })
end

local function QuestTitle(questID)
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    return ns.SafeString(title)
end

--------------------------------------------------------------------------------
-- Collection
--------------------------------------------------------------------------------

function Stats:OnExperienceGained(gain)
    local stats = Store(ns.char)
    local amount = gain.amount
    local active = 0
    if self.lastGainAt then
        active = ns.Clamp(gain.time - self.lastGainAt, 0, ns.settings.afkThreshold * 60)
    end
    self.lastGainAt = gain.time

    local weekday = Bucket(stats.weekday, Weekday(gain.time), { xp = true, active = true })
    weekday.xp, weekday.active = weekday.xp + amount, weekday.active + active
    local hour = Bucket(stats.hour, tonumber(date("%H", gain.time)), { xp = true, active = true })
    hour.xp, hour.active = hour.xp + amount, hour.active + active

    local dayKey = DayKey(gain.time)
    local isNewDay = stats.days[dayKey] == nil
    stats.days[dayKey] = (stats.days[dayKey] or 0) + amount
    if isNewDay then
        -- Keys sort chronologically, so the oldest day is the smallest key.
        local count, oldest = 0, nil
        for key in pairs(stats.days) do
            count = count + 1
            if not oldest or key < oldest then
                oldest = key
            end
        end
        if count > MAX_DAYS then
            stats.days[oldest] = nil
        end
    end

    if gain.zone and gain.zone ~= "" then
        local isNew = stats.zones[gain.zone] == nil
        local zone = Bucket(stats.zones, gain.zone, { xp = true, kills = true, quests = true, active = true })
        zone.xp, zone.active = zone.xp + amount, zone.active + active
        if gain.source == "mob" then
            zone.kills = zone.kills + 1
        elseif gain.source == "quest" then
            zone.quests = zone.quests + 1
        end
        if isNew then
            Trim(stats.zones, MAX_ZONES, "xp")
        end
    end

    if gain.source == "mob" and gain.mobName then
        local isNew = stats.mobs[gain.mobName] == nil
        local mob = Bucket(stats.mobs, gain.mobName, { kills = true, xp = true })
        mob.kills, mob.xp = mob.kills + 1, mob.xp + amount
        if isNew then
            Trim(stats.mobs, MAX_MOBS, "kills")
        end
    end

    if gain.source == "quest" and gain.questID then
        self:AddQuest(stats, gain)
    end

    if not stats.biggestGain or amount > stats.biggestGain.amount then
        stats.biggestGain = { amount = amount, source = gain.source, level = gain.level, at = gain.time }
    end
end

--- Keeps the best rewarded quests, one entry per quest.
function Stats:AddQuest(stats, gain)
    local quests = stats.quests
    for _, quest in ipairs(quests) do
        if quest.id == gain.questID then
            if gain.amount > quest.xp then
                quest.xp, quest.level, quest.at = gain.amount, gain.level, gain.time
            end
            table.sort(quests, function(a, b) return a.xp > b.xp end)
            return
        end
    end
    quests[#quests + 1] = {
        id = gain.questID,
        title = QuestTitle(gain.questID),
        xp = gain.amount,
        level = gain.level,
        at = gain.time,
    }
    table.sort(quests, function(a, b) return a.xp > b.xp end)
    while #quests > MAX_QUESTS do
        table.remove(quests)
    end
end

function Stats:OnDeath()
    if ns.Compat.IsAtMaxLevel() then
        return
    end
    local stats = Store(ns.char)
    local level = ns.SafeNumber(UnitLevel("player"))
    stats.deaths = stats.deaths + 1
    if level then
        stats.deathLevels[level] = (stats.deathLevels[level] or 0) + 1
    end
end

--------------------------------------------------------------------------------
-- Aggregation
--------------------------------------------------------------------------------

--- Keeps the entry with the highest (or lowest) value, remembering who holds it.
local function Best(current, value, key, extra, lowest)
    if value == nil then
        return current
    end
    if current and ((lowest and value >= current.value) or (not lowest and value <= current.value)) then
        return current
    end
    local entry = { value = value, key = key }
    for field, data in pairs(extra or {}) do
        entry[field] = data
    end
    return entry
end

local function SortedList(map, field)
    local list = {}
    for name, entry in pairs(map) do
        local item = { name = name }
        for k, v in pairs(entry) do
            item[k] = v
        end
        list[#list + 1] = item
    end
    table.sort(list, function(a, b)
        if a[field] ~= b[field] then
            return a[field] > b[field]
        end
        return a.name < b.name
    end)
    return list
end

local function AddBuckets(target, source, fields)
    for key, entry in pairs(source or {}) do
        local bucket = target[key]
        if not bucket then
            bucket = {}
            for _, field in ipairs(fields) do
                bucket[field] = 0
            end
            target[key] = bucket
        end
        for _, field in ipairs(fields) do
            bucket[field] = bucket[field] + (entry[field] or 0)
        end
    end
end

--- Longest and current run of consecutive played days.
local function Streaks(days)
    local times = {}
    for key in pairs(days) do
        local t = DayTime(key)
        if t then
            times[#times + 1] = t
        end
    end
    table.sort(times)
    local longest, run = 0, 0
    for i, t in ipairs(times) do
        if i > 1 and math.floor((t - times[i - 1]) / DAY + 0.5) == 1 then
            run = run + 1
        else
            run = 1
        end
        longest = math.max(longest, run)
    end
    local current = 0
    local last = times[#times]
    local today = DayTime(DayKey(time()))
    if last and today and math.floor((today - last) / DAY + 0.5) <= 1 then
        current = run
    end
    return longest, current, #times
end

--- Aggregates every statistic of a list of { key, record } entries: one
--- character or the whole account. "Best" values remember the holder key.
function Stats:Build(entries)
    local data = {
        characters = #entries,
        xp = 0, kills = 0, quests = 0, rested = 0,
        sources = {}, contexts = {},
        completed = 0, totalPlayed = 0,
        sessions = 0, sessionTime = 0, sessionXP = 0, sessionActive = 0,
        runs = 0, runNames = {},
        deaths = 0,
        weekday = {}, hour = {}, days = {}, zones = {}, mobs = {}, questList = {},
    }

    for _, entry in ipairs(entries) do
        local key, record = entry.key, entry.record
        local totals = record.totals or {}
        data.xp = data.xp + (totals.xp or 0)
        data.kills = data.kills + (totals.kills or 0)
        data.quests = data.quests + (totals.quests or 0)
        for source, xp in pairs(totals.sources or {}) do
            data.sources[source] = (data.sources[source] or 0) + xp
        end
        for context, xp in pairs(totals.contexts or {}) do
            data.contexts[context] = (data.contexts[context] or 0) + xp
        end
        for _, level in pairs(record.levels or {}) do
            data.rested = data.rested + (level.rested or 0)
        end

        -- Levels.
        local history = ns.History:GetCharacterStats(record)
        data.completed = data.completed + history.completed
        data.totalPlayed = data.totalPlayed + history.totalPlayed
        if history.fastest then
            data.fastest = Best(data.fastest, history.fastest.played, key, { level = history.fastest.level }, true)
        end
        if history.slowest then
            data.slowest = Best(data.slowest, history.slowest.played, key, { level = history.slowest.level })
        end

        -- Sessions.
        for _, session in ipairs(record.sessions or {}) do
            local duration = math.max(0, (session.endedAt or 0) - (session.startedAt or 0))
            data.sessions = data.sessions + 1
            data.sessionTime = data.sessionTime + duration
            data.sessionXP = data.sessionXP + (session.xp or 0)
            data.sessionActive = data.sessionActive + (session.active or 0)
            data.longestSession = Best(data.longestSession, duration, key, { at = session.startedAt })
            if session.rate and (session.active or 0) >= MIN_SESSION_ACTIVE then
                data.bestSession = Best(data.bestSession, session.rate, key, { at = session.startedAt })
            end
        end

        -- Runs.
        for _, run in ipairs(record.runs or {}) do
            data.runs = data.runs + 1
            if run.name then
                data.runNames[run.name] = (data.runNames[run.name] or 0) + 1
            end
            local rate = ns.Runs:GetRate(run)
            if rate then
                data.bestRun = Best(data.bestRun, rate, key, { name = run.name, level = run.level })
            end
        end

        -- Statistics collected by this module.
        local stats = record.stats
        if type(stats) == "table" then
            if stats.biggestGain then
                local gain = stats.biggestGain
                data.biggestGain = Best(data.biggestGain, gain.amount, key,
                    { source = gain.source, level = gain.level, at = gain.at })
            end
            data.deaths = data.deaths + (stats.deaths or 0)
            for level, count in pairs(stats.deathLevels or {}) do
                data.deadliest = Best(data.deadliest, count, key, { level = level })
            end
            AddBuckets(data.weekday, stats.weekday, { "xp", "active" })
            AddBuckets(data.hour, stats.hour, { "xp", "active" })
            AddBuckets(data.zones, stats.zones, { "xp", "kills", "quests", "active" })
            AddBuckets(data.mobs, stats.mobs, { "kills", "xp" })
            for day, xp in pairs(stats.days or {}) do
                data.days[day] = (data.days[day] or 0) + xp
            end
            for _, quest in ipairs(stats.quests or {}) do
                data.questList[#data.questList + 1] = {
                    id = quest.id, title = quest.title or QuestTitle(quest.id),
                    xp = quest.xp, level = quest.level, at = quest.at, key = key,
                }
            end
        end
    end

    self:Derive(data)
    return data
end

--- Computes the figures that depend on the aggregated totals.
function Stats:Derive(data)
    data.averageLevel = data.completed > 0 and data.totalPlayed / data.completed or nil
    data.averageRate = data.sessionActive >= MIN_SESSION_ACTIVE and data.sessionXP / data.sessionActive * 3600 or nil
    data.averageSession = data.sessions > 0 and data.sessionTime / data.sessions or nil
    data.restedShare = data.xp > 0 and data.rested / data.xp or nil
    local mobXP, questXP = data.sources.mob or 0, data.sources.quest or 0
    data.averageKill = data.kills > 0 and mobXP > 0 and mobXP / data.kills or nil
    data.averageQuest = data.quests > 0 and questXP > 0 and questXP / data.quests or nil

    local instanceXP, contextTotal = 0, 0
    for context, xp in pairs(data.contexts) do
        contextTotal = contextTotal + xp
        if context ~= "world" then
            instanceXP = instanceXP + xp
        end
    end
    data.instanceShare = contextTotal > 0 and instanceXP / contextTotal or nil

    local sourceTotal = 0
    for source, xp in pairs(data.sources) do
        sourceTotal = sourceTotal + xp
        if not data.topSource or xp > data.topSource.xp then
            data.topSource = { source = source, xp = xp }
        end
    end
    if data.topSource then
        data.topSource.share = data.topSource.xp / sourceTotal
    end

    for name, count in pairs(data.runNames) do
        if not data.favoriteRun or count > data.favoriteRun.count then
            data.favoriteRun = { name = name, count = count }
        end
    end

    -- When.
    local timedXP, nightXP = 0, 0
    for weekday, bucket in pairs(data.weekday) do
        timedXP = timedXP + bucket.xp
        if not data.bestWeekday or bucket.xp > data.bestWeekday.xp then
            data.bestWeekday = { weekday = weekday, xp = bucket.xp, active = bucket.active }
        end
    end
    for hour, bucket in pairs(data.hour) do
        if hour < NIGHT_END_HOUR then
            nightXP = nightXP + bucket.xp
        end
        if not data.bestHour or bucket.xp > data.bestHour.xp then
            data.bestHour = { hour = hour, xp = bucket.xp, active = bucket.active }
        end
    end
    data.nightShare = timedXP > 0 and nightXP / timedXP or nil
    for day, xp in pairs(data.days) do
        if not data.bestDay or xp > data.bestDay.xp then
            data.bestDay = { day = day, xp = xp }
        end
    end
    data.longestStreak, data.currentStreak, data.daysPlayed = Streaks(data.days)
    data.averageDay = data.daysPlayed > 0 and timedXP / data.daysPlayed or nil

    -- Where.
    data.zoneList = SortedList(data.zones, "xp")
    for _, zone in ipairs(data.zoneList) do
        zone.rate = zone.active >= MIN_ZONE_ACTIVE and zone.xp / zone.active * 3600 or nil
        if zone.rate and (not data.fastestZone or zone.rate > data.fastestZone.rate) then
            data.fastestZone = zone
        end
        if zone.kills > 0 and (not data.bloodiestZone or zone.kills > data.bloodiestZone.kills) then
            data.bloodiestZone = zone
        end
    end
    data.topZone = data.zoneList[1]

    -- What.
    data.mobList = SortedList(data.mobs, "kills")
    data.topMob = data.mobList[1]
    for _, mob in ipairs(data.mobList) do
        if not data.richestMob or mob.xp > data.richestMob.xp then
            data.richestMob = mob
        end
    end
    table.sort(data.questList, function(a, b) return a.xp > b.xp end)
    data.topQuest = data.questList[1]
end

--- Statistics of one character record.
function Stats:Collect(key)
    return self:Build({ { key = key, record = ns.db.characters[key] } })
end

--- Statistics of every tracked character together.
function Stats:CollectAccount()
    local entries = {}
    for key, record in pairs(ns.db.characters) do
        entries[#entries + 1] = { key = key, record = record }
    end
    return self:Build(entries)
end

--- Display title of a quest entry.
function Stats.QuestName(quest)
    return quest.title or QuestTitle(quest.id) or ("#" .. tostring(quest.id))
end

--- Formats a "YYYY-MM-DD" key as a local date.
function Stats.FormatDay(key)
    local t = DayTime(key)
    return t and date("%d/%m/%Y", t) or key
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Stats:OnLogin()
    Store(ns.char)
    ns:RegisterMessage("XPL_XP_GAINED", function(_, gain) self:OnExperienceGained(gain) end)
    ns:RegisterEvent("PLAYER_DEAD", function() self:OnDeath() end)
    ns:RegisterMessage("XPL_DATA_RESET", function(_, key)
        if key == ns.charKey then
            self.lastGainAt = nil
            Store(ns.char)
        end
    end)
end
