#Requires -Version 5.1

function Get-CmdPeekModuleVersion {
    [CmdletBinding()]
    param([string]$ManifestPath)

    if (-not $ManifestPath) {
        $root = $script:CmdPeekModuleRoot
        if (-not $root) { $root = $PSScriptRoot }
        $ManifestPath = Join-Path $root 'cmdpeek.psd1'
    }
    if (-not (Test-Path -LiteralPath $ManifestPath)) { return $null }
    try {
        # Import-PowerShellDataFile is not on PowerShell 5.0, and a manifest is a
        # hashtable literal, so read the one field instead of invoking the file.
        $text = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
        if ($text -match "(?m)^\s*ModuleVersion\s*=\s*'([^']+)'") { return $Matches[1] }
    }
    catch { }
    return $null
}

function Get-CmdPeekMcpVersion {
    [CmdletBinding()]
    param([string]$PackageJsonPath)

    if (-not $PackageJsonPath) {
        $root = $script:CmdPeekModuleRoot
        if (-not $root) { $root = $PSScriptRoot }
        $PackageJsonPath = Join-Path (Split-Path -Parent $root) 'mcp/package.json'
    }
    if (-not (Test-Path -LiteralPath $PackageJsonPath)) { return $null }
    try {
        $pkg = Get-Content -LiteralPath $PackageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($pkg -and $pkg.PSObject.Properties['version']) { return [string]$pkg.version }
    }
    catch { }
    return $null
}

function Get-CmdPeekVersion {
    [CmdletBinding()]
    param(
        [string]$ManifestPath,
        [string]$PackageJsonPath
    )

    $module = Get-CmdPeekModuleVersion -ManifestPath $ManifestPath
    $mcp = Get-CmdPeekMcpVersion -PackageJsonPath $PackageJsonPath
    # A mismatch means a release shipped a CLI and an MCP server that disagree about
    # which wire shape they speak, which is the kind of drift nobody notices by hand.
    $inSync = $true
    if ($module -and $mcp) { $inSync = ($module -eq $mcp) }
    return [pscustomobject]@{
        module      = $module
        mcp         = $mcp
        inSync      = $inSync
        powerShell  = $PSVersionTable.PSVersion.ToString()
        os          = Get-CmdPeekCurrentOs
    }
}

function Get-CmdPeekFileFact {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Path
    )

    $exists = $false
    $size = 0
    $ageSeconds = $null
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($item) {
            $exists = $true
            if ($item.PSObject.Properties['Length'] -and $null -ne $item.Length) {
                $size = [long]$item.Length
            }
            $ageSeconds = [int]((Get-Date) - $item.LastWriteTime).TotalSeconds
        }
    }
    return [pscustomobject]@{
        name       = $Name
        path       = $Path
        exists     = $exists
        sizeBytes  = $size
        ageSeconds = $ageSeconds
    }
}

