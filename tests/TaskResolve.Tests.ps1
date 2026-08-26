#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'Catalog.ps1')
    . (Join-Path $src 'UsageExamples.ps1')
    . (Join-Path $src 'TaskResolve.ps1')
    . (Join-Path $src 'InteractiveMode.ps1')
}

Describe 'Resolve-CmdPeekTask' {
    BeforeAll {
        $script:catalog = @{
            'jq' = [pscustomobject]@{
                category     = 'dev-tools'
                capabilities = @('json')
                tasks        = @('pretty-print json', 'query json')
                usages       = @("jq '.' file.json  # Pretty-print JSON")
                related      = @('yq')
                substitutes  = @('fx')
            }
            'fx' = [pscustomobject]@{
                category     = 'dev-tools'
                capabilities = @('json')
                tasks        = @('pretty-print json')
                usages       = @('fx file.json  # View JSON')
                substitutes  = @('jq')
            }
            'fd' = [pscustomobject]@{
                category     = 'dev-tools'
                capabilities = @('search')
                tasks        = @('find files')
                usages       = @('fd <pattern>  # Find files')
            }
        }
        $script:history = @(
            [pscustomobject]@{
                Command = 'jq'; PackageManager = 'scoop'; OnPath = $true
                Usages = @("jq '.' file.json")
            }
        )
    }

    It 'prefers the installed json tool over a missing substitute' {
        $result = Resolve-CmdPeekTask -Task 'pretty-print json' -History $script:history -Catalog $script:catalog
        @($result.installed).Count | Should -BeGreaterThan 0
        @($result.installed | ForEach-Object { $_.command }) | Should -Contain 'jq'
        @($result.installed | ForEach-Object { $_.command }) | Should -Not -Contain 'fx'
        @($result.missing | ForEach-Object { $_.command }) | Should -Not -Contain 'jq'
        @($result.missing | ForEach-Object { $_.command }) | Should -Not -Contain 'fx'
    }

    It 'scores an exact capability' {
        $result = Resolve-CmdPeekTask -Task 'json' -History $script:history -Catalog $script:catalog
        $jq = @($result.installed | Where-Object { $_.command -eq 'jq' })[0]
        $jq.score | Should -BeGreaterThan 50
    }
}

Describe 'Get-CmdPeekWhyCommand' {
    It 'reports PATH winner and installed substitutes' {
        $catalog = @{
            'jq' = [pscustomobject]@{
                category = 'dev-tools'; capabilities = @('json')
                substitutes = @('fx'); usages = @('jq .')
            }
            'fx' = [pscustomobject]@{ category = 'dev-tools'; usages = @('fx file') }
        }
        $history = @(
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop'; OnPath = $true }
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'chocolatey'; OnPath = $false }
            [pscustomobject]@{ Command = 'fx'; PackageManager = 'scoop'; OnPath = $true }
        )
        $why = Get-CmdPeekWhyCommand -Command 'jq' -History $history -Catalog $catalog -CommandTester { param($n) $n -eq 'jq' }
        $why.installed | Should -BeTrue
        $why.onPathManager | Should -Be 'scoop'
        $why.substitutesInstalled | Should -Contain 'fx'
    }
}

Describe 'Get-CmdPeekHaveList' {
    It 'filters installed rows by capability' {
        $catalog = @{
            'jq' = [pscustomobject]@{ category = 'dev-tools'; capabilities = @('json'); usages = @('jq .') }
            'fd' = [pscustomobject]@{ category = 'dev-tools'; capabilities = @('search'); usages = @('fd x') }
        }
        $history = @(
            [pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop'; Category = 'dev-tools' }
            [pscustomobject]@{ Command = 'fd'; PackageManager = 'scoop'; Category = 'dev-tools' }
        )
        $have = @(Get-CmdPeekHaveList -History $history -Catalog $catalog -Capability json)
        $have.Command | Should -Contain 'jq'
        $have.Command | Should -Not -Contain 'fd'
    }
}

Describe 'task formatters' {
    It 'prints installed tools first' {
        $result = [pscustomobject]@{
            query     = 'json'
            installed = @([pscustomobject]@{ command = 'jq'; packageManager = 'scoop'; reason = 'capability'; usages = @('jq .') })
            missing   = @()
        }
        $text = Format-CmdPeekTaskOutput -Result $result
        $text | Should -Match 'You already have'
        $text | Should -Match 'jq'
    }
}

Describe 'Search-CmdPeekAvailable' {
    It 'splits installed catalog hits from missing ones' {
        $catalog = @{
            'jq' = [pscustomobject]@{
                category     = 'dev-tools'
                capabilities = @('json')
                usages       = @("jq '.' file.json")
            }
            'fx' = [pscustomobject]@{
                category     = 'dev-tools'
                capabilities = @('json')
                usages       = @('fx file.json')
            }
        }
        $history = @([pscustomobject]@{ Command = 'jq'; PackageManager = 'scoop' })
        $result = Search-CmdPeekAvailable -Query json -History $history -Catalog $catalog
        @($result.catalogInstalled | ForEach-Object { $_.command }) | Should -Contain 'jq'
        @($result.catalogMissing | ForEach-Object { $_.command }) | Should -Contain 'fx'
        @($result.catalogMissing | ForEach-Object { $_.command }) | Should -Not -Contain 'jq'
    }
}
