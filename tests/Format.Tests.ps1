#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'InteractiveMode.ps1')
    . (Join-Path $src 'UsageExamples.ps1')
}

Describe 'Format-CmdPeekQuickOutput' {
    It 'omits generic --help when that is the only usage' {
        $history = @(
            [pscustomobject]@{
                Command        = 'sqlite3'
                PackageManager = 'scoop'
                Usages         = @('sqlite3 --help                       # Show command help')
                Related        = @()
            }
            [pscustomobject]@{
                Command        = 'rg'
                PackageManager = 'scoop'
                Usages         = @(
                    'rg <pattern>                    # Search recursively'
                    'rg -i <pattern>                 # Case-insensitive search'
                )
                Related        = @()
            }
        )

        $text = Format-CmdPeekQuickOutput -History $history -ExampleCount 3
        $text | Should -Match 'sqlite3 \(scoop\)'
        $text | Should -Not -Match '--help'
        $text | Should -Match 'Search recursively'
    }

    It 'shows at most 3 usages and aligns comments to one column' {
        $history = @(
            [pscustomobject]@{
                Command        = 'rg'
                PackageManager = 'scoop'
                Usages         = @(
                    'rg <pattern> # Search recursively'
                    'rg -i <pattern> # Case-insensitive search'
                    'rg -t ps1 <pattern> # Search PowerShell files'
                    'rg -l <pattern> # List matching files only'
                )
                Related        = @()
            }
            [pscustomobject]@{
                Command        = 'fzf'
                PackageManager = 'scoop'
                Usages         = @('fzf # Fuzzy-find from stdin')
                Related        = @()
            }
        )

        $text = Format-CmdPeekQuickOutput -History $history -ExampleCount 3
        $text | Should -Not -Match 'List matching files'
        $usageLines = @($text -split '\r?\n' | Where-Object { $_ -match '^\s+-  ' })
        $usageLines.Count | Should -Be 4
        $commentCols = @($usageLines | ForEach-Object { $_.IndexOf('#') })
        @($commentCols | Select-Object -Unique).Count | Should -Be 1
        $commentCols[0] | Should -BeGreaterThan 0
    }

    It 'appends not on PATH and also: shims, and uses a custom header' {
        $history = @(
            [pscustomobject]@{
                Command        = 'ffmpeg'
                PackageManager = 'scoop'
                OnPath         = $false
                Shims          = @('ffprobe', 'ffplay')
                Usages         = @('ffmpeg -i in.mp4 out.mp3  # Convert')
                Related        = @()
            }
        )
        $text = Format-CmdPeekQuickOutput -History $history -Header 'Installed since last look:'
        $text | Should -Match 'Installed since last look:'
        $text | Should -Match 'not on PATH'
        $text | Should -Match 'also: ffprobe, ffplay'
    }
}
