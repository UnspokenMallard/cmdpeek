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

    It 'maps list processes to tasklist via synonyms' {
        $catalog = @{
            'tasklist' = [pscustomobject]@{
                category = 'system'; origin = 'builtin'; os = @('windows')
                capabilities = @('process'); tasks = @('list processes')
                usages = @('tasklist  # List processes')
                install = [pscustomobject]@{ builtin = $true }
            }
            'jq' = [pscustomobject]@{
                category = 'dev-tools'; capabilities = @('json'); usages = @('jq .')
            }
        }
        $history = @(
            [pscustomobject]@{ Command = 'tasklist'; PackageManager = 'builtin'; OnPath = $true }
        )
        $result = Resolve-CmdPeekTask -Task 'list processes' -History $history -Catalog $catalog
        @($result.installed | ForEach-Object { $_.command }) | Should -Contain 'tasklist'
        @($result.missing | ForEach-Object { $_.command }) | Should -Not -Contain 'tasklist'
    }

    It 'omits wrong-OS builtins from missing' {
        $catalog = @{
            'tasklist' = [pscustomobject]@{
                category = 'system'; origin = 'builtin'; os = @('windows')
                capabilities = @('process'); tasks = @('list processes')
                usages = @('tasklist  # List')
                install = [pscustomobject]@{ builtin = $true }
            }
        }
        $result = Resolve-CmdPeekTask -Task 'list processes' -History @() -Catalog $catalog
        @($result.missing | ForEach-Object { $_.command }) | Should -Not -Contain 'tasklist'
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

Describe 'Compare-CmdPeekCommand' {
    It 'prefers the installed side' {
        $catalog = @{
            'robocopy' = [pscustomobject]@{
                category = 'system'; origin = 'builtin'; os = @('windows')
                usages = @('robocopy src dst /E  # Copy tree')
                whenToUse = 'Windows trees'
                gotchas = @('Exit codes 0-7 are success')
                install = [pscustomobject]@{ builtin = $true }
            }
            'Copy-Item' = [pscustomobject]@{
                category = 'system'; origin = 'builtin'
                usages = @('Copy-Item src dst  # Copy')
                whenToUse = 'PowerShell copy'
                install = [pscustomobject]@{ builtin = $true }
            }
        }
        $history = @([pscustomobject]@{ Command = 'robocopy'; PackageManager = 'builtin'; OnPath = $true })
        $cmp = Compare-CmdPeekCommand -Left robocopy -Right Copy-Item -History $history -Catalog $catalog
        $cmp.prefer | Should -Be 'robocopy'
        $cmp.left.installed | Should -BeTrue
        $cmp.right.installed | Should -BeFalse
    }
}

Describe 'Get-CmdPeekArgvSuggestion' {
    It 'maps ps aux toward an installed process tool' {
        $catalog = @{
            'ps' = [pscustomobject]@{
                category = 'system'; origin = 'builtin'; os = @('linux', 'macos')
                capabilities = @('process'); tasks = @('list processes')
                usages = @('ps aux  # All processes')
                substitutes = @('tasklist', 'Get-Process')
                install = [pscustomobject]@{ builtin = $true }
            }
            'tasklist' = [pscustomobject]@{
                category = 'system'; origin = 'builtin'; os = @('windows')
                capabilities = @('process'); tasks = @('list processes')
                usages = @('tasklist  # List processes')
                substitutes = @('ps', 'Get-Process')
                install = [pscustomobject]@{ builtin = $true }
            }
            'Get-Process' = [pscustomobject]@{
                category = 'system'; origin = 'builtin'
                capabilities = @('process'); tasks = @('list processes')
                usages = @('Get-Process  # Process objects')
                substitutes = @('tasklist', 'ps')
                install = [pscustomobject]@{ builtin = $true }
            }
        }
        $history = @([pscustomobject]@{ Command = 'Get-Process'; PackageManager = 'builtin'; OnPath = $true })
        $sug = Get-CmdPeekArgvSuggestion -Argv 'ps aux' -History $history -Catalog $catalog
        $sug.recommended.command | Should -Be 'Get-Process'
        $sug.example | Should -Match 'Get-Process'
    }
}
