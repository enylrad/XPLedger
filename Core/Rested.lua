--[[----------------------------------------------------------------------------
    XPLedger - Rested experience
    Remembers the rested pool of every character when it logs out, so the
    pool of the alts can be estimated while they are offline.

    Stored in the character record:
      restedXP, restedMax    pool and size of the level bar at the last reading
      restedAt               epoch seconds of the last reading
      isResting              true when the character was in an inn or a city

    Offline accumulation follows the game rules: 5% of the level bar every
    8 hours while resting (a quarter of that elsewhere), up to 150% of the bar.
------------------------------------------------------------------------------]]

local _, ns = ...

local Rested = ns:NewModule("Rested")
local Compat = ns.Compat

local RESTED_RATE = 0.05 / (8 * 3600)   -- fraction of the bar per second
local OUTSIDE_FACTOR = 0.25
local MAX_FRACTION = 1.5

--- Stores the rested state of the logged character.
function Rested:Save()
    local xp, maxXP, level = Compat.GetPlayerExperience()
    if not maxXP or not level then
        return
    end
    local char = ns.char
    char.restedXP = Compat.GetRestedExperience()
    char.restedMax = maxXP
    char.restedAt = time()
    char.isResting = Compat.IsResting()
    char.atMaxLevel = level >= Compat.GetMaxLevel() or nil
end

--- Estimates the rested pool of a character record.
--- @return number|nil pool, number fraction of the level bar (0-1.5),
---         number|nil seconds until the pool is full (0 when full), boolean resting
function Rested:Estimate(record)
    if record == ns.char then
        local _, maxXP = Compat.GetPlayerExperience()
        if not maxXP or maxXP <= 0 or Compat.IsExperienceBlocked() then
            return nil
        end
        local pool = Compat.GetRestedExperience()
        local resting = Compat.IsResting()
        return pool, pool / maxXP, self:TimeToFull(pool / maxXP, resting), resting
    end

    local maxXP = record.restedMax
    if record.atMaxLevel or not maxXP or maxXP <= 0 or not record.restedAt then
        return nil
    end
    local rate = RESTED_RATE * (record.isResting and 1 or OUTSIDE_FACTOR)
    local elapsed = math.max(0, time() - record.restedAt)
    local fraction = math.min(MAX_FRACTION, (record.restedXP or 0) / maxXP + elapsed * rate)
    return fraction * maxXP, fraction, self:TimeToFull(fraction, record.isResting), record.isResting
end

--- Seconds until a pool at `fraction` of the bar reaches the cap offline.
function Rested:TimeToFull(fraction, resting)
    local missing = MAX_FRACTION - fraction
    if missing <= 0 then
        return 0
    end
    return missing / (RESTED_RATE * (resting and 1 or OUTSIDE_FACTOR))
end

function Rested:OnLogin()
    self:Save()
    ns:RegisterEvent("PLAYER_UPDATE_RESTING", function() self:Save() end)
    ns:RegisterEvent("PLAYER_LOGOUT", function() self:Save() end)
end
