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

function Get-CmdPeekRustyLastUsedMap {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    $map = @{}
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $map }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $map
    }
    if (-not $raw -or -not $raw.PSObject.Properties['commands'] -or -not $raw.commands) { return $map }
    foreach ($prop in $raw.commands.PSObject.Properties) {
        $key = $prop.Name.ToLowerInvariant()
        $val = $prop.Value
        $at = $null
        $line = ''
        if ($val -and $val.PSObject.Properties['lastUsedAt'] -and $val.lastUsedAt) {
            try { $at = [datetime]$val.lastUsedAt } catch { $at = $null }
        }
        if ($val -and $val.PSObject.Properties['lastLine'] -and $val.lastLine) {
            $line = [string]$val.lastLine
        }
        $map[$key] = [pscustomobject]@{ LastUsedAt = $at; LastLine = $line }
    }
    return $map
}

function Get-CmdPeekRustyLastUsedPath {
    [CmdletBinding()]
    param(
        [string]$DataDirectory
    )

    if (Get-Command Get-CmdPeekDataDirectory -ErrorAction SilentlyContinue) {
        return (Join-Path (Get-CmdPeekDataDirectory -DataDirectory $DataDirectory) 'rusty-last-used.json')
    }
    if ($DataDirectory) { return (Join-Path $DataDirectory 'rusty-last-used.json') }
    return $null
}

function Save-CmdPeekRustyLastUsed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [hashtable]$Entries
    )

    if (-not $Path) { return }
    if (-not $Entries) { $Entries = @{} }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $commandObj = New-Object PSObject
    foreach ($key in @($Entries.Keys | Sort-Object)) {
        $e = $Entries[$key]
        $at = $null
        $line = ''
        if ($e -and $e.PSObject.Properties['LastUsedAt'] -and $e.LastUsedAt) {
            try { $at = ([datetime]$e.LastUsedAt).ToUniversalTime().ToString('o') } catch { $at = $null }
        }
        if ($e -and $e.PSObject.Properties['LastLine'] -and $e.LastLine) {
            $line = [string]$e.LastLine
        }
        $commandObj | Add-Member -NotePropertyName ([string]$key) -NotePropertyValue ([pscustomobject]@{
            lastUsedAt = $at
            lastLine   = $line
        })
    }
    $payload = [pscustomobject]@{
        schemaVersion = 1
        commands      = $commandObj
    }
    ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-CmdPeekRustyLastUsedLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [string]$DataDirectory,
        [string]$Path
    )

    $parsed = Split-CmdPeekHistoryLine -Line $Line
    if (-not $parsed.Command) { return }
    if (-not $Path) {
        $Path = Get-CmdPeekRustyLastUsedPath -DataDirectory $DataDirectory
    }
    if (-not $Path) { return }
    $map = Get-CmdPeekRustyLastUsedMap -Path $Path
    $key = $parsed.Command.ToLowerInvariant()
    $at = $parsed.LastUsedAt
    if (-not $at) { $at = [datetime]::UtcNow }
    $map[$key] = [pscustomobject]@{
        LastUsedAt = $at
        LastLine   = $parsed.Text
    }
    Save-CmdPeekRustyLastUsed -Path $Path -Entries $map
}

function Add-CmdPeekHistoryTimestamp {
    [CmdletBinding()]
    param(
        [string]$DataDirectory,
        [string]$LastUsedPath
    )

    if ($script:CmdPeekHistoryTimestampRegistered) { return }
    if (-not (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)) { return }

    $previous = $null
    try {
        $opt = Get-PSReadLineOption -ErrorAction Stop
        if ($opt.AddToHistoryHandler) {
            $existing = [string]$opt.AddToHistoryHandler
            if ($existing.Contains('Write-CmdPeekRustyLastUsedLine')) {
                $script:CmdPeekHistoryTimestampRegistered = $true
                return
            }
            $previous = $opt.AddToHistoryHandler
        }
    }
    catch {
        return
    }

    $dataDir = $DataDirectory
    $usedPath = $LastUsedPath
    Set-PSReadLineOption -AddToHistoryHandler {
        param($line)
        if ($previous) {
            try {
                $keep = & $previous $line
                if ($keep -eq $false) { return $false }
            }
            catch { }
        }
        try {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-CmdPeekRustyLastUsedLine -Line $line -DataDirectory $dataDir -Path $usedPath
            }
        }
        catch { }
        return $true
    }
    $script:CmdPeekHistoryTimestampRegistered = $true
}

