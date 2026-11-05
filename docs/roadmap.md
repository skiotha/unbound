# Unbound — roadmap

> A bird's-eye plan from the first usable version to the full addon. It names stages,
> their deliverables and the in-game gate that closes each one. It's deliberately not a
> spec: details are settled when a stage starts, and new findings may reorder, cut or
> add stages. Facts about the client live in [forever-api.md](forever-api.md), the
> in-game checks in [client-checks.md](client-checks.md), and the project rules in
> [copilot-instructions.md](../.github/copilot-instructions.md).

## How we work through it

- **One feature per stage.** Build it (tests first for pure logic), then someone uses
  it in game. A manual gate confirms it, written as a new section in client-checks.md
  when the stage is built. Then we decide: next stage, adjust, cut or add.
- **Gates come before stages that rely on them.** A stage that needs in-game
  confirmation doesn't start until the gate before it has passed or been explicitly
  deferred.
- **The order after 1.0 is a proposal.** What daily use shows decides it.
- **Bookkeeping.** A shipped stage gets a `> ✅ **Completed <date>.** Divergences from
the text above:` note. A stage shipped with parts left over gets a `⏳ Partial` block
  that lists the deferred parts and where they land. No test counts or other live
  status here.
- **Versions** follow the TOC `## Version`. The 0.x stages lead to the first release,
  1.0; each 1.x stage adds one feature. Numbers may shift as stages are cut or added.

## Promises that hold in every stage

From the first version that sends anything:

- **No lost text.** A post Unbound can't send in full stays recoverable. Refused or
  unconfirmed chunks are reported, never silently dropped.
- **No automatic resends.** A missing echo doesn't prove a chunk failed: whispers have
  arrived about 10 s late. Unbound reports; the player decides.
