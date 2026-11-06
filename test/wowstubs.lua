-- Minimal WoW API surface for running addon code outside the client.

local frames = {}
local metadata = {}
local callbacks = {}
local timers = {}

SlashCmdList = {}

-- Blizzard's slash commands for chat types (GlobalStrings), used in history lines.
local CHAT_SLASH_COMMANDS = {
    SLASH_SAY1 = "/s", SLASH_EMOTE1 = "/e", SLASH_YELL1 = "/y", SLASH_PARTY1 = "/p",
    SLASH_WHISPER1 = "/w", SLASH_GUILD1 = "/g",
}

WowStub = {
    -- Every line passed to print() and joined.
    printed = {},
    -- Every C_ChatInfo.SendChatMessage call: { text, chatType, languageID, target }.
    sent = {},
    inInstance = false,
    lockdown = false,
    -- What ChatFrameUtil.GetActiveWindow() returns.
    activeWindow = nil,
    -- Values issecretvalue() reports as secret.
    secretValues = {},
}

-- Clears global state left behind by a previous addon load.
-- `savedVariables` lists the global names declared in the TOC's ## SavedVariables.
function WowStub.reset(savedVariables, tocMetadata)
    frames = {}
    callbacks = {}
    timers = {}
    metadata = tocMetadata or {}
    WowStub.printed = {}
    WowStub.sent = {}
    WowStub.inInstance = false
    WowStub.lockdown = false
    WowStub.activeWindow = nil
    WowStub.secretValues = {}
    SlashCmdList = {}
    for key in pairs(_G) do
        if type(key) == "string" and key:find("^SLASH_") then
            _G[key] = nil
        end
    end
    for key, command in pairs(CHAT_SLASH_COMMANDS) do
        _G[key] = command
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

-- Runs every pending C_Timer callback, including ones scheduled meanwhile.
function WowStub.runTimers()
    while #timers > 0 do
        local due = timers
        timers = {}
        for _, timer in ipairs(due) do timer.callback() end
    end
end

-- Presses Enter in a chat box: Blizzard's SendText, then ClearChat.
function WowStub.sendText(editBox)
    EventRegistry:TriggerEvent("ChatFrame.OnEditBoxPreSendText", editBox)
    local chatType = editBox:GetChatType()
    local text = editBox:GetText()
    if text:find("%s*[^%s]+") then
        local target
        if chatType == "WHISPER" then
            target = editBox:GetTellTarget()
        elseif chatType == "CHANNEL" then
            target = editBox:GetChannelTarget()
        end
        C_ChatInfo.SendChatMessage(text, chatType, editBox.languageID, target)
        editBox:AddHistoryLine((_G["SLASH_" .. chatType .. "1"] or "") .. " " .. text)
    end
    editBox:SetText("")
end

-- A chat window's edit box with Blizzard's default limits (ChatFrameEditBoxTemplate).
function WowStub.newChatEditBox(fields)
    local box = {
        text = "",
        chatType = "SAY",
        languageID = 7,
        history = {},
        maxBytes = 1280,
        maxLetters = 0,
        visibleBytes = 255,
    }
    for key, value in pairs(fields or {}) do box[key] = value end
    function box:GetText() return self.text end
    function box:SetText(text) self.text = text end
    function box:GetChatType() return self.chatType end
    function box:GetTellTarget() return self.tellTarget end
    function box:GetChannelTarget() return self.channelTarget end
    function box:AddHistoryLine(line) self.history[#self.history + 1] = line end
    function box:GetMaxBytes() return self.maxBytes end
    function box:SetMaxBytes(value) self.maxBytes = value end
    function box:GetMaxLetters() return self.maxLetters end
    function box:SetMaxLetters(value) self.maxLetters = value end
    function box:GetVisibleTextByteLimit() return self.visibleBytes end
    function box:SetVisibleTextByteLimit(value) self.visibleBytes = value end
    return box
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

C_ChatInfo = {
    -- The client raises a Lua error for a message over 255 bytes and sends nothing.
    SendChatMessage = function(text, chatType, languageID, target)
        if #text > 255 then error("message over 255 bytes", 2) end
        WowStub.sent[#WowStub.sent + 1] = { text, chatType, languageID, target }
    end,
    InChatMessagingLockdown = function()
        return WowStub.lockdown
    end,
}

C_Timer = {
    After = function(seconds, callback)
        timers[#timers + 1] = { seconds = seconds, callback = callback }
    end,
}

-- Blizzard's CallbackRegistryMixin: one callback per owner and event, called with the
-- owner first.
EventRegistry = {
    RegisterCallback = function(_, event, func, owner)
        callbacks[event] = callbacks[event] or {}
        callbacks[event][owner] = func
    end,
    UnregisterCallback = function(_, event, owner)
        if callbacks[event] then callbacks[event][owner] = nil end
    end,
    TriggerEvent = function(_, event, ...)
        for owner, func in pairs(callbacks[event] or {}) do
            func(owner, ...)
        end
    end,
}

ChatFrameUtil = {
    -- English group tags: {group1} → {g1} (GROUP_TAG_LIST, GROUP_LANGUAGE_INDEPENDENT_STRINGS).
    SubstituteChatMessageBeforeSend = function(text)
        return (text:gsub("{[Gg][Rr][Oo][Uu][Pp](%d)}", "{g%1}"))
    end,
    GetActiveWindow = function()
        return WowStub.activeWindow
    end,
}

Enum = {
    AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
}

ERR_CHAT_THROTTLED = "The number of messages that can be sent is limited, please wait to send another message."

function IsInInstance()
    return WowStub.inInstance, WowStub.inInstance and "party" or "none"
end

function issecretvalue(value)
    return WowStub.secretValues[value] == true
end

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
