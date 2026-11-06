# Unbound — Copilot Project Instructions

> Authoritative rules for every Copilot session working on this project.
> Forever- and chat-API specifics live in [`docs/forever-api.md`](../docs/forever-api.md).
> Read it before touching anything that sends or reads chat.

## About

- **Unbound** is a small World of Warcraft addon for **personal use**. It splits a long
  chat message into chunks and sends them one by one.
- Target client: **World of Warcraft: Forever** (interface `16001`). Forever runs the
  **Retail** API with Midnight-era restrictions, not the Classic API.
- Feature details are still being designed. Don't add behaviour beyond what has been
  agreed. The agreed stages are in [`docs/roadmap.md`](../docs/roadmap.md); build only
  the current one.
- Main use: long roleplay messages in `SAY`, `EMOTE`, group (`PARTY`) and `WHISPER`,
  in calm settings. Other chat types are lower priority.
- Default language is **English**. Text handling must still be UTF-8 safe.
- Not distributed via CurseForge / WoWInterface. Source lives on GitHub.

## Language & Runtime

- All addon code is **Lua 5.1** running inside the WoW client.
- The WoW API is available globally (`CreateFrame`, `C_Timer`, `C_ChatInfo`, …).
- Do **not** use Lua 5.2+ features (`goto`, bitwise operators, `__gc` on tables, `\z`).

## Zero-Dependency Policy

- **No external libraries** (no Ace3, LibStub, ChatThrottleLib, …). Helpers are
  hand-written and kept minimal.

## Code Style

- `local` for all file-scoped variables and functions. Share state through the addon
  namespace: `local addonName, ns = ...`.
- Early return over deep nesting.
- Constants `UPPER_SNAKE_CASE`, locals `camelCase`, namespace API `PascalCase`.
- Lines ≤ 120 characters where practical. 4-space indent, LF line endings
  (see `.editorconfig`).

## Project Layout

```
Unbound/                    -- the addon folder (ships to Interface/AddOns/Unbound/)
├── Unbound.toc             -- manifest: load order, SavedVariables, version
├── Media/
│   └── Icon.png            -- AddOns-list icon (TOC IconTexture), 64×64 PNG
├── Util/                   -- pure-Lua helpers, no WoW API (unit-tested)
│   ├── Defaults.lua        -- ns.ApplyDefaults: deep-fill missing SV keys
│   ├── Splitter.lua        -- ns.SplitText: UTF-8 and markup-aware 255-byte chunks
│   └── Post.lua            -- ns.PlanPost: pass, send in chunks or keep; ns.HistoryLine
├── ChatBox.lua             -- chat box glue: lifted limits, pre-send sending, refusals
└── Unbound.lua             -- entry: events, SavedVariables init, slash commands
test/                       -- DIY runner, WoW stubs, test_*.lua (never shipped)
docs/                       -- design notes and API reference (never shipped)
.github/                    -- Copilot instructions, CI workflow
```

- New module: create the `.lua` file in the right subfolder and list it in
  `Unbound.toc` **after** its dependencies. Pure logic goes in `Util/` (or a future
  `Core/`) so it can be tested outside the client.
- The TOC `## Version` is the single source of the version string (`ns.VERSION`).
- Only `Unbound/` ships. Everything else stays at the repo root.

## SavedVariables

- One persisted table: `UnboundDB`. It carries a `schemaVersion` for future migrations.
- Initialise it in **`ADDON_LOADED`** (for our own addon name) via `ns.ApplyDefaults`,
  **never at file load**. The client restores SVs only after all addon files have run.
- Access it through `ns.db` after initialisation.

## Globals

- Allowed globals: `UnboundDB`, `SLASH_UNBOUND1..n`, `SlashCmdList.UNBOUND`. Nothing
  else.

## Chat & Forever Rules (CRITICAL)

- Send with **`C_ChatInfo.SendChatMessage`**, not the deprecated global.
- `CHANNEL` always needs a hardware event, and so do `SAY` / `YELL` outside instances.
  On Forever `EMOTE` needs one outdoors too, unlike Retail (see `docs/forever-api.md`).
  Never send those from a timer or event handler; the send must run inside a key press
  or click handler.
- **Unbound stays fully inactive inside instances**: no hooks, no lifted chat box limits,
  so chat there is pure Blizzard. Decided before the dungeon checks; revisit only with
  their results.
- Forever names are two-part: `UnitName(unit)` returns first name and surname, not
  name and realm. Never build a whisper target from the first name alone.
- 255 **bytes** per message, counted in bytes (confirmed in game; one byte more raises a
  Lua error and nothing is sent). Never split inside a UTF-8 sequence, a hyperlink or a
  colour escape.
- Say and emote share an observed limit of 15 messages, counted in messages, not bytes.
  No recovery was seen at the tested gaps through about 8 s; bursts 10 s apart worked.
  A burst must fit in what's left of the 15 after the say and emote messages of the last
  12 s, typed ones included. This is a conservative estimate, not a guaranteed quota.
- Whispers are not unrestricted: one batch of 20 self-whispers delivered 10 promptly,
  five about 10 s later, and refused five. The source of the delay is unknown.
  An API return is not delivery confirmation; wait for echoes before retrying.
  `ERR_CHAT_THROTTLED` arrives asynchronously via `CHAT_MSG_SYSTEM` with no chunk ID.
  See `docs/forever-api.md` for the measured limits and remaining uncertainties.
- Send every chunk with the chat box's `languageID`, as Blizzard's `SendText` does, so
  all chunks go out in the language the player picked.
- Respect chat lockdown: check `C_ChatInfo.InChatMessagingLockdown()` and treat
  `CHAT_MSG_*` payloads as possibly secret (`issecretvalue`).
- Wrap `RegisterEvent` in `pcall` for events that may not exist on Forever (an unknown
  event throws and aborts the file).
- Don't detect the client with `GetBuildInfo() >= 100000`. Forever reports `16001`.

## Taint & Combat

- Never touch Blizzard secure frames or `Blizzard_*` internals from addon code.
- Hooking Blizzard chat UI (e.g. the chat edit box) must use `hooksecurefunc` /
  `HookScript`, never replace Blizzard functions.
- **Never replace `C_ChatInfo.SendChatMessage`.** Both earlier splitters did; it taints
  every typed message and broke chat in instances (see `docs/forever-api.md` → Prior
  art).

## Testing

- **Testing-first** for pure logic: write the test, then the code.
- DIY runner: `lua test/run.lua` from the repo root (Lua 5.1, no busted / luarocks).
  See `.github/instructions/tests.instructions.md`.
- CI runs the same command on every push (`.github/workflows/test.yml`).
- Anything that needs the real client (actual sends, UI, hardware events) is checked
  manually in game, following `docs/client-checks.md`.

## Git

- The owner makes all commits himself. Agents never run `git add`, `git commit` or
  `git push`.

## Things to Avoid

- No global pollution beyond the list above.
- No `pairs` / `ipairs` in `OnUpdate` / per-frame code.
- No external library dependencies.
- No speculative features. Build only what is planned.
