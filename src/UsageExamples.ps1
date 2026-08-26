#Requires -Version 5.1
Set-StrictMode -Version Latest

if (-not (Get-Command Read-CmdPeekCatalogFile -ErrorAction SilentlyContinue)) {
    $catalogHelper = Join-Path $PSScriptRoot 'Catalog.ps1'
    if (Test-Path -LiteralPath $catalogHelper) {
        . $catalogHelper
    }
}

function Get-CmdPeekExampleCatalogPath {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ($Path) { return $Path }

    $candidates = @(
        (Join-Path $PSScriptRoot 'examples\usage-examples.json'),
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'examples\usage-examples.json')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return $null
}

function Get-CmdPeekExampleCatalog {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$DataDirectory,
        [string]$OverlayPath
    )

    $resolved = Get-CmdPeekExampleCatalogPath -Path $Path
    $parsed = Read-CmdPeekCatalogFile -Path $resolved
    $map = @{}
    if ($parsed -and $parsed.Commands) { $map = $parsed.Commands }

    $overlay = $OverlayPath
    if (-not $overlay -and $DataDirectory) {
        $overlay = Get-CmdPeekOverlayCatalogPath -DataDirectory $DataDirectory
    }
    if ($overlay -and (Test-Path -LiteralPath $overlay)) {
        $over = Read-CmdPeekCatalogFile -Path $overlay
        $map = Merge-CmdPeekCatalogHashtable -Base $map -Overlay $over.Commands
    }

    return $map
}

function Get-CmdPeekCatalogKits {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$DataDirectory,
        [string]$OverlayPath
    )

    $resolved = Get-CmdPeekExampleCatalogPath -Path $Path
    $parsed = Read-CmdPeekCatalogFile -Path $resolved
    $kits = @{}
    if ($parsed -and $parsed.Kits) { $kits = $parsed.Kits }

    $overlay = $OverlayPath
    if (-not $overlay -and $DataDirectory) {
        $overlay = Get-CmdPeekOverlayCatalogPath -DataDirectory $DataDirectory
    }
    if ($overlay -and (Test-Path -LiteralPath $overlay)) {
        $over = Read-CmdPeekCatalogFile -Path $overlay
        $kits = Merge-CmdPeekCatalogHashtable -Base $kits -Overlay $over.Kits
    }

    return $kits
}

function Get-CmdPeekCatalogEntry {
    param(
        [string]$Command,
        [hashtable]$Catalog
    )

    if (-not $Catalog -or -not $Command) { return $null }
    $needle = $Command.ToLowerInvariant()
    foreach ($key in $Catalog.Keys) {
        if ($key.ToLowerInvariant() -eq $needle) {
            return $Catalog[$key]
        }
    }
    foreach ($key in $Catalog.Keys) {
        $aliases = @(Get-CmdPeekCatalogAliasList -Entry $Catalog[$key])
        foreach ($alias in $aliases) {
            if ($alias.ToLowerInvariant() -eq $needle) {
                return $Catalog[$key]
            }
        }
    }
    return $null
}

