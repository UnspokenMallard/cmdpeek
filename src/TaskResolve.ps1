#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CmdPeekTaskSynonymMap {
    [CmdletBinding()]
    param()

    return @{
        'process'     = @('processes', 'tasklist', 'ps', 'get-process')
        'processes'   = @('process', 'tasklist', 'ps', 'get-process')
        'copy'        = @('robocopy', 'xcopy', 'cp', 'copy-item')
        'files'       = @('file', 'directory', 'folder')
        'listen'      = @('listening', 'netstat', 'ss', 'port', 'ports')
        'listening'   = @('listen', 'netstat', 'ss', 'port')
        'port'        = @('ports', 'listen', 'netstat', 'ss')
        'network'     = @('ip', 'ipconfig', 'netsh', 'dns')
        'ip'          = @('ipconfig', 'address', 'network')
        'permission'  = @('permissions', 'acl', 'icacls', 'chmod', 'get-acl')
        'permissions' = @('permission', 'acl', 'icacls', 'chmod')
        'acl'         = @('icacls', 'get-acl', 'chmod')
        'service'     = @('services', 'sc', 'get-service', 'systemctl')
        'services'    = @('service', 'sc', 'get-service', 'systemctl')
        'search'      = @('grep', 'findstr', 'select-string', 'rg')
        'grep'        = @('findstr', 'select-string', 'rg')
        'hash'        = @('checksum', 'certutil', 'sha256')
        'clipboard'   = @('clip', 'paste')
        'reboot'      = @('shutdown', 'restart')
        'disk'        = @('df', 'du', 'space')
        'owner'       = @('chown', 'icacls')
        'path'        = @('where', 'which')
        'hostname'    = @('computer', 'uname')
        'log'         = @('journalctl', 'tail')
        'dns'         = @('nslookup', 'resolve')
        'firewall'    = @('netsh')
        'registry'    = @('reg')
        'scheduled'   = @('schtasks', 'cron')
        'cron'        = @('schtasks', 'crontab')
    }
}

function Get-CmdPeekTaskTokens {
    param([string]$Task)
    if ([string]::IsNullOrWhiteSpace($Task)) { return @() }
    $lower = $Task.ToLowerInvariant()
    $parts = @($lower -split '[^a-z0-9+.-]+' | Where-Object { $_ -and $_.Length -gt 1 })
    $syn = Get-CmdPeekTaskSynonymMap
    $out = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($part in $parts) {
        if ($seen.ContainsKey($part)) { continue }
        $seen[$part] = $true
        $out.Add($part)
        if ($syn.ContainsKey($part)) {
            foreach ($extra in @($syn[$part])) {
                $el = $extra.ToLowerInvariant()
                if ($seen.ContainsKey($el)) { continue }
                $seen[$el] = $true
                $out.Add($el)
            }
        }
    }
    return @($out)
}

