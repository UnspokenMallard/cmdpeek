#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'PackageManager.ps1')
    . (Join-Path $src 'UsageExamples.ps1')
}

Describe 'Get-CmdPeekPackageManager' {
    It 'returns chocolatey when choco is resolvable' {
        $result = @(Get-CmdPeekPackageManager -CommandTester { param($Name) $Name -eq 'choco' })
        $result.Name | Should -Contain 'chocolatey'
        $result.Count | Should -Be 1
    }

    It 'returns scoop when scoop is resolvable' {
        $result = @(Get-CmdPeekPackageManager -CommandTester { param($Name) $Name -eq 'scoop' })
        $result.Name | Should -Contain 'scoop'
    }

    It 'returns winget when winget is resolvable' {
        $result = @(Get-CmdPeekPackageManager -CommandTester { param($Name) $Name -eq 'winget' })
        $result.Name | Should -Contain 'winget'
    }

    It 'returns all three when every command is present' {
        $result = @(Get-CmdPeekPackageManager -CommandTester { $true })
        $result.Name | Should -Be @('chocolatey', 'scoop', 'winget')
    }

    It 'returns empty when no package manager is present' {
        $result = @(Get-CmdPeekPackageManager -CommandTester { $false })
        $result.Count | Should -Be 0
    }

    It 'includes an install hint for each known manager' {
        $result = @(Get-CmdPeekPackageManager -CommandTester { $true } -All)
        foreach ($pm in $result) {
            $pm.InstallHint | Should -Not -BeNullOrEmpty
            $pm.Command | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-CmdPeekInstalledPackage' {
    BeforeEach {
        $script:scoopRoot = Join-Path $TestDrive 'scoop'
        $script:chocoRoot = Join-Path $TestDrive 'chocolatey'
        $script:wingetRoot = Join-Path $TestDrive 'winget'
        foreach ($root in @($script:scoopRoot, $script:chocoRoot, $script:wingetRoot)) {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It 'reads scoop packages from the apps directory and manifest bin entries' {
        $app = Join-Path $script:scoopRoot 'apps\fd\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8
        '{"bucket":"main"}' | Set-Content -Path (Join-Path $app 'install.json') -Encoding UTF8
        New-Item -ItemType File -Force -Path (Join-Path $app 'fd.exe') | Out-Null
        $dir = Get-Item (Join-Path $script:scoopRoot 'apps\fd')
        $dir.LastWriteTime = [datetime]'2025-08-20T14:32:00'

        $result = @(Get-CmdPeekInstalledPackage -ScoopRoot $script:scoopRoot -EnabledManagers @('scoop'))
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'fd'
        $result[0].PackageManager | Should -Be 'scoop'
        $result[0].Commands | Should -Contain 'fd'
        $result[0].InstallDate | Should -Be ([datetime]'2025-08-20T14:32:00')
    }

    It 'expands scoop manifest bin arrays and aliases' {
        $app = Join-Path $script:scoopRoot 'apps\ripgrep\current'
        New-Item -ItemType Directory -Force -Path $app | Out-Null
        '{"version":"14.1.0","bin":["rg.exe",["rg.exe","ripgrep"]]}' | Set-Content -Path (Join-Path $app 'manifest.json') -Encoding UTF8

        $result = @(Get-CmdPeekInstalledPackage -ScoopRoot $script:scoopRoot -EnabledManagers @('scoop'))
        $result[0].Commands | Should -Contain 'rg'
        $result[0].Commands | Should -Contain 'ripgrep'
    }

    It 'reads chocolatey packages from lib folders and bin shims' {
        $lib = Join-Path $script:chocoRoot 'lib\jq'
        $bin = Join-Path $script:chocoRoot 'bin'
        New-Item -ItemType Directory -Force -Path $lib, $bin | Out-Null
        '<package><metadata><id>jq</id><version>1.7.1</version></metadata></package>' |
            Set-Content -Path (Join-Path $lib 'jq.nuspec') -Encoding UTF8
        New-Item -ItemType File -Force -Path (Join-Path $bin 'jq.exe') | Out-Null
        (Get-Item $lib).LastWriteTime = [datetime]'2025-08-18T09:00:00'

        $result = @(Get-CmdPeekInstalledPackage -ChocolateyRoot $script:chocoRoot -EnabledManagers @('chocolatey'))
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'jq'
        $result[0].PackageManager | Should -Be 'chocolatey'
        $result[0].Version | Should -Be '1.7.1'
        $result[0].Commands | Should -Contain 'jq'
        $result[0].InstallDate | Should -Be ([datetime]'2025-08-18T09:00:00')
    }

    It 'skips chocolatey meta packages that do not expose commands' {
        $lib = Join-Path $script:chocoRoot 'lib\chocolatey'
        New-Item -ItemType Directory -Force -Path $lib | Out-Null
        '<package><metadata><id>chocolatey</id><version>2.0.0</version></metadata></package>' |
            Set-Content -Path (Join-Path $lib 'chocolatey.nuspec') -Encoding UTF8

        $result = @(Get-CmdPeekInstalledPackage -ChocolateyRoot $script:chocoRoot -EnabledManagers @('chocolatey'))
        $result.Count | Should -Be 0
    }

    It 'reads winget packages from the packages directory' {
        $pkg = Join-Path $script:wingetRoot 'Git.Git_Microsoft.Winget.Source_8wekyb3d8bbwe'
        New-Item -ItemType Directory -Force -Path $pkg | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $pkg 'git.exe') | Out-Null
        (Get-Item $pkg).LastWriteTime = [datetime]'2025-08-16T12:00:00'

        $result = @(Get-CmdPeekInstalledPackage `
            -WinGetRoot $script:wingetRoot `
            -EnabledManagers @('winget') `
            -CommandTester { param($Name) $Name -eq 'git' })
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'Git.Git'
        $result[0].PackageManager | Should -Be 'winget'
        $result[0].Commands | Should -Contain 'git'
        $result[0].InstallDate | Should -Be ([datetime]'2025-08-16T12:00:00')
    }

    It 'keeps a WinGet console CLI that the command tester can resolve' {
        $cmd = $env:ComSpec
        if (-not (Test-Path -LiteralPath $cmd)) { return }
        $pkg = Join-Path $script:wingetRoot 'Acme.MyTool_8wekyb3d8bbwe'
        New-Item -ItemType Directory -Force -Path $pkg | Out-Null
        Copy-Item -LiteralPath $cmd -Destination (Join-Path $pkg 'mytool.exe')

        $result = @(Get-CmdPeekInstalledPackage `
            -WinGetRoot $script:wingetRoot `
            -EnabledManagers @('winget') `
            -CommandTester { param($Name) $Name -eq 'mytool' })
        $result.Count | Should -Be 1
        $result[0].Commands | Should -Contain 'mytool'
    }

    It 'skips WinGet GUI executables even when the command tester accepts them' {
        $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
        if (-not (Test-Path -LiteralPath $notepad)) { return }
        $pkg = Join-Path $script:wingetRoot 'LogExpert.LogExpert_8wekyb3d8bbwe'
        New-Item -ItemType Directory -Force -Path $pkg | Out-Null
        Copy-Item -LiteralPath $notepad -Destination (Join-Path $pkg 'LogExpert.exe')

        $result = @(Get-CmdPeekInstalledPackage `
            -WinGetRoot $script:wingetRoot `
            -EnabledManagers @('winget') `
            -CommandTester { $true })
        $result.Count | Should -Be 0
    }

    It 'skips WinGet helper executables that are not on PATH' {
        $pkg = Join-Path $script:wingetRoot 'Vendor.Helper_8wekyb3d8bbwe'
        New-Item -ItemType Directory -Force -Path $pkg | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $pkg 'vendor-helper.exe') | Out-Null

        $result = @(Get-CmdPeekInstalledPackage `
            -WinGetRoot $script:wingetRoot `
            -EnabledManagers @('winget') `
            -CommandTester { $false })
        $result.Count | Should -Be 0
    }

    It 'merges packages from every enabled manager' {
        $scoopApp = Join-Path $script:scoopRoot 'apps\fd\current'
        New-Item -ItemType Directory -Force -Path $scoopApp | Out-Null
        '{"version":"10.2.0","bin":"fd.exe"}' | Set-Content -Path (Join-Path $scoopApp 'manifest.json') -Encoding UTF8

        $lib = Join-Path $script:chocoRoot 'lib\jq'
        $bin = Join-Path $script:chocoRoot 'bin'
        New-Item -ItemType Directory -Force -Path $lib, $bin | Out-Null
        '<package><metadata><id>jq</id><version>1.7.1</version></metadata></package>' |
            Set-Content -Path (Join-Path $lib 'jq.nuspec') -Encoding UTF8
        New-Item -ItemType File -Force -Path (Join-Path $bin 'jq.exe') | Out-Null

        $result = @(Get-CmdPeekInstalledPackage `
            -ScoopRoot $script:scoopRoot `
            -ChocolateyRoot $script:chocoRoot `
            -WinGetRoot $script:wingetRoot `
            -EnabledManagers @('scoop', 'chocolatey'))
        $result.Name | Should -Contain 'fd'
        $result.Name | Should -Contain 'jq'
        $result.Count | Should -Be 2
    }

    It 'returns empty when enabled managers have no packages' {
        $result = @(Get-CmdPeekInstalledPackage -ScoopRoot $script:scoopRoot -EnabledManagers @('scoop'))
        $result.Count | Should -Be 0
    }
}

Describe 'Get-CmdPeekPackageManagerInstallHint' {
    It 'returns a scoop bootstrap command' {
        $hint = Get-CmdPeekPackageManagerInstallHint -Name scoop
        $hint | Should -Match 'scoop'
    }

    It 'returns a chocolatey bootstrap command' {
        $hint = Get-CmdPeekPackageManagerInstallHint -Name chocolatey
        $hint | Should -Match 'chocolatey'
    }

    It 'returns a winget store/app-installer hint' {
        $hint = Get-CmdPeekPackageManagerInstallHint -Name winget
        $hint | Should -Match 'winget|App Installer'
    }
}
