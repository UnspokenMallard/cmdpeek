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
}

Describe 'usage-examples.json' {
    It 'is valid JSON with curated commands from the README' {
        $path = Join-Path $PSScriptRoot '..\examples\usage-examples.json'
        $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $json.commands.'yt-dlp'.usages.Count | Should -BeGreaterThan 1
        $json.commands.fd.usages[0] | Should -Match 'fd'
        $json.commands.jq.usages[0] | Should -Match 'jq'
    }
}
