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
                Hidden         = $false
                Category       = $null
            }
        }
    }

    $deduped = @(
        $rows |
            Group-Object { '{0}|{1}' -f $_.Command.ToLowerInvariant(), $_.PackageManager.ToLowerInvariant() } |
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
        [switch]$Favorite,
        [switch]$HiddenOnly
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
                $usageText = ''
                if ($_.PSObject.Properties['Usages'] -and $_.Usages) {
                    $usageText = (@($_.Usages) -join "`n").ToLowerInvariant()
                }
                return $name.Contains($needle) -or $pm.Contains($needle) -or $pkg.Contains($needle) -or $usageText.Contains($needle)
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

    if ($HiddenOnly) {
        $rows = @(
            $rows | Where-Object {
                $_ -and $_.PSObject.Properties['Hidden'] -and $_.Hidden
            }
        )
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

function Merge-CmdPeekHidden {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [string[]]$Hidden
    )

    $hide = @($Hidden | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    foreach ($row in @($History)) {
        if (-not $row) { continue }
        $isHidden = $hide -contains ([string]$row.Command).ToLowerInvariant()
        $row | Add-Member -NotePropertyName Hidden -NotePropertyValue $isHidden -Force
        $row
    }
}

function Select-CmdPeekQuickHistory {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$History,
        [int]$Count
    )

    $visible = @(
        @($History) | Where-Object {
            if (-not $_) { return $false }
            if ($_.PSObject.Properties['Hidden'] -and $_.Hidden) { return $false }
            return $true
        }
    )

    if ($Count -gt 0) {
        return @($visible | Select-Object -First $Count)
    }
    return $visible
}

function Convert-CmdPeekSince {
    [CmdletBinding()]
    param(
        [string]$Since,
        $Cursor,
        [datetime]$Now = (Get-Date)
    )

    $raw = ''
    if ($null -ne $Since) { $raw = [string]$Since }
    $raw = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw -eq 'last') {
        if ($null -eq $Cursor -or [string]::IsNullOrWhiteSpace([string]$Cursor)) {
            return [pscustomobject]@{ Kind = 'empty'; Instant = $null }
        }
        try {
            $instant = [datetime]$Cursor
        }
        catch {
            return [pscustomobject]@{ Kind = 'empty'; Instant = $null }
        }
        return [pscustomobject]@{ Kind = 'instant'; Instant = $instant }
    }
    if ($raw -eq 'all') {
        return [pscustomobject]@{ Kind = 'all'; Instant = $null }
    }

    $m = [regex]::Match($raw, '^(\d+)([hHdD])$')
    if ($m.Success) {
        $n = [int]$m.Groups[1].Value
        $unit = $m.Groups[2].Value.ToLowerInvariant()
        $instant = $(if ($unit -eq 'h') { $Now.AddHours(-1 * $n) } else { $Now.AddDays(-1 * $n) })
        return [pscustomobject]@{ Kind = 'instant'; Instant = $instant }
    }

    try {
        $instant = [datetime]$raw
        return [pscustomobject]@{ Kind = 'instant'; Instant = $instant }
    }
    catch {
        throw "Invalid -Since value '$Since'. Use last, all, an ISO datetime, 24h, or 7d."
    }
}

function Get-CmdPeekPackageStem {
    param([string]$PackageName)
    if ([string]::IsNullOrWhiteSpace($PackageName)) { return '' }
    $i = $PackageName.LastIndexOf('-')
    if ($i -le 0) { return $PackageName }
    return $PackageName.Substring(0, $i)
}

function Select-CmdPeekPackageRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History
    )

    $rows = @($History | Where-Object { $_ })
    if ($rows.Count -eq 0) { return @() }

    $groups = $rows | Group-Object {
        '{0}|{1}' -f ([string]$_.PackageName).ToLowerInvariant(), ([string]$_.PackageManager).ToLowerInvariant()
    }

    foreach ($g in $groups) {
        $bins = @($g.Group)
        $pkgName = [string]$bins[0].PackageName
        $primary = $null
        $pkgLower = $pkgName.ToLowerInvariant()
        foreach ($b in $bins) {
            if (([string]$b.Command).ToLowerInvariant() -eq $pkgLower) { $primary = $b; break }
        }
        if (-not $primary) {
            $stem = Get-CmdPeekPackageStem -PackageName $pkgName
            $stemLower = $stem.ToLowerInvariant()
            foreach ($b in $bins) {
                if (([string]$b.Command).ToLowerInvariant() -eq $stemLower) { $primary = $b; break }
            }
        }
        if (-not $primary) {
            $primary = @($bins | Sort-Object @{Expression='InstallDate';Descending=$true}, @{Expression='Command'})[0]
        }
        $primaryHidden = [bool]($primary.PSObject.Properties['Hidden'] -and $primary.Hidden)
        if ($primaryHidden) { continue }

        $shims = @(
            $bins |
                Where-Object {
                    ([string]$_.Command).ToLowerInvariant() -ne ([string]$primary.Command).ToLowerInvariant() -and
                    -not ($_.PSObject.Properties['Hidden'] -and $_.Hidden)
                } |
                ForEach-Object { [string]$_.Command }
        )

        $primary | Add-Member -NotePropertyName Shims -NotePropertyValue $shims -Force
        $primary
    }
}

function Test-CmdPeekOnPath {
    param(
        [string]$Command,
        [scriptblock]$CommandTester
    )

    if (-not $Command) { return $false }

    if (-not $CommandTester) {
        $CommandTester = {
            param($Name)
            [bool](Get-Command $Name -ErrorAction SilentlyContinue)
        }
    }

    try {
        return [bool](& $CommandTester $Command)
    }
    catch {
        return $false
    }
}

function Select-CmdPeekJustInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [string]$Since = 'last',
        $Cursor,
        [datetime]$Now = (Get-Date),
        [int]$Count,
        [scriptblock]$CommandTester
    )

    $grouped = @(Select-CmdPeekPackageRow -History $History)
    $marked = foreach ($row in $grouped) {
        $onPath = Test-CmdPeekOnPath -Command ([string]$row.Command) -CommandTester $CommandTester
        $row | Add-Member -NotePropertyName OnPath -NotePropertyValue $onPath -Force
        $row
    }

    $sinceInfo = Convert-CmdPeekSince -Since $Since -Cursor $Cursor -Now $Now
    if ($sinceInfo.Kind -eq 'empty') {
        return @()
    }

    $filtered = @($marked)
    if ($sinceInfo.Kind -eq 'instant') {
        $instant = $sinceInfo.Instant
        $filtered = @(
            $marked | Where-Object { $_.InstallDate -gt $instant }
        )
    }

    $sorted = @($filtered | Sort-Object InstallDate -Descending)

    if ($PSBoundParameters.ContainsKey('Count') -and $Count -gt 0) {
        return @($sorted | Select-Object -First $Count)
    }

    return $sorted
}
