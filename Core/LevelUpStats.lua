--[[----------------------------------------------------------------------------
    XPLedger - Level up stats
    Works out what the character gained on each level up: health, power,
    talent points and the five primary stats.

    Every gain comes from the PLAYER_LEVEL_UP payload, which carries plain
    numbers even in combat (when WoW Forever turns UnitStat and friends into
    secret values):
      classic   level, health, power, talents, str, agi, sta, int, spi
      mainline  level, health, power, talents, pvpSlots, str, agi, sta, int, spi
    (WoW Forever uses the mainline layout.) The layout is told apart by the
    number of values. A before/after snapshot only fills what the payload
    lacks.

    Broadcasts XPL_LEVEL_STATS(result) once the client has settled, where
      result = { level, health, power, powerToken, talents, stats = { [1..5] } }
    Missing or zero values are nil.
------------------------------------------------------------------------------]]

local _, ns = ...

local LevelUpStats = ns:NewModule("LevelUpStats")

local STAT_COUNT = 5
-- XPL_LEVEL_UP already fires a moment after PLAYER_LEVEL_UP; this extra wait
-- lets the client finish updating the character's stats.
local SETTLE_DELAY = 0.5

local snapshot
local payload       -- values carried by the last PLAYER_LEVEL_UP, by level
local pendingLevel  -- highest level reached while the timer is running
local lastResult

local function TakeSnapshot()
    local current = {
        health = ns.SafeNumber(UnitHealthMax("player")),
        power = ns.SafeNumber(UnitPowerMax("player")),
        stats = {},
    }
    for i = 1, STAT_COUNT do
        current.stats[i] = ns.SafeNumber((UnitStat("player", i)))
    end
    if UnitCharacterPoints then
        current.talents = ns.SafeNumber((UnitCharacterPoints("player")))
    end
    return current
end

--- Returns new - old when both are plain numbers and the difference is positive.
local function Gain(new, old)
    if new and old and new > old then
        return new - old
    end
    return nil
end

--- Adds two optional numbers (nil when both are missing).
local function Sum(a, b)
    if a == nil then
        return b
    end
    return a + (b or 0)
end

--- Returns the value when it is a positive plain number.
local function Positive(value)
    value = ns.SafeNumber(value)
    if value and value > 0 then
        return value
    end
    return nil
end

local function Settle()
    local level = pendingLevel
    pendingLevel = nil
    local current = TakeSnapshot()
    local previous = snapshot or current
    local carried = payload and payload.level == level and payload or {}

    local result = {
        level = level,
        health = Positive(carried.health) or Gain(current.health, previous.health),
        power = Positive(carried.power) or Gain(current.power, previous.power),
        talents = Positive(carried.talents) or Gain(current.talents, previous.talents),
        stats = {},
    }
    local _, powerToken = UnitPowerType("player")
    result.powerToken = ns.SafeString(powerToken)
    for i = 1, STAT_COUNT do
        local carriedStat = carried.stats and carried.stats[i]
        if carriedStat ~= nil and ns.SafeNumber(carriedStat) then
            result.stats[i] = Positive(carriedStat)
        else
            result.stats[i] = Gain(current.stats[i], previous.stats[i])
        end
    end

    snapshot = current
    payload = nil
    lastResult = result
    ns:SendMessage("XPL_LEVEL_STATS", result)
end

function LevelUpStats:OnLogin()
    snapshot = TakeSnapshot()

    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if not pendingLevel then
            snapshot = TakeSnapshot()
        end
    end)

    ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, ...)
        local count = select("#", ...)
        local level, health, power, talents = ...
        -- Mainline inserts the PvP talent slots before the stats.
        local firstStat = count >= 10 and 6 or 5
        local stats = {}
        if count >= firstStat + STAT_COUNT - 1 then
            for i = 1, STAT_COUNT do
                stats[i] = (select(firstStat + i - 1, ...))
            end
        end
        local gained = {
            level = ns.SafeNumber(level),
            health = ns.SafeNumber(health),
            power = ns.SafeNumber(power),
            talents = ns.SafeNumber(talents),
            stats = stats,
        }
        for i = 1, STAT_COUNT do
            stats[i] = ns.SafeNumber(stats[i])
        end
        -- Several levels before Settle runs: add the gains up.
        if payload then
            gained.health = Sum(payload.health, gained.health)
            gained.power = Sum(payload.power, gained.power)
            gained.talents = Sum(payload.talents, gained.talents)
            for i = 1, STAT_COUNT do
                stats[i] = Sum(payload.stats[i], stats[i])
            end
        end
        payload = gained
    end)

    -- Several levels at once send one message per level: settle only once.
    ns:RegisterMessage("XPL_LEVEL_UP", function(_, _, newLevel)
        local scheduled = pendingLevel ~= nil
        pendingLevel = math.max(pendingLevel or 0, newLevel or 0)
        if not scheduled then
            C_Timer.After(SETTLE_DELAY, Settle)
        end
    end)
end

--- Returns the result of the last level up of this session, if any.
function LevelUpStats:GetLast()
    return lastResult
end