function Split-CmdPeekHistoryLine {
    param([string]$Line)

    $text = $Line.Trim()
    $at = $null
    if ($text -match '^(#\s*)?(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?)\s+(.+)$') {
        try { $at = [datetime]$Matches[2] } catch { $at = $null }
        $text = $Matches[3].Trim()
    }
    $tok = @($text -split '\s+')
    $cmd = ''
    if ($tok.Count -gt 0) { $cmd = [string]$tok[0] }
    return [pscustomobject]@{ Command = $cmd; Text = $text; LastUsedAt = $at }
}

function Get-CmdPeekRusty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [string[]]$HistoryPath,
        [int]$RecentLines = 0,
        [string]$LastUsedPath,
        [switch]$PersistLastUsed
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
    $lastUsedFromHist = @{}
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
            $parsed = Split-CmdPeekHistoryLine -Line $line
            $key = $parsed.Command.ToLowerInvariant()
            if (-not $key -or -not $byName.ContainsKey($key)) { $i++; continue }
            $seen[$key] = $true
            $lastLine[$key] = $parsed.Text
            if ($parsed.LastUsedAt) { $lastUsedFromHist[$key] = $parsed.LastUsedAt }
            if ($i -ge $recentStart) { $recentAny[$key] = $true }
            $i++
        }
    }

    if (-not $anyReadable) { return @() }

    $overlay = Get-CmdPeekRustyLastUsedMap -Path $LastUsedPath

    $never = New-Object System.Collections.Generic.List[object]
    $stale = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($byName.Keys)) {
        $row = $byName[$key]
        $usages = @()
        if ($row.PSObject.Properties['Usages'] -and $row.Usages) { $usages = @($row.Usages | Select-Object -First 3) }
        $usedAt = $null
        $overlayLine = ''
        if ($lastUsedFromHist.ContainsKey($key)) { $usedAt = $lastUsedFromHist[$key] }
        if ($overlay.ContainsKey($key)) {
            if ($overlay[$key].LastUsedAt) { $usedAt = $overlay[$key].LastUsedAt }
            if ($overlay[$key].LastLine) { $overlayLine = [string]$overlay[$key].LastLine }
        }
        if (-not $seen.ContainsKey($key)) {
            $never.Add([pscustomobject]@{
                Command        = [string]$row.Command
                kind           = 'never'
                LastLine       = $overlayLine
                LastUsedAt     = $usedAt
                PackageManager = [string]$row.PackageManager
                Usages         = $usages
            })
            continue
        }
        if ($recentAny.ContainsKey($key)) { continue }
        $staleLine = [string]$lastLine[$key]
        if (-not $staleLine -and $overlayLine) { $staleLine = $overlayLine }
        $stale.Add([pscustomobject]@{
            Command        = [string]$row.Command
            kind           = 'stale'
            LastLine       = $staleLine
            LastUsedAt     = $usedAt
            PackageManager = [string]$row.PackageManager
            Usages         = $usages
        })
    }

    $neverArr = @($never.ToArray())
    if ($neverArr.Count -gt 1) { $neverArr = @($neverArr | Sort-Object { $_.Command.ToLowerInvariant() }) }
    $staleArr = @($stale.ToArray())
    if ($staleArr.Count -gt 1) { $staleArr = @($staleArr | Sort-Object { $_.Command.ToLowerInvariant() }) }

    if ($PersistLastUsed -and $LastUsedPath) {
        $persist = @{}
        foreach ($k in @($overlay.Keys)) { $persist[$k] = $overlay[$k] }
        foreach ($k in @($lastUsedFromHist.Keys)) {
            $line = ''
            if ($lastLine.ContainsKey($k)) { $line = [string]$lastLine[$k] }
            $persist[$k] = [pscustomobject]@{ LastUsedAt = $lastUsedFromHist[$k]; LastLine = $line }
        }
        Save-CmdPeekRustyLastUsed -Path $LastUsedPath -Entries $persist
    }

    return @($neverArr + $staleArr)
}
