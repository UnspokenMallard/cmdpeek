# Rusty-Tool Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface installed CLIs missing from recent PSReadLine history (`never` / `stale`) on empty `-n` fallback, `cmdpeek -Rusty`, the JSON snapshot, and MCP `list_rusty`.

**Architecture:** `Get-CmdPeekRusty` in `src/CommandUse.ps1` parses history files independently (500-line recent window, injectable `-RecentLines` / `-HistoryPath` for tests). Classification is not a gap kind. Format via `Format-CmdPeekQuickOutput -Rusty`. Snapshot and MCP only consume the PowerShell list.

**Tech Stack:** PowerShell 5.1 module (`src/`), Pester 5+, MCP TypeScript (`mcp/`).

**Spec:** `docs/superpowers/specs/2026-08-25-rusty-tools-design.md`

## Global Constraints

- PowerShell 5.1 floor: no `??`, `?:`, `Join-Path` with more than two arguments, `-AsHashtable` on `ConvertFrom-Json`.
- Wrap pipeline results with `@(...)` before `[0]`.
- Stock PSReadLine history has **no timestamps**. Do not print “N days ago” or apply calendar 90-day windows.
- `$script:CmdPeekRecentHistoryLines = 500` — not user-facing config. Tests pass `-RecentLines`.
- Do not add rusty kinds to `Get-CmdPeekGap`, cheat-sheet `gaps:`, TUI `g`, or MCP `list_gaps` / `get_command`.
- Do not help-probe the whole inventory solely for rusty.
- Pester must not read real `%APPDATA%` history: always pass `-HistoryPath` (TestDrive or `@()`).
- Commits: skip `git commit` unless the user explicitly asked. `docs/` is globally gitignored — `git add -f` if committing specs/plans.
- TDD: failing test first; watch it fail; then minimal code.

## File map

| File | Responsibility |
| --- | --- |
| `src/CommandUse.ps1` | `Get-CmdPeekPsReadLineHistoryPath`, `Get-CmdPeekRusty` |
| `src/InteractiveMode.ps1` | `Format-CmdPeekQuickOutput -Rusty` |
| `src/cmdpeek.psm1` | Dot-source, `-Rusty` branch, empty-delta rusty block |
| `src/cmdpeek.psd1` | Export `Get-CmdPeekRusty` |
| `src/cmdpeek.ps1` | `-Rusty` param, splat, help |
| `src/Inventory.ps1` | Snapshot `rusty` + `-HistoryPath` |
| `mcp/src/index.ts` | `list_rusty` + Snapshot.rusty type |
| `tests/CommandUse.Tests.ps1` | Classifier |
| `tests/Format.Tests.ps1` | Rusty formatter |
| `tests/Invoke-CmdPeek.Tests.ps1` | `-Rusty` and empty-delta `-n` |
| `tests/Inventory.Tests.ps1` | Snapshot isolation |
| `README.md` | Usage row |

---

### Task 1: `Get-CmdPeekRusty`

**Files:**
- Create: `src/CommandUse.ps1`
- Modify: `src/cmdpeek.psm1` (dot-source after `CommandHistory.ps1`; `Export-ModuleMember`)
- Modify: `src/cmdpeek.psd1` (`FunctionsToExport`)
- Test: `tests/CommandUse.Tests.ps1`

**Interfaces:**
- Consumes: inventory rows with `Command`, `PackageManager`, `Usages`, optional `Hidden`
- Produces:
  - `Get-CmdPeekPsReadLineHistoryPath` → `[string[]]` existing default files (5.1 then pwsh paths under `$env:APPDATA`)
  - `Get-CmdPeekRusty -History <object[]> [-HistoryPath <string[]>] [-RecentLines <int>]` → `[object[]]` of `{ command, kind ('never'|'stale'), lastLine, packageManager, usages }`
  - Omitted `-HistoryPath` → `Get-CmdPeekPsReadLineHistoryPath`. Bound empty `@()` → no files (empty result, no throw). Missing/unreadable files skipped.
  - `-RecentLines` default `0` means use `$script:CmdPeekRecentHistoryLines` (500)
  - One row per command name (first inventory row wins). Order: `never` A–Z then `stale` A–Z (`ToLowerInvariant()` key)
  - Recent: first token appears in the last N **non-blank** lines of **at least one** file

