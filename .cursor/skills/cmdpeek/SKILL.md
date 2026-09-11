---
name: cmdpeek
description: Discover newly installed CLIs, resolve tasks against tools already on PATH, and explain how to use them. Use after package installs or when recommending a command-line tool.
---

# cmdpeek

## Fast path

1. After `scoop` / `choco` / `winget` / `pipx` / `npm` / `cargo` / `brew` install, call MCP `refresh_inventory` then `list_recent_commands`.
2. When the user has a job to do, call `resolve_task` first. Prefer installed hits and OS builtins. Only then mention missing catalog tools and their `installCommands`.
3. For a named binary, call `explain_command` or `get_command` (works if it is not installed yet).
4. For a durable per-machine list, call `export_agent_playbook` or read `cmdpeek://agent-export`. OS builtins: `cmdpeek://system`.
5. Map a guessed command line with `suggest_for_argv`. Compare two tools with `compare_commands`.
6. Do not run examples that contain `<placeholders>` or `unsafe: true`. Do not install `origin=builtin` tools.
7. If cmdpeek answers oddly, call `diagnose` (or read `cmdpeek://doctor`) before assuming the machine is at fault.

## Capped results

Lists are ranked and capped at 25 by default and report `total`, `returned`, and `truncated`. A short answer does not mean a short machine.

- `list_gaps` leaves out the `thin-docs` kind; pass `kind` to ask for it, `limit` to widen, or `summary: true` for per-kind counts only.
- `export_agent_playbook` skips PATH commands with nothing to say about them; its closing line counts what it skipped.

## Picking between two installed tools

Read `whenToUse`, `whenNotToUse`, `gotchas`, `os`, and `substitutes` on the catalog entry rather than guessing from the name. They are populated for every catalog command.

## CLI equivalents

```powershell
cmdpeek -n 5
cmdpeek for "pretty-print json"
cmdpeek have search
cmdpeek explain fd
cmdpeek compare robocopy Copy-Item
cmdpeek suggest "ps aux"
cmdpeek agent-export
cmdpeek why jq
cmdpeek gaps
cmdpeek gaps -GapKind thin-docs -GapLimit 0
cmdpeek search-available fzf
cmdpeek doctor
cmdpeek --version
```
