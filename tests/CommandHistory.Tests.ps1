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

    It 'keeps scoop and chocolatey copies of the same command as separate rows' {
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
        $history.Count | Should -Be 2
        $history.PackageManager | Should -Contain 'scoop'
        $history.PackageManager | Should -Contain 'chocolatey'
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

    It 'matches usage text so /json finds jq' {
        $history = @(
            [pscustomobject]@{
                Command        = 'fd'
                PackageManager = 'scoop'
                PackageName    = 'fd'
                Usages         = @('fd <pattern>                    # Find files')
            }
            [pscustomobject]@{
                Command        = 'jq'
                PackageManager = 'chocolatey'
                PackageName    = 'jq'
                Usages         = @("jq '.field' file.json           # Extract field")
            }
        )
        $result = @(Search-CmdPeekCommand -History $history -Query 'json')
        $result.Count | Should -Be 1
        $result[0].Command | Should -Be 'jq'
    }

    It 'returns only hidden commands when HiddenOnly is set' {
        $history = @(
            [pscustomobject]@{ Command = 'logexpert'; Hidden = $true }
            [pscustomobject]@{ Command = 'fd'; Hidden = $false }
            [pscustomobject]@{ Command = 'jq' }
        )
        $result = @(Search-CmdPeekCommand -History $history -HiddenOnly)
        $result.Count | Should -Be 1
        $result[0].Command | Should -Be 'logexpert'
    }
}

Describe 'Select-CmdPeekQuickHistory' {
    It 'omits hidden commands and fills -n from the remaining list' {
        $history = @(
            [pscustomobject]@{ Command = 'logexpert'; Hidden = $true }
            [pscustomobject]@{ Command = 'fd'; Hidden = $false }
            [pscustomobject]@{ Command = 'jq'; Hidden = $false }
        )
        $slice = @(Select-CmdPeekQuickHistory -History $history -Count 1)
        $slice.Count | Should -Be 1
        $slice[0].Command | Should -Be 'fd'

        $visible = @(Select-CmdPeekQuickHistory -History $history -Count 5)
        $visible.Command | Should -Contain 'fd'
        $visible.Command | Should -Contain 'jq'
        $visible.Command | Should -Not -Contain 'logexpert'
    }
}

Describe 'Convert-CmdPeekSince' {
    It 'treats blank, last with no cursor, as empty delta' {
        $r = Convert-CmdPeekSince -Since 'last' -Cursor $null
        $r.Kind | Should -Be 'empty'
    }

    It 'uses last cursor as exclusive lower bound' {
        $c = [datetime]'2026-08-20T00:00:00Z'
        $r = Convert-CmdPeekSince -Since 'last' -Cursor $c
        $r.Kind | Should -Be 'instant'
        $r.Instant | Should -Be $c
    }

    It 'parses all, ISO, and hour/day durations' {
        (Convert-CmdPeekSince -Since 'all').Kind | Should -Be 'all'
        $iso = Convert-CmdPeekSince -Since '2026-08-01T00:00:00Z'
        $iso.Kind | Should -Be 'instant'
        $iso.Instant | Should -Be ([datetime]'2026-08-01T00:00:00Z')
        $now = [datetime]'2026-08-24T12:00:00Z'
        $h = Convert-CmdPeekSince -Since '24h' -Now $now
        $h.Instant | Should -Be $now.AddHours(-24)
        $d = Convert-CmdPeekSince -Since '7d' -Now $now
        $d.Instant | Should -Be $now.AddDays(-7)
    }

    It 'throws on unparseable values' {
        { Convert-CmdPeekSince -Since 'yesterday' } | Should -Throw
        { Convert-CmdPeekSince -Since '30m' } | Should -Throw
    }
}

