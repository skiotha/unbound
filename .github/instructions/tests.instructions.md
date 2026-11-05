---
applyTo: "test/**"
---

# Test Conventions

## Framework

- Tests run outside WoW with **Lua 5.1** and the hand-written runner `test/run.lua`.
  No busted, no luarocks.
- Run from the repository root:
  - all tests: `lua test/run.lua`
  - selected files: `lua test/run.lua test/test_defaults.lua`
  - exit code 0 = all passed, 1 = failures.
- `test/wowstubs.lua` provides the WoW API surface the addon touches. It is loaded
  before any addon file. **Stub only what the addon actually calls**, and keep stubs
  faithful to the real API.

## Loading the addon

- `loadAddon()` resets WoW global state, then loads every `.lua` file listed in
  `Unbound/Unbound.toc` **in TOC order** into a fresh namespace and returns it. Call it
  in `beforeEach` so tests stay independent.
- To simulate SavedVariables, assign the global **after** `loadAddon()` and **before**
  firing `ADDON_LOADED`. That's the order the real client uses.

## Helpers (`WowStub`)

- `WowStub.fireEvent(event, ...)`: deliver an event to every registered frame.
- `WowStub.runSlash("/ub help")`: run a typed slash command through `SlashCmdList`.
- `WowStub.printed`: lines passed to `print()` since the last `loadAddon()`.
  Runner output uses `io.write`, so `print` is free to be captured.

## File Naming

- One test file per module: `test/test_<module>.lua` (e.g. `test/test_defaults.lua`
  tests `Unbound/Util/Defaults.lua`).

## Structure

```lua
describe("ApplyDefaults", function()
    local ns

    beforeEach(function()
        ns = loadAddon()
    end)

    it("fills missing keys", function()
        expect(ns.ApplyDefaults({}, { a = 1 })).toEqual({ a = 1 })
    end)
end)
```

## Assertions

- `expect(a).toEqual(b)`: deep equality for tables, `==` for scalars.
- `expect(a).toBe(b)`: same value / same table reference.
- `expect(a).toBeNil()`, `.toBeTruthy()`, `.toBeFalsy()`
- `expect(a).toContain(b)`: plain substring, or table contains a value.
- `expect(fn).toError([text])`: the function throws, optionally with a message
  containing `text`.

Add matchers to `test/run.lua` only when needed. Keep the runner lean.

## What Not to Test Here

- Real message delivery, hardware-event behaviour, frame rendering: check those in game.

## Principles

- Write tests **before** implementation for pure logic.
- No shared mutable state between `it()` blocks.
- Prefer explicit assertions over "no error thrown".
