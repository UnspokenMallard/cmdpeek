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
        $prevKey = $env:CMDPEEK_OPENAI_API_KEY
        $prevMock = $env:CMDPEEK_OPENAI_MOCK_PATH
        try {
            Remove-Item Env:CMDPEEK_OPENAI_API_KEY -ErrorAction SilentlyContinue
            Remove-Item Env:CMDPEEK_OPENAI_MOCK_PATH -ErrorAction SilentlyContinue
            $examples = @(Get-CmdPeekUsageExample -Command 'some-new-cli' -Catalog $script:catalog)
            $examples.Count | Should -Be 0
        }
        finally {
            if ($null -eq $prevKey) { Remove-Item Env:CMDPEEK_OPENAI_API_KEY -ErrorAction SilentlyContinue }
            else { $env:CMDPEEK_OPENAI_API_KEY = $prevKey }
            if ($null -eq $prevMock) { Remove-Item Env:CMDPEEK_OPENAI_MOCK_PATH -ErrorAction SilentlyContinue }
            else { $env:CMDPEEK_OPENAI_MOCK_PATH = $prevMock }
        }
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
        $systemRoot = [string]$env:SystemRoot
        $comSpec = [string]$env:ComSpec
        $notepad = $null
        if (-not [string]::IsNullOrWhiteSpace($systemRoot)) {
            $notepad = Join-Path $systemRoot 'System32\notepad.exe'
        }
        if ([string]::IsNullOrWhiteSpace($notepad) -or -not (Test-Path -LiteralPath $notepad)) {
            if ([string]::IsNullOrWhiteSpace($comSpec) -or -not (Test-Path -LiteralPath $comSpec)) {
                Set-ItResult -Skipped -Because 'Windows PE test binaries are not available on this OS'
                return
            }
        }
        if ($notepad -and (Test-Path -LiteralPath $notepad)) {
            Get-CmdPeekPeSubsystem -Path $notepad | Should -Be 2
        }
        if (-not [string]::IsNullOrWhiteSpace($comSpec) -and (Test-Path -LiteralPath $comSpec)) {
            Get-CmdPeekPeSubsystem -Path $comSpec | Should -Be 3
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

Describe 'Get-CmdPeekCatalogKits' {
    It 'returns empty hashtable when the file is missing' {
        $kits = Get-CmdPeekCatalogKits -Path (Join-Path $TestDrive 'no-such-kits.json')
        $kits.Count | Should -Be 0
    }

    It 'returns empty hashtable when kits is absent' {
        $path = Join-Path $TestDrive 'commands-only.json'
        '{"commands":{"fd":{"category":"dev-tools","usages":["fd x"]}}}' | Set-Content -LiteralPath $path -Encoding UTF8
        $kits = Get-CmdPeekCatalogKits -Path $path
        $kits.Count | Should -Be 0
        $catalog = Get-CmdPeekExampleCatalog -Path $path
        $catalog.ContainsKey('fd') | Should -BeTrue
    }

    It 'returns empty hashtable for invalid JSON' {
        $path = Join-Path $TestDrive 'bad.json'
        '{' | Set-Content -LiteralPath $path -Encoding UTF8
        (Get-CmdPeekCatalogKits -Path $path).Count | Should -Be 0
    }

    It 'loads kits and keeps a one-element member list as an array' {
        $path = Join-Path $TestDrive 'kits.json'
        @'
{
  "kits": {
    "solo": ["fd"],
    "media": ["ffmpeg", "yt-dlp"]
  }
}
'@ | Set-Content -LiteralPath $path -Encoding UTF8
        $kits = Get-CmdPeekCatalogKits -Path $path
        @($kits['solo']).Count | Should -Be 1
        @($kits['solo'])[0] | Should -Be 'fd'
        @($kits['media']).Count | Should -Be 2
        @($kits['media']) | Should -Contain 'ffmpeg'
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

Describe 'Get-CmdPeekOpenAiExample' {
    It 'uses an injectable HTTP runner and caches usages under the data directory' {
        $prevKey = $env:CMDPEEK_OPENAI_API_KEY
        $prevMock = $env:CMDPEEK_OPENAI_MOCK_PATH
        $prevModel = $env:CMDPEEK_OPENAI_MODEL
        try {
            Remove-Item Env:CMDPEEK_OPENAI_MOCK_PATH -ErrorAction SilentlyContinue
            $env:CMDPEEK_OPENAI_API_KEY = 'sk-test-not-real'
            $env:CMDPEEK_OPENAI_MODEL = 'gpt-4o-mini'
            $data = Join-Path $TestDrive 'openai-live-cache'
            New-Item -ItemType Directory -Force -Path $data | Out-Null
            $script:capturedUri = $null
            $script:capturedAuth = $null
            $runner = {
                param($Uri, $Headers, $Body)
                $script:capturedUri = [string]$Uri
                $script:capturedAuth = [string]$Headers.Authorization
                return [pscustomobject]@{
                    choices = @(
                        [pscustomobject]@{
                            message = [pscustomobject]@{
                                content = '{"usages":["widget-cli status  # Show worker status","widget-cli run --dry  # Preview"]}'
                            }
                        }
                    )
                }
            }
            $usages = @(Get-CmdPeekOpenAiExample -Command 'widget-cli' -Count 2 -DataDirectory $data -HttpRunner $runner)
            $usages.Count | Should -Be 2
            $usages[0] | Should -Match 'widget-cli status'
            $script:capturedUri | Should -Match 'chat/completions'
            $script:capturedAuth | Should -Match 'Bearer sk-test-not-real'
            $cache = Join-Path $data 'openai-examples.json'
            Test-Path -LiteralPath $cache | Should -BeTrue
            $raw = Get-Content -LiteralPath $cache -Raw -Encoding UTF8 | ConvertFrom-Json
            @($raw.commands.'widget-cli'.usages)[0] | Should -Match 'widget-cli status'
        }
        finally {
            if ($null -eq $prevKey) { Remove-Item Env:CMDPEEK_OPENAI_API_KEY -ErrorAction SilentlyContinue }
            else { $env:CMDPEEK_OPENAI_API_KEY = $prevKey }
            if ($null -eq $prevMock) { Remove-Item Env:CMDPEEK_OPENAI_MOCK_PATH -ErrorAction SilentlyContinue }
            else { $env:CMDPEEK_OPENAI_MOCK_PATH = $prevMock }
            if ($null -eq $prevModel) { Remove-Item Env:CMDPEEK_OPENAI_MODEL -ErrorAction SilentlyContinue }
            else { $env:CMDPEEK_OPENAI_MODEL = $prevModel }
        }
    }

    It 'does not call OpenAI when SkipHelpProbe is set' {
        $prevKey = $env:CMDPEEK_OPENAI_API_KEY
        $prevMock = $env:CMDPEEK_OPENAI_MOCK_PATH
        try {
            Remove-Item Env:CMDPEEK_OPENAI_MOCK_PATH -ErrorAction SilentlyContinue
            $env:CMDPEEK_OPENAI_API_KEY = 'sk-test-not-real'
            $script:openaiCalled = $false
            $runner = {
                $script:openaiCalled = $true
                throw 'network should not run'
            }
            $usages = @(Get-CmdPeekUsageExample -Command 'no-such-cli-xyz' -Catalog @{} -SkipHelpProbe -OpenAiRunner $runner)
            $usages.Count | Should -Be 0
            $script:openaiCalled | Should -BeFalse
        }
        finally {
            if ($null -eq $prevKey) { Remove-Item Env:CMDPEEK_OPENAI_API_KEY -ErrorAction SilentlyContinue }
            else { $env:CMDPEEK_OPENAI_API_KEY = $prevKey }
            if ($null -eq $prevMock) { Remove-Item Env:CMDPEEK_OPENAI_MOCK_PATH -ErrorAction SilentlyContinue }
            else { $env:CMDPEEK_OPENAI_MOCK_PATH = $prevMock }
        }
    }

    It 'skips the live API when CMDPEEK_OPENAI_MOCK_PATH is set' {
        $prevKey = $env:CMDPEEK_OPENAI_API_KEY
        $prevMock = $env:CMDPEEK_OPENAI_MOCK_PATH
        try {
            $env:CMDPEEK_OPENAI_API_KEY = 'sk-test-not-real'
            $env:CMDPEEK_OPENAI_MOCK_PATH = (Join-Path $TestDrive 'missing-openai.json')
            $runner = { throw 'network should not run when mock path is set' }
            $usages = @(Get-CmdPeekOpenAiExample -Command 'widget-cli' -HttpRunner $runner)
            $usages.Count | Should -Be 0
        }
        finally {
            if ($null -eq $prevKey) { Remove-Item Env:CMDPEEK_OPENAI_API_KEY -ErrorAction SilentlyContinue }
            else { $env:CMDPEEK_OPENAI_API_KEY = $prevKey }
            if ($null -eq $prevMock) { Remove-Item Env:CMDPEEK_OPENAI_MOCK_PATH -ErrorAction SilentlyContinue }
            else { $env:CMDPEEK_OPENAI_MOCK_PATH = $prevMock }
        }
    }
}

Describe 'Get-CmdPeekCatalogLookup' {
    BeforeEach { Clear-CmdPeekCatalogLookup }

    It 'resolves catalog keys and aliases without walking the catalog' {
        $catalog = @{
            'rg' = [pscustomobject]@{ aliases = @('ripgrep'); category = 'dev-tools' }
            'jq' = [pscustomobject]@{ aliases = @(); category = 'dev-tools' }
        }
        (Get-CmdPeekCatalogEntry -Command 'RIPGREP' -Catalog $catalog).category | Should -Be 'dev-tools'
        Get-CmdPeekCatalogEntry -Command 'nope' -Catalog $catalog | Should -BeNullOrEmpty
        Get-CmdPeekCanonicalCommand -Command 'ripgrep' -Catalog $catalog | Should -Be 'rg'
        Get-CmdPeekCanonicalCommand -Command 'nope' -Catalog $catalog | Should -Be 'nope'
    }

    It 'prefers a real catalog key over another entry alias' {
        $catalog = @{
            'find' = [pscustomobject]@{ aliases = @(); category = 'files' }
            'fd'   = [pscustomobject]@{ aliases = @('find'); category = 'files' }
        }
        Get-CmdPeekCanonicalCommand -Command 'find' -Catalog $catalog | Should -Be 'find'
    }

    It 'rebuilds when a different catalog is passed' {
        $first = @{ 'jq' = [pscustomobject]@{ aliases = @(); category = 'dev-tools' } }
        $second = @{ 'fd' = [pscustomobject]@{ aliases = @(); category = 'files' } }
        Get-CmdPeekCatalogEntry -Command 'jq' -Catalog $first | Should -Not -BeNullOrEmpty
        Get-CmdPeekCatalogEntry -Command 'jq' -Catalog $second | Should -BeNullOrEmpty
        Get-CmdPeekCatalogEntry -Command 'fd' -Catalog $second | Should -Not -BeNullOrEmpty
    }
}

Describe 'Add-CmdPeekUsageProbe budget' {
    BeforeAll {
        $script:probeRunner = {
            param($Command)
            return "Usage: $Command [options]`n  --flag   do a thing"
        }
    }

    It 'probes every row when the limit is zero' {
        $rows = @(
            foreach ($i in 1..5) {
                [pscustomobject]@{ Command = ('tool{0}' -f $i); PackageManager = 'path'; Origin = 'path' }
            }
        )
        $out = @(Add-CmdPeekUsageProbe -History $rows -Catalog @{} -HelpRunner $script:probeRunner -Limit 0)
        @($out | Where-Object { $_.PSObject.Properties['HelpProbed'] -and $_.HelpProbed }).Count | Should -Be 5
    }

    It 'returns every row but only probes up to the limit' {
        $rows = @(
            foreach ($i in 1..10) {
                [pscustomobject]@{ Command = ('tool{0}' -f $i); PackageManager = 'path'; Origin = 'path' }
            }
        )
        $out = @(Add-CmdPeekUsageProbe -History $rows -Catalog @{} -HelpRunner $script:probeRunner -Limit 3)
        $out.Count | Should -Be 10
        @($out | Where-Object { $_.PSObject.Properties['HelpProbed'] -and $_.HelpProbed }).Count | Should -Be 3
    }

    It 'spends the budget on package rows before bin-directory scan rows' {
        $rows = @(
            [pscustomobject]@{ Command = 'scanned'; PackageManager = 'path'; Origin = 'path' }
            [pscustomobject]@{ Command = 'installed'; PackageManager = 'scoop'; Origin = 'package' }
        )
        $out = @(Add-CmdPeekUsageProbe -History $rows -Catalog @{} -HelpRunner $script:probeRunner -Limit 1)
        $probed = @($out | Where-Object { $_.PSObject.Properties['HelpProbed'] -and $_.HelpProbed })
        $probed.Count | Should -Be 1
        $probed[0].Command | Should -Be 'installed'
    }

    It 'prefers favorites over everything else' {
        $rows = @(
            [pscustomobject]@{ Command = 'installed'; PackageManager = 'scoop'; Origin = 'package'; Favorite = $false }
            [pscustomobject]@{ Command = 'starred'; PackageManager = 'path'; Origin = 'path'; Favorite = $true }
        )
        $out = @(Add-CmdPeekUsageProbe -History $rows -Catalog @{} -HelpRunner $script:probeRunner -Limit 1)
        $probed = @($out | Where-Object { $_.PSObject.Properties['HelpProbed'] -and $_.HelpProbed })
        $probed[0].Command | Should -Be 'starred'
    }

    It 'leaves unprobed rows with an empty usage list rather than no property' {
        $rows = @(
            [pscustomobject]@{ Command = 'a'; PackageManager = 'path'; Origin = 'path' }
            [pscustomobject]@{ Command = 'b'; PackageManager = 'path'; Origin = 'path' }
        )
        $out = @(Add-CmdPeekUsageProbe -History $rows -Catalog @{} -HelpRunner $script:probeRunner -Limit 1)
        foreach ($row in $out) {
            $row.PSObject.Properties['Usages'] | Should -Not -BeNullOrEmpty
        }
    }
}
