--[[----------------------------------------------------------------------------
    XPLedger - Friends ranking
    Optional and experimental (settings.ranking.enabled, off by default):
    Battle.net friends who run XPLedger with sharing on see each other's
    deaths in a ranking (Stats view, Friends page), and can be told when one
    of them dies (settings.ranking.notifyDeaths).

    Everything travels as hidden Battle.net addon data (Compat.
    SendBattleNetData): nothing is written in the chat, and only Battle.net
    friends online in WoW receive it. Messages are one line:

      2;<kind>;<Name-Realm>;<CLASS>;<level>;<deaths>;<server time>

      H  hello: sent on login and when sharing is turned on; the friends
         who share answer with U
      U  update: on a level up, and as the answer to H (to that friend only)
      D  death: like U, and the friends may be told

    Protocol 1 (0.4.0) also carried a group code; those messages are
    ignored. A malformed message or one with numbers out of range is dropped
    silently. Received names never carry UI escape sequences.

    Stored for the whole account:
      XPLedgerDB.ranking = {
          members = { ["Name-Realm"] = { class, level, deaths, seen, at } },
      }
    `seen` is the local time of the last message, `at` the sender's server
    time. The account's own characters come from the local records, never
    from messages.
------------------------------------------------------------------------------]]

local _, ns = ...

local Ranking = ns:NewModule("Ranking")

local PREFIX = "XPLedger"
local PROTOCOL = "2"
local FIELDS = 7
local SEND_INTERVAL = 0.3     -- seconds between two messages
local BLOCKED_RETRY = 5       -- seconds to wait while the game blocks them
local LOGIN_DELAY = 8         -- seconds after login before saying hello
local FRESH_DEATH = 120       -- older deaths update the ranking silently
local MAX_LEVEL = 200
local MAX_DEATHS = 1000000
local MAX_MEMBERS = 200
local MAX_NAME_LENGTH = 64

local queue = {}
local flushing = false

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

--- Turns sharing on or off.
function Ranking:SetEnabled(enabled)
    Settings().enabled = enabled and true or false
    if not enabled then
        wipe(queue)
    end
    ns:SendMessage("XPL_RANKING_CHANGED")
    self:Announce("H")
end

--------------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------------

local function Encode(kind)
    local level = ns.SafeNumber(UnitLevel("player")) or (ns.char and ns.char.level) or 0
    return table.concat({
        PROTOCOL, kind, ns.charKey, ns.char.class or "UNKNOWN",
        tostring(level), tostring(ns.Deaths:GetCount()), tostring(GetServerTime()),
    }, ";")
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
--- not a valid message.
function Ranking.Decode(text)
    if type(text) ~= "string" or #text > 255 then
        return nil
    end
    local fields = {}
    for field in (text .. ";"):gmatch("([^;]*);") do
        fields[#fields + 1] = field
    end
    if #fields ~= FIELDS or fields[1] ~= PROTOCOL then
        return nil
    end
    local kind, name, class = fields[2], fields[3], fields[4]
    if kind ~= "H" and kind ~= "U" and kind ~= "D" then
        return nil
    end
    -- "Name-Realm", without pipes (UI escape sequences) or control characters.
    if #name > MAX_NAME_LENGTH or name:find("[|%c]") or not name:match("^[^%-]+%-[^%-]+$") then
        return nil
    end
    if #class > 20 or not class:match("^[A-Z]+$") then
        return nil
    end
    local level = ToInteger(fields[5], 1, MAX_LEVEL)
    local deaths = ToInteger(fields[6], 0, MAX_DEATHS)
    local at = ToInteger(fields[7], 0, 4294967295)
    if not level or not deaths or not at then
        return nil
    end
    return { kind = kind, name = name, class = class, level = level, deaths = deaths, at = at }
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

--- Sends a message of `kind` to every Battle.net friend online in WoW.
function Ranking:Announce(kind)
    if not self:IsActive() or not ns.char then
        return
    end
    local text = Encode(kind)
    ns.Compat.ForEachOnlineWoWFriend(function(target)
        Enqueue(target, text)
    end)
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

--- Name shown for a member: without the realm when it is the player's.
function Ranking.ShortName(key)
    local name, realm = key:match("^(.+)%-([^%-]+)$")
    if name and ns.char and realm == ns.char.realm then
        return name
    end
    return key
end

function Ranking:NotifyDeath(message)
    local L = ns.L
    local name = ns.ColorizeByClass(Ranking.ShortName(message.name), message.class)
    if ns.Pet and ns.Pet.SayFriendDeath and ns.Pet:SayFriendDeath(name, message.deaths) then
        -- The pet said it.
    elseif RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
        -- In the middle of the screen, never in the chat.
        RaidNotice_AddMessage(RaidWarningFrame, L["RANK_FRIEND_DIED"]:format(name, message.deaths),
            ChatTypeInfo.RAID_WARNING)
    end
    if ns.settings.alerts.sound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

function Ranking:OnData(text, sender)
    if not self:IsActive() then
        return
    end
    local message = Ranking.Decode(text)
    if not message or ns.db.characters[message.name] then
        return
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
    member.class, member.level, member.deaths = message.class, message.level, message.deaths
    member.at, member.seen = message.at, time()
    ns:SendMessage("XPL_RANKING_CHANGED")

    if message.kind == "H" and sender then
        Enqueue(sender, Encode("U"))
    elseif message.kind == "D" and Settings().notifyDeaths
        and math.abs(GetServerTime() - message.at) <= FRESH_DEATH then
        self:NotifyDeath(message)
    end
end

--------------------------------------------------------------------------------
-- Ranking rows
--------------------------------------------------------------------------------

--- Every row of the ranking, most deaths first: the account's characters
--- (`mine` = true) and the friends who share.
function Ranking:GetEntries()
    local entries = {}
    for key, record in pairs(ns.db.characters) do
        if type(record) == "table" then
            entries[#entries + 1] = {
                key = key,
                class = record.class,
                level = record.level,
                deaths = ns.Deaths:GetCount(record),
                seen = key == ns.charKey and time() or record.lastSeen,
                mine = true,
                current = key == ns.charKey,
            }
        end
    end
    if self:IsActive() then
        for key, member in pairs(Members()) do
            if not ns.db.characters[key] then
                entries[#entries + 1] = {
                    key = key,
                    class = member.class,
                    level = member.level,
                    deaths = member.deaths or 0,
                    seen = member.seen,
                }
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.deaths ~= b.deaths then
            return a.deaths > b.deaths
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
    ns:RegisterMessage("XPL_LEVEL_UP", function() self:Announce("U") end)
    -- Battle.net friends are not known right away after logging in.
    C_Timer.After(LOGIN_DELAY, function() self:Announce("H") end)
end
