#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:CmdPeekModuleRoot = $PSScriptRoot

. (Join-Path $PSScriptRoot 'Config.ps1')
. (Join-Path $PSScriptRoot 'PackageManager.ps1')
. (Join-Path $PSScriptRoot 'CommandHistory.ps1')
. (Join-Path $PSScriptRoot 'CommandUse.ps1')
. (Join-Path $PSScriptRoot 'Catalog.ps1')
. (Join-Path $PSScriptRoot 'UsageExamples.ps1')
. (Join-Path $PSScriptRoot 'ExtraSources.ps1')
. (Join-Path $PSScriptRoot 'TaskResolve.ps1')
. (Join-Path $PSScriptRoot 'InteractiveMode.ps1')
. (Join-Path $PSScriptRoot 'Inventory.ps1')
. (Join-Path $PSScriptRoot 'Tui.ps1')

function Invoke-CmdPeek {
    [CmdletBinding()]
    param(
        [int]$Count,
        [switch]$Interactive,
        [string]$Search,
        [string]$Category,
        [switch]$NonInteractive,
        [string]$Reinstall,
        [ValidateSet('chocolatey', 'scoop', 'winget', 'pipx', 'npm', 'cargo', 'brew', 'apt', 'pacman')]
        [string]$Manager,
        [string]$Export,
        [string]$Import,
        [string]$DataDirectory,
        [string]$ChocolateyRoot,
        [string]$ScoopRoot,
        [string]$WinGetRoot,
        [string]$ExamplesPath,
        [string[]]$EnabledManagers,
        [scriptblock]$CommandTester,
        [scriptblock]$HelpRunner,
        [switch]$Json,
        [switch]$Gaps,
        [string]$Since,
        [switch]$Recent,
        [switch]$Rusty,
        [string[]]$HistoryPath,
        [int]$RecentLines = 0,
        [string]$Hide,
        [string]$Unhide,
        [string]$Star,
        [string]$Unstar,
        [string]$Task,
        [string]$Why,
        [string]$Explain,
        [string]$SearchAvailable,
        [switch]$Have,
        [string]$Capability,
        [switch]$Refresh,
        [switch]$HumanGaps,
        [switch]$LastInstall,
        [scriptblock]$PackageSearchRunner,
        [string]$PipxRoot,
        [string]$NpmRoot,
        [string]$CargoRoot,
        [string]$BrewRoot,
        [string]$AptStatusPath,
        [string]$PacmanRoot,
        [string]$LastUsedPath,
        [scriptblock]$OpenAiRunner,
        [switch]$AgentExport,
        [string]$AgentExportPath,
        [string]$Compare,
        [string]$Suggest,
        [string[]]$BinRoot,
        [string[]]$GapKind,
        [int]$GapLimit = -1,
        [int]$TaskLimit = 0,
        [int]$ProbeLimit = -1
    )

    if ($ProbeLimit -lt 0) { $ProbeLimit = 25 }

    if ($Recent) {
        $Json = $true
        $NonInteractive = $true
    }
    if ($Json -or $Gaps -or $HumanGaps) {
        $NonInteractive = $true
    }
    if ($Task -or $Why -or $Explain -or $SearchAvailable -or $Have -or $AgentExport -or $Compare -or $Suggest) {
        $NonInteractive = $true
    }
    if ($LastInstall) {
        $NonInteractive = $true
    }
    if ($Rusty -and -not $Interactive) {
        $NonInteractive = $true
    }

    $useInteractive = [bool]$Interactive -or ($Count -le 0 -and -not $Search -and -not $Category)
    if ($NonInteractive) { $useInteractive = $false }
    if ($Rusty -and -not $Interactive) { $useInteractive = $false }
    if ($Task -or $Why -or $Explain -or $SearchAvailable -or $Have -or $HumanGaps -or $AgentExport -or $Compare -or $Suggest) { $useInteractive = $false }

    # Grouped recency: -Recent, or quick view with -n / default NonInteractive peek.
    # -Search/-Category without -Count stay flat and must not use this path.
    $isRecencyPath = [bool]$Recent -or (
        -not $useInteractive -and -not $Json -and -not $Gaps -and -not $Rusty -and -not $Task -and -not $Why -and -not $Explain -and -not $SearchAvailable -and -not $Have -and -not $HumanGaps -and -not $AgentExport -and -not $Compare -and -not $Suggest -and (
            $Count -gt 0 -or (-not $Search -and -not $Category)
        )
    )

    # Validate -Since before scan/save so bogus values never advance LastPeekAt
    if ($isRecencyPath) {
        $sinceCheck = $Since
        if ([string]::IsNullOrWhiteSpace($sinceCheck)) { $sinceCheck = 'last' }
        $null = Convert-CmdPeekSince -Since $sinceCheck -Cursor $null
    }

    if ($Import) {
        Import-CmdPeekState -Path $Import -DataDirectory $DataDirectory
        Write-Host "Imported state from $Import"
        return
    }

    if ($Export -and -not $Interactive) {
        Export-CmdPeekState -Path $Export -DataDirectory $DataDirectory
        Write-Host "Exported state to $Export"
        return
    }

    if ($LastInstall) {
        $last = Get-CmdPeekLastInstall -DataDirectory $DataDirectory
        if (-not $last) {
            Write-Output (@{ generatedAt = $null; commands = @() } | ConvertTo-Json -Depth 6)
        }
        else {
            Write-Output ($last | ConvertTo-Json -Depth 8)
        }
        return
    }

    if ($Hide -or $Unhide -or $Star -or $Unstar) {
        $state = Get-CmdPeekState -DataDirectory $DataDirectory
        if ($Hide) {
            $state = Set-CmdPeekHidden -State $state -Command $Hide -Hidden $true
        }
        if ($Unhide) {
            $state = Set-CmdPeekHidden -State $state -Command $Unhide -Hidden $false
        }
        if ($Star) {
            $state = Set-CmdPeekFavorite -State $state -Command $Star -Favorite $true
        }
        if ($Unstar) {
            $state = Set-CmdPeekFavorite -State $state -Command $Unstar -Favorite $false
        }
        Save-CmdPeekState -State $state -DataDirectory $DataDirectory
        return
    }

    # Only the unfiltered inventory is cacheable. A -Search/-Category/-Count run produces a
    # subset, and writing that to the cache would hand the next caller a partial machine.
    $fullInventoryJson = $Json -and -not $Gaps -and -not $HumanGaps -and -not $Search -and -not $Category

    # Served before the scan, not after: the package managers and bin directories are the
    # expensive part, so a cache checked further down would save nothing.
    if ($fullInventoryJson -and -not $Refresh) {
        $cachedState = Get-CmdPeekState -DataDirectory $DataDirectory
        $cached = Get-CmdPeekInventoryCache -DataDirectory $DataDirectory -State $cachedState
        if ($cached) {
            if ($Count -gt 0 -and $cached.PSObject.Properties['commands']) {
                $cached.commands = @(@($cached.commands) | Select-Object -First $Count)
            }
            $cached | Add-Member lastPeekAt $cachedState.LastPeekAt -Force
            $cached | Add-Member lastMcpAt $cachedState.LastMcpAt -Force
            Write-Output ($cached | ConvertTo-Json -Depth 10)
            return
        }
    }

    $managerNames = @()
    if ($PSBoundParameters.ContainsKey('EnabledManagers')) {
        $managerNames = @($EnabledManagers)
    }
    else {
        $detected = @(Get-CmdPeekPackageManager -CommandTester $CommandTester)
        if ($detected.Count -eq 0) {
            Show-CmdPeekNoManagerPrompt -NonInteractive:$NonInteractive
            $detected = @(Get-CmdPeekPackageManager -CommandTester $CommandTester)
        }
        $managerNames = @($detected | Select-Object -ExpandProperty Name)
    }

    $managers = @(Get-CmdPeekPackageManager -CommandTester $CommandTester -All | Where-Object { $managerNames -contains $_.Name })
    if ($managers.Count -eq 0) {
        $managers = @(
            $managerNames | ForEach-Object {
                [pscustomobject]@{ Name = $_; Command = $_; Present = $true; InstallHint = '' }
            }
        )
    }

    if ($Reinstall) {
        $pm = $Manager
        if (-not $pm) {
            $statePref = (Get-CmdPeekState -DataDirectory $DataDirectory).PreferredPackageManager
            if ($statePref) { $pm = $statePref }
            elseif ($managers.Count -gt 0) { $pm = $managers[0].Name }
            else { $pm = 'scoop' }
        }
        [void](Install-CmdPeekTrackedPackage -PackageName $Reinstall -PackageManager $pm)
        $prefState = Get-CmdPeekState -DataDirectory $DataDirectory
        $prefState = Set-CmdPeekPreferredPackageManager -State $prefState -PackageManager $pm
        Save-CmdPeekState -State $prefState -DataDirectory $DataDirectory
        return
    }

    $packages = @(Get-CmdPeekInstalledPackage `
            -ChocolateyRoot $ChocolateyRoot `
            -ScoopRoot $ScoopRoot `
            -WinGetRoot $WinGetRoot `
            -PipxRoot $PipxRoot `
            -NpmRoot $NpmRoot `
            -CargoRoot $CargoRoot `
            -BrewRoot $BrewRoot `
            -AptStatusPath $AptStatusPath `
            -PacmanRoot $PacmanRoot `
            -EnabledManagers $managerNames `
            -CommandTester $CommandTester)

    $history = @(Get-CmdPeekCommandHistory -Package $packages)
    $catalog = Get-CmdPeekExampleCatalog -Path $ExamplesPath -DataDirectory $DataDirectory
    $includePath = -not $PSBoundParameters.ContainsKey('EnabledManagers') -or (@($managerNames) -contains 'path')
    if ($includePath) {
        $pathArgs = @{
            History       = $history
            Catalog       = $catalog
            CommandTester = $CommandTester
            DataDirectory = $DataDirectory
        }
        if ($PSBoundParameters.ContainsKey('BinRoot')) {
            $pathArgs.BinRoot = $BinRoot
        }
        else {
            $pathArgs.IncludeSystemDirectories = $true
        }
        $history = @(Add-CmdPeekPathCommands @pathArgs)
    }
    $history = @(Add-CmdPeekCatalogMetadata -History $history -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner -SkipHelpProbe)

    $state = Get-CmdPeekState -DataDirectory $DataDirectory
    $history = @(Merge-CmdPeekFavorite -History $history -Favorite @($state.Favorites))
    $history = @(Merge-CmdPeekHidden -History $history -Hidden @($state.Hidden))

    $missing = @(Find-CmdPeekMissingCommand -Previous @($state.Commands) -Current $history)
    $missing = @(
        $missing | Where-Object {
            if (-not $_) { return $false }
            $pm = ''
            if ($_.PSObject.Properties['PackageManager'] -and $_.PackageManager) {
                $pm = ([string]$_.PackageManager).ToLowerInvariant()
            }
            return ($pm -notin @('builtin', 'path'))
        }
    )
    if ($missing.Count -gt 0) {
        if ($useInteractive) {
            $state = Confirm-CmdPeekMissingCommand -Missing $missing -Managers $managers -State $state
        }
        elseif ($NonInteractive) {
            $state = Confirm-CmdPeekMissingCommand -Missing $missing -Managers $managers -State $state -NonInteractive
        }
    }

    $state.Commands = @(
        $history | Select-Object Command, PackageName, PackageManager, InstallDate, Version
    )
    $state.LastScan = (Get-Date).ToString('o')
    Save-CmdPeekState -State $state -DataDirectory $DataDirectory

    $preferred = $state.PreferredPackageManager

    if ($Task) {
        $taskArgs = @{
            Task             = $Task
            History          = $history
            Catalog          = $catalog
            PreferredManager = $preferred
        }
        if ($TaskLimit -gt 0) { $taskArgs.Limit = $TaskLimit }
        $resolved = Resolve-CmdPeekTask @taskArgs
        if ($Json) {
            Write-Output ($resolved | ConvertTo-Json -Depth 8)
        }
        else {
            Write-Output (Format-CmdPeekTaskOutput -Result $resolved)
        }
        return
    }

    if ($Why) {
        $whyRow = Get-CmdPeekWhyCommand -Command $Why -History $history -Catalog $catalog -CommandTester $CommandTester -PreferredManager $preferred
        if ($Json) {
            Write-Output ($whyRow | ConvertTo-Json -Depth 8)
        }
        else {
            Write-Output (Format-CmdPeekWhyOutput -Result $whyRow)
        }
        return
    }

    if ($Compare) {
        $bits = @($Compare.Trim() -split '\s+', 3)
        $left = $bits[0]
        $right = $(if ($bits.Count -gt 1) { $bits[1] } else { '' })
        if (-not $left -or -not $right) {
            Write-Output "Usage: cmdpeek compare <command> <command>`n"
            return
        }
        $cmp = Compare-CmdPeekCommand -Left $left -Right $right -History $history -Catalog $catalog -CommandTester $CommandTester
        if ($Json) {
            Write-Output ($cmp | ConvertTo-Json -Depth 8)
        }
        else {
            Write-Output (Format-CmdPeekCompareOutput -Result $cmp)
        }
        return
    }

    if ($Suggest) {
        $sug = Get-CmdPeekArgvSuggestion -Argv $Suggest -History $history -Catalog $catalog -CommandTester $CommandTester -PreferredManager $preferred
        if ($Json) {
            Write-Output ($sug | ConvertTo-Json -Depth 8)
        }
        else {
            Write-Output (Format-CmdPeekSuggestOutput -Result $sug)
        }
        return
    }

    if ($SearchAvailable) {
        $avail = Search-CmdPeekAvailable -Query $SearchAvailable -History $history -Catalog $catalog -PreferredManager $preferred -PackageSearchRunner $PackageSearchRunner
        if ($Json) {
            Write-Output ($avail | ConvertTo-Json -Depth 8)
        }
        else {
            Write-Output (Format-CmdPeekAvailableOutput -Result $avail)
        }
        return
    }

    if ($Have) {
        $haveRows = @(Get-CmdPeekHaveList -History $history -Catalog $catalog -Capability $Capability -Category $Category)
        if ($Json) {
            Write-Output ([pscustomobject]@{ commands = $haveRows } | ConvertTo-Json -Depth 8)
        }
        else {
            Write-Output (Format-CmdPeekHaveOutput -History $haveRows)
        }
        return
    }

    if ($AgentExport) {
        $markdown = Format-CmdPeekAgentExport -History $history -Catalog $catalog -Favorite @($state.Favorites)
        if ($AgentExportPath) {
            $parent = Split-Path -Parent $AgentExportPath
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Set-Content -LiteralPath $AgentExportPath -Value $markdown -Encoding UTF8
            Write-Output ('Wrote {0}' -f $AgentExportPath)
            return
        }
        Write-Output $markdown
        return
    }

    if ($Explain) {
        $card = Get-CmdPeekCommandCard -Command $Explain -History $history -Catalog $catalog -CommandTester $CommandTester -PreferredManager $preferred
        $exact = @(Select-CmdPeekExactCommand -History $history -Query $Explain)
        if ($exact.Count -eq 1) {
            $probed = @(Add-CmdPeekUsageProbe -History @($exact[0]) -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner -OpenAiRunner $OpenAiRunner -Limit 0)
            if ($probed.Count -gt 0 -and $probed[0].PSObject.Properties['Usages']) {
                $card.usages = @($probed[0].Usages)
                $card.usageDetails = @(ConvertTo-CmdPeekStructuredUsage -Usage @($probed[0].Usages))
            }
        }
        if ($Json) {
            Write-Output ($card | ConvertTo-Json -Depth 8)
        }
        else {
            Write-Output (Format-CmdPeekWhyOutput -Result $card)
        }
        return
    }

    # Category/Search on flat inventory only. Recency paths group first, then filter rows.
    # Human exact-search skips early substring so hidden rows stay eligible for Select-CmdPeekExactCommand.
    $searchPathExact = [bool]$Search -and -not $isRecencyPath -and -not $Json -and -not $Gaps -and -not $useInteractive

    if (($Search -or $Category) -and -not $isRecencyPath -and -not $searchPathExact) {
        $history = @(Search-CmdPeekCommand -History $history -Query $Search -Category $Category)
    }
    elseif ($searchPathExact -and $Category) {
        $history = @(Search-CmdPeekCommand -History $history -Category $Category)
    }

    if ($Recent) {
        $sinceSpec = $Since
        if ([string]::IsNullOrWhiteSpace($sinceSpec)) { $sinceSpec = 'last' }
        $parsed = Convert-CmdPeekSince -Since $sinceSpec -Cursor $state.LastMcpAt
        $cursorBefore = $state.LastMcpAt
        $mode = 'delta'
        $recentTake = 20
        if ($Count -gt 0) { $recentTake = $Count }
        $rows = @(Select-CmdPeekJustInstalled -History $history -Since $sinceSpec -Cursor $state.LastMcpAt -Count $recentTake -CommandTester $CommandTester)
        if ($parsed.Kind -ne 'all' -and $rows.Count -eq 0) {
            $rows = @(Select-CmdPeekJustInstalled -History $history -Since 'all' -Count $recentTake -CommandTester $CommandTester)
            $mode = 'fallback'
        }
        elseif ($parsed.Kind -eq 'all') {
            $mode = 'delta'
        }
        if ($Search -or $Category) {
            $rows = @(Search-CmdPeekCommand -History $rows -Query $Search -Category $Category)
        }
        $rows = @(Add-CmdPeekUsageProbe -History $rows -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner -OpenAiRunner $OpenAiRunner)
        $commands = @(
            foreach ($row in $rows) {
                [pscustomobject]@{
                    command        = $row.Command
                    packageName    = $row.PackageName
                    packageManager = $row.PackageManager
                    installDate    = $(if ($row.InstallDate) { ([datetime]$row.InstallDate).ToString('o') } else { $null })
                    version        = $(if ($row.PSObject.Properties['Version']) { $row.Version } else { $null })
                    category       = $(if ($row.PSObject.Properties['Category']) { $row.Category } else { 'other' })
                    usages         = $(if ($row.PSObject.Properties['Usages']) { @($row.Usages) } else { @() })
                    usageDetails   = @(ConvertTo-CmdPeekStructuredUsage -Usage $(if ($row.PSObject.Properties['Usages']) { @($row.Usages) } else { @() }))
                    related        = $(if ($row.PSObject.Properties['Related'] -and $row.Related) { @($row.Related) } else { @() })
                    shims          = $(if ($row.PSObject.Properties['Shims']) { @($row.Shims) } else { @() })
                    onPath         = [bool]($row.PSObject.Properties['OnPath'] -and $row.OnPath)
                    hidden         = $false
                    favorite       = [bool]($row.PSObject.Properties['Favorite'] -and $row.Favorite)
                    installCommands = @(Get-CmdPeekInstallCommands -Command $row.Command -Catalog $catalog -PreferredManager $preferred)
                }
            }
        )
        $payload = [pscustomobject]@{
            generatedAt = (Get-Date).ToString('o')
            cursor      = $cursorBefore
            mode        = $mode
            commands    = $commands
        }
        if (@($commands).Count -gt 0) {
            $state.LastMcpAt = (Get-Date).ToString('o')
            Save-CmdPeekState -State $state -DataDirectory $DataDirectory
            if ($mode -eq 'delta') {
                [void](Save-CmdPeekLastInstall -Command $rows -DataDirectory $DataDirectory)
            }
        }
        Write-Output ($payload | ConvertTo-Json -Depth 8)
        return
    }

    if ($Json -or $Gaps -or $HumanGaps) {
        $history = @(Add-CmdPeekUsageProbe -History $history -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner -OpenAiRunner $OpenAiRunner -Limit $ProbeLimit)
        $snapArgs = @{
            History        = $history
            Manager        = @(Get-CmdPeekPackageManager -CommandTester $CommandTester -All)
            Catalog        = $catalog
            Favorite       = @($state.Favorites)
            Hidden         = @($state.Hidden)
            CommandTester  = $CommandTester
            RecentLines    = $RecentLines
            DataDirectory  = $DataDirectory
            GapLimit       = $GapLimit
        }
        if ($PSBoundParameters.ContainsKey('GapKind') -and $GapKind) {
            $snapArgs.GapKind = $GapKind
        }
        if ($PSBoundParameters.ContainsKey('HistoryPath')) {
            $snapArgs.HistoryPath = $HistoryPath
        }
        if ($LastUsedPath) {
            $snapArgs.LastUsedPath = $LastUsedPath
        }
        $snapshot = ConvertTo-CmdPeekSnapshot @snapArgs
        if ($Gaps -and -not $HumanGaps) {
            Write-Output ([pscustomobject]@{
                gaps    = @($snapshot.gaps)
                summary = $snapshot.gapSummary
            } | ConvertTo-Json -Depth 8)
        }
        elseif ($HumanGaps) {
            if ($Json) {
                Write-Output ([pscustomobject]@{
                    gaps    = @($snapshot.gaps)
                    summary = $snapshot.gapSummary
                } | ConvertTo-Json -Depth 8)
            }
            else {
                Write-Output (Format-CmdPeekGapOutput -Gap @($snapshot.gaps) -Summary $snapshot.gapSummary)
            }
        }
        else {
            $snapshot | Add-Member lastPeekAt $state.LastPeekAt -Force
            $snapshot | Add-Member lastMcpAt $state.LastMcpAt -Force
            if ($fullInventoryJson) {
                Save-CmdPeekInventoryCache -Snapshot $snapshot -DataDirectory $DataDirectory
            }
            if ($Count -gt 0) {
                $snapshot.commands = @($snapshot.commands | Select-Object -First $Count)
            }
            Write-Output ($snapshot | ConvertTo-Json -Depth 10)
        }
        return
    }

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
        $usedPath = $LastUsedPath
        if (-not $usedPath) { $usedPath = Get-CmdPeekRustyLastUsedPath -DataDirectory $DataDirectory }
        $rustyRows = @(Get-CmdPeekRusty -History $history -HistoryPath @($hp) -RecentLines $RecentLines -LastUsedPath $usedPath -PersistLastUsed)
        if ($rustyRows.Count -eq 0) {
            Write-Output (Format-CmdPeekQuickOutput -History @() -ExampleCount 3 -Rusty)
            return
        }
        Write-Output (Format-CmdPeekQuickOutput -History $rustyRows -ExampleCount 3 -Rusty)
        return
    }

    if ($useInteractive) {
        $kits = Get-CmdPeekCatalogKits -Path $ExamplesPath -DataDirectory $DataDirectory
        $selectArgs = @{ Gap = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits); Limit = $GapLimit }
        if ($PSBoundParameters.ContainsKey('GapKind') -and $GapKind) { $selectArgs.Kind = $GapKind }
        $gapList = @(Select-CmdPeekGap @selectArgs)
        Invoke-CmdPeekInteractive -History $history -State $state -DataDirectory $DataDirectory -Gap $gapList -Catalog $catalog -HelpRunner $HelpRunner
        return
    }

    # -Search / -Category without -n: flat list, no LastPeekAt cursor advance
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
                $whyRow = Get-CmdPeekWhyCommand -Command $row.Command -History $history -Catalog $catalog -CommandTester $CommandTester -PreferredManager $preferred
                $row | Add-Member -NotePropertyName SubstitutesInstalled -NotePropertyValue @($whyRow.substitutesInstalled) -Force
                $row | Add-Member -NotePropertyName InstallCommands -NotePropertyValue @($whyRow.installCommands) -Force
                $slice = @(Add-CmdPeekUsageProbe -History @($row) -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner -OpenAiRunner $OpenAiRunner -Limit 0)
                Write-Output (Format-CmdPeekQuickOutput -History $slice -ExampleCount 5 -CheatSheet)
                return
            }
            if ($exact.Count -gt 1) {
                $flat = @(Add-CmdPeekUsageProbe -History $exact -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner -OpenAiRunner $OpenAiRunner -Limit 0)
                Write-Output (Format-CmdPeekQuickOutput -History $flat -ExampleCount 3)
                return
            }
            $history = @(Search-CmdPeekCommand -History $history -Query $Search -Category $Category)
        }

        $flat = @(Select-CmdPeekQuickHistory -History $history -Count 0)
        $flat = @(Add-CmdPeekUsageProbe -History $flat -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner -OpenAiRunner $OpenAiRunner)
        Write-Output (Format-CmdPeekQuickOutput -History $flat -ExampleCount 3)
        return
    }

    $take = $Count
    if ($take -le 0) { $take = 5 }

    $sinceSpec = $Since
    if ([string]::IsNullOrWhiteSpace($sinceSpec)) { $sinceSpec = 'last' }

    $parsed = Convert-CmdPeekSince -Since $sinceSpec -Cursor $state.LastPeekAt
    $slice = @()
    $header = ''
    $emptyDelta = $false
    if ($parsed.Kind -eq 'all') {
        $slice = @(Select-CmdPeekJustInstalled -History $history -Since 'all' -Count $take -CommandTester $CommandTester)
        $header = "Last $($slice.Count) installed commands:"
    }
    else {
        $slice = @(Select-CmdPeekJustInstalled -History $history -Since $sinceSpec -Cursor $state.LastPeekAt -Count $take -CommandTester $CommandTester)
        if ($slice.Count -eq 0) {
            $slice = @(Select-CmdPeekJustInstalled -History $history -Since 'all' -Count $take -CommandTester $CommandTester)
            $when = $(if ($state.LastPeekAt) { $state.LastPeekAt } else { 'never' })
            $header = "No new installs since $when. Showing last $($slice.Count) instead."
            $emptyDelta = $true
        }
        else {
            $header = 'Installed since last look:'
        }
    }

    if ($Search -or $Category) {
        $slice = @(Search-CmdPeekCommand -History $slice -Query $Search -Category $Category)
    }

    if ($slice.Count -eq 0 -and @($history).Count -gt 0) {
        Write-Output "No commands to show in quick view. Hidden entries still appear in interactive mode (cmdpeek); press h to unhide.`n"
        return
    }
    if ($slice.Count -eq 0) {
        Write-Output (Format-CmdPeekQuickOutput -History @() -ExampleCount 3)
        return
    }

    $rustyOut = $null
    if ($emptyDelta) {
        $skipRusty = $false
        $rustyArgs = @{
            History     = @(
                $history | Where-Object {
                    -not ($_.PSObject.Properties['Hidden'] -and $_.Hidden)
                }
            )
            RecentLines = $RecentLines
        }
        $usedPath = $LastUsedPath
        if (-not $usedPath) { $usedPath = Get-CmdPeekRustyLastUsedPath -DataDirectory $DataDirectory }
        if ($usedPath) { $rustyArgs.LastUsedPath = $usedPath; $rustyArgs.PersistLastUsed = $true }
        if ($PSBoundParameters.ContainsKey('HistoryPath')) {
            $anyHist = $false
            foreach ($p in @($HistoryPath)) {
                if ($p -and (Test-Path -LiteralPath $p)) { $anyHist = $true; break }
            }
            if (-not $anyHist) {
                $skipRusty = $true
            }
            else {
                $rustyArgs.HistoryPath = @($HistoryPath)
            }
        }
        if (-not $skipRusty) {
            $rustyRows = @(Get-CmdPeekRusty @rustyArgs)
            $top = @($rustyRows | Select-Object -First 3)
            if ($top.Count -gt 0) {
                $rustyOut = Format-CmdPeekQuickOutput -History $top -ExampleCount 3 -Rusty
            }
        }
    }

    $slice = @(Add-CmdPeekUsageProbe -History $slice -Catalog $catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner -OpenAiRunner $OpenAiRunner)
    if ($rustyOut) {
        Write-Output $rustyOut
    }
    Write-Output (Format-CmdPeekQuickOutput -History $slice -ExampleCount 3 -Header $header)
    if (-not $emptyDelta -and $slice.Count -gt 0) {
        [void](Save-CmdPeekLastInstall -Command $slice -DataDirectory $DataDirectory)
    }
    $state.LastPeekAt = (Get-Date).ToString('o')
    Save-CmdPeekState -State $state -DataDirectory $DataDirectory
}

