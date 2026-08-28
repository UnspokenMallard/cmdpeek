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
        $key = $prop.Name.ToLowerInvariant()
        if ($key -eq 'builtin') { continue }
        if ($prop.Value -is [string] -and $prop.Value) {
            $map[$key] = [string]$prop.Value
        }
    }
    return $map
}

function Get-CmdPeekCurrentOs {
    [CmdletBinding()]
    param()

    if ($env:OS -eq 'Windows_NT') { return 'windows' }
    try {
        if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            return 'windows'
        }
    }
    catch { }
    if (Test-Path -LiteralPath '/System/Library/CoreServices/SystemVersion.plist') {
        return 'macos'
    }
    return 'linux'
}

function Get-CmdPeekCatalogOrigin {
    [CmdletBinding()]
    param($Entry)

    if ($Entry -and $Entry.PSObject.Properties['origin'] -and $Entry.origin) {
        return ([string]$Entry.origin).ToLowerInvariant()
    }
    if (Test-CmdPeekCatalogIsBuiltin -Entry $Entry) { return 'builtin' }
    return 'package'
}

function Test-CmdPeekCatalogInstallBuiltinFlag {
    [CmdletBinding()]
    param($Entry)

    if (-not $Entry -or -not $Entry.PSObject.Properties['install'] -or -not $Entry.install) {
        return $false
    }
    $inst = $Entry.install
    if (-not $inst.PSObject.Properties['builtin']) { return $false }
    $flag = $inst.builtin
    if ($flag -is [bool]) { return [bool]$flag }
    if ($flag -is [string]) {
        return $flag.ToLowerInvariant() -in @('true', '1', 'yes')
    }
    return $false
}

function Test-CmdPeekCatalogIsBuiltin {
    [CmdletBinding()]
    param($Entry)

    if (-not $Entry) { return $false }
    if ($Entry.PSObject.Properties['origin'] -and $Entry.origin) {
        if (([string]$Entry.origin).ToLowerInvariant() -eq 'builtin') { return $true }
    }
    return [bool](Test-CmdPeekCatalogInstallBuiltinFlag -Entry $Entry)
}

function Get-CmdPeekCatalogOsList {
    [CmdletBinding()]
    param($Entry)
    if (-not $Entry -or -not $Entry.PSObject.Properties['os']) { return @() }
    return @(ConvertTo-CmdPeekStringList -Value $Entry.os)
}

function Get-CmdPeekCatalogShellList {
    [CmdletBinding()]
    param($Entry)
    if (-not $Entry -or -not $Entry.PSObject.Properties['shell']) { return @() }
    return @(ConvertTo-CmdPeekStringList -Value $Entry.shell)
}

function Get-CmdPeekCatalogGotchaList {
    [CmdletBinding()]
    param($Entry)
    if (-not $Entry -or -not $Entry.PSObject.Properties['gotchas']) { return @() }
    return @(ConvertTo-CmdPeekStringList -Value $Entry.gotchas)
}

function Get-CmdPeekCatalogWhenToUse {
    [CmdletBinding()]
    param($Entry)
    if (-not $Entry) { return '' }
    if ($Entry.PSObject.Properties['whenToUse'] -and $Entry.whenToUse) {
        return [string]$Entry.whenToUse
    }
    return ''
}

function Get-CmdPeekCatalogWhenNotToUse {
    [CmdletBinding()]
    param($Entry)
    if (-not $Entry) { return '' }
    if ($Entry.PSObject.Properties['whenNotToUse'] -and $Entry.whenNotToUse) {
        return [string]$Entry.whenNotToUse
    }
    return ''
}

function Test-CmdPeekCatalogAppliesToOs {
    [CmdletBinding()]
    param(
        $Entry,
        [string]$Os
    )

    if (-not $Os) { $Os = Get-CmdPeekCurrentOs }
    $oses = @(Get-CmdPeekCatalogOsList -Entry $Entry)
    if ($oses.Count -eq 0) { return $true }
    foreach ($item in $oses) {
        if ($item.ToLowerInvariant() -eq $Os.ToLowerInvariant()) { return $true }
    }
    return $false
}

