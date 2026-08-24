#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CmdPeekCommandHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Package,
        [int]$Count
    )

    if (-not $Package -or @($Package).Count -eq 0) {
        return @()
    }

    $rows = foreach ($pkg in @($Package)) {
        foreach ($cmd in @($pkg.Commands)) {
            if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
            [pscustomobject]@{
                Command        = [string]$cmd
                PackageName    = [string]$pkg.Name
                PackageManager = [string]$pkg.PackageManager
                InstallDate    = [datetime]$pkg.InstallDate
                Version        = $(if ($pkg.PSObject.Properties['Version']) { $pkg.Version } else { $null })
                Favorite       = $false
                Category       = $null
            }
        }
    }

    $deduped = @(
        $rows |
            Group-Object { $_.Command.ToLowerInvariant() } |
            ForEach-Object { $_.Group | Sort-Object InstallDate -Descending | Select-Object -First 1 }
    )

    $sorted = @($deduped | Sort-Object InstallDate -Descending)

    if ($PSBoundParameters.ContainsKey('Count') -and $Count -gt 0) {
        return @($sorted | Select-Object -First $Count)
    }

    return $sorted
}

function Find-CmdPeekMissingCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Previous,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Current
    )

    $currentNames = @(
        @($Current) |
            Where-Object { $_ -and $_.Command } |
            ForEach-Object { $_.Command.ToLowerInvariant() }
    )

    $missing = @(
        @($Previous) |
            Where-Object {
                $_ -and $_.Command -and
                $currentNames -notcontains $_.Command.ToLowerInvariant()
            }
    )

    return $missing
}

function Search-CmdPeekCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [string]$Query,
        [string]$Category,
        [switch]$Favorite
    )

    $rows = @($History)
    if ($Query) {
        $needle = $Query.ToLowerInvariant()
        $rows = @(
            $rows | Where-Object {
                if (-not $_) { return $false }
                $name = ([string]$_.Command).ToLowerInvariant()
                $pm = ([string]$_.PackageManager).ToLowerInvariant()
                $pkg = $(if ($_.PSObject.Properties['PackageName']) { ([string]$_.PackageName).ToLowerInvariant() } else { '' })
                return $name.Contains($needle) -or $pm.Contains($needle) -or $pkg.Contains($needle)
            }
        )
    }

    if ($Category) {
        $cat = $Category.ToLowerInvariant()
        $rows = @(
            $rows | Where-Object {
                $_ -and $_.PSObject.Properties['Category'] -and
                ([string]$_.Category).ToLowerInvariant() -eq $cat
            }
        )
    }

    if ($Favorite) {
        $rows = @($rows | Where-Object { $_ -and $_.Favorite })
    }

    return $rows
}

function Merge-CmdPeekFavorite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [string[]]$Favorite
    )

    $fav = @($Favorite | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    foreach ($row in @($History)) {
        if (-not $row) { continue }
        $isFav = $fav -contains ([string]$row.Command).ToLowerInvariant()
        $row | Add-Member -NotePropertyName Favorite -NotePropertyValue $isFav -Force
        $row
    }
}
