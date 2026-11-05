# Unbound

A World of Warcraft addon that splits a long chat message into chunks and sends
them one by one. Built for **World of Warcraft: Forever**, mostly for
personal use.

> Early scaffolding. The splitting and sending features are still being designed.

- **Zero external dependencies**: no Ace3, LibStub or other third-party libraries.
- Currently not distributed via CurseForge / WoWInterface / whatever.

## Project Structure

```
Unbound/                -- the addon folder, which ships to Interface/AddOns/Unbound/
├── Unbound.toc         -- manifest: load order, SavedVariables, version
├── Util/
│   └── Defaults.lua    -- SavedVariables defaults helper
└── Unbound.lua         -- entry point: events, SavedVariables init, slash commands
test/                   -- DIY test runner, WoW API stubs, tests, that is not shipped
docs/                   -- design notes and API reference, that is also not shipped
```

## Installation

Just copy or link the `Unbound/` folder into the Forever client's
`_forever_\Interface\AddOns\` directory. Then restart the client. Or type `/reload`.

## Usage

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

## Documentation

| Document                                                   | Description                                                      |
| ---------------------------------------------------------- | ---------------------------------------------------------------- |
| [forever-api.md](docs/forever-api.md)                      | What's specific about the Forever client and the chat API we use |
| [client-checks.md](docs/client-checks.md)                  | In-game checks that confirm the API facts                        |
| [roadmap.md](docs/roadmap.md)                              | Planned stages from the first release to the full addon          |
| [copilot-instructions.md](.github/copilot-instructions.md) | Project rules for contributors and AI agents                     |

## License

[MIT](LICENSE)
