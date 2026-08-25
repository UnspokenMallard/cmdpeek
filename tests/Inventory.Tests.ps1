#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'PackageManager.ps1')
    . (Join-Path $src 'CommandHistory.ps1')
    . (Join-Path $src 'UsageExamples.ps1')
    . (Join-Path $src 'Inventory.ps1')
}

Describe 'Get-CmdPeekGap' {
    BeforeAll {
        $script:catalog = @{
            'yt-dlp' = [pscustomobject]@{
                category = 'media'
                related  = @('ffmpeg', 'gallery-dl')
                usages   = @('yt-dlp <URL>                    # Download video')
            }
            'ffmpeg' = [pscustomobject]@{
                category = 'media'
                related  = @('yt-dlp')
                usages   = @('ffmpeg -i input.mp4 output.mp3  # Convert video to audio')
            }
            'fd' = [pscustomobject]@{
                category = 'dev-tools'
                related  = @('rg', 'fzf')
                usages   = @('fd <pattern>                    # Find files')
            }
        }
        $script:history = @(
            [pscustomobject]@{
                Command        = 'yt-dlp'
                PackageName    = 'yt-dlp'
                PackageManager = 'scoop'
                Category       = 'media'
                Usages         = @('yt-dlp <URL>                    # Download video')
                Related        = @('ffmpeg', 'gallery-dl')
                Favorite       = $false
            }
            [pscustomobject]@{
                Command        = 'mystery-cli'
                PackageName    = 'mystery-cli'
                PackageManager = 'scoop'
                Category       = 'other'
                Usages         = @('mystery-cli --help                       # Show command help')
                Related        = @()
                Favorite       = $false
            }
        )
    }

    It 'flags related catalog tools that are not installed' {
        $gaps = @(Get-CmdPeekGap -History $script:history -Catalog $script:catalog)
        $missing = @($gaps | Where-Object { $_.Kind -eq 'missing-related' })
        $missing.Command | Should -Contain 'ffmpeg'
        $missing.Command | Should -Contain 'gallery-dl'
        $ffmpeg = $missing | Where-Object { $_.Command -eq 'ffmpeg' } | Select-Object -First 1
        $ffmpeg.RelatedTo | Should -Contain 'yt-dlp'
    }

    It 'flags installed commands that only have generic help' {
        $gaps = @(Get-CmdPeekGap -History $script:history -Catalog $script:catalog)
        $thin = @($gaps | Where-Object { $_.Kind -eq 'thin-docs' })
        $thin.Command | Should -Contain 'mystery-cli'
        $thin.Command | Should -Not -Contain 'yt-dlp'
    }

    It 'does not suggest a related tool that is already installed' {
        $withFfmpeg = $script:history + [pscustomobject]@{
            Command        = 'ffmpeg'
            PackageName    = 'ffmpeg'
            PackageManager = 'scoop'
            Category       = 'media'
            Usages         = @('ffmpeg -i input.mp4 output.mp3  # Convert')
            Related        = @('yt-dlp')
            Favorite       = $false
        }
        $gaps = @(Get-CmdPeekGap -History $withFfmpeg -Catalog $script:catalog)
        @($gaps | Where-Object { $_.Kind -eq 'missing-related' }).Command | Should -Not -Contain 'ffmpeg'
    }

    It 'flags a command installed from two package managers as shadowing' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'Scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @(); Hidden = $false
            }
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'Chocolatey'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @(); Hidden = $false
            }
        )
        $gaps = @(Get-CmdPeekGap -History $history -Catalog @{})
        $shadow = @($gaps | Where-Object { $_.kind -eq 'shadowing' })
        $shadow.Count | Should -Be 1
        @($shadow)[0].command | Should -Be 'jq'
        @(@($shadow)[0].packageManagers) | Should -Be @('chocolatey', 'scoop')
        @(@($shadow)[0].relatedTo).Count | Should -Be 0
    }

    It 'does not flag two rows with the same manager as shadowing' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @()
            }
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @()
            }
        )
        $gaps = @(Get-CmdPeekGap -History $history -Catalog @{})
        @($gaps | Where-Object { $_.kind -eq 'shadowing' }).Count | Should -Be 0
    }

    It 'counts a hidden row toward shadowing' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @(); Hidden = $true
            }
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'choco'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @(); Hidden = $false
            }
        )
        $gaps = @(Get-CmdPeekGap -History $history -Catalog @{})
        @($gaps | Where-Object { $_.kind -eq 'shadowing' }).Count | Should -Be 1
    }
}

Describe 'ConvertTo-CmdPeekSnapshot' {
    It 'emits managers, commands, favorites, and gaps' {
        $history = @(
            [pscustomobject]@{
                Command        = 'fd'
                PackageName    = 'fd'
                PackageManager = 'scoop'
                InstallDate    = [datetime]'2025-08-19T00:00:00Z'
                Version        = '10.2.0'
                Category       = 'dev-tools'
                Usages         = @('fd <pattern>                    # Find files')
                Related        = @('rg')
                Favorite       = $true
            }
        )
        $managers = @([pscustomobject]@{ Name = 'scoop'; Command = 'scoop'; Present = $true })
        $catalog = @{
            'fd' = [pscustomobject]@{ category = 'dev-tools'; related = @('rg'); usages = @('fd <pattern>') }
            'rg' = [pscustomobject]@{ category = 'dev-tools'; related = @('fd'); usages = @('rg <pattern>') }
        }
        $snap = ConvertTo-CmdPeekSnapshot -History $history -Manager $managers -Catalog $catalog -Favorite @('fd')
        $snap.commands.Count | Should -Be 1
        @($snap.commands)[0].command | Should -Be 'fd'
        $snap.favorites | Should -Contain 'fd'
        @($snap.managers)[0].name | Should -Be 'scoop'
        $snap.gaps.Count | Should -BeGreaterThan 0
        $json = $snap | ConvertTo-Json -Depth 8
        $json | Should -Match 'fd'
    }

    It 'flags commands the tester cannot resolve as not-on-path' {
        $history = @(
            [pscustomobject]@{
                Command        = 'mystery'
                PackageName    = 'mystery'
                PackageManager = 'scoop'
                Category       = 'other'
                Usages         = @('mystery --help')
                Related        = @()
            }
        )
        $snap = ConvertTo-CmdPeekSnapshot -History $history -Manager @() -Catalog @{} -Favorite @() -Hidden @() -CommandTester { $false }
        @($snap.commands)[0].onPath | Should -BeFalse
        $snap.gaps.kind | Should -Contain 'not-on-path'
    }

    It 'does not add not-on-path when the tester succeeds' {
        $history = @(
            [pscustomobject]@{
                Command        = 'fd'
                PackageName    = 'fd'
                PackageManager = 'scoop'
                Category       = 'dev-tools'
                Usages         = @('fd <pattern> # Find files')
                Related        = @()
            }
        )
        $snap = ConvertTo-CmdPeekSnapshot -History $history -Manager @() -Catalog @{} -Favorite @() -Hidden @() -CommandTester { $true }
        @($snap.commands)[0].onPath | Should -BeTrue
        @($snap.gaps | Where-Object { $_.kind -eq 'not-on-path' }).Count | Should -Be 0
    }
}
