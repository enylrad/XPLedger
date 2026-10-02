--[[----------------------------------------------------------------------------
    XPLedger - Database
    Owns the account-wide saved variable XPLedgerDB: defaults, schema
    migrations and character record management.

    Layout:
      XPLedgerDB = {
          schema     = <number>,
          settings   = { ... see DEFAULT_SETTINGS ... },
          characters = {
              ["Name-Realm"] = {
                  name, realm, class, race, faction, flavor, level,
                  firstSeen, lastSeen,
                  played, playedAt,             -- last /played total and when it was read
                  launcherPosition,             -- used when positions are per character
                  levels  = { [level] = <level record, see History> },
                  totals  = { xp, kills, quests, sources = {}, contexts = {} },
                  samples = { t = {}, v = {} }, -- progress over time (level + fraction)
                  session = { ... see Tracker },
              },
          },
      }
------------------------------------------------------------------------------]]

local _, ns = ...

local Database = ns:NewModule("Database")

local SCHEMA_VERSION = 1

local DEFAULT_SETTINGS = {
    locale = "auto",
    style = "blizzard",   -- interface skin: "blizzard" (native) or "minimal"
    rateWindow = 15,      -- minutes used by the rolling XP/hour rate
    afkThreshold = 5,     -- minutes without XP after which time stops counting
    dingSummary = true,
    silentPlayed = true,
    launcher = {
        shown = true,
        locked = false,
        hideAtMax = true,
        perCharacter = false,
        scale = 1,
        alpha = 1,
        textMode = "eta",
    },
    panel = {
        tab = "overview",
        range = "session",
        sourcesScope = "level",
    },
}

local CHARACTER_DEFAULTS = {
    levels = {},
    totals = { xp = 0, kills = 0, quests = 0, sources = {}, contexts = {} },
    samples = { t = {}, v = {} },
    session = {},
}

-- Ordered list of migrations. Each entry upgrades the database to `version`.
local MIGRATIONS = {
    -- { version = 2, run = function(db) ... end },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Database:OnInitialize()
    local db = _G.XPLedgerDB
    if type(db) ~= "table" then
        db = { schema = SCHEMA_VERSION }
        _G.XPLedgerDB = db
    end

    self:Migrate(db)

    db.settings = ns.ApplyDefaults(type(db.settings) == "table" and db.settings or {}, DEFAULT_SETTINGS)
    db.characters = type(db.characters) == "table" and db.characters or {}

    ns.db = db
    ns.settings = db.settings
    ns:SetLocale(db.settings.locale)
    -- The skin must be active before any frame is created (PLAYER_LOGIN).
    ns.Theme:Init(db.settings.style)
end

function Database:OnLogin()
    local key, name, realm = ns.Compat.GetCharacterKey()
    local record = ns.db.characters[key]
    if type(record) ~= "table" then
        record = { firstSeen = time() }
        ns.db.characters[key] = record
    end
    ns.ApplyDefaults(record, CHARACTER_DEFAULTS)

    local _, classFile = UnitClass("player")
    local _, raceFile = UnitRace("player")
    record.name = name
    record.realm = realm
    record.class = classFile
    record.race = raceFile
    record.faction = UnitFactionGroup("player")
    record.flavor = ns.Compat.flavor
    record.level = ns.SafeNumber(UnitLevel("player")) or record.level
    record.lastSeen = time()

    ns.char = record
    ns.charKey = key
end

--------------------------------------------------------------------------------
-- Schema migrations
--------------------------------------------------------------------------------

function Database:Migrate(db)
    db.schema = db.schema or SCHEMA_VERSION
    for i = 1, #MIGRATIONS do
        local migration = MIGRATIONS[i]
        if db.schema < migration.version then
            migration.run(db)
            db.schema = migration.version
        end
    end
end

--------------------------------------------------------------------------------
-- Character records
--------------------------------------------------------------------------------

--- Returns the record of a character key, or nil.
function Database:GetCharacter(key)
    return ns.db and ns.db.characters[key]
end

--- Returns all characters as an array of { key, record } sorted by level
--- (highest first) and then by name.
function Database:GetCharacterList()
    local list = {}
    for key, record in pairs(ns.db.characters) do
        list[#list + 1] = { key = key, record = record }
    end
    table.sort(list, function(a, b)
        local levelA, levelB = a.record.level or 0, b.record.level or 0
        if levelA ~= levelB then
            return levelA > levelB
        end
        return a.key < b.key
    end)
    return list
end

--- Returns the number of tracked characters.
function Database:CountCharacters()
    local count = 0
    for _ in pairs(ns.db.characters) do
        count = count + 1
    end
    return count
end

--- Wipes the tracked history of a character while keeping its identity.
function Database:ResetCharacter(key)
    local record = ns.db.characters[key]
    if not record then
        return
    end
    record.levels = nil
    record.totals = nil
    record.samples = nil
    record.session = nil
    ns.ApplyDefaults(record, CHARACTER_DEFAULTS)
    ns:SendMessage("XPL_DATA_RESET", key)
end

--- Removes a character completely. The logged character is reset instead.
function Database:DeleteCharacter(key)
    if key == ns.charKey then
        self:ResetCharacter(key)
        return
    end
    ns.db.characters[key] = nil
    ns:SendMessage("XPL_DATA_RESET", key)
end

--- Wipes the history of every character.
function Database:ResetAll()
    for key in pairs(ns.db.characters) do
        if key ~= ns.charKey then
            ns.db.characters[key] = nil
        end
    end
    self:ResetCharacter(ns.charKey)
end