- [ ] **Step 1: Write the failing tests**

Create `tests/CommandUse.Tests.ps1`:

```powershell
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'CommandUse.ps1')
}

Describe 'Get-CmdPeekRusty' {
    BeforeAll {
        $script:inv = @(
            [pscustomobject]@{ Command = 'fd'; PackageManager = 'scoop'; Usages = @('fd x # find'); Hidden = $false }
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop'; Usages = @('jq . # json'); Hidden = $false }
            [pscustomobject]@{ Command = 'nevercli'; PackageManager = 'scoop'; Usages = @('nevercli --help'); Hidden = $false }
            [pscustomobject]@{ Command = 'rg'; PackageManager = 'scoop'; Usages = @('rg x'); Hidden = $false }
        )
    }

    It 'marks never and stale; recent names are omitted' {
        $path = Join-Path $TestDrive 'hist.txt'
        @(
            'jq .'
            'unrelated'
            'fd pattern'
        ) | Set-Content -LiteralPath $path -Encoding UTF8
        $rusty = @(Get-CmdPeekRusty -History $script:inv -HistoryPath @($path) -RecentLines 2)
        $rusty.Command | Should -Contain 'nevercli'
        $rusty.Command | Should -Contain 'jq'
        $rusty.Command | Should -Not -Contain 'fd'
        $never = @($rusty | Where-Object { $_.Command -eq 'nevercli' })[0]
        $never.kind | Should -Be 'never'
        $never.LastLine | Should -Be ''
        $stale = @($rusty | Where-Object { $_.Command -eq 'jq' })[0]
        $stale.kind | Should -Be 'stale'
        $stale.LastLine | Should -Be 'jq .'
        @($rusty)[0].Command | Should -Be 'nevercli'
        @($rusty)[1].Command | Should -Be 'jq'
    }

    It 'returns empty when history files are missing' {
        $rusty = @(Get-CmdPeekRusty -History $script:inv -HistoryPath @((Join-Path $TestDrive 'no-such-hist.txt')) -RecentLines 5)
        $rusty.Count | Should -Be 0
    }

    It 'keeps a name off rusty if it is recent in either file' {
        $win = Join-Path $TestDrive 'win.txt'
        $pwsh = Join-Path $TestDrive 'pwsh.txt'
        @(
            'old'
            'rg -i foo'
        ) | Set-Content -LiteralPath $win -Encoding UTF8
        'other' | Set-Content -LiteralPath $pwsh -Encoding UTF8
        $rusty = @(Get-CmdPeekRusty -History $script:inv -HistoryPath @($win, $pwsh) -RecentLines 2)
        $rusty.Command | Should -Not -Contain 'rg'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Invoke-Pester -Path .\tests\CommandUse.Tests.ps1 -Output Detailed
```

Expected: FAIL — `Get-CmdPeekRusty` is not recognized.

- [ ] **Step 3: Implement**

Create `src/CommandUse.ps1`:

