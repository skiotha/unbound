# Unbound

A World of Warcraft addon that splits a long chat message into chunks and sends
them one by one. Built for **World of Warcraft: Forever**, mostly for
personal use.

> Early development. Long says and emotes are split and sent on one Enter, outdoors.
> Stage 0.3 of the [roadmap](docs/roadmap.md) is complete: its in-game gate passed.

- **Zero external dependencies**: no Ace3, LibStub or other third-party libraries.
- Currently not distributed via CurseForge / WoWInterface / whatever.

## Project Structure

```
Unbound/                -- the addon folder, which ships to Interface/AddOns/Unbound/
├── Unbound.toc         -- manifest: load order, SavedVariables, version
├── Util/
│   ├── Defaults.lua    -- SavedVariables defaults helper
│   ├── Splitter.lua    -- pure UTF-8 and markup-aware text splitting
│   └── Post.lua        -- pure decision: leave a post to Blizzard, split it, or keep it
├── ChatBox.lua         -- chat box glue: long text, sending on Enter, refusal reports
└── Unbound.lua         -- entry point: events, SavedVariables init, slash commands
test/                   -- DIY test runner, WoW API stubs, tests, that is not shipped
docs/                   -- design notes and API reference, that is also not shipped
```

## Installation

Just copy or link the `Unbound/` folder into the Forever client's
`_forever_\Interface\AddOns\` directory. Then restart the client. Or type `/reload`.

## Usage

Outdoors, type a long say or emote and press Enter once. Unbound splits it into
messages of up to 255 bytes and sends them all, in order, in the language picked in
the chat box. Short messages are left to Blizzard.

- One Enter sends at most **8** messages (about 1,950 characters). A longer post isn't
  sent.
- Long text in other chat types (party, whispers, yell, channels) isn't split yet, and
  isn't sent either.
- Every split or unsent post is kept in the chat box history. Open the chat box and
  press Alt+Up to get it back. The history doesn't survive `/reload`.
- If the server refuses some of the messages, Unbound says how many. It doesn't resend.
  Alt+Up brings back the whole post, including the messages that arrived, so delete
  those before you send it again.
- In instances and during chat lockdown, Unbound stays off and the chat box is
  Blizzard's own.
- `/unbound` or `/ub`: show the version and the list of commands.

## Development

### Setup

Link the addon folder into the client so WoW loads it straight from the working copy:

```powershell
New-Item -ItemType Junction `
    -Path "<WoW install>\_forever_\Interface\AddOns\Unbound" `
    -Target "<your-clone-path>\Unbound"
```

No admin rights are needed if you can write to `AddOns`. To remove the link
without touching the source files, run `cmd /c rmdir "<link path>"`.

Recommended VS Code extensions: **Lua** and **WoW API** for completion
and diagnostics. The WoW API extension configures `.vscode/settings.json` automatically.

### Testing

Pure logic can be tested outside the game with **Lua 5.1** and a hand-written runner:

```powershell
lua test/run.lua                        # all tests
lua test/run.lua test/test_defaults.lua # selected files
```

On Windows, `winget install rjpcomputing.luaforwindows` provides Lua 5.1.5. CI runs the
same command on every push (see `.github/workflows/test.yml`).

### Splitter contract

`ns.SplitText(text)` is pure Lua 5.1, with no WoW API calls or side effects. It returns
an ordered array of nonempty chunks, each at most **255 bytes**, counting all markup.
On failure it returns `nil, errorMessage`, never partial chunks. The caller must
report the error and retain the original input; this function does not send anything.
Empty or whitespace-only input returns an empty array, as does colour-only input.

- Prefer the last whitespace that fits. Move a word to the next chunk if it fits
  there; split an oversized word only at a UTF-8 code-point boundary.
- Trim ASCII whitespace (space, tab, CR, LF, vertical tab, form feed) at chunk edges.
  Preserve interior whitespace and the contents of markup. Newlines inside chunks
  remain unchanged: there is no paragraph-to-message conversion or new input binding.
- Preserve complete hyperlinks (`|Htype:payload|hlabel|h`), escaped pipes (`||`),
  textures (`|T...|t`) and atlases (`|A...|a`) as indivisible units.
- Preserve hex colours (`|cAARRGGBB...|r`) and named colours (`|cnNAME:...|r`, including
  item-quality names such as `IQ4`). Close and reopen the full active colour stack at
  chunk boundaries, counting the added bytes. Links can contain balanced formatting,
  but cannot nest links or open/close a colour across the link's own boundary.
- Reject malformed UTF-8, non-whitespace ASCII control characters, unbalanced markup,
  unsupported `|` escapes (including `|n`), or any indivisible unit that cannot fit
  with its colour overhead. Text errors include a 1-based byte position.

This checks markup structure, not link IDs, texture parameters, named-colour
availability, or what the server permits sending. Supporting a UI escape here does
**not** establish that Forever accepts it in outgoing chat. See
[the API notes](docs/forever-api.md#sending-chat) for the remaining client checks.
There are no continuation markers, sentence heuristics or configurable limits.

## Documentation

| Document                                                   | Description                                                      |
| ---------------------------------------------------------- | ---------------------------------------------------------------- |
| [forever-api.md](docs/forever-api.md)                      | What's specific about the Forever client and the chat API we use |
| [client-checks.md](docs/client-checks.md)                  | In-game checks that confirm the API facts                        |
| [roadmap.md](docs/roadmap.md)                              | Planned stages from the first release to the full addon          |
| [copilot-instructions.md](.github/copilot-instructions.md) | Project rules for contributors and AI agents                     |

## License

[MIT](LICENSE)
