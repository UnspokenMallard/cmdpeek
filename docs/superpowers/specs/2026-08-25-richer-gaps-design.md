# Richer inventory gaps (shadowing, kits, category neighbors)

Date: 2026-08-25  
Status: draft for review

## Goal

`Get-CmdPeekGap` already tells an agent “this installed tool’s catalog sibling is missing,” “docs are thin,” or “it is not on PATH.” This spec adds three more kinds so MCP `list_gaps` can also flag **duplicate names across package managers**, **incomplete role kits**, and **same-category catalog tools** you do not have yet.

Existing kinds stay. Cheat sheet `gaps:` stays **missing-related only**.

## Non-goals

- PSReadLine / last-used recency (spec B)
- Changing cheat-sheet gap kinds
- AI-generated kit membership
- Linux/mac, pipx/npm/cargo
- Re-grouping or synthesizing gaps in MCP TypeScript (PowerShell remains the source of truth)
- Changing `missing-related` / `thin-docs` / `not-on-path` firing rules except where this spec says to skip a new kind because an older kind already covers that command

## Data: kits in the example catalog

File: `examples/usage-examples.json` (same path `Get-CmdPeekExampleCatalogPath` already resolves).

Add a root object next to `commands`:

```json
"kits": {
  "media": ["ffmpeg", "yt-dlp", "mpv"],
  "dev-tools": ["fd", "rg", "fzf"],
  "search": ["rg", "fd", "fzf"]
}
```

- 3–5 kits. Ids are lowercase strings (`media`, `dev-tools`, `search`).
- Each value is an array of command names that already exist (or will exist) as keys under `commands`.
- Overlap between kits is allowed (e.g. `fd` in `dev-tools` and `search`).

`Get-CmdPeekExampleCatalog` stays a **command map** (do not change its return type; callers and tests depend on hashtable-of-commands).

Add `Get-CmdPeekCatalogKits` in `src/UsageExamples.ps1`:

- Same `-Path` as the catalog loader.
- Missing file, invalid JSON, or missing `kits` → empty hashtable.
- Parse `kits` like `commands`: each property name is a kit id; value is a string array (skip non-strings).
- Wrap each kit’s member list with `@(...)` before indexing or enumerating. `ConvertFrom-Json` collapses a one-element JSON array to a scalar; without `@()` a single-member kit would be treated as a string of characters.
- Do not require `commands` to be present in order to load kits.

`Get-CmdPeekGap` does **not** read the catalog file. It takes optional `-Kits` (hashtable of kit id → string[]). Omitted, `$null`, or empty → no kit gaps. That keeps current `Get-CmdPeekGap` tests fixture-only.

`ConvertTo-CmdPeekSnapshot` takes the same optional `-Kits`. When omitted, it calls `Get-CmdPeekCatalogKits` (shipped JSON) and passes the result into `Get-CmdPeekGap`. Existing snapshot tests that must ignore shipped kits should pass `-Kits @{}`.

## Installed set

For all new kinds, a command name is **installed** if any history row has that `Command` (case-insensitive), **including Hidden**. Hidden does not remove a name from the installed set.

## New kinds

### `shadowing`

Fire when two or more history rows share the same `Command` (case-insensitive) and those rows use **two or more distinct** `PackageManager` values (case-insensitive).

- One gap per command name (not one per pair of rows).
- `command` = that name (casing from the first matching history row in input order).
- `packageManagers` = distinct manager names, lowercase, sorted A–Z.
- `relatedTo` = `@()` (do not put managers here).
- `category` = that row’s `Category` if set, else `'other'`.
- `reason` = short text that the name is installed from more than one manager.
- Hidden rows count. A hidden scoop `jq` plus a visible choco `jq` is still shadowing.

Do not emit `shadowing` for two rows with the same manager (duplicate scan artifacts).

### `kit`

For each kit, if **at least one** member is installed:

- For each member that is **not** installed, emit a `kit` gap unless that command already has a `missing-related` gap in this run.
- `command` = missing member name (catalog key casing if `Get-CmdPeekCatalogEntry` finds it, else the kit JSON spelling).
- `relatedTo` = one-element array: the **kit id** (not sibling command names).
- `category` = catalog entry category if present, else `'other'`.
- `reason` = short text that the kit is incomplete.