function Get-CmdPeekUsageExample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [hashtable]$Catalog,
        [int]$Count = 3,
        [string]$HelpText,
        [scriptblock]$HelpRunner,
        [string]$DataDirectory,
        [switch]$SkipHelpProbe
    )

    if ($Count -lt 1) { $Count = 1 }
    $entry = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    $usages = @(Get-CmdPeekCatalogUsageList -Entry $entry)

    $usages = @(Select-CmdPeekDisplayUsage -Usage $usages -Count $Count)
    if ($usages.Count -gt 0) {
        return @($usages)
    }

    $help = Get-CmdPeekBuiltinHelpExample -Command $Command
    if ($help -and -not (Test-CmdPeekGenericHelpUsage -Usage $help)) {
        $usages = @($help)
    }

    if ($usages.Count -eq 0 -and -not $SkipHelpProbe) {
        try {
            $raw = $HelpText
            if ([string]::IsNullOrWhiteSpace($raw)) {
                $raw = Get-CmdPeekRawHelpText -Command $Command -HelpRunner $HelpRunner -DataDirectory $DataDirectory
            }
            if (-not [string]::IsNullOrWhiteSpace($raw) -and -not (Test-CmdPeekCrashHelpText -Text $raw)) {
                $usages = @(ConvertFrom-CmdPeekHelpText -Command $Command -HelpText $raw -Count $Count)
            }
        }
        catch {
            $usages = @()
        }
    }

    if ($usages.Count -eq 0 -and -not $SkipHelpProbe) {
        $tldr = Get-CmdPeekTldrExample -Command $Command -Count $Count
        if ($tldr -and @($tldr).Count -gt 0) {
            $usages = @($tldr)
        }
    }

    if ($usages.Count -eq 0) {
        $ai = @(Get-CmdPeekMockAiExample -Command $Command -Count $Count -DataDirectory $DataDirectory)
        if ($ai.Count -gt 0) { $usages = @($ai) }
    }

    return @(Select-CmdPeekDisplayUsage -Usage $usages -Count $Count)
}

function Get-CmdPeekMockAiExamplePath {
    param([string]$DataDirectory)

    if ($env:CMDPEEK_OPENAI_MOCK_PATH -and (Test-Path -LiteralPath $env:CMDPEEK_OPENAI_MOCK_PATH)) {
        return $env:CMDPEEK_OPENAI_MOCK_PATH
    }
    if ($DataDirectory) {
        $local = Join-Path $DataDirectory 'openai-examples.json'
        if (Test-Path -LiteralPath $local) { return $local }
    }
    return $null
}

function Get-CmdPeekMockAiExample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [int]$Count = 3,
        [string]$Path,
        [string]$DataDirectory
    )

    if ($Count -lt 1) { $Count = 3 }
    if (-not $Path) { $Path = Get-CmdPeekMockAiExamplePath -DataDirectory $DataDirectory }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return @() }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return @()
    }
    if (-not $raw -or -not $raw.PSObject.Properties['commands'] -or -not $raw.commands) { return @() }
    $prop = $raw.commands.PSObject.Properties | Where-Object { $_.Name -eq $Command } | Select-Object -First 1
    if (-not $prop) {
        $prop = $raw.commands.PSObject.Properties | Where-Object { $_.Name.ToLowerInvariant() -eq $Command.ToLowerInvariant() } | Select-Object -First 1
    }
    if (-not $prop -or -not $prop.Value) { return @() }
    $entry = $prop.Value
    $list = @()
    if ($entry.PSObject.Properties['usages'] -and $entry.usages) {
        $list = @(Get-CmdPeekCatalogUsageList -Entry $entry)
    }
    return @(Select-CmdPeekDisplayUsage -Usage $list -Count $Count)
}

function Get-CmdPeekTldrExample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [int]$Count = 3
    )

    if ($Count -lt 1) { $Count = 3 }
    $tldr = $null
    try {
        $tldr = Get-Command tldr -ErrorAction SilentlyContinue
    }
    catch { }
    if (-not $tldr) { return @() }

    $file = $tldr.Source
    if (-not $file) { $file = 'tldr' }
    $result = Invoke-CmdPeekProcessHelp -FilePath $file -Argument $Command -TimeoutMs 2500
    if (-not $result -or -not $result.Text) { return @() }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @($result.Text -split '\r?\n')) {
        $trim = $raw.Trim()
        if ($trim -match '^[`''"](.+)[`''"]$') {
            $cmdLine = $Matches[1].Trim()
            if ($cmdLine -and $lines -notcontains $cmdLine) { $lines.Add($cmdLine) }
        }
        elseif ($trim -match ('^\s*' + [regex]::Escape($Command) + '\b')) {
            if ($lines -notcontains $trim) { $lines.Add($trim) }
        }
        if ($lines.Count -ge $Count) { break }
    }
    return @($lines | Select-Object -First $Count)
}

