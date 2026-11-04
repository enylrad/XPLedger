--[[----------------------------------------------------------------------------
    XPLedger - Spells
    Answers "which class abilities become available at this level?" using only
    what the running client knows, because no reliable per-level database
    exists for every flavor (WoW Forever changed the classes).

    Everything is keyed by spellID, never by name: names, ranks and icons are
    read back from the client, so they come in the game's own language.

    Two sources, both probed before use:
      spellbook  mainline clients list future spells with the level they are
                 learned at (C_SpellBook + GetSpellLevelLearned)
      trainer    every class trainer window the player opens is cached per
                 class and race (account wide), including the abilities that
                 are not available yet, so later level ups can be answered
                 without visiting the trainer

    Client differences handled here (learned from LevelUpInfo, MIT):
      - Forever's GetTrainerServiceInfo returns (name, type, ?, ?, rank) while
        Classic returns (name, rank, type, expanded); the order is detected
        from the values themselves.
      - Forever exposes the row's spellID through C_TooltipInfo; Classic needs
        a hidden tooltip and GetSpell.
      - Profession rows and hunter pet-learn rows are skipped.

    Saved data: XPLedgerDB.trainerCache = {
        version = CACHE_VERSION,
        [classFile] = { [raceFile] = { [spellID] = { level, cost } } },
    }
------------------------------------------------------------------------------]]

local _, ns = ...

local Spells = ns:NewModule("Spells")

local CACHE_VERSION = 2
local SERVICE_TYPES = { "available", "unavailable", "used" }
local KEPT_TYPES = { available = true, unavailable = true, used = true }
local SCAN_THROTTLE = 1 -- seconds

local scanning = false
local lastScan = -SCAN_THROTTLE
local scanTooltip

local function PlayerKeys()
    local _, classFile = UnitClass("player")
    local _, raceFile = UnitRace("player")
    return classFile, raceFile
end

--------------------------------------------------------------------------------
-- Spell facts (always from the client, in its language)
--------------------------------------------------------------------------------

--- Returns name, icon of a spell.
local function SpellNameAndIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then
            return ns.SafeString(info.name), info.iconID
        end
    end
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(spellID)
        return ns.SafeString(name), icon
    end
    return nil, nil
end

--- Returns the rank text of a spell ("Rank 2"), or nil.
local function SpellRank(spellID)
    local getSubtext = (C_Spell and C_Spell.GetSpellSubtext) or _G.GetSpellSubtext
    local rank = getSubtext and ns.SafeString(getSubtext(spellID))
    if rank == "" then
        return nil
    end
    return rank
end

local function IsKnown(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID) and true or false
    end
    if IsSpellKnown then
        return IsSpellKnown(spellID) and true or false
    end
    return false
end

--------------------------------------------------------------------------------
-- Trainer cache
--------------------------------------------------------------------------------

local function IsClassTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceLevelReq) then
        return false
    end
    -- Classic has an empty C_Trainer; there only IsTradeskillTrainer can tell.
    local trainer = C_Trainer
    if trainer and trainer.GetTrainerType and Enum and Enum.TrainerType
        and trainer.GetTrainerType() ~= Enum.TrainerType.General then
        return false
    end
    return not (IsTradeskillTrainer and IsTradeskillTrainer())
end

--- Returns serviceType, rank of a trainer row in either client's order.
local function ServiceInfo(index)
    local _, second, third, _, fifth = GetTrainerServiceInfo(index)
    if KEPT_TYPES[second] or second == "header" then
        return second, fifth -- Forever
    end
    return third, second     -- Classic
end

local function RowSpellID(index)
    if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local data = C_TooltipInfo.GetTrainerService(index)
        local spellType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell
        if data and (spellType == nil or data.type == spellType) then
            return ns.SafeNumber(data.id)
        end
        return nil
    end
    scanTooltip = scanTooltip or CreateFrame("GameTooltip")
    if not scanTooltip.SetTrainerService then
        return nil
    end
    scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTooltip:SetTrainerService(index)
    local _, spellID = scanTooltip:GetSpell()
    scanTooltip:Hide()
    return ns.SafeNumber(spellID)
end

local function IsPetLearn(index)
    if not IsTrainerServiceLearnSpell then
        return false
    end
    local _, isPetLearn = IsTrainerServiceLearnSpell(index)
    return isPetLearn and true or false
end