Describe 'Select-CmdPeekPackageRow' {
    It 'collapses ffmpeg helpers onto one scoop row and keeps dual jq installs' {
        $history = @(
            [pscustomobject]@{ Command = 'ffmpeg'; PackageName = 'ffmpeg'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-20'; Hidden = $false }
            [pscustomobject]@{ Command = 'ffprobe'; PackageName = 'ffmpeg'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-20'; Hidden = $false }
            [pscustomobject]@{ Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-21'; Hidden = $false }
            [pscustomobject]@{ Command = 'jq'; PackageName = 'jq'; PackageManager = 'chocolatey'; InstallDate = [datetime]'2026-08-19'; Hidden = $false }
        )
        $rows = @(Select-CmdPeekPackageRow -History $history)
        $rows.Count | Should -Be 3
        $ff = @($rows | Where-Object { $_.Command -eq 'ffmpeg' })[0]
        $ff.Shims | Should -Contain 'ffprobe'
        $ff.PackageManager | Should -Be 'scoop'
        @($rows | Where-Object { $_.Command -eq 'jq' }).Count | Should -Be 2
    }

    It 'omits the package when the primary is hidden and drops hidden shims only' {
        $history = @(
            [pscustomobject]@{ Command = 'ffmpeg'; PackageName = 'ffmpeg'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-20'; Hidden = $true }
            [pscustomobject]@{ Command = 'ffprobe'; PackageName = 'ffmpeg'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-20'; Hidden = $false }
        )
        @(Select-CmdPeekPackageRow -History $history).Count | Should -Be 0

        $history2 = @(
            [pscustomobject]@{ Command = 'ffmpeg'; PackageName = 'ffmpeg'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-20'; Hidden = $false }
            [pscustomobject]@{ Command = 'ffprobe'; PackageName = 'ffmpeg'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-20'; Hidden = $true }
        )
        $row = @(Select-CmdPeekPackageRow -History $history2)[0]
        $row.Command | Should -Be 'ffmpeg'
        @($row.Shims).Count | Should -Be 0
    }

    It 'prefers the gh-cli stem when gh is a bin' {
        $history = @(
            [pscustomobject]@{ Command = 'gh-test'; PackageName = 'gh-cli'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-01'; Hidden = $false }
            [pscustomobject]@{ Command = 'gh'; PackageName = 'gh-cli'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-02'; Hidden = $false }
        )
        $row = @(Select-CmdPeekPackageRow -History $history)[0]
        $row.Command | Should -Be 'gh'
        $row.Shims | Should -Contain 'gh-test'
    }
}

Describe 'Select-CmdPeekJustInstalled' {
    It 'filters by cursor and marks OnPath from the tester' {
        $history = @(
            [pscustomobject]@{ Command = 'new'; PackageName = 'new'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-22'; Hidden = $false }
            [pscustomobject]@{ Command = 'old'; PackageName = 'old'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-10'; Hidden = $false }
        )
        $tester = { param($Name) $Name -eq 'new' }
        $delta = @(Select-CmdPeekJustInstalled -History $history -Since 'last' -Cursor ([datetime]'2026-08-20') -CommandTester $tester)
        $delta.Count | Should -Be 1
        $delta[0].Command | Should -Be 'new'
        $delta[0].OnPath | Should -BeTrue

        $old = @(Select-CmdPeekJustInstalled -History $history -Since 'all' -Count 1 -CommandTester { param($Name) $false })
        $old[0].Command | Should -Be 'new'
        $old[0].OnPath | Should -BeFalse
    }

    It 'returns no rows for last with a null cursor so the caller can fall back' {
        $history = @(
            [pscustomobject]@{ Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-22'; Hidden = $false }
        )
        @(Select-CmdPeekJustInstalled -History $history -Since 'last' -Cursor $null).Count | Should -Be 0
    }

    It 'treats a throwing tester as off PATH' {
        $history = @(
            [pscustomobject]@{ Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'; InstallDate = [datetime]'2026-08-22'; Hidden = $false }
        )
        $row = @(Select-CmdPeekJustInstalled -History $history -Since 'all' -CommandTester { throw 'nope' })[0]
        $row.OnPath | Should -BeFalse
    }
}
