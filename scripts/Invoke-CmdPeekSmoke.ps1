#Requires -Version 5.1
<#
.SYNOPSIS
    End-to-end smoke test: run cmdpeek against the real machine and check the answers.
.DESCRIPTION
    The unit tests all drive cmdpeek against fixture roots, which means a change that
    only breaks on a real populated machine passes them. This script runs the actual
    CLI against the actual package managers and PATH, and fails if a command exits
    non-zero, times out, emits unparseable JSON, or hands back an unbounded payload.

    Each check receives one object with ExitCode, StdOut, Json, and Bytes, and returns
    zero or more problem strings.
.EXAMPLE
    ./scripts/Invoke-CmdPeekSmoke.ps1
.EXAMPLE
    ./scripts/Invoke-CmdPeekSmoke.ps1 -TimeoutSeconds 600 -DataDirectory ./tmp-smoke
#>
[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 300,
    [string]$DataDirectory,
    [int]$MaxGapRows = 60,
    [int]$MaxOutputBytes = 8MB
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$cliPath = Join-Path $repoRoot 'src/cmdpeek.ps1'
if (-not (Test-Path -LiteralPath $cliPath)) {
    throw "cmdpeek.ps1 not found at $cliPath"
}

if (-not $DataDirectory) {
    $DataDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('cmdpeek-smoke-' + [guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null

# Promoted to script scope so the nested runner and the check blocks can see them.
$script:cli = $cliPath
$script:dataDir = $DataDirectory
$script:timeout = $TimeoutSeconds
$script:gapBudget = $MaxGapRows
$script:byteBudget = $MaxOutputBytes
$script:shell = 'pwsh'
if (-not (Get-Command $script:shell -ErrorAction SilentlyContinue)) { $script:shell = 'powershell' }
$script:failures = New-Object System.Collections.Generic.List[string]
$script:results = New-Object System.Collections.Generic.List[object]

function Invoke-CmdPeekSmokeCase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Argument,
        [int]$ExpectExitCode = 0,
        [switch]$ExpectJson,
        [scriptblock]$Check
    )

    $stdoutFile = Join-Path $script:dataDir ('smoke-' + ($Name -replace '[^A-Za-z0-9]', '-') + '.out')
    $stderrFile = [System.IO.Path]::ChangeExtension($stdoutFile, '.err')
    $all = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:cli,
        '-NonInteractive', '-DataDirectory', $script:dataDir
    ) + $Argument

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $script:shell -ArgumentList $all -NoNewWindow -PassThru `
        -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    $finished = $proc.WaitForExit($script:timeout * 1000)
    if (-not $finished) {
        try { $proc.Kill() } catch { }
        $sw.Stop()
        $script:failures.Add("$Name timed out after $($script:timeout)s")
        $script:results.Add([pscustomobject]@{ name = $Name; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); exit = 'timeout'; bytes = 0 })
        return
    }
    $sw.Stop()

    $stdout = ''
    $stderr = ''
    if (Test-Path -LiteralPath $stdoutFile) { $stdout = Get-Content -LiteralPath $stdoutFile -Raw }
    if (Test-Path -LiteralPath $stderrFile) { $stderr = Get-Content -LiteralPath $stderrFile -Raw }
    if ($null -eq $stdout) { $stdout = '' }
    if ($null -eq $stderr) { $stderr = '' }
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($stdout)

    $script:results.Add([pscustomobject]@{
            name    = $Name
            seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            exit    = $proc.ExitCode
            bytes   = $bytes
        })

    if ($proc.ExitCode -ne $ExpectExitCode) {
        $head = (@($stderr -split "`n" | Select-Object -First 5) -join "`n    ")
        $script:failures.Add("$Name exited $($proc.ExitCode), expected $ExpectExitCode`n    $head")
        return
    }

    if ($ExpectExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($stdout)) {
        $script:failures.Add("$Name produced no output")
        return
    }

    if ($bytes -gt $script:byteBudget) {
        $script:failures.Add("$Name produced $bytes bytes, over the $($script:byteBudget) byte budget")
    }

    $json = $null
    if ($ExpectJson) {
        try { $json = $stdout | ConvertFrom-Json }
        catch {
            $script:failures.Add("$Name did not emit parseable JSON: $($_.Exception.Message)")
            return
        }
    }

    if ($Check) {
        $result = [pscustomobject]@{
            ExitCode = $proc.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
            Json     = $json
            Bytes    = $bytes
        }
        foreach ($problem in @(& $Check $result)) {
            if ($problem) { $script:failures.Add("${Name}: $problem") }
        }
    }
}

Write-Host "cmdpeek smoke test  (shell $($script:shell), data $($script:dataDir))"
Write-Host ''

Invoke-CmdPeekSmokeCase -Name 'version' -Argument @('-Version') -Check {
    param($r)
    if ($r.StdOut -notmatch 'cmdpeek \d+\.\d+\.\d+') { 'did not print a version' }
    if ($r.StdOut -match 'does not match the module') { 'module and MCP versions disagree' }
}