function Get-CmdPeekHelpCachePath {
    param([string]$DataDirectory)
    $root = $DataDirectory
    if (-not $root) {
        if (Get-Command Get-CmdPeekDataDirectory -ErrorAction SilentlyContinue) {
            $root = Get-CmdPeekDataDirectory
        }
        else {
            $localApp = $env:LOCALAPPDATA
            if (-not $localApp) {
                if ($env:XDG_DATA_HOME) { $localApp = $env:XDG_DATA_HOME }
                elseif ($HOME) { $localApp = Join-Path $HOME '.local/share' }
                else { $localApp = [System.IO.Path]::GetTempPath() }
            }
            $root = Join-Path $localApp 'cmdpeek'
        }
    }
    return (Join-Path $root 'help-cache.json')
}

function Get-CmdPeekCachedHelpText {
    param(
        [string]$Command,
        [string]$DataDirectory
    )

    $path = Get-CmdPeekHelpCachePath -DataDirectory $DataDirectory
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $cache = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
    if (-not $cache) { return $null }
    $prop = $cache.PSObject.Properties | Where-Object { $_.Name -eq $Command } | Select-Object -First 1
    if (-not $prop) { return $null }
    $entry = $prop.Value
    if (-not $entry) { return $null }
    $fetched = $null
    if ($entry.PSObject.Properties['fetchedAt']) {
        try { $fetched = [datetime]$entry.fetchedAt } catch { $fetched = $null }
    }
    $ttlHours = 24
    if (Get-Command Get-CmdPeekState -ErrorAction SilentlyContinue) {
        try {
            $ttlState = Get-CmdPeekState -DataDirectory $DataDirectory
            if ($ttlState -and $ttlState.PSObject.Properties['CacheTtlHours'] -and $ttlState.CacheTtlHours) {
                $ttlHours = [int]$ttlState.CacheTtlHours
            }
        }
        catch { }
    }
    if ($ttlHours -lt 1) { $ttlHours = 24 }
    if ($fetched -and ((Get-Date) - $fetched).TotalHours -gt $ttlHours) { return $null }
    if ($entry.PSObject.Properties['text']) { return [string]$entry.text }
    return $null
}

function Save-CmdPeekCachedHelpText {
    param(
        [string]$Command,
        [string]$Text,
        [string]$DataDirectory
    )

    $dir = $DataDirectory
    if (-not $dir) {
        $cachePath = Get-CmdPeekHelpCachePath -DataDirectory $DataDirectory
        $dir = Split-Path -Parent $cachePath
    }
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $path = Get-CmdPeekHelpCachePath -DataDirectory $DataDirectory
    $map = @{}
    if (Test-Path -LiteralPath $path) {
        try {
            $existing = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existing) {
                foreach ($p in $existing.PSObject.Properties) {
                    $map[$p.Name] = $p.Value
                }
            }
        }
        catch { }
    }
    $map[$Command] = [pscustomobject]@{
        fetchedAt = (Get-Date).ToString('o')
        text      = $Text
    }
    ($map | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding UTF8
}

function Test-CmdPeekCrashHelpText {
    [CmdletBinding()]
    param(
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return [bool]($Text -match '(?i)(FATAL ERROR|JavaScript heap out of memory|Native stack trace|OutOfMemoryException|AccessViolation|Unhandled exception|CmdLineException|Syntax error of parameter|Allocation failed|IsTerminatingError)')
}

function Get-CmdPeekPeSubsystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $null }
        [void]$stream.Seek(0x3C, [System.IO.SeekOrigin]::Begin)
        $peOffset = $reader.ReadInt32()
        if ($peOffset -le 0 -or $peOffset -gt ($stream.Length - 90)) { return $null }
        [void]$stream.Seek($peOffset, [System.IO.SeekOrigin]::Begin)
        if ($reader.ReadUInt32() -ne 0x00004550) { return $null }
        [void]$stream.Seek($peOffset + 24 + 68, [System.IO.SeekOrigin]::Begin)
        return [int]$reader.ReadUInt16()
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

