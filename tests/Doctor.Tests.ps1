#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\cmdpeek.psd1') -Force
    $script:examples = Join-Path $PSScriptRoot '..\examples\usage-examples.json'
}

Describe 'Get-CmdPeekVersion' {
    It 'reports the module version from the manifest' {
        $manifest = Join-Path $PSScriptRoot '..\src\cmdpeek.psd1'
        Get-CmdPeekModuleVersion -ManifestPath $manifest | Should -Match '^\d+\.\d+\.\d+'
    }

    It 'reports the MCP version from package.json' {
        $pkg = Join-Path $PSScriptRoot '..\mcp\package.json'
        Get-CmdPeekMcpVersion -PackageJsonPath $pkg | Should -Match '^\d+\.\d+\.\d+'
    }

    It 'keeps the module and the MCP server on the same version' {
        $ver = Get-CmdPeekVersion
        $ver.module | Should -Be $ver.mcp
        $ver.inSync | Should -BeTrue
    }

    It 'flags version drift between the module and the MCP server' {
        $pkg = Join-Path $TestDrive 'drift-package.json'
        '{"name":"@cmdpeek/mcp","version":"9.9.9"}' | Set-Content -LiteralPath $pkg -Encoding UTF8

        $ver = Get-CmdPeekVersion -PackageJsonPath $pkg
        $ver.mcp | Should -Be '9.9.9'
        $ver.inSync | Should -BeFalse
    }

    It 'treats a missing MCP package.json as in sync rather than as drift' {
        $ver = Get-CmdPeekVersion -PackageJsonPath (Join-Path $TestDrive 'nope/package.json')
        $ver.mcp | Should -BeNullOrEmpty
        $ver.inSync | Should -BeTrue
    }
}

Describe 'Get-CmdPeekDoctorReport' {
    BeforeEach {
        $script:data = Join-Path $TestDrive ('doctor-' + [guid]::NewGuid().ToString('N'))
    }

    It 'reports a writable data directory it had to create' {
        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples -HistoryPath @()

        $report.dataDirectory.path | Should -Be $script:data
        $report.dataDirectory.writable | Should -BeTrue
    }

    It 'splits package managers into present and missing' {
        $tester = { param($Name) $Name -eq 'scoop' }
        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples `
            -CommandTester $tester -HistoryPath @()

        $report.managers.present | Should -Contain 'scoop'
        $report.managers.missing | Should -Contain 'winget'
        $report.managers.present | Should -Not -Contain 'winget'
    }

    It 'counts catalog commands, builtins, and kits' {
        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples -HistoryPath @()

        $report.catalog.commands | Should -BeGreaterThan 0
        $report.catalog.builtins | Should -BeGreaterThan 0
        $report.catalog.kits | Should -BeGreaterThan 0
    }

    It 'finds no catalog validation errors in the shipped catalog' {
        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples -HistoryPath @()

        @($report.catalog.errors) | Should -BeNullOrEmpty
    }

    It 'surfaces catalog validation errors as problems' {
        $bad = Join-Path $TestDrive 'bad-catalog.json'
        '{"commands":{"broken":{"usages":[],"related":["nosuchtool"]}}}' |
            Set-Content -LiteralPath $bad -Encoding UTF8

        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $bad -HistoryPath @()

        @($report.catalog.errors).Count | Should -BeGreaterThan 0
        ($report.problems -join "`n") | Should -Match 'validation error'
    }

    It 'reports every cache file with an age, and absent ones as absent' {
        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples -HistoryPath @()

        @($report.caches).name | Should -Contain 'inventory'
        @($report.caches).name | Should -Contain 'help-text'
        @($report.caches | Where-Object { $_.name -eq 'inventory' })[0].exists | Should -BeFalse

        Save-CmdPeekInventoryCache -Snapshot ([pscustomobject]@{ commands = @() }) -DataDirectory $script:data
        $again = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples -HistoryPath @()
        $cache = @($again.caches | Where-Object { $_.name -eq 'inventory' })[0]
        $cache.exists | Should -BeTrue
        $cache.sizeBytes | Should -BeGreaterThan 0
        $cache.ageSeconds | Should -BeGreaterOrEqual 0
    }

    It 'reports the inventory cache TTL that is actually in effect' {
        $state = Get-CmdPeekState -DataDirectory $script:data
        $state.InventoryCacheSeconds = 900
        Save-CmdPeekState -State $state -DataDirectory $script:data

        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples -HistoryPath @()
        $report.cacheSeconds | Should -Be 900
    }

    It 'counts the lines in a readable history file' {
        $hist = Join-Path $TestDrive 'doctor-history.txt'
        @('fd foo', 'jq .', 'rg bar') | Set-Content -LiteralPath $hist -Encoding UTF8

        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples -HistoryPath @($hist)

        $entry = @($report.history)[0]
        $entry.readable | Should -BeTrue
        $entry.lines | Should -Be 3
        ($report.problems -join "`n") | Should -Not -Match 'readable shell history'
    }

    It 'flags a missing history file as a problem' {
        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples `
            -HistoryPath @((Join-Path $TestDrive 'no-such-history.txt'))

        ($report.problems -join "`n") | Should -Match 'readable shell history'
    }

    It 'counts entries in the learned catalog overlay' {
        Save-CmdPeekLearnedCatalogEntry -Command 'widgetcli' -Usages @('widgetcli build .') `
            -DataDirectory $script:data | Should -BeTrue

        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples -HistoryPath @()
        $report.catalog.learnedEntries | Should -Be 1
    }

    It 'omits timings unless asked' {
        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples -HistoryPath @()
        @($report.timings) | Should -BeNullOrEmpty
    }

    It 'measures every scan stage when -Timing is passed' {
        $tester = { param($Name) $false }
        $report = Get-CmdPeekDoctorReport -DataDirectory $script:data -ExamplesPath $script:examples `
            -CommandTester $tester -HistoryPath @() -Timing

        @($report.timings).stage | Should -Contain 'package managers'
        @($report.timings).stage | Should -Contain 'PATH scan'
        @($report.timings).stage | Should -Contain 'gap analysis'
        foreach ($t in @($report.timings)) { $t.milliseconds | Should -BeGreaterOrEqual 0 }
    }
}