function Get-CmdPeekTaskScore {
    [CmdletBinding()]
    param(
        [string]$Query,
        [string]$Command,
        $Entry
    )

    if ([string]::IsNullOrWhiteSpace($Query) -or [string]::IsNullOrWhiteSpace($Command)) { return 0 }
    $q = $Query.Trim().ToLowerInvariant()
    $tokens = @(Get-CmdPeekTaskTokens -Task $Query)
    $score = 0
    $reasons = New-Object System.Collections.Generic.List[string]

    $cmdLower = $Command.ToLowerInvariant()
    if ($cmdLower -eq $q) {
        $score += 90
        $reasons.Add('exact name')
    }
    elseif ($cmdLower.Contains($q) -or $q.Contains($cmdLower)) {
        $score += 60
        $reasons.Add('name')
    }

    $aliases = @(Get-CmdPeekCatalogAliasList -Entry $Entry)
    foreach ($alias in $aliases) {
        $al = $alias.ToLowerInvariant()
        if ($al -eq $q) {
            $score += 88
            $reasons.Add('alias')
        }
        elseif ($al.Contains($q) -or $q.Contains($al)) {
            $score += 50
            $reasons.Add('alias')
        }
    }

    $caps = @(Get-CmdPeekCatalogCapabilityList -Entry $Entry)
    foreach ($cap in $caps) {
        $cl = $cap.ToLowerInvariant()
        if ($cl -eq $q) {
            $score += 100
            $reasons.Add("capability '$cap'")
        }
        elseif ($tokens -contains $cl -or $q.Contains($cl)) {
            $score += 70
            $reasons.Add("capability '$cap'")
        }
    }

    $tasks = @(Get-CmdPeekCatalogTaskList -Entry $Entry)
    foreach ($task in $tasks) {
        $tl = $task.ToLowerInvariant()
        if ($tl -eq $q) {
            $score += 95
            $reasons.Add('task')
        }
        elseif ($q.Contains($tl) -or $tl.Contains($q)) {
            $score += 80
            $reasons.Add("task '$task'")
        }
        else {
            $overlap = 0
            $taskTokens = @(Get-CmdPeekTaskTokens -Task $task)
            foreach ($tok in $tokens) {
                if ($taskTokens -contains $tok) { $overlap++ }
            }
            if ($overlap -ge 2) {
                $score += 55
                $reasons.Add("task '$task'")
            }
            elseif ($overlap -eq 1 -and $tokens.Count -eq 1) {
                $score += 35
                $reasons.Add("task '$task'")
            }
        }
    }

    $cat = ''
    if ($Entry -and $Entry.PSObject.Properties['category'] -and $Entry.category) {
        $cat = ([string]$Entry.category).ToLowerInvariant()
    }
    if ($cat -and ($cat -eq $q -or $tokens -contains $cat)) {
        $score += 40
        $reasons.Add("category '$cat'")
    }

    $usages = @(Get-CmdPeekCatalogUsageList -Entry $Entry)
    $blob = ($usages -join "`n").ToLowerInvariant()
    if ($blob -and $q.Length -gt 2 -and $blob.Contains($q)) {
        $score += 45
        $reasons.Add('usage text')
    }
    else {
        $hitTok = 0
        foreach ($tok in $tokens) {
            if ($tok.Length -gt 2 -and $blob.Contains($tok)) { $hitTok++ }
        }
        if ($hitTok -ge 2) {
            $score += 30
            $reasons.Add('usage text')
        }
    }

    foreach ($tok in $tokens) {
        if ($tok.Length -gt 2 -and $cmdLower -eq $tok) {
            $score += 40
            $reasons.Add('synonym')
            break
        }
    }

    $reason = ''
    if ($reasons.Count -gt 0) {
        $uniq = @($reasons | Select-Object -Unique)
        $reason = $uniq[0]
    }
    return [pscustomobject]@{ Score = [int]$score; Reason = $reason }
}

