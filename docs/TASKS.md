# cmdpeek follow-ons

Shipped in this branch: catalog capabilities/aliases/substitutes/install IDs, overlay, task resolver, extra scanners (PATH/pipx/npm/cargo/brew), last-install sidecar, inventory cache, winget/pipx/npm/cargo/brew profile hooks, MCP prompts/resources, Cursor skill, agent playbook, Linux Pester CI.

Still optional later:

- [ ] Calendar timestamps for rusty tools (PSReadLine history has no dates)
- [ ] apt/pacman full package-name inventory (PATH catalog merge covers binaries)
- [ ] OpenAI-backed examples behind `CMDPEEK_OPENAI_API_KEY` (reserved; tldr is the current optional fallback)
- [ ] Published GitHub release ZIP with SHA256 for WinGet
- [ ] Upgrade existing profile snippets to the 0.2 wrappers (re-run after deleting the old `BEGIN cmdpeek hint` block)