function Get-CmdPeekLearnedCatalogPath {
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
    return (Join-Path $DataDirectory 'catalog.learned.json')
}

function Test-CmdPeekLearnedCommandName {
    [CmdletBinding()]
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    return [bool]($Command -match '^[A-Za-z][A-Za-z0-9._-]{0,79}$')
}

function Get-CmdPeekNameCollision {
    [CmdletBinding()]
    param(
        [string]$Command
    )

    if ([string]::IsNullOrWhiteSpace($Command)) { return @() }
    $key = $Command.ToLowerInvariant()
    $map = @{
        'curl'  = 'In Windows PowerShell, curl is an alias for Invoke-WebRequest. Call curl.exe for the real client.'
        'wget'  = 'In Windows PowerShell, wget is an alias for Invoke-WebRequest. Call wget.exe if you installed GNU Wget.'
        'sc'    = 'In PowerShell, sc is an alias for Set-Content. Call sc.exe for the Service Control Manager.'
        'find'  = 'Windows find.exe searches file contents (like findstr). POSIX find searches the tree by name. PowerShell has no Unix find.'
        'where' = 'PowerShell where is Where-Object. Call where.exe to search PATH.'
        'sort'  = 'PowerShell sort is Sort-Object, not the POSIX sort filter.'
        'sleep' = 'PowerShell sleep is Start-Sleep. POSIX sleep is a binary that takes seconds.'
        'cat'   = 'PowerShell cat is Get-Content. POSIX cat writes files to stdout.'
        'ls'    = 'PowerShell ls is Get-ChildItem. POSIX ls lists directory entries and does not recurse the same way.'
        'dir'   = 'cmd dir and PowerShell dir (Get-ChildItem) differ from POSIX ls.'
        'kill'  = 'PowerShell kill is Stop-Process. POSIX kill signals a PID.'
        'mkdir' = 'PowerShell mkdir is New-Item -ItemType Directory. POSIX mkdir has -p.'
        'echo'  = 'PowerShell echo is Write-Output. cmd echo and POSIX echo quote differently.'
        'copy'  = 'cmd copy is not robocopy. PowerShell copy is Copy-Item.'
        'move'  = 'PowerShell move is Move-Item. cmd move does not copy across volumes the same way.'
        'type'  = 'cmd type prints a file. PowerShell type is Get-Content. Neither is the POSIX type builtin.'
        'set'   = 'cmd set and POSIX set are not Set-Variable. PowerShell set is a default alias for Set-Variable.'
        'compare' = 'PowerShell compare is Compare-Object, not fc.exe.'
        'fc'    = 'fc.exe compares files. It is not Format-Custom (fc in PowerShell).'
        'gcm'   = 'PowerShell gcm is Get-Command, not git commit -m.'
        'gps'   = 'PowerShell gps is Get-Process, not git push.'
        'rm'    = 'PowerShell rm is Remove-Item and can recurse. POSIX rm needs -r for directories.'
    }
    if (-not $map.ContainsKey($key) -or -not $map[$key]) { return @() }
    return @(
        [pscustomobject]@{
            command = $Command
            shell   = 'powershell'
            warning = [string]$map[$key]
        }
    )
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

    if (Test-CmdPeekCatalogIsBuiltin -Entry $entry) {
        if ($map.Count -eq 0) { return @() }
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
            origin       = Get-CmdPeekCatalogOrigin -Entry $entry
            os           = @(Get-CmdPeekCatalogOsList -Entry $entry)
            shell        = @(Get-CmdPeekCatalogShellList -Entry $entry)
            capabilities = @(Get-CmdPeekCatalogCapabilityList -Entry $entry)
            aliases      = @(Get-CmdPeekCatalogAliasList -Entry $entry)
            related      = @(ConvertTo-CmdPeekStringList -Value $(if ($entry.PSObject.Properties['related']) { $entry.related } else { $null }))
            substitutes  = @(Get-CmdPeekCatalogSubstituteList -Entry $entry)
            tasks        = @(Get-CmdPeekCatalogTaskList -Entry $entry)
            gotchas      = @(Get-CmdPeekCatalogGotchaList -Entry $entry)
            whenToUse    = Get-CmdPeekCatalogWhenToUse -Entry $entry
            whenNotToUse = Get-CmdPeekCatalogWhenNotToUse -Entry $entry
            install      = Get-CmdPeekCatalogInstallMap -Entry $entry
            usages       = @(Get-CmdPeekCatalogUsageList -Entry $entry | Select-Object -First 5)
            collisions   = @(Get-CmdPeekNameCollision -Command $key)
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

    $validOrigin = @('builtin', 'package', 'path')
    $validOs = @('windows', 'linux', 'macos')
    $validShell = @('cmd', 'powershell', 'posix')

    foreach ($key in @($Catalog.Keys)) {
        $entry = $Catalog[$key]
        $usages = @(Get-CmdPeekCatalogUsageList -Entry $entry)
        if ($usages.Count -eq 0) {
            $errors.Add("Command '$key' has no usages")
        }
        $origin = ''
        if ($entry -and $entry.PSObject.Properties['origin'] -and $entry.origin) {
            $origin = ([string]$entry.origin).ToLowerInvariant()
            if ($validOrigin -notcontains $origin) {
                $errors.Add("Command '$key' origin '$origin' is invalid")
            }
        }
        $isBuiltin = Test-CmdPeekCatalogIsBuiltin -Entry $entry
        $installMap = Get-CmdPeekCatalogInstallMap -Entry $entry
        if ($isBuiltin -and $installMap.Count -gt 0) {
            $errors.Add("Command '$key' is builtin but has package install ids")
        }
        if ($origin -eq 'package' -and $isBuiltin) {
            $errors.Add("Command '$key' origin is package but install.builtin is set")
        }
        foreach ($osName in @(Get-CmdPeekCatalogOsList -Entry $entry)) {
            if ($validOs -notcontains $osName.ToLowerInvariant()) {
                $errors.Add("Command '$key' os '$osName' is invalid")
            }
        }
        foreach ($shellName in @(Get-CmdPeekCatalogShellList -Entry $entry)) {
            if ($validShell -notcontains $shellName.ToLowerInvariant()) {
                $errors.Add("Command '$key' shell '$shellName' is invalid")
            }
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

function Get-CmdPeekRowPackageManager {
    [CmdletBinding()]
    param(
        $Entry,
        [string]$Fallback = 'path'
    )

    if (Test-CmdPeekCatalogIsBuiltin -Entry $Entry) { return 'builtin' }
    $origin = Get-CmdPeekCatalogOrigin -Entry $Entry
    if ($origin -eq 'builtin') { return 'builtin' }
    if ($Fallback) { return $Fallback }
    return 'path'
}

function Save-CmdPeekLearnedCatalogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [AllowEmptyCollection()]
        [string[]]$Usages,
        [string]$DataDirectory,
        [hashtable]$Catalog,
        [string]$Category = 'other',
        [string]$Origin = 'path'
    )

    if (-not $DataDirectory) { return $false }
    if (-not (Test-CmdPeekLearnedCommandName -Command $Command)) { return $false }
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Usages)) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        if ($item -match '(^|\s)(--help|-h)(\s|$)') { continue }
        $keep.Add([string]$item)
    }
    if ($keep.Count -eq 0) { return $false }

    $shipped = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    if ($shipped) {
        $existing = @(Get-CmdPeekCatalogUsageList -Entry $shipped)
        if ($existing.Count -gt 0) { return $false }
    }

    $path = Get-CmdPeekLearnedCatalogPath -DataDirectory $DataDirectory
    if (-not $path) { return $false }

    $commandObj = New-Object PSObject
    $count = 0
    if (Test-Path -LiteralPath $path) {
        try {
            $existingJson = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existingJson -and $existingJson.PSObject.Properties['commands'] -and $existingJson.commands) {
                foreach ($prop in $existingJson.commands.PSObject.Properties) {
                    $count++
                    $commandObj | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
            }
        }
        catch { }
    }

    $already = $false
    foreach ($prop in $commandObj.PSObject.Properties) {
        if ($prop.Name.ToLowerInvariant() -eq $Command.ToLowerInvariant()) { $already = $true; break }
    }
    if (-not $already -and $count -ge 200) { return $false }

    $payloadEntry = [pscustomobject]@{
        category = $Category
        origin   = $Origin
        usages   = @($keep)
    }
    $commandObj | Add-Member -NotePropertyName $Command -NotePropertyValue $payloadEntry -Force

    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $payload = [pscustomobject]@{
        schemaVersion = 1
        commands      = $commandObj
    }
    ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding UTF8
    return $true
}

