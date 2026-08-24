#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:CmdPeekModuleRoot = $PSScriptRoot

. (Join-Path $PSScriptRoot 'Config.ps1')
. (Join-Path $PSScriptRoot 'PackageManager.ps1')
. (Join-Path $PSScriptRoot 'CommandHistory.ps1')
. (Join-Path $PSScriptRoot 'UsageExamples.ps1')
. (Join-Path $PSScriptRoot 'InteractiveMode.ps1')

function Invoke-CmdPeek {
    [CmdletBinding()]
    param(
        [int]$Count,
        [switch]$Interactive,
        [string]$Search,
        [string]$Category,
        [switch]$NonInteractive,
        [string]$Reinstall,
        [ValidateSet('chocolatey', 'scoop', 'winget')]
        [string]$Manager,
        [string]$Export,
        [string]$Import,
        [string]$DataDirectory,
        [string]$ChocolateyRoot,
        [string]$ScoopRoot,
        [string]$WinGetRoot,
        [string]$ExamplesPath,
        [string[]]$EnabledManagers,
        [scriptblock]$CommandTester
    )

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

    $managerNames = @()
    if ($PSBoundParameters.ContainsKey('EnabledManagers')) {
        $managerNames = @($EnabledManagers)
    }
    else {
        $detected = @(Get-CmdPeekPackageManager -CommandTester $CommandTester)
        if ($detected.Count -eq 0) {
            Show-CmdPeekNoManagerPrompt -NonInteractive:$NonInteractive
            $detected = @(Get-CmdPeekPackageManager -CommandTester $CommandTester)
            if ($detected.Count -eq 0) { return }
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
        return
    }

    $packages = @(Get-CmdPeekInstalledPackage `
            -ChocolateyRoot $ChocolateyRoot `
            -ScoopRoot $ScoopRoot `
            -WinGetRoot $WinGetRoot `
            -EnabledManagers $managerNames `
            -CommandTester $CommandTester)

    $history = @(Get-CmdPeekCommandHistory -Package $packages)
    $catalog = Get-CmdPeekExampleCatalog -Path $ExamplesPath
    $history = @(Add-CmdPeekCatalogMetadata -History $history -Catalog $catalog)

    $state = Get-CmdPeekState -DataDirectory $DataDirectory
    $history = @(Merge-CmdPeekFavorite -History $history -Favorite @($state.Favorites))

    $missing = @(Find-CmdPeekMissingCommand -Previous @($state.Commands) -Current $history)
    if ($missing.Count -gt 0) {
        Confirm-CmdPeekMissingCommand -Missing $missing -Managers $managers -NonInteractive:$NonInteractive
    }

    $state.Commands = @(
        $history | Select-Object Command, PackageName, PackageManager, InstallDate, Version
    )
    $state.LastScan = (Get-Date).ToString('o')
    Save-CmdPeekState -State $state -DataDirectory $DataDirectory

    if ($Search -or $Category) {
        $history = @(Search-CmdPeekCommand -History $history -Query $Search -Category $Category)
    }

    $useInteractive = [bool]$Interactive -or ($Count -le 0 -and -not $Search -and -not $Category)
    if ($NonInteractive) { $useInteractive = $false }

    if ($useInteractive) {
        Invoke-CmdPeekInteractive -History $history -State $state -DataDirectory $DataDirectory
        return
    }

    $take = $Count
    if ($take -le 0) { $take = 5 }
    $slice = @($history | Select-Object -First $take)
    Write-Output (Format-CmdPeekQuickOutput -History $slice -ExampleCount 3)
}

Export-ModuleMember -Function @(
    'Get-CmdPeekPackageManager'
    'Get-CmdPeekPackageManagerInstallHint'
    'Get-CmdPeekInstalledPackage'
    'Get-CmdPeekCommandHistory'
    'Find-CmdPeekMissingCommand'
    'Search-CmdPeekCommand'
    'Get-CmdPeekState'
    'Save-CmdPeekState'
    'Set-CmdPeekFavorite'
    'Export-CmdPeekState'
    'Import-CmdPeekState'
    'Get-CmdPeekUsageExample'
    'Get-CmdPeekExampleCatalog'
    'Invoke-CmdPeek'
    'Invoke-CmdPeekInteractive'
    'Format-CmdPeekQuickOutput'
    'Install-CmdPeekTrackedPackage'
)
