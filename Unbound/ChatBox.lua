local addonName, ns = ...

local format = string.format
local gsub = string.gsub
local lower = string.lower
local match = string.match
local min = math.min
local concat = table.concat

local PRE_SEND_EVENT = "ChatFrame.OnEditBoxPreSendText"
local FOCUS_GAINED_EVENT = "ChatFrame.OnEditBoxFocusGained"
-- ERR_CHAT_THROTTLED lines arrive right after the burst they refuse.
local REFUSAL_WINDOW_SECONDS = 3
-- Whispers have arrived about 10 s late (check 10), so their echoes are waited for longer.
local WHISPER_WATCH_SECONDS = 30
local KEPT_HINT = "The whole post is in the chat box history: open the chat box and press Alt+Up."
-- "No player named '%s' is currently playing." as a pattern capturing the name.
local NOT_FOUND_PATTERN = "^" .. gsub(gsub(ERR_CHAT_PLAYER_NOT_FOUND_S, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"),
    "%%%%s", "(.+)") .. "$"

local restrictionTypes = Enum.AddOnRestrictionType or {}
local restrictionStates = Enum.AddOnRestrictionState or {}
local COMBAT_RESTRICTION = restrictionTypes.Combat
local RESTRICTION_INACTIVE = restrictionStates.Inactive or 0

local active = false
local restrictions = {}  -- [restrictionType] = true while a non-combat restriction is on
local liftedBoxes = {}   -- [editBox] = { maxBytes, maxLetters, visibleBytes } before lifting
local refusalWatch       -- { sent, refused, token } until the window after a say/emote burst closes
local whisperWatches = {} -- one per whisper burst, oldest first, until it's reported

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

-- Whispers --------------------------------------------------------------------

local function reportWhispers(watch)
    local problems = {}
    if watch.notFound > 0 then
        tinsert(problems, format("No player named '%s' is online, so %d of %d whispers didn't arrive.",
            watch.target, watch.notFound, watch.sent))
    end
    if watch.refused > 0 then
        tinsert(problems, format("The server refused %d of %d whispers.", watch.refused, watch.sent))
    end
    if watch.unresolved > 0 then
        tinsert(problems, format("%d of %d whispers haven't shown up yet and may still arrive, so don't resend "
            .. "them right away.", watch.unresolved, watch.sent))
    end
    if #problems == 0 then return end
    ns.Print(concat(problems, " ") .. " " .. KEPT_HINT)
end

local function finishWhisperWatch(watch)
    for i, open in ipairs(whisperWatches) do
        if open == watch then
            tremove(whisperWatches, i)
            reportWhispers(watch)
            return
        end
    end
end

-- Counts one chunk as accounted for; `outcome` is "refused", "notFound" or nil (echoed).
local function resolveWhisper(watch, outcome)
    if outcome then watch[outcome] = watch[outcome] + 1 end
    watch.unresolved = watch.unresolved - 1
    if watch.unresolved == 0 then finishWhisperWatch(watch) end
end

local function watchWhispers(chunks, target)
    local watch = { target = target, sent = #chunks, unresolved = #chunks, refused = 0, notFound = 0, pending = {} }
    for _, chunk in ipairs(chunks) do
        watch.pending[chunk] = (watch.pending[chunk] or 0) + 1
    end
    tinsert(whisperWatches, watch)
    C_Timer.After(WHISPER_WATCH_SECONDS, function() finishWhisperWatch(watch) end)
end

-- Echoes are matched by text, so whispers typed meanwhile don't count.
local function onWhisperEcho(text)
    if issecretvalue(text) then return end
    for _, watch in ipairs(whisperWatches) do
        local count = watch.pending[text]
        if count then
            watch.pending[text] = count > 1 and count - 1 or nil
            resolveWhisper(watch, nil)
            return
        end
    end
end

-- The refusal line names no chunk: it goes to the oldest open whisper burst.
local function onWhisperRefused()
    local watch = whisperWatches[1]
    if watch then resolveWhisper(watch, "refused") end
end

local function sameName(a, b)
    return gsub(lower(a), "-", " ") == gsub(lower(b), "-", " ")
end

local function onWhisperTargetNotFound(name)
    local found = whisperWatches[1]
    for _, watch in ipairs(whisperWatches) do
        if sameName(watch.target, name) then
            found = watch
            break
        end
    end
    if found then resolveWhisper(found, "notFound") end
end

-- System lines ----------------------------------------------------------------

-- A throttle line goes to a say/emote burst while its short window is open: refusals
-- of that burst arrive right away, while whisper outcomes can come much later.
local function onSystemMessage(text)
    if issecretvalue(text) then return end
    if text == ERR_CHAT_THROTTLED then
        if refusalWatch then
            refusalWatch.refused = refusalWatch.refused + 1
        else
            onWhisperRefused()
        end
        return
    end
    local name = match(text, NOT_FOUND_PATTERN)
    if name then onWhisperTargetNotFound(name) end
end

-- Sending ---------------------------------------------------------------------

-- The whisper name or channel number Blizzard's SendText would use.
local function chatTarget(editBox, chatType)
    if chatType == "WHISPER" then
        return editBox:GetTellTarget()
    elseif chatType == "CHANNEL" then
        return editBox:GetChannelTarget()
    end
end

local function keepMessage(plan)
    if plan.reason == "cap" then
        return format("Not sent: this post needs %d messages, and Unbound sends at most %d at once.",
            plan.count, plan.cap)
    end
    if plan.reason == "chatType" then
        return "Not sent: long text is only split in say, emote and whispers for now."
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
    local target = chatTarget(editBox, chatType)
    editBox:AddHistoryLine(ns.HistoryLine(text, chatType, _G["SLASH_" .. chatType .. "1"], target))
    editBox:SetText("")
    if plan.action == "keep" then
        ns.Print(keepMessage(plan) .. " " .. KEPT_HINT)
        return
    end
    for _, chunk in ipairs(plan.chunks) do
        C_ChatInfo.SendChatMessage(chunk, chatType, editBox.languageID, target)
    end
    if chatType == "WHISPER" then
        watchWhispers(plan.chunks, target)
    else
        watchRefusals(#plan.chunks)
    end
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

function handlers.CHAT_MSG_WHISPER_INFORM(text)
    onWhisperEcho(text)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
-- A Midnight-era event: if the client doesn't know it, RegisterEvent throws.
pcall(eventFrame.RegisterEvent, eventFrame, "ADDON_RESTRICTION_STATE_CHANGED")
