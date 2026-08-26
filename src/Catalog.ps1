#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CmdPeekOverlayCatalogPath {
    [CmdletBinding()]
    param(
        [string]$DataDirectory
    )

    if (-not $DataDirectory) {
        if (Get-Command Get-CmdPeekDataDirectory -ErrorAction SilentlyContinue) {
            $DataDirectory = Get-CmdPeekDataDirectory
        }
        else {
            return $null
        }
    }
    return (Join-Path $DataDirectory 'catalog.overlay.json')
}

function ConvertTo-CmdPeekStringList {
    param($Value)
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        if ($item -is [string] -and $item) {
            $list.Add($item)
        }
    }
    return @($list)
}

function ConvertTo-CmdPeekUsageString {
    [CmdletBinding()]
    param(
        $Usage
    )

    if ($null -eq $Usage) { return $null }
    if ($Usage -is [string]) { return [string]$Usage }

    $argv = ''
    if ($Usage.PSObject.Properties['argv'] -and $Usage.argv) {
        if ($Usage.argv -is [string]) {
            $argv = [string]$Usage.argv
        }
        else {
            $argv = (@($Usage.argv | ForEach-Object { [string]$_ }) -join ' ')
        }
    }
    elseif ($Usage.PSObject.Properties['command'] -and $Usage.command) {
        $argv = [string]$Usage.command
    }
    if ([string]::IsNullOrWhiteSpace($argv)) { return $null }

    $comment = ''
    if ($Usage.PSObject.Properties['comment'] -and $Usage.comment) {
        $comment = [string]$Usage.comment
    }
    if ($comment) {
        return ('{0}  # {1}' -f $argv, $comment)
    }
    return $argv
}

function Get-CmdPeekCatalogUsageList {
    [CmdletBinding()]
    param(
        $Entry
    )

    if (-not $Entry -or -not $Entry.PSObject.Properties['usages'] -or -not $Entry.usages) {
        return @()
    }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Entry.usages)) {
        $line = ConvertTo-CmdPeekUsageString -Usage $item
        if ($line) { $out.Add($line) }
    }
    return @($out)
}

function ConvertTo-CmdPeekStructuredUsage {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Usage
    )

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Usage)) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        $parts = Split-CmdPeekUsage -Usage $item
        $unsafe = [bool]($parts.Command -match '<[^>]+>')
        $rows.Add([pscustomobject]@{
            argv    = [string]$parts.Command
            comment = [string]$parts.Comment
            unsafe  = $unsafe
        })
    }
    return @($rows.ToArray())
}

function Merge-CmdPeekCatalogHashtable {
    [CmdletBinding()]
    param(
        [hashtable]$Base,
        [hashtable]$Overlay
    )

    if (-not $Base) { $Base = @{} }
    if (-not $Overlay) { return $Base }
    foreach ($key in @($Overlay.Keys)) {
        $Base[$key] = $Overlay[$key]
    }
    return $Base
}

function Read-CmdPeekCatalogFile {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    $commands = @{}
    $kits = @{}
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Commands = $commands; Kits = $kits }
    }
    try {
        $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{ Commands = $commands; Kits = $kits }
    }
    if ($json -and $json.PSObject.Properties['commands'] -and $json.commands) {
        foreach ($prop in $json.commands.PSObject.Properties) {
            $commands[$prop.Name] = $prop.Value
        }
    }
    if ($json -and $json.PSObject.Properties['kits'] -and $json.kits) {
        foreach ($prop in $json.kits.PSObject.Properties) {
            $members = New-Object System.Collections.Generic.List[string]
            foreach ($item in @($prop.Value)) {
                if ($item -is [string] -and $item) { $members.Add($item) }
            }
            $kits[$prop.Name] = @($members)
        }
    }
    return [pscustomobject]@{ Commands = $commands; Kits = $kits }
}

function Get-CmdPeekCatalogAliasList {
    [CmdletBinding()]
    param(
        $Entry
    )

    if (-not $Entry) { return @() }
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($propName in @('aliases', 'alias')) {
        if ($Entry.PSObject.Properties[$propName] -and $Entry.$propName) {
            foreach ($item in (ConvertTo-CmdPeekStringList -Value $Entry.$propName)) {
                $names.Add($item)
            }
        }
    }
    return @($names)
}

function Get-CmdPeekCatalogCapabilityList {
    [CmdletBinding()]
    param($Entry)
    if (-not $Entry -or -not $Entry.PSObject.Properties['capabilities']) { return @() }
    return @(ConvertTo-CmdPeekStringList -Value $Entry.capabilities)
}

function Get-CmdPeekCatalogTaskList {
    [CmdletBinding()]
    param($Entry)
    if (-not $Entry) { return @() }
    $tasks = New-Object System.Collections.Generic.List[string]
    foreach ($item in (ConvertTo-CmdPeekStringList -Value $(if ($Entry.PSObject.Properties['tasks']) { $Entry.tasks } else { $null }))) {
        $tasks.Add($item)
    }
    return @($tasks)
}

