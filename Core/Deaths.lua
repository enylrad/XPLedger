--[[----------------------------------------------------------------------------
    XPLedger - Deaths
    Counts every death of each character, also at the level cap (unlike
    stats.deaths, which only counts deaths while leveling, see Stats).

    Stored in the character record:
      deathCount   deaths since the character was first tracked; it starts
                   from stats.deaths for characters tracked before it existed

    Broadcasts XPL_DEATH (count) after each death: the pet says the count
    and the friends ranking shares it (see Ranking).
------------------------------------------------------------------------------]]

local _, ns = ...

local Deaths = ns:NewModule("Deaths")

--- Total deaths of a character record (default: the logged character).
function Deaths:GetCount(record)
    record = record or ns.char
    if type(record) ~= "table" then
        return 0
    end
    local count = ns.SafeNumber(record.deathCount)
    if count then
        return count
    end
    local stats = type(record.stats) == "table" and ns.SafeNumber(record.stats.deaths)
    return stats or 0
end

function Deaths:OnDeath()
    local count = self:GetCount() + 1
    ns.char.deathCount = count
    ns:SendMessage("XPL_DEATH", count)
end

function Deaths:OnLogin()
    ns.char.deathCount = self:GetCount()
    ns:RegisterEvent("PLAYER_DEAD", function() self:OnDeath() end)
end
