#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:cli = Join-Path $PSScriptRoot '..\src\cmdpeek.ps1'
    $script:shell = (Get-Process -Id $PID).Path
    if (-not $script:shell) { $script:shell = 'pwsh' }

    $script:runCli = {
        param([string[]]$CliArgument)
        $out = Join-Path $TestDrive ('cli-' + [guid]::NewGuid().ToString('N') + '.out')
        $err = [System.IO.Path]::ChangeExtension($out, '.err')
        $all = @('-NoProfile', '-File', $script:cli) + $CliArgument
        $proc = Start-Process -FilePath $script:shell -ArgumentList $all -NoNewWindow -PassThru -Wait `
            -RedirectStandardOutput $out -RedirectStandardError $err
        $stdout = ''
        $stderr = ''
        if (Test-Path -LiteralPath $out) { $stdout = (Get-Content -LiteralPath $out -Raw) }
        if (Test-Path -LiteralPath $err) { $stderr = (Get-Content -LiteralPath $err -Raw) }
        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            StdOut   = [string]$stdout
            StdErr   = [string]$stderr
        }
    }
}

Describe 'cmdpeek.ps1 argument handling' {
    It 'reports an unknown option instead of treating it as a search term' {
        $r = & $script:runCli @('for', 'json', '--nosuchflag')

        $r.ExitCode | Should -Be 2
        $r.StdErr | Should -Match 'unknown option --nosuchflag'
        $r.StdErr | Should -Match "cmdpeek --help"
    }

    It 'reports a misspelled switch' {
        $r = & $script:runCli @('-Jsonn')

        $r.ExitCode | Should -Be 2
        $r.StdErr | Should -Match 'unknown option -Jsonn'
    }

    It 'does not mistake a negative-looking word inside a quoted argument for an option' {
        $r = & $script:runCli @('--version')

        $r.ExitCode | Should -Be 0
        $r.StdOut | Should -Match 'cmdpeek \d+\.\d+\.\d+'
    }

    It 'accepts version as a verb' {
        $r = & $script:runCli @('version')

        $r.ExitCode | Should -Be 0
        $r.StdOut | Should -Match 'cmdpeek \d+\.\d+\.\d+'
    }

    It 'forwards -DataDirectory instead of reading it as a positional value' {
        $data = Join-Path $TestDrive 'cli-data'

        $r = & $script:runCli @('doctor', '-Json', '-DataDirectory', $data)

        $r.ExitCode | Should -Be 0
        ($r.StdOut | ConvertFrom-Json).dataDirectory.path | Should -Be $data
        # The old behaviour wrote a file named after the flag it did not understand.
        Test-Path -LiteralPath (Join-Path $TestDrive '-DataDirectory*') | Should -BeFalse
    }

    It 'writes the agent playbook to the path given after the verb' {
        $target = Join-Path $TestDrive 'playbook.md'

        $r = & $script:runCli @('agent-export', $target, '-DataDirectory', (Join-Path $TestDrive 'ae-data'))

        $r.ExitCode | Should -Be 0
        Test-Path -LiteralPath $target | Should -BeTrue
        (Get-Content -LiteralPath $target -Raw) | Should -Match 'cmdpeek agent playbook'
    }

    It 'prints help without touching the machine' {
        $r = & $script:runCli @('--help')

        $r.ExitCode | Should -Be 0
        $r.StdOut | Should -Match 'cmdpeek doctor'
        $r.StdOut | Should -Match 'cmdpeek --version'
        $r.StdOut | Should -Match 'cmdpeek gaps'
    }
}
