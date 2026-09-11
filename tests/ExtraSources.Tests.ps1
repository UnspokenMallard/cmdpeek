#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'PackageManager.ps1')
    . (Join-Path $src 'Catalog.ps1')
    . (Join-Path $src 'UsageExamples.ps1')
    . (Join-Path $src 'ExtraSources.ps1')
}

Describe 'language and PATH scanners' {
    It 'reads pipx venv Scripts shims' {
        $root = Join-Path $TestDrive 'pipx\venvs'
        $scripts = Join-Path $root 'httpie\Scripts'
        New-Item -ItemType Directory -Force -Path $scripts | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $scripts 'http.exe') | Out-Null
        $pkgs = @(Get-CmdPeekPipxPackage -PipxRoot $root)
        $pkgs.Count | Should -Be 1
        $pkgs[0].PackageManager | Should -Be 'pipx'
        $pkgs[0].Commands | Should -Contain 'http'
    }

    It 'reads cargo bin executables' {
        $root = Join-Path $TestDrive 'cargo\bin'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $root 'rg.exe') | Out-Null
        $pkgs = @(Get-CmdPeekCargoPackage -CargoRoot $root)
        $pkgs.Commands | Should -Contain 'rg'
        $pkgs[0].PackageManager | Should -Be 'cargo'
    }

    It 'reads npm prefix shims' {
        $root = Join-Path $TestDrive 'npm-prefix'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $root 'pnpm.cmd') | Out-Null
        $pkgs = @(Get-CmdPeekNpmPackage -NpmRoot $root)
        $pkgs.Commands | Should -Contain 'pnpm'
    }

    It 'reads brew Cellar formula bins' {
        $root = Join-Path $TestDrive 'Cellar'
        $bin = Join-Path $root 'jq\1.7.1\bin'
        New-Item -ItemType Directory -Force -Path $bin | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $bin 'jq') | Out-Null
        $pkgs = @(Get-CmdPeekBrewPackage -BrewRoot $root)
        $pkgs[0].Name | Should -Be 'jq'
        $pkgs[0].Version | Should -Be '1.7.1'
        $pkgs[0].Commands | Should -Contain 'jq'
    }

    It 'adds catalog commands that the tester can resolve and skips ones already in history' {
        $catalog = @{
            'jq' = [pscustomobject]@{ category = 'dev-tools'; usages = @('jq .') }
            'fd' = [pscustomobject]@{ category = 'dev-tools'; usages = @('fd x') }
        }
        $history = @([pscustomobject]@{ Command = 'fd'; PackageManager = 'scoop'; PackageName = 'fd' })
        $merged = @(Add-CmdPeekPathCommands -History $history -Catalog $catalog -CommandTester { param($n) $n -eq 'jq' })
        $merged.Command | Should -Contain 'fd'
        $merged.Command | Should -Contain 'jq'
        @($merged | Where-Object { $_.Command -eq 'jq' })[0].PackageManager | Should -Be 'path'
    }

    It 'tags catalog builtins as builtin instead of path' {
        $catalog = @{
            'tasklist' = [pscustomobject]@{
                category = 'system'; origin = 'builtin'
                usages = @('tasklist'); install = [pscustomobject]@{ builtin = $true }
            }
        }
        $merged = @(Add-CmdPeekPathCommands -History @() -Catalog $catalog -CommandTester { param($n) $n -eq 'tasklist' })
        @($merged | Where-Object { $_.Command -eq 'tasklist' })[0].PackageManager | Should -Be 'builtin'
        @($merged | Where-Object { $_.Command -eq 'tasklist' })[0].Origin | Should -Be 'builtin'
    }

    It 'scans injected bin roots for unknown console names and skips denylisted ones' {
        $root = Join-Path $TestDrive 'sys32'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $root 'weirdtool.exe') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $root 'notepad.exe') | Out-Null
        $merged = @(Add-CmdPeekPathCommands -History @() -Catalog @{} -BinRoot @($root) -CommandTester { $false })
        $merged.Command | Should -Contain 'weirdtool'
        $merged.Command | Should -Not -Contain 'notepad'
        @($merged | Where-Object { $_.Command -eq 'weirdtool' })[0].PackageManager | Should -Be 'path'
        @($merged | Where-Object { $_.Command -eq 'weirdtool' })[0].Origin | Should -Be 'path'
    }
}