function Get-CmdPeekCommandCard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [hashtable]$Catalog,
        [AllowEmptyCollection()]
        [object[]]$History,
        [scriptblock]$CommandTester,
        [string]$PreferredManager
    )

    if (-not $Catalog) { $Catalog = @{} }
    $canonical = Get-CmdPeekCanonicalCommand -Command $Command -Catalog $Catalog
    $entry = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    $why = $null
    if (Get-Command Get-CmdPeekWhyCommand -ErrorAction SilentlyContinue) {
        $why = Get-CmdPeekWhyCommand -Command $Command -History $History -Catalog $Catalog -CommandTester $CommandTester -PreferredManager $PreferredManager
    }

    $usages = @()
    if ($why -and $why.PSObject.Properties['usages']) {
        $usages = @($why.usages)
    }
    else {
        $usages = @(Get-CmdPeekCatalogUsageList -Entry $entry | Select-Object -First 5)
    }

    $row = $null
    foreach ($item in @($History)) {
        if (-not $item -or -not $item.Command) { continue }
        if ($item.Command.ToLowerInvariant() -eq $canonical.ToLowerInvariant() -or $item.Command.ToLowerInvariant() -eq $Command.ToLowerInvariant()) {
            $row = $item
            break
        }
    }

    $os = Get-CmdPeekCurrentOs
    $subs = @(Get-CmdPeekCatalogSubstituteList -Entry $entry)
    $installedSet = Get-CmdPeekInstalledNameSet -History $History -Catalog $Catalog
    $subRows = New-Object System.Collections.Generic.List[object]
    foreach ($sub in $subs) {
        $subEntry = Get-CmdPeekCatalogEntry -Command $sub -Catalog $Catalog
        $prefer = Test-CmdPeekCatalogAppliesToOs -Entry $subEntry -Os $os
        $subRows.Add([pscustomobject]@{
            command   = $sub
            installed = [bool](Test-CmdPeekNameCovered -Name $sub -InstalledSet $installedSet -Catalog $Catalog)
            origin    = Get-CmdPeekCatalogOrigin -Entry $subEntry
            preferOnOs = [bool]$prefer
        })
    }

    $related = @(ConvertTo-CmdPeekStringList -Value $(if ($entry -and $entry.PSObject.Properties['related']) { $entry.related } else { $null }))
    $dangerous = @(
        ConvertTo-CmdPeekStructuredUsage -Usage $usages | Where-Object { $_.unsafe } | ForEach-Object { $_.argv }
    )

    $pm = $null
    if ($row -and $row.PSObject.Properties['PackageManager']) { $pm = [string]$row.PackageManager }
    elseif ($why -and $why.PSObject.Properties['onPathManager'] -and $why.onPathManager) { $pm = [string]$why.onPathManager }
    elseif (Test-CmdPeekCatalogIsBuiltin -Entry $entry) { $pm = 'builtin' }

    return [pscustomobject]@{
        command         = $(if ($canonical) { $canonical } else { $Command })
        queried         = $Command
        origin          = Get-CmdPeekCatalogOrigin -Entry $entry
        os              = @(Get-CmdPeekCatalogOsList -Entry $entry)
        shell           = @(Get-CmdPeekCatalogShellList -Entry $entry)
        category        = $(if ($entry -and $entry.PSObject.Properties['category'] -and $entry.category) { [string]$entry.category } else { 'other' })
        onPath          = [bool]$(if ($why) { $why.onPath } elseif ($row -and $row.PSObject.Properties['OnPath']) { $row.OnPath } else { $false })
        installed       = [bool]($null -ne $row)
        covered         = [bool]$(if ($why) { $why.installed } else { $null -ne $row })
        packageManager  = $pm
        whenToUse       = Get-CmdPeekCatalogWhenToUse -Entry $entry
        whenNotToUse    = Get-CmdPeekCatalogWhenNotToUse -Entry $entry
        gotchas         = @(Get-CmdPeekCatalogGotchaList -Entry $entry)
        collisions      = @(Get-CmdPeekNameCollision -Command $(if ($canonical) { $canonical } else { $Command }))
        aliases         = @(Get-CmdPeekCatalogAliasList -Entry $entry)
        capabilities    = @(Get-CmdPeekCatalogCapabilityList -Entry $entry)
        related         = $related
        substitutes     = @($subRows.ToArray())
        usages          = $usages
        usageDetails    = @(ConvertTo-CmdPeekStructuredUsage -Usage $usages)
        dangerous       = @($dangerous)
        appliesToOs     = [bool](Test-CmdPeekCatalogAppliesToOs -Entry $entry -Os $os)
        currentOs       = $os
        installCommands = $(if ($why) { @($why.installCommands) } else { @(Get-CmdPeekInstallCommands -Command $(if ($canonical) { $canonical } else { $Command }) -Catalog $Catalog -PreferredManager $PreferredManager) })
    }
}