```powershell
#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:CmdPeekRecentHistoryLines = 500

function Get-CmdPeekPsReadLineHistoryPath {
    [CmdletBinding()]
    param()

    $paths = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt')
        (Join-Path $env:APPDATA 'Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt')
    )
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($p in $paths) {
        if ($p -and (Test-Path -LiteralPath $p)) { $found.Add($p) }
    }
    return @($found)
}

function Get-CmdPeekRusty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [string[]]$HistoryPath,
        [int]$RecentLines = 0
    )

    if ($RecentLines -le 0) { $RecentLines = $script:CmdPeekRecentHistoryLines }

    $files = $HistoryPath
    if (-not $PSBoundParameters.ContainsKey('HistoryPath')) {
        $files = @(Get-CmdPeekPsReadLineHistoryPath)
    }
    if (-not $files) { $files = @() }

    $byName = @{}
    foreach ($row in @($History)) {
        if (-not $row -or -not $row.Command) { continue }
        $key = $row.Command.ToLowerInvariant()
        if (-not $byName.ContainsKey($key)) { $byName[$key] = $row }
    }

    $lastLine = @{}
    $recentAny = @{}
    $seen = @{}

    foreach ($path in @($files)) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        $lines = New-Object System.Collections.Generic.List[string]
        try {
            foreach ($raw in @(Get-Content -LiteralPath $path -ErrorAction Stop)) {
                if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                $lines.Add([string]$raw)
            }
        }
        catch {
            continue
        }
        $arr = @($lines)
        $n = $arr.Count
        $recentStart = $n - $RecentLines
        if ($recentStart -lt 0) { $recentStart = 0 }
        $i = 0
        foreach ($line in $arr) {
            $tok = @($line.Trim() -split '\s+')
            if ($tok.Count -eq 0) { $i++; continue }
            $cmd = [string]$tok[0]
            $key = $cmd.ToLowerInvariant()
            if (-not $byName.ContainsKey($key)) { $i++; continue }
            $seen[$key] = $true
            $lastLine[$key] = $line
            if ($i -ge $recentStart) { $recentAny[$key] = $true }
            $i++
        }
    }

    $never = New-Object System.Collections.Generic.List[object]
    $stale = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($byName.Keys)) {
        $row = $byName[$key]
        $usages = @()
        if ($row.PSObject.Properties['Usages'] -and $row.Usages) { $usages = @($row.Usages | Select-Object -First 3) }
        if (-not $seen.ContainsKey($key)) {
            $never.Add([pscustomobject]@{
                Command        = [string]$row.Command
                kind           = 'never'
                LastLine       = ''
                PackageManager = [string]$row.PackageManager
                Usages         = $usages
            })
            continue
        }
        if ($recentAny.ContainsKey($key)) { continue }
        $stale.Add([pscustomobject]@{
            Command        = [string]$row.Command
            kind           = 'stale'
            LastLine       = [string]$lastLine[$key]
            PackageManager = [string]$row.PackageManager
            Usages         = $usages
        })
    }

    $neverArr = @($never)
    if ($neverArr.Count -gt 1) { $neverArr = @($neverArr | Sort-Object { $_.Command.ToLowerInvariant() }) }
    $staleArr = @($stale)
    if ($staleArr.Count -gt 1) { $staleArr = @($staleArr | Sort-Object { $_.Command.ToLowerInvariant() }) }
    return @($neverArr + $staleArr)
}
```

Property names: `Command`, `kind`, `LastLine`, `PackageManager`, `Usages` (PS JSON snapshot in Task 4 projects lowercase).

Dot-source in `src/cmdpeek.psm1` after CommandHistory:

```powershell
. (Join-Path $PSScriptRoot 'CommandUse.ps1')
```

Add `'Get-CmdPeekRusty'` to `Export-ModuleMember` and `src/cmdpeek.psd1` `FunctionsToExport`.

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path .\tests\CommandUse.Tests.ps1 -Output Detailed
```

Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

```powershell
git add src/CommandUse.ps1 src/cmdpeek.psm1 src/cmdpeek.psd1 tests/CommandUse.Tests.ps1
git commit -m "Classify rusty commands from PSReadLine history."
```

---

### Task 2: `-Rusty` formatter

**Files:**
- Modify: `src/InteractiveMode.ps1` (`Format-CmdPeekQuickOutput`)
- Test: `tests/Format.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 rows (`Command`, `kind`, `LastLine`, `PackageManager`, `Usages`)
- Produces: `[switch]$Rusty` on `Format-CmdPeekQuickOutput` — default header `Rusty tools (not in recent history):`; title `{command} ({manager})` (no index); `   last: {LastLine}` when non-empty; usages; no `also:` / `suggestions:` / `gaps:`. Empty `-History` with `-Rusty` → `No rusty tools.`

- [ ] **Step 1: Write the failing test**

In `tests/Format.Tests.ps1` `Describe 'Format-CmdPeekQuickOutput'`:

