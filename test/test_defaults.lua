describe("ApplyDefaults", function()
    local ns

    beforeEach(function()
        ns = loadAddon()
    end)

    it("fills missing keys", function()
        local result = ns.ApplyDefaults({}, { a = 1, b = "x" })
        expect(result).toEqual({ a = 1, b = "x" })
    end)

    it("returns the target table", function()
        local target = {}
        expect(ns.ApplyDefaults(target, { a = 1 })).toBe(target)
    end)

    it("keeps existing values, including false", function()
        local result = ns.ApplyDefaults({ a = 2, flag = false }, { a = 1, flag = true })
        expect(result).toEqual({ a = 2, flag = false })
    end)

    it("recurses into nested tables", function()
        local result = ns.ApplyDefaults({ settings = { kept = 1 } }, { settings = { kept = 0, added = 2 } })
        expect(result).toEqual({ settings = { kept = 1, added = 2 } })
    end)

    it("does not replace a saved non-table value with a default table", function()
        local result = ns.ApplyDefaults({ settings = "legacy" }, { settings = { a = 1 } })
        expect(result.settings).toEqual("legacy")
    end)

    it("copies default tables instead of sharing them", function()
        local defaults = { settings = { list = { 1, 2 } } }
        local result = ns.ApplyDefaults({}, defaults)
        result.settings.list[1] = 99
        expect(defaults.settings.list[1]).toEqual(1)
    end)
end)
