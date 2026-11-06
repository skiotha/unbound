# WoW: Forever — API notes

> Reference for what is specific about the **World of Warcraft: Forever** client and
> the chat API. Facts sources are at the bottom and relevant for September 2026.
> Items marked **verify** have not yet been confirmed in our own client;
> [client-checks.md](client-checks.md) has the steps. Items marked **confirmed** were
> tested in our client, at the build named in [Checked in game](#checked-in-game).

## Checked in game

First round: 2026-11-05 (launch day), client `1.60.1.70790`, open world only, with
BugGrabber, BugSack and Total RP 3 loaded. Second to sixth rounds: later the same
day, same setup (build not re-checked). The first run of the 0.3 gate (check 12),
with Unbound 0.3.0, was the same day too, and its last three steps were rerun on
2026-11-06. The 0.4 gate (check 13), with Unbound 0.4.0, ran on 2026-11-06. Results
are filed under their topics below.

Still open:

- Dungeon (out of combat) and boss fight: client-checks 3.7, 4.3, 5.4 and 6. They need a
  levelled character. Until then Unbound stays off in instances (project rule).
- The exact say/emote reset mechanism, including whether refused attempts extend the
  wait. Check 10 found no recovery at the tested gaps below about 10 s.
- Whisper pacing and recovery: check 10 found delayed delivery and refusals. Where
  the delay happens (client, server or another addon) remains untested. So does
  whether whispers to another player are paced like self-whispers: check 13.5 sent
  them only 2 to 4 at a time.
- **TODO, deferred until group testing is possible:** whether party chat has a limit of
  its own or shares the say/emote limit (check 10).
- Whether the server counts hyperlink markup in full. Chunks that count it in full
  arrive (check 12.5), but whether the server would take more is untested. Also
  untested: safe spacing between automatic sends.

## The client

- **Interface number: `16001`** (build line `1.60.x`). The number is
  major·10000 + minor·100 + patch. A `1.60.2` client would need `16002` in the TOC.
  **Confirmed**: on launch day `/dump GetBuildInfo()` printed `"1.60.1"`, `"70790"`,
  `"Nov  3 2026"`, `16001`, and the AddOns list accepted the TOC.
- **Lua**: a subset of Lua 5.1. `/dump _VERSION` prints `"Lua 5.1"` (**confirmed**),
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
  Reported fixed in builds after 2026-09-25. **Confirmed** fixed: `UnboundDB` kept a
  value across `/reload` and a full restart. If settings ever reset on every launch,
  check the client build before debugging the addon.
- **Game type `camelot`**: Blizzard's TOCs load Forever's own files with
  `[AllowLoadGameType camelot]`. In the UI source, a `Camelot\` file replaces its
  `Mainline\` or shared namesake.
- **Addon icon**: the AddOns list draws the TOC's `IconTexture` (or `IconAtlas`) as a
  20×20 inline texture (`Blizzard_AddOnList/AddonList.lua`). Texture sizes must be
  powers of two. PNG works if the path includes `.png`. **Confirmed**: Unbound's
  `Media\Icon.png` shows in the list. The minimap addon compartment
  (`AddonCompartmentFunc`) loads only for game type `mainline` (`Blizzard_Minimap.toc`),
  so Forever has none (from the source, not checked in game).
- **Two-part names**: Forever characters are named `First Surname`. `UnitName(unit)` and
  `UnitNameUnmodified(unit)` return the first name and the surname, not name and realm.
  - `NameUtil.GetUnmodifiedUnitFullName(unit)` joins them with Blizzard's separator
    (`Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR`, set by
    the client). **Confirmed**: the separator is a space (`First Surname`).
  - Typed whispers accept both `First-Surname` and `First Surname` (`ExtractTellTarget`
    in `ChatFrameEditBox.lua`). **Confirmed** with Unbound 0.4.0 (check 13.5): a long
    whisper typed to `First-Surname` arrived split, like one to `First Surname`.
  - **Confirmed**: sending a `WHISPER` to `UnitName("player")` fails with "No player named
    '<first name>' is currently playing." Sent to the full name, it arrives.
  - **Confirmed** (check 13.4): that line is `ERR_CHAT_PLAYER_NOT_FOUND_S`, delivered
    as `CHAT_MSG_SYSTEM`, once per message sent (two for a 2-piece whisper). It carries
    the name as typed.
  - **Confirmed** (check 13.2): a whisper's `CHAT_MSG_WHISPER_INFORM` echo carries the
    target's full name, joined with a space (`First Surname`), as its second argument.
  - Whisper chunks should reuse the target Blizzard's chat box already resolved
    (`editBox:GetTellTarget()`) instead of building a name.

## Sending chat

- API: **`C_ChatInfo.SendChatMessage(message, chatType, languageID, target)`**.
  - `chatType` defaults to `"SAY"`. `target` is used by `"WHISPER"` (player name) and
    `"CHANNEL"` (channel number).
  - `languageID`: Blizzard's chat box passes `editBox.languageID`, the language picked
    in the chat menu (`SendText`). The menu fills it with `GetDefaultLanguage()` when
    it's empty. In the first round, a typed `/s` and three `/run` sends with no
    `languageID` all showed as `says: [Darnassian]`. A say gets that tag whenever its
    language isn't `GetAlternativeDefaultLanguage()` (`ChatFrameOverrides.lua`), so the
    tag doesn't show what a send with no `languageID` falls back to. Unbound's chunks
    must pass the chat box's `languageID`, so they all go out in the language the
    player picked.
  - Blizzard docs flag it `HasRestrictions`, `RestrictedForMacroChatMessages`,
    `SecretArguments = AllowedWhenUntainted`.
  - `RestrictedForMacroChatMessages` applies only during an active encounter. Macros
    then can't send to channels that aren't group-only, and group or whisper sends are
    rate-limited and need everyone in the instance (Blizzard, March 2026).
- **Hardware event requirement** (since 8.2.5). Each restricted call must run inside a
  key press or mouse click handler, so a timer **cannot** send these. The wiki's table is
  for Retail; Forever is stricter about `EMOTE`:

  | Chat type                                                           | Needs a hardware event?                                                                     |
  | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
  | `CHANNEL` (`/1`, `/2`, …)                                           | Always, outdoors and in instances                                                           |
  | `SAY`, `YELL`                                                       | Outside instances. **Confirmed** for `SAY`: nothing arrived from a timer                    |
  | `EMOTE`                                                             | Outside instances (Retail: no). **Confirmed**: timer blocked, key press sends               |
  | `PARTY`                                                             | No. **Confirmed**: a timer send arrived                                                     |
  | `WHISPER`                                                           | No. **Confirmed**: a timer whisper to the full name arrived                                 |
  | `RAID`, `RAID_WARNING`, `INSTANCE_CHAT`, `GUILD`, `OFFICER`         | No (Retail wiki; not tested)                                                                |

  - **`EMOTE` on Forever** behaves like `SAY` outdoors. From a timer:
    `[ADDON_ACTION_BLOCKED] AddOn '*** ForceTaint_Strong ***' tried to call the protected
    function 'UNKNOWN()'` (`ForceTaint_Strong` is how `/run` code shows up). From a
    `/run` on a key press it arrives (**confirmed**; the first round's empty result
    didn't repeat after a `/reload`). Inside instances: **verify**.
  - **Several messages from one key press work** for `SAY` and `EMOTE`: three from one
    `/run` arrived, in order (**confirmed**). So did 6 and 10 full-length (255-byte)
    chunks, in both types (**confirmed**, client-checks 8). Every echo in a burst had the
    same `GetTime()`. More than 15 hits the throttle (see Throttling). Emote Splitter
    (see Prior art) still sends one chunk at a time and waits for each server echo (see
    below). The echo arrives outside the key press, so with that pattern these types
    need one key press per chunk.

- **Message length.** Blizzard's chat box (`Blizzard_ChatFrameBase/Mainline/ChatFrameEditBox.xml`
  on Forever) allows `visibleBytes="255"` of visible text plus `invisibleBytes="1023"`
  of hidden markup (hyperlink codes). That's bytes, not characters (**confirmed**, see
  below). Plain English is 1 byte per character, but typographic characters such as
  `’ “ ” — …` are 3 bytes each in UTF-8, and letters of other languages take 2–3. Emote
  Splitter also treats 255 bytes as the per-message limit. Chunks with item links,
  counted with all their markup, arrived (**confirmed**, check 12.5). Whether the
  server counts link markup in full is still **verify**. A chunk split must never:
  - cut a UTF-8 multi-byte sequence in half;
  - break a hyperlink (`|H…|h[…]|h`) or a colour escape (`|cAARRGGBB…|r`).

  **Markup syntax reference, not an outgoing-chat confirmation:** modern WoW's
  [UI escape sequences](https://warcraft.wiki.gg/wiki/UI_escape_sequences) include
  hex and named colours (`|cnNAME:…|r`, including `|cnIQ4:…|r`). Since 9.0.1,
  `|r` pops the innermost colour, restoring the outer one rather than always
  resetting to the default. The splitter must close/reopen the whole active stack
  when splitting coloured text. Item links inserted by the client, with their quality
  colours, are accepted in outgoing chat (check 12.5). Colours outside a link and the
  server's hyperlink byte counting are untested.
- **Over the limit, nothing is sent.** `C_ChatInfo.SendChatMessage` raises a Lua error,
  `SendChatMessage(): Chat message limits exceeded`. **Confirmed** through Blizzard's
  chat box: 600 and 300 letters failed (BugGrabber: "No Lua Taint"), 200 went out.
  **Confirmed** boundary: 255 bytes, counted in bytes. From `/run`, 255 × `x` and 85 em
  dashes (255 bytes) went out; 256 × `x` and 86 em dashes (258 bytes, 86 characters)
  raised the error.
- **Typing past the limit**: the chat box itself refuses longer input. Defaults on
  Forever: `GetMaxBytes()` 1280, `GetMaxLetters()` 0 (no limit),
  `GetVisibleTextByteLimit()` 255 (**confirmed**). An addon has to lift that with
  `SetMaxLetters(0)`, `SetMaxBytes(0)` and `SetVisibleTextByteLimit(0)`
  (`SimpleEditBoxAPIDocumentation.lua`). **Confirmed**: after that, the box took a
  600-letter paste. Pressing Enter on it hits the error above, so whatever lifts the
  limits must also shorten the text before Blizzard sends it.
- **One box per chat window, each with its own history.** Every chat window has its own
  edit box (`ChatFrame1EditBox`, …); whisper windows opened later add more
  (`FloatingChatFrame.xml`). Lifting the limits has to cover them all. Each box keeps a
  32-line history (`historyLines="32"`), cleared when its window opens. Alt+Up recalls
  a line (`ignoreArrows`), and the chat type comes back with it. Blizzard stores a sent
  line as `/say text`, `/emote text`, … (`AddHistory`). `AddHistoryLine` is a widget
  method, so filling the history from addon code writes no Blizzard Lua state (from the
  source). A typed slash command goes into the history after its handler has run
  (`ParseText`), so a line added from `/run` sits one step behind the `/run` line
  (seen in check 11). **Confirmed** (check 11.6), with the limits lifted: a 731-byte
  `/s …` line added with `AddHistoryLine` came back whole on Alt+Up, in Say mode, and
  an `/e …` line in Emote mode. **Confirmed** (check 12.6): the history keeps lines
  longer than the box's default 1280 bytes. A 2,306-byte say that Unbound refused and
  kept came back on Alt+Up, and Unbound counted 9 messages again. **Confirmed** (check
  12.8): a long whisper that Unbound refused and kept came back whole, as a whisper to
  the same two-part name. **The history doesn't survive `/reload`**: afterwards only
  lines typed since came back.
- **Pre-send hook**: Blizzard's chat box triggers the `EventRegistry` event
  `"ChatFrame.OnEditBoxPreSendText"` (payload: the edit box) inside `SendText`. It
  runs after slash-command parsing and before the text is read
  (`Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua`). Blizzard's comment:
  "Notification for user addons to perform any final edits to chat text contents before
  sending." `CallbackRegistryMixin:TriggerEvent` runs each callback through
  `securecallfunction`, so editing the text there doesn't taint Blizzard's own send.
  - **Confirmed** outdoors: a callback registered from `/run` code appended text with
    `SetText`. `SAY` (also in combat), `EMOTE`, `PARTY` and `WHISPER` went out with the
    change and no error. Outdoors, addon code on a key press may send all four itself,
    so this can't show whether Blizzard's send stayed untainted. That only matters where
    tainted sends are blocked (instances, lockdown): **verify** with the dungeon checks.
  - It also fires after a slash command has run, with an empty box. Check for text before
    touching it.
  - `SetText` in the hook runs Blizzard's slash parsing again (`OnTextSet` →
    `ParseText(0)` → `HandleChatType`). Text that starts with `/2 `, `/p ` or `/w Name `
    can switch the box's chat type, and `SendText` then sends the rest there. An empty
    box is safe: `ParseText` stops at once, and `SendText` neither sends nor adds a
    history line (**confirmed**, check 11: nothing else went out, and Alt+Up showed the
    line before). So a split post is sent by Unbound in full, and the box is emptied.
  - **Confirmed** outdoors (check 11): sending from inside the callback works on the
    Enter key press. Three `C_ChatInfo.SendChatMessage` calls on one Enter sent three
    says, and after a `/reload` three emotes, all in order. With the box's `languageID`
    every chunk went out in the language picked in the box (two characters; the default
    language and a racial one).
  - **Confirmed** with Unbound 0.3.0 (check 12), outdoors:
    - Says and emotes of 2, 5 and 8 full 255-byte chunks arrived complete and in order,
      in the picked language. So did a say typed in a whisper window's box.
    - A 408-byte say with em dashes, curly quotes and ellipses arrived intact in 2
      chunks. With three item links Shift-clicked into it, it took 3 chunks. Every
      link arrived whole and coloured, inside one chunk.
    - A long say sent during a fight arrived with no error: Unbound's own sends from
      the hook get through in combat outdoors.
  - **Confirmed** with Unbound 0.4.0 (check 13), outdoors: whispers of 2, 3 and 4 full
    255-byte chunks arrived complete and in order, to yourself and to another player.
    `editBox:GetTellTarget()` works as the send's `target`.
  - Macros don't fire it. Macro lines go through a separate box built on
    `ChatFrameEditBoxBaseMixin`, whose `OnPreSendText` is empty
    (`MacroExecutionManager.lua`). Only typed chat reaches the hook.
  - After the hook, `ChatFrameUtil.SubstituteChatMessageBeforeSend` rewrites group tags
    (`{group1}` → `{g1}`). In English that only makes the text shorter. Chunks Unbound
    sends itself skip this step, so Unbound calls it on the whole post before splitting.
- **Sticky chat types and reopening the box.** After a send, the box keeps its type for
  `SAY`, `PARTY`, `RAID`, `INSTANCE_CHAT`, `GUILD`, `OFFICER`, `WHISPER` and `CHANNEL`
  (`ChatTypeInfoConstants.lua`). `EMOTE` isn't sticky: the box falls back to the last
  sticky type. `ChatFrameUtil.OpenChat(text)` reopens the box with text in it. Called
  from addon code, it writes Blizzard state (`ACTIVE_CHAT_EDIT_BOX`, `editBox.text`,
  `editBox.setText`). The box applies the text on its next frame (`OnUpdate` →
  `SetText`, `ParseText`); that code reads the fields addon code wrote, so it probably
  runs tainted. A leading `/e` would then store a tainted chat type: the type is a frame
  attribute (`GetAttribute("chatType")`), and `SendText` reads it on the next Enter.
  **Confirmed** outdoors: `OpenChat` from a timer reopened the box in Say mode, and with
  `/e …` in Emote mode. Enter sent both with no error, and `/e` and `/s` typed afterwards,
  without a reload, went out too. As with the hook, outdoors can't show whether those
  sends were tainted.
- **Ordering and the server throttle**: sending `SAY`/`EMOTE`/`YELL` too fast gets
  messages dropped or reordered (Retail reports; Forever: see Throttling). The robust
  pattern is to send one chunk, wait for its own echo (`CHAT_MSG_SAY`,
  `CHAT_MSG_EMOTE`, …), then send the next. Bursts of up to 15 arrived in order on
  Forever (**confirmed**), so the echo wait isn't needed for ordering at that size.
  - **Confirmed** outdoors, in and out of combat: your own messages echo as
    `CHAT_MSG_SAY`, `CHAT_MSG_EMOTE` and `CHAT_MSG_WHISPER_INFORM`, with readable (not
    secret) text.
  - In a party you lead, the echo is `CHAT_MSG_PARTY_LEADER`, not `CHAT_MSG_PARTY`.
  - **Confirmed** (check 13.2): a whisper echo's text equals the sent text, byte for
    byte. Unbound matched every chunk by text and stayed quiet. The chunks of one burst
    echoed in the same frame (one `GetTime()` value).
  - During chat lockdown those echoes are secret values (**verify** how that affects
    matching).
  - An addon's event frame can get a chat event before the chat window shows it
    (**confirmed**, check 13.4). Unbound printed its report while handling the second
    "No player named …" line, and the report appeared above that line. The likely
    reason is that chat windows register their message events after addons load; that
    isn't checked in the source. A `/run` watcher registers later, so its lines come
    after the chat window's.
- **Throttling**: **confirmed** outdoors (client-checks 8.5, 9 and 10). `SAY` and `EMOTE`
  share one limit of **15 messages**, counted in messages, not bytes. Of 20 sent on one
  key press, the first 15 arrived every time: full-length or short, all in say or 10
  says then 10 emotes. For each of the rest the client printed a yellow system line:
  "The number of messages that can be sent is limited, please wait to send another
  message." Those messages were dropped, not queued or delayed, and Lua saw no error
  (BugGrabber stayed empty).
  - That line is `ERR_CHAT_THROTTLED`, byte for byte (**confirmed**, check 12.7: equal,
    88 bytes each). It's delivered as `CHAT_MSG_SYSTEM`, one per refused message in the
    isolated tests. In check 9, arrived and refused added up to the number sent, with
    refusals at the end of the burst. The system line has no chunk identifier: match own
    echoes before deciding which chunks to retry, especially if delivery is delayed or
    other sends overlap. The order of lines doesn't help. In both runs of check 12.7, a
    burst's refusal lines appeared in chat before the echo of its one accepted message.
    In the probe, they appeared between the first and second echoes.
  - The refusal lines arrive after the sending code has returned (**confirmed**, check
    12.7). A probe sent 17 says in one `/run` and saw both of its refusals only after
    the loop had finished. So a watch started after the burst still catches them.
  - **Confirmed** with Unbound 0.3.0 (check 12.7): 14 says, then a 3-chunk say. Piece 1
    arrived, and Unbound reported "The server refused 2 of 3 messages". Alt+Up brought
    back the whole post, and Enter on it sent all three pieces, piece 1 a second time.
  - **Recovery:** check 10 started with 15 successful says after a rest. Another 15 at
    2 s got none through; a further retry about 2 s later also failed. Fresh rested
    trials at a 5 s target (the screenshot shows a rounded 6 s gap) and about 8 s also
    got none through. Three bursts of 15 spaced about 10 s apart all arrived. This
    suggests recovery near 10 s, with no partial refill at the sampled times; it does
    not establish an exact boundary, a fixed versus rolling window, or whether refused
    attempts restart a cooldown.
  - Check 9 also got 15 through after gaps of 11, 12, 31, 61 and 122 s, as after a
    3-minute rest. No refusal penalty persisted beyond the tested 11-12 s gaps. A
    budget counting recent sends over 12 s is a conservative estimate from these
    observations, not a guaranteed server quota or an API-provided reset time.
  - **Whispers are also throttled, and can be delayed.** In check 10, one
    `UBT.go(20,0,"WHISPER")` submitted 20 short self-whispers: 1-10 arrived promptly,
    11-15 arrived about 10 s later without another send, and the last five were
    refused with the same system text. The helper called the send API in a loop; its
    timers only printed. The source of the delay is unknown. A self-whisper appears
    twice in chat (received and sent); only `CHAT_MSG_WHISPER_INFORM` counts here.
    Do not treat a successful API return, or a missing echo after 3 s, as a delivery
    result. Retrying delayed chunks early could duplicate them.
  - Check 13.7 sent 10 short self-whispers from one `/run`, then a 4-chunk whisper
    from Unbound about a second later. All 14 arrived promptly, the 4 chunks echoing in
    one frame, with no system line. So the 10 prompt whispers of check 10 aren't a
    simple cap of 10 per few seconds. Whether the gap or the single 20-message loop made
    the difference is untested.
  - In check 9, 10 says plus 10 self-whispers all arrived. That rules out a simple
    shared 15-message cap for that mixed burst, not all interaction between their
    limits. It does not make whispers unlimited. Party-chat testing remains deferred.
  - **Check 10 helper correction:** the original immediate summary ran before chat
    events arrived, printing `0 ok, 0 limited` even when delivery or refusals followed.
    Its totals are invalid; the results above use the visible numbered messages,
    system lines and reported timing. The checklist now uses explicit snapshots.
  - Disconnects on floods are reported for Retail; none on Forever (check 9 sent 235
    messages in under half an hour).

## Chat messaging lockdown

- **`C_ChatInfo.InChatMessagingLockdown()`** returns `true` while chat-related API
  security restrictions are in effect (Midnight-era: encounters, Mythic+, rated PvP).
  **Confirmed** `false` outdoors, in and out of combat (`IsInInstance()` also `false`).
  Dungeon and boss fight: **verify**.
- During lockdown, `CHAT_MSG_*` event payloads are **secret values**
  (`SecretInChatMessagingLockdown` in Blizzard's docs). Addon code can't read or
  compare them. Check `issecretvalue(x)` before touching a chat payload.
- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` reports whether addons may send
  outgoing chat messages on this realm.
- **`ADDON_RESTRICTION_STATE_CHANGED`** (payload: type, state) fires before a restriction
  becomes active and after it ends. Type `Enum.AddOnRestrictionType.Chat` (5) is "addon
  chat communications are restricted", probably the lockdown above (**verify**).
  `C_RestrictedActions.IsAddOnRestrictionActive` always returns `false` while that
  event is being dispatched, so read the payload (from the generated docs).

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
  2026-11-05 it was still at build 70009 while the client was at 70790.
- After an in-game session, evidence can be read from disk: BugGrabber's errors in
  `WTF\Account\<account>\SavedVariables\!BugGrabber.lua`, taint in `Logs\taint.log`
  (`/console taintLog 1`), screenshots in `Screenshots\`.
  - BugGrabber reports `ADDON_ACTION_BLOCKED` **once per addon per session** (its
    `badAddons` table) and turns off Blizzard's own "Interface action failed" message,
    so later blocks in that session are silent. All `/run` code counts as one addon,
    `*** ForceTaint_Strong ***`. `/reload` before each check that might be blocked.
  - `taintLog` isn't saved in `Config.wtf`, so set it again after every restart. Level
    1 records only blocked actions and the taint behind them, and the client writes the
    file periodically and at logout. No `taint.log` appeared in the first round (the
    restart in check 1.4 had probably turned `taintLog` off), nor in the check 12
    round, where it was on, nor after its rerun. BugGrabber recorded no blocked action
    in either, so the missing file most likely means nothing was blocked.

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
