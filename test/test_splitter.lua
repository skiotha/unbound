local RED = "|cffff0000"
local GREEN = "|cff00ff00"
local RESET = "|r"
local LINK = "|Hitem:123:0|h[An example item]|h"

describe("SplitText", function()
    local ns

    beforeEach(function()
        ns = loadAddon()
    end)

    local function split(text)
        local chunks, err = ns.SplitText(text)
        expect(err).toBeNil()
        expect(type(chunks)).toEqual("table")
        for _, chunk in ipairs(chunks) do
            expect(#chunk > 0 and #chunk <= 255).toBeTruthy()
        end
        return chunks
    end

    local function fails(text, message)
        local chunks, err = ns.SplitText(text)
        expect(chunks).toBeNil()
        expect(type(err)).toEqual("string")
        expect(err).toContain(message)
    end

    it("returns no chunks for empty or whitespace-only input", function()
        expect(split("")).toEqual({})
        expect(split(" \t\r\n\v\f ")).toEqual({})
    end)

    it("trims edges without normalising interior whitespace or interpreting paragraphs", function()
        expect(split(" \t alpha  beta\tgamma\n delta \r\n")).toEqual({ "alpha  beta\tgamma\n delta" })
    end)

    it("keeps short text and the exact 255-byte boundary unchanged", function()
        for _, size in ipairs({ 1, 254, 255 }) do
            local text = string.rep("x", size)
            expect(split(text)).toEqual({ text })
        end
    end)

    it("splits an oversized word only at the byte limit", function()
        expect(split(string.rep("x", 511))).toEqual({
            string.rep("x", 255), string.rep("x", 255), "x",
        })
    end)

    it("uses the last whitespace, not an earlier sentence ending", function()
        local first = "Done. " .. string.rep("x", 240)
        expect(split(first .. " next-word")).toEqual({ first, "next-word" })
    end)

    it("moves a word that fits on its own instead of splitting it to fill a chunk", function()
        expect(split(string.rep("a", 200) .. " " .. string.rep("b", 100))).toEqual({
            string.rep("a", 200), string.rep("b", 100),
        })
    end)

    it("trims cut-boundary whitespace without empty chunks", function()
        expect(split(string.rep("a", 255) .. " \t\r\n " .. string.rep("b", 255) .. "   ")).toEqual({
            string.rep("a", 255), string.rep("b", 255),
        })
        expect(split("alpha" .. string.rep(" ", 300) .. "beta")).toEqual({ "alpha", "beta" })
    end)

    it("preserves two-, three- and four-byte UTF-8 characters at boundaries", function()
        for _, character in ipairs({ "\195\169", "\226\128\148", "\240\159\152\128" }) do
            local prefix = string.rep("x", 256 - #character)
            expect(split(prefix .. character .. "tail")).toEqual({ prefix, character .. "tail" })
            local exact = string.rep("x", 255 - #character) .. character
            expect(split(exact)).toEqual({ exact })
        end
    end)

    it("rejects invalid UTF-8 even inside markup, without returning a valid prefix", function()
        local invalid = {
            "\128", "\192\175", "\194", "\194x", "\224\128\128",
            "\237\160\128", "\240\128\128\128", "\244\144\128\128", "\245\128\128\128",
        }
        for _, sequence in ipairs(invalid) do
            fails(string.rep("x", 300) .. sequence, "UTF-8")
        end
        fails("|Hitem:1|h[" .. "\128" .. "]|h", "UTF-8")
    end)

    it("rejects non-text input and non-whitespace ASCII controls explicitly", function()
        fails(nil, "string")
        fails(42, "string")
        fails("alpha\000beta", "control")
        fails("alpha\127beta", "control")
    end)

    it("keeps hyperlinks whole, counting the payload and spaces in the label", function()
        local prefix = string.rep("x", 255 - #LINK + 1)
        expect(split(prefix .. LINK)).toEqual({ prefix, LINK })
        expect(split("See " .. LINK .. " here.")).toEqual({ "See " .. LINK .. " here." })
    end)

    it("keeps a coloured hyperlink whole and includes its colour overhead", function()
        local coloured = RED .. LINK .. RESET
        expect(split(string.rep("x", 243) .. " " .. coloured)).toEqual({
            string.rep("x", 243), coloured,
        })
        local exactLink = "|Hitem:1|h[" .. string.rep("x", 241) .. "]|h"
        expect(#exactLink).toEqual(255)
        expect(split(exactLink)).toEqual({ exactLink })
        fails(RED .. exactLink .. RESET, "255")
    end)

    it("rejects oversized atomic markup instead of returning partial chunks", function()
        fails("before " .. "|Hitem:1|h[" .. string.rep("x", 256) .. "]|h", "255")
        fails("|T" .. string.rep("x", 256) .. "|t", "255")
        fails(string.rep(RED, 22) .. "x" .. string.rep(RESET, 22), "255")
    end)

    it("preserves escaped pipes without treating their following letters as markup", function()
        expect(split(string.rep("x", 254) .. "||tail")).toEqual({ string.rep("x", 254), "||tail" })
        expect(split("||cffff0000not coloured")).toEqual({ "||cffff0000not coloured" })
        local link = "|Hitem:1|h[label ||h text]|h"
        expect(split(link .. " tail")).toEqual({ link .. " tail" })
    end)

    it("keeps texture and atlas escapes atomic without trimming their contents", function()
        for _, markup in ipairs({ "|TInterface\\Icons\\Example:16|t", "|A:example-atlas:16:16|a" }) do
            expect(split(string.rep("x", 254) .. markup)).toEqual({ string.rep("x", 254), markup })
        end
        expect(split("|Hitem:1|h[  spaced label  ]|h")).toEqual({ "|Hitem:1|h[  spaced label  ]|h" })
    end)

    it("closes and reopens a colour while budgeting both codes", function()
        expect(split(RED .. string.rep("x", 244) .. RESET)).toEqual({
            RED .. string.rep("x", 243) .. RESET,
            RED .. "x" .. RESET,
        })
    end)

    it("respects word boundaries within a colour and leaves no colour-only chunks", function()
        expect(split(RED .. string.rep("a", 200) .. " " .. string.rep("b", 100) .. RESET)).toEqual({
            RED .. string.rep("a", 200) .. RESET,
            RED .. string.rep("b", 100) .. RESET,
        })
        expect(split(" \t" .. RED .. "  hello  " .. RESET .. " \n")).toEqual({ RED .. "hello" .. RESET })
        expect(split(RED .. "   " .. RESET)).toEqual({})
        expect(split(RED .. RESET)).toEqual({})
    end)

    it("preserves nested colour stacks across a split and restores the outer colour", function()
        local text = RED .. string.rep("a", 220) .. GREEN .. string.rep("b", 20)
            .. RESET .. string.rep("c", 20) .. RESET
        expect(split(text)).toEqual({
            RED .. string.rep("a", 220) .. GREEN .. string.rep("b", 11) .. RESET .. RESET,
            RED .. GREEN .. string.rep("b", 9) .. RESET .. string.rep("c", 20) .. RESET,
        })
    end)

    it("does not leak colour into following uncoloured text", function()
        expect(split(RED .. string.rep("x", 243) .. RESET .. "tail")).toEqual({
            RED .. string.rep("x", 243) .. RESET, "tail",
        })
    end)

    it("preserves named and item-quality colours with their actual byte overhead", function()
        for _, colour in ipairs({ "|cnPURE_RED_COLOR:", "|cnIQ4:" }) do
            local room = 255 - #colour - #RESET
            expect(split(colour .. string.rep("x", room + 1) .. RESET)).toEqual({
                colour .. string.rep("x", room) .. RESET, colour .. "x" .. RESET,
            })
        end
    end)

    it("preserves balanced formatting inside a link as part of the atomic link", function()
        local link = "|Hitem:1|h[" .. GREEN .. "green" .. RESET .. " label]|h"
        expect(split(RED .. link .. RESET)).toEqual({ RED .. link .. RESET })
    end)

    it("rejects malformed or unbalanced markup, even after otherwise valid chunks", function()
        local malformed = {
            "|", "|c123xyz00x|r", "|cn:x|r", RED .. "missing reset", "|r",
            "|Hitem:1", "|Hitem:1|h[unfinished]", "|H|h[label]|h",
            "|Hitem:1|h[nested |Hitem:2|h[x]|h]|h", "|h", "|Tmissing", "|A:missing",
            "|Hitem:1|h[" .. GREEN .. "unclosed]|h",
            RED .. "|Hitem:1|h[closes outer" .. RESET .. "]|h",
        }
        for _, markup in ipairs(malformed) do
            fails(string.rep("x", 300) .. markup, "byte")
        end
    end)

    it("fails explicitly on unsupported escapes instead of guessing their boundaries", function()
        for _, markup in ipairs({ "|qexample", "|n", "|Kq1|k", "|4word:words;" }) do
            fails("before " .. markup, "Unsupported escape")
        end
    end)

    it("splits a long lorem-ipsum post without losing or duplicating words", function()
        local paragraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
        local text = string.rep(paragraph .. " ", 30):sub(1, -2)
        local chunks = split(text)
        expect(#chunks > 2).toBeTruthy()
        expect(table.concat(chunks, " ")).toEqual(text)
    end)
end)