function Invoke-CmdPeekProcessHelp {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string]$Argument,
        [int]$TimeoutMs = 2500
    )

    $proc = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = $Argument
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.ErrorDialog = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $null = $proc.Start()
        try { $proc.StandardInput.Close() } catch { }
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        $exited = $proc.WaitForExit($TimeoutMs)
        if (-not $exited) {
            try {
                $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
                if (Test-Path -LiteralPath $taskkill) {
                    & $taskkill /PID $proc.Id /T /F 2>$null | Out-Null
                }
            }
            catch { }
            try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
            try { $null = $proc.WaitForExit(2000) } catch { }
            return [pscustomobject]@{ Text = $null; Crash = $true }
        }

        $out = ''
        $err = ''
        try { $out = [string]$stdoutTask.GetAwaiter().GetResult() } catch { }
        try { $err = [string]$stderrTask.GetAwaiter().GetResult() } catch { }
        $text = ($out + "`n" + $err).Trim()
        if (Test-CmdPeekCrashHelpText -Text $text) {
            return [pscustomobject]@{ Text = $null; Crash = $true }
        }
        if ($text.Length -lt 8) {
            return [pscustomobject]@{ Text = $null; Crash = $false }
        }
        return [pscustomobject]@{ Text = $text; Crash = $false }
    }
    catch {
        return [pscustomobject]@{ Text = $null; Crash = $true }
    }
    finally {
        if ($proc) { try { $proc.Dispose() } catch { } }
    }
}

function Get-CmdPeekRawHelpText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [scriptblock]$HelpRunner,
        [string]$DataDirectory,
        [int]$TimeoutMs = 2500
    )

    try {
        if ($HelpRunner) {
            try {
                $fromRunner = [string](& $HelpRunner $Command)
                if (Test-CmdPeekCrashHelpText -Text $fromRunner) { return $null }
                return $fromRunner
            }
            catch {
                return $null
            }
        }

        $cached = Get-CmdPeekCachedHelpText -Command $Command -DataDirectory $DataDirectory
        if ($null -ne $cached) {
            if ([string]::IsNullOrWhiteSpace($cached) -or (Test-CmdPeekCrashHelpText -Text $cached)) {
                return $null
            }
            return $cached
        }

        $resolved = Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $resolved) { return $null }
        $file = $null
        if ($resolved.PSObject.Properties['Source'] -and $resolved.Source) { $file = [string]$resolved.Source }
        if (-not $file -or -not (Test-Path -LiteralPath $file)) { return $null }
        if ($file -match '\.(ps1|psm1|cmd|bat)$') { return $null }

        $subsystem = Get-CmdPeekPeSubsystem -Path $file
        if ($subsystem -eq 2) {
            Save-CmdPeekCachedHelpText -Command $Command -Text '' -DataDirectory $DataDirectory
            return $null
        }

        $text = $null
        $argsToTry = @('--help')
        if ($subsystem -eq 3 -or $null -eq $subsystem) {
            $argsToTry += '-h'
        }

        foreach ($arg in $argsToTry) {
            $result = Invoke-CmdPeekProcessHelp -FilePath $file -Argument $arg -TimeoutMs $TimeoutMs
            if ($result.Crash) { break }
            if ($result.Text) {
                $text = $result.Text
                break
            }
        }

        $store = $text
        if (-not $store) { $store = '' }
        Save-CmdPeekCachedHelpText -Command $Command -Text $store -DataDirectory $DataDirectory
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return $text
    }
    catch {
        return $null
    }
}

