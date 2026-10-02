--[[----------------------------------------------------------------------------
    XPLedger - Goals and alerts
    A level goal per character (optionally with a deadline), an experience
    goal per session and the on-screen alerts of the addon.

    Stored data:
      char.goal = { level, deadline, setAt, reachedAt }
      settings.goals.sessionXP        0 disables the session goal
      settings.alerts.<kind>          rested, goals, records, milestones, sound
------------------------------------------------------------------------------]]

local _, ns = ...

local Goals = ns:NewModule("Goals")

local DAY = 86400

--------------------------------------------------------------------------------
-- Alerts
--------------------------------------------------------------------------------

--- Shows an alert in the chat and in the middle of the screen, unless the
--- alert kind is disabled in the options.
function Goals:Alert(kind, message)
    local alerts = ns.settings.alerts
    if kind and alerts[kind] == false then
        return
    end
    ns:Print(message)
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
        RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo.RAID_WARNING)
    elseif UIErrorsFrame then
        UIErrorsFrame:AddMessage(message, 1, 0.82, 0)
    end
    if alerts.sound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

--------------------------------------------------------------------------------
-- Level goal
--------------------------------------------------------------------------------

--- Sets the level goal of the logged character. `days` is optional.
--- @return boolean ok, string|nil error locale key
function Goals:SetLevelGoal(level, days)
    local _, _, current = ns.Tracker:GetSnapshot()
    current = current or ns.char.level or 1
    if not level or level <= current or level > ns.Compat.GetMaxLevel() then
        return false, "GOAL_INVALID_LEVEL"
    end
    if days and days <= 0 then
        return false, "GOAL_INVALID_DAYS"
    end
    ns.char.goal = {
        level = level,
        deadline = days and time() + days * DAY or nil,
        setAt = time(),
    }
    ns:SendMessage("XPL_STATE_CHANGED")
    return true
end

function Goals:ClearLevelGoal()
    ns.char.goal = nil
    ns:SendMessage("XPL_STATE_CHANGED")
end

--- Projection of the level goal of a character record, or nil without goal.
--- Fields: level, deadline, reachedAt, levelsLeft, perLevel (played seconds
--- per level, from the recent pace), playedLeft, timeLeft (until the
--- deadline) and hoursPerDay (played hours needed every day).
function Goals:GetProjection(record)
    local goal = record.goal
    if type(goal) ~= "table" or not goal.level then
        return nil
    end
    local projection = { level = goal.level, deadline = goal.deadline, reachedAt = goal.reachedAt }
    if goal.reachedAt then
        return projection
    end

    local level, fraction = record.level or 1, 0
    if record == ns.char then
        local xp, maxXP, current = ns.Tracker:GetSnapshot()
        if xp and maxXP and current and maxXP > 0 then
            level, fraction = current, xp / maxXP
        end
    end
    projection.levelsLeft = math.max(0, goal.level - level - fraction)

    local _, _, recentAverage = ns.History:GetRecentPace(record)
    projection.perLevel = recentAverage
    if recentAverage then
        projection.playedLeft = projection.levelsLeft * recentAverage
    end
    if goal.deadline then
        projection.timeLeft = goal.deadline - time()
        if projection.playedLeft and projection.timeLeft > 0 then
            projection.hoursPerDay = projection.playedLeft / 3600 / math.max(1, projection.timeLeft / DAY)
        end
    end
    return projection
end

--- One line describing the level goal of a record, or nil without goal.
function Goals:FormatGoal(record)
    local L = ns.L
    local projection = self:GetProjection(record)
    if not projection then
        return nil
    end
    if projection.reachedAt then
        return L["GOAL_REACHED_ON"]:format(projection.level, date("%d/%m/%Y", projection.reachedAt))
    end
    local text = L["GOAL_STATUS"]:format(projection.level, ("%.1f"):format(projection.levelsLeft))
    if projection.playedLeft then
        text = text .. "  ·  " .. L["GOAL_PLAYED_LEFT"]:format(ns.FormatDuration(projection.playedLeft))
    end
    if projection.deadline then
        if projection.timeLeft <= 0 then
            text = text .. "  ·  " .. L["GOAL_DEADLINE_PASSED"]
        elseif projection.hoursPerDay then
            text = text .. "  ·  " .. L["GOAL_PER_DAY"]:format(ns.FormatDuration(projection.hoursPerDay * 3600))
        end
    end
    return text
end

--------------------------------------------------------------------------------
-- Event handlers
--------------------------------------------------------------------------------

function Goals:OnLevelUp(_, newLevel)
    local goal = ns.char.goal
    if type(goal) == "table" and goal.level and not goal.reachedAt and newLevel >= goal.level then
        goal.reachedAt = time()
        local text = ns.L["ALERT_LEVEL_GOAL"]:format(goal.level)
        if goal.deadline then
            local margin = goal.deadline - goal.reachedAt
            text = text .. " " .. (margin >= 0 and ns.L["ALERT_GOAL_EARLY"] or ns.L["ALERT_GOAL_LATE"])
                :format(ns.FormatDuration(math.abs(margin)))
        end
        self:Alert("goals", text)
    end
end

function Goals:OnExperienceGained()
    local target = ns.settings.goals.sessionXP or 0
    local session = ns.Tracker:GetSession()
    if target > 0 and not session.goalReached and session.xp >= target then
        session.goalReached = true
        self:Alert("goals", ns.L["ALERT_SESSION_GOAL"]:format(ns.FormatInteger(target),
            ns.FormatDuration(time() - session.startedAt)))
    end
end

function Goals:OnRestedChanged()
    local rested = ns.Compat.GetRestedExperience()
    if (self.lastRested or 0) > 0 and rested <= 0 and not ns.Compat.IsExperienceBlocked() then
        self:Alert("rested", ns.L["ALERT_RESTED_DEPLETED"])
    end
    self.lastRested = rested
end

--- Sets the session goal (0 disables it).
function Goals:SetSessionGoal(amount)
    ns.settings.goals.sessionXP = math.max(0, math.floor(amount or 0))
    ns.Tracker:GetSession().goalReached = nil
    ns:SendMessage("XPL_SETTINGS_CHANGED")
end

function Goals:OnLogin()
    self.lastRested = ns.Compat.GetRestedExperience()
    ns:RegisterEvent("UPDATE_EXHAUSTION", function() self:OnRestedChanged() end)
    ns:RegisterMessage("XPL_LEVEL_UP", function(_, oldLevel, newLevel) self:OnLevelUp(oldLevel, newLevel) end)
    ns:RegisterMessage("XPL_XP_GAINED", function() self:OnExperienceGained() end)
end
