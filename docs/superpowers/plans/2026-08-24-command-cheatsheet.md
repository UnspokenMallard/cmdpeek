# Command Cheat Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `cmdpeek fd` (unique exact command name) prints a one-command cheat sheet instead of a numbered search list.

**Architecture:** Exact-name match runs on the existing search path before substring search and before `Select-CmdPeekQuickHistory` (so hidden commands still resolve). One hit → `Test-CmdPeekOnPath` + help-probe + `Format-CmdPeekQuickOutput -CheatSheet`. Two+ exact names → list those rows only. Zero exact names → today’s substring search list.

**Tech Stack:** PowerShell 5.1 module (`src/`), Pester 5+.

**Spec:** `docs/superpowers/specs/2026-08-24-command-cheatsheet-design.md`

## Global Constraints

- PowerShell 5.1 floor: no `??`, `?:`, `Join-Path` with more than two arguments, `-AsHashtable` on `ConvertFrom-Json`.
- Wrap pipeline results with `@(...)` before `[0]`.
- Do not change `-n` / `-Json` / `-Gaps` / `-i` / `-Recent`, MCP `get_command`, grouping, or recency cursors.
- Do not advance `LastPeekAt` or `LastMcpAt` on the cheat-sheet or search-list path.
- Do not invent gap kinds; `gaps:` uses existing `missing-related` only.
- Commits: skip `git commit` unless the user explicitly asked for commits.
- TDD: failing test first; watch it fail; then minimal code.

## File map

| File | Responsibility |
| --- | --- |
| `src/InteractiveMode.ps1` | `Format-CmdPeekQuickOutput -CheatSheet` |
| `src/CommandHistory.ps1` | `Select-CmdPeekExactCommand` |
| `src/cmdpeek.psm1` | Search-path branch |
| `src/cmdpeek.psd1` | Export `Select-CmdPeekExactCommand` |
| `tests/Format.Tests.ps1` | Cheat-sheet formatting |
| `tests/CommandHistory.Tests.ps1` | Exact-name selection |
| `tests/Invoke-CmdPeek.Tests.ps1` | CLI trigger cases |
| `README.md`, `src/cmdpeek.ps1` | User-facing help |

---

### Task 1: `-CheatSheet` formatter

**Files:**
- Modify: `src/InteractiveMode.ps1` (`Format-CmdPeekQuickOutput`)
- Test: `tests/Format.Tests.ps1`

**Interfaces:**
- Consumes: existing `Format-CmdPeekQuickOutput` (`-History`, `-ExampleCount`, `-Header`)
- Produces: `[switch]$CheatSheet` — omits list index and `Last N` header; first line is `{command} ({manager})` plus PATH suffix; skips `also:` shims; prints `gaps: a, b` from row `MissingRelated` instead of `suggestions:`

- [ ] **Step 1: Write the failing test**

In `tests/Format.Tests.ps1`, inside `Describe 'Format-CmdPeekQuickOutput'`, add:

```powershell
    It 'prints a cheat sheet title without an index and uses MissingRelated as gaps' {
        $history = @(
            [pscustomobject]@{
                Command        = 'fd'
                PackageManager = 'scoop'
                OnPath         = $true
                Usages         = @(
                    'fd <pattern> # Find files'
                    'fd -t f <pattern> # Find files only'
                )
                Related        = @('rg', 'fzf')
                MissingRelated = @('rg', 'fzf')
                Shims          = @('should-not-appear')
            }
        )
        $text = Format-CmdPeekQuickOutput -History $history -ExampleCount 5 -CheatSheet
        $text | Should -Match '^fd \(scoop\)'
        $text | Should -Not -Match '^\d+\. fd'
        $text | Should -Not -Match 'Last \d+ installed commands'
        $text | Should -Not -Match 'also:'
        $text | Should -Not -Match 'suggestions:'
        $text | Should -Match 'gaps: rg, fzf'
        $text | Should -Match 'Find files'
    }
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Import-Module Pester -MinimumVersion 5.0.0
Invoke-Pester -Path .\tests\Format.Tests.ps1 -Output Detailed
```

