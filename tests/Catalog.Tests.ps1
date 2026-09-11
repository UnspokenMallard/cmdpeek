#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'Config.ps1')
    . (Join-Path $src 'Catalog.ps1')
    . (Join-Path $src 'UsageExamples.ps1')
}

Describe 'shipped catalog' {
    It 'has no validation errors' {
        $catalog = Get-CmdPeekExampleCatalog
        $kits = Get-CmdPeekCatalogKits
        $errors = @(Test-CmdPeekCatalog -Catalog $catalog -Kits $kits)
        $errors | Should -BeNullOrEmpty
    }

    It 'looks up ripgrep via the rg aliases' {
        $catalog = Get-CmdPeekExampleCatalog
        $entry = Get-CmdPeekCatalogEntry -Command 'ripgrep' -Catalog $catalog
        $entry | Should -Not -BeNullOrEmpty
        @(Get-CmdPeekCatalogCapabilityList -Entry $entry) | Should -Contain 'search'
    }
}

Describe 'catalog overlay' {
    It 'overlays commands from catalog.overlay.json' {
        $base = Join-Path $TestDrive 'base.json'
        '{"commands":{"fd":{"category":"dev-tools","usages":["fd x"]}}}' | Set-Content -LiteralPath $base -Encoding UTF8
        $data = Join-Path $TestDrive 'overlay-data'
        New-Item -ItemType Directory -Force -Path $data | Out-Null
        '{"commands":{"mycmd":{"category":"dev-tools","usages":["mycmd --help"]}}}' |
            Set-Content -LiteralPath (Join-Path $data 'catalog.overlay.json') -Encoding UTF8
        $catalog = Get-CmdPeekExampleCatalog -Path $base -DataDirectory $data
        $catalog.ContainsKey('fd') | Should -BeTrue
        $catalog.ContainsKey('mycmd') | Should -BeTrue
    }
}

Describe 'Get-CmdPeekInstallCommands' {
    It 'prefers catalog install ids' {
        $catalog = Get-CmdPeekExampleCatalog
        $lines = @(Get-CmdPeekInstallCommands -Command 'rg' -Catalog $catalog -PreferredManager 'scoop')
        $lines[0] | Should -Match 'scoop install ripgrep'
    }

    It 'emits pipx and npm install lines from catalog ids' {
        $catalog = @{
            'httpie' = [pscustomobject]@{
                category = 'network'
                usages   = @('http GET https://example.com')
                install  = [pscustomobject]@{ pipx = 'httpie'; npm = 'httpie' }
            }
        }
        $lines = @(Get-CmdPeekInstallCommands -Command 'httpie' -Catalog $catalog -PreferredManager 'pipx')
        $lines[0] | Should -Match 'pipx install httpie'
        ($lines -join "`n") | Should -Match 'npm install -g httpie'
    }
}

Describe 'structured usages' {
    It 'marks placeholder usages as unsafe' {
        $rows = @(ConvertTo-CmdPeekStructuredUsage -Usage @('jq ''.field'' file.json  # Extract', 'fd <pattern>  # Find'))
        $rows.Count | Should -Be 2
        $rows[0].unsafe | Should -BeFalse
        $rows[1].unsafe | Should -BeTrue
        $rows[1].argv | Should -Match 'fd'
    }
}

Describe 'name coverage' {
    It 'treats aliases and substitutes as covering a missing name' {
        $catalog = @{
            'rg' = [pscustomobject]@{
                category    = 'dev-tools'
                aliases     = @('ripgrep')
                substitutes = @('grep')
                usages      = @('rg x')
            }
            'grep' = [pscustomobject]@{
                category = 'dev-tools'
                usages   = @('grep x')
            }
        }
        $history = @([pscustomobject]@{ Command = 'rg' })
        $set = Get-CmdPeekInstalledNameSet -History $history -Catalog $catalog
        Test-CmdPeekNameCovered -Name 'ripgrep' -InstalledSet $set -Catalog $catalog | Should -BeTrue
        Test-CmdPeekNameCovered -Name 'grep' -InstalledSet $set -Catalog $catalog | Should -BeTrue
        Test-CmdPeekNameCovered -Name 'jq' -InstalledSet $set -Catalog $catalog | Should -BeFalse
    }
}

Describe 'catalog origin and builtin install' {
    It 'rejects builtin entries that also have package ids' {
        $catalog = @{
            'tasklist' = [pscustomobject]@{
                category = 'system'
                origin   = 'builtin'
                usages   = @('tasklist  # list')
                install  = [pscustomobject]@{ builtin = $true; scoop = 'tasklist' }
            }
        }
        $errors = @(Test-CmdPeekCatalog -Catalog $catalog -Kits @{})
        ($errors -join '`n') | Should -Match 'package install ids'
    }

    It 'does not emit scoop install lines for builtins' {
        $catalog = @{
            'tasklist' = [pscustomobject]@{
                category = 'system'
                origin   = 'builtin'
                usages   = @('tasklist  # list')
                install  = [pscustomobject]@{ builtin = $true }
            }
        }
        @(Get-CmdPeekInstallCommands -Command tasklist -Catalog $catalog) | Should -BeNullOrEmpty
    }

    It 'ships system commands in the merged catalog' {
        $catalog = Get-CmdPeekExampleCatalog
        $catalog.ContainsKey('tasklist') | Should -BeTrue
        $catalog.ContainsKey('Get-Process') | Should -BeTrue
        Test-CmdPeekCatalogIsBuiltin -Entry $catalog['tasklist'] | Should -BeTrue
        @(Get-CmdPeekCatalogOsList -Entry $catalog['tasklist']) | Should -Contain 'windows'
    }
}