Invoke-CmdPeekSmokeCase -Name 'doctor' -Argument @('-Doctor', '-Json') -ExpectJson -Check {
    param($r)
    if (-not $r.Json.version.inSync) { "version drift: module $($r.Json.version.module) vs mcp $($r.Json.version.mcp)" }
    if (-not $r.Json.dataDirectory.writable) { 'data directory is not writable' }
    $errs = @($r.Json.catalog.errors)
    if ($errs.Count -gt 0) { "catalog has $($errs.Count) validation error(s), first: $($errs[0])" }
    if ([int]$r.Json.catalog.commands -le 0) { 'catalog loaded zero commands' }
}

# The expensive one. This is the call that used to run for 15 minutes without
# finishing, so the timeout is the assertion that matters most here.
Invoke-CmdPeekSmokeCase -Name 'inventory refresh' -Argument @('-Json', '-Refresh') -ExpectJson -Check {
    param($r)
    if (@($r.Json.commands).Count -le 0) { 'inventory contains no commands' }
    if (-not $r.Json.PSObject.Properties['gapSummary']) { 'snapshot has no gapSummary' }
    foreach ($row in @($r.Json.commands | Select-Object -First 50)) {
        if (-not $row.command) { 'a command row has no name'; break }
    }
}

Invoke-CmdPeekSmokeCase -Name 'inventory cached' -Argument @('-Json') -ExpectJson -Check {
    param($r)
    if (@($r.Json.commands).Count -le 0) { 'cached inventory contains no commands' }
}

Invoke-CmdPeekSmokeCase -Name 'gaps' -Argument @('-Gaps', '-Json') -ExpectJson -Check {
    param($r)
    $rows = @($r.Json.gaps)
    if ($rows.Count -gt $script:gapBudget) { "returned $($rows.Count) gaps, over the $($script:gapBudget) row budget" }
    if (-not $r.Json.summary) { 'gaps payload has no summary' }
    foreach ($row in $rows) {
        if ($row.kind -eq 'thin-docs') { 'default gap answer still includes thin-docs'; break }
    }
}

Invoke-CmdPeekSmokeCase -Name 'gaps thin-docs' -Argument @('-Gaps', '-Json', '-GapKind', 'thin-docs', '-GapLimit', '5') -ExpectJson -Check {
    param($r)
    $rows = @($r.Json.gaps)
    if ($rows.Count -gt 5) { "-GapLimit 5 returned $($rows.Count) rows" }
    foreach ($row in $rows) {
        if ($row.kind -ne 'thin-docs') { "asked for thin-docs but got $($row.kind)"; break }
    }
}

Invoke-CmdPeekSmokeCase -Name 'resolve task' -Argument @('for', 'json', '-Json') -ExpectJson -Check {
    param($r)
    if (-not $r.Json.PSObject.Properties['installed'] -and -not $r.Json.PSObject.Properties['missing']) {
        'task result has neither installed nor missing, so the inventory snapshot leaked through'
    }
}

Invoke-CmdPeekSmokeCase -Name 'explain' -Argument @('explain', 'cd') -Check {
    param($r)
    if ($r.StdOut.Trim().Length -lt 5) { 'explain produced almost nothing' }
    # cd is a shell alias on every platform cmdpeek runs on, so there is no package
    # to install and no manager that could install one. Offering a line here is the
    # exact hallucination cmdpeek exists to stop.
    if ($r.StdOut -match '(?im)^\s*install:') { 'explain offered to install a shell builtin' }
    if ($r.StdOut -notmatch '(?im)builtin') { 'explain did not recognise a shell builtin' }
}

Invoke-CmdPeekSmokeCase -Name 'explain catalog entry' -Argument @('explain', 'jq') -Check {
    param($r)
    foreach ($field in @('origin:', 'when:')) {
        if ($r.StdOut -notmatch [regex]::Escape($field)) { "explain omitted $field" }
    }
}

Invoke-CmdPeekSmokeCase -Name 'system list' -Argument @('-Json', '-Category', 'system') -ExpectJson

Invoke-CmdPeekSmokeCase -Name 'agent export' -Argument @('agent-export') -Check {
    param($r)
    if ($r.StdOut -notmatch '(?m)^### ') { 'agent export listed no tools' }
}

Invoke-CmdPeekSmokeCase -Name 'human quick view' -Argument @('-n', '5')

Invoke-CmdPeekSmokeCase -Name 'unknown option' -Argument @('for', 'json', '--nosuchflag') -ExpectExitCode 2 -Check {
    param($r)
    if ($r.StdErr -notmatch 'unknown option') { 'exited 2 without saying which option was unknown' }
}

Write-Host ('{0,-20} {1,8} {2,8} {3,12}' -f 'case', 'seconds', 'exit', 'bytes')
Write-Host ('{0,-20} {1,8} {2,8} {3,12}' -f '------------------', '-------', '----', '-----------')
foreach ($row in $script:results) {
    Write-Host ('{0,-20} {1,8} {2,8} {3,12:N0}' -f $row.name, $row.seconds, $row.exit, $row.bytes)
}
Write-Host ''

if ($script:failures.Count -gt 0) {
    Write-Host "$($script:failures.Count) smoke failure(s):" -ForegroundColor Red
    foreach ($f in $script:failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host "All $($script:results.Count) smoke cases passed." -ForegroundColor Green
exit 0
