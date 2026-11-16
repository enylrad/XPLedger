--[[----------------------------------------------------------------------------
    XPLedger - Friends ranking
    Optional (settings.ranking.enabled, off by default): Battle.net friends
    who run XPLedger with sharing on see each other's progress in a ranking
    (Friends view): level and level progress, deaths, XP/hour,
    time to level, time played, kills, quests and runs. They can be told
    when one of them dies (settings.ranking.notifyDeaths) or levels up
    (settings.ranking.notifyLevels).

    Everything travels as hidden Battle.net addon data (Compat.
    SendBattleNetData). Light on traffic:
      - H goes to every Battle.net friend online in WoW, to find who shares;
      - everything else only goes to the friends that answered (peers);
      - one pending message per friend, sent at most every SEND_INTERVAL;
      - progress updates at most every PROGRESS_INTERVAL, and only when the
        progress moved at least PROGRESS_STEP.

    Messages are one line of `;` separated fields:

      4;<kind>;<Name-Realm>;<CLASS>;<level>;<progress>;<deaths>;<xp/hour>;
        <eta>;<played>;<kills>;<quests>;<runs>;<efficiency>;<% mob>;<% quest>;
        <% exploration>;<% pet battle>;<% other>;<server time>

      H  hello: sent on login and when sharing is turned on; the friends
         who share answer with U
      U  update: as the answer to H (to that friend only), and while
         gaining experience
      L  level up: like U, and the friends may be told
      D  death: like U, and the friends may be told

    <progress> is the part of the level done in thousandths (0-999); <eta>
    and <played> are seconds. <progress>, <xp/hour>, <eta> and <played> are
    empty when unknown (level cap, no rate yet, /played not read).
    <efficiency> is the "optimization": hundredths of a level gained per
    active hour (AFK time left out) since tracking started, empty when
    unknown (see Ranking.GetEfficiency). The
    <% ...> fields split the experience earned by source (see Sources),
    empty while the character has earned none.

    Older protocols are still read, without the fields they lack (see
    LAYOUTS): 3 (0.4.2) and 2 (0.4.1). Protocol 1 (0.4.0) carried a group
    code; those messages are ignored. A malformed message or one with
    numbers out of range is dropped silently. Received names never carry
    UI escape sequences.

    Stored for the whole account:
      XPLedgerDB.ranking = {
          members = { ["Name-Realm"] = { class, level, progress, deaths, rate,
                      eta, played, kills, quests, runs, seen, at } },
      }
    `seen` is the local time of the last message, `at` the sender's server
    time. The account's own characters come from the local records, never
    from messages.
------------------------------------------------------------------------------]]

local _, ns = ...

local Ranking = ns:NewModule("Ranking")

local PREFIX = "XPLedger"
local PROTOCOL = "4"
local SEND_INTERVAL = 0.5     -- seconds between two messages
local BLOCKED_RETRY = 5       -- seconds to wait while the game blocks them
local LOGIN_DELAY = 8         -- seconds after login before saying hello
local FRESH_NOTICE = 120      -- older deaths and level ups update the ranking silently
local MAX_MEMBERS = 200
local MAX_NAME_LENGTH = 64
local PROGRESS_INTERVAL = 300 -- seconds between two progress updates
local PROGRESS_STEP = 20      -- thousandths of a level worth an update
Ranking.RATE_FRESH = 900      -- seconds: an older XP/hour is not shown

-- Values after <CLASS>, per readable protocol.
local LAYOUTS = {
    ["2"] = { "level", "deaths", "at" },
    ["3"] = { "level", "progress", "deaths", "at" },
    ["4"] = {
        "level", "progress", "deaths", "rate", "eta", "played", "kills", "quests", "runs", "efficiency",
        "shareMob", "shareQuest", "shareExploration", "sharePetbattle", "shareOther", "at",
    },
}

-- Range of every value; `optional` values may be empty.
local VALUES = {
    level = { 1, 200 },
    progress = { 0, 999, optional = true },
    deaths = { 0, 1000000 },
    rate = { 0, 1000000000, optional = true },
    eta = { 0, 10000000, optional = true },
    played = { 0, 1000000000, optional = true },
    kills = { 0, 10000000 },
    quests = { 0, 10000000 },
    runs = { 0, 10000000 },
    efficiency = { 0, 100000, optional = true },
    shareMob = { 0, 100, optional = true },
    shareQuest = { 0, 100, optional = true },
    shareExploration = { 0, 100, optional = true },
    sharePetbattle = { 0, 100, optional = true },
    shareOther = { 0, 100, optional = true },
    at = { 0, 4294967295 },
}

