--[[----------------------------------------------------------------------------
    XPLedger - Compatibility layer
    Hides the API differences between game flavors behind a small interface.

    Supported flavors:
      retail   Midnight and later (mainline client, 12.x)
      forever  WoW: Forever ("Camelot"): runs the mainline UI and API but
               reports a 1.x build and the mainline WOW_PROJECT_ID
      era      Classic Era / Anniversary realms (legacy classic API)
      classic  Classic progression realms (TBC, Wrath, Cata, Mists...)

    Rule of thumb: always probe for an API instead of branching on the flavor.
    The flavor is only used for display and for storing alongside records.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local Compat = {}
ns.Compat = Compat

--------------------------------------------------------------------------------
-- Flavor detection
--------------------------------------------------------------------------------

local _, _, _, interfaceVersion = GetBuildInfo()
Compat.interfaceVersion = interfaceVersion or 0

local function DetectFlavor()
    local projectID = WOW_PROJECT_ID
    -- Future-proofing: if Blizzard ever gives Forever its own project constant.
    local foreverID = _G.WOW_PROJECT_CAMELOT or _G.WOW_PROJECT_FOREVER
    if foreverID and projectID == foreverID then
        return "forever"
    end
    if projectID == WOW_PROJECT_MAINLINE then
        -- Forever shares the mainline project id but ships a 1.x build.
        if Compat.interfaceVersion < 20000 then
            return "forever"
        end
        return "retail"
    end
    if WOW_PROJECT_CLASSIC and projectID == WOW_PROJECT_CLASSIC then
        return "era"
    end
    return "classic"
end

Compat.flavor = DetectFlavor()
Compat.isMainlineAPI = Compat.flavor == "retail" or Compat.flavor == "forever"

--------------------------------------------------------------------------------
-- Generic API shims
--------------------------------------------------------------------------------

--- Reads a TOC metadata field of this addon.
function Compat.GetAddOnMetadata(field)
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    return getter and getter(ADDON_NAME, field)
end

--- Template name required to use SetBackdrop on frames (nil when not needed).
Compat.BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

--- Returns the class color of a class file name as r, g, b.
function Compat.GetClassColor(classFile)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local color = classFile and colors and colors[classFile]
    if color then
        return color.r, color.g, color.b
    end
    return 0.8, 0.8, 0.8
end

--- Returns true while the player is in combat (secret-safe).
function Compat.InCombat()
    if InCombatLockdown() then
        return true
    end
    local affecting = UnitAffectingCombat("player")
    return not ns.IsSecret(affecting) and affecting == true
end

--- Returns true while the player is underwater, or at least swimming on
--- clients without IsSubmerged (secret-safe).
function Compat.IsUnderwater()
    local check = IsSubmerged or IsSwimming
    local underwater = check and check()
    return not ns.IsSecret(underwater) and (underwater == true or underwater == 1)
end

--- Returns true while the player is flagged away from keyboard (secret-safe).
function Compat.IsAFK()
    local afk = UnitIsAFK and UnitIsAFK("player")
    return not ns.IsSecret(afk) and (afk == true or afk == 1)
end

--- Returns true when an API answer is a plain true (secret-safe).
local function IsTrue(value)
    return not ns.IsSecret(value) and (value == true or value == 1)
end

--- Returns true while the player lies dead, before releasing the spirit.
function Compat.IsDead()
    return IsTrue(UnitIsDead("player"))
end

--- Returns true while the player is a ghost (spirit released).
function Compat.IsGhost()
    return UnitIsGhost ~= nil and IsTrue(UnitIsGhost("player"))
end

--- Returns true when the current target is a dead enemy (secret-safe).
function Compat.IsTargetDead()
    return IsTrue(UnitExists("target")) and IsTrue(UnitIsDead("target"))
        and IsTrue(UnitCanAttack("player", "target"))
end

--- Returns the player's health as a fraction, or nil when the client hides it.
function Compat.GetHealthPercent()
    local health = ns.SafeNumber(UnitHealth("player"))
    local maxHealth = ns.SafeNumber(UnitHealthMax("player"))
    if not health or not maxHealth or maxHealth <= 0 then
        return nil
    end
    return health / maxHealth
end

--- Returns the localized name of a spell, or nil.
function Compat.GetSpellName(spellID)
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    return ns.SafeString(name)
end

--------------------------------------------------------------------------------
-- Experience
--------------------------------------------------------------------------------

--- Returns the level cap that applies to this character right now.
function Compat.GetMaxLevel()
    local maxLevel
    if GetMaxLevelForPlayerExpansion then
        maxLevel = ns.SafeNumber(GetMaxLevelForPlayerExpansion())
    end
    if (not maxLevel or maxLevel <= 0) and GetMaxPlayerLevel then
        maxLevel = ns.SafeNumber(GetMaxPlayerLevel())
    end
    if not maxLevel or maxLevel <= 0 then
        maxLevel = MAX_PLAYER_LEVEL or 60
    end
    -- Trial and restricted accounts have a lower cap.
    if GameLimitedMode_IsActive and GameLimitedMode_IsActive() and GetRestrictedAccountData then
        local restrictedLevel = ns.SafeNumber(GetRestrictedAccountData())
        if restrictedLevel and restrictedLevel > 0 then
            maxLevel = math.min(maxLevel, restrictedLevel)
        end
    end
    return maxLevel
end

--- Returns true when the character has reached the level cap. Unlike
--- IsExperienceBlocked, experience turned off by the player does not count.
function Compat.IsAtMaxLevel()
    local level = ns.SafeNumber(UnitLevel("player"))
    return level ~= nil and level >= Compat.GetMaxLevel()
end

--- Returns current xp, xp needed for the level and the level.
--- Any of them is nil when the client hands out a secret value.
function Compat.GetPlayerExperience()
    return ns.SafeNumber(UnitXP("player")),
        ns.SafeNumber(UnitXPMax("player")),
        ns.SafeNumber(UnitLevel("player"))
end

--- Returns the rested experience pool (0 when not rested).
function Compat.GetRestedExperience()
    return ns.SafeNumber(GetXPExhaustion and GetXPExhaustion()) or 0
end

--- Returns true while the character is in an inn or a city (secret-safe).
function Compat.IsResting()
    local resting = IsResting and IsResting()
    return not ns.IsSecret(resting) and resting == true
end

--- Returns true when the character cannot gain experience at all.
function Compat.IsExperienceBlocked()
    if IsXPUserDisabled and IsXPUserDisabled() then
        return true
    end
    local _, maxXP, level = Compat.GetPlayerExperience()
    if level and level >= Compat.GetMaxLevel() then
        return true
    end
    return maxXP ~= nil and maxXP <= 0
end

--- Returns true when experience was turned off by the player (XP elixir / NPC).
function Compat.IsExperienceDisabledByUser()
    return IsXPUserDisabled ~= nil and IsXPUserDisabled() == true
end

--------------------------------------------------------------------------------
-- Quest log
--------------------------------------------------------------------------------

local function SafeXP(value)
    value = ns.SafeNumber(value)
    return value and value > 0 and value or 0
end

--- Returns the quests of the log as an array of { questID, xp, complete }.
--- Quests under collapsed headers are only visible on mainline clients.
function Compat.GetQuestLogExperience()
    local quests = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and GetQuestLogRewardXP then
        -- Mainline API: every entry is addressable by quest id.
        local count = ns.SafeNumber(C_QuestLog.GetNumQuestLogEntries()) or 0
        for i = 1, count do
            local info = C_QuestLog.GetInfo(i)
            local questID = info and ns.SafeNumber(info.questID)
            if questID and questID > 0 and not info.isHeader and not info.isHidden then
                local complete = (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID))
                    or (C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID))
                quests[#quests + 1] = {
                    questID = questID,
                    xp = SafeXP(GetQuestLogRewardXP(questID)),
                    complete = complete == true,
                }
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle and GetQuestLogRewardXP and SelectQuestLogEntry then
        -- Legacy API: the reward functions read the selected entry.
        local selected = GetQuestLogSelection and GetQuestLogSelection() or 0
        local count = ns.SafeNumber(GetNumQuestLogEntries()) or 0
        for i = 1, count do
            local _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            if not isHeader then
                SelectQuestLogEntry(i)
                quests[#quests + 1] = {
                    questID = ns.SafeNumber(questID) or 0,
                    xp = SafeXP(GetQuestLogRewardXP()),
                    complete = isComplete == 1 or isComplete == true,
                }
            end
        end
        SelectQuestLogEntry(selected)
    end
    return quests
