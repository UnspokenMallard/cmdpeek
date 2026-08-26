#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CmdPeekGap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [hashtable]$Kits
    )

    if (-not $Catalog) { $Catalog = @{} }
    if (-not $Kits) { $Kits = @{} }

    $installed = @{}
    foreach ($row in @($History)) {
        if ($row -and $row.Command) {
            $lk = $row.Command.ToLowerInvariant()
            if (-not $installed.ContainsKey($lk)) {
                $installed[$lk] = $row
            }
        }
    }
    $installedSet = Get-CmdPeekInstalledNameSet -History $History -Catalog $Catalog

    $relatedMap = @{}
    foreach ($row in @($History)) {
        if (-not $row) { continue }
        $names = New-Object System.Collections.Generic.List[string]
        if ($row.PSObject.Properties['Related'] -and $row.Related) {
            foreach ($rel in @($row.Related)) {
                if ($rel) { $names.Add([string]$rel) }
            }
        }
        $entry = Get-CmdPeekCatalogEntry -Command $row.Command -Catalog $Catalog
        if ($entry -and $entry.PSObject.Properties['related'] -and $entry.related) {
            foreach ($rel in @($entry.related)) {
                if ($rel) { $names.Add([string]$rel) }
            }
        }

        foreach ($name in $names) {
            $key = $name.ToLowerInvariant()
            if (Test-CmdPeekNameCovered -Name $name -InstalledSet $installedSet -Catalog $Catalog) { continue }
            if (-not $relatedMap.ContainsKey($key)) {
                $category = 'other'
                $catEntry = Get-CmdPeekCatalogEntry -Command $name -Catalog $Catalog
                if ($catEntry -and $catEntry.PSObject.Properties['category'] -and $catEntry.category) {
                    $category = [string]$catEntry.category
                }
                $relatedMap[$key] = [pscustomobject]@{
                    Name      = $name
                    RelatedTo = New-Object System.Collections.Generic.List[string]
                    Category  = $category
                }
            }
            if ($relatedMap[$key].RelatedTo -notcontains $row.Command) {
                $relatedMap[$key].RelatedTo.Add($row.Command)
            }
        }
    }

    $gaps = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($relatedMap.Keys)) {
        $hit = $relatedMap[$key]
        $relatedTo = @($hit.RelatedTo)
        $who = $relatedTo -join ', '
        $verb = $(if ($relatedTo.Count -eq 1) { 'is' } else { 'are' })
        $gaps.Add([pscustomobject]@{
            kind      = 'missing-related'
            command   = $hit.Name
            reason    = "Suggested because $who $verb installed"
            relatedTo = $relatedTo
            category  = $hit.Category
        })
    }

    foreach ($row in @($History)) {
        if (-not $row) { continue }
        $usages = @()
        if ($row.PSObject.Properties['Usages'] -and $row.Usages) { $usages = @($row.Usages) }
        $curated = @($usages | Where-Object { $_ -and $_ -notmatch '--help' })
        if ($curated.Count -eq 0) {
            $gaps.Add([pscustomobject]@{
                kind      = 'thin-docs'
                command   = [string]$row.Command
                reason    = 'No curated usage examples; only generic --help'
                relatedTo = @()
                category  = $(if ($row.PSObject.Properties['Category'] -and $row.Category) { [string]$row.Category } else { 'other' })
            })
        }
    }

    foreach ($row in @($History)) {
        if (-not $row) { continue }
        if (-not ($row.PSObject.Properties['OnPath'] -and -not $row.OnPath)) { continue }
        $gaps.Add([pscustomobject]@{
            kind           = 'not-on-path'
            command        = [string]$row.Command
            reason         = ('Installed via {0} but not on PATH' -f $(if ($row.PackageManager) { $row.PackageManager } else { 'a package manager' }))
            relatedTo      = @()
            category       = $(if ($row.PSObject.Properties['Category'] -and $row.Category) { [string]$row.Category } else { 'other' })
            packageName    = $(if ($row.PSObject.Properties['PackageName']) { [string]$row.PackageName } else { [string]$row.Command })
            packageManager = [string]$row.PackageManager
        })
    }

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
        $rows = @($byName[$key].ToArray())
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
        $onPathManager = $null
        foreach ($row in $rows) {
            if ($row.PSObject.Properties['OnPath'] -and $row.OnPath) {
                $onPathManager = [string]$row.PackageManager
                break
            }
        }
        $reason = 'Installed from more than one package manager'
        if ($onPathManager) {
            $reason = ('Installed from more than one package manager; PATH resolves {0}' -f $onPathManager)
        }
        $gaps.Add([pscustomobject]@{
            kind            = 'shadowing'
            command         = [string]$first.Command
            reason          = $reason
            relatedTo       = @()
            category        = $cat
            packageManagers = @($sortedPm)
            onPathManager   = $onPathManager
        })
    }

    $missingRelatedNames = @{}
    foreach ($g in @($gaps.ToArray())) {
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
            if ($member -and (Test-CmdPeekNameCovered -Name $member -InstalledSet $installedSet -Catalog $Catalog)) {
                $anyInstalled = $true
                break
            }
        }
        if (-not $anyInstalled) { continue }

        foreach ($member in $members) {
            if (-not $member) { continue }
            $lk = ([string]$member).ToLowerInvariant()
            if (Test-CmdPeekNameCovered -Name $member -InstalledSet $installedSet -Catalog $Catalog) { continue }
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
            $installCmds = @()
            if (Get-Command Get-CmdPeekInstallCommands -ErrorAction SilentlyContinue) {
                $installCmds = @(Get-CmdPeekInstallCommands -Command $commandName -Catalog $Catalog)
            }
            $kitGaps.Add([pscustomobject]@{
                kind             = 'kit'
                command          = $commandName
                reason           = "Incomplete kit '$kitId'"
                relatedTo        = @($kitId)
                category         = $cat
                installCommands  = $installCmds
            })
        }
    }

    $kitArr = @($kitGaps.ToArray())
    if ($kitArr.Count -gt 1) {
        $kitArr = @($kitArr | Sort-Object { $_.command.ToLowerInvariant() })
    }
    foreach ($g in $kitArr) { $gaps.Add($g) }

    $covered = @{}
    foreach ($g in @($gaps.ToArray())) {
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
        if (Test-CmdPeekNameCovered -Name $ck -InstalledSet $installedSet -Catalog $Catalog) {
            $shown = $ck
            if ($installed.ContainsKey($lk)) { $shown = [string]$installed[$lk].Command }
            $byCatInstalled[$cat].Add($shown)
        }
        else {
            $byCatMissing[$cat].Add([string]$ck)
        }
    }

    $neighborList = New-Object System.Collections.Generic.List[object]
    foreach ($cat in @($byCatInstalled.Keys)) {
        $installedHere = @($byCatInstalled[$cat].ToArray())
        if ($installedHere.Count -eq 0) { continue }
        $relatedTo = @($installedHere | Sort-Object { $_.ToLowerInvariant() } | Select-Object -First 3)
        $cands = @($byCatMissing[$cat].ToArray() | Sort-Object { $_.ToLowerInvariant() })
        $kept = 0
        foreach ($name in $cands) {
            $lk = $name.ToLowerInvariant()
            if ($covered.ContainsKey($lk)) { continue }
            if (Test-CmdPeekNameCovered -Name $name -InstalledSet $installedSet -Catalog $Catalog) { continue }
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

    $neighborArr = @($neighborList.ToArray())
    if ($neighborArr.Count -gt 1) {
        $neighborArr = @($neighborArr | Sort-Object { $_.command.ToLowerInvariant() })
    }
    foreach ($g in $neighborArr) { $gaps.Add($g) }

    return @($gaps.ToArray())
}

function ConvertTo-CmdPeekSnapshot {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$History,
        [AllowEmptyCollection()]
        [object[]]$Manager,
        [hashtable]$Catalog,
        [string[]]$Favorite,
        [string[]]$Hidden,
        [scriptblock]$CommandTester,
        [hashtable]$Kits,
        [string[]]$HistoryPath,
        [int]$RecentLines = 0
    )

    if (-not $Catalog) { $Catalog = @{} }

    $history = @(
        foreach ($row in @($History)) {
            if (-not $row) { continue }
            $onPath = Test-CmdPeekOnPath -Command $row.Command -CommandTester $CommandTester
            $row | Add-Member -NotePropertyName OnPath -NotePropertyValue $onPath -Force
            $row
        }
    )
    $kitMap = $Kits
    if (-not $PSBoundParameters.ContainsKey('Kits')) {
        $kitMap = Get-CmdPeekCatalogKits
    }
    if (-not $kitMap) { $kitMap = @{} }
    $gaps = @(Get-CmdPeekGap -History $history -Catalog $Catalog -Kits $kitMap)

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

    $commands = @(
        foreach ($row in @($history)) {
            if (-not $row) { continue }
            $install = $null
            if ($row.PSObject.Properties['InstallDate'] -and $row.InstallDate) {
                try { $install = ([datetime]$row.InstallDate).ToString('o') } catch { $install = [string]$row.InstallDate }
            }
            $usages = $(if ($row.PSObject.Properties['Usages'] -and $row.Usages) { @($row.Usages) } else { @() })
            $entry = Get-CmdPeekCatalogEntry -Command $row.Command -Catalog $Catalog
            [pscustomobject]@{
                command        = [string]$row.Command
                packageName    = $(if ($row.PSObject.Properties['PackageName']) { [string]$row.PackageName } else { [string]$row.Command })
                packageManager = [string]$row.PackageManager
                installDate    = $install
                version        = $(if ($row.PSObject.Properties['Version']) { $row.Version } else { $null })
                category       = $(if ($row.PSObject.Properties['Category']) { [string]$row.Category } else { 'other' })
                capabilities   = @(Get-CmdPeekCatalogCapabilityList -Entry $entry)
                aliases        = @(Get-CmdPeekCatalogAliasList -Entry $entry)
                substitutes    = @(Get-CmdPeekCatalogSubstituteList -Entry $entry)
                usages         = $usages
                usageDetails   = @(ConvertTo-CmdPeekStructuredUsage -Usage $usages)
                related        = $(if ($row.PSObject.Properties['Related'] -and $row.Related) { @($row.Related) } else { @() })
                favorite       = [bool]$(if ($row.PSObject.Properties['Favorite']) { $row.Favorite } else { $false })
                hidden         = [bool]$(if ($row.PSObject.Properties['Hidden']) { $row.Hidden } else { $false })
                onPath         = [bool]$row.OnPath
            }
        }
    )

    $managers = @(
        foreach ($pm in @($Manager)) {
            if (-not $pm) { continue }
            [pscustomobject]@{
                name        = [string]$pm.Name
                command     = [string]$pm.Command
                present     = [bool]$pm.Present
                installHint = $(if ($pm.PSObject.Properties['InstallHint']) { [string]$pm.InstallHint } else { '' })
            }
        }
    )

    return [pscustomobject]@{
        generatedAt = (Get-Date).ToString('o')
        managers    = $managers
        commands    = $commands
        catalog     = @(Get-CmdPeekCatalogIndex -Catalog $Catalog)
        favorites   = @($Favorite | Where-Object { $_ })
        hidden      = @($Hidden | Where-Object { $_ })
        gaps        = $gaps
        rusty       = $rusty
    }
}

