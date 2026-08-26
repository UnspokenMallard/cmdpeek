#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'CommandUse.ps1')
}

Describe 'Get-CmdPeekRusty' {
    BeforeAll {
        $script:inv = @(
            [pscustomobject]@{ Command = 'fd'; PackageManager = 'scoop'; Usages = @('fd x # find'); Hidden = $false }
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop'; Usages = @('jq . # json'); Hidden = $false }
            [pscustomobject]@{ Command = 'nevercli'; PackageManager = 'scoop'; Usages = @('nevercli --help'); Hidden = $false }
        )
    }

    It 'marks never and stale; recent names are omitted' {
        $path = Join-Path $TestDrive 'hist.txt'
        @(
            'jq .'
            'unrelated'
            'fd pattern'
        ) | Set-Content -LiteralPath $path -Encoding UTF8
        $rusty = @(Get-CmdPeekRusty -History $script:inv -HistoryPath @($path) -RecentLines 2)
        $rusty.Command | Should -Contain 'nevercli'
        $rusty.Command | Should -Contain 'jq'
        $rusty.Command | Should -Not -Contain 'fd'
        $never = @(@($rusty | Where-Object { $_.Command -eq 'nevercli' }))[0]
        $never.kind | Should -Be 'never'
        $never.LastLine | Should -Be ''
        $stale = @(@($rusty | Where-Object { $_.Command -eq 'jq' }))[0]
        $stale.kind | Should -Be 'stale'
        $stale.LastLine | Should -Be 'jq .'
        @($rusty)[0].Command | Should -Be 'nevercli'
        @($rusty)[1].Command | Should -Be 'jq'
    }

    It 'persists ISO-prefixed last-used dates to a sidecar without touching mock fixtures' {
        $path = Join-Path $TestDrive 'hist-iso.txt'
        @(
            '2026-03-02T14:11:00Z jq .'
            'fd pattern'
        ) | Set-Content -LiteralPath $path -Encoding UTF8
        $sidecar = Join-Path $TestDrive 'data-rusty\rusty-last-used.json'
        $inv = @(
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop'; Usages = @('jq .') }
            [pscustomobject]@{ Command = 'fd'; PackageManager = 'scoop'; Usages = @('fd x') }
        )
        $null = @(Get-CmdPeekRusty -History $inv -HistoryPath @($path) -RecentLines 1 -LastUsedPath $sidecar -PersistLastUsed)
        Test-Path -LiteralPath $sidecar | Should -BeTrue
        $raw = Get-Content -LiteralPath $sidecar -Raw -Encoding UTF8 | ConvertFrom-Json
        ([datetime]$raw.commands.jq.lastUsedAt).Year | Should -Be 2026
        ([datetime]$raw.commands.jq.lastUsedAt).Month | Should -Be 3
        ([datetime]$raw.commands.jq.lastUsedAt).Day | Should -Be 2
        [string]$raw.commands.jq.lastLine | Should -Match 'jq'
        $sidecar | Should -Not -Match 'examples'
    }

    It 'does not write a sidecar unless PersistLastUsed is set' {
        $path = Join-Path $TestDrive 'hist-nopersist.txt'
        '2026-03-02T14:11:00Z jq .' | Set-Content -LiteralPath $path -Encoding UTF8
        $sidecar = Join-Path $TestDrive 'no-write\rusty-last-used.json'
        $inv = @([pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop'; Usages = @('jq .') })
        $null = @(Get-CmdPeekRusty -History $inv -HistoryPath @($path) -RecentLines 1 -LastUsedPath $sidecar)
        Test-Path -LiteralPath $sidecar | Should -BeFalse
    }

    It 'returns empty when history files are missing' {
        $rusty = @(Get-CmdPeekRusty -History $script:inv -HistoryPath @((Join-Path $TestDrive 'no-such-hist.txt')) -RecentLines 5)
        $rusty.Count | Should -Be 0
    }

    It 'keeps a name off rusty if it is recent in either file' {
        $inv = @($script:inv) + [pscustomobject]@{ Command = 'rg'; PackageManager = 'scoop'; Usages = @('rg x'); Hidden = $false }
        $win = Join-Path $TestDrive 'win.txt'
        $pwsh = Join-Path $TestDrive 'pwsh.txt'
        @(
            'old'
            'rg -i foo'
        ) | Set-Content -LiteralPath $win -Encoding UTF8
        'other' | Set-Content -LiteralPath $pwsh -Encoding UTF8
        $rusty = @(Get-CmdPeekRusty -History $inv -HistoryPath @($win, $pwsh) -RecentLines 2)
        $rusty.Command | Should -Not -Contain 'rg'
    }
}
