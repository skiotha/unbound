local addonName, ns = ...

local find = string.find

local MAX_CHUNKS = 8
local SPLIT_CHAT_TYPES = { SAY = true, EMOTE = true }

-- Decides what happens to a post on Enter. Returns one of:
--   { action = "pass" }                          Blizzard sends it as usual
--   { action = "send", chunks = { ... } }        Unbound sends every chunk
--   { action = "keep", reason = "cap", count = n }
--   { action = "keep", reason = "chatType" }
--   { action = "keep", reason = "error", error = message }
local function planPost(text, chatType)
    if #text <= ns.MAX_MESSAGE_BYTES or not find(text, "%S") then
        return { action = "pass" }
    end
    if not SPLIT_CHAT_TYPES[chatType] then
        return { action = "keep", reason = "chatType" }
    end

    local chunks, err = ns.SplitText(text)
    if not chunks then
        return { action = "keep", reason = "error", error = err }
    end
    if #chunks == 0 then
        return { action = "keep", reason = "error", error = "Nothing to send." }
    end
    if #chunks > MAX_CHUNKS then
        return { action = "keep", reason = "cap", count = #chunks }
    end
    return { action = "send", chunks = chunks }
end

-- The line Blizzard's AddHistory would store for this post. `header` is the chat
-- type's slash command (SLASH_<TYPE>1); `target` is the whisper name or channel number.
local function historyLine(text, chatType, header, target)
    local line = header or ""
    if chatType == "WHISPER" then
        line = line .. " " .. target
    elseif chatType == "CHANNEL" then
        line = "/" .. target
    end
    if text ~= "" then
        line = line .. " " .. text
    end
    return line
end

ns.MAX_CHUNKS = MAX_CHUNKS
ns.PlanPost = planPost
ns.HistoryLine = historyLine
