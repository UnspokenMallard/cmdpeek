# cmdpeek

Show the **N most recently installed CLI commands** from Chocolatey, Scoop, and WinGet — plus the 1–3 usages you actually need.

```powershell
cmdpeek 3
```

```
Last 3 installed commands:

1. yt-dlp (scoop)
   -  yt-dlp <URL>                    # Download video
   -  yt-dlp -f bestaudio <URL>       # Extract audio only

2. fd (scoop)
   -  fd <pattern>                    # Find files
   -  fd -t f <pattern>               # Find files only

3. jq (choco)
   -  jq '.field' file.json           # Extract field
   -  jq 'map(.name)' file.json       # Transform array
```

## Why cmdpeek?

Package managers tell you *what* is installed. They do not remind you *how* to use the new binary, or that you uninstalled it last week. cmdpeek reads local install metadata (no scraping of PM logs in v0.1 — filesystem + manifests), caches it, and attaches community examples.

## Install

Windows 10/11, PowerShell 5.1 or PowerShell 7+.

### Standalone (works without a package manager)

From a clone:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

From GitHub once the repo is public:

```powershell
irm https://raw.githubusercontent.com/cmdpeek/cmdpeek/main/install.ps1 | iex
```

### Scoop

```powershell
scoop install .\scoop\cmdpeek.json
```

After the GitHub repo exists you can add a bucket and `scoop install cmdpeek`.

### Chocolatey

```powershell
choco pack .\chocolatey\cmdpeek.nuspec
choco install cmdpeek -s . -y
```

### WinGet

