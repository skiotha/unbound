local addonName, ns = ...

local PRINT_PREFIX = "|cff66ccff[Unbound]|r"

local DB_DEFAULTS = {
    schemaVersion = 1,
    settings = {},
}

ns.VERSION = C_AddOns.GetAddOnMetadata(addonName, "Version")

function ns.Print(...)
    print(PRINT_PREFIX, ...)
end

-- Events ---------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(loadedName)
    if loadedName ~= addonName then return end
    eventFrame:UnregisterEvent("ADDON_LOADED")

    -- SavedVariables are restored right before this event.
    UnboundDB = ns.ApplyDefaults(UnboundDB or {}, DB_DEFAULTS)
    ns.db = UnboundDB
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

for event in pairs(handlers) do
    eventFrame:RegisterEvent(event)
end

-- Slash commands -------------------------------------------------------------

local commands = {}

function commands.help()
    ns.Print("v" .. ns.VERSION .. " - commands:")
    print("  /ub help - show this list")
end

SLASH_UNBOUND1 = "/unbound"
SLASH_UNBOUND2 = "/ub"
SlashCmdList.UNBOUND = function(msg)
    local name, rest = strtrim(msg or ""):match("^(%S*)%s*(.*)$")
    name = name:lower()
    if name == "" then name = "help" end

    local command = commands[name]
    if not command then
        ns.Print("Unknown command '" .. name .. "'. Type /ub help.")
        return
    end
    command(rest)
end
