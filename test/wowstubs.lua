-- Minimal WoW API surface for running addon code outside the client.

local frames = {}
local metadata = {}

SlashCmdList = {}

WowStub = {
    -- Every line passed to print() and joined.
    printed = {},
}

-- Clears global state left behind by a previous addon load.
-- `savedVariables` lists the global names declared in the TOC's ## SavedVariables.
function WowStub.reset(savedVariables, tocMetadata)
    frames = {}
    metadata = tocMetadata or {}
    WowStub.printed = {}
    SlashCmdList = {}
    for key in pairs(_G) do
        if type(key) == "string" and key:find("^SLASH_") then
            _G[key] = nil
        end
    end
    for _, name in ipairs(savedVariables or {}) do
        _G[name] = nil
    end
end

-- Delivers `event` to every frame registered for it.
function WowStub.fireEvent(event, ...)
    for _, frame in ipairs(frames) do
        local onEvent = frame.scripts.OnEvent
        if frame.events[event] and onEvent then
            onEvent(frame, event, ...)
        end
    end
end

-- Runs a typed slash command line, i.e. as "/ub help".
function WowStub.runSlash(line)
    local typed, rest = line:match("^(/%S+)%s*(.-)$")
    typed = typed and typed:lower()
    for key, handler in pairs(SlashCmdList) do
        local i = 1
        while _G["SLASH_" .. key .. i] do
            if _G["SLASH_" .. key .. i]:lower() == typed then
                handler(rest)
                return
            end
            i = i + 1
        end
    end
    error("no slash command registered for " .. tostring(typed), 2)
end

-- Frames ---------------------------------------------------------------------

local Frame = {}
Frame.__index = Frame

function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:IsEventRegistered(event) return self.events[event] == true end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end

function CreateFrame(frameType, name)
    local frame = setmetatable({ frameType = frameType, events = {}, scripts = {} }, Frame)
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

-- API ------------------------------------------------------------------------

C_AddOns = {
    GetAddOnMetadata = function(_, field)
        return metadata[field]
    end,
}

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    WowStub.printed[#WowStub.printed + 1] = table.concat(parts, " ")
end

-- Lua extensions the client adds as globals -----------------------------------

function strtrim(str, chars)
    if not chars then
        return (str:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local class = "[" .. chars:gsub("[%%%]%^%-]", "%%%0") .. "]"
    return (str:gsub("^" .. class .. "+", ""):gsub(class .. "+$", ""))
end

function wipe(t)
    for key in pairs(t) do t[key] = nil end
    return t
end

tinsert = table.insert
tremove = table.remove