function Test-CmdPeekSystemInventoryRow {
    [CmdletBinding()]
    param(
        $Row,
        $Entry
    )

    if ($Entry -and (Test-CmdPeekCatalogIsBuiltin -Entry $Entry)) { return $true }
    if ($Entry -and $Entry.PSObject.Properties['category'] -and $Entry.category) {
        if (([string]$Entry.category).ToLowerInvariant() -eq 'system') { return $true }
    }
    if ($Row -and $Row.PSObject.Properties['PackageManager'] -and $Row.PackageManager) {
        $pm = ([string]$Row.PackageManager).ToLowerInvariant()
        if ($pm -in @('builtin', 'windows')) { return $true }
    }
    if ($Row -and $Row.PSObject.Properties['Origin'] -and $Row.Origin) {
        if (([string]$Row.Origin).ToLowerInvariant() -eq 'builtin') { return $true }
    }
    if ($Row -and $Row.PSObject.Properties['Category'] -and $Row.Category) {
        if (([string]$Row.Category).ToLowerInvariant() -eq 'system') { return $true }
    }
    return $false
}

function Get-CmdPeekSystemList {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog
    )

    if (-not $Catalog) { $Catalog = @{} }
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($row in @($History)) {
        if (-not $row -or -not $row.Command) { continue }
        $key = $row.Command.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $entry = Get-CmdPeekCatalogEntry -Command $row.Command -Catalog $Catalog
        if (-not (Test-CmdPeekSystemInventoryRow -Row $row -Entry $entry)) { continue }
        $seen[$key] = $true
        $rows.Add($row)
    }
    return @($rows.ToArray() | Sort-Object @{ Expression = { $_.Command.ToLowerInvariant() } })
}
