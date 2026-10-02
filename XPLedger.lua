--[[----------------------------------------------------------------------------
    XPLedger - Bootstrap
    Loaded last. Wires the saved variables, the module lifecycle and the slash
    commands together.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

ns:RegisterEvent("ADDON_LOADED", function(_, loadedName)
    if loadedName ~= ADDON_NAME then
        return
    end
    ns:CallModules("OnInitialize")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
    ns:CallModules("OnLogin")
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function PrintHelp()
    local L = ns.L
    ns:Print(L["HELP_HEADER"])
    for _, line in ipairs({
        "HELP_TOGGLE", "HELP_OPTIONS", "HELP_LOCK", "HELP_UNLOCK",
        "HELP_SHOW", "HELP_HIDE", "HELP_RESET", "HELP_GOAL", "HELP_GOAL_SESSION",
        "HELP_GOAL_CLEAR", "HELP_SESSION", "HELP_HELP",
    }) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. L[line])
    end
end

--- /xpl goal [<level> [days] | session <xp> | clear]
local function GoalCommand(args)
    local L, Goals = ns.L, ns.Goals
    local first, second = args:match("^(%S*)%s*(%S*)")
    if first == "" then
        local text = Goals:FormatGoal(ns.char)
        ns:Print(text or L["GOAL_NONE"])
        local sessionGoal = ns.settings.goals.sessionXP
        if sessionGoal > 0 then
            ns:Print(L["GOAL_SESSION_STATUS"]:format(ns.FormatInteger(ns.Tracker:GetSession().xp),
                ns.FormatInteger(sessionGoal)))
        end
    elseif first == "clear" then
        Goals:ClearLevelGoal()
        ns:Print(L["GOAL_CLEARED"])
    elseif first == "session" then
        local amount = tonumber(second)
        if not amount then
            ns:Print(L["HELP_GOAL_SESSION"])
            return
        end
        Goals:SetSessionGoal(amount)
        ns:Print(amount > 0 and L["GOAL_SESSION_SET"]:format(ns.FormatInteger(amount)) or L["GOAL_SESSION_OFF"])
    else
        local ok, errorKey = Goals:SetLevelGoal(tonumber(first), second ~= "" and tonumber(second) or nil)
        if ok then
            ns:Print(Goals:FormatGoal(ns.char))
        else
            ns:Print(L[errorKey])
        end
    end
end

-- Maps each subcommand to its action. Modules are resolved lazily because the
-- UI modules are optional from the point of view of the bootstrap.
local commands = {
    [""] = function() if ns.MainPanel then ns.MainPanel:Toggle() end end,
    options = function() if ns.Options then ns.Options:Open() end end,
    config = function() if ns.Options then ns.Options:Open() end end,
    lock = function() if ns.Launcher then ns.Launcher:SetLocked(true) end end,
    unlock = function() if ns.Launcher then ns.Launcher:SetLocked(false) end end,
    show = function() if ns.Launcher then ns.Launcher:SetShown(true) end end,
    hide = function() if ns.Launcher then ns.Launcher:SetShown(false) end end,
    reset = function() if ns.Launcher then ns.Launcher:ResetPosition() end end,
    goal = GoalCommand,
    session = function() if ns.Sessions then ns.Sessions:PrintCurrent() end end,
    help = PrintHelp,
}

SLASH_XPLEDGER1 = "/xpl"
SLASH_XPLEDGER2 = "/xpledger"
SlashCmdList.XPLEDGER = function(input)
    local command, args = strtrim(input or ""):lower():match("^(%S*)%s*(.-)$")
    local action = commands[command]
    if action then
        action(args)
    else
        PrintHelp()
    end
end