**At most one `kit` gap per command name.** If a missing name sits in two kits, keep the kit whose id sorts first A–Z and skip the other.

If every member of a kit is missing, emit nothing for that kit (no “you have none of these” spam).

### `category-neighbor`

Use catalog `category` strings on command entries (existing field).

For each category that has **at least one installed** catalog command:

- Candidates = catalog commands in that category whose name is **not** installed.
- Drop a candidate if this run already has `missing-related` or `kit` for that command name.
- Sort remaining candidates by command name A–Z (ordinal, case-insensitive).
- Keep at most **3** per category.

Each kept candidate:

- `kind` = `category-neighbor`
- `command` = catalog key
- `relatedTo` = up to 3 installed command names in that category, sorted A–Z (if more than three are installed, take the first three after that sort)
- `category` = that category string
- `reason` = short text that other tools in this category are installed

Categories with no installed members produce no neighbors.

## Dedup and order

1. Compute existing kinds first (`missing-related`, `thin-docs`, `not-on-path`) unchanged.
2. Append `shadowing`.
3. Append `kit` (skip names already in `missing-related`).
4. Append `category-neighbor` (skip names already in `missing-related` or `kit`).

Do not emit two gaps of the **same** new kind for the same command name.

Return order: previous kinds in their current relative order, then shadowing (command A–Z), then kit (command A–Z), then category-neighbor (command A–Z).

## Gap object

Same shape as today (`command`, `kind`, `reason`, `relatedTo`, `category`) plus:

| Kind | Extra / `relatedTo` |
| --- | --- |
| `shadowing` | `packageManagers` string[]; no related commands required |
| `kit` | `relatedTo` = `[kitId]` |
| `category-neighbor` | `relatedTo` = up to 3 installed names in that category |

JSON snapshot `gaps` and `cmdpeek -Gaps` stay automatic: they already serialize whatever `Get-CmdPeekGap` returns.

## Surfaces

- CLI `-Gaps` / `-Json` snapshot: no new flags.
- MCP `list_gaps` `kind` enum: `missing-related | thin-docs | not-on-path | shadowing | category-neighbor | kit | all`. Filter still exact kind match; `all` unfiltered.
- TUI `g`: already prints `Kind`; pad kind to **18** characters so `category-neighbor` is not truncated (`Get-CmdPeekPadded $g.Kind 18` in `src/Tui.ps1`).
- Cheat sheet `gaps:` line: still only `missing-related` for the peeked command.

After changing the MCP enum, run `npm run build` in `mcp/`.

## Tests

`tests/Inventory.Tests.ps1` (and catalog kit tests in `tests/UsageExamples.Tests.ps1` if that is where catalog loaders are covered):

1. Two managers, same command name → one `shadowing` gap with sorted lowercase `packageManagers`.
2. Same name, same manager twice → no `shadowing`.
3. Kit with one installed member and one missing → one `kit` gap; `relatedTo` is the kit id; skip if that missing name already has `missing-related`.
4. Missing name in two kits → only one `kit` gap (kit id that sorts first A–Z).
5. Category with installed `fd` and extra catalog tools → at most 3 `category-neighbor` gaps; none for names already covered by missing-related or kit.
6. Hidden duplicate-manager name still shadows.

Keep existing gap tests green.

## Docs

README: one sentence that `-Gaps` / MCP can include shadowing, incomplete kits, and category neighbors. Do not document kit JSON as a user-facing config file.

## Files

- `examples/usage-examples.json` — add `kits`
- `src/UsageExamples.ps1` — `Get-CmdPeekCatalogKits`
- `src/Inventory.ps1` — `Get-CmdPeekGap -Kits`; `ConvertTo-CmdPeekSnapshot -Kits`
- `src/Tui.ps1` — kind column width 18
- `mcp/src/index.ts` — enum; rebuild
- `tests/Inventory.Tests.ps1` — new cases
- `tests/UsageExamples.Tests.ps1` — `Get-CmdPeekCatalogKits` (missing file, missing `kits`, one-element array stays a one-item list)
- `README.md` — brief mention
