#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CmdPeekDataDirectory {
    [CmdletBinding()]
    param(
        [string]$DataDirectory
    )

    if ($DataDirectory) { return $DataDirectory }
    return (Join-Path $env:LOCALAPPDATA 'cmdpeek')
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
        [ValidateSet('chocolatey', 'scoop', 'winget')]
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
# END cmdpeek hint
'@

    $parent = Split-Path -Parent $ProfilePath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $existing = ''
    if (Test-Path -LiteralPath $ProfilePath) {
        $existing = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8
        if ($existing -and $existing.Contains($marker)) {
            return
        }
    }

    $block = $snippet.TrimEnd() + [Environment]::NewLine
    if ($existing -and -not $existing.EndsWith("`n")) {
        $block = [Environment]::NewLine + $block
    }
    Add-Content -LiteralPath $ProfilePath -Value $block -Encoding UTF8
}