--- Shows every service type while scanning; returns the types it turned on.
local function ShowAllServices()
    local flipped = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, kind in ipairs(SERVICE_TYPES) do
            if not GetTrainerServiceTypeFilter(kind) then
                SetTrainerServiceTypeFilter(kind, true)
                flipped[#flipped + 1] = kind
            end
        end
    end
    return flipped
end

local function RecordRows(cache)
    for index = 1, GetNumTrainerServices() do
        local serviceType = ServiceInfo(index)
        if KEPT_TYPES[serviceType] then
            local level = ns.SafeNumber(GetTrainerServiceLevelReq(index))
            local cost, isProfession
            if GetTrainerServiceCost then
                cost, isProfession = GetTrainerServiceCost(index)
            end
            if level and level > 0 and not isProfession and not IsPetLearn(index) then
                local spellID = RowSpellID(index)
                if spellID then
                    cache[spellID] = { level = level, cost = ns.SafeNumber(cost) }
                end
            end
        end
    end
end

local function TrainerCacheFor(classFile, raceFile)
    local root = ns.db.trainerCache
    root[classFile] = root[classFile] or {}
    root[classFile][raceFile] = root[classFile][raceFile] or {}
    return root[classFile][raceFile]
end

local function ScanTrainer()
    -- Changing the filters fires TRAINER_UPDATE again; the throttle stops a
    -- scan from triggering the next one.
    local now = GetTime()
    if scanning or now - lastScan < SCAN_THROTTLE or not IsClassTrainer() then
        return
    end
    local classFile, raceFile = PlayerKeys()
    if not (classFile and raceFile) then
        return
    end
    lastScan = now
    scanning = true
    local flipped = {}
    local ok, err = pcall(function()
        flipped = ShowAllServices()
        RecordRows(TrainerCacheFor(classFile, raceFile))
    end)
    for _, kind in ipairs(flipped) do
        SetTrainerServiceTypeFilter(kind, false)
    end
    scanning = false
    if not ok then
        geterrorhandler()(err)
    end
end

--------------------------------------------------------------------------------
-- Spellbook (future spells)
--------------------------------------------------------------------------------

local function SpellLevelGetter()
    if C_Spell and C_Spell.GetSpellLevelLearned then
        return C_Spell.GetSpellLevelLearned
    end
    return _G.GetSpellLevelLearned
end

local function CanScanSpellBook()
    local book = C_SpellBook
    return book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo
        and book.GetSpellBookItemInfo and Enum and Enum.SpellBookItemType
        and Enum.SpellBookItemType.FutureSpell and Enum.SpellBookSpellBank
        and SpellLevelGetter() ~= nil
end

local function ScanSpellBook(level, add)
    if not CanScanSpellBook() then
        return
    end
    local book, getLevel = C_SpellBook, SpellLevelGetter()
    local future, bank = Enum.SpellBookItemType.FutureSpell, Enum.SpellBookSpellBank.Player
    for line = 1, book.GetNumSpellBookSkillLines() do
        local info = book.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide and not info.offSpecID then
            local first = info.itemIndexOffset or 0
            for index = first + 1, first + (info.numSpellBookItems or 0) do
                local item = book.GetSpellBookItemInfo(index, bank)
                local spellID = item and ns.SafeNumber(item.spellID)
                if spellID and item.itemType == future and ns.SafeNumber(getLevel(spellID)) == level then
                    add(spellID, nil)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Spells:OnInitialize()
    local cache = ns.db.trainerCache
    -- Older layouts were keyed by spell name, which breaks across languages.
    if type(cache) ~= "table" or cache.version ~= CACHE_VERSION then
        ns.db.trainerCache = { version = CACHE_VERSION }
    end
end

function Spells:OnLogin()
    ns:RegisterEvent("TRAINER_SHOW", ScanTrainer)
    ns:RegisterEvent("TRAINER_UPDATE", ScanTrainer)
end

--- Returns the class abilities first available at the given level that the
--- character does not know yet, sorted by name: a list of
--- { spellID, name, rank, icon, cost }.
function Spells:GetNewForLevel(level)
    local list, seen = {}, {}
    local function add(spellID, cost)
        if seen[spellID] or IsKnown(spellID) then
            return
        end
        seen[spellID] = true
        local name, icon = SpellNameAndIcon(spellID)
        if name then
            list[#list + 1] = { spellID = spellID, name = name, rank = SpellRank(spellID), icon = icon, cost = cost }
        end
    end

    local classFile, raceFile = PlayerKeys()
    local byClass = ns.db.trainerCache[classFile or ""]
    local cache = byClass and byClass[raceFile or ""]
    if cache then
        for spellID, entry in pairs(cache) do
            if entry.level == level then
                add(spellID, entry.cost)
            end
        end
    end

    local ok, err = pcall(ScanSpellBook, level, add)
    if not ok then
        geterrorhandler()(err)
    end

    table.sort(list, function(a, b)
        if a.name == b.name then
            return (a.rank or "") < (b.rank or "")
        end
        return a.name < b.name
    end)
    return list
end
