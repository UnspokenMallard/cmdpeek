#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CmdPeekLocalAppData {
    [CmdletBinding()]
    param()

    if ($env:LOCALAPPDATA) { return [string]$env:LOCALAPPDATA }
    if ($env:XDG_DATA_HOME) { return [string]$env:XDG_DATA_HOME }
    if ($HOME) { return (Join-Path $HOME '.local/share') }
    return [System.IO.Path]::GetTempPath()
}

function Get-CmdPeekDataDirectory {
    [CmdletBinding()]
    param(
        [string]$DataDirectory
    )

    if ($DataDirectory) { return $DataDirectory }
    return (Join-Path (Get-CmdPeekLocalAppData) 'cmdpeek')
}

function Get-CmdPeekStatePath {
    [CmdletBinding()]
    param(
        [string]$DataDirectory
    )

    return (Join-Path (Get-CmdPeekDataDirectory -DataDirectory $DataDirectory) 'state.json')
}

function Get-CmdPeekDefaultState {
    [CmdletBinding()]
    param()

    # Schema v1 fields actually used. TelemetryEnabled and ExampleUsageCounts were
    # stored in earlier drafts and are ignored on load (not written back).
    return [pscustomobject]@{
        SchemaVersion             = 1
        Favorites                 = @()
        Hidden                    = @()
        PreferredPackageManager   = $null
        CacheTtlHours             = 24
        InventoryCacheSeconds     = 120
        LastScan                  = $null
        LastPeekAt                = $null
        LastMcpAt                 = $null
        Commands                  = @()
    }
}

function Get-CmdPeekState {
    [CmdletBinding()]
    param(
        [string]$DataDirectory
    )

    $path = Get-CmdPeekStatePath -DataDirectory $DataDirectory
    if (-not (Test-Path -LiteralPath $path)) {
        return (Get-CmdPeekDefaultState)
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return (Get-CmdPeekDefaultState)
    }

    $state = Get-CmdPeekDefaultState
    if ($raw.PSObject.Properties['Favorites'] -and $raw.Favorites) {
        $state.Favorites = @($raw.Favorites | ForEach-Object { [string]$_ })
    }
    if ($raw.PSObject.Properties['Hidden'] -and $raw.Hidden) {
        $state.Hidden = @($raw.Hidden | ForEach-Object { [string]$_ })
    }
    if ($raw.PSObject.Properties['PreferredPackageManager']) {
        $state.PreferredPackageManager = $raw.PreferredPackageManager
    }
    if ($raw.PSObject.Properties['CacheTtlHours'] -and $raw.CacheTtlHours) {
        $state.CacheTtlHours = [int]$raw.CacheTtlHours
    }
    if ($raw.PSObject.Properties['InventoryCacheSeconds'] -and $null -ne $raw.InventoryCacheSeconds) {
        $state.InventoryCacheSeconds = [int]$raw.InventoryCacheSeconds
    }
    if ($raw.PSObject.Properties['LastScan']) {
        $state.LastScan = $raw.LastScan
        if ($state.LastScan -is [datetime]) {
            $state.LastScan = $state.LastScan.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        }
    }
    if ($raw.PSObject.Properties['LastPeekAt']) {
        $state.LastPeekAt = $raw.LastPeekAt
        if ($state.LastPeekAt -is [datetime]) {
            $state.LastPeekAt = $state.LastPeekAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        }
    }
    if ($raw.PSObject.Properties['LastMcpAt']) {
        $state.LastMcpAt = $raw.LastMcpAt
        if ($state.LastMcpAt -is [datetime]) {
            $state.LastMcpAt = $state.LastMcpAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        }
    }
    if ($raw.PSObject.Properties['Commands'] -and $raw.Commands) {
        $state.Commands = @($raw.Commands)
    }
    if ($raw.PSObject.Properties['SchemaVersion'] -and $raw.SchemaVersion) {
        $state.SchemaVersion = [int]$raw.SchemaVersion
    }

    return $state
}

function Save-CmdPeekState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,
        [string]$DataDirectory
    )

    $dir = Get-CmdPeekDataDirectory -DataDirectory $DataDirectory
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $path = Get-CmdPeekStatePath -DataDirectory $DataDirectory
    $json = $State | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function Set-CmdPeekFavorite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(Mandatory)]
        [bool]$Favorite
    )

    $current = @($State.Favorites | Where-Object { $_ })
    $needle = $Command.ToLowerInvariant()
    if ($Favorite) {
        if (-not ($current | Where-Object { $_.ToLowerInvariant() -eq $needle })) {
            $current += $Command
        }
    }
    else {
        $current = @($current | Where-Object { $_.ToLowerInvariant() -ne $needle })
    }

    $State.Favorites = @($current)
    return $State
}