function Get-CmdPeekCatalogSubstituteList {
    [CmdletBinding()]
    param($Entry)
    if (-not $Entry -or -not $Entry.PSObject.Properties['substitutes']) { return @() }
    return @(ConvertTo-CmdPeekStringList -Value $Entry.substitutes)
}

function Get-CmdPeekCatalogInstallMap {
    [CmdletBinding()]
    param($Entry)
    $map = @{}
    if (-not $Entry -or -not $Entry.PSObject.Properties['install'] -or -not $Entry.install) {
        return $map
    }
    $inst = $Entry.install
    foreach ($prop in $inst.PSObject.Properties) {
        if ($prop.Value -is [string] -and $prop.Value) {
            $map[$prop.Name.ToLowerInvariant()] = [string]$prop.Value
        }
    }
    return $map
}

function Get-CmdPeekCanonicalCommand {
    [CmdletBinding()]
    param(
        [string]$Command,
        [hashtable]$Catalog
    )

    if (-not $Command) { return $Command }
    $entryHit = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    if (-not $entryHit) { return $Command }
    foreach ($key in @($Catalog.Keys)) {
        if ($key.ToLowerInvariant() -eq $Command.ToLowerInvariant()) {
            return [string]$key
        }
    }
    foreach ($key in @($Catalog.Keys)) {
        $entry = $Catalog[$key]
        $aliases = @(Get-CmdPeekCatalogAliasList -Entry $entry)
        foreach ($alias in $aliases) {
            if ($alias.ToLowerInvariant() -eq $Command.ToLowerInvariant()) {
                return [string]$key
            }
        }
    }
    return $Command
}

function Get-CmdPeekCommandNamesFor {
    [CmdletBinding()]
    param(
        [string]$Command,
        [hashtable]$Catalog
    )

    $names = New-Object System.Collections.Generic.List[string]
    if ($Command) { $names.Add($Command) }
    $canonical = Get-CmdPeekCanonicalCommand -Command $Command -Catalog $Catalog
    if ($canonical -and $names -notcontains $canonical) { $names.Add($canonical) }
    $entry = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    foreach ($alias in @(Get-CmdPeekCatalogAliasList -Entry $entry)) {
        if ($alias -and $names -notcontains $alias) { $names.Add($alias) }
    }
    if ($Catalog -and $canonical -and $Catalog.ContainsKey($canonical)) {
        foreach ($alias in @(Get-CmdPeekCatalogAliasList -Entry $Catalog[$canonical])) {
            if ($alias -and $names -notcontains $alias) { $names.Add($alias) }
        }
    }
    return @($names)
}

function Get-CmdPeekInstalledNameSet {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog
    )

    $set = @{}
    foreach ($row in @($History)) {
        if (-not $row -or -not $row.Command) { continue }
        foreach ($name in @(Get-CmdPeekCommandNamesFor -Command $row.Command -Catalog $Catalog)) {
            $set[$name.ToLowerInvariant()] = $true
        }
    }
    return $set
}

function Test-CmdPeekNameCovered {
    [CmdletBinding()]
    param(
        [string]$Name,
        [hashtable]$InstalledSet,
        [hashtable]$Catalog
    )

    if (-not $Name -or -not $InstalledSet) { return $false }
    foreach ($candidate in @(Get-CmdPeekCommandNamesFor -Command $Name -Catalog $Catalog)) {
        if ($InstalledSet.ContainsKey($candidate.ToLowerInvariant())) { return $true }
    }

    $missingEntry = Get-CmdPeekCatalogEntry -Command $Name -Catalog $Catalog
    foreach ($sub in @(Get-CmdPeekCatalogSubstituteList -Entry $missingEntry)) {
        foreach ($candidate in @(Get-CmdPeekCommandNamesFor -Command $sub -Catalog $Catalog)) {
            if ($InstalledSet.ContainsKey($candidate.ToLowerInvariant())) { return $true }
        }
    }

    if ($Catalog) {
        foreach ($key in @($Catalog.Keys)) {
            if (-not $InstalledSet.ContainsKey($key.ToLowerInvariant())) { continue }
            $subs = @(Get-CmdPeekCatalogSubstituteList -Entry $Catalog[$key])
            foreach ($sub in $subs) {
                if ($sub.ToLowerInvariant() -eq $Name.ToLowerInvariant()) { return $true }
                foreach ($alias in @(Get-CmdPeekCommandNamesFor -Command $sub -Catalog $Catalog)) {
                    if ($alias.ToLowerInvariant() -eq $Name.ToLowerInvariant()) { return $true }
                }
            }
        }
    }

    return $false
}