function Get-CmdPeekInventory {
    [CmdletBinding()]
    param(
        [string]$DataDirectory,
        [string]$ChocolateyRoot,
        [string]$ScoopRoot,
        [string]$WinGetRoot,
        [string]$ExamplesPath,
        [string[]]$EnabledManagers,
        [scriptblock]$CommandTester,
        [string]$Search,
        [string]$Category,
        [string[]]$HistoryPath,
        [int]$RecentLines = 0
    )

    $managerNames = @()
    if ($PSBoundParameters.ContainsKey('EnabledManagers')) {
        $managerNames = @($EnabledManagers)
    }
    else {
        $detected = @(Get-CmdPeekPackageManager -CommandTester $CommandTester)
        $managerNames = @($detected | Select-Object -ExpandProperty Name)
    }

    $managers = @(Get-CmdPeekPackageManager -CommandTester $CommandTester -All)
    if ($managerNames.Count -gt 0) {
        $managers = @($managers | Where-Object { $managerNames -contains $_.Name })
    }

    $packages = @(Get-CmdPeekInstalledPackage `
            -ChocolateyRoot $ChocolateyRoot `
            -ScoopRoot $ScoopRoot `
            -WinGetRoot $WinGetRoot `
            -EnabledManagers $managerNames `
            -CommandTester $CommandTester)

    $history = @(Get-CmdPeekCommandHistory -Package $packages)
    $catalog = Get-CmdPeekExampleCatalog -Path $ExamplesPath
    $history = @(Add-CmdPeekCatalogMetadata -History $history -Catalog $catalog -DataDirectory $DataDirectory)

    $state = Get-CmdPeekState -DataDirectory $DataDirectory
    $history = @(Merge-CmdPeekFavorite -History $history -Favorite @($state.Favorites))
    $history = @(Merge-CmdPeekHidden -History $history -Hidden @($state.Hidden))

    if ($Search -or $Category) {
        $history = @(Search-CmdPeekCommand -History $history -Query $Search -Category $Category)
    }

    $snapArgs = @{
        History       = $history
        Manager       = @(Get-CmdPeekPackageManager -CommandTester $CommandTester -All)
        Catalog       = $catalog
        Favorite      = @($state.Favorites)
        Hidden        = @($state.Hidden)
        CommandTester = $CommandTester
        RecentLines   = $RecentLines
    }
    if ($PSBoundParameters.ContainsKey('HistoryPath')) {
        $snapArgs.HistoryPath = $HistoryPath
    }
    $snapshot = ConvertTo-CmdPeekSnapshot @snapArgs

    return [pscustomobject]@{
        History  = $history
        Managers = @(Get-CmdPeekPackageManager -CommandTester $CommandTester -All)
        State    = $state
        Catalog  = $catalog
        Snapshot = $snapshot
        Gaps     = @($snapshot.gaps)
    }
}
