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
        [ValidateSet('chocolatey', 'scoop', 'winget', 'pipx', 'npm', 'cargo', 'brew')]
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

    $imported = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    Save-CmdPeekState -State $imported -DataDirectory $DataDirectory
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
# END cmdpeek hint
'@

    $parent = Split-Path -Parent $ProfilePath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $existing = ''
    if (Test-Path -LiteralPath $ProfilePath) {
        $existing = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8
        if ($existing -and $existing.Contains($marker) -and $existing.Contains('function pipx')) {
            return
        }
        if ($existing -and $existing.Contains($marker) -and -not $existing.Contains('function pipx')) {
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

function Get-CmdPeekInventoryCache {
    [CmdletBinding()]
    param(
        [string]$DataDirectory,
        [int]$MaxAgeSeconds = 120
    )

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