function Get-CmdPeekInstallCommands {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [hashtable]$Catalog,
        [string]$PreferredManager
    )

    $entry = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    $map = Get-CmdPeekCatalogInstallMap -Entry $entry
    $order = @('scoop', 'winget', 'chocolatey', 'brew', 'pipx', 'npm', 'cargo', 'apt')
    if ($PreferredManager) {
        $pref = $PreferredManager.ToLowerInvariant()
        if ($pref -eq 'choco') { $pref = 'chocolatey' }
        $order = @($pref) + @($order | Where-Object { $_ -ne $pref })
    }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($manager in $order) {
        $id = $Command
        if ($map.ContainsKey($manager) -and $map[$manager]) {
            $id = $map[$manager]
        }
        elseif ($map.Count -eq 0) {
            # still emit a reasonable guess for primary Windows managers
        }
        else {
            if (-not $map.ContainsKey($manager)) { continue }
        }
        $line = $null
        switch ($manager) {
            'scoop' { $line = "scoop install $id" }
            'chocolatey' { $line = "choco install $id -y" }
            'winget' { $line = "winget install --id $id -e --accept-package-agreements --accept-source-agreements" }
            'brew' { $line = "brew install $id" }
            'pipx' { $line = "pipx install $id" }
            'npm' { $line = "npm install -g $id" }
            'cargo' { $line = "cargo install $id" }
            'apt' { $line = "sudo apt install $id" }
        }
        if ($line) { $lines.Add($line) }
    }
    if ($lines.Count -eq 0) {
        $lines.Add("scoop install $Command")
        $lines.Add("choco install $Command -y")
        $lines.Add("winget install $Command")
    }
    return @($lines)
}

function Get-CmdPeekCatalogIndex {
    [CmdletBinding()]
    param(
        [hashtable]$Catalog
    )

    if (-not $Catalog) { $Catalog = @{} }
    $rows = New-Object System.Collections.Generic.List[object]
    $keys = [string[]]@($Catalog.Keys)
    if ($keys.Count -gt 1) {
        [Array]::Sort($keys, [StringComparer]::OrdinalIgnoreCase)
    }
    foreach ($key in $keys) {
        $entry = $Catalog[$key]
        $rows.Add([pscustomobject]@{
            command      = [string]$key
            category     = $(if ($entry.PSObject.Properties['category'] -and $entry.category) { [string]$entry.category } else { 'other' })
            capabilities = @(Get-CmdPeekCatalogCapabilityList -Entry $entry)
            aliases      = @(Get-CmdPeekCatalogAliasList -Entry $entry)
            related      = @(ConvertTo-CmdPeekStringList -Value $(if ($entry.PSObject.Properties['related']) { $entry.related } else { $null }))
            substitutes  = @(Get-CmdPeekCatalogSubstituteList -Entry $entry)
            tasks        = @(Get-CmdPeekCatalogTaskList -Entry $entry)
            install      = Get-CmdPeekCatalogInstallMap -Entry $entry
            usages       = @(Get-CmdPeekCatalogUsageList -Entry $entry | Select-Object -First 5)
        })
    }
    return @($rows.ToArray())
}

function Test-CmdPeekCatalog {
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [hashtable]$Kits
    )

    $errors = New-Object System.Collections.Generic.List[string]
    if (-not $Catalog) { $Catalog = @{} }
    if (-not $Kits) { $Kits = @{} }

    foreach ($key in @($Catalog.Keys)) {
        $entry = $Catalog[$key]
        $usages = @(Get-CmdPeekCatalogUsageList -Entry $entry)
        if ($usages.Count -eq 0) {
            $errors.Add("Command '$key' has no usages")
        }
        foreach ($rel in @(ConvertTo-CmdPeekStringList -Value $(if ($entry.PSObject.Properties['related']) { $entry.related } else { $null }))) {
            $hit = Get-CmdPeekCatalogEntry -Command $rel -Catalog $Catalog
            if (-not $hit) {
                $errors.Add("Command '$key' related '$rel' is not a catalog command")
            }
        }
        foreach ($sub in @(Get-CmdPeekCatalogSubstituteList -Entry $entry)) {
            $hit = Get-CmdPeekCatalogEntry -Command $sub -Catalog $Catalog
            if (-not $hit) {
                $errors.Add("Command '$key' substitute '$sub' is not a catalog command")
            }
        }
    }

    foreach ($kitId in @($Kits.Keys)) {
        foreach ($member in @($Kits[$kitId])) {
            if (-not $member) { continue }
            $hit = Get-CmdPeekCatalogEntry -Command $member -Catalog $Catalog
            if (-not $hit) {
                $errors.Add("Kit '$kitId' member '$member' is not a catalog command")
            }
        }
    }

    return @($errors.ToArray())
}