Expected: FAIL — `-CheatSheet` is not a parameter.

- [ ] **Step 3: Write minimal implementation**

In `Format-CmdPeekQuickOutput` param block, add `[switch]$CheatSheet`.

When building the title and header:

```powershell
    if ($CheatSheet) {
        $title = '{0} ({1})' -f $row.Command, $row.PackageManager
    }
    else {
        $title = '{0}. {1} ({2})' -f $index, $row.Command, $row.PackageManager
    }
    if ($row.PSObject.Properties['OnPath'] -and -not $row.OnPath) {
        $title += '  not on PATH'
    }
```

For the first line of the whole output when `-CheatSheet`: do **not** add `Last N installed commands:` and do **not** use `-Header`. The first `$lines.Add` should be skipped for the default header; add `$title` as the first content line (blank line after it is optional; keep a blank line after the title to match list layout).

Skip the shims (`also:`) block when `$CheatSheet`.

When `$CheatSheet`, skip `suggestions:`. If `MissingRelated` is non-empty:

```powershell
        if ($CheatSheet) {
            $missing = @()
            if ($row.PSObject.Properties['MissingRelated'] -and $row.MissingRelated) {
                $missing = @($row.MissingRelated | Where-Object { $_ })
            }
            if ($missing.Count -gt 0) {
                $lines.Add(('   gaps: {0}' -f ($missing -join ', ')))
            }
        }
        elseif ($row.PSObject.Properties['Related'] -and $row.Related -and @($row.Related).Count -gt 0) {
            $lines.Add(('   suggestions: {0}' -f ((@($row.Related) | Select-Object -First 3) -join ', ')))
        }
```

Existing tests must still pass (numbered titles, `-Header` still works when `-CheatSheet` is off).

- [ ] **Step 4: Run Format tests — PASS**

Same Pester path. Expected: all Format tests PASS.

- [ ] **Step 5: Commit** (only if the user asked)

```
git add src/InteractiveMode.ps1 tests/Format.Tests.ps1
git commit -m "Format a one-command cheat sheet without a numbered list."
```

---

### Task 2: Exact-name selector

**Files:**
- Modify: `src/CommandHistory.ps1` (append near `Search-CmdPeekCommand`)
- Modify: `src/cmdpeek.psm1` and `src/cmdpeek.psd1` — export `Select-CmdPeekExactCommand`
- Test: `tests/CommandHistory.Tests.ps1`

**Interfaces:**
- Consumes: flat history rows with `Command`
- Produces:

```powershell
function Select-CmdPeekExactCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [string]$Query
    )
    # returns rows whose Command equals Query (case-insensitive); empty query → @()
}
```

- [ ] **Step 1: Write the failing tests**

Append to `tests/CommandHistory.Tests.ps1`:

```powershell
Describe 'Select-CmdPeekExactCommand' {
    It 'returns the one row whose Command equals the query' {
        $history = @(
            [pscustomobject]@{ Command = 'fd'; PackageManager = 'scoop' }
            [pscustomobject]@{ Command = 'ffmpeg'; PackageManager = 'scoop' }
        )
        $hits = @(Select-CmdPeekExactCommand -History $history -Query 'FD')
        $hits.Count | Should -Be 1
        $hits[0].Command | Should -Be 'fd'
    }

    It 'returns both dual-manager rows with the same command name' {
        $history = @(
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop' }
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'chocolatey' }
        )
        @(Select-CmdPeekExactCommand -History $history -Query 'jq').Count | Should -Be 2
    }

    It 'returns nothing when the query only appears in other fields' {
        $history = @(
            [pscustomobject]@{ Command = 'fd'; PackageManager = 'scoop'; Usages = @('fd <pattern> # Find') }
        )
        @(Select-CmdPeekExactCommand -History $history -Query 'pattern').Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Invoke-Pester -Path .\tests\CommandHistory.Tests.ps1 -Output Detailed
```

