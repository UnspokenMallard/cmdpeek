# cmdpeek follow-ons

Shipped in this branch: catalog capabilities/aliases/substitutes/install IDs, overlay, task resolver, extra scanners (PATH/pipx/npm/cargo/brew/apt/pacman), last-install sidecar, rusty last-used sidecar, inventory cache, winget/pipx/npm/cargo/brew profile hooks, MCP prompts/resources, Cursor skill, agent playbook, Linux Pester CI, OpenAI examples with an injectable HTTP runner, portable zip pack script, Scoop/WinGet/Chocolatey manifest updates from that zip, PSReadLine last-used timestamps via the profile hint, and `cmdpeek agent-export`.

- [x] Calendar timestamps for rusty tools — default sidecar plus profile `AddToHistoryHandler` (`Add-CmdPeekHistoryTimestamp`)
- [x] apt/pacman inventory — live scan when those managers are enabled
- [x] OpenAI-backed examples — `CMDPEEK_OPENAI_API_KEY` with injectable HTTP in tests
- [x] WinGet/Scoop pack script — `scripts/New-CmdPeekReleaseArchive.ps1 -UpdateManifest` writes zip SHA256 into `winget/manifest.yaml` and `scoop/cmdpeek.json`; Chocolatey nuspec version is bumped; `.github/workflows/release.yml` uploads those files on `v*` tags
- [x] Profile snippet upgrade — `Add-CmdPeekProfileHint` replaces older blocks in place (including timestamp registration)
- [x] `cmdpeek agent-export` — markdown playbook of installed tools; MCP `export_agent_playbook` / `cmdpeek://agent-export`

Still not live:

- [ ] A published GitHub release ZIP (tag `v*` on the default branch to run the release workflow, then commit the updated scoop/winget hashes if you want them in-tree)
