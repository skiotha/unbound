describe("Unbound entry", function()
    local ns

    beforeEach(function()
        ns = loadAddon()
    end)

    it("reads its version from the TOC", function()
        expect(ns.VERSION).toEqual("0.1.0")
    end)

    describe("ADDON_LOADED", function()
        it("creates UnboundDB with defaults on first run", function()
            WowStub.fireEvent("ADDON_LOADED", "Unbound")
            expect(UnboundDB).toEqual({ schemaVersion = 1, settings = {} })
            expect(ns.db).toBe(UnboundDB)
        end)

        it("keeps values restored from SavedVariables", function()
            UnboundDB = { schemaVersion = 1, settings = { chunkSize = 200 } }
            WowStub.fireEvent("ADDON_LOADED", "Unbound")
            expect(UnboundDB.settings.chunkSize).toEqual(200)
        end)

        it("ignores ADDON_LOADED for other addons", function()
            WowStub.fireEvent("ADDON_LOADED", "SomeOtherAddon")
            expect(UnboundDB).toBeNil()
            expect(ns.db).toBeNil()
        end)
    end)

    describe("slash commands", function()
        it("shows help for /unbound and /ub", function()
            WowStub.runSlash("/unbound")
            WowStub.runSlash("/UB help")
            expect(#WowStub.printed > 0).toBeTruthy()
            expect(WowStub.printed[1]).toContain("v0.1.0")
            expect(table.concat(WowStub.printed, "\n")).toContain("/ub help")
        end)

        it("reports unknown commands", function()
            WowStub.runSlash("/ub frobnicate now")
            expect(WowStub.printed[1]).toContain("Unknown command 'frobnicate'")
        end)
    end)
end)
