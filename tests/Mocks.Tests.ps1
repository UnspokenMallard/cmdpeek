#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'Config.ps1')
    . (Join-Path $src 'PackageManager.ps1')
    . (Join-Path $src 'CommandUse.ps1')
    . (Join-Path $src 'Catalog.ps1')
    . (Join-Path $src 'UsageExamples.ps1')
    . (Join-Path $src 'ExtraSources.ps1')
    . (Join-Path $src 'InteractiveMode.ps1')
    $script:mocks = Join-Path $PSScriptRoot '..\examples\mocks'
}

Describe 'rusty last-used overlay' {
    It 'attaches calendar timestamps from the mock overlay' {
        $history = @(
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop'; Usages = @('jq .') }
            [pscustomobject]@{ Command = 'nevercli'; PackageManager = 'scoop'; Usages = @('nevercli --help') }
            [pscustomobject]@{ Command = 'fd'; PackageManager = 'scoop'; Usages = @('fd x') }
        )
        $histPath = Join-Path $script:mocks 'psreadline-history.txt'
        $overlay = Join-Path $script:mocks 'rusty-last-used.json'
        $rusty = @(Get-CmdPeekRusty -History $history -HistoryPath @($histPath) -RecentLines 1 -LastUsedPath $overlay)
        $never = @($rusty | Where-Object { $_.Command -eq 'nevercli' })[0]
        $never.kind | Should -Be 'never'
        $stale = @($rusty | Where-Object { $_.Command -eq 'jq' })[0]
        $stale.kind | Should -Be 'stale'
        $stale.LastUsedAt | Should -Not -BeNullOrEmpty
        ([datetime]$stale.LastUsedAt).Year | Should -Be 2026
        $text = Format-CmdPeekQuickOutput -History @($stale) -Rusty
        $text | Should -Match 'last used: 2026-03-02'
    }
}

Describe 'apt and pacman mock inventories' {
    It 'reads installed apt packages from a dpkg status excerpt' {
        $status = Join-Path $script:mocks 'dpkg-status'
        $pkgs = @(Get-CmdPeekAptPackage -StatusPath $status)
        $pkgs.Name | Should -Contain 'jq'
        $pkgs.Name | Should -Contain 'fd-find'
        $pkgs.Name | Should -Not -Contain 'ripgrep'
        $fd = @($pkgs | Where-Object { $_.Name -eq 'fd-find' })[0]
        $fd.Commands | Should -Contain 'fd'
        $fd.PackageManager | Should -Be 'apt'
    }

    It 'reads pacman local desc files including bin commands and build dates' {
        $root = Join-Path $script:mocks 'pacman\local'
        $pkgs = @(Get-CmdPeekPacmanPackage -LocalRoot $root)
        $pkgs.Name | Should -Contain 'ripgrep'
        $pkgs.Name | Should -Contain 'fd'
        $rg = @($pkgs | Where-Object { $_.Name -eq 'ripgrep' })[0]
        $rg.Commands | Should -Contain 'rg'
        $rg.Version | Should -Be '14.1.0-1'
        $rg.InstallDate | Should -Not -BeNullOrEmpty
    }

    It 'merges apt mocks through Get-CmdPeekInstalledPackage' {
        $status = Join-Path $script:mocks 'dpkg-status'
        $result = @(Get-CmdPeekInstalledPackage -AptStatusPath $status -EnabledManagers @('apt'))
        $result.Name | Should -Contain 'jq'
    }
}

Describe 'OpenAI mock completions' {
    It 'returns canned usages without calling the network' {
        $path = Join-Path $script:mocks 'openai-examples.json'
        $usages = @(Get-CmdPeekMockAiExample -Command 'mystery-cli' -Path $path -Count 2)
        $usages.Count | Should -Be 2
        $usages[0] | Should -Match 'mystery-cli status'
    }

    It 'uses CMDPEEK_OPENAI_MOCK_PATH from Get-CmdPeekUsageExample' {
        $path = Join-Path $script:mocks 'openai-examples.json'
        $prev = $env:CMDPEEK_OPENAI_MOCK_PATH
        try {
            $env:CMDPEEK_OPENAI_MOCK_PATH = $path
            $usages = @(Get-CmdPeekUsageExample -Command 'acme-internal' -Catalog @{} -Count 2 -SkipHelpProbe)
            $usages[0] | Should -Match 'acme-internal whoami'
        }
        finally {
            if ($null -eq $prev) { Remove-Item Env:CMDPEEK_OPENAI_MOCK_PATH -ErrorAction SilentlyContinue }
            else { $env:CMDPEEK_OPENAI_MOCK_PATH = $prev }
        }
    }
}

Describe 'WinGet mock release SHA256' {
    It 'matches Get-FileHash of the payload file' {
        $path = Join-Path $script:mocks 'winget-release.json'
        $info = Get-CmdPeekWinGetReleaseInfo -Path $path
        $info | Should -Not -BeNullOrEmpty
        $info.InstallerSha256 | Should -Be 'EFB66D74B23CD2219110F6366E69984EB8E7738F893C90B3F9008CEB1FA1C33E'
        $info.PayloadSha256 | Should -Be $info.InstallerSha256
        $info.MatchesPayload | Should -BeTrue
        $info.PackageVersion | Should -Be '0.2.0-mock'
    }
}

Describe 'profile v1 upgrade' {
    It 'replaces a 0.1 hint block with pipx/npm/cargo/brew wrappers' {
        $srcProfile = Join-Path $script:mocks 'profile-v1.ps1'
        $dest = Join-Path $TestDrive 'Microsoft.PowerShell_profile.ps1'
        Copy-Item -LiteralPath $srcProfile -Destination $dest
        Add-CmdPeekProfileHint -ProfilePath $dest
        $text = Get-Content -LiteralPath $dest -Raw -Encoding UTF8
        $text | Should -Match 'function pipx'
        $text | Should -Match 'function brew'
        $text | Should -Match 'Set-Alias ll'
        ([regex]::Matches($text, 'BEGIN cmdpeek hint')).Count | Should -Be 1
        $text | Should -Not -Match '(?s)BEGIN cmdpeek hint.*BEGIN cmdpeek hint'
    }
}
