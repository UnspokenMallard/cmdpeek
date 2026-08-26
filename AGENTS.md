# Agent playbook for cmdpeek

cmdpeek inventories CLIs installed via Scoop, Chocolatey, WinGet, pipx, npm, cargo, Homebrew, apt, pacman, and PATH, then attaches usage examples.

## When to use it

- After the user installs a package
- When the user asks how to do a task (search files, pretty-print JSON, download video)
- When you are about to recommend installing a new CLI

## MCP / CLI

Prefer MCP tools when the cmdpeek server is configured. Otherwise run the same ideas via `cmdpeek.ps1`.

1. After install: `refresh_inventory` then `list_recent_commands` (CLI: `cmdpeek -Json -Refresh`; `cmdpeek -Json -Recent`).
2. For a task: `resolve_task` **before** suggesting a new package (CLI: `cmdpeek for json`).
3. Prefer **installed** matches. Do not recommend `ripgrep` if `rg` is present, or `fx` if `jq` is present.
4. Explain a binary with `explain_command` / `get_command` (CLI: `cmdpeek explain fd` or `cmdpeek fd`). Catalog-only names are allowed.
5. Never execute usage lines that contain `<placeholders>` or `usageDetails.unsafe=true`.

## Resources

- `cmdpeek://recent` — just-installed envelope
- `cmdpeek://last-install` — last delta written after a peek
- `cmdpeek://inventory` / `cmdpeek://gaps`