function Resolve-CmdPeekTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Task,
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [int]$Limit = 8,
        [string]$PreferredManager
    )

    if (-not $Catalog) { $Catalog = @{} }
    if ($Limit -lt 1) { $Limit = 8 }
    $query = $Task.Trim()
    $currentOs = Get-CmdPeekCurrentOs
    $installedSet = Get-CmdPeekInstalledNameSet -History $History -Catalog $Catalog
    $historyByName = @{}
    foreach ($row in @($History)) {
        if (-not $row -or -not $row.Command) { continue }
        $k = $row.Command.ToLowerInvariant()
        if (-not $historyByName.ContainsKey($k)) { $historyByName[$k] = $row }
    }

    $installedHits = New-Object System.Collections.Generic.List[object]
    $missingHits = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($key in @($Catalog.Keys)) {
        $lk = $key.ToLowerInvariant()
        if ($seen.ContainsKey($lk)) { continue }
        $seen[$lk] = $true
        $entry = $Catalog[$key]
        $scored = Get-CmdPeekTaskScore -Query $query -Command $key -Entry $entry
        if ($scored.Score -le 0) { continue }

        $applies = Test-CmdPeekCatalogAppliesToOs -Entry $entry -Os $currentOs
        $isBuiltin = Test-CmdPeekCatalogIsBuiltin -Entry $entry
        if ($applies) {
            $scored.Score = [int]$scored.Score + 25
        }
        else {
            $scored.Score = [int]$scored.Score - 40
        }

        $usages = @(Get-CmdPeekCatalogUsageList -Entry $entry | Select-Object -First 3)
        $row = $null
        foreach ($name in @(Get-CmdPeekCommandNamesFor -Command $key -Catalog $Catalog)) {
            $nk = $name.ToLowerInvariant()
            if ($historyByName.ContainsKey($nk)) { $row = $historyByName[$nk]; break }
        }
        $covered = Test-CmdPeekNameCovered -Name $key -InstalledSet $installedSet -Catalog $Catalog
        $actuallyInstalled = $null -ne $row
        $onPath = $false
        if ($row -and $row.PSObject.Properties['OnPath']) { $onPath = [bool]$row.OnPath }
        if ($actuallyInstalled) {
            $scored.Score = [int]$scored.Score + 20
            if ($onPath) { $scored.Score = [int]$scored.Score + 10 }
            if ($isBuiltin -and $applies) { $scored.Score = [int]$scored.Score + 15 }
        }
        if ($scored.Score -le 0 -and -not $actuallyInstalled) { continue }
        $item = [pscustomobject]@{
            command          = [string]$key
            score            = [int]$scored.Score
            reason           = [string]$scored.Reason
            category         = $(if ($entry.PSObject.Properties['category'] -and $entry.category) { [string]$entry.category } else { 'other' })
            origin           = Get-CmdPeekCatalogOrigin -Entry $entry
            os               = @(Get-CmdPeekCatalogOsList -Entry $entry)
            capabilities     = @(Get-CmdPeekCatalogCapabilityList -Entry $entry)
            usages           = $usages
            usageDetails     = @(ConvertTo-CmdPeekStructuredUsage -Usage $usages)
            packageManager   = $(if ($row -and $row.PSObject.Properties['PackageManager']) { [string]$row.PackageManager } else { $null })
            onPath           = $onPath
            installed        = [bool]$actuallyInstalled
            appliesToOs      = [bool]$applies
            installCommands  = @()
        }
        if ($actuallyInstalled) {
            $installedHits.Add($item)
        }
        elseif (-not $covered) {
            if ($isBuiltin -and -not $applies) { continue }
            if ($isBuiltin) {
                # Builtins cannot be scooped in; omit from missing unless they also have package ids.
                $installLines = @(Get-CmdPeekInstallCommands -Command $key -Catalog $Catalog -PreferredManager $PreferredManager)
                if ($installLines.Count -eq 0) { continue }
                $item.installCommands = $installLines
            }
            else {
                $item.installCommands = @(Get-CmdPeekInstallCommands -Command $key -Catalog $Catalog -PreferredManager $PreferredManager)
            }
            $missingHits.Add($item)
        }
    }

    $installedSorted = @($installedHits.ToArray() | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = { $_.command.ToLowerInvariant() } } | Select-Object -First $Limit)
    $missingSorted = @($missingHits.ToArray() | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = { $_.command.ToLowerInvariant() } } | Select-Object -First $Limit)

    return [pscustomobject]@{
        query     = $query
        installed = @($installedSorted)
        missing   = @($missingSorted)
    }
}

