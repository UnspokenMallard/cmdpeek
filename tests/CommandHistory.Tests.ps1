#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'PackageManager.ps1')
    . (Join-Path $src 'CommandHistory.ps1')
}

Describe 'Get-CmdPeekCommandHistory' {
    It 'flattens packages into one row per command, newest first' {
        $packages = @(
            [pscustomobject]@{
                Name            = 'ripgrep'
                Version         = '14.1.0'
                PackageManager  = 'scoop'
                InstallDate     = [datetime]'2025-08-17T10:00:00Z'
                Commands        = @('rg')
            }
            [pscustomobject]@{
                Name            = 'yt-dlp'
                Version         = '2025.08.11'
                PackageManager  = 'scoop'
                InstallDate     = [datetime]'2025-08-20T14:32:00Z'
                Commands        = @('yt-dlp')
            }
            [pscustomobject]@{
                Name            = 'jq'
                Version         = '1.7.1'
                PackageManager  = 'chocolatey'
                InstallDate     = [datetime]'2025-08-18T09:00:00Z'
                Commands        = @('jq')
            }
        )

        $history = @(Get-CmdPeekCommandHistory -Package $packages)
        $history.Count | Should -Be 3
        $history[0].Command | Should -Be 'yt-dlp'
        $history[1].Command | Should -Be 'jq'
        $history[2].Command | Should -Be 'rg'
        $history[0].PackageManager | Should -Be 'scoop'
        $history[1].PackageManager | Should -Be 'chocolatey'
    }

    It 'keeps the newest install when the same command appears twice' {
        $packages = @(
            [pscustomobject]@{
                Name           = 'jq'
                Version        = '1.6'
                PackageManager = 'chocolatey'
                InstallDate    = [datetime]'2024-01-01T00:00:00Z'
                Commands       = @('jq')
            }
            [pscustomobject]@{
                Name           = 'jq'
                Version        = '1.7.1'
                PackageManager = 'scoop'
                InstallDate    = [datetime]'2025-08-18T09:00:00Z'
                Commands       = @('jq')
            }
        )

        $history = @(Get-CmdPeekCommandHistory -Package $packages)
        $history.Count | Should -Be 1
        $history[0].PackageManager | Should -Be 'scoop'
        $history[0].InstallDate | Should -Be ([datetime]'2025-08-18T09:00:00Z')
    }

    It 'limits results when -Count is set' {
        $packages = 1..5 | ForEach-Object {
            [pscustomobject]@{
                Name           = "pkg$_"
                Version        = '1.0'
                PackageManager = 'scoop'
                InstallDate    = ([datetime]'2025-08-01T00:00:00Z').AddDays($_)
                Commands       = @("cmd$_")
            }
        }

        $history = @(Get-CmdPeekCommandHistory -Package $packages -Count 3)
        $history.Count | Should -Be 3
        $history[0].Command | Should -Be 'cmd5'
        $history[2].Command | Should -Be 'cmd3'
    }

    It 'skips packages with no commands' {
        $packages = @(
            [pscustomobject]@{
                Name           = 'dotnetfx'
                Version        = '4.8'
                PackageManager = 'chocolatey'
                InstallDate    = [datetime]'2025-08-01T00:00:00Z'
                Commands       = @()
            }
        )

        $history = @(Get-CmdPeekCommandHistory -Package $packages)
        $history.Count | Should -Be 0
    }
}

Describe 'Find-CmdPeekMissingCommand' {
    It 'returns commands that were tracked but are no longer installed' {
        $previous = @(
            [pscustomobject]@{ Command = 'yt-dlp'; PackageManager = 'scoop'; PackageName = 'yt-dlp' }
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'chocolatey'; PackageName = 'jq' }
        )
        $current = @(
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'chocolatey'; PackageName = 'jq' }
        )

        $missing = @(Find-CmdPeekMissingCommand -Previous $previous -Current $current)
        $missing.Count | Should -Be 1
        $missing[0].Command | Should -Be 'yt-dlp'
        $missing[0].PackageManager | Should -Be 'scoop'
    }

    It 'returns empty when every tracked command is still present' {
        $rows = @(
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'chocolatey'; PackageName = 'jq' }
        )
        $missing = @(Find-CmdPeekMissingCommand -Previous $rows -Current $rows)
        $missing.Count | Should -Be 0
    }

    It 'is case-insensitive when matching command names' {
        $previous = @([pscustomobject]@{ Command = 'JQ'; PackageManager = 'scoop'; PackageName = 'jq' })
        $current  = @([pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop'; PackageName = 'jq' })
        $missing = @(Find-CmdPeekMissingCommand -Previous $previous -Current $current)
        $missing.Count | Should -Be 0
    }
}

Describe 'Search-CmdPeekCommand' {
    BeforeAll {
        $script:history = @(
            [pscustomobject]@{ Command = 'yt-dlp'; PackageManager = 'scoop'; Category = 'media'; Favorite = $true }
            [pscustomobject]@{ Command = 'fd'; PackageManager = 'scoop'; Category = 'dev-tools'; Favorite = $false }
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'chocolatey'; Category = 'dev-tools'; Favorite = $false }
        )
    }

    It 'filters by command name substring' {
        $result = @(Search-CmdPeekCommand -History $script:history -Query 'yt')
        $result.Count | Should -Be 1
        $result[0].Command | Should -Be 'yt-dlp'
    }

    It 'filters by category' {
        $result = @(Search-CmdPeekCommand -History $script:history -Category 'dev-tools')
        $result.Command | Should -Contain 'fd'
        $result.Command | Should -Contain 'jq'
        $result.Command | Should -Not -Contain 'yt-dlp'
    }

    It 'returns only favorites when requested' {
        $result = @(Search-CmdPeekCommand -History $script:history -Favorite)
        $result.Count | Should -Be 1
        $result[0].Command | Should -Be 'yt-dlp'
    }
}
