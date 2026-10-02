--[[----------------------------------------------------------------------------
    XPLedger - Source attribution
    PLAYER_XP_UPDATE does not say where experience came from, so the source is
    inferred from "hints" observed around the moment of the gain:

      kill         CHAT_MSG_COMBAT_XP_GAIN matching a "<mob> dies" message
      combat       CHAT_MSG_COMBAT_XP_GAIN that is unnamed or unreadable
      quest        QUEST_TURNED_IN (carries the quest xp reward)
      exploration  CHAT_MSG_SYSTEM matching the "Discovered <zone>" message

    Since Midnight, chat payloads can be secret values while in combat or in
    instances. The text is then never inspected: the mere arrival of the event
    plus the combat state is enough to classify the gain as a kill.

    Message patterns are built from the client's own global strings, so the
    attribution works with any client language.

    Every gain also receives an activity context (world, dungeon, raid,
    battleground, scenario) captured by the Tracker when it was queued.
------------------------------------------------------------------------------]]

local _, ns = ...

local Sources = ns:NewModule("Sources")

-- Ordered list of the source buckets, also used for display order and colors.
Sources.SOURCES = { "mob", "quest", "exploration", "petbattle", "other" }
Sources.CONTEXTS = { "world", "dungeon", "raid", "battleground", "scenario" }

-- Hints are matched when they arrive within this window around the gain.
local HINT_BEFORE = 2.0
local HINT_AFTER = 0.6
-- Experience shortly after leaving combat still counts as a kill.
local POST_COMBAT_GRACE = 3.0
-- Hints older than this are discarded.
local HINT_LIFETIME = 10

local hints = {}
local killPatterns, unnamedPatterns, explorationPatterns = {}, {}, {}
local lastCombatClock = 0

--------------------------------------------------------------------------------
-- Pattern building
--------------------------------------------------------------------------------

--- Converts a printf style global string into an anchored Lua pattern.
--- Handles plain (%s, %d) and positional (%1$s) tokens.
local function FormatToPattern(format)
    local pattern = format:gsub("%%%d?%$?[sd]", "\001")
    pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    pattern = pattern:gsub("\001", "(.-)")
    return "^" .. pattern .. "$"
end

local function AddPattern(list, format)
    if type(format) == "string" and format ~= "" then
        list[#list + 1] = FormatToPattern(format)
    end
end

--- Collects every COMBATLOG_XPGAIN_* global string. Named ones ("<mob> dies,
--- you gain...") identify kills; unnamed ones are generic combat experience.
local function BuildPatterns()
    for key, value in pairs(_G) do
        if type(key) == "string" and type(value) == "string" and key:find("^COMBATLOG_XPGAIN") then
            if key:find("UNNAMED") or key:find("QUEST") then
                AddPattern(unnamedPatterns, value)
            else
                AddPattern(killPatterns, value)
            end
        end
    end
    AddPattern(explorationPatterns, _G.ERR_ZONE_EXPLORED_XP)

    -- Longer patterns are more specific: test them first.
    local function ByLength(a, b) return #a > #b end
    table.sort(killPatterns, ByLength)
    table.sort(unnamedPatterns, ByLength)
end

local function MatchesAny(text, patterns)
    for i = 1, #patterns do
        if text:find(patterns[i]) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Hint collection
--------------------------------------------------------------------------------

local function AddHint(kind, amount)
    local now = GetTime()
    -- Drop stale hints so the list never grows unbounded.
    local fresh = {}
    for i = 1, #hints do
        if now - hints[i].clock <= HINT_LIFETIME and not hints[i].consumed then
            fresh[#fresh + 1] = hints[i]
        end
    end
    fresh[#fresh + 1] = { kind = kind, clock = now, amount = amount }
    hints = fresh
end

local function OnCombatExperience(_, text)
    local message = ns.SafeString(text)
    if not message then
        AddHint("combat")
    elseif MatchesAny(message, killPatterns) then
        AddHint("kill")
    elseif MatchesAny(message, unnamedPatterns) then
        AddHint("combat")
    else
        AddHint("combat")
    end
end

local function OnQuestTurnedIn(_, _, xpReward)
    AddHint("quest", ns.SafeNumber(xpReward))
end

local function OnSystemMessage(_, text)
    local message = ns.SafeString(text)
    if message and MatchesAny(message, explorationPatterns) then
        AddHint("exploration")
    end
end

function Sources:OnLogin()
    BuildPatterns()
    ns:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", OnCombatExperience)
    ns:RegisterEvent("QUEST_TURNED_IN", OnQuestTurnedIn)
    ns:RegisterEvent("CHAT_MSG_SYSTEM", OnSystemMessage)
    ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() lastCombatClock = GetTime() end)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() lastCombatClock = GetTime() end)
end

--------------------------------------------------------------------------------
-- Classification
--------------------------------------------------------------------------------

--- Returns the first unconsumed hint of a kind inside the gain window. When
--- `amount` is given, a hint carrying a matching amount is preferred.
local function FindHint(gain, kind, amount)
    local fallback
    for i = 1, #hints do
        local hint = hints[i]
        local offset = hint.clock - gain.clock
        if not hint.consumed and hint.kind == kind and offset >= -HINT_BEFORE and offset <= HINT_AFTER then
            if not amount or not hint.amount then
                fallback = fallback or hint
            elseif math.abs(hint.amount - amount) <= math.max(1, amount * 0.15) then
                return hint
            else
                fallback = fallback or hint
            end
        end
    end
    return fallback
end

--- Consumes every hint of a kind inside the gain window. Used to swallow the
--- generic "You gain X experience" messages that accompany a quest reward.
local function ConsumeAll(gain, kind)
    for i = 1, #hints do
        local hint = hints[i]
        local offset = hint.clock - gain.clock
        if hint.kind == kind and offset >= -HINT_BEFORE and offset <= HINT_AFTER then
            hint.consumed = true
        end
    end
end

local function RecentlyInCombat(gain)
    return gain.inCombat or (gain.clock - lastCombatClock) <= POST_COMBAT_GRACE
end

--- Sets gain.source based on the collected hints. gain.context is already set.
function Sources:Classify(gain)
    if gain.inPetBattle then
        gain.source = "petbattle"
        return
    end

    local hint = FindHint(gain, "quest", gain.amount)
    if hint then
        hint.consumed = true
        ConsumeAll(gain, "combat")
        gain.source = "quest"
        return
    end

    hint = FindHint(gain, "exploration")
    if hint then
        hint.consumed = true
        gain.source = "exploration"
        return
    end

    hint = FindHint(gain, "kill")
    if hint then
        hint.consumed = true
        gain.source = "mob"
        return
    end

    hint = FindHint(gain, "combat")
    if hint then
        hint.consumed = true
        gain.source = RecentlyInCombat(gain) and "mob" or "other"
        return
    end

    gain.source = RecentlyInCombat(gain) and "mob" or "other"
end
