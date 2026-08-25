#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CmdPeekGap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog
    )

    if (-not $Catalog) { $Catalog = @{} }

    $installed = @{}
    foreach ($row in @($History)) {
        if ($row -and $row.Command) {
            $installed[$row.Command.ToLowerInvariant()] = $row
        }
    }

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
            if ($installed.ContainsKey($key)) { continue }
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
        $gaps.Add([pscustomobject]@{
            kind            = 'shadowing'
            command         = [string]$first.Command
            reason          = 'Installed from more than one package manager'
            relatedTo       = @()
            category        = $cat
            packageManagers = @($sortedPm)
        })
    }

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
        [scriptblock]$CommandTester
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
    $gaps = @(Get-CmdPeekGap -History $history -Catalog $Catalog)

    $commands = @(
        foreach ($row in @($history)) {
            if (-not $row) { continue }
            $install = $null
            if ($row.PSObject.Properties['InstallDate'] -and $row.InstallDate) {
                try { $install = ([datetime]$row.InstallDate).ToString('o') } catch { $install = [string]$row.InstallDate }
            }
            [pscustomobject]@{
                command        = [string]$row.Command
                packageName    = $(if ($row.PSObject.Properties['PackageName']) { [string]$row.PackageName } else { [string]$row.Command })
                packageManager = [string]$row.PackageManager
                installDate    = $install
                version        = $(if ($row.PSObject.Properties['Version']) { $row.Version } else { $null })
                category       = $(if ($row.PSObject.Properties['Category']) { [string]$row.Category } else { 'other' })
                usages         = $(if ($row.PSObject.Properties['Usages'] -and $row.Usages) { @($row.Usages) } else { @() })
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
        favorites   = @($Favorite | Where-Object { $_ })
        hidden      = @($Hidden | Where-Object { $_ })
        gaps        = $gaps
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
        [string]$Category
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

    $snapshot = ConvertTo-CmdPeekSnapshot -History $history -Manager @(Get-CmdPeekPackageManager -CommandTester $CommandTester -All) -Catalog $catalog -Favorite @($state.Favorites) -Hidden @($state.Hidden) -CommandTester $CommandTester

    return [pscustomobject]@{
        History  = $history
        Managers = @(Get-CmdPeekPackageManager -CommandTester $CommandTester -All)
        State    = $state
        Catalog  = $catalog
        Snapshot = $snapshot
        Gaps     = @($snapshot.gaps)
    }
}
