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

    It 'emits a kit gap for a missing member when another member is installed' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @()
            }
        )
        $catalog = @{
            'fd'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fd x') }
            'rg'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('rg x') }
        }
        $kits = @{ 'dev-tools' = @('fd', 'rg') }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits)
        $kitGaps = @($gaps | Where-Object { $_.kind -eq 'kit' })
        $kitGaps.Count | Should -Be 1
        @($kitGaps)[0].command | Should -Be 'rg'
        @(@($kitGaps)[0].relatedTo) | Should -Be @('dev-tools')
        @($kitGaps)[0].reason | Should -Match 'dev-tools'
    }

    It 'skips a kit gap when the missing name is already missing-related' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @('rg')
            }
        )
        $catalog = @{
            'fd' = [pscustomobject]@{ category = 'dev-tools'; related = @('rg'); usages = @('fd x') }
            'rg' = [pscustomobject]@{ category = 'dev-tools'; related = @('fd'); usages = @('rg x') }
        }
        $kits = @{ 'dev-tools' = @('fd', 'rg') }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits)
        @($gaps | Where-Object { $_.kind -eq 'missing-related' }).command | Should -Contain 'rg'
        @($gaps | Where-Object { $_.kind -eq 'kit' }).Count | Should -Be 0
    }

    It 'emits only one kit gap when a missing name sits in two kits' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @()
            }
        )
        $catalog = @{
            'fd'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fd x') }
            'fzf' = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fzf') }
        }
        $kits = @{
            'search'    = @('fd', 'fzf')
            'dev-tools' = @('fd', 'fzf')
        }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits)
        $kitGaps = @($gaps | Where-Object { $_.kind -eq 'kit' })
        $kitGaps.Count | Should -Be 1
        @(@($kitGaps)[0].relatedTo)[0] | Should -Be 'dev-tools'
    }

    It 'does not emit kit gaps when no member is installed' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @()
            }
        )
        $kits = @{ 'media' = @('ffmpeg', 'mpv') }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog @{} -Kits $kits)
        @($gaps | Where-Object { $_.kind -eq 'kit' }).Count | Should -Be 0
    }

    It 'does not emit kit gaps when -Kits is omitted' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @()
            }
        )
        $catalog = @{
            'fd' = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fd x') }
            'rg' = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('rg x') }
        }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog)
        @($gaps | Where-Object { $_.kind -eq 'kit' }).Count | Should -Be 0
    }

    It 'suggests at most three category neighbors and skips missing-related and kit names' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @('rg')
            }
        )
        $catalog = @{
            'fd'   = [pscustomobject]@{ category = 'dev-tools'; related = @('rg'); usages = @('fd x') }
            'rg'   = [pscustomobject]@{ category = 'dev-tools'; related = @('fd'); usages = @('rg x') }
            'fzf'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fzf') }
            'bat'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('bat') }
            'eza'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('eza') }
            'delta'= [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('delta') }
            'jq'   = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('jq') }
        }
        $kits = @{ 'dev-tools' = @('fd', 'fzf') }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits $kits)
        @($gaps | Where-Object { $_.kind -eq 'missing-related' }).command | Should -Contain 'rg'
        @($gaps | Where-Object { $_.kind -eq 'kit' }).command | Should -Contain 'fzf'
        $neighbors = @($gaps | Where-Object { $_.kind -eq 'category-neighbor' })
        $neighbors.Count | Should -Be 3
        $neighbors.command | Should -Not -Contain 'rg'
        $neighbors.command | Should -Not -Contain 'fzf'
        $neighbors.command | Should -Not -Contain 'fd'
        @($neighbors)[0].command | Should -Be 'bat'
        @(@($neighbors)[0].relatedTo) | Should -Contain 'fd'
    }

    It 'does not suggest category neighbors when nothing in that category is installed' {
        $history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageName = 'jq'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('jq .'); Related = @()
            }
        )
        $catalog = @{
            'ffmpeg' = [pscustomobject]@{ category = 'media'; related = @(); usages = @('ffmpeg') }
            'mpv'    = [pscustomobject]@{ category = 'media'; related = @(); usages = @('mpv') }
        }
        $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits @{})
        @($gaps | Where-Object { $_.kind -eq 'category-neighbor' }).Count | Should -Be 0
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
        $snap = ConvertTo-CmdPeekSnapshot -History $history -Manager $managers -Catalog $catalog -Favorite @('fd') -Kits @{}
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
        $snap = ConvertTo-CmdPeekSnapshot -History $history -Manager @() -Catalog @{} -Favorite @() -Hidden @() -CommandTester { $false } -Kits @{}
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
        $snap = ConvertTo-CmdPeekSnapshot -History $history -Manager @() -Catalog @{} -Favorite @() -Hidden @() -CommandTester { $true } -Kits @{}
        @($snap.commands)[0].onPath | Should -BeTrue
        @($snap.gaps | Where-Object { $_.kind -eq 'not-on-path' }).Count | Should -Be 0
    }

    It 'loads shipped kits when -Kits is omitted' {
        $history = @(
            [pscustomobject]@{
                Command = 'fd'; PackageName = 'fd'; PackageManager = 'scoop'
                Category = 'dev-tools'; Usages = @('fd x'); Related = @()
            }
        )
        $catalog = @{
            'fd'  = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fd x') }
            'fzf' = [pscustomobject]@{ category = 'dev-tools'; related = @(); usages = @('fzf') }
        }
        $snap = ConvertTo-CmdPeekSnapshot -History $history -Manager @() -Catalog $catalog -Favorite @() -Hidden @() -CommandTester { $true }
        @($snap.gaps | Where-Object { $_.kind -eq 'kit' -and $_.command -eq 'fzf' }).Count | Should -BeGreaterThan 0
    }
}