function Get-CmdPeekWhyCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [scriptblock]$CommandTester,
        [string]$PreferredManager
    )

    if (-not $Catalog) { $Catalog = @{} }
    $canonical = Get-CmdPeekCanonicalCommand -Command $Command -Catalog $Catalog
    $entry = Get-CmdPeekCatalogEntry -Command $Command -Catalog $Catalog
    $installedSet = Get-CmdPeekInstalledNameSet -History $History -Catalog $Catalog
    $installed = Test-CmdPeekNameCovered -Name $Command -InstalledSet $installedSet -Catalog $Catalog
    $matched = @(
        @($History) | Where-Object {
            $_ -and $_.Command -and (
                $_.Command.ToLowerInvariant() -eq $Command.ToLowerInvariant() -or
                $_.Command.ToLowerInvariant() -eq $canonical.ToLowerInvariant()
            )
        }
    )
    $onPathManager = $null
    $onPath = $false
    if ($CommandTester -and $Command) {
        try { $onPath = [bool](& $CommandTester $Command) } catch { $onPath = $false }
    }
    if ($matched.Count -gt 0) {
        foreach ($row in $matched) {
            $name = [string]$row.Command
            $ok = $false
            if ($CommandTester) {
                try { $ok = [bool](& $CommandTester $name) } catch { $ok = $false }
            }
            elseif ($row.PSObject.Properties['OnPath']) {
                $ok = [bool]$row.OnPath
            }
            if ($ok) {
                $onPath = $true
                $onPathManager = [string]$row.PackageManager
                break
            }
        }
        if (-not $onPathManager) {
            $onPathManager = [string]$matched[0].PackageManager
        }
    }

    $subsInstalled = New-Object System.Collections.Generic.List[string]
    $subsMissing = New-Object System.Collections.Generic.List[string]
    foreach ($sub in @(Get-CmdPeekCatalogSubstituteList -Entry $entry)) {
        if (Test-CmdPeekNameCovered -Name $sub -InstalledSet $installedSet -Catalog $Catalog) {
            $subsInstalled.Add($sub)
        }
        else {
            $subsMissing.Add($sub)
        }
    }

    return [pscustomobject]@{
        command         = $(if ($canonical) { $canonical } else { $Command })
        queried         = $Command
        installed       = [bool]$installed
        onPath          = [bool]$onPath
        onPathManager   = $onPathManager
        packageManagers = @($matched | ForEach-Object { [string]$_.PackageManager } | Select-Object -Unique)
        category        = $(if ($entry -and $entry.PSObject.Properties['category']) { [string]$entry.category } else { 'other' })
        capabilities    = @(Get-CmdPeekCatalogCapabilityList -Entry $entry)
        aliases         = @(Get-CmdPeekCatalogAliasList -Entry $entry)
        substitutesInstalled = @($subsInstalled)
        substitutesMissing   = @($subsMissing)
        usages          = @(Get-CmdPeekCatalogUsageList -Entry $entry | Select-Object -First 5)
        origin          = Get-CmdPeekCatalogOrigin -Entry $entry
        os              = @(Get-CmdPeekCatalogOsList -Entry $entry)
        shell           = @(Get-CmdPeekCatalogShellList -Entry $entry)
        gotchas         = @(Get-CmdPeekCatalogGotchaList -Entry $entry)
        whenToUse       = Get-CmdPeekCatalogWhenToUse -Entry $entry
        whenNotToUse    = Get-CmdPeekCatalogWhenNotToUse -Entry $entry
        collisions      = @(Get-CmdPeekNameCollision -Command $(if ($canonical) { $canonical } else { $Command }))
        appliesToOs     = [bool](Test-CmdPeekCatalogAppliesToOs -Entry $entry)
        installCommands = @(Get-CmdPeekInstallCommands -Command $(if ($canonical) { $canonical } else { $Command }) -Catalog $Catalog -PreferredManager $PreferredManager)
        rows            = @($matched)
    }
}

