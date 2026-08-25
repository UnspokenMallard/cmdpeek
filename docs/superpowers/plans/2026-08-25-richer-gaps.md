# Richer Inventory Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Get-CmdPeekGap` also emits `shadowing`, `kit`, and `category-neighbor` so `-Gaps`, the JSON snapshot, TUI `g`, and MCP `list_gaps` can flag duplicate managers, incomplete role kits, and same-category catalog tools.

**Architecture:** PowerShell remains the only gap synthesizer. Kits live in `examples/usage-examples.json` and load via `Get-CmdPeekCatalogKits`. `Get-CmdPeekGap` takes optional `-Kits` (omitted/`$null`/empty = no kit gaps). `ConvertTo-CmdPeekSnapshot` loads shipped kits when `-Kits` is omitted. Existing kinds are unchanged; new kinds append after them with the spec’s dedup order.

**Tech Stack:** PowerShell 5.1 module (`src/`), Pester 5+, MCP TypeScript (`mcp/`).

**Spec:** `docs/superpowers/specs/2026-08-25-richer-gaps-design.md`

## Global Constraints

- PowerShell 5.1 floor: no `??`, `?:`, `Join-Path` with more than two arguments, `-AsHashtable` on `ConvertFrom-Json`.
- Wrap pipeline results with `@(...)` before `[0]`. Wrap kit member lists with `@(...)` after `ConvertFrom-Json` (one-element JSON arrays collapse to a scalar).
- Do not regroup or invent gaps in MCP TypeScript.
- Do not change cheat-sheet `gaps:` (still `missing-related` only).
- Do not change `missing-related` / `thin-docs` / `not-on-path` firing rules.
- Commits: skip `git commit` unless the user explicitly asked for commits. Spec/plan files under `docs/` are globally gitignored — use `git add -f` if committing them.
- TDD: failing test first; watch it fail; then minimal code.

## File map

| File | Responsibility |
| --- | --- |
| `src/UsageExamples.ps1` | `Get-CmdPeekCatalogKits` |
| `examples/usage-examples.json` | Root `kits` plus a `mpv` command entry (kit member must exist as a catalog key) |
| `src/Inventory.ps1` | `Get-CmdPeekGap -Kits`; `ConvertTo-CmdPeekSnapshot -Kits` |
| `src/cmdpeek.psm1` | TUI path passes kits into `Get-CmdPeekGap`; export `Get-CmdPeekCatalogKits` |
| `src/cmdpeek.psd1` | Export `Get-CmdPeekCatalogKits` |
| `src/Tui.ps1` | Kind column pad 18 |
| `mcp/src/index.ts` | `list_gaps` enum + tool description |
| `tests/UsageExamples.Tests.ps1` | Kit loader |
| `tests/Inventory.Tests.ps1` | New gap kinds; snapshot `-Kits @{}` |
| `tests/Invoke-CmdPeek.Tests.ps1` | Shipped JSON has `kits` |
| `README.md`, `src/cmdpeek.ps1` | User-facing mention |

---

### Task 1: Catalog kits loader

**Files:**
- Modify: `src/UsageExamples.ps1` (after `Get-CmdPeekExampleCatalog`)
- Modify: `src/cmdpeek.psd1`, `src/cmdpeek.psm1` (`Export-ModuleMember` / `FunctionsToExport`)
- Modify: `examples/usage-examples.json`
- Test: `tests/UsageExamples.Tests.ps1`
- Test: `tests/Invoke-CmdPeek.Tests.ps1` (`Describe 'usage-examples.json'`)

**Interfaces:**
- Consumes: `Get-CmdPeekExampleCatalogPath -Path`
- Produces: `Get-CmdPeekCatalogKits [[string]$Path]` → `[hashtable]` kit id → `[string[]]`. Missing file, invalid JSON, or missing `kits` → `@{}`. Does not require `commands`. Does not change `Get-CmdPeekExampleCatalog` return type.

- [ ] **Step 1: Write the failing tests**

In `tests/UsageExamples.Tests.ps1`, add a new `Describe` (this file already dotsources `UsageExamples.ps1` in `BeforeAll`):

