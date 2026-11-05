# WoW: Forever — API notes

> Reference for what is specific about the **World of Warcraft: Forever** client and
> the chat API. Facts sources are at the bottom and relevant for September 2026.
> Items marked **verify** have not yet been confirmed in our own client;
> [client-checks.md](client-checks.md) has the steps.

## The client

- **Interface number: `16001`** (build line `1.60.x`). The number is
  major·10000 + minor·100 + patch, so the installed client `1.60.1.70755`
  (`Wow.exe` file version after the 2026-11-03 update) is still `16001`. A `1.60.2` client
  would need `16002` in the TOC. Verify in game with `/dump select(4, GetBuildInfo())`.
- **Lua**: a subset of Lua 5.1. `/dump _VERSION` prints `"Lua 5.1"`,
  and the patch level isn't exposed. Our tests run on stock 5.1.5. WoW's
  _environment_ differs: no file access, a cut-down `os`, extra globals
  (`strsplit`, `strtrim`, `wipe`, …), taint and secret values. `test/wowstubs.lua`
  stands in for that environment.
- It is the **Retail (mainline) client**: `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`, all
  modern `C_*` namespaces. Classic globals like `GetItemInfo`, `GetSpellInfo`, or
  `UnitAura`, are deprecated. Retail API docs and examples are warranted.
- **Never gate on `GetBuildInfo() >= 100000`** to mean "modern client". Forever answers
  `16001`.
- **Midnight (12.x) restrictions apply**: secret values (`issecretvalue`, `C_Secrets`),
  restricted combat log, and chat messaging lockdown (see below).
- **`RegisterEvent` with an unknown event throws**, which aborts the rest of the file.
  Wrap registration in `pcall` when an event might not exist on Forever.
- **`ReloadUI()` is protected**, so addon "Reload" buttons don't work. Type `/reload`.
- After **100 Lua errors** in one session the client stops reporting errors.
- **SavedVariables**: early beta builds wrote SVs to disk but never loaded them back.
  Reported fixed in builds after 2026-09-25. If settings reset on every launch, check
  the client build before debugging the addon.

## Sending chat

- API: **`C_ChatInfo.SendChatMessage(message, chatType, languageID, target)`**.
  - `chatType` defaults to `"SAY"`. `target` is used by `"WHISPER"` (player name) and
    `"CHANNEL"` (channel number).
  - Blizzard docs flag it `HasRestrictions`, `RestrictedForMacroChatMessages`,
    `SecretArguments = AllowedWhenUntainted`.
  - `RestrictedForMacroChatMessages` applies only during an active encounter. Macros
    then can't send to channels that aren't group-only, and group or whisper sends are
    rate-limited and need everyone in the instance (Blizzard, March 2026).
- **Hardware event requirement** (since 8.2.5). Each restricted call must run inside a
  key press or mouse click handler, so a timer **cannot** send these:

  | Chat type                                                                                | Needs a hardware event?           |
  | ---------------------------------------------------------------------------------------- | --------------------------------- |
  | `CHANNEL` (`/1`, `/2`, …)                                                                | Always, outdoors and in instances |
  | `SAY`, `YELL`                                                                            | Outside instances                 |
  | `EMOTE`, `PARTY`, `RAID`, `RAID_WARNING`, `INSTANCE_CHAT`, `GUILD`, `OFFICER`, `WHISPER` | No (**verify** on Forever)        |

  Whether one key press may send _several_ messages is unconfirmed. Emote Splitter
  (see Prior art) tries, and falls back to a prompt if Blizzard blocks it. In practice,
  chunks are sent one at a time and each waits for the server echo (see below). The echo
  arrives outside the key press, so these types end up needing one key press per chunk.

- **Message length.** Blizzard's chat box (`Blizzard_ChatFrameBase/Mainline/ChatFrameEditBox.xml`
  on Forever) allows `visibleBytes="255"` of visible text plus `invisibleBytes="1023"`
  of hidden markup (hyperlink codes). That's bytes, not characters. Plain English is
  1 byte per character, but typographic characters such as `’ “ ” — …` are 3 bytes each
  in UTF-8, and letters of other languages take 2–3. Emote Splitter treats
  255 bytes as the per-message limit. How the server counts link markup is still
  **verify**. A chunk split must never:
  - cut a UTF-8 multi-byte sequence in half;
  - break a hyperlink (`|H…|h[…]|h`) or a colour escape (`|cAARRGGBB…|r`).
- **Typing past the limit**: the chat box itself refuses longer input. An addon has to
  lift that with `SetMaxLetters(0)`, `SetMaxBytes(0)` and `SetVisibleTextByteLimit(0)`.
  All three exist on Forever (`SimpleEditBoxAPIDocumentation.lua`).
- **Pre-send hook**: Blizzard's chat box triggers the `EventRegistry` event
  `"ChatFrame.OnEditBoxPreSendText"` (payload: the edit box) inside `SendText`. It
  runs after slash-command parsing and before the text is read
  (`Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua`). Blizzard's comment:
  "Notification for user addons to perform any final edits to chat text contents before
  sending." `CallbackRegistryMixin:TriggerEvent` runs each callback through
  `securecallfunction`, so editing the text there shouldn't taint Blizzard's own send
  (**verify**). It also fires after a slash command has run, with an empty box. Check
  for text before touching it.