Describe 'Format-CmdPeekDoctorReport' {
    It 'renders a clean report as having no problems' {
        $report = [pscustomobject]@{
            version       = [pscustomobject]@{ module = '1.2.3'; mcp = '1.2.3'; inSync = $true; powerShell = '5.1'; os = 'windows' }
            dataDirectory = [pscustomobject]@{ path = 'C:\data'; exists = $true; writable = $true }
            managers      = [pscustomobject]@{ present = @('scoop'); missing = @('winget') }
            catalog       = [pscustomobject]@{ commands = 10; kits = 2; builtins = 3; learnedEntries = 0; loadError = $null; errors = @() }
            caches        = @([pscustomobject]@{ name = 'inventory'; exists = $false; sizeBytes = 0; ageSeconds = $null })
            cacheSeconds  = 120
            history       = @([pscustomobject]@{ path = 'h.txt'; readable = $true; lines = 5 })
            profileHint   = [pscustomobject]@{ path = 'p.ps1'; present = $true }
            timings       = @()
            problems      = @()
        }

        $text = Format-CmdPeekDoctorReport -Report $report
        $text | Should -Match 'cmdpeek 1\.2\.3'
        $text | Should -Match 'present  scoop'
        $text | Should -Match 'missing  winget'
        $text | Should -Match 'inventory\s+absent'
        $text | Should -Match '5 lines'
        $text | Should -Match 'Profile hint\s+installed'
        $text | Should -Match 'No problems found\.'
    }

    It 'renders version drift and problems' {
        $report = [pscustomobject]@{
            version       = [pscustomobject]@{ module = '1.2.3'; mcp = '9.9.9'; inSync = $false; powerShell = '5.1'; os = 'windows' }
            dataDirectory = [pscustomobject]@{ path = 'C:\data'; exists = $false; writable = $false }
            managers      = [pscustomobject]@{ present = @(); missing = @('scoop') }
            catalog       = [pscustomobject]@{ commands = 0; kits = 0; builtins = 0; learnedEntries = 0; loadError = 'boom'; errors = @('bad thing') }
            caches        = @()
            cacheSeconds  = 0
            history       = @()
            profileHint   = [pscustomobject]@{ path = 'p.ps1'; present = $false }
            timings       = @()
            problems      = @('one', 'two')
        }

        $text = Format-CmdPeekDoctorReport -Report $report
        $text | Should -Match 'versions disagree'
        $text | Should -Match 'NOT WRITABLE'
        $text | Should -Match 'present  none'
        $text | Should -Match '! boom'
        $text | Should -Match '! bad thing'
        $text | Should -Match 'none found'
        $text | Should -Match '2 problem'
        $text | Should -Match '- one'
    }
}

Describe 'Invoke-CmdPeek -Doctor and -Version' {
    It 'prints a human doctor report without scanning the machine' {
        $text = Invoke-CmdPeek -Doctor -NonInteractive `
            -DataDirectory (Join-Path $TestDrive 'invoke-doctor') `
            -ExamplesPath $script:examples `
            -HistoryPath @() | Out-String

        $text | Should -Match 'Data directory'
        $text | Should -Match 'Package managers'
        $text | Should -Match 'Catalog '
    }

    It 'emits a doctor report as JSON' {
        $report = Invoke-CmdPeek -Doctor -Json -NonInteractive `
            -DataDirectory (Join-Path $TestDrive 'invoke-doctor-json') `
            -ExamplesPath $script:examples `
            -HistoryPath @() | Out-String | ConvertFrom-Json

        $report.PSObject.Properties.Name | Should -Contain 'problems'
        $report.version.module | Should -Match '^\d+\.\d+\.\d+'
    }

    It 'prints the version on -Version' {
        $text = Invoke-CmdPeek -Version -NonInteractive | Out-String
        $text | Should -Match 'cmdpeek \d+\.\d+\.\d+'
        $text | Should -Match 'mcp \d+\.\d+\.\d+'
    }

    It 'emits the version as JSON' {
        $ver = Invoke-CmdPeek -Version -Json -NonInteractive | Out-String | ConvertFrom-Json
        $ver.module | Should -Match '^\d+\.\d+\.\d+'
        $ver.inSync | Should -BeTrue
    }
}
