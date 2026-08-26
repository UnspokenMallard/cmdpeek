#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CmdPeekTaskTokens {
    param([string]$Task)
    if ([string]::IsNullOrWhiteSpace($Task)) { return @() }
    $lower = $Task.ToLowerInvariant()
    $parts = @($lower -split '[^a-z0-9+.-]+' | Where-Object { $_ -and $_.Length -gt 1 })
    return @($parts)
}

function Get-CmdPeekTaskScore {
    [CmdletBinding()]
    param(
        [string]$Query,
        [string]$Command,
        $Entry
    )

    if ([string]::IsNullOrWhiteSpace($Query) -or [string]::IsNullOrWhiteSpace($Command)) { return 0 }
    $q = $Query.Trim().ToLowerInvariant()
    $tokens = @(Get-CmdPeekTaskTokens -Task $Query)
    $score = 0
    $reasons = New-Object System.Collections.Generic.List[string]

    $cmdLower = $Command.ToLowerInvariant()
    if ($cmdLower -eq $q) {
        $score += 90
        $reasons.Add('exact name')
    }
    elseif ($cmdLower.Contains($q) -or $q.Contains($cmdLower)) {
        $score += 60
        $reasons.Add('name')
    }

    $aliases = @(Get-CmdPeekCatalogAliasList -Entry $Entry)
    foreach ($alias in $aliases) {
        $al = $alias.ToLowerInvariant()
        if ($al -eq $q) {
            $score += 88
            $reasons.Add('alias')
        }
        elseif ($al.Contains($q) -or $q.Contains($al)) {
            $score += 50
            $reasons.Add('alias')
        }
    }

    $caps = @(Get-CmdPeekCatalogCapabilityList -Entry $Entry)
    foreach ($cap in $caps) {
        $cl = $cap.ToLowerInvariant()
        if ($cl -eq $q) {
            $score += 100
            $reasons.Add("capability '$cap'")
        }
        elseif ($tokens -contains $cl -or $q.Contains($cl)) {
            $score += 70
            $reasons.Add("capability '$cap'")
        }
    }

    $tasks = @(Get-CmdPeekCatalogTaskList -Entry $Entry)
    foreach ($task in $tasks) {
        $tl = $task.ToLowerInvariant()
        if ($tl -eq $q) {
            $score += 95
            $reasons.Add('task')
        }
        elseif ($q.Contains($tl) -or $tl.Contains($q)) {
            $score += 80
            $reasons.Add("task '$task'")
        }
        else {
            $overlap = 0
            $taskTokens = @(Get-CmdPeekTaskTokens -Task $task)
            foreach ($tok in $tokens) {
                if ($taskTokens -contains $tok) { $overlap++ }
            }
            if ($overlap -ge 2) {
                $score += 55
                $reasons.Add("task '$task'")
            }
            elseif ($overlap -eq 1 -and $tokens.Count -eq 1) {
                $score += 35
                $reasons.Add("task '$task'")
            }
        }
    }

    $cat = ''
    if ($Entry -and $Entry.PSObject.Properties['category'] -and $Entry.category) {
        $cat = ([string]$Entry.category).ToLowerInvariant()
    }
    if ($cat -and ($cat -eq $q -or $tokens -contains $cat)) {
        $score += 40
        $reasons.Add("category '$cat'")
    }

    $usages = @(Get-CmdPeekCatalogUsageList -Entry $Entry)
    $blob = ($usages -join "`n").ToLowerInvariant()
    if ($blob -and $q.Length -gt 2 -and $blob.Contains($q)) {
        $score += 45
        $reasons.Add('usage text')
    }
    else {
        $hitTok = 0
        foreach ($tok in $tokens) {
            if ($tok.Length -gt 2 -and $blob.Contains($tok)) { $hitTok++ }
        }
        if ($hitTok -ge 2) {
            $score += 30
            $reasons.Add('usage text')
        }
    }

    $reason = ''
    if ($reasons.Count -gt 0) {
        $uniq = @($reasons | Select-Object -Unique)
        $reason = $uniq[0]
    }
    return [pscustomobject]@{ Score = [int]$score; Reason = $reason }
}

