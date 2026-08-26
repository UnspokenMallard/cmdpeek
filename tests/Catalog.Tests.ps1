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
