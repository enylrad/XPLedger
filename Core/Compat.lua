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

--- Returns true while a pet battle is running (mainline-API clients only).
function Compat.InPetBattle()
    return C_PetBattles ~= nil and C_PetBattles.IsInBattle ~= nil and C_PetBattles.IsInBattle() == true
end

--------------------------------------------------------------------------------
-- Identity
--------------------------------------------------------------------------------

--- Returns the unique key of the logged character ("Name-Realm").
function Compat.GetCharacterKey()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName():gsub("%s", "")
    return ("%s-%s"):format(name, realm), name, realm
end
