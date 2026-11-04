--[[----------------------------------------------------------------------------
    XPLedger - Zones
    Recommends leveling zones for a level, filtered by the player's faction.

    Level ranges, best source first:
      1. the Group Finder (C_LFGList activities): WoW Forever lists every
         questing zone there with its suggested range, new zones included
      2. C_Map.GetMapLevels, when the client fills it
      3. ZONE_LEVELS: the classic 1-60 ranges
    ZONE_LEVELS is also the only source of each zone's faction; zones it does
    not know (e.g. the new Forever zones) are treated as contested.

    Works in every language: the table is keyed by uiMapID, names come from
    the client (C_Map.GetMapInfo) and Group Finder activities are matched
    against those localized map names, never against English text. An
    activity that matches nothing keeps its own (already localized) name.
------------------------------------------------------------------------------]]

local _, ns = ...

local Zones = ns:NewModule("Zones")

local MAX_RESULTS = 4
local ALLIANCE, HORDE = "Alliance", "Horde"

-- { uiMapID, minLevel, maxLevel, faction (nil = contested), English name }
local ZONE_LEVELS = {
    -- Alliance
    { 1429, 1, 10, ALLIANCE, "Elwynn Forest" },
    { 1426, 1, 10, ALLIANCE, "Dun Morogh" },
    { 1438, 1, 10, ALLIANCE, "Teldrassil" },
    { 1436, 10, 20, ALLIANCE, "Westfall" },
    { 1432, 10, 20, ALLIANCE, "Loch Modan" },
    { 1439, 10, 20, ALLIANCE, "Darkshore" },
    { 1433, 15, 25, ALLIANCE, "Redridge Mountains" },
    { 1431, 18, 30, ALLIANCE, "Duskwood" },
    { 1437, 20, 30, ALLIANCE, "Wetlands" },
    -- Horde
    { 1411, 1, 10, HORDE, "Durotar" },
    { 1412, 1, 10, HORDE, "Mulgore" },
    { 1420, 1, 10, HORDE, "Tirisfal Glades" },
    { 1413, 10, 25, HORDE, "The Barrens" },
    { 1421, 10, 20, HORDE, "Silverpine Forest" },
    -- Contested
    { 1442, 15, 27, nil, "Stonetalon Mountains" },
    { 1440, 18, 30, nil, "Ashenvale" },
    { 1424, 20, 30, nil, "Hillsbrad Foothills" },
    { 1441, 25, 35, nil, "Thousand Needles" },
    { 1416, 30, 40, nil, "Alterac Mountains" },
    { 1417, 30, 40, nil, "Arathi Highlands" },
    { 1443, 30, 40, nil, "Desolace" },
    { 1434, 30, 45, nil, "Stranglethorn Vale" },
    { 1445, 35, 45, nil, "Dustwallow Marsh" },
    { 1418, 35, 45, nil, "Badlands" },
    { 1435, 35, 45, nil, "Swamp of Sorrows" },
    { 1444, 40, 50, nil, "Feralas" },
    { 1425, 40, 50, nil, "The Hinterlands" },
    { 1446, 40, 50, nil, "Tanaris" },
    { 1427, 43, 50, nil, "Searing Gorge" },
    { 1447, 45, 55, nil, "Azshara" },
    { 1419, 45, 55, nil, "Blasted Lands" },
    { 1449, 48, 55, nil, "Un'Goro Crater" },
    { 1448, 48, 55, nil, "Felwood" },
    { 1428, 50, 58, nil, "Burning Steppes" },
    { 1422, 51, 58, nil, "Western Plaguelands" },
    { 1423, 53, 60, nil, "Eastern Plaguelands" },
    { 1452, 53, 60, nil, "Winterspring" },
    { 1451, 55, 60, nil, "Silithus" },
    -- WoW Forever: starting isle of the Skyborne, shared by both factions.
    -- Its range comes from the Group Finder; 1-10 is only the fallback.
    { 2521, 1, 10, nil, "Zephras Isle" },
}

-- Leading articles dropped before comparing names ("The Hinterlands" in the
-- Group Finder is "Hinterlands" on the map, and the same happens in other
-- languages).
local ARTICLES = {
    "the", "el", "la", "los", "las", "le", "les", "l'", "der", "die", "das", "o", "a", "os", "as", "il", "lo",
}

local FALLBACK_WORLD_MAP = 947 -- Azeroth

local zones -- list of { mapID?, min, max, faction?, name }; .complete once the Group Finder answered

local function MapName(mapID, fallback)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and ns.SafeString(info.name) or fallback
end

--- Reads the level range of every zone the client reports, keyed by map id.
local function ReadClientRanges()
    local ranges = {}
    if not (C_Map and C_Map.GetMapLevels and C_Map.GetMapChildrenInfo and Enum and Enum.UIMapType) then
        return ranges
    end
    local world = C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID() or FALLBACK_WORLD_MAP
    local continents = C_Map.GetMapChildrenInfo(world, Enum.UIMapType.Continent, false) or {}
    for _, continent in ipairs(continents) do
        local children = C_Map.GetMapChildrenInfo(continent.mapID, Enum.UIMapType.Zone, false) or {}
        for _, child in ipairs(children) do
            local minLevel, maxLevel = C_Map.GetMapLevels(child.mapID)
            minLevel, maxLevel = ns.SafeNumber(minLevel), ns.SafeNumber(maxLevel)
            if minLevel and maxLevel and minLevel > 0 and maxLevel >= minLevel then
                ranges[child.mapID] = { min = minLevel, max = maxLevel, name = ns.SafeString(child.name) }
            end
        end
    end
    return ranges