```powershell
Describe 'Get-CmdPeekCatalogKits' {
    It 'returns empty hashtable when the file is missing' {
        $kits = Get-CmdPeekCatalogKits -Path (Join-Path $TestDrive 'no-such-kits.json')
        $kits.Count | Should -Be 0
    }

    It 'returns empty hashtable when kits is absent' {
        $path = Join-Path $TestDrive 'commands-only.json'
        '{"commands":{"fd":{"category":"dev-tools","usages":["fd x"]}}}' | Set-Content -LiteralPath $path -Encoding UTF8
        $kits = Get-CmdPeekCatalogKits -Path $path
        $kits.Count | Should -Be 0
        $catalog = Get-CmdPeekExampleCatalog -Path $path
        $catalog.ContainsKey('fd') | Should -BeTrue
    }

    It 'returns empty hashtable for invalid JSON' {
        $path = Join-Path $TestDrive 'bad.json'
        '{' | Set-Content -LiteralPath $path -Encoding UTF8
        (Get-CmdPeekCatalogKits -Path $path).Count | Should -Be 0
    }

    It 'loads kits and keeps a one-element member list as an array' {
        $path = Join-Path $TestDrive 'kits.json'
        @'
{
  "kits": {
    "solo": ["fd"],
    "media": ["ffmpeg", "yt-dlp"]
  }
}
'@ | Set-Content -LiteralPath $path -Encoding UTF8
        $kits = Get-CmdPeekCatalogKits -Path $path
        @($kits['solo']).Count | Should -Be 1
        @($kits['solo'])[0] | Should -Be 'fd'
        @($kits['media']).Count | Should -Be 2
        @($kits['media']) | Should -Contain 'ffmpeg'
    }
}
```

In `tests/Invoke-CmdPeek.Tests.ps1`, inside `Describe 'usage-examples.json'`, add:

```powershell
    It 'declares role kits next to commands' {
        $path = Join-Path $PSScriptRoot '..\examples\usage-examples.json'
        $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        @($json.kits.media) | Should -Contain 'ffmpeg'
        @($json.kits.'dev-tools') | Should -Contain 'fd'
        @($json.kits.search) | Should -Contain 'rg'
        $json.commands.mpv.category | Should -Be 'media'
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Invoke-Pester -Path .\tests\UsageExamples.Tests.ps1 -FullNameFilter 'Get-CmdPeekCatalogKits*' -Output Detailed
Invoke-Pester -Path .\tests\Invoke-CmdPeek.Tests.ps1 -FullNameFilter '*role kits*' -Output Detailed
```

Expected: FAIL — `Get-CmdPeekCatalogKits` is not a recognized command; shipped JSON has no `kits` / `mpv`.

- [ ] **Step 3: Implement loader, shipped kits, export**

Add after `Get-CmdPeekExampleCatalog` in `src/UsageExamples.ps1`:

```powershell
function Get-CmdPeekCatalogKits {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    $kits = @{}
    $resolved = Get-CmdPeekExampleCatalogPath -Path $Path
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved)) {
        return $kits
    }

    try {
        $json = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $kits
    }

    if (-not $json -or -not $json.PSObject.Properties['kits']) {
        return $kits
    }

    foreach ($prop in $json.kits.PSObject.Properties) {
        $members = New-Object System.Collections.Generic.List[string]
        foreach ($item in @($prop.Value)) {
            if ($item -is [string] -and $item) {
                $members.Add($item)
            }
        }
        $kits[$prop.Name] = @($members)
    }

    return $kits
}
```

In `examples/usage-examples.json`:

1. After the `ffmpeg` command object, add `mpv` (kit member must be a catalog key):

```json
    "mpv": {
      "category": "media",
      "related": ["ffmpeg", "yt-dlp"],
      "usages": [
        "mpv <file>                      # Play media",
        "mpv --no-video <file>           # Audio only"
      ]
    },
```

2. After the closing `}` of `"commands"`, before the file’s final `}`, add a comma and:

```json
  "kits": {
    "media": ["ffmpeg", "yt-dlp", "mpv"],
    "dev-tools": ["fd", "rg", "fzf"],
    "search": ["rg", "fd", "fzf"]
  }
```

The file must remain valid JSON (`{ "commands": { ... }, "kits": { ... } }`).

