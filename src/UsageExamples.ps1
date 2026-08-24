#Requires -Version 5.1
Set-StrictMode -Version Latest

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
        [string]$Path
    )

    $resolved = Get-CmdPeekExampleCatalogPath -Path $Path
    $map = @{}
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved)) {
        return $map
    }

    try {
        $json = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $map
    }

    if (-not $json -or -not $json.PSObject.Properties['commands']) {
        return $map
    }

    foreach ($prop in $json.commands.PSObject.Properties) {
        $map[$prop.Name] = $prop.Value
    }

    return $map
}

function Get-CmdPeekCatalogEntry {
    param(
        [string]$Command,
        [hashtable]$Catalog
    )

    if (-not $Catalog -or -not $Command) { return $null }
    foreach ($key in $Catalog.Keys) {
        if ($key.ToLowerInvariant() -eq $Command.ToLowerInvariant()) {
            return $Catalog[$key]
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
        [int]$Count = 3
    )

    if ($Count -lt 1) { $Count = 1 }
    $entry = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    $usages = @()
    if ($entry -and $entry.PSObject.Properties['usages'] -and $entry.usages) {
        $usages = @($entry.usages | ForEach-Object { [string]$_ })
    }

    if ($usages.Count -eq 0) {
        $usages = @(
            ('{0} --help                       # Show command help' -f $Command)
        )
        $help = Get-CmdPeekBuiltinHelpExample -Command $Command
        if ($help) { $usages = @($help) + $usages }
    }

    return @($usages | Select-Object -First $Count)
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

    $installed = @($InstalledCommand | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $related = @(
        $entry.related | ForEach-Object { [string]$_ } | Where-Object {
            $_ -and $installed -notcontains $_.ToLowerInvariant()
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
        [hashtable]$Catalog
    )

    $installed = @($History | Where-Object { $_ } | ForEach-Object { $_.Command })
    foreach ($row in @($History)) {
        if (-not $row) { continue }
        $category = Get-CmdPeekCommandCategory -Command $row.Command -Catalog $Catalog
        $usages = @(Get-CmdPeekUsageExample -Command $row.Command -Catalog $Catalog -Count 5)
        $related = @(Get-CmdPeekRelatedCommand -Command $row.Command -Catalog $Catalog -InstalledCommand $installed)
        $row | Add-Member -NotePropertyName Category -NotePropertyValue $category -Force
        $row | Add-Member -NotePropertyName Usages -NotePropertyValue $usages -Force
        $row | Add-Member -NotePropertyName Related -NotePropertyValue $related -Force
        $row
    }
}