- **Ordering and the server throttle**: sending `SAY`/`EMOTE`/`YELL` too fast gets
  messages dropped or reordered. The robust pattern is to send one chunk, wait for its
  own echo (`CHAT_MSG_SAY`, `CHAT_MSG_EMOTE`, …), then send the next. During chat
  lockdown those echoes are secret values (**verify** how that affects matching).
- **Throttling**: the server drops or disconnects on message floods. Space out
  automatic sends (**verify** safe intervals on Forever).

## Chat messaging lockdown

- **`C_ChatInfo.InChatMessagingLockdown()`** returns `true` while chat-related API
  security restrictions are in effect (Midnight-era: encounters, Mythic+, rated PvP).
- During lockdown, `CHAT_MSG_*` event payloads are **secret values**
  (`SecretInChatMessagingLockdown` in Blizzard's docs). Addon code can't read or
  compare them. Check `issecretvalue(x)` before touching a chat payload.
- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` reports whether addons may send
  outgoing chat messages on this realm.

## Tooling

- LuaLS annotations: the `ketho.wow-api` VS Code extension (0.22.x already includes
  `InChatMessagingLockdown` and the other Midnight chat APIs). It adds the library
  path to `.vscode/settings.json` automatically.
- Blizzard's generated API docs for Forever:
  `Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua` in
  [Ketho/wow-ui-source-forever](https://github.com/Ketho/wow-ui-source-forever)
  (branch `forever`). This is the authoritative signature list. `ChatInfoDocumentation.lua`
  covers the chat functions, `SimpleEditBoxAPIDocumentation.lua` the chat box limits.
  A shallow clone sits next to this repo as `../wow-ui-source-forever` for local
  searching; `git pull` it after Forever patches. The mirror can trail the client: on
  2026-11-03 it was at build 70009 while the client was at 70755.
- After an in-game session, evidence can be read from disk: BugGrabber's errors in
  `WTF\Account\<account>\SavedVariables\!BugGrabber.lua`, taint in `Logs\taint.log`
  (`/console taintLog 1`), screenshots in `Screenshots\`.

## Prior art

- [Emote Splitter](https://github.com/tmg-pub/emote-splitter) (Tammya-MoonGuard)
  solves the same problem. It lifts the chat box limits, splits UTF-8 safely,
  queues chunks and waits for each server echo. For a protected type it shows "Press
  enter to continue" and resumes on the next chat-open key press. GitHub detects no
  license, so read it for ideas and don't copy its code. Its TOC is `110207`, which is
  older than Midnight / Forever.
- [UnlimitedChatMessage](https://www.curseforge.com/wow/addons/unlimitedchatmessage)
  (Zwixx, Cyprias; GPLv3, so don't copy its code) is the Retail splitter Unbound
  replaces. It lifts the chat box limits and sends chunks through ChatThrottleLib.
- **Both replace `C_ChatInfo.SendChatMessage`** with their own function: UCM through
  AceHook's `RawHook`, Emote Splitter by plain assignment. Every message typed into
  Blizzard's chat box then runs through addon code, so the send is tainted. On Retail
  12.x chat broke in instances. BugGrabber recorded
  `[ADDON_ACTION_BLOCKED] AddOn 'UnlimitedChatMessage' tried to call the protected
  function 'UNKNOWN()'` with the stack `ChatFrameEditBox.lua SendText → UCM hook →
  SendChatMessage` (May 2026). UCM 1.0.34 unhooks during combat and Mythic+, but a
  value written by addon code stays tainted until `/reload`, so putting the original
  back doesn't help. **Unbound never replaces `SendChatMessage`.**

## Sources

- [Thunderz96/forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit):
  findings measured against the live beta client (builds 69893 → 70009).
- [Ketho/wow-ui-source-forever](https://github.com/Ketho/wow-ui-source-forever):
  FrameXML mirror for Forever (1.60.1).
- [warcraft.wiki.gg — C_ChatInfo.SendChatMessage](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendChatMessage)
- [warcraft.wiki.gg — Patch 8.2.5 API changes](https://warcraft.wiki.gg/wiki/Patch_8.2.5/API_changes):
  hardware event protection.
- [warcraft.wiki.gg — SendChatMessageType](https://warcraft.wiki.gg/wiki/API_types/SendChatMessageType):
  per-chat-type hardware event table.
- [warcraft.wiki.gg — Lua](https://warcraft.wiki.gg/wiki/Lua): Lua 5.1 subset, 5.1.1
  since patch 2.0.1.
- [warcraft.wiki.gg — Secure Execution and Tainting](https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting):
  taint spreads to anything tainted code writes and lasts until a reload.
- [Blizzard forums — Macro changes now live](https://us.forums.blizzard.com/en/wow/t/macro-changes-now-live-target-markers-and-chat-messages/2261956):
  encounter-only macro chat restrictions (March 2026).
- Blizzard forums: SavedVariables load bug reports and the "[SOLVED]" follow-up (Sep 2026).