Add `'Get-CmdPeekCatalogKits'` to `FunctionsToExport` in `src/cmdpeek.psd1` (next to `Get-CmdPeekExampleCatalog`) and to `Export-ModuleMember -Function` in `src/cmdpeek.psm1`.

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path .\tests\UsageExamples.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\Invoke-CmdPeek.Tests.ps1 -FullNameFilter 'usage-examples.json*' -Output Detailed
```

Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

```powershell
git add src/UsageExamples.ps1 src/cmdpeek.psd1 src/cmdpeek.psm1 examples/usage-examples.json tests/UsageExamples.Tests.ps1 tests/Invoke-CmdPeek.Tests.ps1
git commit -m "Load role kits from the example catalog JSON."
```

---

### Task 2: `shadowing` gaps

**Files:**
- Modify: `src/Inventory.ps1` (`Get-CmdPeekGap`, after the existing `not-on-path` loop, before `return`)
- Test: `tests/Inventory.Tests.ps1`

**Interfaces:**
- Consumes: existing `Get-CmdPeekGap -History -Catalog`
- Produces: one `kind = 'shadowing'` gap per command name that appears on 2+ distinct package managers (case-insensitive). Properties: `command`, `kind`, `reason`, `relatedTo = @()`, `category`, `packageManagers` (lowercase, A–Z). Hidden rows count. Same manager twice → no gap. Append after existing kinds; shadowing rows sorted by command A–Z (`OrdinalIgnoreCase`).

- [ ] **Step 1: Write the failing tests**

In `tests/Inventory.Tests.ps1`, inside `Describe 'Get-CmdPeekGap'`, add:

```powershell
    It 'flags a command installed from two package managers as shadowing' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'Scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @(); Hidden = $false
            }
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'Chocolatey'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @(); Hidden = $false
            }
        )
        $gaps = @(Get-CmdPeekGap -History $history -Catalog @{})
        $shadow = @($gaps | Where-Object { $_.kind -eq 'shadowing' })
        $shadow.Count | Should -Be 1
        @($shadow)[0].command | Should -Be 'jq'
        @(@($shadow)[0].packageManagers) | Should -Be @('chocolatey', 'scoop')
        @(@($shadow)[0].relatedTo).Count | Should -Be 0
    }

    It 'does not flag two rows with the same manager as shadowing' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @()
            }
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @()
            }
        )
        $gaps = @(Get-CmdPeekGap -History $history -Catalog @{})
        @($gaps | Where-Object { $_.kind -eq 'shadowing' }).Count | Should -Be 0
    }

    It 'counts a hidden row toward shadowing' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @(); Hidden = $true
            }
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'choco'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @(); Hidden = $false
            }
        )
        $gaps = @(Get-CmdPeekGap -History $history -Catalog @{})
        @($gaps | Where-Object { $_.kind -eq 'shadowing' }).Count | Should -Be 1
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Invoke-Pester -Path .\tests\Inventory.Tests.ps1 -FullNameFilter '*shadowing*' -Output Detailed
```

Expected: FAIL — no `shadowing` gaps.

- [ ] **Step 3: Implement shadowing**

In `Get-CmdPeekGap`, after the `not-on-path` loop and before `return`, add:

```powershell
    $byName = @{}
    foreach ($row in @($History)) {
        if (-not $row -or -not $row.Command) { continue }
        $key = $row.Command.ToLowerInvariant()
        if (-not $byName.ContainsKey($key)) {
            $byName[$key] = New-Object System.Collections.Generic.List[object]
        }
        $byName[$key].Add($row)
    }

    $shadowNames = [string[]]@($byName.Keys)
    if ($shadowNames.Count -gt 1) {
        [Array]::Sort($shadowNames, [StringComparer]::OrdinalIgnoreCase)
    }
    foreach ($key in $shadowNames) {
        $rows = @($byName[$key])
        $managers = New-Object System.Collections.Generic.List[string]
        foreach ($row in $rows) {
            $pm = ''
            if ($row.PSObject.Properties['PackageManager'] -and $row.PackageManager) {
                $pm = [string]$row.PackageManager.ToLowerInvariant()
            }
            if ($pm -and $managers -notcontains $pm) { $managers.Add($pm) }
        }
        if ($managers.Count -lt 2) { continue }
        $sortedPm = [string[]]@($managers)
        [Array]::Sort($sortedPm, [StringComparer]::OrdinalIgnoreCase)
        $first = @($rows)[0]
        $cat = 'other'
        if ($first.PSObject.Properties['Category'] -and $first.Category) {
            $cat = [string]$first.Category
        }
        $gaps.Add([pscustomobject]@{
            kind            = 'shadowing'
            command         = [string]$first.Command
            reason          = 'Installed from more than one package manager'
            relatedTo       = @()
            category        = $cat
            packageManagers = @($sortedPm)
        })
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path .\tests\Inventory.Tests.ps1 -Output Detailed
```

Expected: PASS (existing gap tests still green).

- [ ] **Step 5: Commit** (only if asked)

```powershell
git add src/Inventory.ps1 tests/Inventory.Tests.ps1
git commit -m "Flag commands installed from more than one package manager."
```

---

### Task 3: `kit` gaps

**Files:**
- Modify: `src/Inventory.ps1` (`Get-CmdPeekGap` param block + kit loop after shadowing)
- Test: `tests/Inventory.Tests.ps1`

**Interfaces:**
- Consumes: `Get-CmdPeekCatalogKits` hashtable shape from Task 1; `Get-CmdPeekCatalogEntry`
- Produces: `Get-CmdPeekGap -History -Catalog [-Kits]`. Omitted, `$null`, or empty `-Kits` → no `kit` gaps. If a kit has ≥1 installed member, emit `kit` for each missing member unless that name already has `missing-related`. At most one `kit` gap per command; overlapping kits keep the kit id that sorts first `OrdinalIgnoreCase`. `relatedTo` is `@($kitId)`. `reason` is `Incomplete kit '<id>'`. Skip kits where every member is missing.

- [ ] **Step 1: Write the failing tests**

In `tests/Inventory.Tests.ps1`, inside `Describe 'Get-CmdPeekGap'`, add:

```powershell
    It 'emits a kit gap for a missing member when another member is installed' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @()
            }
        )
        $catalog = @{
            'fd'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fd x') }
            'rg'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('rg x') }
        }
        $kits = @{ 'dev-tools' = @('fd', 'rg') }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits)
        $kitGaps = @($gaps | Where-Object { $_.kind -eq 'kit' })
        $kitGaps.Count | Should -Be 1
        @($kitGaps)[0].command | Should -Be 'rg'
        @(@($kitGaps)[0].relatedTo) | Should -Be @('dev-tools')
        @($kitGaps)[0].reason | Should -Match 'dev-tools'
    }

    It 'skips a kit gap when the missing name is already missing-related' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @('rg')
            }
        )
        $catalog = @{
            'fd' = [pscustomobject]@{ category = 'dev-tools'; related = @('rg'); usages = @('fd x') }
            'rg' = [pscustomobject]@{ category = 'dev-tools'; related = @('fd'); usages = @('rg x') }
        }
        $kits = @{ 'dev-tools' = @('fd', 'rg') }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits)
        @($gaps | Where-Object { $_.kind -eq 'missing-related' }).command | Should -Contain 'rg'
        @($gaps | Where-Object { $_.kind -eq 'kit' }).Count | Should -Be 0
    }

    It 'emits only one kit gap when a missing name sits in two kits' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @()
            }
        )
        $catalog = @{
            'fd'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fd x') }
            'fzf' = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fzf') }
        }
        $kits = @{
            'search'    = @('fd', 'fzf')
            'dev-tools' = @('fd', 'fzf')
        }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits)
        $kitGaps = @($gaps | Where-Object { $_.kind -eq 'kit' })
        $kitGaps.Count | Should -Be 1
        @(@($kitGaps)[0].relatedTo)[0] | Should -Be 'dev-tools'
    }

    It 'does not emit kit gaps when no member is installed' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @()
            }
        )
        $kits = @{ 'media' = @('ffmpeg', 'mpv') }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog @{} -Kits $kits)
        @($gaps | Where-Object { $_.kind -eq 'kit' }).Count | Should -Be 0
    }

    It 'does not emit kit gaps when -Kits is omitted' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @()
            }
        )
        $catalog = @{
            'fd' = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fd x') }
            'rg' = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('rg x') }
        }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog)
        @($gaps | Where-Object { $_.kind -eq 'kit' }).Count | Should -Be 0
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Invoke-Pester -Path .\tests\Inventory.Tests.ps1 -FullNameFilter '*kit*' -Output Detailed
```

Expected: FAIL — `Get-CmdPeekGap` has no `-Kits` (or emits nothing).

- [ ] **Step 3: Implement `-Kits` and kit gaps**

Add to `Get-CmdPeekGap`’s `param` block:

```powershell
        [hashtable]$Kits