function Resolve-CmdPeekTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Task,
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [int]$Limit = 8,
        [string]$PreferredManager
    )

    if (-not $Catalog) { $Catalog = @{} }
    if ($Limit -lt 1) { $Limit = 8 }
    $query = $Task.Trim()
    $installedSet = Get-CmdPeekInstalledNameSet -History $History -Catalog $Catalog
    $historyByName = @{}
    foreach ($row in @($History)) {
        if (-not $row -or -not $row.Command) { continue }
        $k = $row.Command.ToLowerInvariant()
        if (-not $historyByName.ContainsKey($k)) { $historyByName[$k] = $row }
    }

    $installedHits = New-Object System.Collections.Generic.List[object]
    $missingHits = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($key in @($Catalog.Keys)) {
        $lk = $key.ToLowerInvariant()
        if ($seen.ContainsKey($lk)) { continue }
        $seen[$lk] = $true
        $entry = $Catalog[$key]
        $scored = Get-CmdPeekTaskScore -Query $query -Command $key -Entry $entry
        if ($scored.Score -le 0) { continue }

        $usages = @(Get-CmdPeekCatalogUsageList -Entry $entry | Select-Object -First 3)
        $row = $null
        foreach ($name in @(Get-CmdPeekCommandNamesFor -Command $key -Catalog $Catalog)) {
            $nk = $name.ToLowerInvariant()
            if ($historyByName.ContainsKey($nk)) { $row = $historyByName[$nk]; break }
        }
        $covered = Test-CmdPeekNameCovered -Name $key -InstalledSet $installedSet -Catalog $Catalog
        $actuallyInstalled = $null -ne $row
        $item = [pscustomobject]@{
            command          = [string]$key
            score            = [int]$scored.Score
            reason           = [string]$scored.Reason
            category         = $(if ($entry.PSObject.Properties['category'] -and $entry.category) { [string]$entry.category } else { 'other' })
            capabilities     = @(Get-CmdPeekCatalogCapabilityList -Entry $entry)
            usages           = $usages
            usageDetails     = @(ConvertTo-CmdPeekStructuredUsage -Usage $usages)
            packageManager   = $(if ($row -and $row.PSObject.Properties['PackageManager']) { [string]$row.PackageManager } else { $null })
            onPath           = $(if ($row -and $row.PSObject.Properties['OnPath']) { [bool]$row.OnPath } else { $false })
            installed        = [bool]$actuallyInstalled
            installCommands  = @()
        }
        if ($actuallyInstalled) {
            $installedHits.Add($item)
        }
        elseif (-not $covered) {
            $item.installCommands = @(Get-CmdPeekInstallCommands -Command $key -Catalog $Catalog -PreferredManager $PreferredManager)
            $missingHits.Add($item)
        }
    }

    $installedSorted = @($installedHits.ToArray() | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = { $_.command.ToLowerInvariant() } } | Select-Object -First $Limit)
    $missingSorted = @($missingHits.ToArray() | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = { $_.command.ToLowerInvariant() } } | Select-Object -First $Limit)

    return [pscustomobject]@{
        query     = $query
        installed = @($installedSorted)
        missing   = @($missingSorted)
    }
}

function Get-CmdPeekWhyCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [scriptblock]$CommandTester,
        [string]$PreferredManager
    )

    if (-not $Catalog) { $Catalog = @{} }
    $canonical = Get-CmdPeekCanonicalCommand -Command $Command -Catalog $Catalog
    $entry = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    $installedSet = Get-CmdPeekInstalledNameSet -History $History -Catalog $Catalog
    $installed = Test-CmdPeekNameCovered -Name $Command -InstalledSet $installedSet -Catalog $Catalog
    $matches = @(
        @($History) | Where-Object {
            $_ -and $_.Command -and (
                $_.Command.ToLowerInvariant() -eq $Command.ToLowerInvariant() -or
                $_.Command.ToLowerInvariant() -eq $canonical.ToLowerInvariant()
            )
        }
    )
    $onPathManager = $null
    $onPath = $false
    if ($CommandTester -and $Command) {
        try { $onPath = [bool](& $CommandTester $Command) } catch { $onPath = $false }
    }
    if ($matches.Count -gt 0) {
        foreach ($row in $matches) {
            $name = [string]$row.Command
            $ok = $false
            if ($CommandTester) {
                try { $ok = [bool](& $CommandTester $name) } catch { $ok = $false }
            }
            elseif ($row.PSObject.Properties['OnPath']) {
                $ok = [bool]$row.OnPath
            }
            if ($ok) {
                $onPath = $true
                $onPathManager = [string]$row.PackageManager
                break
            }
        }
        if (-not $onPathManager) {
            $onPathManager = [string]$matches[0].PackageManager
        }
    }

    $subsInstalled = New-Object System.Collections.Generic.List[string]
    $subsMissing = New-Object System.Collections.Generic.List[string]
    foreach ($sub in @(Get-CmdPeekCatalogSubstituteList -Entry $entry)) {
        if (Test-CmdPeekNameCovered -Name $sub -InstalledSet $installedSet -Catalog $Catalog) {
            $subsInstalled.Add($sub)
        }
        else {
            $subsMissing.Add($sub)
        }
    }

    return [pscustomobject]@{
        command         = $(if ($canonical) { $canonical } else { $Command })
        queried         = $Command
        installed       = [bool]$installed
        onPath          = [bool]$onPath
        onPathManager   = $onPathManager
        packageManagers = @($matches | ForEach-Object { [string]$_.PackageManager } | Select-Object -Unique)
        category        = $(if ($entry -and $entry.PSObject.Properties['category']) { [string]$entry.category } else { 'other' })
        capabilities    = @(Get-CmdPeekCatalogCapabilityList -Entry $entry)
        aliases         = @(Get-CmdPeekCatalogAliasList -Entry $entry)
        substitutesInstalled = @($subsInstalled)
        substitutesMissing   = @($subsMissing)
        usages          = @(Get-CmdPeekCatalogUsageList -Entry $entry | Select-Object -First 5)
        installCommands = @(Get-CmdPeekInstallCommands -Command $(if ($canonical) { $canonical } else { $Command }) -Catalog $Catalog -PreferredManager $PreferredManager)
        rows            = @($matches)
    }
}

