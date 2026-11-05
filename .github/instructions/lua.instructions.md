---
applyTo: "Unbound/**/*.lua"
---

# Lua 5.1 — WoW Addon Conventions

## Language Constraints

- Target **Lua 5.1** only. The WoW client does not support 5.2+.
- Forbidden: `goto`, bitwise operators (`&`, `|`, `~`, `<<`, `>>`), `__gc` on tables,
  `\z` escapes, `load()` with a mode argument.
- `unpack` is global (not `table.unpack`).
- String functions work on **bytes**. Cyrillic and other non-ASCII text is multi-byte
  UTF-8, so `#str` and `str:sub(i, j)` count bytes, not characters.

## File Boilerplate

Every `.lua` file in `Unbound/` starts with:

```lua
local addonName, ns = ...
```

All file-level symbols are `local`. Export through `ns`:

```lua
local function doThing() ... end
ns.DoThing = doThing          -- PascalCase for namespace API
```

## Naming

| Scope           | Convention                  | Example                       |
| --------------- | --------------------------- | ----------------------------- |
| Constants       | `UPPER_SNAKE_CASE`          | `MAX_MESSAGE_BYTES`           |
| Locals / params | `camelCase`                 | `chunkSize`, `chatType`       |
| Namespace API   | `PascalCase`                | `ns.ApplyDefaults`, `ns.Print` |
| Private helpers | `camelCase` local functions | `local splitMessage`          |

## Patterns

- Early return over deep nesting: `if not text then return end`.
- Events are registered on a dedicated hidden frame and dispatched through a
  `handlers[event]` table (see `Unbound.lua`).
- Keep pure logic (splitting, parsing) free of WoW API calls so it can be unit-tested.
- Prefer `tinsert` / `tremove` / `wipe` (WoW globals) over manual table ops.
- Cache frequently used globals at file scope: `local format = string.format`.

## WoW API Safety

- Send chat with `C_ChatInfo.SendChatMessage`. Respect the hardware-event rules in
  `docs/forever-api.md`.
- Check `issecretvalue(value)` before reading or comparing any chat event payload.
- Never call protected functions from insecure code. Hook Blizzard UI with
  `hooksecurefunc` / `HookScript`, never by replacing functions.