```powershell
    It 'prints rusty titles without indexes and includes last history line' {
        $rows = @(
            [pscustomobject]@{
                Command        = 'jq'
                PackageManager = 'scoop'
                kind           = 'stale'
                LastLine       = 'jq .'
                Usages         = @('jq . # json')
            }
        )
        $text = Format-CmdPeekQuickOutput -History $rows -ExampleCount 3 -Rusty
        $text | Should -Match 'Rusty tools \(not in recent history\):'
        $text | Should -Match '^jq \(scoop\)'
        $text | Should -Not -Match '^\d+\. jq'
        $text | Should -Match 'last: jq \.'
        $text | Should -Match 'json'
        $text | Should -Not -Match 'suggestions:'
        $text | Should -Not -Match 'gaps:'
    }
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Invoke-Pester -Path .\tests\Format.Tests.ps1 -FullNameFilter '*rusty*' -Output Detailed
```

Expected: FAIL — parameter `-Rusty` not found.

- [ ] **Step 3: Implement `-Rusty`**

Add `[switch]$Rusty` to `Format-CmdPeekQuickOutput`. Treat `$Rusty` like `$CheatSheet` for: no numeric index; skip `also:` / `suggestions:` / `gaps:`. Differences from cheat sheet:

- If `-not $CheatSheet` header logic: when `$Rusty`, always use header `Rusty tools (not in recent history):` unless `-Header` is passed (then use Header).
- After the title line, if LastLine present:

```powershell
        $last = ''
        if ($row.PSObject.Properties['LastLine'] -and $row.LastLine) { $last = [string]$row.LastLine }
        elseif ($row.PSObject.Properties['lastLine'] -and $row.lastLine) { $last = [string]$row.lastLine }
        if ($Rusty -and $last) { $lines.Add(('   last: {0}' -f $last)) }
```

Empty `$History` with `-Rusty`: return `No rusty tools.` + newline (do not use the “No installed commands found” message).

- [ ] **Step 4: Run tests**

```powershell
Invoke-Pester -Path .\tests\Format.Tests.ps1 -Output Detailed
```

Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

```powershell
git add src/InteractiveMode.ps1 tests/Format.Tests.ps1 src/CommandUse.ps1 tests/CommandUse.Tests.ps1
git commit -m "Format rusty-tool reminder rows for the quick view."
```

---

### Task 3: CLI `-Rusty` and empty-delta `-n`

**Files:**
- Modify: `src/cmdpeek.psm1` (`Invoke-CmdPeek` params + branches)
- Modify: `src/cmdpeek.ps1` (param, splat, help)
- Test: `tests/Invoke-CmdPeek.Tests.ps1`

**Interfaces:**
- Consumes: `Get-CmdPeekRusty`, `Format-CmdPeekQuickOutput -Rusty`
- Produces: `[switch]$Rusty`, `[string[]]$HistoryPath`, `[int]$RecentLines` on `Invoke-CmdPeek` (last two for tests only; not exposed on `cmdpeek.ps1` except we do **not** add CLI flags for them)
- `$Json` / `$Gaps` / `$useInteractive` / `$Search` win over `$Rusty`
- `$Rusty` turns off `$isRecencyPath` (no `LastPeekAt` update)
- `-n 5 -Rusty` → rusty full list only
- Empty just-installed delta: rusty (exclude `Hidden`) first 3, then existing newest-N format
- No history files (bound `-HistoryPath` all missing, or omitted defaults empty): `No PSReadLine history found.`
- Files exist, nothing rusty: `No rusty tools.`

- [ ] **Step 1: Write the failing tests**

Add to `tests/Invoke-CmdPeek.Tests.ps1` (same scoop fixture pattern as existing fallback test). Pass `-HistoryPath` always.