Expected: FAIL `Select-CmdPeekExactCommand` is not recognized.

- [ ] **Step 3: Write minimal implementation**

```powershell
function Select-CmdPeekExactCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [string]$Query
    )

    $q = ''
    if ($null -ne $Query) { $q = ([string]$Query).Trim() }
    if ([string]::IsNullOrWhiteSpace($q)) { return @() }

    $needle = $q.ToLowerInvariant()
    return @(
        @($History) | Where-Object {
            $_ -and ([string]$_.Command).ToLowerInvariant() -eq $needle
        }
    )
}
```

Export from `cmdpeek.psm1` (`Export-ModuleMember`) and `cmdpeek.psd1` (`FunctionsToExport`) as `Select-CmdPeekExactCommand`.

- [ ] **Step 4: Run CommandHistory tests — PASS**

- [ ] **Step 5: Commit** (only if asked)

```
git commit -m "Select history rows whose command name matches exactly."
```

---

### Task 3: Wire search path in `Invoke-CmdPeek`

**Files:**
- Modify: `src/cmdpeek.psm1` (the `-not $isRecencyPath` search/list block ~249-254)
- Test: `tests/Invoke-CmdPeek.Tests.ps1`

**Interfaces:**
- Consumes: `Select-CmdPeekExactCommand`, `Test-CmdPeekOnPath`, `Get-CmdPeekGap`, `Add-CmdPeekUsageProbe`, `Format-CmdPeekQuickOutput -CheatSheet`
- Produces: CLI behavior per spec

Replace the search-path block so exact match happens **before** `Select-CmdPeekQuickHistory` (hidden rows stay eligible).

Keep substring `Search-CmdPeekCommand` on `$history` for `-Json`/`-Gaps`/interactive. Skip that early substring pass when this is the human search path (has `$Search`, not recency, not Json/Gaps, not interactive):

```powershell
    $searchPathExact = [bool]$Search -and -not $isRecencyPath -and -not $Json -and -not $Gaps -and -not $useInteractive

    if (($Search -or $Category) -and -not $isRecencyPath -and -not $searchPathExact) {
        $history = @(Search-CmdPeekCommand -History $history -Query $Search -Category $Category)
    }
    elseif ($searchPathExact -and $Category) {
        $history = @(Search-CmdPeekCommand -History $history -Category $Category)
    }
```

Then the search-path block (`if (-not $isRecencyPath)`):

```powershell
    if (-not $isRecencyPath) {
        if ($Search) {
            $exact = @(Select-CmdPeekExactCommand -History $history -Query $Search)
            if ($exact.Count -eq 1) {
                $row = $exact[0]
                $onPath = Test-CmdPeekOnPath -Command $row.Command -CommandTester $CommandTester
                $row | Add-Member -NotePropertyName OnPath -NotePropertyValue $onPath -Force
                $gapList = @(Get-CmdPeekGap -History $history -Catalog $catalog)
                $missing = @(
                    $gapList |
                        Where-Object {
                            $_ -and $_.kind -eq 'missing-related' -and
                            @($_.relatedTo) -contains $row.Command
                        } |
                        ForEach-Object { [string]$_.command }
                )
                $row | Add-Member -NotePropertyName MissingRelated -NotePropertyValue $missing -Force
                $slice = @(Add-CmdPeekUsageProbe -History @($row) -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner)
                Write-Output (Format-CmdPeekQuickOutput -History $slice -ExampleCount 5 -CheatSheet)
                return
            }
            if ($exact.Count -gt 1) {
                $flat = @(Add-CmdPeekUsageProbe -History $exact -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner)
                Write-Output (Format-CmdPeekQuickOutput -History $flat -ExampleCount 3)
                return
            }
            $history = @(Search-CmdPeekCommand -History $history -Query $Search -Category $Category)
        }

        $flat = @(Select-CmdPeekQuickHistory -History $history -Count 0)
        $flat = @(Add-CmdPeekUsageProbe -History $flat -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner)
        Write-Output (Format-CmdPeekQuickOutput -History $flat -ExampleCount 3)
        return
    }
```