function Get-CmdPeekHelpComment {
    param([string]$Text, [int]$MaxLength = 72)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $one = ($Text -replace '\s+', ' ').Trim()
    $one = $one -replace '^[^A-Za-z0-9]+', ''
    if ($one -match '^\[.+\]' -or $one -match '^(?i)(options|arguments|flags|commands|usage)\b') {
        return ''
    }
    $cut = $one
    $dot = $one.IndexOf('. ')
    if ($dot -gt 12) { $cut = $one.Substring(0, $dot) }
    if ($cut.Length -gt $MaxLength) { $cut = $cut.Substring(0, $MaxLength).Trim() + '...' }
    return $cut.Trim(' .')
}

function ConvertFrom-CmdPeekHelpText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(Mandatory)]
        [string]$HelpText,
        [int]$Count = 3
    )

    if ($Count -lt 1) { $Count = 3 }
    if (Test-CmdPeekCrashHelpText -Text $HelpText) { return @() }
    $plain = $HelpText -replace '\x1B\[[0-9;]*[A-Za-z]', ''
    $rawLines = @($plain -split '\r?\n')
    $lines = @($rawLines | ForEach-Object { $_.TrimEnd() })

    $found = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    $preamble = ''
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t -match '(?i)^(?:usage|synopsis)\s*:') { break }
        if ($t -match '(?i)^unknown option') { continue }
        if ($t.Length -gt 12 -and $t -notmatch '^\s*-{1,2}\S') {
            if ($t -match ('^' + [regex]::Escape($Command) + '(?:\.exe)?\b')) { continue }
            $preamble = Get-CmdPeekHelpComment -Text $t
            if ($preamble) { break }
        }
    }

    $add = {
        param($CmdLine, $Comment)
        if ([string]::IsNullOrWhiteSpace($CmdLine)) { return }
        $cmdLine = ($CmdLine -replace '\s+', ' ').Trim()
        $cmdLine = $cmdLine -replace '^[\$>]\s+', ''
        if ($cmdLine -match '(^|\s)(--help|-h|-help)(\s|$)') { return }
        if ($cmdLine -match '(?i)unknown option') { return }
        $key = $cmdLine.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        $note = Get-CmdPeekHelpComment -Text $Comment
        if (-not $note) { $note = $preamble }
        if ($note -and $note -eq $cmdLine) { $note = '' }
        if ($note) {
            $found.Add(('{0}  # {1}' -f $cmdLine, $note))
        }
        else {
            $found.Add($cmdLine)
        }
    }

    $inExamples = $false
    $exampleBuf = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $trim = $line.Trim()
        if ($trim -match '^(?i)examples?:\s*$') {
            $inExamples = $true
            continue
        }
        if ($inExamples) {
            if ($trim -match '^(?i)(usage|synopsis|options|arguments|flags|commands):') {
                $inExamples = $false
            }
            elseif ($trim -match '^(?i)[A-Z][\w ]{2,30}:\s*$' -and $trim -notmatch '(?i)^examples?') {
                $inExamples = $false
            }
            elseif ($trim) {
                $exampleBuf.Add($trim)
            }
        }
    }
    foreach ($ex in $exampleBuf) {
        if ($found.Count -ge $Count) { break }
        if ($ex -match [regex]::Escape($Command) -or $ex -match '^\S+\s+\S+') {
            & $add $ex $null
        }
    }

    $usageRegex = [regex]'(?i)^\s*(?:usage|synopsis)\s*:\s*(.+)$'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = $usageRegex.Match($lines[$i])
        if (-not $m.Success) { continue }
        $usage = $m.Groups[1].Value.Trim()
        $usage = $usage -replace ('(?i)[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\)*' + [regex]::Escape($Command) + '(?:\.exe)?'), $Command
        $usage = $usage -replace [regex]::Escape($Command) + '\.exe', $Command
        if ($usage -notmatch [regex]::Escape($Command)) {
            $usage = "$Command $usage"
        }
        $comment = ''
        for ($j = $i + 1; $j -lt [Math]::Min($i + 6, $lines.Count); $j++) {
            $next = $lines[$j].Trim()
            if (-not $next) { continue }
            if ($next -match '(?i)^(options?|flags|arguments|commands|examples)(\s+include)?:') { continue }
            if ($next -match '^\s*-{1,2}\S') { continue }
            $comment = $next
            break
        }
        & $add $usage $comment
        if ($found.Count -ge $Count) { break }
    }

    if ($found.Count -eq 0) {
        foreach ($line in $lines) {
            $trim = $line.Trim()
            if ($trim -match ('^' + [regex]::Escape($Command) + '(?:\.exe)?\b.*\S') -and $trim -notmatch '(?i)unknown option') {
                $usage = $trim -replace [regex]::Escape($Command) + '\.exe', $Command
                $usage = $usage -replace ('(?i)[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\)*' + [regex]::Escape($Command) + '(?:\.exe)?'), $Command
                & $add $usage $null
                if ($found.Count -ge 1) { break }
            }
        }
    }

    if ($found.Count -lt $Count) {
        $flagPattern = [regex]'^\s{1,6}(-{1,2}[A-Za-z][\w\[\]-]*)(?:\s+([A-Z][A-Z0-9_-]*))?\s{2,}(\S.+)$'
        foreach ($line in $lines) {
            if ($found.Count -ge $Count) { break }
            $fm = $flagPattern.Match($line)
            if (-not $fm.Success) { continue }
            $flag = $fm.Groups[1].Value
            $desc = $fm.Groups[3].Value.Trim()
            if ($flag -match '\[') { continue }
            if ($flag -match '(?i)^(--help|-h|-help|--version|-version|-v)$') { continue }
            if ($desc -match '(?i)^(show this|print help|display help|show the version)') { continue }
            & $add ("$Command $flag") $desc
        }
    }

    return @($found | Select-Object -First $Count)
}

