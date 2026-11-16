--[[----------------------------------------------------------------------------
    XPLedger - Deaths
    Counts every death of each character, also at the level cap (unlike
    stats.deaths, which only counts deaths while leveling, see Stats).

    The game's own statistic (Statistics > Deaths > Total deaths, see
    Compat.GetTotalDeathsStatistic) wins when the client has it: it also knows
    the deaths from before XPLedger was installed. The addon's own count is
    the fallback for clients without statistics.

    Stored in the character record:
      deathCount   total deaths; it starts from the statistic, or from
                   stats.deaths for characters tracked before it existed

    Broadcasts XPL_DEATH (count) after each death: the pet says the count
    and the friends ranking shares it (see Ranking). XPL_DEATH_SYNC (count)
    when the statistic raised the count without a death.
------------------------------------------------------------------------------]]

local _, ns = ...

local Deaths = ns:NewModule("Deaths")

local SYNC_DELAY = 5  -- seconds: the statistics may not be loaded at login

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

--- Raises the count to the game's statistic. The count never goes down.
function Deaths:Sync()
    local statistic = ns.Compat.GetTotalDeathsStatistic()
    local count = self:GetCount()
    if statistic and statistic > count then
        ns.char.deathCount = statistic
        ns:SendMessage("XPL_DEATH_SYNC", statistic)
    end
end

function Deaths:OnDeath()
    -- The statistic may already include this death, or not yet.
    local count = math.max(self:GetCount() + 1, ns.Compat.GetTotalDeathsStatistic() or 0)
    ns.char.deathCount = count
    ns:SendMessage("XPL_DEATH", count)
end

function Deaths:OnLogin()
    ns.char.deathCount = self:GetCount()
    ns:RegisterEvent("PLAYER_DEAD", function() self:OnDeath() end)
    self:Sync()
    C_Timer.After(SYNC_DELAY, function() self:Sync() end)
end
