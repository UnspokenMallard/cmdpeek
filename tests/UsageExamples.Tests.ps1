#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'Config.ps1')
    . (Join-Path $src 'UsageExamples.ps1')
}

Describe 'Get-CmdPeekUsageExample' {
    BeforeAll {
        $script:catalogPath = Join-Path $TestDrive 'usage-examples.json'
        $catalog = @{
            commands = @{
                'yt-dlp' = @{
                    category = 'media'
                    related  = @('ffmpeg')
                    usages   = @(
                        'yt-dlp <URL>                    # Download video'
                        'yt-dlp -f bestaudio <URL>       # Extract audio only'
                    )
                }
                'fd' = @{
                    category = 'dev-tools'
                    usages   = @(
                        'fd <pattern>                    # Find files'
                    )
                }
            }
        }
        $catalog | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:catalogPath -Encoding UTF8
        $script:catalog = Get-CmdPeekExampleCatalog -Path $script:catalogPath
    }

    It 'returns curated usages for a known command' {
        $examples = @(Get-CmdPeekUsageExample -Command 'yt-dlp' -Catalog $script:catalog -Count 2)
        $examples.Count | Should -Be 2
        $examples[0] | Should -Match 'yt-dlp <URL>'
    }

    It 'limits the number of usages' {
        $examples = @(Get-CmdPeekUsageExample -Command 'yt-dlp' -Catalog $script:catalog -Count 1)
        $examples.Count | Should -Be 1
    }

    It 'returns no usages for unknown commands instead of a generic --help line' {
        $examples = @(Get-CmdPeekUsageExample -Command 'some-new-cli' -Catalog $script:catalog)
        $examples.Count | Should -Be 0
    }

    It 'looks up category from the catalog' {
        Get-CmdPeekCommandCategory -Command 'yt-dlp' -Catalog $script:catalog | Should -Be 'media'
        Get-CmdPeekCommandCategory -Command 'unknown' -Catalog $script:catalog | Should -Be 'other'
    }

    It 'suggests related tools that are not already installed' {
        $installed = @('yt-dlp')
        $related = @(Get-CmdPeekRelatedCommand -Command 'yt-dlp' -Catalog $script:catalog -InstalledCommand $installed)
        $related | Should -Contain 'ffmpeg'
        $related | Should -Not -Contain 'yt-dlp'
    }

    It 'parses --help text when the catalog has no usages' {
        $runner = {
            param($Name)
            @"
Usage: $Name [OPTIONS] [FILENAME [SQL...]]
FILENAME is the name of an SQLite database. Defaults to :memory:.
OPTIONS include:
   -csv                 set output mode to 'csv'
   -help                show this message
   -json                set output mode to 'json'
"@
        }
        $examples = @(Get-CmdPeekUsageExample -Command 'sqlite3' -Catalog @{} -HelpRunner $runner -Count 3)
        $examples.Count | Should -Be 3
        $examples[0] | Should -Match 'sqlite3 \[OPTIONS\]'
        ($examples -join "`n") | Should -Match '-csv'
        ($examples -join "`n") | Should -Not -Match '--help'
        ($examples -join "`n") | Should -Not -Match '-help'
    }
}

Describe 'ConvertFrom-CmdPeekHelpText' {
    It 'strips a full executable path from the usage line' {
        $help = @"
Usage: C:\Users\anzes\scoop\apps\sqlite\current\sqlite3.exe [OPTIONS] [FILENAME [SQL...]]
FILENAME is the name of an SQLite database. A new database is created
if the file does not previously exist. Defaults to :memory:.
"@
        $examples = @(ConvertFrom-CmdPeekHelpText -Command 'sqlite3' -HelpText $help -Count 1)
        $examples[0] | Should -Match '^sqlite3 '
        $examples[0] | Should -Not -Match 'C:\\'
        $examples[0] | Should -Match 'database|:memory:'
    }

    It 'uses an Examples section when present' {
        $help = @"
Usage: just [OPTIONS] [ARGUMENTS]...
Examples:
  just
  just --list
  just build
"@
        $examples = @(ConvertFrom-CmdPeekHelpText -Command 'just' -HelpText $help -Count 3)
        ($examples -join "`n") | Should -Match 'just --list'
        ($examples -join "`n") | Should -Match 'just build'
        ($examples -join "`n") | Should -Not -Match '--help'
    }

    It 'parses analyzer-style usage without treating Unknown option as useful' {
        $help = @"
Unknown option: --help
Usage: sqlite3_analyzer ?--pageinfo? ?--stats? database-filename

Analyze the SQLite3 database file specified by the argument.

Options:
   --pageinfo   Show how each page of the database-file is used
   --stats      Output SQL text that creates a new database
   --version    Show the version number of SQLite
"@
        $examples = @(ConvertFrom-CmdPeekHelpText -Command 'sqlite3_analyzer' -HelpText $help -Count 3)
        $examples.Count | Should -BeGreaterThan 0
        $examples[0] | Should -Match 'sqlite3_analyzer'
        ($examples -join "`n") | Should -Match 'pageinfo|database'
        ($examples -join "`n") | Should -Not -Match 'Unknown option'
    }

    It 'returns nothing when help has no usage or examples' {
        $examples = @(ConvertFrom-CmdPeekHelpText -Command 'foo' -HelpText "error: unrecognized flag`ntry again" -Count 3)
        $examples.Count | Should -Be 0
    }

    It 'ignores crash dumps and exception stacks instead of treating them as usage' {
        $crash = @"
FATAL ERROR: Reached heap limit Allocation failed - JavaScript heap out of memory
----- Native stack trace -----
 1: 00007FF7D8897F8F node::OnFatalError+1343
Syntax error of parameter -h: Parameter is not allowed.
CmdLineException
   at LogExpert.Classes.CmdLine.Parse(String[] args)
   at LogExpert.Program.Main(String[] orgArgs)
"@
        Test-CmdPeekCrashHelpText -Text $crash | Should -BeTrue
        $examples = @(ConvertFrom-CmdPeekHelpText -Command 'logexpert' -HelpText $crash -Count 3)
        $examples.Count | Should -Be 0
    }
}

