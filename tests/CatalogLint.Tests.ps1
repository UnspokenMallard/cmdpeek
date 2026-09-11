#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\cmdpeek.psd1') -Force
    $script:schemaPath = Join-Path $PSScriptRoot '..\examples\usage-examples.schema.json'
    $script:schema = Get-Content -LiteralPath $script:schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

Describe 'Test-CmdPeekJsonSchema' {
    It 'accepts a minimal valid catalog' {
        $doc = '{"commands":{"fd":{"usages":["fd foo"]}}}' | ConvertFrom-Json

        @(Test-CmdPeekJsonSchema -Schema $script:schema -Value $doc) | Should -BeNullOrEmpty
    }

    It 'requires the commands property' {
        $doc = '{"kits":{}}' | ConvertFrom-Json

        $problems = @(Test-CmdPeekJsonSchema -Schema $script:schema -Value $doc)
        ($problems -join "`n") | Should -Match "missing required property 'commands'"
    }

    It 'requires usages on every command' {
        $doc = '{"commands":{"fd":{"category":"files"}}}' | ConvertFrom-Json

        $problems = @(Test-CmdPeekJsonSchema -Schema $script:schema -Value $doc)
        ($problems -join "`n") | Should -Match "commands.fd is missing required property 'usages'"
    }

    It 'rejects an empty usages array' {
        $doc = '{"commands":{"fd":{"usages":[]}}}' | ConvertFrom-Json

        $problems = @(Test-CmdPeekJsonSchema -Schema $script:schema -Value $doc)
        ($problems -join "`n") | Should -Match 'needs at least 1'
    }

    It 'rejects a typo in a property name' {
        $doc = '{"commands":{"fd":{"usages":["fd foo"],"whentouse":"x"}}}' | ConvertFrom-Json

        $problems = @(Test-CmdPeekJsonSchema -Schema $script:schema -Value $doc)
        ($problems -join "`n") | Should -Match "unknown property 'whentouse'"
    }

    It 'rejects a value outside an enum' {
        $doc = '{"commands":{"fd":{"usages":["fd foo"],"os":["solaris"]}}}' | ConvertFrom-Json

        $problems = @(Test-CmdPeekJsonSchema -Schema $script:schema -Value $doc)
        ($problems -join "`n") | Should -Match "commands.fd.os\[0\] is 'solaris'"
    }

    It 'rejects the wrong type for a property' {
        $doc = '{"commands":{"fd":{"usages":"fd foo"}}}' | ConvertFrom-Json

        $problems = @(Test-CmdPeekJsonSchema -Schema $script:schema -Value $doc)
        ($problems -join "`n") | Should -Match 'commands.fd.usages should be array'
    }

    It 'rejects a string where the schema wants an object' {
        $doc = '{"commands":"nope"}' | ConvertFrom-Json

        $problems = @(Test-CmdPeekJsonSchema -Schema $script:schema -Value $doc)
        ($problems -join "`n") | Should -Match 'commands should be object'
    }

    It 'accepts both string and boolean install values through oneOf' {
        $doc = '{"commands":{"cd":{"usages":["cd .."],"install":{"builtin":true,"scoop":"cd"}}}}' | ConvertFrom-Json

        @(Test-CmdPeekJsonSchema -Schema $script:schema -Value $doc) | Should -BeNullOrEmpty
    }

    It 'rejects an install value that is neither string nor boolean' {
        $doc = '{"commands":{"cd":{"usages":["cd .."],"install":{"scoop":42}}}}' | ConvertFrom-Json

        $problems = @(Test-CmdPeekJsonSchema -Schema $script:schema -Value $doc)
        ($problems -join "`n") | Should -Match 'does not match exactly one of the allowed shapes'
    }
}

Describe 'Get-CmdPeekCatalogCoverage' {
    It 'counts filled agent-facing fields and names what is missing' {
        $doc = @'
{"commands":{
  "a":{"usages":["a"],"whenToUse":"use a","gotchas":["careful"]},
  "b":{"usages":["b"],"whenToUse":""},
  "c":{"usages":["c"],"gotchas":[]}
}}
'@ | ConvertFrom-Json

        $coverage = @(Get-CmdPeekCatalogCoverage -Document $doc)
        $whenToUse = @($coverage | Where-Object { $_.field -eq 'whenToUse' })[0]
        $whenToUse.have | Should -Be 1
        $whenToUse.total | Should -Be 3
        $whenToUse.percent | Should -Be 33
        $whenToUse.missing | Should -Contain 'b'
        $whenToUse.missing | Should -Contain 'c'

        $gotchas = @($coverage | Where-Object { $_.field -eq 'gotchas' })[0]
        $gotchas.have | Should -Be 1
        $gotchas.missing | Should -Contain 'c'
    }
}