function Get-CmdPeekHaveList {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [string]$Capability,
        [string]$Category
    )

    if (-not $Catalog) { $Catalog = @{} }
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($row in @($History)) {
        if (-not $row -or -not $row.Command) { continue }
        $key = $row.Command.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $entry = Get-CmdPeekCatalogEntry -Command $row.Command -Catalog $Catalog
        $caps = @(Get-CmdPeekCatalogCapabilityList -Entry $entry)
        $cat = 'other'
        if ($row.PSObject.Properties['Category'] -and $row.Category) { $cat = [string]$row.Category }
        elseif ($entry -and $entry.PSObject.Properties['category'] -and $entry.category) { $cat = [string]$entry.category }
        if ($Capability) {
            $want = $Capability.ToLowerInvariant()
            $ok = $false
            foreach ($c in $caps) { if ($c.ToLowerInvariant() -eq $want) { $ok = $true; break } }
            if (-not $ok) { continue }
        }
        if ($Category) {
            if ($cat.ToLowerInvariant() -ne $Category.ToLowerInvariant()) { continue }
        }
        $usages = @()
        if ($row.PSObject.Properties['Usages'] -and $row.Usages) {
            $usages = @($row.Usages | Select-Object -First 3)
        }
        else {
            $usages = @(Get-CmdPeekCatalogUsageList -Entry $entry | Select-Object -First 3)
        }
        $rows.Add([pscustomobject]@{
            Command        = [string]$row.Command
            PackageManager = [string]$row.PackageManager
            Category       = $cat
            Capabilities   = $caps
            Usages         = $usages
            OnPath         = $(if ($row.PSObject.Properties['OnPath']) { [bool]$row.OnPath } else { $true })
        })
    }
    return @($rows.ToArray() | Sort-Object @{ Expression = { $_.Category.ToLowerInvariant() } }, @{ Expression = { $_.Command.ToLowerInvariant() } })
}

function Search-CmdPeekAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [string]$PreferredManager,
        [scriptblock]$PackageSearchRunner,
        [int]$Limit = 15
    )

    if (-not $Catalog) { $Catalog = @{} }
    $resolved = Resolve-CmdPeekTask -Task $Query -History $History -Catalog $Catalog -Limit $Limit -PreferredManager $PreferredManager
    $catalogHits = @($resolved.missing)

    $pmHits = New-Object System.Collections.Generic.List[object]
    if ($PackageSearchRunner) {
        try {
            $raw = @(& $PackageSearchRunner $Query)
            foreach ($item in $raw) {
                if (-not $item) { continue }
                if ($item -is [string]) {
                    $pmHits.Add([pscustomobject]@{ name = $item; manager = 'unknown'; source = 'package-manager' })
                }
                else {
                    $pmHits.Add($item)
                }
            }
        }
        catch { }
    }

    $pmArr = @($pmHits.ToArray())
    $missingArr = @($catalogHits)
    $installedArr = @($resolved.installed)

    $out = [pscustomobject]@{ query = [string]$Query }
    Add-Member -InputObject $out -NotePropertyName catalogMissing -NotePropertyValue $missingArr
    Add-Member -InputObject $out -NotePropertyName catalogInstalled -NotePropertyValue $installedArr
    Add-Member -InputObject $out -NotePropertyName packageManagers -NotePropertyValue $pmArr
    return $out
}

function Compare-CmdPeekCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Left,
        [Parameter(Mandatory)]
        [string]$Right,
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [scriptblock]$CommandTester
    )

    if (-not $Catalog) { $Catalog = @{} }
    $leftCard = Get-CmdPeekCommandCard -Command $Left -Catalog $Catalog -History $History -CommandTester $CommandTester
    $rightCard = Get-CmdPeekCommandCard -Command $Right -Catalog $Catalog -History $History -CommandTester $CommandTester
    $os = Get-CmdPeekCurrentOs
    $prefer = $null
    if ($leftCard.installed -and -not $rightCard.installed) { $prefer = $leftCard.command }
    elseif ($rightCard.installed -and -not $leftCard.installed) { $prefer = $rightCard.command }
    elseif ($leftCard.appliesToOs -and -not $rightCard.appliesToOs) { $prefer = $leftCard.command }
    elseif ($rightCard.appliesToOs -and -not $leftCard.appliesToOs) { $prefer = $rightCard.command }
    elseif ($leftCard.origin -eq 'builtin' -and $leftCard.appliesToOs -and $leftCard.installed) { $prefer = $leftCard.command }
    elseif ($rightCard.origin -eq 'builtin' -and $rightCard.appliesToOs -and $rightCard.installed) { $prefer = $rightCard.command }

    return [pscustomobject]@{
        currentOs = $os
        prefer    = $prefer
        left      = $leftCard
        right     = $rightCard
    }
}

function Get-CmdPeekArgvSuggestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Argv,
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [scriptblock]$CommandTester,
        [string]$PreferredManager
    )

    if (-not $Catalog) { $Catalog = @{} }
    $trim = $Argv.Trim()
    $parts = @($trim -split '\s+', 2)
    $name = $parts[0]
    if ($name -match '[/\\]') {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($name)
    }
    $resolvedName = Resolve-CmdPeekTask -Task $name -History $History -Catalog $Catalog -PreferredManager $PreferredManager
    $resolvedFull = Resolve-CmdPeekTask -Task $trim -History $History -Catalog $Catalog -PreferredManager $PreferredManager
    $card = Get-CmdPeekCommandCard -Command $name -Catalog $Catalog -History $History -CommandTester $CommandTester -PreferredManager $PreferredManager
    $installedHits = New-Object System.Collections.Generic.List[object]
    $seenInst = @{}
    foreach ($hit in @($resolvedName.installed) + @($resolvedFull.installed)) {
        if (-not $hit -or -not $hit.command) { continue }
        $lk = $hit.command.ToLowerInvariant()
        if ($seenInst.ContainsKey($lk)) { continue }
        $seenInst[$lk] = $true
        $installedHits.Add($hit)
    }
    $installed = @($installedHits.ToArray())
    $recommended = $null
    if ($card.installed -and $card.appliesToOs) {
        $recommended = $card
    }
    elseif ($installed.Count -gt 0) {
        $top = $installed[0]
        $recommended = Get-CmdPeekCommandCard -Command $top.command -Catalog $Catalog -History $History -CommandTester $CommandTester -PreferredManager $PreferredManager
    }
    elseif ($card.PSObject.Properties['substitutes'] -and $card.substitutes) {
        foreach ($sub in @($card.substitutes)) {
            $subName = $(if ($sub -is [string]) { $sub } else { [string]$sub.command })
            if (-not $subName) { continue }
            $subCard = Get-CmdPeekCommandCard -Command $subName -Catalog $Catalog -History $History -CommandTester $CommandTester -PreferredManager $PreferredManager
            if ($subCard.installed) { $recommended = $subCard; break }
        }
    }
    if (-not $recommended -and $card.command) {
        $recommended = $card
    }

    $missingHits = New-Object System.Collections.Generic.List[object]
    $seenMiss = @{}
    foreach ($hit in @($resolvedName.missing) + @($resolvedFull.missing)) {
        if (-not $hit -or -not $hit.command) { continue }
        $lk = $hit.command.ToLowerInvariant()
        if ($seenMiss.ContainsKey($lk) -or $seenInst.ContainsKey($lk)) { continue }
        $seenMiss[$lk] = $true
        $missingHits.Add($hit)
    }

    return [pscustomobject]@{
        argv         = $trim
        queried      = $name
        recommended  = $recommended
        why          = $(if ($recommended) { $recommended.whenToUse } else { '' })
        os           = Get-CmdPeekCurrentOs
        installed    = $installed
        substitutes  = $(if ($recommended) { @($recommended.substitutes) } else { @() })
        example      = $(if ($recommended -and @($recommended.usages).Count -gt 0) { @($recommended.usages)[0] } else { $null })
        missing      = @($missingHits.ToArray())
    }
}
