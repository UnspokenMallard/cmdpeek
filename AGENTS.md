# Agent playbook for cmdpeek

cmdpeek inventories CLIs installed via Scoop, Chocolatey, WinGet, pipx, npm, cargo, Homebrew, apt, pacman, and PATH, then attaches usage examples. OS builtins (tasklist, robocopy, ps, Get-Process, and similar) are first-class catalog entries.

## When to use it

- After the user installs a package
- When the user asks how to do a task (search files, list processes, copy a tree, pretty-print JSON)
- When you are about to recommend installing a new CLI
- When you need the Windows or POSIX command that is already on the machine

## MCP / CLI

Prefer MCP tools when the cmdpeek server is configured. Otherwise run the same ideas via `cmdpeek.ps1`.

1. After install: `refresh_inventory` then `list_recent_commands` (CLI: `cmdpeek -Json -Refresh`; `cmdpeek -Json -Recent`).
2. For a task: `resolve_task` **before** suggesting a new package (CLI: `cmdpeek for json`). Prefer **installed** matches, then **OS builtins**, then installs.
3. Do not recommend `ripgrep` if `rg` is present, or `fx` if `jq` is present. On Windows prefer `tasklist` / `findstr` / `robocopy` over `ps` / `grep` / `cp` when those builtins are present.
4. Explain a binary with `explain_command` / `get_command` (CLI: `cmdpeek explain fd` or `cmdpeek fd`). Catalog-only names are allowed. Read `gotchas` and `collisions` (PowerShell `curl`/`sc`/`find`/`where`).
5. Map a hallucinated argv with `suggest_for_argv` (CLI: `cmdpeek suggest "ps aux"`). Compare two tools with `compare_commands` (CLI: `cmdpeek compare robocopy Copy-Item`).
6. For a durable per-machine cheat sheet: `cmdpeek agent-export` (MCP: `export_agent_playbook` / `cmdpeek://agent-export`). System builtins: `cmdpeek://system`.
7. Never execute usage lines that contain `<placeholders>` or `usageDetails.unsafe=true`. Never scoop-install `origin=builtin` commands.
8. If cmdpeek itself misbehaves, ask it: `diagnose` (CLI: `cmdpeek doctor`, `cmdpeek doctor -Timing`). It reports versions, detected managers, catalog health, cache ages, and a `problems` list.

## Reading a capped answer

List-shaped results are ranked and capped, because an unbounded answer does not fit in a context window. Every capped result reports `total`, `returned`, and `truncated`, so check those before concluding something is absent.

- Gaps omit the `thin-docs` kind by default and cap at 25 rows. Ask for `kind: "thin-docs"`, or raise `limit`, when you actually want them.
- `summary: true` on `list_gaps` returns per-kind counts with no rows, which is the cheapest way to see the shape of a machine.
- `export_agent_playbook` lists only commands that have usages, a catalog entry, or a star. A machine with a full `/usr/bin` has ~1200 more binaries on PATH; the playbook's closing line says how many. Read `cmdpeek://inventory` or `cmdpeek -Json` if you need all of them.

## Choosing between two installed tools

Catalog entries carry more than usage lines. When two tools both match a task, read these instead of guessing:

- `whenToUse` / `whenNotToUse` — the intended job and the case where something else is better
- `gotchas` — platform traps, for example that `jq`'s single-quoted filters do not quote in `cmd.exe`
- `os` / `origin` — whether it runs here, and whether it is a builtin or an installed package
- `substitutes` — what it replaces, so you do not suggest installing something already covered

## Resources

- `cmdpeek://recent` — just-installed envelope
- `cmdpeek://last-install` — last delta written after a peek
- `cmdpeek://inventory` / `cmdpeek://gaps` (capped; `cmdpeek -Json` for everything)
- `cmdpeek://doctor` — health check: versions, managers, catalog, caches, problems
- `cmdpeek://system` — OS builtins and system-category tools on this machine
- `cmdpeek://agent-export` — markdown playbook of installed tools on this machine