```

After `if (-not $Catalog) { $Catalog = @{} }`:

```powershell
    if (-not $Kits) { $Kits = @{} }
```

After the shadowing loop, before `return`:

```powershell
    $missingRelatedNames = @{}
    foreach ($g in @($gaps)) {
        if ($g -and $g.kind -eq 'missing-related' -and $g.command) {
            $missingRelatedNames[$g.command.ToLowerInvariant()] = $true
        }
    }

    $kitSeen = @{}
    $kitGaps = New-Object System.Collections.Generic.List[object]
    $kitIds = [string[]]@($Kits.Keys)
    if ($kitIds.Count -gt 1) {
        [Array]::Sort($kitIds, [StringComparer]::OrdinalIgnoreCase)
    }
    foreach ($kitId in $kitIds) {
        $members = @($Kits[$kitId])
        $anyInstalled = $false
        foreach ($member in $members) {
            if ($member -and $installed.ContainsKey(([string]$member).ToLowerInvariant())) {
                $anyInstalled = $true
                break
            }
        }
        if (-not $anyInstalled) { continue }

        foreach ($member in $members) {
            if (-not $member) { continue }
            $lk = ([string]$member).ToLowerInvariant()
            if ($installed.ContainsKey($lk)) { continue }
            if ($missingRelatedNames.ContainsKey($lk)) { continue }
            if ($kitSeen.ContainsKey($lk)) { continue }
            $kitSeen[$lk] = $true
            $entry = Get-CmdPeekCatalogEntry -Command $member -Catalog $Catalog
            $commandName = [string]$member
            $cat = 'other'
            if ($entry) {
                foreach ($ck in @($Catalog.Keys)) {
                    if ($ck.ToLowerInvariant() -eq $lk) { $commandName = [string]$ck; break }
                }
                if ($entry.PSObject.Properties['category'] -and $entry.category) {
                    $cat = [string]$entry.category
                }
            }
            $kitGaps.Add([pscustomobject]@{
                kind      = 'kit'
                command   = $commandName
                reason    = "Incomplete kit '$kitId'"
                relatedTo = @($kitId)
                category  = $cat
            })
        }
    }

    $kitArr = @($kitGaps)
    if ($kitArr.Count -gt 1) {
        $kitArr = @($kitArr | Sort-Object { $_.command.ToLowerInvariant() })
    }
    foreach ($g in $kitArr) { $gaps.Add($g) }