end

--------------------------------------------------------------------------------
-- Activity context
--------------------------------------------------------------------------------

-- Maps the instance type reported by IsInInstance() to a context bucket.
local INSTANCE_CONTEXTS = {
    party = "dungeon",
    raid = "raid",
    pvp = "battleground",
    arena = "battleground",
    scenario = "scenario",
}

--- Returns where the player currently is: world, dungeon, raid, battleground
--- or scenario (scenarios and delves).
function Compat.GetActivityContext()
    local inInstance, instanceType = IsInInstance()
    if ns.IsSecret(inInstance) or ns.IsSecret(instanceType) then
        return "world"
    end
    if inInstance and instanceType then
        return INSTANCE_CONTEXTS[instanceType] or "world"
    end
    return "world"
end

--- Returns the instance the player is in as a table { name, instanceType,
--- difficultyName, instanceID }, or nil outside instances or when the client
--- hides the values.
function Compat.GetInstanceInfo()
    if not GetInstanceInfo then
        return nil
    end
    local name, instanceType, _, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    name, instanceType = ns.SafeString(name), ns.SafeString(instanceType)
    if not name or not instanceType or instanceType == "none" then
        return nil
    end
    return {
        name = name,
        instanceType = instanceType,
        difficultyName = ns.SafeString(difficultyName),
        instanceID = ns.SafeNumber(instanceID) or name,
    }
end

--- Returns true while a pet battle is running (mainline-API clients only).
function Compat.InPetBattle()
    return C_PetBattles ~= nil and C_PetBattles.IsInBattle ~= nil and C_PetBattles.IsInBattle() == true
end

--------------------------------------------------------------------------------
-- Identity
--------------------------------------------------------------------------------

--- Returns the surname of the logged character, or nil. Forever characters
--- have a first name and a surname, and only the pair is unique: UnitName
--- returns the surname as its second value (other flavors: the realm, which
--- is nil for the player).
function Compat.GetPlayerSurname()
    if Compat.flavor ~= "forever" and not (C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname) then
        return nil
    end
    local _, surname = UnitName("player")
    surname = ns.SafeString(surname)
    return surname ~= "" and surname or nil
end

--- Separator between a first name and a surname.
function Compat.GetSurnameSeparator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    return consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

--- Returns the unique key of the logged character ("Name-Realm", or
--- "Name Surname-Realm" on Forever) plus the name, realm and surname.
function Compat.GetCharacterKey()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName():gsub("%s", "")
    local surname = Compat.GetPlayerSurname()
    local fullName = surname and (name .. Compat.GetSurnameSeparator() .. surname) or name
    return ("%s-%s"):format(fullName, realm), name, realm, surname
end
