--[[----------------------------------------------------------------------------
    XPLedger - Quest log experience
    Adds up the experience waiting in the quest log: the completed quests
    that only need to be turned in, and the whole log.
------------------------------------------------------------------------------]]

local _, ns = ...

local Quests = ns:NewModule("Quests")

local SCAN_THROTTLE = 1

Quests.completeXP = 0   -- experience of the quests ready to turn in
Quests.completeCount = 0
Quests.totalXP = 0      -- experience of every quest in the log
Quests.totalCount = 0

function Quests:Scan()
    self.scanQueued = false
    self.scannedAt = GetTime()
    local completeXP, completeCount, totalXP, totalCount = 0, 0, 0, 0
    for _, quest in ipairs(ns.Compat.GetQuestLogExperience()) do
        if quest.xp > 0 then
            totalXP, totalCount = totalXP + quest.xp, totalCount + 1
            if quest.complete then
                completeXP, completeCount = completeXP + quest.xp, completeCount + 1
            end
        end
    end
    local changed = completeXP ~= self.completeXP or totalXP ~= self.totalXP
    self.completeXP, self.completeCount = completeXP, completeCount
    self.totalXP, self.totalCount = totalXP, totalCount
    if changed then
        ns:SendMessage("XPL_STATE_CHANGED")
    end
end

--- Schedules a scan; bursts of quest log events collapse into one.
function Quests:QueueScan()
    if self.scanQueued then
        return
    end
    self.scanQueued = true
    C_Timer.After(SCAN_THROTTLE, function() self:Scan() end)
end

function Quests:OnLogin()
    local function Queue() self:QueueScan() end
    ns:RegisterEvent("QUEST_LOG_UPDATE", function()
        -- Selecting entries during a legacy scan can echo this event: ignore it.
        if self.scannedAt and GetTime() - self.scannedAt < 0.1 then
            return
        end
        Queue()
    end)
    ns:RegisterEvent("QUEST_TURNED_IN", Queue)
    ns:RegisterEvent("QUEST_ACCEPTED", Queue)
    -- Rewards scale with the level.
    ns:RegisterMessage("XPL_LEVEL_UP", Queue)
    self:QueueScan()
end