- **Blizzard's send stays Blizzard's.** Unbound only uses Blizzard's pre-send event and
  never replaces a Blizzard function (see [Prior art](forever-api.md#prior-art) for why).
- **Off in instances and during chat lockdown** until the dungeon stage: no hooks and no
  lifted limits, so chat there is pure Blizzard.
- **Limits are estimates.** The 15-message say/emote limit and the roughly 10 s recovery
  are observations, not guarantees. Keep margins.

The chat rules behind these (bytes, hardware events, languages, two-part names) are in
the [project rules](../.github/copilot-instructions.md), under Chat & Forever Rules.

## What we know so far

| Topic                                                              | Where                                                                              |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| What's confirmed and what's still open                             | [forever-api.md → Checked in game](forever-api.md#checked-in-game)                 |
| Hardware events, 255 bytes, chat box limits, pre-send hook, echoes | [forever-api.md → Sending chat](forever-api.md#sending-chat)                       |
| Throttling: 15 say/emote, recovery near 10 s, whisper delays       | [forever-api.md → Sending chat](forever-api.md#sending-chat) (Throttling)          |
| Lockdown and secret chat payloads                                  | [forever-api.md → Chat messaging lockdown](forever-api.md#chat-messaging-lockdown) |
| Why earlier splitters broke chat in instances                      | [forever-api.md → Prior art](forever-api.md#prior-art)                             |
| Bursts from one key press                                          | [client-checks 8](client-checks.md#8-many-full-length-chunks-from-one-key-press)   |
| Limit and recovery measurements                                    | [client-checks 9](client-checks.md#9-how-fast-the-chat-limit-recovers)             |
| Say recovery gaps and the whisper limit                            | [client-checks 10](client-checks.md#10-say-recovery-and-whisper-limit)             |

Unknowns that shape later stages: dungeons and boss fights, party chat's limit, the
exact say/emote recovery, where whisper delays come from, how the server counts
hyperlink markup, and chat lockdown.

## Stages at a glance

| Version | Stage             | Gist                                           | Gate                           |
| ------- | ----------------- | ---------------------------------------------- | ------------------------------ |
| 0.1     | Groundwork        | Scaffold, API notes, in-game checks            | Checks 1–10 (outdoors)         |
| 0.2     | Splitter          | Cut text into safe chunks; pure Lua            | Unit tests, sample review      |
| 0.3     | Say and emote     | Long say/emote on one Enter, outdoors          | Outdoor acceptance             |
| 0.4     | Whispers          | Long whispers, usually 2–3 chunks              | Self and another player        |
| 0.5     | Party             | Long party messages                            | Group check (deferred)         |
| **1.0** | **First release** | 0.2–0.5 polished by daily use                  | Ordinary RP sessions           |
| 1.1     | Send budget       | Count recent sends; don't hit the limit        | Mixed typed and split bursts   |
| 1.2     | Long posts        | Tail waits for the next Enter; "wait N s" hint | 20–30 chunk post               |
| 1.3     | Delivery tracking | Know which chunks arrived; return the rest     | Forced refusals, late whispers |
| 1.4     | Settings          | `/ub` options in `UnboundDB`                   | Survive reload and restart     |
| 1.5     | Dungeons          | Work in instances or stay off, proven clean    | Dungeon run and boss fight     |

**Fully featured** means 1.1–1.5 are done. Stages under "Later, if wanted" are extras.

## 0.1 Groundwork

Scaffold (TOC, SavedVariables, `/ub` help, test runner, CI), the AddOns link, the
icon, the Forever API notes and checks 1–10 outdoors.

> ✅ **Completed 2026-11-05.** Divergences from the text above: none (written after the
> fact). Dungeon checks (3.7, 4.3, 5.4, 6) and party limits move to stages 1.5 and 0.5.

## 0.2 Splitter

Cut a long text into chunks that each fit one message, without breaking anything. No
change in game yet.

- A pure-Lua module in `Util/`, written test-first.
- Chunks of at most 255 bytes, cut at the last whitespace that fits. Split a word
  only when it cannot fit on its own, at a UTF-8 boundary. No sentence preference.
  Never cut inside a UTF-8 sequence, a hyperlink, a colour escape or another `|` escape.
- Link markup counts in full until the server's counting is checked (conservative).
- Preserve colour across chunk boundaries by closing and reopening the active colour
  stack, including nested colours. Count all added markup in the 255-byte limit.
- Trim leading/trailing whitespace, including at chunk boundaries, without rewriting
  whitespace inside a chunk or the contents of links and escapes.
- No continuation markers. Custom markers and their byte budgeting are a much later
  discussion, not part of the initial splitter or settings stage.
- Malformed input or an indivisible unit that exceeds the byte limit returns an
  explicit failure, not truncated text or partial chunks. The caller keeps the
  original post; there is no automatic fallback send.

**Gate:** unit tests, plus we review where two or three lorem-ipsum posts get cut.
Include UTF-8 punctuation and link cases, not just ASCII filler. Use lorem-ipsum
posts for later client checks too, with actual client-inserted links where relevant.

The supported escape forms and failure contract are in
[README → Splitter contract](../README.md#splitter-contract). Unknown forms fail
explicitly rather than being split speculatively.

> ✅ **Completed 2026-11-05.** Divergences from the text above: none.
> The gate was unit tests and offline sample review, not an in-game send check.
> Chat integration, outgoing hyperlink/colour acceptance and markup byte counting
> belong to 0.3; no arbitrary outgoing colour support is assumed.

## 0.3 Say and emote, outdoors

Type a long say or emote, press Enter once, and all chunks arrive in order. This is
option 1 from the checks; option 2 (one Enter per chunk) stays the fallback.

- The chat box takes long text outdoors; Blizzard's limits come back in instances and
  during lockdown.
- On Enter, Blizzard's pre-send event hands the text to Unbound. It sends the chunks in
  the same key press, in the chat box's language. Short messages pass untouched.
- A fixed cap per Enter, well under 15 (10 arrived in checks 8.3 and 8.4). A longer
  post isn't sent: Unbound says so and keeps the text.
- If the server refuses chunks right after a burst (`ERR_CHAT_THROTTLED`), Unbound
  reports it and keeps the post's text. No resend.

**Gate** (new client-checks section, `taintLog` on, BugSack watched):

- 2, 5 and cap-sized says and emotes arrive in order, in the right language;
- review emote readability with the character's name repeated before each chunk;
- a post with typographic characters and an actual item link; check hyperlink/colour
  acceptance and markup byte counting, without assuming arbitrary colours can be sent;
- an over-cap post: nothing sent, text kept;
- a forced refusal (15 typed says first): reported, text kept;
- slash commands, an empty box and `/reload` cause no errors.

Open: how text is "kept" (the box reopened, or saved for a command)? The cap's value?

## 0.4 Whispers

Long whispers, expected at 2–3 chunks, to Forever's two-part names.

- Chunks go to the chat box's whisper target on the same Enter, with a small cap
  (check 10 delivered only 10 of 20 promptly).
- Delivery is read from `CHAT_MSG_WHISPER_INFORM`. Late chunks are waited for, never
  resent.

**Gate:** 2, 3 and cap-sized whispers to yourself and to another player. A whisper to
an offline or misspelled name is reported, and the text is kept.

Open: the cap's value? Battle.net whispers are a separate type (see "Later").

## 0.5 Party

Long party messages, same flow as 0.3. Party needs no key press, but uses the same
path.

- Until party's own limit is known, party sends count against the say/emote limit
  (conservative).
- A party leader's own messages echo as `CHAT_MSG_PARTY_LEADER`.

**Gate:** the deferred party part of check 10, then acceptance in a group. If no group
is possible before 1.0, 1.0 ships with the conservative rule and this stage is marked
`⏳ Partial` until the gate runs.

## 1.0 First release

What we actually use for roleplay: say, emote, party and whispers outdoors, at
lengths that fit one burst.

- 0.2–0.5, polished from daily use. README usage section, version 1.0.0. We tag
  the release.

**Gate:** a few ordinary RP sessions with no lost text, no Lua errors and no chat
trouble afterwards. Notes from these sessions decide the order of the 1.x stages.

## 1.1 Send budget

Don't hit the limit in the first place.

- Unbound counts say and emote messages over the last ~12 s, typed ones included, and
  sends only what fits. Whispers get their own budget.
- The fixed cap stays as an upper bound, for etiquette.
- A post that doesn't fit right now is handled as an over-cap post in 1.0 (until 1.2).

**Gate:** typed and split messages mixed near the limit: no refusals.

## 1.2 Long posts: the tail

Posts longer than one burst.

- Unbound sends what fits; the rest (the tail) waits for the next Enter.
- A local "wait N s" hint, shown only to the player, when the budget hasn't recovered
  yet.
- One chunk per Enter is the same mechanism, so option 2 comes almost free if
  instances or a patch need it.

**Gate:** a 20–30 chunk post. Enter too early shows the hint and nothing is refused;
after the wait, Enter sends the next part.

Open: where the tail lives (box reopened, or held until the next Enter)? Changing chat
type or target with a tail pending? Cancelling a tail?

## 1.3 Delivery tracking

Know exactly which chunks arrived.

- Each chunk is unsent, awaiting its echo, or confirmed. Echoes are matched to chunks;
  refusals are counted.
- After a refusal or a timeout, unconfirmed chunks go back to the tail (1.2) for the
  player to send. Nothing is resent automatically, and late whispers are waited for.

**Gate:** forced refusals in say and whisper, and a late whisper: no duplicates, no lost
chunks.

## 1.4 Settings

Tune behaviour without editing code.

- `/ub` options stored in `UnboundDB`. Candidates: the cap per Enter, what to do with
  very long posts, the hint, chat types on or off.
- Maybe a `/ub status` line (budget left, time to recovery). Low priority while
  recovery is about 10 s.
- An options panel only if slash options feel clumsy.
- A stage that clearly needs an option ships it itself; this stage collects the rest.

**Gate:** settings survive a reload and a restart; defaults behave as before.

## 1.5 Dungeons

Decide Unbound's place in instances. Needs a levelled character, not the earlier 1.x
stages, so it can move earlier.

- Run the deferred checks: 3.7, 4.3, 5.4 and 6 in a dungeon and during a boss fight.
- Then either Unbound works where the checks show it's safe (maybe out of combat and
  lockdown only), or it stays off and we show that outdoor use leaves no taint behind.
- Entering or leaving an instance with a tail pending or the chat box open.

**Gate:** a dungeon run with `taintLog` on. Typed chat works in every type, before,
during and after a boss; BugSack stays empty.

## Later, if wanted

- **After 1.0: deliberate newlines and paragraphs for RP.** Discuss multiline input
  (for example Ctrl+Enter), pasted newlines, and how paragraph breaks map to chat
  messages. No new input binding or paragraph behaviour in 0.2.
- **Much later: custom continuation markers.** Discuss user-configured prefixes or
  suffixes and update the splitter to include their bytes in every chunk's limit.
- **Post-release: optional colour authoring.** If client checks establish that outgoing
  colours work, discuss helping the player colour input text. The initial splitter
  only preserves existing markup; it does not introduce a colour-input feature.
- **Manual bypass after a splitter failure.** Consider a quick "use Blizzard chat
  as-is" switch, since a rejection may expose a parser bug rather than bad user
  input. Restore Blizzard's normal limits; bypass cannot make an oversized message
  valid and must not automatically resend anything.
- Other chat types: yell, raid, instance, guild, officer, channels, Battle.net
  whispers. Each needs its own limit and key-press check first.
- Whatever daily use suggests.

## Gates outside the stages

- **Instance smoke test**, as soon as any dungeon is reachable, whatever the stage.
  After using Unbound outdoors, without a reload, enter a dungeon and type a say, an
  emote and a party message. Chat must work. This guards the reason Unbound exists;
  if it fails, stop and investigate before any new feature.
- **After each Forever patch:** update the TOC interface number if needed, and re-run
  the checks for chat box limits (2), bursts (8) and the say limit (9.3).

## Fallbacks

- **Several sends per key press get blocked:** option 2, one chunk per Enter (see 1.2).
- **Hooking Blizzard's chat box taints instance chat:** keep Unbound off in instances
  (the current rule). As a last resort, an Unbound-owned input box that leaves
  Blizzard's alone (an idea only).

## Not planned

- Replacing `C_ChatInfo.SendChatMessage` or any other Blizzard function.
- Libraries such as ChatThrottleLib.
- Automatic resends.