function Get-CmdPeekHaveList {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [string]$Capability,
        [string]$Category
    )

    if (-not $Catalog) { $Catalog = @{} }
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($row in @($History)) {
        if (-not $row -or -not $row.Command) { continue }
        $key = $row.Command.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $entry = Get-CmdPeekCatalogEntry -Command $row.Command -Catalog $Catalog
        $caps = @(Get-CmdPeekCatalogCapabilityList -Entry $entry)
        $cat = 'other'
        if ($row.PSObject.Properties['Category'] -and $row.Category) { $cat = [string]$row.Category }
        elseif ($entry -and $entry.PSObject.Properties['category'] -and $entry.category) { $cat = [string]$entry.category }
        if ($Capability) {
            $want = $Capability.ToLowerInvariant()
            $ok = $false
            foreach ($c in $caps) { if ($c.ToLowerInvariant() -eq $want) { $ok = $true; break } }
            if (-not $ok) { continue }
        }
        if ($Category) {
            if ($cat.ToLowerInvariant() -ne $Category.ToLowerInvariant()) { continue }
        }
        $usages = @()
        if ($row.PSObject.Properties['Usages'] -and $row.Usages) {
            $usages = @($row.Usages | Select-Object -First 3)
        }
        else {
            $usages = @(Get-CmdPeekCatalogUsageList -Entry $entry | Select-Object -First 3)
        }
        $rows.Add([pscustomobject]@{
            Command        = [string]$row.Command
            PackageManager = [string]$row.PackageManager
            Category       = $cat
            Capabilities   = $caps
            Usages         = $usages
            OnPath         = $(if ($row.PSObject.Properties['OnPath']) { [bool]$row.OnPath } else { $true })
        })
    }
    return @($rows.ToArray() | Sort-Object @{ Expression = { $_.Category.ToLowerInvariant() } }, @{ Expression = { $_.Command.ToLowerInvariant() } })
}

function Search-CmdPeekAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [string]$PreferredManager,
        [scriptblock]$PackageSearchRunner,
        [int]$Limit = 15
    )

    if (-not $Catalog) { $Catalog = @{} }
    $installedSet = Get-CmdPeekInstalledNameSet -History $History -Catalog $Catalog
    $resolved = Resolve-CmdPeekTask -Task $Query -History $History -Catalog $Catalog -Limit $Limit -PreferredManager $PreferredManager
    $catalogHits = @($resolved.missing)

    $pmHits = New-Object System.Collections.Generic.List[object]
    if ($PackageSearchRunner) {
        try {
            $raw = @(& $PackageSearchRunner $Query)
            foreach ($item in $raw) {
                if (-not $item) { continue }
                if ($item -is [string]) {
                    $pmHits.Add([pscustomobject]@{ name = $item; manager = 'unknown'; source = 'package-manager' })
                }
                else {
                    $pmHits.Add($item)
                }
            }
        }
        catch { }
    }

    $pmArr = @($pmHits.ToArray())
    $missingArr = @($catalogHits)
    $installedArr = @($resolved.installed)

    $out = [pscustomobject]@{ query = [string]$Query }
    Add-Member -InputObject $out -NotePropertyName catalogMissing -NotePropertyValue $missingArr
    Add-Member -InputObject $out -NotePropertyName catalogInstalled -NotePropertyValue $installedArr
    Add-Member -InputObject $out -NotePropertyName packageManagers -NotePropertyValue $pmArr
    return $out
}