Describe 'Get-CmdPeekAptPackage command filtering' {
    BeforeAll {
        function New-AptFixture {
            param([string]$Root)

            $info = Join-Path $Root 'info'
            New-Item -ItemType Directory -Force -Path $info | Out-Null
            $status = Join-Path $Root 'status'
            @(
                'Package: coreutils'
                'Status: install ok installed'
                'Version: 9.4-3'
                ''
                'Package: zlib1g'
                'Status: install ok installed'
                'Version: 1:1.3-1'
                'Provides: libz1'
                ''
                'Package: mawk'
                'Status: install ok installed'
                'Version: 1.3.4'
                'Provides: awk'
                ''
                'Package: ghost'
                'Status: deinstall ok config-files'
                'Version: 1.0'
                ''
            ) | Set-Content -LiteralPath $status -Encoding UTF8

            @('/usr/bin/ls', '/usr/bin/cat', '/usr/share/man/man1/ls.1.gz') |
                Set-Content -LiteralPath (Join-Path $info 'coreutils.list') -Encoding UTF8
            @('/usr/lib/x86_64-linux-gnu/libz.so.1', '/usr/share/doc/zlib1g/copyright') |
                Set-Content -LiteralPath (Join-Path $info 'zlib1g:amd64.list') -Encoding UTF8
            @('/usr/bin/mawk') |
                Set-Content -LiteralPath (Join-Path $info 'mawk.list') -Encoding UTF8

            return $status
        }
    }

    It 'drops library packages that ship no executable' {
        $status = New-AptFixture -Root (Join-Path $TestDrive 'dpkg-libs')
        $pkgs = @(Get-CmdPeekAptPackage -StatusPath $status)
        @($pkgs | Select-Object -ExpandProperty Name) | Should -Not -Contain 'zlib1g'
    }

    It 'uses the dpkg file list for command names instead of the package name' {
        $status = New-AptFixture -Root (Join-Path $TestDrive 'dpkg-names')
        $pkgs = @(Get-CmdPeekAptPackage -StatusPath $status)
        $coreutils = @($pkgs | Where-Object { $_.Name -eq 'coreutils' })[0]
        @($coreutils.Commands) | Should -Be @('ls', 'cat')
    }

    It 'keeps Provides aliases for packages that do ship an executable' {
        $status = New-AptFixture -Root (Join-Path $TestDrive 'dpkg-provides')
        $pkgs = @(Get-CmdPeekAptPackage -StatusPath $status)
        $mawk = @($pkgs | Where-Object { $_.Name -eq 'mawk' })[0]
        @($mawk.Commands) | Should -Contain 'mawk'
        @($mawk.Commands) | Should -Contain 'awk'
    }

    It 'skips packages that are not fully installed' {
        $status = New-AptFixture -Root (Join-Path $TestDrive 'dpkg-ghost')
        $pkgs = @(Get-CmdPeekAptPackage -StatusPath $status)
        @($pkgs | Select-Object -ExpandProperty Name) | Should -Not -Contain 'ghost'
    }

    It 'falls back to the package name when no dpkg file lists exist' {
        $root = Join-Path $TestDrive 'dpkg-nolists'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $status = Join-Path $root 'status'
        @('Package: ripgrep', 'Status: install ok installed', 'Version: 14.1.0', '') |
            Set-Content -LiteralPath $status -Encoding UTF8
        $pkgs = @(Get-CmdPeekAptPackage -StatusPath $status)
        $pkgs.Count | Should -Be 1
        @($pkgs[0].Commands) | Should -Be @('ripgrep')
    }
}

Describe 'live apt and pacman default roots' {
    It 'scans /var/lib/dpkg/status when StatusPath is omitted' {
        $default = Get-CmdPeekDefaultUnixRoot -Manager apt
        if (-not (Test-Path -LiteralPath $default)) {
            Set-ItResult -Skipped -Because 'no dpkg status database on this OS'
            return
        }
        $pkgs = @(Get-CmdPeekAptPackage)
        $pkgs.Count | Should -BeGreaterThan 0
        $pkgs[0].PackageManager | Should -Be 'apt'
        $pkgs[0].Path | Should -Be $default
    }

    It 'scans /var/lib/pacman/local when LocalRoot is omitted' {
        $default = Get-CmdPeekDefaultUnixRoot -Manager pacman
        if (-not (Test-Path -LiteralPath $default)) {
            Set-ItResult -Skipped -Because 'no pacman local database on this OS'
            return
        }
        $pkgs = @(Get-CmdPeekPacmanPackage)
        $pkgs.Count | Should -BeGreaterThan 0
        $pkgs[0].PackageManager | Should -Be 'pacman'
    }
}
