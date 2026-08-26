# Contributing to cmdpeek

Thanks for helping. cmdpeek is a PowerShell 5.1-compatible Windows CLI. Keep that floor unless a change is isolated behind a version check.

## Setup

1. Clone the repo.
2. Install Pester 5 or newer:

   ```powershell
   Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -MinimumVersion 5.0.0
   ```

3. Run tests:

   ```powershell
   Import-Module Pester -MinimumVersion 5.0.0
   Invoke-Pester -Path .\tests
   ```

## How to change behavior

- Prefer a failing Pester test first (`tests/*.Tests.ps1`), then the smallest fix in `src/`.
- Do not require PowerShell 7-only syntax (`??`, `?:`, `Join-Path` with more than two arguments, `-AsHashtable` on `ConvertFrom-Json`).
- Package-manager queries must stay injectable (`-ChocolateyRoot`, `-ScoopRoot`, `-WinGetRoot`, `-CommandTester`) so tests never need a real choco/scoop/winget install.
- Interactive prompts must honor `-NonInteractive`.
- Default data paths must not assume `%LOCALAPPDATA%` is set (fall back to `$HOME/.local/share`).

## Layout

| Path | Role |
| --- | --- |
| `src/PackageManager.ps1` | Detect PMs; scan install roots |
| `src/ExtraSources.ps1` | pipx / npm / cargo / brew / PATH catalog merge / apt / pacman |
| `examples/mocks/` | Fixture data for rusty timestamps, apt/pacman, OpenAI cache, WinGet SHA256, profile v1 |
| `src/Catalog.ps1` | Overlay, aliases, capabilities, substitutes, install IDs |
| `src/TaskResolve.ps1` | Task → installed-first matching |
| `src/CommandHistory.ps1` | Flatten, sort, search, missing-command diff |
| `src/UsageExamples.ps1` | Catalog + help / tldr fallback |
| `src/Config.ps1` | `%LOCALAPPDATA%\cmdpeek` state, last-install, inventory cache |
| `src/InteractiveMode.ps1` | Menus, reinstall prompts, formatters |
| `src/Tui.ps1` | Arrow-key TUI |
| `src/Inventory.ps1` | JSON snapshot + gap analysis |
| `mcp/` | MCP server for AI tools |
| `AGENTS.md` | Agent playbook |
| `docs/TASKS.md` | Remaining follow-ons |

New popular tools belong in the JSON catalog, not hardcoded in PowerShell.

## Pull requests

- One concern per PR when you can.
- Include tests for new parsing rules.
- Run `Invoke-Pester -Path .\tests` and mention the result.
- Do not commit `%LOCALAPPDATA%\cmdpeek` state, API keys, or `.nupkg` binaries.

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
