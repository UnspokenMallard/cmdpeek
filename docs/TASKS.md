# cmdpeek follow-ons

Shipped in this branch: catalog capabilities/aliases/substitutes/install IDs, overlay, task resolver, extra scanners (PATH/pipx/npm/cargo/brew), last-install sidecar, inventory cache, winget/pipx/npm/cargo/brew profile hooks, MCP prompts/resources, Cursor skill, agent playbook, Linux Pester CI.

Mock fixtures in `examples/mocks/` cover the five follow-ons that still need a real machine, API, or GitHub release:

- [x] Calendar timestamps for rusty tools — `rusty-last-used.json` + ISO-prefixed `psreadline-history.txt`
- [x] apt/pacman inventory — `dpkg-status` and `pacman/local/*/desc` (parsers: `Get-CmdPeekAptPackage`, `Get-CmdPeekPacmanPackage`)
- [x] OpenAI-backed examples — `openai-examples.json` via `CMDPEEK_OPENAI_MOCK_PATH` (no network call)
- [x] WinGet release SHA256 — `winget-release.json` hashes `winget-portable-payload.txt`; `winget/manifest.yaml` uses the same mock hash
- [x] Profile snippet upgrade — `profile-v1.ps1`; `Add-CmdPeekProfileHint` replaces a 0.1 block in place

Still not live:

- [ ] PSReadLine does not record dates; overlay timestamps are opt-in
- [ ] Live `apt`/`pacman` scan uses `/var/lib/dpkg/status` and `/var/lib/pacman/local` when those managers are enabled
- [ ] `CMDPEEK_OPENAI_API_KEY` still does not call OpenAI
- [ ] Publish a real GitHub release ZIP and replace the mock SHA256