Export-ModuleMember -Function @(
    'Get-CmdPeekPackageManager'
    'Get-CmdPeekPackageManagerInstallHint'
    'Get-CmdPeekInstalledPackage'
    'Get-CmdPeekCommandHistory'
    'Get-CmdPeekUnknownInstallDate'
    'Find-CmdPeekMissingCommand'
    'Search-CmdPeekCommand'
    'Select-CmdPeekExactCommand'
    'Get-CmdPeekState'
    'Save-CmdPeekState'
    'Set-CmdPeekFavorite'
    'Set-CmdPeekHidden'
    'Set-CmdPeekPreferredPackageManager'
    'Export-CmdPeekState'
    'Import-CmdPeekState'
    'ConvertTo-CmdPeekState'
    'Get-CmdPeekUsageExample'
    'Get-CmdPeekExampleCatalog'
    'Get-CmdPeekCatalogKits'
    'Invoke-CmdPeek'
    'Invoke-CmdPeekInteractive'
    'Format-CmdPeekQuickOutput'
    'Install-CmdPeekTrackedPackage'
    'Get-CmdPeekGap'
    'Get-CmdPeekGapKind'
    'Get-CmdPeekGapKindRank'
    'Get-CmdPeekGapSummary'
    'Select-CmdPeekGap'
    'Get-CmdPeekInventory'
    'ConvertTo-CmdPeekSnapshot'
    'Add-CmdPeekProfileHint'
    'Convert-CmdPeekSince'
    'Select-CmdPeekJustInstalled'
    'Get-CmdPeekRusty'
    'Resolve-CmdPeekTask'
    'Get-CmdPeekWhyCommand'
    'Get-CmdPeekHaveList'
    'Search-CmdPeekAvailable'
    'Test-CmdPeekCatalog'
    'Get-CmdPeekLastInstall'
    'Get-CmdPeekInstallCommands'
    'Add-CmdPeekPathCommands'
    'Format-CmdPeekTaskOutput'
    'Format-CmdPeekWhyOutput'
    'Format-CmdPeekHaveOutput'
    'Get-CmdPeekAptPackage'
    'Get-CmdPeekAptPackageCommand'
    'Get-CmdPeekAptFileListMap'
    'Get-CmdPeekPacmanPackage'
    'Get-CmdPeekWinGetReleaseInfo'
    'Get-CmdPeekMockAiExample'
    'Get-CmdPeekOpenAiExample'
    'Get-CmdPeekRustyLastUsedPath'
    'Save-CmdPeekRustyLastUsed'
    'Write-CmdPeekRustyLastUsedLine'
    'Add-CmdPeekHistoryTimestamp'
    'Get-CmdPeekDefaultUnixRoot'
    'Format-CmdPeekGapOutput'
    'Format-CmdPeekAgentExport'
    'Get-CmdPeekCommandCard'
    'Compare-CmdPeekCommand'
    'Get-CmdPeekArgvSuggestion'
    'Get-CmdPeekSystemList'
    'Test-CmdPeekCatalogIsBuiltin'
    'Get-CmdPeekCurrentOs'
    'Save-CmdPeekLearnedCatalogEntry'
)
