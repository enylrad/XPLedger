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
        "HELP_SHOW", "HELP_HIDE", "HELP_RESET", "HELP_HELP",
    }) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. L[line])
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
    help = PrintHelp,
}

SLASH_XPLEDGER1 = "/xpl"
SLASH_XPLEDGER2 = "/xpledger"
SlashCmdList.XPLEDGER = function(input)
    local command = strtrim(input or ""):lower()
    local action = commands[command]
    if action then
        action()
    else
        PrintHelp()
    end
end