```

`ToLowerInvariant()` as the `Sort-Object` key is the PowerShell 5.1-safe stand-in for ordinal case-insensitive command order (ASCII catalog names).

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path .\tests\Inventory.Tests.ps1 -Output Detailed
```

Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

```powershell
git add src/Inventory.ps1 tests/Inventory.Tests.ps1
git commit -m "Suggest missing members of incomplete command kits."
```

---

### Task 4: `category-neighbor` + snapshot kit wiring

**Files:**
- Modify: `src/Inventory.ps1` (`Get-CmdPeekGap` neighbor loop; `ConvertTo-CmdPeekSnapshot` `-Kits`)
- Modify: `src/cmdpeek.psm1` (TUI `Get-CmdPeekGap` call ~line 250)
- Test: `tests/Inventory.Tests.ps1`

**Interfaces:**
- Consumes: `Get-CmdPeekGap -Kits` from Task 3; `Get-CmdPeekCatalogKits` from Task 1
- Produces: `category-neighbor` gaps (max 3 per category, skip names already `missing-related` or `kit`). `relatedTo` = up to 3 installed names in that category, A–Z. `ConvertTo-CmdPeekSnapshot [-Kits]`: when `-Kits` is **omitted** (`-not $PSBoundParameters.ContainsKey('Kits')`), call `Get-CmdPeekCatalogKits` and pass it through. Existing snapshot tests pass `-Kits @{}`. TUI path: `$kits = Get-CmdPeekCatalogKits`; `Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits`. Cheat-sheet `Get-CmdPeekGap` call may stay without `-Kits` (it only reads `missing-related`).

- [ ] **Step 1: Write the failing tests**

In `tests/Inventory.Tests.ps1`, inside `Describe 'Get-CmdPeekGap'`, add:

