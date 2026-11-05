# Unbound

A small World of Warcraft addon that splits a long chat message into chunks and sends
them one by one. Built for **World of Warcraft: Forever** (interface `16001`), for
personal use.

> Early scaffolding. The splitting and sending features are still being designed.

- **Zero external dependencies**: no Ace3, LibStub or other third-party libraries.
- Not distributed via CurseForge / WoWInterface.

## Project Structure

```
Unbound/                -- the addon folder (ships to Interface/AddOns/Unbound/)
├── Unbound.toc         -- manifest: load order, SavedVariables, version
├── Util/
│   └── Defaults.lua    -- SavedVariables defaults helper
└── Unbound.lua         -- entry point: events, SavedVariables init, slash commands
test/                   -- DIY test runner, WoW API stubs, tests (not shipped)
docs/                   -- design notes and API reference (not shipped)
```

## Installation

Copy (or link, see below) the `Unbound/` folder into the Forever client's
`_forever_\Interface\AddOns\` directory, then restart the client or type `/reload`.

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

No admin rights are needed if your user can write to `AddOns`. To remove the link
without touching the source files, run `cmd /c rmdir "<link path>"`.

Recommended VS Code extensions: **Lua** (`sumneko.lua`) and **WoW API**
(`ketho.wow-api`) for completion and diagnostics. The WoW API extension configures
`.vscode/settings.json` automatically.

### Testing

Pure logic is tested outside the game with **Lua 5.1** and a hand-written runner
(no busted or luarocks):

```powershell
lua test/run.lua                        # all tests
lua test/run.lua test/test_defaults.lua # selected files
```

On Windows, `winget install rjpcomputing.luaforwindows` provides Lua 5.1.5. CI runs the
same command on every push (see `.github/workflows/test.yml`).

## Documentation

| Document                                     | Description                                                      |
| -------------------------------------------- | ---------------------------------------------------------------- |
| [forever-api.md](docs/forever-api.md)        | What's specific about the Forever client and the chat API we use |
| [client-checks.md](docs/client-checks.md)    | In-game checks that confirm the API facts                        |
| [copilot-instructions.md](.github/copilot-instructions.md) | Project rules for contributors and AI agents         |

## License

[MIT](LICENSE)