function Set-CmdPeekHidden {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(Mandatory)]
        [bool]$Hidden
    )

    $current = @($State.Hidden | Where-Object { $_ })
    $needle = $Command.ToLowerInvariant()
    if ($Hidden) {
        if (-not ($current | Where-Object { $_.ToLowerInvariant() -eq $needle })) {
            $current += $Command
        }
    }
    else {
        $current = @($current | Where-Object { $_.ToLowerInvariant() -ne $needle })
    }

    $State.Hidden = @($current)
    return $State
}

function Set-CmdPeekPreferredPackageManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,
        [Parameter(Mandatory)]
        [ValidateSet('chocolatey', 'scoop', 'winget', 'pipx', 'npm', 'cargo', 'brew', 'apt', 'pacman')]
        [string]$PackageManager
    )

    $State.PreferredPackageManager = $PackageManager
    return $State
}

function Export-CmdPeekState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$DataDirectory
    )

    $state = Get-CmdPeekState -DataDirectory $DataDirectory
    $json = $state | ConvertTo-Json -Depth 8
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function ConvertTo-CmdPeekState {
    [CmdletBinding()]
    param($Raw)

    # Anything that reaches state.json has to survive Get-CmdPeekState under
    # StrictMode, so coerce an arbitrary document onto the known schema instead of
    # writing it through untouched.
    $state = Get-CmdPeekDefaultState
    if (-not $Raw) { return $state }

    $version = 1
    if ($Raw.PSObject.Properties['SchemaVersion'] -and $Raw.SchemaVersion) {
        $version = [int]$Raw.SchemaVersion
    }
    if ($version -gt $state.SchemaVersion) {
        throw "State file uses schema version $version but this cmdpeek understands $($state.SchemaVersion). Upgrade cmdpeek or export a fresh state."
    }

    if ($Raw.PSObject.Properties['Favorites'] -and $Raw.Favorites) {
        $state.Favorites = @($Raw.Favorites | Where-Object { $_ } | ForEach-Object { [string]$_ })
    }
    if ($Raw.PSObject.Properties['Hidden'] -and $Raw.Hidden) {
        $state.Hidden = @($Raw.Hidden | Where-Object { $_ } | ForEach-Object { [string]$_ })
    }
    if ($Raw.PSObject.Properties['PreferredPackageManager'] -and $Raw.PreferredPackageManager) {
        $pm = ([string]$Raw.PreferredPackageManager).ToLowerInvariant()
        $known = @('chocolatey', 'scoop', 'winget', 'pipx', 'npm', 'cargo', 'brew', 'apt', 'pacman')
        if ($known -contains $pm) { $state.PreferredPackageManager = $pm }
    }
    foreach ($name in @('CacheTtlHours', 'InventoryCacheSeconds')) {
        if ($Raw.PSObject.Properties[$name] -and $null -ne $Raw.$name) {
            $parsed = 0
            if ([int]::TryParse([string]$Raw.$name, [ref]$parsed) -and $parsed -ge 0) {
                $state.$name = $parsed
            }
        }
    }
    foreach ($name in @('LastScan', 'LastPeekAt', 'LastMcpAt')) {
        if (-not ($Raw.PSObject.Properties[$name]) -or -not $Raw.$name) { continue }
        $value = $Raw.$name
        if ($value -is [datetime]) {
            $state.$name = ([datetime]$value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
            continue
        }
        $when = [datetime]::MinValue
        if ([datetime]::TryParse([string]$value, [ref]$when)) {
            $state.$name = $when.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        }
    }
    if ($Raw.PSObject.Properties['Commands'] -and $Raw.Commands) {
        $state.Commands = @(
            foreach ($row in @($Raw.Commands)) {
                if (-not $row -or -not $row.PSObject.Properties['Command'] -or -not $row.Command) { continue }
                [pscustomobject]@{
                    Command        = [string]$row.Command
                    PackageName    = $(if ($row.PSObject.Properties['PackageName']) { [string]$row.PackageName } else { [string]$row.Command })
                    PackageManager = $(if ($row.PSObject.Properties['PackageManager']) { [string]$row.PackageManager } else { '' })
                    InstallDate    = $(if ($row.PSObject.Properties['InstallDate']) { $row.InstallDate } else { $null })
                    Version        = $(if ($row.PSObject.Properties['Version']) { $row.Version } else { $null })
                }
            }
        )
    }
    return $state
}

function Import-CmdPeekState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$DataDirectory
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Backup file not found: $Path"
    }

    try {
        $imported = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Backup file is not valid JSON: $Path"
    }
    Save-CmdPeekState -State (ConvertTo-CmdPeekState -Raw $imported) -DataDirectory $DataDirectory
}