-- Values that belong to one level: dropped when an older message moves
-- the member to another level without them.
local PER_LEVEL = { progress = true, eta = true }
local MIN_EFFICIENCY_ACTIVE = 1800  -- active seconds before the efficiency means something
local MIN_EFFICIENCY_LEVELS = 0.25

local KINDS = { H = true, U = true, L = true, D = true }

-- Experience sources, in the order shown, and the value carrying each share.
Ranking.SOURCES = {
    { source = "mob", key = "shareMob" },
    { source = "quest", key = "shareQuest" },
    { source = "exploration", key = "shareExploration" },
    { source = "petbattle", key = "sharePetbattle" },
    { source = "other", key = "shareOther" },
}

local queue = {}
local flushing = false
local peers = {}  -- game accounts that sent a valid message this login
local lastProgressAt = 0
local lastProgress

local function Settings()
    return ns.settings.ranking
end

local function Members()
    return ns.db.ranking.members
end

--------------------------------------------------------------------------------
-- Sharing
--------------------------------------------------------------------------------

--- True when the player shares with Battle.net friends.
function Ranking:IsActive()
    return Settings().enabled == true
end

--- Number of friends' game accounts that sent a valid message this login.
function Ranking:CountPeers()
    local count = 0
    for _ in pairs(peers) do
        count = count + 1
    end
    return count
end

--- Turns sharing on or off.
function Ranking:SetEnabled(enabled)
    Settings().enabled = enabled and true or false
    if not enabled then
        wipe(queue)
        wipe(peers)
    end
    ns:SendMessage("XPL_RANKING_CHANGED")
    self:Announce("H")
end

--------------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------------

--- Part of the current level done, in thousandths (0-999), or nil at the
--- level cap or when unknown.
function Ranking.GetProgress()
    if ns.Compat.IsAtMaxLevel() then
        return nil
    end
    local xp, maxXP = ns.Tracker:GetSnapshot()
    if not xp or not maxXP or maxXP <= 0 then
        return nil
    end
    return math.max(0, math.min(999, math.floor(xp / maxXP * 1000)))
end

--- Finished runs of a character record that gave experience.
function Ranking.CountRuns(record)
    local count = 0
    for _, run in ipairs(type(record.runs) == "table" and record.runs or {}) do
        if (run.xp or 0) > 0 then
            count = count + 1
        end
    end
    return count
end

local function Whole(value)
    value = ns.SafeNumber(value)
    return value and value >= 0 and math.floor(value) or nil
end

--- Percent of the experience earned from each source (keys of
--- Ranking.SOURCES, rounded), or nil when nothing was earned yet.
function Ranking.GetShares(record)
    local totals = type(record.totals) == "table" and record.totals
    local sources = totals and type(totals.sources) == "table" and totals.sources
    if not sources then
        return nil
    end
    local sum = 0
    for _, amount in pairs(sources) do
        sum = sum + (ns.SafeNumber(amount) or 0)
    end
    if sum <= 0 then
        return nil
    end
    local shares = {}
    for _, item in ipairs(Ranking.SOURCES) do
        local amount = ns.SafeNumber(sources[item.source]) or 0
        shares[item.key] = math.floor(amount / sum * 100 + 0.5)
    end
    -- Unknown sources count as "other".
    local known = 0
    for _, item in ipairs(Ranking.SOURCES) do
        known = known + (ns.SafeNumber(sources[item.source]) or 0)
    end
    shares.shareOther = math.floor(((ns.SafeNumber(sources.other) or 0) + sum - known) / sum * 100 + 0.5)
    return shares
end

--- XP/hour and time to level of the logged character, or nil.
function Ranking.GetPace()
    if ns.Compat.IsAtMaxLevel() then
        return nil, nil
    end
    local estimate = ns.Tracker:GetEstimate()
    return Whole(estimate.rate or estimate.sessionRate), Whole(estimate.eta)
end

