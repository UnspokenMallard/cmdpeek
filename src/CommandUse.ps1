#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:CmdPeekRecentHistoryLines = 500

function Get-CmdPeekPsReadLineHistoryPath {
    [CmdletBinding()]
    param()

    $paths = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt')
        (Join-Path $env:APPDATA 'Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt')
    )
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($p in $paths) {
        if ($p -and (Test-Path -LiteralPath $p)) { $found.Add($p) }
    }
    return @($found.ToArray())
}

function Get-CmdPeekRusty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [string[]]$HistoryPath,
        [int]$RecentLines = 0
    )

    if ($RecentLines -le 0) { $RecentLines = $script:CmdPeekRecentHistoryLines }

    $files = $HistoryPath
    if (-not $PSBoundParameters.ContainsKey('HistoryPath')) {
        $files = @(Get-CmdPeekPsReadLineHistoryPath)
    }
    if (-not $files) { $files = @() }

    $byName = @{}
    foreach ($row in @($History)) {
        if (-not $row -or -not $row.Command) { continue }
        $key = $row.Command.ToLowerInvariant()
        if (-not $byName.ContainsKey($key)) { $byName[$key] = $row }
    }

    $lastLine = @{}
    $recentAny = @{}
    $seen = @{}
    $anyReadable = $false

    foreach ($path in @($files)) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        $lines = New-Object System.Collections.Generic.List[string]
        try {
            foreach ($raw in @(Get-Content -LiteralPath $path -ErrorAction Stop)) {
                if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                $lines.Add([string]$raw)
            }
        }
        catch {
            continue
        }
        $anyReadable = $true
        $arr = @($lines.ToArray())
        $n = $arr.Count
        $recentStart = $n - $RecentLines
        if ($recentStart -lt 0) { $recentStart = 0 }
        $i = 0
        foreach ($line in $arr) {
            $tok = @($line.Trim() -split '\s+')
            if ($tok.Count -eq 0) { $i++; continue }
            $cmd = [string]$tok[0]
            $key = $cmd.ToLowerInvariant()
            if (-not $byName.ContainsKey($key)) { $i++; continue }
            $seen[$key] = $true
            $lastLine[$key] = $line
            if ($i -ge $recentStart) { $recentAny[$key] = $true }
            $i++
        }
    }

    if (-not $anyReadable) { return @() }

    $never = New-Object System.Collections.Generic.List[object]
    $stale = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($byName.Keys)) {
        $row = $byName[$key]
        $usages = @()
        if ($row.PSObject.Properties['Usages'] -and $row.Usages) { $usages = @($row.Usages | Select-Object -First 3) }
        if (-not $seen.ContainsKey($key)) {
            $never.Add([pscustomobject]@{
                Command        = [string]$row.Command
                kind           = 'never'
                LastLine       = ''
                PackageManager = [string]$row.PackageManager
                Usages         = $usages
            })
            continue
        }
        if ($recentAny.ContainsKey($key)) { continue }
        $stale.Add([pscustomobject]@{
            Command        = [string]$row.Command
            kind           = 'stale'
            LastLine       = [string]$lastLine[$key]
            PackageManager = [string]$row.PackageManager
            Usages         = $usages
        })
    }

    $neverArr = @($never.ToArray())
    if ($neverArr.Count -gt 1) { $neverArr = @($neverArr | Sort-Object { $_.Command.ToLowerInvariant() }) }
    $staleArr = @($stale.ToArray())
    if ($staleArr.Count -gt 1) { $staleArr = @($staleArr | Sort-Object { $_.Command.ToLowerInvariant() }) }
    return @($neverArr + $staleArr)
}
