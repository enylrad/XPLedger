--[[----------------------------------------------------------------------------
    XPLedger - Core
    Addon namespace, event dispatching, internal message bus and shared helpers.

    Every other file receives the same private namespace table (`ns`) through
    the vararg passed by the client when the file is loaded.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.title = "XPLedger"

-- Expose the namespace globally for debugging (/dump XPLedger) and for the
-- addon compartment callbacks, which must be reachable by global name.
_G.XPLedger = ns

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------

-- Modules are plain tables stored on the namespace. The bootstrap calls their
-- optional lifecycle hooks in registration order (which follows the TOC order):
--   module:OnInitialize()  saved variables are available (ADDON_LOADED)
--   module:OnLogin()       character data is available (PLAYER_LOGIN)
ns.modules = {}

--- Creates and registers a new module, also reachable as ns[name].
function ns:NewModule(name)
    local module = { moduleName = name }
    ns[name] = module
    ns.modules[#ns.modules + 1] = module
    return module
end

--- Invokes a lifecycle hook on every module that implements it.
function ns:CallModules(hook, ...)
    for i = 1, #ns.modules do
        local module = ns.modules[i]
        if module[hook] then
            module[hook](module, ...)
        end
    end
end

--------------------------------------------------------------------------------
-- Secret value guards
--------------------------------------------------------------------------------

-- Since Midnight (12.0) some values handed to addons can be "secret": they can
-- be passed around but any arithmetic, comparison or string operation on them
-- raises an error. These helpers make the rest of the code defensive by design.
local issecretvalue = _G.issecretvalue

--- Returns true when the given value is a secret value that must not be inspected.
function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

--- Returns the value when it is a plain number, nil otherwise (secret or wrong type).
function ns.SafeNumber(value)
    if ns.IsSecret(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

--- Returns the value when it is a plain string, nil otherwise (secret or wrong type).
function ns.SafeString(value)
    if ns.IsSecret(value) or type(value) ~= "string" then
        return nil
    end
    return value
end

--------------------------------------------------------------------------------
-- Game event dispatching
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

--- Checks whether the running client knows an event, so registering it is safe.
local function IsEventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event)
    end
    -- Older clients: probe by registering on a throwaway frame.
    local probe = CreateFrame("Frame")
    local ok = pcall(probe.RegisterEvent, probe, event)
    probe:UnregisterAllEvents()
    return ok
end

--- Registers a handler for a game event. Several handlers per event are allowed.
--- Events unknown to the running client are ignored and false is returned.
--- @param event string
--- @param handler fun(event: string, ...)
--- @return boolean registered
function ns:RegisterEvent(event, handler)
    local handlers = eventHandlers[event]
    if not handlers then
        if not IsEventValid(event) then
            return false
        end
        handlers = {}
        eventHandlers[event] = handlers
        eventFrame:RegisterEvent(event)
    end
    handlers[#handlers + 1] = handler
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handlers = eventHandlers[event]
    if not handlers then
        return
    end
    for i = 1, #handlers do
        handlers[i](event, ...)
    end
end)

--------------------------------------------------------------------------------
-- Internal message bus (decouples tracking logic from the UI)
--------------------------------------------------------------------------------

local messageHandlers = {}

--- Subscribes to an internal addon message.
function ns:RegisterMessage(message, handler)
    local handlers = messageHandlers[message]
    if not handlers then
        handlers = {}
        messageHandlers[message] = handlers
    end
    handlers[#handlers + 1] = handler
end

--- Broadcasts an internal addon message to every subscriber.
function ns:SendMessage(message, ...)
    local handlers = messageHandlers[message]
    if not handlers then
        return
    end
    for i = 1, #handlers do
        handlers[i](message, ...)
    end
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

local CHAT_PREFIX = "|cff4fc3f7XPLedger|r: "

--- Prints a message to the default chat frame with the addon prefix.
function ns:Print(message, ...)
    if select("#", ...) > 0 then
        message = message:format(...)
    end
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(message))
end

--------------------------------------------------------------------------------
-- Generic helpers
--------------------------------------------------------------------------------

--- Clamps a number into the [low, high] range.
function ns.Clamp(value, low, high)
    if value < low then
        return low
    elseif value > high then
        return high
    end
    return value
end

--- Rounds a number to the given amount of decimals.
function ns.Round(value, decimals)
    local factor = 10 ^ (decimals or 0)
    return math.floor(value * factor + 0.5) / factor
end

--- Recursively fills missing keys of `target` with copies of `defaults`.
function ns.ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            ns.ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

--- Returns a deep copy of a plain data table.
function ns.DeepCopy(source)
    if type(source) ~= "table" then
        return source
    end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = ns.DeepCopy(value)
    end
    return copy
end

--- Formats a large number in a compact way (1234 -> 1.2k, 2500000 -> 2.5M).
function ns.FormatNumber(value)
    value = value or 0
    local absolute = math.abs(value)
    if absolute >= 1e6 then
        return ("%.1fM"):format(value / 1e6)
    elseif absolute >= 1e4 then
        return ("%.0fk"):format(value / 1e3)
    elseif absolute >= 1e3 then
        return ("%.1fk"):format(value / 1e3)
    end
    return tostring(math.floor(value + 0.5))
end

--- Formats a number with thousands separators (1234567 -> 1,234,567).
function ns.FormatInteger(value)
    value = math.floor((value or 0) + 0.5)
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value)
    end
    local formatted = tostring(value)
    local count
    repeat
        formatted, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until count == 0
    return formatted
end

--- Formats a duration in seconds. Uses the localized unit abbreviations.
--- @param seconds number|nil
--- @param precise boolean|nil include seconds for short durations
function ns.FormatDuration(seconds, precise)
    local L = ns.L
    if not seconds or seconds ~= seconds or seconds == math.huge or seconds < 0 then
        return L["DURATION_UNKNOWN"]
    end
    seconds = math.floor(seconds + 0.5)
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if days > 0 then
        return L["DURATION_DAYS_HOURS"]:format(days, hours)
    elseif hours > 0 then
        return L["DURATION_HOURS_MINUTES"]:format(hours, minutes)
    elseif minutes > 0 then
        if precise and minutes < 10 then
            return L["DURATION_MINUTES_SECONDS"]:format(minutes, secs)
        end
        return L["DURATION_MINUTES"]:format(minutes)
    end
    return L["DURATION_SECONDS"]:format(secs)
end

--- Returns the colored name of a class using the client's class colors.
function ns.ColorizeByClass(text, classFile)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local color = classFile and colors and colors[classFile]
    if color then
        return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, text)
    end
    return text
end