```powershell
    It 'suggests at most three category neighbors and skips missing-related and kit names' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @('rg')
            }
        )
        $catalog = @{
            'fd'   = [pscustomobject]@{ category = 'dev-tools'; related = @('rg'); usages = @('fd x') }
            'rg'   = [pscustomobject]@{ category = 'dev-tools'; related = @('fd'); usages = @('rg x') }
            'fzf'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fzf') }
            'bat'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('bat') }
            'eza'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('eza') }
            'delta'= [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('delta') }
            'jq'   = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('jq') }
        }
        $kits = @{ 'dev-tools' = @('fd', 'fzf') }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits)
        @($gaps | Where-Object { $_.kind -eq 'missing-related' }).command | Should -Contain 'rg'
        @($gaps | Where-Object { $_.kind -eq 'kit' }).command | Should -Contain 'fzf'
        $neighbors = @($gaps | Where-Object { $_.kind -eq 'category-neighbor' })
        $neighbors.Count | Should -Be 3
        $neighbors.command | Should -Not -Contain 'rg'
        $neighbors.command | Should -Not -Contain 'fzf'
        $neighbors.command | Should -Not -Contain 'fd'
        @($neighbors)[0].command | Should -Be 'bat'
        @(@($neighbors)[0].relatedTo) | Should -Contain 'fd'
    }

    It 'does not suggest category neighbors when nothing in that category is installed' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @()
            }
        )
        $catalog = @{
            'ffmpeg' = [pscustomobject]@{ category = 'media'; related = @(); usages = @('ffmpeg') }
            'mpv'    = [pscustomobject]@{ category = 'media'; related = @(); usages = @('mpv') }
        }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits @{})
        @($gaps | Where-Object { $_.kind -eq 'category-neighbor' }).Count | Should -Be 0
    }
```

In `Describe 'ConvertTo-CmdPeekSnapshot'`, add `-Kits @{}` to **every existing** `ConvertTo-CmdPeekSnapshot` call in that Describe (three tests). Then add:

```powershell
    It 'loads shipped kits when -Kits is omitted' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @()
            }
        )
        $catalog = @{
            'fd'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fd x') }
            'fzf' = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fzf') }
        }
        $snap = ConvertTo-CmdPeekSnapshot -History $history -Manager @() -Catalog $catalog -Favorite @() -Hidden @() -CommandTester { $true }
        @($snap.gaps | Where-Object { $_.kind -eq 'kit' -and $_.command -eq 'fzf' }).Count | Should -BeGreaterThan 0
    }
```

That omitted-`-Kits` test depends on Task 1 shipped `dev-tools` / `search` kits including `fzf`. `fd`’s catalog `related` is empty in this fixture so `fzf` is not `missing-related`.

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Invoke-Pester -Path .\tests\Inventory.Tests.ps1 -FullNameFilter '*category neighbor*','*shipped kits*' -Output Detailed
```

Expected: FAIL — no `category-neighbor`; omitted `-Kits` on snapshot does not load shipped kits.

- [ ] **Step 3: Implement neighbors and snapshot/TUI wiring**

After kit gaps are appended in `Get-CmdPeekGap`, before `return`:

```powershell
    $covered = @{}
    foreach ($g in @($gaps)) {
        if (-not $g -or -not $g.command) { continue }
        if ($g.kind -eq 'missing-related' -or $g.kind -eq 'kit') {
            $covered[$g.command.ToLowerInvariant()] = $true
        }
    }

    $byCatInstalled = @{}
    $byCatMissing = @{}
    foreach ($ck in @($Catalog.Keys)) {
        $entry = $Catalog[$ck]
        $cat = 'other'
        if ($entry -and $entry.PSObject.Properties['category'] -and $entry.category) {
            $cat = [string]$entry.category
        }
        if (-not $byCatInstalled.ContainsKey($cat)) {
            $byCatInstalled[$cat] = New-Object System.Collections.Generic.List[string]
            $byCatMissing[$cat] = New-Object System.Collections.Generic.List[string]
        }
        $lk = $ck.ToLowerInvariant()
        if ($installed.ContainsKey($lk)) {
            $byCatInstalled[$cat].Add([string]$installed[$lk].Command)
        }
        else {
            $byCatMissing[$cat].Add([string]$ck)
        }
    }

    $neighborList = New-Object System.Collections.Generic.List[object]
    foreach ($cat in @($byCatInstalled.Keys)) {
        $installedHere = @($byCatInstalled[$cat])
        if ($installedHere.Count -eq 0) { continue }
        $relatedTo = @($installedHere | Sort-Object { $_.ToLowerInvariant() } | Select-Object -First 3)
        $cands = @($byCatMissing[$cat] | Sort-Object { $_.ToLowerInvariant() })
        $kept = 0
        foreach ($name in $cands) {
            $lk = $name.ToLowerInvariant()
            if ($covered.ContainsKey($lk)) { continue }
            if ($kept -ge 3) { break }
            $neighborList.Add([pscustomobject]@{
                kind      = 'category-neighbor'
                command   = $name
                reason    = "Other tools in category '$cat' are installed"
                relatedTo = @($relatedTo)
                category  = $cat
            })
            $kept++
            $covered[$lk] = $true
        }
    }

    $neighborArr = @($neighborList)
    if ($neighborArr.Count -gt 1) {
        $neighborArr = @($neighborArr | Sort-Object { $_.command.ToLowerInvariant() })
    }
    foreach ($g in $neighborArr) { $gaps.Add($g) }
