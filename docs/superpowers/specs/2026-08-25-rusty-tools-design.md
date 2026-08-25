# Rusty-tool reminders (PSReadLine)

Date: 2026-08-25  
Status: draft for review

## Goal

Remind the user how to use **installed** CLIs they have not typed recently. Install date cannot do that. Stock PSReadLine history (`ConsoleHost_history.txt`) can, with one honest limit: **the file has no timestamps**, so “stale” is **not in the last 500 lines**, not “90 calendar days.”

Follow-on (not this document): GitHub release hashes; profile-hook calendar dates.

## Non-goals

- Calendar 90-day windows or “N days ago” copy
- Profile / prompt hooks that record timestamps
- New `Get-CmdPeekGap` kinds (rusty is not a gap)
- Changing cheat sheet `gaps:`, TUI `g`, or MCP `list_gaps` / `get_command`
- AI-generated examples, Linux/mac, pipx/npm/cargo
- User-facing config for the 500-line window

## Architecture

New module file `src/CommandUse.ps1`, dotted from `src/cmdpeek.psm1`.

`Get-CmdPeekRusty`:

- **Inputs:** inventory rows (`-History`), optional `-HistoryPath` (string[] of files; tests). If `-HistoryPath` omitted, use files that exist:
  1. `(Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt')`
  2. `(Join-Path $env:APPDATA 'Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt')`
- **Parse each file independently:** skip blank lines; first whitespace-separated token is the command; match inventory `Command` case-insensitively. Keep the last matching **full line** and 0-based line index per file.
- **Recent window:** `$script:CmdPeekRecentHistoryLines = 500` in `CommandUse.ps1`. A name is **recent** if it appears in the last 500 lines of **at least one** history file (dual-host: using it in either Windows PowerShell or pwsh keeps it off the rusty list). Do **not** concatenate files into one index (that would mark 5.1-only daily tools stale).
- **Classify** (inventory names only):
  - `never` — not present in any parsed file
  - `stale` — present in some file, but not recent
  - else — omit (actively used)
- **Order:** all `never` (command A–Z), then `stale` (command A–Z). (`ToLowerInvariant()` sort key.) Calendar/oldest-first ranking is not possible without timestamps.
- **One row per command name.** Dual scoop+choco: use the first inventory row’s `Command` casing, `PackageManager`, and usages source.
- **Row shape:**

```
command, kind ('never'|'stale'), lastLine ('' if never), packageManager, usages (string[], up to 3)
```

`lastLine` is the last matching history line from the file where that name’s last index was highest (pwsh file wins ties if both have a last line — process files in listed order so pwsh overwrites).

Usages: reuse existing catalog / already-probed `Usages` on that inventory row; **do not** help-probe the whole inventory solely for rusty. Quick-view `-n` already probes the displayed newest-N slice; rusty rows on that path may have only catalog usages (acceptable).

Missing, empty, or unreadable history files: skip them. If none readable → empty rusty list, no throw.

## Surfaces

### Empty just-installed `-n`

When `Select-CmdPeekJustInstalled` returns no new installs and the existing fallback to newest N runs:

1. Compute rusty **excluding Hidden** names.
2. Take at most **3** rows (never first, then stale, already sorted).
3. Print header `Rusty tools (not in recent history):` and those rows (title `{command} ({manager})`, `last: {lastLine}` when `lastLine` is non-empty, then up to 3 usages).
4. Then print the existing `No new installs since …` newest-N block **unchanged**.

If the just-installed delta is **non-empty**, do not print rusty.  
If rusty is empty, `-n` looks as today (fallback only).  
Do not advance `LastPeekAt` any differently than today (still after a displayed newest-N slice).

### `cmdpeek -Rusty`

New `[switch]$Rusty` on `cmdpeek.ps1` and `Invoke-CmdPeek`.

- Mutually exclusive with recency `-n`: if `-Rusty` is set, skip just-installed / newest-N / `LastPeekAt` update (same early-exit idea as `-Gaps`).
- `-Json` / `-Gaps` / `-i` / `-Search` win over `-Rusty` if combined (do not invent combo behavior); `-n 5 -Rusty` → `-Rusty` only.
- Print the **full** rusty list (no cap of 3), **including Hidden**.
- If no history files: one line `No PSReadLine history found.` and no rows.
- If files exist but no rusty names: print `No rusty tools.`

### Snapshot / MCP

`ConvertTo-CmdPeekSnapshot` adds `rusty` (array of `{ command, kind, lastLine, packageManager }`; usages optional on JSON to keep payload smaller — **include `lastLine` and `kind`**; omit bulky usages on snapshot, MCP can `get_command` for examples). Tests that must ignore live `%APPDATA%` pass `-HistoryPath @()` or a TestDrive file.

MCP `list_rusty`: enum `never | stale | all` (default `all`). Filter `snap.rusty` in TypeScript the same way `list_gaps` filters kinds. No history I/O in MCP. After enum change, `npm run build` in `mcp/`.

## Tests

`tests/CommandUse.Tests.ps1` (new) + a thin `Invoke-CmdPeek` case:

1. TestDrive history: last 500 lines contain `fd`; early line `jq .`; `nevercli` absent; inventory has `fd`, `jq`, `nevercli` → rusty is `nevercli` (never) then `jq` (stale); not `fd`.
2. Missing history path → empty list, no throw.
3. Dual files: `rg` only in 5.1 last-500 → not stale.
4. `Invoke-CmdPeek` NonInteractive with LastPeekAt newer than all installs → output matches `Rusty tools` and still matches `No new installs since`; `LastPeekAt` still advances as today.
5. `-Rusty` lists hidden never-used; `-n` rusty block does not.

Do not read real `%APPDATA%` in Pester.

## Docs

README + `cmdpeek.ps1` help: one row for `cmdpeek -Rusty` and a sentence that empty `-n` may show rusty tools above the newest-N fallback.

## Files

- `src/CommandUse.ps1` — parse + classify
- `src/cmdpeek.psm1` / `src/cmdpeek.psd1` — dot-source, export, `-Rusty` branch
- `src/cmdpeek.ps1` — param + help
- `src/Inventory.ps1` — snapshot `rusty` + optional `-HistoryPath`
- `src/InteractiveMode.ps1` — format rusty block **or** extend `Format-CmdPeekQuickOutput` with a small `-Rusty` mode (prefer one extra formatter switch rather than a second formatter)
- `mcp/src/index.ts` — `list_rusty`
- `tests/CommandUse.Tests.ps1`, `tests/Invoke-CmdPeek.Tests.ps1`
- `README.md`
