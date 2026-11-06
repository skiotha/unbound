local PRE_SEND = "ChatFrame.OnEditBoxPreSendText"
local FOCUS_GAINED = "ChatFrame.OnEditBoxFocusGained"
local CHAT = Enum.AddOnRestrictionType.Chat
local COMBAT = Enum.AddOnRestrictionType.Combat
local INACTIVE = Enum.AddOnRestrictionState.Inactive
local ACTIVATING = Enum.AddOnRestrictionState.Activating

-- One 255-byte word per chunk keeps the chunk count exact.
local function longText(chunkCount, word)
    local words = {}
    for i = 1, chunkCount do
        words[i] = word or ("x"):rep(255)
    end
    return table.concat(words, " ")
end

local function sentTexts()
    local texts = {}
    for i, message in ipairs(WowStub.sent) do texts[i] = message[1] end
    return texts
end

describe("ChatBox", function()
    local ns

    beforeEach(function()
        ns = loadAddon()
        WowStub.fireEvent("ADDON_LOADED", "Unbound")
    end)

    local function enterWorld()
        WowStub.fireEvent("PLAYER_ENTERING_WORLD", false, false)
    end

    it("stays off until the player is in the world", function()
        local box = WowStub.newChatEditBox({ text = longText(2) })
        EventRegistry:TriggerEvent(PRE_SEND, box)
        EventRegistry:TriggerEvent(FOCUS_GAINED, box)
        expect(box.text).toEqual(longText(2))
        expect(box.maxBytes).toEqual(1280)
    end)

    it("lifts the limits of the box already open when it turns on", function()
        local open = WowStub.newChatEditBox()
        WowStub.activeWindow = open
        enterWorld()
        expect({ open.maxBytes, open.maxLetters, open.visibleBytes }).toEqual({ 0, 0, 0 })
    end)

    describe("outdoors", function()
        beforeEach(enterWorld)

        it("sends a long say in chunks on one Enter, keeps it in history, and Blizzard sends nothing", function()
            local text = longText(3)
            local box = WowStub.newChatEditBox({ text = text, languageID = 35 })
            WowStub.sendText(box)
            expect(sentTexts()).toEqual(ns.SplitText(text))
            for _, message in ipairs(WowStub.sent) do
                expect(message[2]).toEqual("SAY")
                expect(message[3]).toEqual(35)
            end
            expect(box.history).toEqual({ "/s " .. text })
            expect(box.text).toEqual("")
            expect(#WowStub.printed).toEqual(0)
        end)

        it("sends emotes as emotes", function()
            local box = WowStub.newChatEditBox({ text = longText(2), chatType = "EMOTE" })
            WowStub.sendText(box)
            expect(#WowStub.sent).toEqual(2)
            expect(WowStub.sent[2][2]).toEqual("EMOTE")
            expect(box.history).toEqual({ "/e " .. longText(2) })
        end)

        it("sends Blizzard's substituted text, and keeps the typed text in history", function()
            local word = ("y"):rep(200) .. " {group1}"
            local box = WowStub.newChatEditBox({ text = longText(2, word) })
            WowStub.sendText(box)
            expect(sentTexts()).toEqual(ns.SplitText(longText(2, ("y"):rep(200) .. " {g1}")))
            expect(box.history[1]).toContain("{group1}")
        end)

        it("leaves short messages to Blizzard", function()
            local box = WowStub.newChatEditBox({ text = "Hello there." })
            WowStub.sendText(box)
            expect(WowStub.sent).toEqual({ { "Hello there.", "SAY", 7 } })
            expect(box.history).toEqual({ "/s Hello there." })
        end)

        it("keeps an over-cap post unsent and says so", function()
            local box = WowStub.newChatEditBox({ text = longText(9) })
            WowStub.sendText(box)
            expect(#WowStub.sent).toEqual(0)
            expect(box.history).toEqual({ "/s " .. longText(9) })
            expect(WowStub.printed[1]).toContain("needs 9 messages")
            expect(WowStub.printed[1]).toContain("Alt+Up")
        end)

        it("keeps long text in other chat types unsent, with the whisper target", function()
            local box = WowStub.newChatEditBox({ text = longText(2), chatType = "WHISPER", tellTarget = "Ek Palewind" })
            WowStub.sendText(box)
            expect(#WowStub.sent).toEqual(0)
            expect(box.history).toEqual({ "/w Ek Palewind " .. longText(2) })
            expect(WowStub.printed[1]).toContain("say and emote")
        end)

        it("keeps text the splitter rejects and reports the error", function()
            local box = WowStub.newChatEditBox({ text = longText(1) .. " |n " .. longText(1) })
            WowStub.sendText(box)
            expect(#WowStub.sent).toEqual(0)
            expect(#box.history).toEqual(1)
            expect(WowStub.printed[1]).toContain("Unsupported")
        end)

        it("lifts the limits of a box when it gains focus", function()
            local box = WowStub.newChatEditBox()
            EventRegistry:TriggerEvent(FOCUS_GAINED, box)
            expect({ box.maxBytes, box.maxLetters, box.visibleBytes }).toEqual({ 0, 0, 0 })
        end)

        it("turns off in instances: limits restored and the box left to Blizzard", function()
            local box = WowStub.newChatEditBox()
            EventRegistry:TriggerEvent(FOCUS_GAINED, box)
            WowStub.inInstance = true
            enterWorld()
            expect({ box.maxBytes, box.maxLetters, box.visibleBytes }).toEqual({ 1280, 0, 255 })

            box.text = longText(2)
            EventRegistry:TriggerEvent(PRE_SEND, box)
            EventRegistry:TriggerEvent(FOCUS_GAINED, box)
            expect(box.text).toEqual(longText(2))
            expect(box.maxBytes).toEqual(1280)
        end)

        it("turns off while a non-combat addon restriction is on, and back on after", function()
            local box = WowStub.newChatEditBox({ text = longText(2) })
            WowStub.fireEvent("ADDON_RESTRICTION_STATE_CHANGED", CHAT, ACTIVATING)
            EventRegistry:TriggerEvent(PRE_SEND, box)
            expect(box.text).toEqual(longText(2))

            WowStub.fireEvent("ADDON_RESTRICTION_STATE_CHANGED", CHAT, INACTIVE)
            WowStub.fireEvent("ADDON_RESTRICTION_STATE_CHANGED", COMBAT, ACTIVATING)
            WowStub.sendText(box)
            expect(#WowStub.sent).toEqual(2)
        end)

        it("leaves the box alone if chat lockdown is on when Enter is pressed", function()
            WowStub.lockdown = true
            local box = WowStub.newChatEditBox({ text = longText(2) })
            EventRegistry:TriggerEvent(PRE_SEND, box)
            expect(box.text).toEqual(longText(2))
            expect(#WowStub.sent).toEqual(0)
        end)

        describe("refusals", function()
            local function burst(chunkCount)
                WowStub.sendText(WowStub.newChatEditBox({ text = longText(chunkCount) }))
            end

            it("reports how many chunks the server refused after a burst", function()
                burst(3)
                WowStub.fireEvent("CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED)
                WowStub.fireEvent("CHAT_MSG_SYSTEM", "Someone has come online.")
                WowStub.fireEvent("CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED)
                expect(#WowStub.printed).toEqual(0)
                WowStub.runTimers()
                expect(WowStub.printed[1]).toContain("refused 2 of 3")
                expect(WowStub.printed[1]).toContain("Alt+Up")
            end)

            it("stays quiet when nothing was refused, or outside a burst", function()
                WowStub.fireEvent("CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED)
                burst(2)
                WowStub.runTimers()
                WowStub.fireEvent("CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED)
                WowStub.runTimers()
                expect(#WowStub.printed).toEqual(0)
            end)

            it("adds a burst sent before the report to the same count", function()
                burst(2)
                WowStub.fireEvent("CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED)
                burst(3)
                WowStub.fireEvent("CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED)
                WowStub.runTimers()
                expect(#WowStub.printed).toEqual(1)
                expect(WowStub.printed[1]).toContain("refused 2 of 5")
            end)

            it("doesn't read secret system messages", function()
                WowStub.secretValues[ERR_CHAT_THROTTLED] = true
                burst(2)
                WowStub.fireEvent("CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED)
                WowStub.runTimers()
                expect(#WowStub.printed).toEqual(0)
            end)
        end)
    end)
end)