```

`ConvertTo-CmdPeekSnapshot` param block: add `[hashtable]$Kits`.

Replace `$gaps = @(Get-CmdPeekGap -History $history -Catalog $Catalog)` with:

```powershell
    $kitMap = $Kits
    if (-not $PSBoundParameters.ContainsKey('Kits')) {
        $kitMap = Get-CmdPeekCatalogKits
    }
    if (-not $kitMap) { $kitMap = @{} }
    $gaps = @(Get-CmdPeekGap -History $history -Catalog $Catalog -Kits $kitMap)
```

In `src/cmdpeek.psm1`, TUI branch only:

```powershell
        $kits = Get-CmdPeekCatalogKits
        $gapList = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits)
```

Leave the cheat-sheet `Get-CmdPeekGap` call without `-Kits`.

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path .\tests\Inventory.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests -PassThru
```

Expected: 0 failed. Neighbor order in the cap-3 test: remaining names A–Z among `bat`, `delta`, `eza`, `jq` → `bat`, `delta`, `eza`.

- [ ] **Step 5: Commit** (only if asked)

```powershell
git add src/Inventory.ps1 src/cmdpeek.psm1 tests/Inventory.Tests.ps1
git commit -m "Suggest same-category catalog tools and wire shipped kits into snapshots."
```

---

### Task 5: TUI column, MCP enum, README

**Files:**
- Modify: `src/Tui.ps1` (kind pad `16` → `18` on the gaps view row)
- Modify: `mcp/src/index.ts` (`list_gaps` enum + description)
- Modify: `README.md` (`cmdpeek -Gaps` row and `list_gaps` row)
- Modify: `src/cmdpeek.ps1` (help banner `-Gaps` line)
- Test: `tests/Tui.Tests.ps1`

**Interfaces:**
- Consumes: gap `kind` strings from Tasks 2–4 (`shadowing`, `kit`, `category-neighbor`)
- Produces: TUI kind column width 18 (`category-neighbor` is 18 characters). MCP `kind` enum: `missing-related | thin-docs | not-on-path | shadowing | category-neighbor | kit | all`. Filter remains `normalize(g.kind) === kind`; `all` unfiltered. No TypeScript gap synthesis.

- [ ] **Step 1: Write the failing TUI test**

`Write-CmdPeekTuiFrame` writes to `[Console]` and does not return the frame, so do not call it from Pester. `tests/Tui.Tests.ps1` already dotsources `src/Tui.ps1`. Add:

```powershell
Describe 'Get-CmdPeekPadded' {
    It 'keeps category-neighbor intact at width 18' {
        Get-CmdPeekPadded 'category-neighbor' 18 | Should -Be 'category-neighbor'
        Get-CmdPeekPadded 'category-neighbor' 16 | Should -Be 'category-neighbo'
    }
}

Describe 'Write-CmdPeekTuiFrame gaps kind width' {
    It 'pads gap kinds to 18 characters' {
        $src = Join-Path $PSScriptRoot '..\src\Tui.ps1'
        $text = Get-Content -LiteralPath $src -Raw -Encoding UTF8
        $text | Should -Match 'Get-CmdPeekPadded \$g\.Kind 18'
    }
}
```

- [ ] **Step 2: Run tests to verify the width assertion fails**