function Add-CmdPeekProfileHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath
    )

    $marker = 'BEGIN cmdpeek hint'
    $snippet = @'
# BEGIN cmdpeek hint
function Invoke-CmdPeekHint {
    if (Get-Command cmdpeek -ErrorAction SilentlyContinue) {
        cmdpeek -NonInteractive -n 1
    }
}
function scoop {
    $app = Get-Command scoop -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { throw 'scoop not found on PATH' }
    & $app.Source @args
    if ($args.Count -ge 1 -and $args[0] -eq 'install') { Invoke-CmdPeekHint }
}
function choco {
    $app = Get-Command choco -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { throw 'choco not found on PATH' }
    & $app.Source @args
    if ($args.Count -ge 1 -and $args[0] -eq 'install') { Invoke-CmdPeekHint }
}
function winget {
    $app = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { throw 'winget not found on PATH' }
    & $app.Source @args
    if ($args.Count -ge 1 -and $args[0] -eq 'install') { Invoke-CmdPeekHint }
}
function pipx {
    $app = Get-Command pipx -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { throw 'pipx not found on PATH' }
    & $app.Source @args
    if ($args.Count -ge 1 -and $args[0] -eq 'install') { Invoke-CmdPeekHint }
}
function npm {
    $app = Get-Command npm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { throw 'npm not found on PATH' }
    & $app.Source @args
    $isGlobal = $false
    foreach ($a in @($args)) {
        if ($a -eq '-g' -or $a -eq '--global') { $isGlobal = $true }
    }
    if ($args.Count -ge 2 -and $args[0] -eq 'install' -and $isGlobal) { Invoke-CmdPeekHint }
}
function cargo {
    $app = Get-Command cargo -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { throw 'cargo not found on PATH' }
    & $app.Source @args
    if ($args.Count -ge 1 -and $args[0] -eq 'install') { Invoke-CmdPeekHint }
}
function brew {
    $app = Get-Command brew -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { throw 'brew not found on PATH' }
    & $app.Source @args
    if ($args.Count -ge 1 -and $args[0] -eq 'install') { Invoke-CmdPeekHint }
}
function Register-CmdPeekHistoryTimestamp {
    if (-not (Get-Command Add-CmdPeekHistoryTimestamp -ErrorAction SilentlyContinue)) {
        $localApp = $env:LOCALAPPDATA
        if (-not $localApp) {
            if ($env:XDG_DATA_HOME) { $localApp = $env:XDG_DATA_HOME }
            elseif ($HOME) { $localApp = Join-Path $HOME '.local/share' }
        }
        if ($localApp) {
            $modDir = Join-Path $localApp 'cmdpeek'
            $psd1 = Join-Path (Join-Path $modDir 'module') 'cmdpeek.psd1'
            if (Test-Path -LiteralPath $psd1) {
                Import-Module $psd1 -ErrorAction SilentlyContinue
            }
        }
        if (-not (Get-Command Add-CmdPeekHistoryTimestamp -ErrorAction SilentlyContinue)) {
            Import-Module cmdpeek -ErrorAction SilentlyContinue
        }
    }
    if (Get-Command Add-CmdPeekHistoryTimestamp -ErrorAction SilentlyContinue) {
        Add-CmdPeekHistoryTimestamp
    }
}
Register-CmdPeekHistoryTimestamp
# END cmdpeek hint
'@

    $parent = Split-Path -Parent $ProfilePath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $existing = ''
    if (Test-Path -LiteralPath $ProfilePath) {
        $existing = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8
        if ($existing -and $existing.Contains($marker) -and $existing.Contains('Register-CmdPeekHistoryTimestamp')) {
            return
        }
        if ($existing -and $existing.Contains($marker) -and -not $existing.Contains('Register-CmdPeekHistoryTimestamp')) {
            $start = $existing.IndexOf('# BEGIN cmdpeek hint')
            $endMarker = '# END cmdpeek hint'
            $end = $existing.IndexOf($endMarker)
            if ($start -ge 0 -and $end -gt $start) {
                $end = $end + $endMarker.Length
                while ($end -lt $existing.Length -and ($existing[$end] -eq "`r" -or $existing[$end] -eq "`n")) {
                    $end++
                }
                $existing = $existing.Remove($start, $end - $start)
            }
        }
    }

    $block = $snippet.TrimEnd() + [Environment]::NewLine
    if ($existing -and -not $existing.EndsWith("`n")) {
        $existing = $existing + [Environment]::NewLine
    }
    $combined = $existing + $block
    $dirForFile = Split-Path -Parent $ProfilePath
    if ($dirForFile -and -not (Test-Path -LiteralPath $dirForFile)) {
        New-Item -ItemType Directory -Path $dirForFile -Force | Out-Null
    }
    Set-Content -LiteralPath $ProfilePath -Value $combined -Encoding UTF8
}

