# Command cheat sheet (`cmdpeek fd`)

Date: 2026-08-24  
Status: spec approved; implementation plan at `docs/superpowers/plans/2026-08-24-command-cheatsheet.md`

## Goal

When a human types a command name, cmdpeek prints that tool’s usages immediately — no TUI, no recency list — so “how do I use this?” is one argv.

Follow-on specs (not this document): **B** rusty-tool reminders from PSReadLine; **C** extra MCP gap kinds.

## Non-goals

- PSReadLine / last-used recency (spec B)
- New gap kinds (`shadowing`, role kits, catalog-neighbor) (spec C)
- Changing MCP `get_command` in this slice
- Grouping helper bins (stays on `-n` only)
- `-Json` / `-Gaps` / `-i` / `-n` behavior changes
- Advancing `LastPeekAt` or `LastMcpAt`
- LLM-generated examples, Linux/mac, pipx/npm/cargo

## Trigger

Applies only on the existing **search path**: positional non-digit argument or `-Search`, and **not** `-n` / `-Count`, `-i`, `-Json`, `-Gaps`, `-Recent`.

After scan + catalog/favorite/hidden merge (same as today):

1. Let `$q` be the search query (trimmed).
2. Exact name hits = history rows whose `Command` equals `$q` case-insensitively.
3. **Exactly one** exact name hit → cheat sheet for that row. Stop.
4. **Two or more** exact name hits (dual scoop+choco `jq`) → today’s filtered list of those rows only (do not pick one).
5. **Zero** exact name hits → today’s `Search-CmdPeekCommand` substring list (name, package, manager, usage text).

Hidden rows are included: typing the name shows the sheet even if the command is hidden from `-n`.

No match at all: keep the current empty search / empty-inventory wording. Do not add a new error dialect.

## Output

Human text, one command:

- Title: `{command} ({manager})` plus `  not on PATH` when `OnPath` is present and false. No list index (`1.`).
- Header line is that title (not `Last N installed commands:`).
- Up to **5** usages (help-probe this row only, then `Format-CmdPeekQuickOutput -ExampleCount 5`).
- If catalog-related tools are missing, one `gaps: a, b` line from existing `missing-related` gaps for this command (do not invent gap kinds).
- No `Shims` / package grouping on this path.

Mark `OnPath` on the chosen row with the injectable `CommandTester` (`Test-CmdPeekOnPath`) so the PATH suffix works without building a full snapshot.

## CLI mapping

| Input | Result |
| --- | --- |
| `cmdpeek fd` | Unique exact `fd` → cheat sheet |
| `cmdpeek -Search fd` | Same trigger rules |
| `cmdpeek jq` with scoop+choco jq | List of both rows |
| `cmdpeek ff` matching several names | Substring list (no unique exact name) |
| `cmdpeek 5` | Unchanged recency quick view |
| `cmdpeek -n 3 -Search fd` | Unchanged recency + post-group search |

`LastPeekAt` is not updated.

## Tests

`tests/Invoke-CmdPeek.Tests.ps1` (scoop TestDrive fixtures):

1. Unique `fd` → output matches `fd (` and `scoop`, usages present, does **not** match `Last \d+ installed commands`, `LastPeekAt` unchanged.
2. Two managers named `jq` → both appear; not a single cheat-sheet title-only path.
3. Query that only hits usage text, not an exact command name → list path (more than the one-command title format).
4. Hidden unique name still prints the cheat sheet.

## Docs

README usage table: `cmdpeek fd` — if that name is unique, print the cheat sheet; otherwise search.

`src/cmdpeek.ps1` help banner: one line for the same.

## Files

- `src/cmdpeek.psm1` — branch on the search path
- `src/InteractiveMode.ps1` — `Format-CmdPeekQuickOutput -CheatSheet` omits the `1.` index; title is `{command} ({manager})` (and PATH suffix). `-Header` is unused in this mode (the title is the header).
- `tests/Invoke-CmdPeek.Tests.ps1`
- `README.md`, `src/cmdpeek.ps1` help

Do not add a second formatter.