Describe 'shell builtins are not installable' {
    It 'recognises an alias and a cmdlet as shell builtins' {
        Test-CmdPeekShellBuiltinName -Command 'cd' | Should -BeTrue
        Test-CmdPeekShellBuiltinName -Command 'Set-Location' | Should -BeTrue
    }

    It 'does not call a real executable or an unknown name a shell builtin' {
        Test-CmdPeekShellBuiltinName -Command 'pwsh' | Should -BeFalse
        Test-CmdPeekShellBuiltinName -Command 'cmdpeek-no-such-binary' | Should -BeFalse
        Test-CmdPeekShellBuiltinName -Command '' | Should -BeFalse
    }

    It 'emits no install guess for a name the shell owns' {
        @(Get-CmdPeekInstallCommands -Command 'cd' -Catalog @{}) | Should -BeNullOrEmpty
    }

    It 'still guesses an install line for a name that could be a package' {
        $lines = @(Get-CmdPeekInstallCommands -Command 'cmdpeek-no-such-binary' -Catalog @{} -PreferredManager 'scoop')
        $lines[0] | Should -Match 'scoop install cmdpeek-no-such-binary'
    }

    It 'reports origin builtin for a shell name with no catalog entry' {
        Get-CmdPeekCatalogOrigin -Entry $null -Command 'cd' | Should -Be 'builtin'
        Get-CmdPeekCatalogOrigin -Entry $null -Command 'cmdpeek-no-such-binary' | Should -Be 'package'
    }

    It 'lets a catalog origin win over the live probe' {
        $entry = [pscustomobject]@{ category = 'dev-tools'; origin = 'package' }
        Get-CmdPeekCatalogOrigin -Entry $entry -Command 'cd' | Should -Be 'package'
    }

    It 'builds a builtin command card with no install line' {
        $card = Get-CmdPeekCommandCard -Command 'cd' -Catalog @{} -History @()
        $card.origin | Should -Be 'builtin'
        @($card.installCommands) | Should -BeNullOrEmpty
    }
}

Describe 'learned catalog' {
    It 'writes help-probe usages for unknown commands and skips names already in the catalog' {
        $data = Join-Path $TestDrive 'learned-data'
        New-Item -ItemType Directory -Force -Path $data | Out-Null
        $catalog = @{
            'fd' = [pscustomobject]@{ category = 'dev-tools'; usages = @('fd x') }
        }
        $ok = Save-CmdPeekLearnedCatalogEntry -Command 'mysterycli' -Usages @('mysterycli status  # Show status') -DataDirectory $data -Catalog $catalog -Origin path
        $ok | Should -BeTrue
        $skip = Save-CmdPeekLearnedCatalogEntry -Command 'fd' -Usages @('fd extra') -DataDirectory $data -Catalog $catalog
        $skip | Should -BeFalse
        $base = Join-Path $TestDrive 'learned-base.json'
        '{"commands":{"fd":{"category":"dev-tools","usages":["fd x"]}}}' | Set-Content -LiteralPath $base -Encoding UTF8
        $merged = Get-CmdPeekExampleCatalog -Path $base -DataDirectory $data
        $merged.ContainsKey('mysterycli') | Should -BeTrue
        @(Get-CmdPeekCatalogUsageList -Entry $merged['mysterycli'])[0] | Should -Match 'mysterycli status'
    }
}

Describe 'Get-CmdPeekSubstituteCoverage' {
    BeforeEach { Clear-CmdPeekSubstituteCoverage }

    It 'reports names an installed tool already substitutes for' {
        $catalog = @{
            'rg'   = [pscustomobject]@{ aliases = @('ripgrep'); substitutes = @('grep', 'findstr') }
            'grep' = [pscustomobject]@{ aliases = @() }
        }
        $installed = @{ 'rg' = $true }
        $coverage = Get-CmdPeekSubstituteCoverage -InstalledSet $installed -Catalog $catalog
        $coverage.ContainsKey('grep') | Should -BeTrue
        $coverage.ContainsKey('findstr') | Should -BeTrue
        $coverage.ContainsKey('jq') | Should -BeFalse
    }

    It 'keeps Test-CmdPeekNameCovered answering through substitutes' {
        $catalog = @{
            'rg'   = [pscustomobject]@{ aliases = @(); substitutes = @('grep') }
            'grep' = [pscustomobject]@{ aliases = @() }
            'jq'   = [pscustomobject]@{ aliases = @() }
        }
        $installed = @{ 'rg' = $true }
        Test-CmdPeekNameCovered -Name 'grep' -InstalledSet $installed -Catalog $catalog | Should -BeTrue
        Test-CmdPeekNameCovered -Name 'jq' -InstalledSet $installed -Catalog $catalog | Should -BeFalse
    }

    It 'does not reuse coverage across different installed sets' {
        $catalog = @{
            'rg'   = [pscustomobject]@{ aliases = @(); substitutes = @('grep') }
            'grep' = [pscustomobject]@{ aliases = @() }
        }
        Test-CmdPeekNameCovered -Name 'grep' -InstalledSet @{ 'rg' = $true } -Catalog $catalog | Should -BeTrue
        Test-CmdPeekNameCovered -Name 'grep' -InstalledSet @{ 'jq' = $true } -Catalog $catalog | Should -BeFalse
    }
}
