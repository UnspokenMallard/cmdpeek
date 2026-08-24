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

    return [pscustomobject]@{
        SchemaVersion             = 1
        Favorites                 = @()
        PreferredPackageManager   = $null
        TelemetryEnabled          = $false
        CacheTtlHours             = 24
        LastScan                  = $null
        Commands                  = @()
        ExampleUsageCounts        = [pscustomobject]@{}
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
    if ($raw.PSObject.Properties['PreferredPackageManager']) {
        $state.PreferredPackageManager = $raw.PreferredPackageManager
    }
    if ($raw.PSObject.Properties['TelemetryEnabled']) {
        $state.TelemetryEnabled = [bool]$raw.TelemetryEnabled
    }
    if ($raw.PSObject.Properties['CacheTtlHours'] -and $raw.CacheTtlHours) {
        $state.CacheTtlHours = [int]$raw.CacheTtlHours
    }
    if ($raw.PSObject.Properties['LastScan']) {
        $state.LastScan = $raw.LastScan
    }
    if ($raw.PSObject.Properties['Commands'] -and $raw.Commands) {
        $state.Commands = @($raw.Commands)
    }
    if ($raw.PSObject.Properties['ExampleUsageCounts'] -and $raw.ExampleUsageCounts) {
        $state.ExampleUsageCounts = $raw.ExampleUsageCounts
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
