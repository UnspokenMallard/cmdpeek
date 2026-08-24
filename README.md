# cmdpeek

Show the **N most recently installed CLI commands** from Chocolatey, Scoop, and WinGet — plus the 1–3 usages you actually need.

```powershell
cmdpeek 3
```

```
Last 3 installed commands:

1. yt-dlp (scoop)
   -  yt-dlp <URL>                    # Download video
   -  yt-dlp -f bestaudio <URL>       # Extract audio only

2. fd (scoop)
   -  fd <pattern>                    # Find files
   -  fd -t f <pattern>               # Find files only

3. jq (choco)
   -  jq '.field' file.json           # Extract field
   -  jq 'map(.name)' file.json       # Transform array
```

## Why cmdpeek?

Package managers tell you *what* is installed. They do not remind you *how* to use the new binary, or that you uninstalled it last week. cmdpeek reads local install metadata (no scraping of PM logs in v0.1 — filesystem + manifests), caches it, and attaches community examples.

## Install

Windows 10/11, PowerShell 5.1 or PowerShell 7+.

### Standalone (works without a package manager)

From a clone:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

From GitHub once the repo is public:

```powershell
irm https://raw.githubusercontent.com/cmdpeek/cmdpeek/main/install.ps1 | iex
```

### Scoop

```powershell
scoop install .\scoop\cmdpeek.json
```

After the GitHub repo exists you can add a bucket and `scoop install cmdpeek`.

### Chocolatey

```powershell
choco pack .\chocolatey\cmdpeek.nuspec
choco install cmdpeek -s . -y
```

### WinGet

The file `winget/manifest.yaml` is a submission template for [winget-pkgs](https://github.com/microsoft/winget-pkgs). Until a release ZIP with a real SHA256 is published, use `install.ps1`.

### First run with no package manager

cmdpeek detects `choco`, `scoop`, and `winget`. If none are on PATH it prints bootstrap commands and (in interactive mode) offers to run one:

1. **Scoop** — user-level, recommended
2. **Chocolatey** — typically needs an elevated shell
3. **WinGet** — App Installer / Microsoft Store

## Usage

| Command | Mode |
| --- | --- |
| `cmdpeek` or `cmdpeek -i` | Interactive browser |
| `cmdpeek 5` or `cmdpeek -n 5` | Quick: last 5 commands, 1–3 examples each |
| `cmdpeek -Search rg` | Quick filter by name |
| `cmdpeek -Category media` | Filter by catalog category |
| `cmdpeek -Export backup.json` | Backup favorites + history |
| `cmdpeek -Import backup.json` | Restore |
| `cmdpeek -Reinstall fd -Manager scoop` | Reinstall a tracked package |
| `cmdpeek -NonInteractive -n 5` | No prompts (CI / scripts) |

### Interactive keys

```
cmdpeek - Recently Installed Commands

  yt-dlp (scoop)      2025-08-20
  fd (scoop)          2025-08-19
* jq (choco)          2025-08-18

  # Open   / Search   C Category   F Favorite   A All   E Export   Q Quit
```

Open a command for more examples, copy-to-clipboard, or run (examples with `<placeholders>` are copied, not executed).

### Uninstall detection

On startup cmdpeek compares the last scan to what is still installed. If a tracked command disappeared:

```
Command 'yt-dlp' was uninstalled. Reinstall it? [Y/n/chocolatey/scoop/winget]
```

`-NonInteractive` prints the same information without prompting.

## How install dates are found

| Manager | Source |
| --- | --- |
| Scoop | `~\scoop\apps\<name>` timestamps + `manifest.json` `bin` |
| Chocolatey | `%ChocolateyInstall%\lib\<pkg>` + `%ChocolateyInstall%\bin` shims |
| WinGet | `%LOCALAPPDATA%\Microsoft\WinGet\Packages` folder timestamps + `.exe` files |

Commands without a CLI shim (runtimes, fonts, GUI-only apps) are skipped.

## Data and privacy

State lives in `%LOCALAPPDATA%\cmdpeek\state.json` (favorites, last scan, optional local example-use counters). Telemetry is **off** unless you set `TelemetryEnabled` in that file; v0.1 does not send data anywhere.

Optional AI examples are not called unless you add an API key later (`CMDPEEK_OPENAI_API_KEY` is reserved; unused in 0.1.0).

## Shell integration

Add to your PowerShell profile if you want a reminder after installing packages:

```powershell
function Invoke-CmdPeekHint {
    if (Get-Command cmdpeek -ErrorAction SilentlyContinue) {
        cmdpeek -NonInteractive -n 3
    }
}
```

Call it after `scoop install`, or alias your package-manager wrappers.

## Development

```powershell
Import-Module .\src\cmdpeek.psd1 -Force
Invoke-Pester -Path .\tests
.\src\cmdpeek.ps1 -NonInteractive -n 5
```

Requires [Pester](https://pester.dev/) 5+ (`Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck`).

## License

MIT. See [LICENSE](LICENSE).