function Test-CmdPeekDirectoryWritable {
    [CmdletBinding()]
    param([string]$Path)

    if (-not $Path) { return $false }
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        $probe = Join-Path $Path ('.cmdpeek-write-probe-' + [guid]::NewGuid().ToString('N'))
        'probe' | Set-Content -LiteralPath $probe -Encoding UTF8 -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

function Get-CmdPeekDoctorReport {
    [CmdletBinding()]
    param(
        [string]$DataDirectory,
        [string]$ExamplesPath,
        [scriptblock]$CommandTester,
        [string[]]$HistoryPath,
        [switch]$Timing
    )

    $problems = New-Object System.Collections.Generic.List[string]
    $version = Get-CmdPeekVersion
    if (-not $version.inSync) {
        $problems.Add("Version drift: module is $($version.module) but mcp/package.json is $($version.mcp)")
    }

    $dir = Get-CmdPeekDataDirectory -DataDirectory $DataDirectory
    $writable = Test-CmdPeekDirectoryWritable -Path $dir
    if (-not $writable) {
        $problems.Add("Data directory is not writable: $dir")
    }

    $managerArgs = @{ All = $true }
    if ($CommandTester) { $managerArgs.CommandTester = $CommandTester }
    $managers = @(Get-CmdPeekPackageManager @managerArgs)
    $present = @($managers | Where-Object { $_.Present } | Select-Object -ExpandProperty Name)
    $missing = @($managers | Where-Object { -not $_.Present } | Select-Object -ExpandProperty Name)
    if ($present.Count -eq 0) {
        $problems.Add('No package manager detected, so the inventory will only contain PATH commands')
    }

    $catalogArgs = @{ DataDirectory = $dir }
    if ($ExamplesPath) { $catalogArgs.Path = $ExamplesPath }
    $catalog = @{}
    $catalogError = $null
    try { $catalog = Get-CmdPeekExampleCatalog @catalogArgs }
    catch {
        $catalogError = $_.Exception.Message
        $problems.Add("Catalog failed to load: $catalogError")
    }
    $kits = @{}
    try { $kits = Get-CmdPeekCatalogKits @catalogArgs } catch { $kits = @{} }

    $builtins = 0
    foreach ($key in @($catalog.Keys)) {
        if (Test-CmdPeekCatalogIsBuiltin -Entry $catalog[$key]) { $builtins++ }
    }
    $catalogErrors = @()
    if (-not $catalogError) {
        $catalogErrors = @(Test-CmdPeekCatalog -Catalog $catalog -Kits $kits)
        if ($catalogErrors.Count -gt 0) {
            $problems.Add("Catalog has $($catalogErrors.Count) validation error(s); run cmdpeek doctor -Json to see them")
        }
    }

    $learnedPath = Get-CmdPeekLearnedCatalogPath -DataDirectory $dir
    $learnedCount = 0
    if ($learnedPath -and (Test-Path -LiteralPath $learnedPath)) {
        try {
            $learned = Get-Content -LiteralPath $learnedPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($learned -and $learned.PSObject.Properties['commands'] -and $learned.commands) {
                $learnedCount = @($learned.commands.PSObject.Properties).Count
            }
        }
        catch {
            $problems.Add("Learned catalog overlay is not valid JSON: $learnedPath")
        }
    }

    $caches = @(
        Get-CmdPeekFileFact -Name 'state' -Path (Get-CmdPeekStatePath -DataDirectory $dir)
        Get-CmdPeekFileFact -Name 'inventory' -Path (Get-CmdPeekInventoryCachePath -DataDirectory $dir)
        Get-CmdPeekFileFact -Name 'help-text' -Path (Get-CmdPeekHelpCachePath -DataDirectory $dir)
        Get-CmdPeekFileFact -Name 'pe-subsystem' -Path (Get-CmdPeekPeSubsystemCachePath -DataDirectory $dir)
    )

    $historyPaths = @()
    if ($PSBoundParameters.ContainsKey('HistoryPath')) { $historyPaths = @($HistoryPath) }
    else { $historyPaths = @(Get-CmdPeekPsReadLineHistoryPath) }
    $history = New-Object System.Collections.Generic.List[object]
    foreach ($hp in $historyPaths) {
        $lines = $null
        $readable = $false
        if ($hp -and (Test-Path -LiteralPath $hp)) {
            try {
                $lines = @(Get-Content -LiteralPath $hp -ErrorAction Stop).Count
                $readable = $true
            }
            catch { $readable = $false }
        }
        $history.Add([pscustomobject]@{ path = $hp; readable = $readable; lines = $lines })
    }
    if (@($history | Where-Object { $_.readable }).Count -eq 0) {
        $problems.Add('No readable shell history found, so cmdpeek rusty has nothing to compare against')
    }

    $profilePath = $PROFILE
    $profileHint = $false
    if ($profilePath -and (Test-Path -LiteralPath $profilePath)) {
        try {
            $profileHint = [bool]((Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8) -match 'BEGIN cmdpeek hint')
        }
        catch { $profileHint = $false }
    }

    $timings = @()
    if ($Timing) { $timings = @(Measure-CmdPeekScanStage -DataDirectory $dir -ExamplesPath $ExamplesPath -CommandTester $CommandTester) }

    return [pscustomobject]@{
        generatedAt   = (Get-Date).ToString('o')
        version       = $version
        dataDirectory = [pscustomobject]@{
            path     = $dir
            exists   = (Test-Path -LiteralPath $dir)
            writable = $writable
        }
        managers      = [pscustomobject]@{
            present = $present
            missing = $missing
        }
        catalog       = [pscustomobject]@{
            commands       = @($catalog.Keys).Count
            kits           = @($kits.Keys).Count
            builtins       = $builtins
            learnedPath    = $learnedPath
            learnedEntries = $learnedCount
            loadError      = $catalogError
            errors         = $catalogErrors
        }
        caches        = $caches
        cacheSeconds  = (Get-CmdPeekInventoryCacheSeconds -DataDirectory $dir)
        history       = @($history.ToArray())
        profileHint   = [pscustomobject]@{
            path    = $profilePath
            present = $profileHint
        }
        timings       = $timings
        problems      = @($problems.ToArray())
    }
}

function Measure-CmdPeekScanStage {
    [CmdletBinding()]
    param(
        [string]$DataDirectory,
        [string]$ExamplesPath,
        [scriptblock]$CommandTester
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $managerArgs = @{}
    if ($CommandTester) { $managerArgs.CommandTester = $CommandTester }
    $names = @(@(Get-CmdPeekPackageManager @managerArgs) | Select-Object -ExpandProperty Name)

    $catalogArgs = @{ DataDirectory = $DataDirectory }
    if ($ExamplesPath) { $catalogArgs.Path = $ExamplesPath }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $catalog = Get-CmdPeekExampleCatalog @catalogArgs
    $rows.Add([pscustomobject]@{ stage = 'catalog'; milliseconds = [int]$sw.ElapsedMilliseconds; rows = @($catalog.Keys).Count })

    $pkgArgs = @{ EnabledManagers = $names }
    if ($CommandTester) { $pkgArgs.CommandTester = $CommandTester }
    $sw.Restart()
    $packages = @(Get-CmdPeekInstalledPackage @pkgArgs)
    $rows.Add([pscustomobject]@{ stage = 'package managers'; milliseconds = [int]$sw.ElapsedMilliseconds; rows = $packages.Count })

    $sw.Restart()
    $history = @(Get-CmdPeekCommandHistory -Package $packages)
    $rows.Add([pscustomobject]@{ stage = 'history'; milliseconds = [int]$sw.ElapsedMilliseconds; rows = $history.Count })

    $pathArgs = @{
        History                  = $history
        Catalog                  = $catalog
        DataDirectory            = $DataDirectory
        IncludeSystemDirectories = $true
    }
    if ($CommandTester) { $pathArgs.CommandTester = $CommandTester }
    $sw.Restart()
    $history = @(Add-CmdPeekPathCommands @pathArgs)
    $rows.Add([pscustomobject]@{ stage = 'PATH scan'; milliseconds = [int]$sw.ElapsedMilliseconds; rows = $history.Count })

    $sw.Restart()
    $gaps = @(Get-CmdPeekGap -History $history -Catalog $catalog -Kits (Get-CmdPeekCatalogKits @catalogArgs))
    $rows.Add([pscustomobject]@{ stage = 'gap analysis'; milliseconds = [int]$sw.ElapsedMilliseconds; rows = $gaps.Count })
    $sw.Stop()

    return @($rows.ToArray())
}

function Format-CmdPeekDoctorReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Report
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $v = $Report.version
    $mcp = $v.mcp
    if (-not $mcp) { $mcp = 'not found' }
    $lines.Add("cmdpeek $($v.module)  (mcp $mcp, PowerShell $($v.powerShell), $($v.os))")
    if (-not $v.inSync) { $lines.Add('  ! module and MCP versions disagree') }
    $lines.Add('')

    $dd = $Report.dataDirectory
    $writable = 'writable'
    if (-not $dd.writable) { $writable = 'NOT WRITABLE' }
    $lines.Add("Data directory  $($dd.path)  [$writable]")
    $lines.Add("Inventory cache $($Report.cacheSeconds)s TTL")
    foreach ($cache in @($Report.caches)) {
        $state = 'absent'
        if ($cache.exists) {
            $state = '{0:N0} KB, {1}s old' -f ($cache.sizeBytes / 1KB), $cache.ageSeconds
        }
        $lines.Add(('  {0,-14} {1}' -f $cache.name, $state))
    }
    $lines.Add('')

    $present = @($Report.managers.present)
    $missing = @($Report.managers.missing)
    $lines.Add("Package managers")
    if ($present.Count -gt 0) { $lines.Add("  present  $($present -join ', ')") }
    else { $lines.Add('  present  none') }
    if ($missing.Count -gt 0) { $lines.Add("  missing  $($missing -join ', ')") }
    $lines.Add('')

    $c = $Report.catalog
    $lines.Add("Catalog  $($c.commands) commands, $($c.builtins) builtin, $($c.kits) kits, $($c.learnedEntries) learned")
    if ($c.loadError) { $lines.Add("  ! $($c.loadError)") }
    foreach ($err in @($c.errors | Select-Object -First 10)) { $lines.Add("  ! $err") }
    if (@($c.errors).Count -gt 10) { $lines.Add("  ... and $((@($c.errors).Count) - 10) more") }
    $lines.Add('')

    $lines.Add('Shell history')
    if (@($Report.history).Count -eq 0) { $lines.Add('  none found') }
    foreach ($h in @($Report.history)) {
        if ($h.readable) { $lines.Add("  $($h.lines) lines  $($h.path)") }
        else { $lines.Add("  unreadable   $($h.path)") }
    }
    $hint = 'not installed'
    if ($Report.profileHint.present) { $hint = 'installed' }
    $lines.Add("Profile hint    $hint  ($($Report.profileHint.path))")

    if (@($Report.timings).Count -gt 0) {
        $lines.Add('')
        $lines.Add('Scan timings')
        foreach ($t in @($Report.timings)) {
            $lines.Add(('  {0,-18} {1,7} ms  {2} rows' -f $t.stage, $t.milliseconds, $t.rows))
        }
    }

    $lines.Add('')
    $problems = @($Report.problems)
    if ($problems.Count -eq 0) { $lines.Add('No problems found.') }
    else {
        $lines.Add("$($problems.Count) problem(s):")
        foreach ($p in $problems) { $lines.Add("  - $p") }
    }

    return ($lines -join [Environment]::NewLine)
}
