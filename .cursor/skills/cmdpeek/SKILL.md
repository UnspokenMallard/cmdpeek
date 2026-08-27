---
name: cmdpeek
description: Discover newly installed CLIs, resolve tasks against tools already on PATH, and explain how to use them. Use after package installs or when recommending a command-line tool.
---

# cmdpeek

## Fast path

1. After `scoop` / `choco` / `winget` / `pipx` / `npm` / `cargo` / `brew` install, call MCP `refresh_inventory` then `list_recent_commands`.
2. When the user has a job to do, call `resolve_task` first. Use installed hits. Only then mention missing catalog tools and their `installCommands`.
3. For a named binary, call `explain_command` or `get_command` (works if it is not installed yet).
4. For a durable per-machine list, call `export_agent_playbook` or read `cmdpeek://agent-export`.
5. Do not run examples that contain `<placeholders>` or `unsafe: true`.

## CLI equivalents

```powershell
cmdpeek -n 5
cmdpeek for "pretty-print json"
cmdpeek have search
cmdpeek explain fd
cmdpeek agent-export
cmdpeek why jq
cmdpeek gaps
cmdpeek search-available fzf
```