```powershell
Invoke-Pester -Path .\tests\Tui.Tests.ps1 -FullNameFilter '*18*' -Output Detailed
```

Expected: `Get-CmdPeekPadded` PASS; `pads gap kinds to 18 characters` FAIL (source still has `16`).

- [ ] **Step 3: Implement surfaces**

In `src/Tui.ps1`, gaps view:

```powershell
                $kind = Get-CmdPeekPadded $g.Kind 18
```

In `mcp/src/index.ts`, replace the `list_gaps` tool registration with:

```typescript
server.tool(
  "list_gaps",
  "Identify tooling gaps: missing related CLIs, thin docs, not-on-path shims, the same name from more than one package manager, incomplete role kits, and same-category catalog tools. Use this to suggest what to install or document next.",
  {
    kind: z
      .enum([
        "missing-related",
        "thin-docs",
        "not-on-path",
        "shadowing",
        "category-neighbor",
        "kit",
        "all",
      ])
      .optional()
      .describe("Gap kind to return (default all)"),
  },
  async ({ kind }) => {
    const snap = await loadSnapshot();
    let gaps = snap.gaps ?? [];
    if (kind && kind !== "all") {
      gaps = gaps.filter((g) => normalize(g.kind) === kind);
    }
    return asText({ gaps });
  },
);
```

Do not change the filter body beyond the enum.

README `-Gaps` row:

```markdown
| `cmdpeek -Gaps` | JSON gaps: missing related, thin docs, not-on-path, **shadowing**, incomplete **kits**, and **category-neighbor** |
```

README `list_gaps` row:

```markdown
| `list_gaps` | Missing related, thin docs, not-on-path, shadowing, kit, and category-neighbor; filter with `kind` (`missing-related`, `thin-docs`, `not-on-path`, `shadowing`, `kit`, `category-neighbor`, `all`) |
```

`src/cmdpeek.ps1` help:

```
  cmdpeek -Gaps               JSON gaps: missing related, thin docs, not-on-path, shadowing, kits, category-neighbor
```

Do not document kit JSON as a user-facing config file.

- [ ] **Step 4: Run tests and MCP build**

```powershell
Invoke-Pester -Path .\tests\Tui.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests -PassThru
Set-Location .\mcp; npm run build
```

Expected: Pester 0 failed; `tsc` exits 0.

- [ ] **Step 5: Commit** (only if asked)

```powershell
git add src/Tui.ps1 mcp/src/index.ts README.md src/cmdpeek.ps1 tests/Tui.Tests.ps1
git commit -m "Expose new gap kinds in the TUI, MCP list_gaps, and README."
```

`mcp/dist` is gitignored; `npm run build` is for local/CI verification only.

---

## Self-review vs spec

| Spec requirement | Task |
| --- | --- |
| `Get-CmdPeekCatalogKits`; `@()` on members; empty on missing/invalid/`kits` absent | 1 |
| Shipped kits `media` / `dev-tools` / `search`; catalog keys exist | 1 (`mpv` entry) |
| `Get-CmdPeekExampleCatalog` return type unchanged | 1 |
| Installed set includes Hidden | 2, 3, 4 (same `$installed` hashtable) |
| `shadowing`: 2+ managers, one gap, sorted lowercase `packageManagers`, hidden counts, same-manager skip | 2 |
| `kit`: ≥1 member installed; skip `missing-related`; one gap per name; first kit id A–Z; skip all-missing kits; `relatedTo` = kit id | 3 |
| `Get-CmdPeekGap -Kits` omitted/empty → no kit gaps | 3 |
| `category-neighbor`: max 3/category; skip missing-related and kit; `relatedTo` up to 3 installed in category | 4 |
| Dedup order: existing, shadowing, kit, neighbor | 2–4 append order |
| `ConvertTo-CmdPeekSnapshot` loads kits when `-Kits` omitted; tests can pass `@{}` | 4 |
| `-Gaps` / snapshot automatic (snapshot path already serializes `Get-CmdPeekGap`) | 4 (snapshot wiring); `-Gaps` uses snapshot |
| TUI `g` kind width 18 | 5 |
| MCP enum + no TS synthesis | 5 |
| Cheat sheet `gaps:` still missing-related only | 4 (cheat-sheet call omits `-Kits`; filter unchanged) |
| README one sentence; no user-facing kit config docs | 5 |

No spec section is left without a task.
