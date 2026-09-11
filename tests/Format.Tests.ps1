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

    It 'prints a cheat sheet title without an index and uses MissingRelated as gaps' {
        $history = @(
            [pscustomobject]@{
                Command        = 'fd'
                PackageManager = 'scoop'
                OnPath         = $true
                Usages         = @(
                    'fd <pattern> # Find files'
                    'fd -t f <pattern> # Find files only'
                )
                Related        = @('rg', 'fzf')
                MissingRelated = @('rg', 'fzf')
                Shims          = @('should-not-appear')
            }
        )
        $text = Format-CmdPeekQuickOutput -History $history -ExampleCount 5 -CheatSheet
        $text | Should -Match '^fd \(scoop\)'
        $text | Should -Not -Match '^\d+\. fd'
        $text | Should -Not -Match 'Last \d+ installed commands'
        $text | Should -Not -Match 'also:'
        $text | Should -Not -Match 'suggestions:'
        $text | Should -Match 'gaps: rg, fzf'
        $text | Should -Match 'Find files'
    }

    It 'prints rusty titles without indexes and includes last history line' {
        $rows = @(
            [pscustomobject]@{
                Command        = 'jq'
                PackageManager = 'scoop'
                kind           = 'stale'
                LastLine       = 'jq .'
                Usages         = @('jq . # json')
            }
        )
        $text = Format-CmdPeekQuickOutput -History $rows -ExampleCount 3 -Rusty
        $text | Should -Match 'Rusty tools \(not in recent history\):'
        $text | Should -Match '(?m)^jq \(scoop\)'
        $text | Should -Not -Match '^\d+\. jq'
        $text | Should -Match 'last: jq \.'
        $text | Should -Match 'json'
        $text | Should -Not -Match 'suggestions:'
        $text | Should -Not -Match 'gaps:'
    }

    It 'prints last used dates on rusty rows' {
        $rows = @(
            [pscustomobject]@{
                Command        = 'jq'
                PackageManager = 'scoop'
                kind           = 'stale'
                LastLine       = 'jq .'
                LastUsedAt     = [datetime]'2026-03-02T14:11:00Z'
                Usages         = @('jq . # json')
            }
        )
        $text = Format-CmdPeekQuickOutput -History $rows -ExampleCount 3 -Rusty
        $text | Should -Match 'last used: 2026-03-02'
    }
}

Describe 'Format-CmdPeekAgentExport' {
    It 'lists installed tools with aliases, substitutes, and usages' {
        $catalog = @{
            'jq' = [pscustomobject]@{
                category    = 'dev-tools'
                aliases     = @('gojq')
                substitutes = @('fx')
                usages      = @('jq . file.json  # pretty-print')
            }
        }
        $history = @(
            [pscustomobject]@{
                Command        = 'jq'
                PackageManager = 'scoop'
                Category       = 'dev-tools'
                Usages         = @('jq . file.json  # pretty-print')
                Hidden         = $false
            }
            [pscustomobject]@{
                Command        = 'secret'
                PackageManager = 'scoop'
                Hidden         = $true
                Usages         = @('secret --help')
            }
        )
        $text = Format-CmdPeekAgentExport -History $history -Catalog $catalog -Favorite @('jq')
        $text | Should -Match 'cmdpeek agent playbook'
        $text | Should -Match '### jq \(scoop\) \*'
        $text | Should -Match 'aliases: gojq'
        $text | Should -Match 'covers: fx'
        $text | Should -Match 'pretty-print'
        $text | Should -Not -Match 'secret'
    }

    It 'leaves out PATH commands that have nothing to teach, and counts them' {
        $catalog = @{
            'jq' = [pscustomobject]@{ category = 'dev-tools'; usages = @('jq . file.json') }
        }
        $history = @(
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop'; Usages = @('jq . file.json') }
            [pscustomobject]@{ Command = '['; PackageManager = 'apt'; Usages = @() }
            [pscustomobject]@{ Command = 'addgnupghome'; PackageManager = 'apt'; Usages = @() }
        )

        $text = Format-CmdPeekAgentExport -History $history -Catalog $catalog

        $text | Should -Match '### jq'
        $text | Should -Not -Match 'addgnupghome'
        $text | Should -Match '2 more commands are on PATH with no usage examples'
    }

    It 'keeps an undocumented command when it is a favorite' {
        $history = @([pscustomobject]@{ Command = 'widgetcli'; PackageManager = 'cargo'; Usages = @() })

        $text = Format-CmdPeekAgentExport -History $history -Catalog @{} -Favorite @('widgetcli')

        $text | Should -Match '### widgetcli \(cargo\) \*'
    }

    It 'keeps an undocumented command when the catalog knows the name' {
        $catalog = @{ 'widgetcli' = [pscustomobject]@{ category = 'dev-tools'; substitutes = @('gadgetcli') } }
        $history = @([pscustomobject]@{ Command = 'widgetcli'; PackageManager = 'cargo'; Usages = @() })

        $text = Format-CmdPeekAgentExport -History $history -Catalog $catalog

        $text | Should -Match '### widgetcli'
        $text | Should -Match 'covers: gadgetcli'
    }

    It 'includes everything when -IncludeUndocumented is passed' {
        $history = @(
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop'; Usages = @('jq . file.json') }
            [pscustomobject]@{ Command = 'addgnupghome'; PackageManager = 'apt'; Usages = @() }
        )

        $text = Format-CmdPeekAgentExport -History $history -Catalog @{} -IncludeUndocumented

        $text | Should -Match 'addgnupghome'
        $text | Should -Not -Match 'more commands are on PATH'
    }
}
