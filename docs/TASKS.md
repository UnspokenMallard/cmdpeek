# cmdpeek follow-ons

Shipped in this branch: catalog capabilities/aliases/substitutes/install IDs, overlay, task resolver, extra scanners (PATH/pipx/npm/cargo/brew/apt/pacman), last-install sidecar, rusty last-used sidecar, inventory cache, winget/pipx/npm/cargo/brew profile hooks, MCP prompts/resources, Cursor skill, agent playbook, Linux Pester CI, OpenAI examples with an injectable HTTP runner, and a portable zip pack script.

- [x] Calendar timestamps for rusty tools — default sidecar `%LOCALAPPDATA%\cmdpeek\rusty-last-used.json` (ISO-prefixed history lines are merged on `-Rusty` and empty-delta `-n`; `-Json` inventory reads the same file)
- [x] apt/pacman inventory — live scan of `/var/lib/dpkg/status` and `/var/lib/pacman/local` when those managers are enabled; fixtures in `examples/mocks/`
- [x] OpenAI-backed examples — `CMDPEEK_OPENAI_API_KEY` calls chat completions; `CMDPEEK_OPENAI_MOCK_PATH` and `{data}/openai-examples.json` skip the network; tests inject `-HttpRunner`
- [x] WinGet pack script — `scripts/New-CmdPeekReleaseArchive.ps1` writes the portable zip + SHA256 sidecar; `.github/workflows/release.yml` uploads it on `v*` tags
- [x] Profile snippet upgrade — `Add-CmdPeekProfileHint` replaces a 0.1 block in place

Still not live:

- [ ] PSReadLine itself still does not record dates; the sidecar and optional ISO prefixes are the timestamp source
- [ ] A published GitHub release ZIP (tag `v*` to run the release workflow, then copy `dist/cmdpeek-win-x64.sha256.json` into `winget/manifest.yaml`)
