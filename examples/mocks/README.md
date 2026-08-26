# Mock fixtures for deferred cmdpeek features

These files stand in for data that is awkward to collect in CI. Parsers under `src/` also read the live defaults (`/var/lib/dpkg/status`, `/var/lib/pacman/local`, `%LOCALAPPDATA%\cmdpeek\rusty-last-used.json`) when those paths exist.

| File | Stands in for |
| --- | --- |
| `rusty-last-used.json` | Calendar timestamps PSReadLine does not store |
| `psreadline-history.txt` | A short ConsoleHost_history.txt with ISO prefixes |
| `dpkg-status` | `apt` / dpkg installed-package database |
| `pacman/local/*/desc` | `pacman -Q` local package metadata |
| `openai-examples.json` | Cached model completions (`CMDPEEK_OPENAI_MOCK_PATH`; live calls use `CMDPEEK_OPENAI_API_KEY`) |
| `winget-portable-payload.txt` + `winget-release.json` | A published GitHub release ZIP and its SHA256 |
| `profile-v1.ps1` | A 0.1 `BEGIN cmdpeek hint` block to upgrade in place |

Set `CMDPEEK_OPENAI_MOCK_PATH` to `openai-examples.json` to serve canned usages for commands with no catalog/help/tldr examples (this also skips the live OpenAI call). Pack a real WinGet zip with `scripts/New-CmdPeekReleaseArchive.ps1`.
