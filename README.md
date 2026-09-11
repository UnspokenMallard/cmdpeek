# cmdpeek

Show the **N most recently installed CLI commands** — and, for agents, **which installed tool already solves the task**.

```powershell
cmdpeek 3
cmdpeek for json
cmdpeek have search
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

Package managers tell you *what* is installed. They do not remind you *how* to use the new binary, or that you uninstalled it last week. cmdpeek reads local install metadata (filesystem + manifests), caches it, and attaches community examples.

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
irm https://raw.githubusercontent.com/UnspokenMallard/cmdpeek/main/install.ps1 | iex
```

### Scoop

```powershell
scoop install .\scoop\cmdpeek.json
```

After the GitHub repo exists you can add a bucket and `scoop install cmdpeek`. Tag `v*` to build a portable zip; `.\scripts\New-CmdPeekReleaseArchive.ps1 -UpdateManifest` writes this file's `url`/`hash` from that zip.

### Chocolatey

```powershell
choco pack .\chocolatey\cmdpeek.nuspec
choco install cmdpeek -s . -y
```

### WinGet

The file `winget/manifest.yaml` is a submission template for [winget-pkgs](https://github.com/microsoft/winget-pkgs). Pack a real installer with `.\scripts\New-CmdPeekReleaseArchive.ps1`; pushing a `v*` or numeric tag (or running the release workflow with `attach_tag`) attaches the zip. Until that asset exists, `InstallerSha256` hashes the mock payload in `examples/mocks/` and you should install with `install.ps1`.

### First run with no package manager

cmdpeek detects `choco`, `scoop`, `winget`, `pipx`, `npm`, `cargo`, `brew`, `apt`, and `pacman`. If none of the Windows managers are on PATH it prints bootstrap commands and (in interactive mode) offers to run one. PATH-only machines still work: catalog names and curated OS builtins already on PATH are inventoried. System32 / `/bin` scans add extra console binaries (capped) that are not in the catalog.

1. **Scoop** — user-level, recommended on Windows
2. **Chocolatey** — typically needs an elevated shell
3. **WinGet** — App Installer / Microsoft Store
4. **pipx / npm / cargo / Homebrew** — language and Unix toolchains, scanned when present
5. **apt / pacman** — `/var/lib/dpkg/status` and `/var/lib/pacman/local` when those commands are on PATH

## Usage

| Command | Mode |
| --- | --- |
| `cmdpeek` or `cmdpeek -i` | Arrow-key TUI (list + live preview) |
| `cmdpeek 5` or `cmdpeek -n 5` or `cmdpeek recent` | Quick view: installs **since last look** (default), up to N with 1–3 examples; if none, falls back to newest N; a short rusty block may appear above that fallback |
| `cmdpeek -Since 7d` | Time window for quick view / MCP: `last` (default), `all`, ISO datetime, `24h`, or `7d` (minutes not supported) |
| `cmdpeek -Search rg` | Unique exact name: cheat sheet (usages + missing related). Otherwise search. |
| `cmdpeek fd` | Unique command name: cheat sheet (usages, substitutes, install line). Otherwise search. |
| `cmdpeek explain fd` | Command card: origin, gotchas, collisions, PATH winner, substitutes |
| `cmdpeek for json` | **Installed tools first** (OS-aware), then catalog tools to install |
| `cmdpeek why jq` | Why this tool exists here: origin, managers, PATH winner, substitutes |
| `cmdpeek compare robocopy Copy-Item` | Side-by-side cards and which to prefer on this OS |
| `cmdpeek suggest "ps aux"` | Map a command line to an installed equivalent |
| `cmdpeek have search` | Installed catalog tools you can already use (optional capability) |
| `cmdpeek agent-export` | Markdown playbook of this machine's installed tools (for agents) |
| `cmdpeek search-available fzf` | Catalog search (installed vs missing + install commands) |
| `cmdpeek gaps` | Human-readable gaps, ranked and capped |
| `cmdpeek doctor` | Environment, catalog, and cache health check; `-Timing` adds per-stage scan timings |
| `cmdpeek --version` | Module and MCP server versions, and whether they agree |
| `cmdpeek catalog-lint` | Validate the catalog files against the schema and report field coverage (exit 1 on error) |
| `cmdpeek -Category media` | Filter by catalog category |
| `cmdpeek -Json` | Full inventory JSON (for MCP / scripts); add `-Refresh` to bypass cache |
| `cmdpeek -Gaps` | JSON gaps: missing related, thin docs, not-on-path, **shadowing** (PATH winner), incomplete **kits** (with install commands), and **category-neighbor** |
| `cmdpeek -Rusty` | Installed tools missing from recent PSReadLine history (never / not in last 500 lines) |
| `cmdpeek -Export backup.json` | Backup favorites, hidden commands, and history |
| `cmdpeek -Import backup.json` | Restore |
| `cmdpeek -Reinstall fd -Manager scoop` | Reinstall a tracked package |
| `cmdpeek -NonInteractive -n 5` | No prompts (CI / scripts) |
| `cmdpeek -Hide LogExpert` | Hide a command from `-n` (still listed in `-i`) |
| `cmdpeek -Star fd` | Favorite a command without opening the TUI |

### Keeping answers small

A populated machine has thousands of binaries on PATH, and an unbounded answer is useless to an agent with a context window. Gaps are ranked (incomplete kits first, then missing-related, shadowing, not-on-path, category-neighbor) and capped, and the `thin-docs` kind is left out of the default answer because it is mostly noise.

`-Gaps` returns `{ gaps, summary }`. The summary carries `total`, `returned`, `truncated`, and a per-kind `counts` map, so nothing is hidden — you can see that 1198 thin-docs rows exist without being handed them:

```json
{
  "gaps": [ { "kind": "missing-related", "command": "delta", "relatedTo": ["git"] } ],
  "summary": {
    "total": 1396, "returned": 50, "truncated": true,
    "counts": { "kit": 0, "missing-related": 10, "shadowing": 0,
                "not-on-path": 181, "category-neighbor": 7, "thin-docs": 1198 }
  }
}
```

| Flag | Effect |
| --- | --- |
| `-GapKind <kind>` | Only that kind. Naming `thin-docs` opts back into it. |
| `-GapLimit <n>` | Cap the rows returned; `0` means uncapped |
| `-TaskLimit <n>` | Cap matches per group in `for` / `resolve_task` |
| `-ProbeLimit <n>` | Cap how many undocumented binaries get a `--help` probe (default 25) |
| `-IncludeUndocumented` | Let `agent-export` list PATH commands that have no usages and no catalog entry |
| `-DataDirectory <path>` | Read and write state somewhere other than `%LOCALAPPDATA%\cmdpeek` |
| `-ExamplesPath <path>` | Load the catalog from somewhere other than `examples/` |

`agent-export` drops rows with no usages, no catalog entry, and no star, because a playbook line that says only "this binary exists" teaches an agent nothing. On a machine with a full `/usr/bin` that is the difference between 1271 sections and 55.

A full `-Json` inventory is cached for `InventoryCacheSeconds` (default 120, configurable in `state.json`) and served **before** the package-manager and PATH scan, so a warm call costs about half a second instead of rescanning. Only the unfiltered inventory is cached: a `-Search`, `-Category`, or `-Count` run would otherwise hand the next caller a partial machine.

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
↑↓ move  ←→ pane  ↵ open/copy  / search  f fav  F favs  C cat  h hide  H hidden  g gaps  u have  s system  ? help  q quit
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
| u | Use what you have — installed catalog tools by category / capability |
| s | System commands — OS builtins and system-category tools |
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
| `list_recent_commands` | Recency envelope from `-Json -Recent` (usages, related, install commands, PATH) |
| `search_commands` | Find a CLI by name, category, capability, or usage text |
| `get_command` | Full detail for **installed or catalog-only** names (origin, gotchas, collisions) |
| `resolve_task` | Task → **installed first** (OS-aware builtins), then missing catalog tools |
| `explain_command` | Command card: usages, origin, gotchas, PATH winner, substitutes |
| `compare_commands` | Side-by-side cards and which to prefer on this OS |
| `suggest_for_argv` | Map a hallucinated or off-OS argv to an installed equivalent |
| `search_available` | Catalog search with install commands |
| `list_installed_for` | Installed tools for a capability |
| `list_gaps` | Missing related, thin docs, not-on-path, shadowing (PATH winner), kit, category-neighbor |
| `list_rusty` | Installed CLIs absent from recent PSReadLine history |
| `list_package_managers` | choco / scoop / winget / pipx / npm / cargo / brew detection |
| `list_favorites` | User-starred commands |
| `list_hidden` | Commands hidden from `-n` |
| `set_hidden` | Hide/unhide a command from `-n` |
| `set_favorite` | Star/unstar a command |
| `install_package` | Dry-run install command (set `execute` only with consent; refuses builtins) |
| `export_agent_playbook` | Markdown playbook of installed tools (prefer these over new packages) |
| `diagnose` | Health check: versions, managers, catalog, caches (`timing` adds per-stage scan times) |
| `refresh_inventory` | Rescan after install/uninstall (bypasses cache) |

List-shaped tools are capped (25 rows for most, 20 for `list_recent_commands`) and accept `limit`. Each capped result reports `total`, `returned`, and `truncated`, so a truncated answer is never *silently* truncated. `list_gaps` also takes `summary: true` for counts only, and `kind` to ask for a kind the default answer omits. `cmdpeek://inventory` and `cmdpeek://system` page to 60 rows each; the unbounded snapshot is still reachable through the CLI.

Resources: `cmdpeek://inventory`, `cmdpeek://gaps`, `cmdpeek://doctor`, `cmdpeek://recent`, `cmdpeek://last-install`, `cmdpeek://agent-export`, `cmdpeek://system`.

Prompts: `after_install`, `prefer_installed`, `prefer_system_then_installed`.

Agents should call `resolve_task` before suggesting a new CLI, prefer OS builtins on this machine, call `refresh_inventory` + `list_recent_commands` after a package install, and must not run usages with `<placeholders>`.

### Uninstall detection

On startup cmdpeek compares the last scan to what is still installed. If a tracked command disappeared:

```
Command 'yt-dlp' was uninstalled. Reinstall it? [Y/n/chocolatey/scoop/winget]
```

`-NonInteractive` prints the same information without prompting.

### Health check

`cmdpeek doctor` answers "why is cmdpeek behaving like that" without needing to read the source: which package managers it found and which it did not, whether the catalog parsed and how many commands it holds, how old each cache is and what the inventory TTL is, whether the data directory is writable, whether the profile hint is installed, and whether the module and MCP server versions agree.

```
cmdpeek 0.2.0  (mcp 0.2.0, PowerShell 7.6.5, linux)

Data directory  C:\Users\you\AppData\Local\cmdpeek  [writable]
Inventory cache 120s TTL
  state          238 KB, 62s old
  inventory      908 KB, 2523s old
  help-text      45 KB, 2403s old
  pe-subsystem   absent

Package managers
  present  scoop, chocolatey, npm
  missing  winget, pipx, cargo, brew, apt, pacman

Catalog  125 commands, 59 builtin, 13 kits, 0 learned

Shell history
  4212 lines  C:\Users\you\AppData\Roaming\...\ConsoleHost_history.txt
Profile hint    installed  (C:\Users\you\Documents\PowerShell\Microsoft.PowerShell_profile.ps1)

No problems found.
```

`cmdpeek doctor -Timing` times each scan stage separately (catalog load, package managers, history, PATH scan, gap analysis), which is how you tell a slow manager apart from a slow PATH. Anything cmdpeek considers wrong shows up in a `problems` list, and the same report is available as JSON with `-Json`, over MCP as `diagnose`, and as the `cmdpeek://doctor` resource.

## How install dates are found

| Manager | Source |
| --- | --- |
| Scoop | `~\scoop\apps\<name>` timestamps + `manifest.json` `bin` |
| Chocolatey | `%ChocolateyInstall%\lib\<pkg>` + `%ChocolateyInstall%\bin` shims (including shims whose exe lives inside the package folder) |
| WinGet | `%LOCALAPPDATA%\Microsoft\WinGet\Packages` folder timestamps + `.exe` files that are console apps resolvable on PATH (GUI helpers are skipped) |
| pipx / npm / cargo / brew | Isolated tool roots (`pipx` venvs, npm prefix, `~/.cargo/bin`, Homebrew Cellar) |
| apt | `/var/lib/dpkg/status` (`install ok installed`) |
| pacman | `/var/lib/pacman/local/*/desc` (`%NAME%`, `%VERSION%`, `%BUILDDATE%`) |
| PATH | Catalog command names resolvable by `Get-Command` (builtins tagged `packageManager=builtin`) plus a capped System32/`/bin` scan of extra console binaries |

Commands without a CLI shim (runtimes, fonts, GUI-only apps) are skipped.

## Data and privacy

State lives in `%LOCALAPPDATA%\cmdpeek\state.json` (favorites, commands hidden from `-n`, preferred package manager, last scan). `state.json` does not include telemetry or example-use counters; those unused fields are ignored if an older file still has them. Rusty last-used dates are stored next to it in `rusty-last-used.json`. Stock PSReadLine history has no timestamps; `Add-CmdPeekProfileHint` registers a PSReadLine `AddToHistoryHandler` that writes last-used dates into that sidecar as you type. Optional ISO prefixes on history lines are still merged on `-Rusty` and empty-delta `-n`.

Optional AI examples: set `CMDPEEK_OPENAI_API_KEY` to call OpenAI chat completions when catalog, `--help`, tldr, and the local cache have no usages. Completions are written to `%LOCALAPPDATA%\cmdpeek\openai-examples.json`. Set `CMDPEEK_OPENAI_MOCK_PATH` (for example `examples/mocks/openai-examples.json`) to serve canned usages and skip the network. `CMDPEEK_OPENAI_MODEL` defaults to `gpt-4o-mini`. Tests inject `-HttpRunner` / `-OpenAiRunner` and never call the live API. tldr pages are used as an optional local fallback when a command has no catalog examples.

## Shell integration

`install.ps1 -AddProfileHint` appends package-manager wrappers to your PowerShell profile so `scoop install` / `choco install` / `winget install` (and pipx/npm -g/cargo/brew) print `cmdpeek -n 1` for the new command. You can also add the same snippet yourself:

```powershell
Add-CmdPeekProfileHint -ProfilePath $PROFILE
```

The wrappers call the real `scoop`/`choco`/`winget`/`pipx`/`npm`/`cargo`/`brew` executables, then `cmdpeek -NonInteractive -n 1` after an install (`npm` only for `npm install -g`). The same snippet registers `Add-CmdPeekHistoryTimestamp` so typed commands update `rusty-last-used.json`. Re-running the helper upgrades an older hint block in place and is a no-op when the current snippet is already present.

Optional user catalog overlay: `%LOCALAPPDATA%\cmdpeek\catalog.overlay.json` (see `examples/catalog.overlay.example.json`). Help-probe examples for unknown PATH binaries are saved to `catalog.learned.json` in the same directory. Curated OS builtins live in `examples/system-commands.json`.

## The catalog

`examples/usage-examples.json` (packages) and `examples/system-commands.json` (OS builtins) are merged at load time into one catalog of 125 commands and 13 kits. They are merged before anything reads them, so a `related` entry in one file may point at a command defined in the other.

Beyond `usages`, each entry carries the fields an agent needs to *choose* a tool rather than just run one:

| Field | Answers |
| --- | --- |
| `whenToUse` | What job this is the right answer for |
| `whenNotToUse` | When to reach for something else instead |
| `gotchas` | What bites you the first time, for example that `jq`'s single-quoted filters do not quote in `cmd.exe` |
| `os` / `origin` | Where it runs, and whether it is a builtin or a package |
| `substitutes` / `related` | What it replaces, and what pairs with it |
| `capabilities` / `tasks` | How `for` and `have` find it |

`cmdpeek catalog-lint` validates both files against `examples/usage-examples.schema.json`, checks that every `related`, `substitutes`, and kit member resolves in the merged catalog, and reports per-field coverage. It exits 1 on any error, so it can gate a build, and it runs on every push:

```
/workspace/examples/usage-examples.json  71 commands, 6 kits
  schema valid

  agent-facing field coverage
    whenToUse     100%  ####################  71/71
    whenNotToUse  100%  ####################  71/71
    gotchas        76%  ###############.....  54/71
    ...

Merged catalog: 125 commands, 13 kits
  every related, substitute, and kit member resolves

No catalog errors.
```

## Development

```powershell
Import-Module .\src\cmdpeek.psd1 -Force
Invoke-Pester -Path .\tests
.\src\cmdpeek.ps1 -NonInteractive -n 5
.\src\cmdpeek.ps1 -Json
.\src\cmdpeek.ps1 catalog-lint
.\scripts\Invoke-CmdPeekSmoke.ps1
Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
.\scripts\New-CmdPeekReleaseArchive.ps1 -OutputDirectory .\dist
.\scripts\New-CmdPeekReleaseArchive.ps1 -OutputDirectory .\dist -UpdateManifest
cd mcp; npm install; npm run build; npm test
```

Requires [Pester](https://pester.dev/) 5+ (`Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck`).

The Pester suite mocks the filesystem, so it proves the logic but not that cmdpeek works on a real machine. `scripts/Invoke-CmdPeekSmoke.ps1` covers that gap: it runs the CLI end to end against the machine it is on and asserts on exit codes, JSON validity, payload size, and wall-clock budgets. CI runs it on both `windows-latest` and `ubuntu-latest`, alongside the catalog lint and PSScriptAnalyzer.

Note that PowerShell 5.1 reads a BOM-less file as ANSI, so any script containing non-ASCII characters (the TUI's box and arrow glyphs, em dashes) needs a UTF-8 BOM or it renders as mojibake.

## License

MIT. See [LICENSE](LICENSE).
