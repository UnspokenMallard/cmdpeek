#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'Config.ps1')
}

Describe 'Get-CmdPeekState' {
    It 'returns a default state when no file exists' {
        $dir = Join-Path $TestDrive 'fresh'
        $state = Get-CmdPeekState -DataDirectory $dir
        $state.Favorites | Should -Be @()
        $state.PreferredPackageManager | Should -BeNullOrEmpty
        $state.TelemetryEnabled | Should -BeFalse
        $state.Commands | Should -Be @()
    }

    It 'round-trips favorites and tracked commands' {
        $dir = Join-Path $TestDrive 'roundtrip'
        $state = Get-CmdPeekState -DataDirectory $dir
        $state.Favorites = @('fd', 'jq')
        $state.PreferredPackageManager = 'scoop'
        $state.Commands = @(
            [pscustomobject]@{
                Command        = 'fd'
                PackageManager = 'scoop'
                PackageName    = 'fd'
                InstallDate    = [datetime]'2025-08-19T00:00:00Z'
            }
        )
        Save-CmdPeekState -State $state -DataDirectory $dir

        $loaded = Get-CmdPeekState -DataDirectory $dir
        $loaded.Favorites | Should -Be @('fd', 'jq')
        $loaded.PreferredPackageManager | Should -Be 'scoop'
        $loaded.Commands[0].Command | Should -Be 'fd'
    }
}

Describe 'Set-CmdPeekFavorite' {
    It 'adds and removes a favorite by command name' {
        $dir = Join-Path $TestDrive 'fav'
        $state = Get-CmdPeekState -DataDirectory $dir
        $state = Set-CmdPeekFavorite -State $state -Command 'rg' -Favorite $true
        $state.Favorites | Should -Contain 'rg'
        $state = Set-CmdPeekFavorite -State $state -Command 'rg' -Favorite $false
        $state.Favorites | Should -Not -Contain 'rg'
    }
}

Describe 'Export-CmdPeekState / Import-CmdPeekState' {
    It 'writes a shareable backup that can be imported' {
        $dir = Join-Path $TestDrive 'data'
        $exportPath = Join-Path $TestDrive 'backup.json'
        $state = Get-CmdPeekState -DataDirectory $dir
        $state.Favorites = @('jq')
        Save-CmdPeekState -State $state -DataDirectory $dir

        Export-CmdPeekState -DataDirectory $dir -Path $exportPath
        Test-Path -LiteralPath $exportPath | Should -BeTrue

        $other = Join-Path $TestDrive 'other'
        Import-CmdPeekState -Path $exportPath -DataDirectory $other
        $loaded = Get-CmdPeekState -DataDirectory $other
        $loaded.Favorites | Should -Contain 'jq'
    }
}