```powershell
    It 'prepends rusty tools when just-installed delta is empty' {
        $scoopRoot = Join-Path $TestDrive 'scoop-rusty-n'
        $fdApp = Join-Path $scoopRoot 'apps\fd\current'
        $jqApp = Join-Path $scoopRoot 'apps\jq\current'
        New-Item -ItemType Directory -Force -Path $fdApp, $jqApp | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $fdApp 'manifest.json') -Encoding UTF8
        '{"version":"1.7.1","bin":"jq.exe"}' | Set-Content -Path (Join-Path $jqApp 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\fd')).LastWriteTime = [datetime]'2025-08-22T00:00:00'
        (Get-Item (Join-Path $scoopRoot 'apps\jq')).LastWriteTime = [datetime]'2025-08-19T00:00:00'

        $hist = Join-Path $TestDrive 'hist-rusty-n.txt'
        @(
            'jq .'
            'unrelated'
            'fd pattern'
        ) | Set-Content -LiteralPath $hist -Encoding UTF8

        $data = Join-Path $TestDrive 'rusty-n-data'
        $state = Get-CmdPeekState -DataDirectory $data
        $state.LastPeekAt = ([datetime]'2025-08-23T00:00:00').ToString('o')
        Save-CmdPeekState -State $state -DataDirectory $data
        $before = $state.LastPeekAt

        $output = Invoke-CmdPeek -Count 5 -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-rn') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-rn') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json') `
            -HistoryPath @($hist) `
            -RecentLines 2

        $text = $output | Out-String
        $text | Should -Match 'Rusty tools \(not in recent history\):'
        $text | Should -Match 'jq \(scoop\)'
        $text | Should -Match 'last: jq \.'
        $text | Should -Match 'No new installs since'
        $after = Get-CmdPeekState -DataDirectory $data
        $after.LastPeekAt | Should -Not -Be $before
    }

    It 'lists hidden never-used commands on -Rusty but not on -n rusty block' {
        $scoopRoot = Join-Path $TestDrive 'scoop-rusty-hide'
        $fdApp = Join-Path $scoopRoot 'apps\fd\current'
        $hidApp = Join-Path $scoopRoot 'apps\hiddencli\current'
        New-Item -ItemType Directory -Force -Path $fdApp, $hidApp | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $fdApp 'manifest.json') -Encoding UTF8
        '{"version":"1.0.0","bin":"hiddencli.exe"}' | Set-Content -Path (Join-Path $hidApp 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\fd')).LastWriteTime = [datetime]'2025-08-22T00:00:00'
        (Get-Item (Join-Path $scoopRoot 'apps\hiddencli')).LastWriteTime = [datetime]'2025-08-19T00:00:00'

        $hist = Join-Path $TestDrive 'hist-hide.txt'
        @(
            'unrelated'
            'fd pattern'
        ) | Set-Content -LiteralPath $hist -Encoding UTF8

        $data = Join-Path $TestDrive 'rusty-hide-data'
        $st = Get-CmdPeekState -DataDirectory $data
        $st.LastPeekAt = ([datetime]'2025-08-23T00:00:00').ToString('o')
        $st.Hidden = @('hiddencli')
        Save-CmdPeekState -State $st -DataDirectory $data

        $nText = @(Invoke-CmdPeek -Count 5 -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-rh') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-rh') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json') `
            -HistoryPath @($hist) `
            -RecentLines 2) | Out-String
        $nText | Should -Not -Match 'hiddencli'

        $rText = @(Invoke-CmdPeek -Rusty -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-rh2') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-rh2') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json') `
            -HistoryPath @($hist) `
            -RecentLines 2) | Out-String
        $rText | Should -Match 'hiddencli'
        $rText | Should -Not -Match 'No new installs since'
        $after = Get-CmdPeekState -DataDirectory $data
        $after.LastPeekAt | Should -Be $st.LastPeekAt
    }
```

If scoop `bin` `hiddencli.exe` does not produce Command `hiddencli`, check how `Get-CmdPeekCommandHistory` names bins — use a catalogued name like `jq` and hide `jq` instead (jq is in usage-examples.json). Prefer **hide `jq`** if `hiddencli` is not scanned.

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Invoke-Pester -Path .\tests\Invoke-CmdPeek.Tests.ps1 -FullNameFilter '*rusty*' -Output Detailed
```

Expected: FAIL — `-Rusty` / `-HistoryPath` not bound.

- [ ] **Step 3: Implement wiring**

`Invoke-CmdPeek` param add:

```powershell
        [switch]$Rusty,
        [string[]]$HistoryPath,
        [int]$RecentLines = 0