The file `winget/manifest.yaml` is a submission template for [winget-pkgs](https://github.com/microsoft/winget-pkgs). Until a release ZIP with a real SHA256 is published, use `install.ps1`.

### First run with no package manager

cmdpeek detects `choco`, `scoop`, and `winget`. If none are on PATH it prints bootstrap commands and (in interactive mode) offers to run one:

1. **Scoop** — user-level, recommended
2. **Chocolatey** — typically needs an elevated shell
3. **WinGet** — App Installer / Microsoft Store

## Usage

| Command | Mode |
| --- | --- |
| `cmdpeek` or `cmdpeek -i` | Arrow-key TUI (list + live preview) |
| `cmdpeek 5` or `cmdpeek -n 5` | Quick view: installs **since last look** (default), up to N with 1–3 examples; if none, falls back to newest N with header `No new installs since …` |
| `cmdpeek -Since 7d` | Time window for quick view / MCP: `last` (default), `all`, ISO datetime, `24h`, or `7d` (minutes not supported) |
| `cmdpeek -Search rg` | Unique exact name: cheat sheet (usages + missing related). Otherwise search. |
| `cmdpeek fd` | Unique command name: cheat sheet (usages + missing related). Otherwise search. |
| `cmdpeek -Category media` | Filter by catalog category |
| `cmdpeek -Json` | Full inventory JSON (for MCP / scripts) |
| `cmdpeek -Gaps` | JSON gaps: missing related, thin docs, not-on-path, **shadowing**, incomplete **kits**, and **category-neighbor** |
| `cmdpeek -Export backup.json` | Backup favorites, hidden commands, and history |
| `cmdpeek -Import backup.json` | Restore |
| `cmdpeek -Reinstall fd -Manager scoop` | Reinstall a tracked package |
| `cmdpeek -NonInteractive -n 5` | No prompts (CI / scripts) |
| `cmdpeek -Hide LogExpert` | Hide a command from `-n` (still listed in `-i`) |
| `cmdpeek -Star fd` | Favorite a command without opening the TUI |

### Interactive TUI

`cmdpeek` with no arguments opens a two-pane terminal UI (Windows 10/11 console / Windows Terminal). If stdin/stdout is redirected it falls back to a numbered menu.

```
 cmdpeek
> fd               scoop       2025-08-19 | fd
  jq               chocolatey  2025-08-18 | scoop  2025-08-19  dev-tools
  rg               scoop       2025-08-17 |
                                          | > fd <pattern>                    # Find files
                                          |   fd -t f <pattern>               # Find files only
                                          | gaps: rg, fzf
↑↓ move  ←→ pane  ↵ open/copy  / search  f fav  F favs  C cat  h hide  H hidden  g gaps  ? help  q quit
```

| Key | Action |
| --- | --- |
| ↑ ↓ PgUp PgDn Home End | Move in the active list |
| ← → Tab | Switch list vs preview pane |
| Enter | Open detail (list) or copy the highlighted usage (preview) |
| / | Live search by name, package, manager, or usage (type, Backspace, Enter to keep, Esc to clear) |
| f | Toggle favorite |
| Shift+F | Show favorites only (toggle) |
| Shift+C | Cycle catalog category filter |
| Shift+H | Show hidden commands only (toggle), so they can be unhidden |
| h | Hide/unhide this command from `cmdpeek -n` quick view (still listed in the TUI) |
| g | Gap view — related CLIs you do not have, and commands with only `--help` |
| c / r | Copy or run the highlighted usage (`<placeholders>` are copied, not run) |
| a | Clear filters |
| ? or F1 | Key help |
| Esc | Back / clear filter / quit |
| q | Quit |

### MCP server (any AI tool)

cmdpeek speaks MCP over stdio so Cursor, Claude Desktop, and other agents can discover newly installed CLIs and point out gaps.

```powershell
cd mcp
npm install
npm run build
```

Cursor / Claude Desktop config:

```json
{
  "mcpServers": {
    "cmdpeek": {
      "command": "node",
        "args": ["C:/path/to/cmdpeek/mcp/dist/index.js"],
        "env": {
          "CMDPEEK_ROOT": "C:/path/to/cmdpeek"
        }
    }
  }
}
```

On Windows, `pwsh` is used to scan installs (`CMDPEEK_PWSH` overrides the shell). Set `CMDPEEK_ROOT` if the server is not sitting in this repo layout.

| Tool | Purpose |
| --- | --- |
| `list_recent_commands` | Recency envelope from `-Json -Recent`: optional `since` (`last`, `all`, ISO, `24h`, `7d`); `mode` is `delta` or `fallback`; each command includes `shims` and `onPath` |
| `search_commands` | Find a CLI by name, category, or usage text |
| `get_command` | Full detail + related missing tools |
| `list_gaps` | Missing related, thin docs, not-on-path, shadowing, kit, and category-neighbor; filter with `kind` (`missing-related`, `thin-docs`, `not-on-path`, `shadowing`, `kit`, `category-neighbor`, `all`) |
| `list_package_managers` | choco / scoop / winget detection |
| `list_favorites` | User-starred commands |
| `list_hidden` | Commands hidden from `-n` |
| `set_hidden` | Hide/unhide a command from `-n` |
| `set_favorite` | Star/unstar a command |
| `refresh_inventory` | Rescan after install/uninstall |

Resources: `cmdpeek://inventory`, `cmdpeek://gaps`.

Agents should call `list_recent_commands` after a package install and `list_gaps` when suggesting the next tool to add.

### Uninstall detection

On startup cmdpeek compares the last scan to what is still installed. If a tracked command disappeared:

```
Command 'yt-dlp' was uninstalled. Reinstall it? [Y/n/chocolatey/scoop/winget]
```

`-NonInteractive` prints the same information without prompting.

## How install dates are found

| Manager | Source |
| --- | --- |
| Scoop | `~\scoop\apps\<name>` timestamps + `manifest.json` `bin` |
| Chocolatey | `%ChocolateyInstall%\lib\<pkg>` + `%ChocolateyInstall%\bin` shims |
| WinGet | `%LOCALAPPDATA%\Microsoft\WinGet\Packages` folder timestamps + `.exe` files that are console apps resolvable on PATH (GUI helpers are skipped) |

Commands without a CLI shim (runtimes, fonts, GUI-only apps) are skipped.

## Data and privacy

State lives in `%LOCALAPPDATA%\cmdpeek\state.json` (favorites, commands hidden from `-n`, preferred package manager, last scan). `state.json` does not include telemetry or example-use counters; those unused fields are ignored if an older file still has them.

Optional AI examples are not called unless you add an API key later (`CMDPEEK_OPENAI_API_KEY` is reserved; unused in 0.1.0).

## Shell integration

`install.ps1 -AddProfileHint` appends scoop/choco wrappers to your PowerShell profile so `scoop install` / `choco install` print `cmdpeek -n 1` for the new command. You can also add the same snippet yourself:

```powershell
Add-CmdPeekProfileHint -ProfilePath $PROFILE
```

The wrappers call the real `scoop`/`choco` executables, then `cmdpeek -NonInteractive -n 1`. Re-running the helper is a no-op if the snippet is already present.

## Development

```powershell
Import-Module .\src\cmdpeek.psd1 -Force
Invoke-Pester -Path .\tests
.\src\cmdpeek.ps1 -NonInteractive -n 5
.\src\cmdpeek.ps1 -Json
cd mcp; npm install; npm run build
```

Requires [Pester](https://pester.dev/) 5+ (`Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck`).

## License

MIT. See [LICENSE](LICENSE).