Describe 'Test-CmdPeekCatalogFile' {
    It 'reports a missing file rather than throwing' {
        $r = Test-CmdPeekCatalogFile -Path (Join-Path $TestDrive 'nope.json')
        ($r.errors -join "`n") | Should -Match 'File not found'
    }

    It 'reports unparseable JSON' {
        $bad = Join-Path $TestDrive 'broken.json'
        '{ not json' | Set-Content -LiteralPath $bad -Encoding UTF8

        $r = Test-CmdPeekCatalogFile -Path $bad
        ($r.errors -join "`n") | Should -Match 'Not valid JSON'
    }

    It 'leaves cross-file references alone when told to skip them' {
        $file = Join-Path $TestDrive 'xref.json'
        '{"commands":{"rg":{"usages":["rg foo"],"substitutes":["Select-String"]}}}' |
            Set-Content -LiteralPath $file -Encoding UTF8

        $withXref = Test-CmdPeekCatalogFile -Path $file
        ($withXref.errors -join "`n") | Should -Match "substitute 'Select-String' is not a catalog command"

        $withoutXref = Test-CmdPeekCatalogFile -Path $file -SkipCrossReference
        @($withoutXref.errors) | Should -BeNullOrEmpty
    }

    It 'returns the parsed catalog so callers can merge files' {
        $file = Join-Path $TestDrive 'small.json'
        '{"commands":{"rg":{"usages":["rg foo"]}},"kits":{"search":["rg"]}}' |
            Set-Content -LiteralPath $file -Encoding UTF8

        $r = Test-CmdPeekCatalogFile -Path $file
        $r.commands | Should -Be 1
        $r.kits | Should -Be 1
        $r.catalog.Keys | Should -Contain 'rg'
        $r.kitMap.Keys | Should -Contain 'search'
    }
}

Describe 'Invoke-CmdPeekCatalogLint' {
    It 'finds the shipped catalog files valid and fully cross-referenced' {
        $lint = Invoke-CmdPeekCatalogLint

        @($lint.files).Count | Should -Be 2
        foreach ($f in @($lint.files)) {
            @($f.errors) | Should -BeNullOrEmpty -Because "$($f.path) should be schema valid"
        }
        @($lint.crossReference) | Should -BeNullOrEmpty
        $lint.errorCount | Should -Be 0
        $lint.commands | Should -BeGreaterThan 100
    }

    It 'resolves references across the files it was given, not within each one' {
        $a = Join-Path $TestDrive 'merge-a.json'
        $b = Join-Path $TestDrive 'merge-b.json'
        '{"commands":{"rg":{"usages":["rg foo"],"substitutes":["Select-String"]}}}' | Set-Content -LiteralPath $a -Encoding UTF8
        '{"commands":{"Select-String":{"usages":["Select-String foo"]}}}' | Set-Content -LiteralPath $b -Encoding UTF8

        $lint = Invoke-CmdPeekCatalogLint -Path @($a, $b)

        @($lint.crossReference) | Should -BeNullOrEmpty
        $lint.errorCount | Should -Be 0
        $lint.commands | Should -Be 2
    }

    It 'still reports a reference that no given file defines' {
        $a = Join-Path $TestDrive 'merge-only-a.json'
        '{"commands":{"rg":{"usages":["rg foo"],"substitutes":["nosuchtool"]}}}' | Set-Content -LiteralPath $a -Encoding UTF8

        $lint = Invoke-CmdPeekCatalogLint -Path @($a)

        ($lint.crossReference -join "`n") | Should -Match "substitute 'nosuchtool' is not a catalog command"
        $lint.errorCount | Should -Be 1
    }
}

Describe 'Format-CmdPeekCatalogLint' {
    It 'renders coverage bars, a merged summary, and a clean verdict' {
        $lint = Invoke-CmdPeekCatalogLint

        $text = Format-CmdPeekCatalogLint -Lint $lint
        $text | Should -Match 'schema valid'
        $text | Should -Match 'agent-facing field coverage'
        $text | Should -Match 'whenToUse'
        $text | Should -Match 'every related, substitute, and kit member resolves'
        $text | Should -Match 'No catalog errors\.'
    }

    It 'renders errors and a count' {
        $a = Join-Path $TestDrive 'fmt-bad.json'
        '{"commands":{"rg":{"usages":["rg foo"],"related":["nosuchtool"]}}}' | Set-Content -LiteralPath $a -Encoding UTF8

        $text = Format-CmdPeekCatalogLint -Lint (Invoke-CmdPeekCatalogLint -Path @($a))
        $text | Should -Match '! Command .rg. related .nosuchtool.'
        $text | Should -Match '1 catalog error'
    }
}