```

After `$Json -or $Gaps` NonInteractive block, if `$Rusty` also `$NonInteractive = $true` unless Interactive was explicit… Spec: Interactive wins. So only `if ($Rusty -and -not $Interactive) { $NonInteractive = $true }`.

`$isRecencyPath`: add `-and -not $Rusty`.

`$useInteractive`: if `$Rusty` and `-not $Interactive`, not TUI.

After inventory is built (same place as `-Gaps` JSON), before TUI:

```powershell
    if ($Rusty -and -not $Json -and -not $Gaps -and -not $useInteractive -and -not $Search) {
        $hp = $HistoryPath
        $hpBound = $PSBoundParameters.ContainsKey('HistoryPath')
        if (-not $hpBound) {
            $existing = @(Get-CmdPeekPsReadLineHistoryPath)
            if ($existing.Count -eq 0) {
                Write-Output "No PSReadLine history found."
                return
            }
            $hp = $existing
        }
        else {
            $any = $false
            foreach ($p in @($hp)) {
                if ($p -and (Test-Path -LiteralPath $p)) { $any = $true; break }
            }
            if (-not $any) {
                Write-Output "No PSReadLine history found."
                return
            }
        }
        $rusty = @(Get-CmdPeekRusty -History $history -HistoryPath @($hp) -RecentLines $RecentLines)
        if ($rusty.Count -eq 0) {
            Write-Output (Format-CmdPeekQuickOutput -History @() -ExampleCount 3 -Rusty)
            return
        }
        Write-Output (Format-CmdPeekQuickOutput -History $rusty -ExampleCount 3 -Rusty)
        return
    }
```

Empty-delta branch (where header is `No new installs since`): **before** probe+format of `$slice`, compute visible rows (`Hidden` not true), `Get-CmdPeekRusty` with same HistoryPath/RecentLines rules (if no files, skip rusty block, do not print “No PSReadLine history found” on `-n`). Take `@($rusty | Select-Object -First 3)`. If any, `$rustyOut = Format-CmdPeekQuickOutput -History $top -ExampleCount 3 -Rusty`. Then existing format of newest-N. `Write-Output` both (rusty first).

Pass `-HistoryPath` into `Get-CmdPeekRusty` only when bound; when omitted on `-n`, use defaults (production). Tests always pass `-HistoryPath`.

`src/cmdpeek.ps1`: `[switch]$Rusty`; `if ($Rusty) { $invoke.Rusty = $true }`. Help line:

```
  cmdpeek -Rusty              Installed tools missing from recent PSReadLine history
```

- [ ] **Step 4: Run tests**

```powershell
Invoke-Pester -Path .\tests\Invoke-CmdPeek.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests -PassThru
```

Expected: 0 failed.

- [ ] **Step 5: Commit** (only if asked)

```powershell
git add src/cmdpeek.psm1 src/cmdpeek.ps1 tests/Invoke-CmdPeek.Tests.ps1
git commit -m "Show rusty tools on -Rusty and empty just-installed fallback."
```

---

### Task 4: Snapshot, MCP, README

**Files:**
- Modify: `src/Inventory.ps1` (`ConvertTo-CmdPeekSnapshot`)
- Modify: `mcp/src/index.ts`
- Modify: `README.md`
- Test: `tests/Inventory.Tests.ps1`

**Interfaces:**
- Consumes: `Get-CmdPeekRusty`
- Produces: snapshot.rusty = `[{ command, kind, lastLine, packageManager }]`. Omitted `-HistoryPath` loads defaults; tests pass `-HistoryPath @()`. MCP `list_rusty` filters `snap.rusty` by `kind` `never|stale|all`. No TS history I/O.

- [ ] **Step 1: Write the failing tests**

In `Describe 'ConvertTo-CmdPeekSnapshot'`, add `-HistoryPath @()` to **every existing** `ConvertTo-CmdPeekSnapshot` call. Then:

```powershell
    It 'includes rusty rows from injected history and omits usages' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq . # json'); Related = @()
            }
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @()
            }
        )
        $hist = Join-Path $TestDrive 'snap-hist.txt'
        @(
            'jq .'
            'x'
            'fd y'
        ) | Set-Content -LiteralPath $hist -Encoding UTF8
        $snap = ConvertTo-CmdPeekSnapshot -History $history -Manager @() -Catalog @{} -Favorite @() -Hidden @() -CommandTester { $true } -Kits @{} -HistoryPath @($hist) -RecentLines 2
        $jq = @($snap.rusty | Where-Object { $_.command -eq 'jq' })[0]
        $jq.kind | Should -Be 'stale'
        $jq.lastLine | Should -Be 'jq .'
        $jq.PSObject.Properties.Name | Should -Not -Contain 'usages'
        @($snap.rusty | Where-Object { $_.command -eq 'fd' }).Count | Should -Be 0
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Invoke-Pester -Path .\tests\Inventory.Tests.ps1 -FullNameFilter '*rusty*' -Output Detailed
```

Expected: FAIL — `-HistoryPath` not found or `rusty` missing.

- [ ] **Step 3: Implement snapshot + MCP + README**

`ConvertTo-CmdPeekSnapshot` params: `[string[]]$HistoryPath`, `[int]$RecentLines = 0`.

After gaps:

```powershell
    $hpBound = $PSBoundParameters.ContainsKey('HistoryPath')
    $rustySrc = @()
    if ($hpBound) {
        $rustySrc = @(Get-CmdPeekRusty -History $history -HistoryPath $HistoryPath -RecentLines $RecentLines)
    }
    else {
        $rustySrc = @(Get-CmdPeekRusty -History $history -RecentLines $RecentLines)
    }
    $rusty = @(
        foreach ($r in $rustySrc) {
            if (-not $r) { continue }
            [pscustomobject]@{
                command        = [string]$r.Command
                kind           = [string]$r.kind
                lastLine       = [string]$r.LastLine
                packageManager = [string]$r.PackageManager
            }
        }
    )