function Get-CmdPeekLastInstallPath {
    [CmdletBinding()]
    param([string]$DataDirectory)
    return (Join-Path (Get-CmdPeekDataDirectory -DataDirectory $DataDirectory) 'last-install.json')
}

function Save-CmdPeekLastInstall {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Command,
        [string]$DataDirectory
    )

    $rows = @(
        foreach ($row in @($Command)) {
            if (-not $row) { continue }
            [pscustomobject]@{
                command        = [string]$row.Command
                packageName    = $(if ($row.PSObject.Properties['PackageName']) { [string]$row.PackageName } else { [string]$row.Command })
                packageManager = [string]$row.PackageManager
                installDate    = $(if ($row.PSObject.Properties['InstallDate'] -and $row.InstallDate) { ([datetime]$row.InstallDate).ToString('o') } else { $null })
                usages         = $(if ($row.PSObject.Properties['Usages'] -and $row.Usages) { @($row.Usages | Select-Object -First 3) } else { @() })
            }
        }
    )
    $payload = [pscustomobject]@{
        generatedAt = (Get-Date).ToString('o')
        commands    = @($rows)
    }
    $dir = Get-CmdPeekDataDirectory -DataDirectory $DataDirectory
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $path = Get-CmdPeekLastInstallPath -DataDirectory $DataDirectory
    ($payload | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Get-CmdPeekLastInstall {
    [CmdletBinding()]
    param([string]$DataDirectory)

    $path = Get-CmdPeekLastInstallPath -DataDirectory $DataDirectory
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-CmdPeekInventoryCachePath {
    [CmdletBinding()]
    param([string]$DataDirectory)
    return (Join-Path (Get-CmdPeekDataDirectory -DataDirectory $DataDirectory) 'inventory-cache.json')
}

function Save-CmdPeekInventoryCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Snapshot,
        [string]$DataDirectory
    )

    $dir = Get-CmdPeekDataDirectory -DataDirectory $DataDirectory
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $path = Get-CmdPeekInventoryCachePath -DataDirectory $DataDirectory
    ($Snapshot | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-CmdPeekInventoryCacheSeconds {
    [CmdletBinding()]
    param(
        [string]$DataDirectory,
        $State
    )

    if ($env:CMDPEEK_INVENTORY_CACHE_SECONDS) {
        $parsed = 0
        if ([int]::TryParse($env:CMDPEEK_INVENTORY_CACHE_SECONDS, [ref]$parsed) -and $parsed -ge 0) {
            return $parsed
        }
    }
    if (-not $State) {
        try { $State = Get-CmdPeekState -DataDirectory $DataDirectory } catch { $State = $null }
    }
    if ($State -and $State.PSObject.Properties['InventoryCacheSeconds'] -and $null -ne $State.InventoryCacheSeconds) {
        return [int]$State.InventoryCacheSeconds
    }
    return 120
}

function Get-CmdPeekInventoryCache {
    [CmdletBinding()]
    param(
        [string]$DataDirectory,
        [int]$MaxAgeSeconds = -1,
        $State
    )

    if ($MaxAgeSeconds -lt 0) {
        $MaxAgeSeconds = Get-CmdPeekInventoryCacheSeconds -DataDirectory $DataDirectory -State $State
    }
    if ($MaxAgeSeconds -eq 0) { return $null }

    $path = Get-CmdPeekInventoryCachePath -DataDirectory $DataDirectory
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    if (((Get-Date) - $item.LastWriteTime).TotalSeconds -gt $MaxAgeSeconds) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

