local addonName, ns = ...

local format = string.format
local min = math.min

local PRE_SEND_EVENT = "ChatFrame.OnEditBoxPreSendText"
local FOCUS_GAINED_EVENT = "ChatFrame.OnEditBoxFocusGained"
-- ERR_CHAT_THROTTLED lines arrive right after the burst they refuse.
local REFUSAL_WINDOW_SECONDS = 3
local KEPT_HINT = "The whole post is in the chat box history: open the chat box and press Alt+Up."

local restrictionTypes = Enum.AddOnRestrictionType or {}
local restrictionStates = Enum.AddOnRestrictionState or {}
local COMBAT_RESTRICTION = restrictionTypes.Combat
local RESTRICTION_INACTIVE = restrictionStates.Inactive or 0

local active = false
local restrictions = {}  -- [restrictionType] = true while a non-combat restriction is on
local liftedBoxes = {}   -- [editBox] = { maxBytes, maxLetters, visibleBytes } before lifting
local refusalWatch       -- { sent, refused, token } until the window after a burst closes

-- Chat box limits -------------------------------------------------------------

local function liftLimits(editBox)
    if liftedBoxes[editBox] then return end
    liftedBoxes[editBox] = {
        editBox:GetMaxBytes(), editBox:GetMaxLetters(), editBox:GetVisibleTextByteLimit(),
    }
    editBox:SetMaxBytes(0)
    editBox:SetMaxLetters(0)
    editBox:SetVisibleTextByteLimit(0)
end

local function restoreLimits()
    for editBox, limits in pairs(liftedBoxes) do
        editBox:SetMaxBytes(limits[1])
        editBox:SetMaxLetters(limits[2])
        editBox:SetVisibleTextByteLimit(limits[3])
    end
    wipe(liftedBoxes)
end

-- Refusals --------------------------------------------------------------------

-- A burst sent before the window closes joins the same count and restarts the window.
local function watchRefusals(sentCount)
    local watch = refusalWatch or { sent = 0, refused = 0 }
    local token = {}
    watch.sent = watch.sent + sentCount
    watch.token = token
    refusalWatch = watch

    C_Timer.After(REFUSAL_WINDOW_SECONDS, function()
        if refusalWatch ~= watch or watch.token ~= token then return end
        refusalWatch = nil
        local refused = min(watch.refused, watch.sent)
        if refused == 0 then return end
        ns.Print(format("The server refused %d of %d messages. %s", refused, watch.sent, KEPT_HINT))
    end)
end

local function onSystemMessage(text)
    if not refusalWatch or issecretvalue(text) then return end
    if text == ERR_CHAT_THROTTLED then
        refusalWatch.refused = refusalWatch.refused + 1
    end
end

-- Sending ---------------------------------------------------------------------

local function keepInHistory(editBox, text, chatType)
    local target
    if chatType == "WHISPER" then
        target = editBox:GetTellTarget()
    elseif chatType == "CHANNEL" then
        target = editBox:GetChannelTarget()
    end
    editBox:AddHistoryLine(ns.HistoryLine(text, chatType, _G["SLASH_" .. chatType .. "1"], target))
end

local function keepMessage(plan)
    if plan.reason == "cap" then
        return format("Not sent: this post needs %d messages, and Unbound sends at most %d at once.",
            plan.count, ns.MAX_CHUNKS)
    end
    if plan.reason == "chatType" then
        return "Not sent: long text is only split in say and emote for now."
    end
    return "Not sent: " .. plan.error
end

local function onPreSendText(_, editBox)
    if IsInInstance() or C_ChatInfo.InChatMessagingLockdown() then return end
    local text = editBox:GetText()
    local chatType = editBox:GetChatType()
    local plan = ns.PlanPost(ChatFrameUtil.SubstituteChatMessageBeforeSend(text), chatType)
    if plan.action == "pass" then return end

    -- Keep the post and empty the box before sending: if a send fails, the text is
    -- safe and Blizzard has nothing left to send.
    keepInHistory(editBox, text, chatType)
    editBox:SetText("")
    if plan.action == "keep" then
        ns.Print(keepMessage(plan) .. " " .. KEPT_HINT)
        return
    end
    for _, chunk in ipairs(plan.chunks) do
        C_ChatInfo.SendChatMessage(chunk, chatType, editBox.languageID)
    end
    watchRefusals(#plan.chunks)
end

local function onFocusGained(_, editBox)
    liftLimits(editBox)
end

-- On and off ------------------------------------------------------------------

-- Off in instances and during chat lockdown: no callbacks, Blizzard's limits.
local function refresh()
    local wanted = not IsInInstance() and not C_ChatInfo.InChatMessagingLockdown() and next(restrictions) == nil
    if wanted == active then return end
    active = wanted

    if active then
        EventRegistry:RegisterCallback(PRE_SEND_EVENT, onPreSendText, addonName)
        EventRegistry:RegisterCallback(FOCUS_GAINED_EVENT, onFocusGained, addonName)
        local openBox = ChatFrameUtil.GetActiveWindow()
        if openBox then liftLimits(openBox) end
    else
        EventRegistry:UnregisterCallback(PRE_SEND_EVENT, addonName)
        EventRegistry:UnregisterCallback(FOCUS_GAINED_EVENT, addonName)
        restoreLimits()
    end
end

-- Events ----------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function handlers.PLAYER_ENTERING_WORLD()
    refresh()
end

-- Fires before a restriction starts and after it ends, so the payload is the truth
-- while it is dispatched.
function handlers.ADDON_RESTRICTION_STATE_CHANGED(restrictionType, state)
    if restrictionType == COMBAT_RESTRICTION then return end
    restrictions[restrictionType] = state ~= RESTRICTION_INACTIVE or nil
    refresh()
end

function handlers.CHAT_MSG_SYSTEM(text)
    onSystemMessage(text)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
-- A Midnight-era event: if the client doesn't know it, RegisterEvent throws.
pcall(eventFrame.RegisterEvent, eventFrame, "ADDON_RESTRICTION_STATE_CHANGED")