Use `$exact[0]` only after `@($exact)` (already wrapped). Dual-manager list keeps numbered `Format-CmdPeekQuickOutput` (not `-CheatSheet`).

- [ ] **Step 1: Write failing Invoke-CmdPeek tests**

Fixture style: scoop TestDrive apps like existing tests. Use `examples/usage-examples.json` for `fd` usages.

1. Unique `fd` — `Invoke-CmdPeek -Search fd -NonInteractive` (no `-Count`): output matches `^fd \(scoop\)` or `fd (scoop)`, matches `Find files`, does **not** match `Last \d+ installed commands` or `^\d+\. fd`, seeded `LastPeekAt` unchanged.

2. Two `jq` apps (scoop only can do two names — use two package folders `jq` is one name; dual managers: enable chocolatey+scoop fixtures). Simpler: two scoop packages cannot share command `jq` unless two managers. Create scoop `jq` and a chocolatey lib `jq` like other tests if present; otherwise two history managers via EnabledManagers scoop+chocolatey with both roots populated.

   Minimal chocolatey+scoop dual `jq` (copy patterns from dual-install tests if any). If none, create:
   - scoop `apps\jq\current` + chocolatey `lib\jq` shim as in PackageManager tests.

   Output should match `jq` twice / both `scoop` and `chocolatey`, and match `\d+\. jq` (numbered list).

3. Usage-only query: one `fd` package; `-Search pattern` → list path (contains `fd`, may be numbered); not a cheat-sheet first line `pattern (`.

4. Hide `fd`, then `-Search fd` → still cheat sheet (`fd (scoop)`), `LastPeekAt` unchanged.

- [ ] **Step 2: Run `tests/Invoke-CmdPeek.Tests.ps1` — expect FAIL** (unique fd still numbered list / hidden omitted)

- [ ] **Step 3: Implement** the wiring above.

- [ ] **Step 4: Run `tests/Invoke-CmdPeek.Tests.ps1` and `tests/Format.Tests.ps1` — PASS.** Then `Invoke-Pester -Path .\tests` — 0 failed.

- [ ] **Step 5: Commit** (only if asked)

```
git commit -m "Show a cheat sheet when cmdpeek search matches one command name."
```

---

### Task 4: README and help

**Files:**
- Modify: `README.md` usage table (`cmdpeek -Search rg` row and a `cmdpeek fd` row)
- Modify: `src/cmdpeek.ps1` usage banner

Document: unique exact name → cheat sheet; otherwise search list. Do not claim MCP `get_command` changed.

- [ ] **Step 1:** Edit docs (no failing test required).

README: change the Search row and add:

```markdown
| `cmdpeek fd` | Unique command name: cheat sheet (usages + missing related). Otherwise search. |
```

Help banner add:

```
  cmdpeek fd              Cheat sheet if that name is unique; else search
```

- [ ] **Step 2:** `Invoke-Pester -Path .\tests` — 0 failed.

- [ ] **Step 3: Commit** (only if asked)

---

## Self-review vs spec

| Spec requirement | Task |
| --- | --- |
| Unique exact name → cheat sheet | 2, 3 |
| Two+ exact (dual jq) → those rows only, numbered | 2, 3 |
| Zero exact → substring search | 3 |
| Hidden unique name still sheets | 3 (before QuickHistory) |
| No LastPeekAt | 3 |
| Title without index; 5 usages; PATH; gaps: missing-related | 1, 3 |
| No shims/grouping on this path | 1 (skip also:), 3 |
| `-n` / Json / Gaps / i unchanged | 3 early-filter split |
| README + help | 4 |
| MCP get_command unchanged | no TS task |
