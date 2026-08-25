#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\cmdpeek.psd1') -Force
}

Describe 'Invoke-CmdPeek' {
    It 'prints the last N commands from fixture install roots' {
        $scoopRoot = Join-Path $TestDrive 'scoop'
        $app = Join-Path $scoopRoot 'apps\fd\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\fd')).LastWriteTime = [datetime]'2025-08-19T00:00:00'

        $examples = Join-Path $PSScriptRoot '..\examples\usage-examples.json'
        $data = Join-Path $TestDrive 'data'

        $output = Invoke-CmdPeek -Count 1 -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget') `
            -DataDirectory $data `
            -ExamplesPath $examples

        $text = $output | Out-String
        $text | Should -Match 'fd'
        $text | Should -Match 'scoop'
        $text | Should -Match 'Find files'
        # First run (null LastPeekAt): empty delta then fallback — do not require old "Last N" header
    }

    It 'shows only packages newer than LastPeekAt with Installed since last look header' {
        $scoopRoot = Join-Path $TestDrive 'scoop-delta'
        $newApp = Join-Path $scoopRoot 'apps\fd\current'
        $oldApp = Join-Path $scoopRoot 'apps\jq\current'
        New-Item -ItemType Directory -Force -Path $newApp, $oldApp | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $newApp 'manifest.json') -Encoding UTF8
        '{"version":"1.7.1","bin":"jq.exe"}' | Set-Content -Path (Join-Path $oldApp 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\fd')).LastWriteTime = [datetime]'2025-08-22T00:00:00'
        (Get-Item (Join-Path $scoopRoot 'apps\jq')).LastWriteTime = [datetime]'2025-08-19T00:00:00'

        $data = Join-Path $TestDrive 'delta-peek-data'
        $state = Get-CmdPeekState -DataDirectory $data
        $state.LastPeekAt = ([datetime]'2025-08-20T12:00:00').ToString('o')
        Save-CmdPeekState -State $state -DataDirectory $data
        $beforePeek = (Get-CmdPeekState -DataDirectory $data).LastPeekAt

        $output = Invoke-CmdPeek -Count 5 -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-delta') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-delta') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json')

        $text = $output | Out-String
        $text | Should -Match 'Installed since last look:'
        $text | Should -Match 'fd'
        $text | Should -Not -Match '(?m)^\d+\. jq '

        $after = Get-CmdPeekState -DataDirectory $data
        $after.LastPeekAt | Should -Not -BeNullOrEmpty
        $after.LastPeekAt | Should -Not -Be $beforePeek
    }

    It 'falls back to newest N when nothing is newer than LastPeekAt' {
        $scoopRoot = Join-Path $TestDrive 'scoop-fallback'
        $fdApp = Join-Path $scoopRoot 'apps\fd\current'
        $jqApp = Join-Path $scoopRoot 'apps\jq\current'
        New-Item -ItemType Directory -Force -Path $fdApp, $jqApp | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $fdApp 'manifest.json') -Encoding UTF8
        '{"version":"1.7.1","bin":"jq.exe"}' | Set-Content -Path (Join-Path $jqApp 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\fd')).LastWriteTime = [datetime]'2025-08-22T00:00:00'
        (Get-Item (Join-Path $scoopRoot 'apps\jq')).LastWriteTime = [datetime]'2025-08-19T00:00:00'

        $data = Join-Path $TestDrive 'fallback-peek-data'
        $state = Get-CmdPeekState -DataDirectory $data
        $state.LastPeekAt = ([datetime]'2025-08-23T00:00:00').ToString('o')
        Save-CmdPeekState -State $state -DataDirectory $data

        $output = Invoke-CmdPeek -Count 5 -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-fallback') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-fallback') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json')

        $text = $output | Out-String
        $text | Should -Match 'No new installs since'
        $text | Should -Match 'fd'
        $text | Should -Match 'jq'
    }

    It 'does not advance LastPeekAt or LastMcpAt on -Json' {
        $scoopRoot = Join-Path $TestDrive 'scoop-json-cursors'
        $app = Join-Path $scoopRoot 'apps\fd\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8

        $data = Join-Path $TestDrive 'json-cursor-data'
        $state = Get-CmdPeekState -DataDirectory $data
        $state.LastPeekAt = '2025-08-10T00:00:00.0000000Z'
        $state.LastMcpAt = '2025-08-11T00:00:00.0000000Z'
        Save-CmdPeekState -State $state -DataDirectory $data

        $raw = Invoke-CmdPeek -Json -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-json-c') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-json-c') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json') |
            Out-String

        $snap = $raw | ConvertFrom-Json
        $snap.PSObject.Properties.Name | Should -Contain 'lastPeekAt'
        $snap.PSObject.Properties.Name | Should -Contain 'lastMcpAt'
        ([datetime]$snap.lastPeekAt).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ') |
            Should -Be '2025-08-10T00:00:00.0000000Z'
        ([datetime]$snap.lastMcpAt).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ') |
            Should -Be '2025-08-11T00:00:00.0000000Z'

        $after = Get-CmdPeekState -DataDirectory $data
        $after.LastPeekAt | Should -Be '2025-08-10T00:00:00.0000000Z'
        $after.LastMcpAt | Should -Be '2025-08-11T00:00:00.0000000Z'
    }

    It 'emits -Json -Recent fallback payload and advances LastMcpAt only' {
        $scoopRoot = Join-Path $TestDrive 'scoop-recent'
        $app = Join-Path $scoopRoot 'apps\fd\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\fd')).LastWriteTime = [datetime]'2025-08-19T00:00:00'

        $data = Join-Path $TestDrive 'recent-data'
        $state = Get-CmdPeekState -DataDirectory $data
        $state.LastPeekAt | Should -BeNullOrEmpty
        $state.LastMcpAt | Should -BeNullOrEmpty
        Save-CmdPeekState -State $state -DataDirectory $data

        $raw = Invoke-CmdPeek -Json -Recent -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-recent') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-recent') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json') |
            Out-String

        $payload = $raw | ConvertFrom-Json
        $payload.mode | Should -Be 'fallback'
        @($payload.commands).Count | Should -BeGreaterThan 0
        @($payload.commands).command | Should -Contain 'fd'

        $after = Get-CmdPeekState -DataDirectory $data
        $after.LastMcpAt | Should -Not -BeNullOrEmpty
        $after.LastPeekAt | Should -BeNullOrEmpty
    }

    It 'keeps uncatalogued package shims when -Json -Recent filters by category after grouping' {
        $scoopRoot = Join-Path $TestDrive 'scoop-recent-cat-shim'
        $app = Join-Path $scoopRoot 'apps\ffmpeg\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"7.0.0","bin":["ffmpeg.exe","ffprobe.exe"]}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\ffmpeg')).LastWriteTime = [datetime]'2025-08-22T00:00:00'

        $data = Join-Path $TestDrive 'recent-cat-shim-data'
        $raw = Invoke-CmdPeek -Json -Recent -Category media -Since all -Count 20 -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-recent-cat') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-recent-cat') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json') |
            Out-String

        $payload = $raw | ConvertFrom-Json
        $cmds = @($payload.commands)
        $ff = @($cmds | Where-Object { $_.command -eq 'ffmpeg' })[0]
        $ff | Should -Not -BeNullOrEmpty
        @($ff.shims) | Should -Contain 'ffprobe'
    }

    It 'does not advance LastMcpAt on -Json -Recent when inventory is empty' {
        $data = Join-Path $TestDrive 'recent-empty-data'
        $state = Get-CmdPeekState -DataDirectory $data
        $state.LastMcpAt | Should -BeNullOrEmpty
        Save-CmdPeekState -State $state -DataDirectory $data

        $raw = Invoke-CmdPeek -Json -Recent -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot (Join-Path $TestDrive 'empty-scoop-recent') `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-recent-empty') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-recent-empty') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json') |
            Out-String

        $payload = $raw | ConvertFrom-Json
        @($payload.commands).Count | Should -Be 0

        $after = Get-CmdPeekState -DataDirectory $data
        $after.LastMcpAt | Should -BeNullOrEmpty
    }

    It 'does not advance LastPeekAt for -Category without -Count (flat list)' {
        $scoopRoot = Join-Path $TestDrive 'scoop-cat-flat'
        $app = Join-Path $scoopRoot 'apps\ffmpeg\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"7.0.0","bin":"ffmpeg.exe"}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\ffmpeg')).LastWriteTime = [datetime]'2025-08-22T00:00:00'

        $data = Join-Path $TestDrive 'cat-flat-data'
        $seeded = '2025-08-10T00:00:00.0000000Z'
        $state = Get-CmdPeekState -DataDirectory $data
        $state.LastPeekAt = $seeded
        Save-CmdPeekState -State $state -DataDirectory $data

        $null = Invoke-CmdPeek -Category media -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-cat-flat') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-cat-flat') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json')

        $after = Get-CmdPeekState -DataDirectory $data
        $after.LastPeekAt | Should -Be $seeded
    }

    It 'throws on unparseable -Since without updating LastPeekAt' {
        $scoopRoot = Join-Path $TestDrive 'scoop-since-bad'
        $app = Join-Path $scoopRoot 'apps\fd\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8

        $data = Join-Path $TestDrive 'since-bad-data'
        $state = Get-CmdPeekState -DataDirectory $data
        $state.LastPeekAt = '2025-08-10T00:00:00.0000000Z'
        Save-CmdPeekState -State $state -DataDirectory $data

        { Invoke-CmdPeek -Count 5 -Since 'bogus' -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-since-bad') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-since-bad') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json')
        } | Should -Throw -ExpectedMessage '*Invalid -Since*'

        $after = Get-CmdPeekState -DataDirectory $data
        $after.LastPeekAt | Should -Be '2025-08-10T00:00:00.0000000Z'
    }

    It 'probes --help only for the primary bin when a package has multiple commands' {
        $scoopRoot = Join-Path $TestDrive 'scoop-shim-probe'
        $app = Join-Path $scoopRoot 'apps\ffmpeg\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"7.0.0","bin":["ffprobe.exe","ffmpeg.exe"]}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\ffmpeg')).LastWriteTime = [datetime]'2025-08-22T00:00:00'

        $calls = New-Object System.Collections.Generic.List[string]
        $runner = {
            param($Name)
            $calls.Add($Name)
            "Usage: $Name [OPTIONS]`nDo a thing."
        }

        $emptyExamples = Join-Path $TestDrive 'empty-examples-shim.json'
        '{"commands":{}}' | Set-Content -LiteralPath $emptyExamples -Encoding UTF8

        # Count high enough that ungrouped history would include both bins
        $null = Invoke-CmdPeek -Count 5 -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-shim') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-shim') `
            -DataDirectory (Join-Path $TestDrive 'shim-probe-data') `
            -ExamplesPath $emptyExamples `
            -HelpRunner $runner

        $calls | Should -Contain 'ffmpeg'
        $calls | Should -Not -Contain 'ffprobe'
        $calls.Count | Should -Be 1
    }

    It 'omits commands hidden in interactive mode from -n quick view' {
        $scoopRoot = Join-Path $TestDrive 'scoop-hide'
        $fdApp = Join-Path $scoopRoot 'apps\fd\current'
        $jqApp = Join-Path $scoopRoot 'apps\jq\current'
        New-Item -ItemType Directory -Force -Path $fdApp, $jqApp | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $fdApp 'manifest.json') -Encoding UTF8
        '{"version":"1.7.1","bin":"jq.exe"}' | Set-Content -Path (Join-Path $jqApp 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\fd')).LastWriteTime = [datetime]'2025-08-20T00:00:00'
        (Get-Item (Join-Path $scoopRoot 'apps\jq')).LastWriteTime = [datetime]'2025-08-19T00:00:00'

        $data = Join-Path $TestDrive 'hide-data'
        $state = Get-CmdPeekState -DataDirectory $data
        $state = Set-CmdPeekHidden -State $state -Command 'fd' -Hidden $true
        Save-CmdPeekState -State $state -DataDirectory $data

        $output = Invoke-CmdPeek -Count 5 -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-hide') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-hide') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json')

        $text = $output | Out-String
        $text | Should -Match 'jq'
        $text | Should -Not -Match 'fd'
    }

    It 'probes --help only for the commands included in -n quick view' {
        $scoopRoot = Join-Path $TestDrive 'scoop-lazy'
        $newApp = Join-Path $scoopRoot 'apps\alpha-cli\current'
        $oldApp = Join-Path $scoopRoot 'apps\beta-cli\current'
        New-Item -ItemType Directory -Force -Path $newApp, $oldApp | Out-Null
        '{"version":"1.0.0","bin":"alpha-cli.exe"}' | Set-Content -Path (Join-Path $newApp 'manifest.json') -Encoding UTF8
        '{"version":"1.0.0","bin":"beta-cli.exe"}' | Set-Content -Path (Join-Path $oldApp 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\alpha-cli')).LastWriteTime = [datetime]'2025-08-22T00:00:00'
        (Get-Item (Join-Path $scoopRoot 'apps\beta-cli')).LastWriteTime = [datetime]'2025-08-21T00:00:00'

        $calls = New-Object System.Collections.Generic.List[string]
        $runner = {
            param($Name)
            $calls.Add($Name)
            "Usage: $Name [OPTIONS]`nDo a thing."
        }

        $emptyExamples = Join-Path $TestDrive 'empty-examples.json'
        '{"commands":{}}' | Set-Content -LiteralPath $emptyExamples -Encoding UTF8

        $null = Invoke-CmdPeek -Count 1 -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-lazy') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-lazy') `
            -DataDirectory (Join-Path $TestDrive 'lazy-data') `
            -ExamplesPath $emptyExamples `
            -HelpRunner $runner

        $calls | Should -Contain 'alpha-cli'
        $calls | Should -Not -Contain 'beta-cli'
        $calls.Count | Should -Be 1
    }

    It 'emits JSON inventory for MCP consumers' {
        $scoopRoot = Join-Path $TestDrive 'scoop-json'
        $app = Join-Path $scoopRoot 'apps\fd\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8

        $raw = Invoke-CmdPeek -Json -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget') `
            -DataDirectory (Join-Path $TestDrive 'json-data') `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json') |
            Out-String

        $snap = $raw | ConvertFrom-Json
        $snap.commands.command | Should -Contain 'fd'
        $snap.PSObject.Properties.Name | Should -Contain 'gaps'
    }

    It 'reports uninstalled commands without prompting when NonInteractive' {
        $data = Join-Path $TestDrive 'missing'
        $previous = [pscustomobject]@{
            Favorites               = @()
            PreferredPackageManager = $null
            TelemetryEnabled        = $false
            CacheTtlHours           = 24
            LastScan                = $null
            Commands                = @(
                [pscustomobject]@{
                    Command        = 'yt-dlp'
                    PackageName    = 'yt-dlp'
                    PackageManager = 'scoop'
                    InstallDate    = [datetime]'2025-08-20T00:00:00Z'
                }
            )
            ExampleUsageCounts      = [pscustomobject]@{}
            SchemaVersion           = 1
        }
        Save-CmdPeekState -State $previous -DataDirectory $data

        $warnings = @()
        $output = Invoke-CmdPeek -Count 5 -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot (Join-Path $TestDrive 'empty-scoop') `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget') `
            -DataDirectory $data `
            -WarningVariable warnings `
            -WarningAction Continue | Out-String

        ($warnings -join "`n") | Should -Match 'yt-dlp'
        ($warnings -join "`n") | Should -Match 'uninstalled'
    }

    It 'does not prompt about uninstalls in -n quick view' {
        $data = Join-Path $TestDrive 'missing-quick'
        $previous = [pscustomobject]@{
            Favorites               = @()
            PreferredPackageManager = $null
            TelemetryEnabled        = $false
            CacheTtlHours           = 24
            LastScan                = $null
            Commands                = @(
                [pscustomobject]@{
                    Command        = 'yt-dlp'
                    PackageName    = 'yt-dlp'
                    PackageManager = 'scoop'
                    InstallDate    = [datetime]'2025-08-20T00:00:00Z'
                }
            )
            ExampleUsageCounts      = [pscustomobject]@{}
            SchemaVersion           = 1
        }
        Save-CmdPeekState -State $previous -DataDirectory $data

        Mock -ModuleName cmdpeek -CommandName Read-Host -MockWith { 'n' }

        $warnings = @()
        $output = Invoke-CmdPeek -Count 5 `
            -EnabledManagers @('scoop') `
            -ScoopRoot (Join-Path $TestDrive 'empty-scoop-quick') `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-quick') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-quick') `
            -DataDirectory $data `
            -WarningVariable warnings `
            -WarningAction Continue | Out-String

        Should -Invoke -CommandName Read-Host -ModuleName cmdpeek -Times 0
        ($warnings -join "`n") | Should -Not -Match 'uninstalled'
        $output | Should -Not -Match 'Reinstall'
    }

    It 'prompts about uninstalls in interactive mode' {
        $data = Join-Path $TestDrive 'missing-interactive'
        $previous = [pscustomobject]@{
            Favorites               = @()
            PreferredPackageManager = $null
            TelemetryEnabled        = $false
            CacheTtlHours           = 24
            LastScan                = $null
            Commands                = @(
                [pscustomobject]@{
                    Command        = 'yt-dlp'
                    PackageName    = 'yt-dlp'
                    PackageManager = 'scoop'
                    InstallDate    = [datetime]'2025-08-20T00:00:00Z'
                }
            )
            ExampleUsageCounts      = [pscustomobject]@{}
            SchemaVersion           = 1
        }
        Save-CmdPeekState -State $previous -DataDirectory $data

        Mock -ModuleName cmdpeek -CommandName Read-Host -MockWith { 'n' }
        Mock -ModuleName cmdpeek -CommandName Invoke-CmdPeekInteractive -MockWith { }

        Invoke-CmdPeek -Interactive `
            -EnabledManagers @('scoop') `
            -ScoopRoot (Join-Path $TestDrive 'empty-scoop-interactive') `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-interactive') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-interactive') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json')

        Should -Invoke -CommandName Read-Host -ModuleName cmdpeek -Times 1
    }

    It 'does not probe --help for the full inventory before interactive mode' {
        $scoopRoot = Join-Path $TestDrive 'scoop-tui-lazy'
        $newApp = Join-Path $scoopRoot 'apps\alpha-cli\current'
        $oldApp = Join-Path $scoopRoot 'apps\beta-cli\current'
        New-Item -ItemType Directory -Force -Path $newApp, $oldApp | Out-Null
        '{"version":"1.0.0","bin":"alpha-cli.exe"}' | Set-Content -Path (Join-Path $newApp 'manifest.json') -Encoding UTF8
        '{"version":"1.0.0","bin":"beta-cli.exe"}' | Set-Content -Path (Join-Path $oldApp 'manifest.json') -Encoding UTF8

        $calls = New-Object System.Collections.Generic.List[string]
        $runner = {
            param($Name)
            $calls.Add($Name)
            "Usage: $Name [OPTIONS]`nDo a thing."
        }

        Mock -ModuleName cmdpeek -CommandName Invoke-CmdPeekInteractive -MockWith { }

        $emptyExamples = Join-Path $TestDrive 'empty-examples-tui.json'
        '{"commands":{}}' | Set-Content -LiteralPath $emptyExamples -Encoding UTF8

        Invoke-CmdPeek -Interactive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-tui-lazy') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-tui-lazy') `
            -DataDirectory (Join-Path $TestDrive 'tui-lazy-data') `
            -ExamplesPath $emptyExamples `
            -HelpRunner $runner

        $calls.Count | Should -Be 0
    }

    It 'hides and unhides a command from -n via -Hide and -Unhide' {
        $data = Join-Path $TestDrive 'hide-cli'
        Invoke-CmdPeek -Hide 'LogExpert' -DataDirectory $data -NonInteractive
        $state = Get-CmdPeekState -DataDirectory $data
        @($state.Hidden) | Should -Contain 'LogExpert'

        Invoke-CmdPeek -Unhide 'LogExpert' -DataDirectory $data -NonInteractive
        $state = Get-CmdPeekState -DataDirectory $data
        @($state.Hidden) | Should -Not -Contain 'LogExpert'
    }

    It 'stars and unstars a command via -Star and -Unstar' {
        $data = Join-Path $TestDrive 'star-cli'
        Invoke-CmdPeek -Star 'fd' -DataDirectory $data -NonInteractive
        $state = Get-CmdPeekState -DataDirectory $data
        @($state.Favorites) | Should -Contain 'fd'

        Invoke-CmdPeek -Unstar 'fd' -DataDirectory $data -NonInteractive
        $state = Get-CmdPeekState -DataDirectory $data
        @($state.Favorites) | Should -Not -Contain 'fd'
    }

    It 'remembers the package manager used with -Reinstall' {
        Mock -ModuleName cmdpeek -CommandName Install-CmdPeekTrackedPackage -MockWith { 0 }

        $data = Join-Path $TestDrive 'pref-mgr'
        Invoke-CmdPeek -Reinstall 'fd' -Manager 'chocolatey' -DataDirectory $data -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot (Join-Path $TestDrive 'empty-scoop-pref') `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-pref') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-pref')

        $state = Get-CmdPeekState -DataDirectory $data
        $state.PreferredPackageManager | Should -Be 'chocolatey'
    }

    It 'shows a cheat sheet for a unique exact command search without advancing LastPeekAt' {
        $scoopRoot = Join-Path $TestDrive 'scoop-exact-fd'
        $app = Join-Path $scoopRoot 'apps\fd\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\fd')).LastWriteTime = [datetime]'2025-08-19T00:00:00'

        $data = Join-Path $TestDrive 'exact-fd-data'
        $seeded = '2025-08-10T00:00:00.0000000Z'
        $state = Get-CmdPeekState -DataDirectory $data
        $state.LastPeekAt = $seeded
        Save-CmdPeekState -State $state -DataDirectory $data

        $output = Invoke-CmdPeek -Search fd -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-exact-fd') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-exact-fd') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json')

        $text = $output | Out-String
        $text | Should -Match 'fd \(scoop\)'
        $text | Should -Match 'Find files'
        $text | Should -Not -Match 'Last \d+ installed commands'
        $text | Should -Not -Match '(?m)^\d+\. fd'

        $after = Get-CmdPeekState -DataDirectory $data
        $after.LastPeekAt | Should -Be $seeded
    }

    It 'lists dual-manager exact matches as a numbered list without cheat sheet' {
        $scoopRoot = Join-Path $TestDrive 'scoop-dual-jq'
        $chocoRoot = Join-Path $TestDrive 'choco-dual-jq'
        $scoopApp = Join-Path $scoopRoot 'apps\jq\current'
        $lib = Join-Path $chocoRoot 'lib\jq'
        $bin = Join-Path $chocoRoot 'bin'
        New-Item -ItemType Directory -Force -Path $scoopApp, $lib, $bin | Out-Null
        '{"version":"1.7.1","bin":"jq.exe"}' | Set-Content -Path (Join-Path $scoopApp 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\jq')).LastWriteTime = [datetime]'2025-08-19T00:00:00'
        '<package><metadata><id>jq</id><version>1.7.1</version></metadata></package>' |
            Set-Content -Path (Join-Path $lib 'jq.nuspec') -Encoding UTF8
        New-Item -ItemType File -Force -Path (Join-Path $bin 'jq.exe') | Out-Null
        (Get-Item $lib).LastWriteTime = [datetime]'2025-08-18T09:00:00'

        $output = Invoke-CmdPeek -Search jq -NonInteractive `
            -EnabledManagers @('scoop', 'chocolatey') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot $chocoRoot `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-dual-jq') `
            -DataDirectory (Join-Path $TestDrive 'dual-jq-data') `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json')

        $text = $output | Out-String
        $text | Should -Match 'scoop'
        $text | Should -Match 'chocolatey'
        $text | Should -Match '(?m)^\d+\. jq'
        (@([regex]::Matches($text, '(?m)^\d+\. jq')).Count) | Should -Be 2
    }

    It 'falls back to numbered list when search matches usage text only' {
        $scoopRoot = Join-Path $TestDrive 'scoop-usage-pattern'
        $app = Join-Path $scoopRoot 'apps\fd\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\fd')).LastWriteTime = [datetime]'2025-08-19T00:00:00'

        $output = Invoke-CmdPeek -Search pattern -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-usage-pattern') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-usage-pattern') `
            -DataDirectory (Join-Path $TestDrive 'usage-pattern-data') `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json')

        $text = $output | Out-String
        $text | Should -Match 'fd'
        $text | Should -Not -Match '(?m)^pattern \('
    }

    It 'shows a cheat sheet for a hidden command on exact search without advancing LastPeekAt' {
        $scoopRoot = Join-Path $TestDrive 'scoop-hidden-exact'
        $app = Join-Path $scoopRoot 'apps\fd\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8
        (Get-Item (Join-Path $scoopRoot 'apps\fd')).LastWriteTime = [datetime]'2025-08-19T00:00:00'

        $data = Join-Path $TestDrive 'hidden-exact-data'
        $seeded = '2025-08-10T00:00:00.0000000Z'
        $state = Get-CmdPeekState -DataDirectory $data
        $state.LastPeekAt = $seeded
        $state = Set-CmdPeekHidden -State $state -Command 'fd' -Hidden $true
        Save-CmdPeekState -State $state -DataDirectory $data

        $output = Invoke-CmdPeek -Search fd -NonInteractive `
            -EnabledManagers @('scoop') `
            -ScoopRoot $scoopRoot `
            -ChocolateyRoot (Join-Path $TestDrive 'none-choco-hidden-exact') `
            -WinGetRoot (Join-Path $TestDrive 'none-winget-hidden-exact') `
            -DataDirectory $data `
            -ExamplesPath (Join-Path $PSScriptRoot '..\examples\usage-examples.json')

        $text = $output | Out-String
        $text | Should -Match 'fd \(scoop\)'
        $text | Should -Not -Match 'Last \d+ installed commands'
        $text | Should -Not -Match '(?m)^\d+\. fd'

        $after = Get-CmdPeekState -DataDirectory $data
        $after.LastPeekAt | Should -Be $seeded
    }
}

Describe 'usage-examples.json' {
    It 'is valid JSON with curated commands from the README' {
        $path = Join-Path $PSScriptRoot '..\examples\usage-examples.json'
        $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $json.commands.'yt-dlp'.usages.Count | Should -BeGreaterThan 1
        $json.commands.fd.usages[0] | Should -Match 'fd'
        $json.commands.jq.usages[0] | Should -Match 'jq'
    }

    It 'declares role kits next to commands' {
        $path = Join-Path $PSScriptRoot '..\examples\usage-examples.json'
        $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        @($json.kits.media) | Should -Contain 'ffmpeg'
        @($json.kits.'dev-tools') | Should -Contain 'fd'
        @($json.kits.search) | Should -Contain 'rg'
        $json.commands.mpv.category | Should -Be 'media'
    }
}
