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
        $state.Hidden | Should -Be @()
        $state.PreferredPackageManager | Should -BeNullOrEmpty
        $state.PSObject.Properties.Name | Should -Not -Contain 'TelemetryEnabled'
        $state.PSObject.Properties.Name | Should -Not -Contain 'ExampleUsageCounts'
        $state.Commands | Should -Be @()
    }

    It 'round-trips favorites and tracked commands' {
        $dir = Join-Path $TestDrive 'roundtrip'
        $state = Get-CmdPeekState -DataDirectory $dir
        $state.Favorites = @('fd', 'jq')
        $state.Hidden = @('logexpert')
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
        $loaded.Hidden | Should -Be @('logexpert')
        $loaded.PreferredPackageManager | Should -Be 'scoop'
        $loaded.Commands[0].Command | Should -Be 'fd'
    }

    It 'round-trips LastPeekAt and LastMcpAt without treating LastScan as a recency cursor' {
        $dir = Join-Path $TestDrive 'cursors'
        $state = Get-CmdPeekState -DataDirectory $dir
        $state.PSObject.Properties.Name | Should -Contain 'LastPeekAt'
        $state.PSObject.Properties.Name | Should -Contain 'LastMcpAt'
        $state.LastPeekAt | Should -BeNullOrEmpty
        $state.LastMcpAt | Should -BeNullOrEmpty

        $state.LastPeekAt = '2026-08-24T10:00:00.0000000Z'
        $state.LastMcpAt = '2026-08-24T11:00:00.0000000Z'
        $state.LastScan = '2026-08-24T12:00:00.0000000Z'
        Save-CmdPeekState -State $state -DataDirectory $dir

        $loaded = Get-CmdPeekState -DataDirectory $dir
        $loaded.LastPeekAt | Should -Be '2026-08-24T10:00:00.0000000Z'
        $loaded.LastMcpAt | Should -Be '2026-08-24T11:00:00.0000000Z'
        $loaded.LastScan | Should -Be '2026-08-24T12:00:00.0000000Z'
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

Describe 'Set-CmdPeekHidden' {
    It 'adds and removes a command hidden from quick view' {
        $dir = Join-Path $TestDrive 'hide'
        $state = Get-CmdPeekState -DataDirectory $dir
        $state = Set-CmdPeekHidden -State $state -Command 'logexpert' -Hidden $true
        $state.Hidden | Should -Contain 'logexpert'
        $state = Set-CmdPeekHidden -State $state -Command 'logexpert' -Hidden $false
        $state.Hidden | Should -Not -Contain 'logexpert'
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

Describe 'Add-CmdPeekProfileHint' {
    It 'appends the install hint to a profile once' {
        $profilePath = Join-Path $TestDrive 'Microsoft.PowerShell_profile.ps1'
        Add-CmdPeekProfileHint -ProfilePath $profilePath
        Add-CmdPeekProfileHint -ProfilePath $profilePath
        $text = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8
        $text | Should -Match 'Invoke-CmdPeekHint'
        $text | Should -Match 'cmdpeek -NonInteractive -n 1'
        $text | Should -Match 'function winget'
        $text | Should -Match 'function pipx'
        $text | Should -Match 'function cargo'
        $text | Should -Match 'Register-CmdPeekHistoryTimestamp'
        $text | Should -Match 'Add-CmdPeekHistoryTimestamp'
        ([regex]::Matches($text, 'BEGIN cmdpeek hint')).Count | Should -Be 1
    }

    It 'upgrades a pipx-era hint that lacks history timestamps' {
        $profilePath = Join-Path $TestDrive 'pipx-only-profile.ps1'
        @'
# BEGIN cmdpeek hint
function pipx { }
# END cmdpeek hint
'@ | Set-Content -LiteralPath $profilePath -Encoding UTF8
        Add-CmdPeekProfileHint -ProfilePath $profilePath
        $text = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8
        $text | Should -Match 'Register-CmdPeekHistoryTimestamp'
        ([regex]::Matches($text, 'BEGIN cmdpeek hint')).Count | Should -Be 1
    }

    It 'upgrades a copied 0.1 profile fixture' {
        $src = Join-Path $PSScriptRoot '..\examples\mocks\profile-v1.ps1'
        $profilePath = Join-Path $TestDrive 'upgrade-profile.ps1'
        Copy-Item -LiteralPath $src -Destination $profilePath
        Add-CmdPeekProfileHint -ProfilePath $profilePath
        $text = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8
        $text | Should -Match 'function pipx'
        ([regex]::Matches($text, 'BEGIN cmdpeek hint')).Count | Should -Be 1
    }
}

Describe 'Get-CmdPeekDataDirectory' {
    It 'resolves a default path when LOCALAPPDATA is unset' {
        $had = Test-Path Env:LOCALAPPDATA
        $prev = $env:LOCALAPPDATA
        try {
            if ($had) { Remove-Item Env:LOCALAPPDATA }
            $dir = Get-CmdPeekDataDirectory
            $dir | Should -Match 'cmdpeek'
            { [void](Join-Path $dir 'state.json') } | Should -Not -Throw
        }
        finally {
            if ($had) { $env:LOCALAPPDATA = $prev }
        }
    }
}

Describe 'Set-CmdPeekPreferredPackageManager' {
    It 'stores chocolatey, scoop, winget, or language-toolchain managers' {
        $state = Get-CmdPeekDefaultState
        $state = Set-CmdPeekPreferredPackageManager -State $state -PackageManager 'scoop'
        $state.PreferredPackageManager | Should -Be 'scoop'
        $state = Set-CmdPeekPreferredPackageManager -State $state -PackageManager 'chocolatey'
        $state.PreferredPackageManager | Should -Be 'chocolatey'
        $state = Set-CmdPeekPreferredPackageManager -State $state -PackageManager 'pipx'
        $state.PreferredPackageManager | Should -Be 'pipx'
    }
}