```

Add `rusty = $rusty` to the returned pscustomobject.

MCP `Snapshot` type: `rusty?: Array<{ command: string; kind: string; lastLine?: string; packageManager?: string }>`

After `list_gaps` tool, add:

```typescript
server.tool(
  "list_rusty",
  "Installed CLIs that do not appear in recent PSReadLine history (never used, or not in the last 500 history lines). Use this to remind the user how to use idle tools. Not a packaging gap.",
  {
    kind: z.enum(["never", "stale", "all"]).optional().describe("Rusty kind to return (default all)"),
  },
  async ({ kind }) => {
    const snap = await loadSnapshot();
    let rusty = snap.rusty ?? [];
    if (kind && kind !== "all") {
      rusty = rusty.filter((r) => normalize(r.kind) === kind);
    }
    return asText({ rusty });
  },
);
```

README usage table after `-Gaps`:

```markdown
| `cmdpeek -Rusty` | Installed tools missing from recent PSReadLine history (never / not in last 500 lines) |
```

On the `-n` row, add that when there are no new installs, a short rusty block may appear above the newest-N fallback.

`src/cmdpeek.ps1` help already updated in Task 3; add README MCP table row for `list_rusty`.

- [ ] **Step 4: Run tests and MCP build**

```powershell
Invoke-Pester -Path .\tests\Inventory.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests -PassThru
Set-Location .\mcp; npm run build
```

Expected: Pester 0 failed; `tsc` 0.

- [ ] **Step 5: Commit** (only if asked)

```powershell
git add src/Inventory.ps1 tests/Inventory.Tests.ps1 mcp/src/index.ts README.md
git commit -m "Expose rusty tools on the inventory snapshot and MCP list_rusty."
```

---

## Self-review vs spec

| Spec requirement | Task |
| --- | --- |
| Parse 5.1 + pwsh files independently; 500-line window; recent in either file | 1 (`$recentAny`) |
| never / stale / omit; A–Z; one row per name | 1 |
| Missing files empty, no throw | 1 |
| `-RecentLines` / `-HistoryPath` for tests; no live APPDATA in Pester | 1, 3, 4 |
| Formatter title, last:, usages, no gap kinds | 2 |
| Empty-delta `-n`: rusty ≤3 excluding Hidden, then newest-N; LastPeekAt unchanged rules | 3 |
| Non-empty delta: no rusty | 3 (only in empty-delta branch) |
| `-Rusty` full list including Hidden; no LastPeekAt; Json/Gaps/i/Search win | 3 |
| No history: `No PSReadLine history found.`; empty rusty: `No rusty tools.` | 2 empty format + 3 |
| Snapshot rusty without usages | 4 |
| MCP `list_rusty` filter only | 4 |
| README | 4 |
| Not a gap kind | no Inventory gap changes |