end

--- Lowercases a name and strips a leading article, spaces and punctuation, so
--- the Group Finder and the map spell a zone the same way. Non ASCII bytes
--- (accents, other alphabets) are kept.
local function NormalName(name)
    local text = name:lower()
    for _, article in ipairs(ARTICLES) do
        local prefix = article:sub(-1) == "'" and article or article .. " "
        if text:sub(1, #prefix) == prefix then
            text = text:sub(#prefix + 1)
            break
        end
    end
    return (text:gsub("[%s%p]", ""))
end

local function LevelField(value)
    value = ns.SafeNumber(value)
    if value and value > 0 then
        return value
    end
    return nil
end

--- Reads every Group Finder activity as { name, min, max }, grouped by
--- category. Empty until the client has loaded the Group Finder data.
local function ReadFinderCategories()
    local result = {}
    local finder = C_LFGList
    if not (finder and finder.GetAvailableCategories and finder.GetAvailableActivities
        and finder.GetActivityInfoTable) then
        return result
    end
    for _, categoryID in ipairs(finder.GetAvailableCategories() or {}) do
        local activities = {}
        for _, activityID in ipairs(finder.GetAvailableActivities(categoryID) or {}) do
            local info = finder.GetActivityInfoTable(activityID)
            if info then
                local name = ns.SafeString(info.fullName) or ns.SafeString(info.shortName)
                local minLevel = LevelField(info.minLevelSuggestion) or LevelField(info.minLevel)
                local maxLevel = LevelField(info.maxLevelSuggestion) or LevelField(info.maxLevel)
                if name and minLevel and maxLevel and maxLevel >= minLevel then
                    activities[#activities + 1] = { name = name, min = minLevel, max = maxLevel }
                end
            end
        end
        result[#result + 1] = activities
    end
    return result
end

--- Applies the Group Finder ranges. Only categories where at least one
--- activity is a known zone are taken (the others are dungeons, raids...).
--- Returns true when the finder answered.
local function ApplyFinderRanges(byName)
    local categories = ReadFinderCategories()
    local answered = false
    for _, activities in ipairs(categories) do
        local isZones = false
        for _, activity in ipairs(activities) do
            if byName[NormalName(activity.name)] then
                isZones = true
                break
            end
        end
        if isZones then
            answered = true
            for _, activity in ipairs(activities) do
                local key = NormalName(activity.name)
                local zone = byName[key]
                if not zone then
                    zone = { name = activity.name }
                    zones[#zones + 1] = zone
                    byName[key] = zone
                end
                zone.min, zone.max = activity.min, activity.max
            end
        end
    end
    return answered
end

--- Builds the zone list: table rows first, then the map API ranges, then the
--- Group Finder ranges, each one overriding the previous.
local function Build()
    zones = {}
    local byName, byMap = {}, {}
    for _, row in ipairs(ZONE_LEVELS) do
        local zone = {
            mapID = row[1],
            min = row[2],
            max = row[3],
            faction = row[4],
            name = MapName(row[1], row[5]),
        }
        zones[#zones + 1] = zone
        byMap[zone.mapID] = zone
        byName[NormalName(zone.name)] = zone
    end

    local ok, ranges = pcall(ReadClientRanges)
    if not ok then
        geterrorhandler()(ranges)
        ranges = {}
    end
    for mapID, client in pairs(ranges) do
        local zone = byMap[mapID]
        if not zone then
            zone = { mapID = mapID, name = client.name or MapName(mapID, tostring(mapID)) }
            zones[#zones + 1] = zone
            byMap[mapID] = zone
            byName[NormalName(zone.name)] = zone
        end
        zone.min, zone.max = client.min, client.max
    end

    local answered
    ok, answered = pcall(ApplyFinderRanges, byName)
    if not ok then
        geterrorhandler()(answered)
        answered = false
    end
    -- The Group Finder may not be loaded yet: try again next time.
    zones.complete = answered
end

--- Returns up to MAX_RESULTS zones for the level, without the enemy faction's
--- zones; the player's own faction first, then by closeness of the range
--- middle to the level. Each entry is { name, min, max, faction }.
function Zones:GetRecommended(level)
    if not (zones and zones.complete) then
        Build()
    end
    local faction = UnitFactionGroup("player")
    local maxLevel = ns.Compat.GetMaxLevel()
    local list = {}
    for _, zone in ipairs(zones) do
        -- A zone open to every level (retail housing areas and the like)
        -- recommends nothing.
        local everyLevel = zone.min <= 1 and zone.max >= maxLevel
        if not everyLevel and zone.min <= level and level <= zone.max
            and (zone.faction == nil or zone.faction == faction) then
            list[#list + 1] = zone
        end
    end
    table.sort(list, function(a, b)
        local aOwn, bOwn = a.faction ~= nil, b.faction ~= nil
        if aOwn ~= bOwn then
            return aOwn
        end
        local aDistance = math.abs((a.min + a.max) / 2 - level)
        local bDistance = math.abs((b.min + b.max) / 2 - level)
        if aDistance ~= bDistance then
            return aDistance < bDistance
        end
        return a.name < b.name
    end)
    for i = #list, MAX_RESULTS + 1, -1 do
        list[i] = nil
    end
    return list
end
