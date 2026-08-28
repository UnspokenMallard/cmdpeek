# cmdpeek follow-ons

Shipped in this branch: catalog capabilities/aliases/substitutes/install IDs, overlay, task resolver, extra scanners (PATH/pipx/npm/cargo/brew/apt/pacman), last-install sidecar, rusty last-used sidecar, inventory cache, winget/pipx/npm/cargo/brew profile hooks, MCP prompts/resources, Cursor skill, agent playbook, Linux Pester CI, OpenAI examples with an injectable HTTP runner, portable zip pack script, Scoop/WinGet/Chocolatey manifest updates from that zip, PSReadLine last-used timestamps via the profile hint, and `cmdpeek agent-export`.

- [x] Calendar timestamps for rusty tools — default sidecar plus profile `AddToHistoryHandler` (`Add-CmdPeekHistoryTimestamp`)
- [x] apt/pacman inventory — live scan when those managers are enabled
- [x] OpenAI-backed examples — `CMDPEEK_OPENAI_API_KEY` with injectable HTTP in tests
- [x] WinGet/Scoop pack script — `New-CmdPeekReleaseArchive.ps1 -UpdateManifest` writes zip SHA256 into Scoop/WinGet/Chocolatey; release workflow runs on `v*` or numeric tags and `workflow_dispatch` `attach_tag`
- [x] Profile snippet upgrade — `Add-CmdPeekProfileHint` replaces older blocks in place (including timestamp registration)
- [x] `cmdpeek agent-export` — markdown playbook of installed tools; MCP `export_agent_playbook` / `cmdpeek://agent-export`
- [x] System command hub — catalog origin/os/shell/gotchas, curated Windows/POSIX/cmdlet entries, PATH/System32 enumerator, synonym ranking, command cards, learned overlay, TUI system view, `compare` / `suggest`

Still not live:

- [ ] Attach the portable zip to GitHub release `0.2.0` (the tag is `0.2.0`, so the original `v*` workflow did not run). After this fix is on the default branch: Actions → release → Run workflow → `attach_tag` = `0.2.0`. Then commit the scoop/winget hashes from that zip.