Describe 'Get-CmdPeekPeSubsystem' {
    It 'detects notepad as a GUI app and cmd as a console app' {
        $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
        $cmd = $env:ComSpec
        if (Test-Path -LiteralPath $notepad) {
            Get-CmdPeekPeSubsystem -Path $notepad | Should -Be 2
        }
        if (Test-Path -LiteralPath $cmd) {
            Get-CmdPeekPeSubsystem -Path $cmd | Should -Be 3
        }
    }
}

Describe 'Get-CmdPeekUsageExample crash isolation' {
    It 'swallows a crashing help runner and returns no usages' {
        $runner = { throw 'CmdLineException: -h is not allowed' }
        { Get-CmdPeekUsageExample -Command 'logexpert' -Catalog @{} -HelpRunner $runner } | Should -Not -Throw
        $examples = @(Get-CmdPeekUsageExample -Command 'logexpert' -Catalog @{} -HelpRunner $runner)
        $examples.Count | Should -Be 0
    }
}

Describe 'Add-CmdPeekCatalogMetadata help probing' {
    It 'does not invoke HelpRunner when SkipHelpProbe is set' {
        $runner = { throw 'should not probe help' }
        $history = @([pscustomobject]@{ Command = 'some-new-cli' })
        { @(Add-CmdPeekCatalogMetadata -History $history -Catalog @{} -HelpRunner $runner -SkipHelpProbe) } | Should -Not -Throw
        $rows = @(Add-CmdPeekCatalogMetadata -History $history -Catalog @{} -HelpRunner $runner -SkipHelpProbe)
        @($rows[0].Usages).Count | Should -Be 0
    }
}

Describe 'Add-CmdPeekUsageProbe' {
    It 'probes help only for the rows passed in' {
        $calls = New-Object System.Collections.Generic.List[string]
        $runner = {
            param($Name)
            $calls.Add($Name)
            "Usage: $Name [OPTIONS]`nDo a thing."
        }
        $alpha = [pscustomobject]@{ Command = 'alpha-cli'; Usages = @() }
        $beta = [pscustomobject]@{ Command = 'beta-cli'; Usages = @() }
        $updated = @(Add-CmdPeekUsageProbe -History @($alpha) -Catalog @{} -HelpRunner $runner)
        $calls.Count | Should -Be 1
        $calls[0] | Should -Be 'alpha-cli'
        $updated[0].Usages.Count | Should -BeGreaterThan 0
        $beta.Usages.Count | Should -Be 0
    }

    It 'does not re-probe a row that was already help-probed' {
        $calls = New-Object System.Collections.Generic.List[string]
        $runner = {
            param($Name)
            $calls.Add($Name)
            "Usage: $Name [OPTIONS]`nDo a thing."
        }
        $row = [pscustomobject]@{ Command = 'alpha-cli'; Usages = @() }
        $null = @(Add-CmdPeekUsageProbe -History @($row) -Catalog @{} -HelpRunner $runner)
        $null = @(Add-CmdPeekUsageProbe -History @($row) -Catalog @{} -HelpRunner $runner)
        $calls.Count | Should -Be 1
    }
}

Describe 'Get-CmdPeekCachedHelpText TTL' {
    It 'expires cache using CacheTtlHours from state.json' {
        $data = Join-Path $TestDrive 'ttl-short'
        New-Item -ItemType Directory -Force -Path $data | Out-Null
        $state = Get-CmdPeekDefaultState
        $state.CacheTtlHours = 1
        Save-CmdPeekState -State $state -DataDirectory $data

        @{
            'old-cli' = @{
                fetchedAt = (Get-Date).AddHours(-2).ToString('o')
                text      = 'Usage: old-cli'
            }
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'help-cache.json') -Encoding UTF8

        Get-CmdPeekCachedHelpText -Command 'old-cli' -DataDirectory $data | Should -BeNullOrEmpty
    }

    It 'returns cached help when still within CacheTtlHours' {
        $data = Join-Path $TestDrive 'ttl-long'
        New-Item -ItemType Directory -Force -Path $data | Out-Null
        $state = Get-CmdPeekDefaultState
        $state.CacheTtlHours = 24
        Save-CmdPeekState -State $state -DataDirectory $data

        @{
            'fresh-cli' = @{
                fetchedAt = (Get-Date).AddHours(-2).ToString('o')
                text      = 'Usage: fresh-cli'
            }
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'help-cache.json') -Encoding UTF8

        Get-CmdPeekCachedHelpText -Command 'fresh-cli' -DataDirectory $data | Should -Be 'Usage: fresh-cli'
    }
}