function Test-CmdPeekGenericHelpUsage {
    [CmdletBinding()]
    param(
        [string]$Usage
    )

    if ([string]::IsNullOrWhiteSpace($Usage)) { return $true }
    $parts = Split-CmdPeekUsage -Usage $Usage
    return [bool]($parts.Command -match '(^|\s)(--help|-h)(\s|$)')
}

function Split-CmdPeekUsage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Usage
    )

    $text = $Usage.Trim()
    if ($text -match '^(.*?)\s+#\s+(.*)$') {
        return [pscustomobject]@{
            Command = $Matches[1].Trim()
            Comment = $Matches[2].Trim()
        }
    }

    return [pscustomobject]@{
        Command = $text
        Comment = ''
    }
}

function Select-CmdPeekDisplayUsage {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Usage,
        [int]$Count = 3
    )

    if ($Count -lt 1) { $Count = 3 }
    $kept = @(
        @($Usage) |
            Where-Object { $_ -and -not (Test-CmdPeekGenericHelpUsage -Usage $_) } |
            Select-Object -First $Count
    )
    return $kept
}

function Format-CmdPeekAlignedUsage {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Usage,
        [int]$Count = 3,
        [int]$CommentColumn = 0
    )

    $kept = @(Select-CmdPeekDisplayUsage -Usage $Usage -Count $Count)
    $parts = @($kept | ForEach-Object { Split-CmdPeekUsage -Usage $_ })
    if ($parts.Count -eq 0) { return @() }

    $width = $CommentColumn
    if ($width -le 0) {
        $width = ($parts | ForEach-Object { $_.Command.Length } | Measure-Object -Maximum).Maximum
    }

    $formatted = foreach ($part in $parts) {
        $cmd = $part.Command.PadRight($width)
        if ($part.Comment) {
            '{0}  # {1}' -f $cmd, $part.Comment
        }
        else {
            $part.Command
        }
    }
    return @($formatted)
}