--- Levels gained per active hour of a character record since tracking
--- started (the "optimization"), or nil with too little data. Both the
--- levels and the time come from the progress samples (History), which
--- keep their first point; each gap between two samples counts at most the
--- AFK threshold, as the Tracker does.
function Ranking.GetEfficiency(record)
    local samples = type(record) == "table" and type(record.samples) == "table" and record.samples
    local t, v = samples and samples.t, samples and samples.v
    if type(t) ~= "table" or type(v) ~= "table" or #t < 2 or #v ~= #t then
        return nil
    end
    local afkSeconds = (ns.SafeNumber(ns.settings.afkThreshold) or 5) * 60
    local active = 0
    for i = 2, #t do
        active = active + ns.Clamp((ns.SafeNumber(t[i]) or 0) - (ns.SafeNumber(t[i - 1]) or 0), 0, afkSeconds)
    end
    local levels = (ns.SafeNumber(v[#v]) or 0) - (ns.SafeNumber(v[1]) or 0)
    if active < MIN_EFFICIENCY_ACTIVE or levels < MIN_EFFICIENCY_LEVELS then
        return nil
    end
    return levels / (active / 3600)
end

--- Values of the logged character, as LAYOUTS name them.
local function CurrentValues(level)
    local totals = type(ns.char.totals) == "table" and ns.char.totals or {}
    local rate, eta = Ranking.GetPace()
    local values = Ranking.GetShares(ns.char) or {}
    local base = {
        level = level or ns.SafeNumber(UnitLevel("player")) or ns.char.level or 1,
        progress = Ranking.GetProgress(),
        deaths = ns.Deaths:GetCount(),
        rate = rate,
        eta = eta,
        played = Whole(ns.History and ns.History:GetPlayedNow()),
        kills = Whole(totals.kills) or 0,
        quests = Whole(totals.quests) or 0,
        runs = Ranking.CountRuns(ns.char),
        efficiency = Whole((Ranking.GetEfficiency(ns.char) or -1) * 100),
        at = GetServerTime(),
    }
    for key, value in pairs(base) do
        values[key] = value
    end
    return values
end

local function Encode(kind, level)
    local values = CurrentValues(level)
    local fields = { PROTOCOL, kind, ns.charKey, ns.char.class or "UNKNOWN" }
    for _, key in ipairs(LAYOUTS[PROTOCOL]) do
        local value = values[key]
        fields[#fields + 1] = value and tostring(value) or ""
    end
    return table.concat(fields, ";")
end

local function ToInteger(text, low, high)
    if type(text) ~= "string" or not text:match("^%d+$") then
        return nil
    end
    local value = tonumber(text)
    if not value or value < low or value > high then
        return nil
    end
    return value
end

--- Parses a received line. Returns a message table, or nil when the line is
--- not a valid message. `message.carried` lists the values the protocol has.
function Ranking.Decode(text)
    if type(text) ~= "string" or #text > 255 then
        return nil
    end
    local fields = {}
    for field in (text .. ";"):gmatch("([^;]*);") do
        fields[#fields + 1] = field
    end
    local layout = LAYOUTS[fields[1]]
    if not layout or #fields ~= #layout + 4 then
        return nil
    end
    local kind, name, class = fields[2], fields[3], fields[4]
    if not KINDS[kind] then
        return nil
    end
    -- "Name-Realm", without pipes (UI escape sequences) or control characters.
    if #name > MAX_NAME_LENGTH or name:find("[|%c]") or not name:match("^[^%-]+%-[^%-]+$") then
        return nil
    end
    if #class > 20 or not class:match("^[A-Z]+$") then
        return nil
    end
    local message = { kind = kind, name = name, class = class, carried = {} }
    for index, key in ipairs(layout) do
        local field, range = fields[index + 4], VALUES[key]
        message.carried[key] = true
        if not (range.optional and field == "") then
            local value = ToInteger(field, range[1], range[2])
            if not value then
                return nil
            end
            message[key] = value
        end
    end
    return message
end

local function Flush()
    if not Ranking:IsActive() then
        wipe(queue)
        flushing = false
        return
    end
    if ns.Compat.IsAddonMessagingBlocked() then
        C_Timer.After(BLOCKED_RETRY, Flush)
        return
    end
    local item = table.remove(queue, 1)
    if item then
        ns.Compat.SendBattleNetData(item.target, PREFIX, item.text)
    end
    if #queue > 0 then
        C_Timer.After(SEND_INTERVAL, Flush)
    else
        flushing = false
    end
end

local function Enqueue(target, text)
    -- One pending message per friend is enough: keep the newest.
    for _, item in ipairs(queue) do
        if item.target == target then
            item.text = text
            return
        end
    end
    queue[#queue + 1] = { target = target, text = text }
    if not flushing then
        flushing = true
        C_Timer.After(0, Flush)
    end
end

--- Sends a message of `kind`: H to every Battle.net friend online in WoW
--- (to find who shares), anything else only to the friends who answered.
--- `level` overrides the level read from the game (right after a level up).
function Ranking:Announce(kind, level)
    if not self:IsActive() or not ns.char then
        return
    end
    local text = Encode(kind, level)
    lastProgressAt, lastProgress = time(), Ranking.GetProgress()
    if kind == "H" then
        ns.Compat.ForEachOnlineWoWFriend(function(target)
            Enqueue(target, text)
        end)
    else
        for target in pairs(peers) do
            Enqueue(target, text)
        end
    end
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

local function CountMembers()
    local count = 0
    for _ in pairs(Members()) do
        count = count + 1
    end
    return count
end

local function SplitKey(key)
    return key:match("^(.+)%-([^%-]+)$")
end

--- Name shown for a member: without the realm when it is the player's (or
--- always with it when `withRealm`), and with a short realm name (see
--- ns.ShortRealm).
function Ranking.ShortName(key, withRealm)
    local name, realm = SplitKey(key)
    if not name then
        return key
    end
    if not withRealm and ns.char and realm == ns.char.realm then
        return name
    end
    return name .. "-" .. ns.ShortRealm(realm)
end

--- Name used in death notices: the first name only (no Forever surname),
--- plus the short realm when it is not the player's.
function Ranking.NoticeName(key)
    local name, realm = SplitKey(key)
    if not name then
        return key
    end
    local separator = ns.Compat.GetSurnameSeparator and ns.Compat.GetSurnameSeparator() or " "
    local cut = name:find(separator, 1, true)
    if cut and cut > 1 then
        name = name:sub(1, cut - 1)
    end
    if ns.char and realm == ns.char.realm then
        return name
    end
    return name .. "-" .. ns.ShortRealm(realm)
end

--- Tells about a friend: the pet says `event` when it is shown, else a
--- message shows in the middle of the screen (never in the chat).
function Ranking:Notify(message, event, textKey, value)
    local name = ns.ColorizeByClass(Ranking.NoticeName(message.name), message.class)
    if ns.Pet and ns.Pet.SayFriend and ns.Pet:SayFriend(event, name, value) then
        -- The pet said it.
    elseif RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
        RaidNotice_AddMessage(RaidWarningFrame, ns.L[textKey]:format(name, value), ChatTypeInfo.RAID_WARNING)
    end
    if ns.settings.alerts.sound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

function Ranking:NotifyDeath(message)
    self:Notify(message, "frienddeath", "RANK_FRIEND_DIED", message.deaths)
end

function Ranking:NotifyLevel(message)
    self:Notify(message, "friendlevel", "RANK_FRIEND_LEVEL", message.level)
end

function Ranking:OnData(text, sender)
    if not self:IsActive() then
        return
    end
    local message = Ranking.Decode(text)
    if not message or ns.db.characters[message.name] then
        return
    end
    if sender then
        peers[sender] = true
    end
    local members = Members()
    local member = members[message.name]
    if not member then
        if CountMembers() >= MAX_MEMBERS then
            return
        end
        member = {}
        members[message.name] = member
    end
    local levelChanged = member.level ~= message.level
    for key in pairs(VALUES) do
        if message.carried[key] then
            member[key] = message[key]
        elseif levelChanged and PER_LEVEL[key] then
            -- An older version: values of another level are meaningless.
            member[key] = nil
        end
    end
    member.class, member.seen = message.class, time()
    ns:SendMessage("XPL_RANKING_CHANGED")

    local fresh = math.abs(GetServerTime() - message.at) <= FRESH_NOTICE
    if message.kind == "H" and sender then
        Enqueue(sender, Encode("U"))
    elseif message.kind == "D" and fresh and Settings().notifyDeaths then
        self:NotifyDeath(message)
    elseif message.kind == "L" and fresh and Settings().notifyLevels then
        self:NotifyLevel(message)
    end
end

--------------------------------------------------------------------------------
-- Ranking rows
--------------------------------------------------------------------------------

--- Progress of another character of the account, from its last sample
--- (level + fraction), or nil.
local function SavedProgress(record)
    local samples = type(record.samples) == "table" and record.samples
    local values = samples and samples.v
    local value = values and ns.SafeNumber(values[#values])
    if not value or not record.level or math.floor(value) ~= record.level then
        return nil
    end
    return math.floor((value - record.level) * 1000)
end

--- Sends the level progress while gaining experience, now and then.
function Ranking:OnExperienceGained()
    local progress = Ranking.GetProgress()
    if not progress or time() - lastProgressAt < PROGRESS_INTERVAL then
        return
    end
    if lastProgress and math.abs(progress - lastProgress) < PROGRESS_STEP then
        return
    end
    self:Announce("U")
end

--- Levels gained per hour played (level 1 counts as none), or nil.
function Ranking.GetSpeed(entry)
    if not entry.level or not entry.played or entry.played < 600 then
        return nil
    end
    return (entry.level - 1 + (entry.progress or 0) / 1000) / (entry.played / 3600)
end

local SORTS = {
    deaths = function(entry) return entry.deaths end,
    level = function(entry) return (entry.level or 0) + (entry.progress or 0) / 1000 end,
    speed = function(entry) return Ranking.GetSpeed(entry) end,
    optimization = function(entry) return entry.efficiency end,
}

local function OwnEntry(key, record)
    local current = key == ns.charKey
    local totals = type(record.totals) == "table" and record.totals or {}
    local entry = {
        key = key,
        class = record.class,
        level = record.level,
        progress = current and Ranking.GetProgress() or SavedProgress(record),
        deaths = ns.Deaths:GetCount(record),
        played = Whole(record.played),
        kills = Whole(totals.kills) or 0,
        quests = Whole(totals.quests) or 0,
        runs = Ranking.CountRuns(record),
        shares = Ranking.GetShares(record),
        efficiency = Ranking.GetEfficiency(record),
        seen = current and time() or record.lastSeen,
        mine = true,
        current = current,
    }
    if current then
        entry.rate, entry.eta = Ranking.GetPace()
        entry.played = Whole(ns.History and ns.History:GetPlayedNow()) or entry.played
    end
    return entry
end

local function FriendEntry(key, member)
    local entry = {
        key = key,
        class = member.class,
        level = member.level,
        progress = member.progress,
        deaths = member.deaths or 0,
        played = member.played,
        kills = member.kills,
        quests = member.quests,
        runs = member.runs,
        efficiency = member.efficiency and member.efficiency / 100,
        seen = member.seen,
    }
    if member.shareMob then
        entry.shares = {}
        for _, item in ipairs(Ranking.SOURCES) do
            entry.shares[item.key] = member[item.key] or 0
        end
    end
    -- The pace only means something while the friend is still playing.
    local age = member.seen and time() - member.seen
    if age and age <= Ranking.RATE_FRESH then
        entry.rate = member.rate
        entry.eta = member.eta and math.max(0, member.eta - age) or nil
    end
    return entry
end

--- Every row of the ranking: the account's characters (`mine` = true) and
--- the friends who share, sorted by `sort` ("deaths", "level", "speed" or
--- "optimization" (levels per active hour),
--- highest first; rows without a value go last).
function Ranking:GetEntries(sort)
    local entries = {}
    for key, record in pairs(ns.db.characters) do
        if type(record) == "table" then
            entries[#entries + 1] = OwnEntry(key, record)
        end
    end
    if self:IsActive() then
        for key, member in pairs(Members()) do
            if not ns.db.characters[key] then
                entries[#entries + 1] = FriendEntry(key, member)
            end
        end
    end
    local value = SORTS[sort] or SORTS.deaths
    local keys = {}
    for _, entry in ipairs(entries) do
        keys[entry] = value(entry)
    end
    table.sort(entries, function(a, b)
        local va, vb = keys[a], keys[b]
        if va ~= vb then
            if va == nil or vb == nil then
                return vb == nil
            end
            return va > vb
        end
        return a.key < b.key
    end)
    return entries
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Ranking:OnInitialize()
    local data = ns.db.ranking
    if type(data) ~= "table" then
        data = {}
        ns.db.ranking = data
    end
    data.members = type(data.members) == "table" and data.members or {}
    -- 0.4.0 had group codes.
    ns.settings.ranking.code = nil
end

function Ranking:OnLogin()
    ns.Compat.RegisterAddonPrefix(PREFIX)
    ns:RegisterEvent("BN_CHAT_MSG_ADDON", function(_, prefix, text, _, sender)
        if prefix == PREFIX then
            self:OnData(text, ns.SafeNumber(sender))
        end
    end)
    ns:RegisterMessage("XPL_DEATH", function() self:Announce("D") end)
    ns:RegisterMessage("XPL_LEVEL_UP", function(_, _, newLevel) self:Announce("L", ns.SafeNumber(newLevel)) end)
    ns:RegisterMessage("XPL_DEATH_SYNC", function() self:Announce("U") end)
    ns:RegisterMessage("XPL_XP_GAINED", function() self:OnExperienceGained() end)
    -- Battle.net friends are not known right away after logging in.
    C_Timer.After(LOGIN_DELAY, function() self:Announce("H") end)
end
