describe("PlanPost", function()
    local ns

    beforeEach(function()
        ns = loadAddon()
    end)

    -- One 255-byte word per chunk keeps the chunk count exact.
    local function longText(chunkCount)
        local words = {}
        for i = 1, chunkCount do
            words[i] = ("x"):rep(255)
        end
        return table.concat(words, " ")
    end

    it("passes text that fits one message untouched", function()
        expect(ns.PlanPost("", "SAY")).toEqual({ action = "pass" })
        expect(ns.PlanPost(("x"):rep(255), "SAY")).toEqual({ action = "pass" })
        expect(ns.PlanPost(("x"):rep(255), "WHISPER")).toEqual({ action = "pass" })
    end)

    it("passes long whitespace-only text, which Blizzard doesn't send", function()
        expect(ns.PlanPost((" "):rep(300), "SAY")).toEqual({ action = "pass" })
    end)

    it("splits long says and emotes into chunks to send", function()
        for _, chatType in ipairs({ "SAY", "EMOTE" }) do
            local plan = ns.PlanPost(longText(2), chatType)
            expect(plan.action).toEqual("send")
            expect(plan.chunks).toEqual(ns.SplitText(longText(2)))
            expect(#plan.chunks).toEqual(2)
        end
    end)

    it("sends up to the cap of 8 chunks and keeps anything longer", function()
        expect(ns.MAX_CHUNKS).toEqual(8)
        expect(#ns.PlanPost(longText(8), "SAY").chunks).toEqual(8)
        expect(ns.PlanPost(longText(9), "SAY")).toEqual({ action = "keep", reason = "cap", count = 9 })
    end)

    it("keeps long text in chat types it doesn't split yet", function()
        for _, chatType in ipairs({ "YELL", "PARTY", "WHISPER", "BN_WHISPER", "CHANNEL", "GUILD" }) do
            expect(ns.PlanPost(longText(2), chatType)).toEqual({ action = "keep", reason = "chatType" })
        end
    end)

    it("keeps text the splitter rejects, with its error", function()
        local plan = ns.PlanPost(longText(1) .. " \1 " .. longText(1), "SAY")
        expect(plan.action).toEqual("keep")
        expect(plan.reason).toEqual("error")
        expect(plan.error).toContain("Unsupported control character")
    end)

    it("keeps long text that leaves nothing to send", function()
        local plan = ns.PlanPost(("|cff00ff00|r"):rep(30), "EMOTE")
        expect(plan).toEqual({ action = "keep", reason = "error", error = "Nothing to send." })
    end)
end)

describe("HistoryLine", function()
    local ns

    beforeEach(function()
        ns = loadAddon()
    end)

    it("prefixes the chat type's slash command, like Blizzard's AddHistory", function()
        expect(ns.HistoryLine("hello there", "SAY", "/s")).toEqual("/s hello there")
        expect(ns.HistoryLine("waves", "EMOTE", "/e")).toEqual("/e waves")
    end)

    it("adds the target for whispers and uses the channel number for channels", function()
        expect(ns.HistoryLine("hi", "WHISPER", "/w", "Ek Palewind")).toEqual("/w Ek Palewind hi")
        expect(ns.HistoryLine("lfg", "CHANNEL", "/1", 2)).toEqual("/2 lfg")
    end)

    it("leaves the prefix out when the chat type has no slash command", function()
        expect(ns.HistoryLine("hi", "BN_WHISPER", nil, "Friend")).toEqual(" hi")
    end)
end)