function Get-CmdPeekCommandCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [hashtable]$Catalog
    )

    $entry = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    if ($entry -and $entry.PSObject.Properties['category'] -and $entry.category) {
        return [string]$entry.category
    }
    return 'other'
}

function Get-CmdPeekRelatedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [hashtable]$Catalog,
        [string[]]$InstalledCommand
    )

    $entry = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    if (-not $entry -or -not $entry.PSObject.Properties['related'] -or -not $entry.related) {
        return @()
    }

    $fakeHistory = @(
        foreach ($name in @($InstalledCommand)) {
            if ($name) { [pscustomobject]@{ Command = [string]$name } }
        }
    )
    $installedSet = Get-CmdPeekInstalledNameSet -History $fakeHistory -Catalog $Catalog
    $related = @(
        $entry.related | ForEach-Object { [string]$_ } | Where-Object {
            $_ -and -not (Test-CmdPeekNameCovered -Name $_ -InstalledSet $installedSet -Catalog $Catalog)
        }
    )
    return $related
}

function Get-CmdPeekBuiltinHelpExample {
    [CmdletBinding()]
    param(
        [string]$Command
    )

    try {
        $cmd = Get-Command $Command -ErrorAction Stop
        if ($cmd.CommandType -eq 'Cmdlet' -or $cmd.CommandType -eq 'Function') {
            $help = Get-Help $Command -ErrorAction SilentlyContinue
            if ($help -and $help.PSObject.Properties['Synopsis'] -and $help.Synopsis) {
                $synopsis = ([string]$help.Synopsis).Trim()
                if ($synopsis) {
                    return ('{0}  # {1}' -f $Command, ($synopsis -split "`n")[0].Trim())
                }
            }
        }
    }
    catch {
        return $null
    }

    return $null
}

function Add-CmdPeekCatalogMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [string]$DataDirectory,
        [scriptblock]$HelpRunner,
        [switch]$SkipHelpProbe
    )

    $installed = @($History | Where-Object { $_ } | ForEach-Object { $_.Command })
    foreach ($row in @($History)) {
        if (-not $row) { continue }
        $category = Get-CmdPeekCommandCategory -Command $row.Command -Catalog $Catalog
        $usages = @()
        try {
            $usages = @(Get-CmdPeekUsageExample -Command $row.Command -Catalog $Catalog -Count 5 -DataDirectory $DataDirectory -HelpRunner $HelpRunner -SkipHelpProbe:$SkipHelpProbe)
        }
        catch {
            $usages = @()
        }
        $related = @(Get-CmdPeekRelatedCommand -Command $row.Command -Catalog $Catalog -InstalledCommand $installed)
        $row | Add-Member -NotePropertyName Category -NotePropertyValue $category -Force
        $row | Add-Member -NotePropertyName Usages -NotePropertyValue $usages -Force
        $row | Add-Member -NotePropertyName Related -NotePropertyValue $related -Force
        $row
    }
}

function Add-CmdPeekUsageProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [string]$DataDirectory,
        [scriptblock]$HelpRunner
    )

    foreach ($row in @($History)) {
        if (-not $row) { continue }
        $alreadyProbed = $row.PSObject.Properties['HelpProbed'] -and $row.HelpProbed
        $hasUsages = $row.PSObject.Properties['Usages'] -and @($row.Usages).Count -gt 0
        if ($alreadyProbed -or $hasUsages) {
            $row
            continue
        }
        try {
            $usages = @(Get-CmdPeekUsageExample -Command $row.Command -Catalog $Catalog -Count 5 -DataDirectory $DataDirectory -HelpRunner $HelpRunner)
        }
        catch {
            $usages = @()
        }
        $row | Add-Member -NotePropertyName Usages -NotePropertyValue $usages -Force
        $row | Add-Member -NotePropertyName HelpProbed -NotePropertyValue $true -Force
        $row
    }
}
