#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CmdPeekDefaultLanguageRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('pipx', 'npm', 'cargo', 'brew')]
        [string]$Manager
    )

    switch ($Manager) {
        'pipx' {
            if ($env:PIPX_HOME) { return (Join-Path $env:PIPX_HOME 'venvs') }
            $homeLocal = Join-Path $HOME '.local'
            return (Join-Path $homeLocal 'pipx\venvs')
        }
        'npm' {
            if ($env:NPM_PREFIX) { return $env:NPM_PREFIX }
            if ($env:APPDATA) { return (Join-Path $env:APPDATA 'npm') }
            return (Join-Path $HOME '.npm-global')
        }
        'cargo' {
            if ($env:CARGO_HOME) { return (Join-Path $env:CARGO_HOME 'bin') }
            return (Join-Path (Join-Path $HOME '.cargo') 'bin')
        }
        'brew' {
            foreach ($prefix in @('/opt/homebrew', '/usr/local', '/home/linuxbrew/.linuxbrew')) {
                $cellar = Join-Path $prefix 'Cellar'
                if (Test-Path -LiteralPath $cellar) { return $cellar }
            }
            return '/opt/homebrew/Cellar'
        }
    }
}

function Get-CmdPeekPipxPackage {
    [CmdletBinding()]
    param(
        [string]$PipxRoot
    )

    if (-not $PipxRoot) { $PipxRoot = Get-CmdPeekDefaultLanguageRoot -Manager pipx }
    if (-not (Test-Path -LiteralPath $PipxRoot)) { return @() }

    $packages = foreach ($venv in Get-ChildItem -LiteralPath $PipxRoot -Directory -ErrorAction SilentlyContinue) {
        $binDirs = @(
            (Join-Path $venv.FullName 'Scripts')
            (Join-Path $venv.FullName 'bin')
        )
        $commands = New-Object System.Collections.Generic.List[string]
        foreach ($bin in $binDirs) {
            if (-not (Test-Path -LiteralPath $bin)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $bin -File -ErrorAction SilentlyContinue)) {
                if ($file.Extension -match '\.(exe|cmd|bat|ps1)$' -or [string]::IsNullOrWhiteSpace($file.Extension)) {
                    $stem = Get-CmdPeekCommandStem -FileName $file.Name
                    if ($stem -and $stem -notmatch '^(python|pip|activate)$' -and $commands -notcontains $stem) {
                        $commands.Add($stem)
                    }
                }
            }
        }
        if ($commands.Count -eq 0) { continue }
        [pscustomobject]@{
            Name           = $venv.Name
            Version        = $null
            PackageManager = 'pipx'
            InstallDate    = $venv.LastWriteTime
            Commands       = @($commands)
            Path           = $venv.FullName
        }
    }
    return @($packages)
}

function Get-CmdPeekNpmPackage {
    [CmdletBinding()]
    param(
        [string]$NpmRoot
    )

    if (-not $NpmRoot) { $NpmRoot = Get-CmdPeekDefaultLanguageRoot -Manager npm }
    if (-not (Test-Path -LiteralPath $NpmRoot)) { return @() }

    $files = @(Get-ChildItem -LiteralPath $NpmRoot -File -ErrorAction SilentlyContinue)
    $stems = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) {
        if ($file.Extension -match '\.(exe|cmd|bat|ps1)$' -or [string]::IsNullOrWhiteSpace($file.Extension)) {
            $stem = Get-CmdPeekCommandStem -FileName $file.Name
            if ($stem -and $stems -notcontains $stem) { $stems.Add($stem) }
        }
    }
    $packages = foreach ($stem in $stems) {
        $match = @($files | Where-Object { (Get-CmdPeekCommandStem -FileName $_.Name) -eq $stem } | Select-Object -First 1)
        $when = Get-Date
        if ($match.Count -gt 0) { $when = $match[0].LastWriteTime }
        [pscustomobject]@{
            Name           = $stem
            Version        = $null
            PackageManager = 'npm'
            InstallDate    = $when
            Commands       = @($stem)
            Path           = $NpmRoot
        }
    }
    return @($packages)
}

function Get-CmdPeekCargoPackage {
    [CmdletBinding()]
    param(
        [string]$CargoRoot
    )

    if (-not $CargoRoot) { $CargoRoot = Get-CmdPeekDefaultLanguageRoot -Manager cargo }
    if (-not (Test-Path -LiteralPath $CargoRoot)) { return @() }

    $packages = foreach ($file in @(Get-ChildItem -LiteralPath $CargoRoot -File -ErrorAction SilentlyContinue)) {
        if ($file.Extension -match '\.(exe|pdb)$' -and $file.Extension -eq '.pdb') { continue }
        $ok = $false
        if ($file.Extension -match '\.(exe|cmd|bat)$') { $ok = $true }
        elseif ([string]::IsNullOrWhiteSpace($file.Extension)) { $ok = $true }
        if (-not $ok) { continue }
        $stem = Get-CmdPeekCommandStem -FileName $file.Name
        if (-not $stem) { continue }
        [pscustomobject]@{
            Name           = $stem
            Version        = $null
            PackageManager = 'cargo'
            InstallDate    = $file.LastWriteTime
            Commands       = @($stem)
            Path           = $file.FullName
        }
    }
    return @($packages)
}

function Get-CmdPeekBrewPackage {
    [CmdletBinding()]
    param(
        [string]$BrewRoot
    )

    if (-not $BrewRoot) { $BrewRoot = Get-CmdPeekDefaultLanguageRoot -Manager brew }
    if (-not (Test-Path -LiteralPath $BrewRoot)) { return @() }

    $packages = foreach ($formula in Get-ChildItem -LiteralPath $BrewRoot -Directory -ErrorAction SilentlyContinue) {
        $versions = @(Get-ChildItem -LiteralPath $formula.FullName -Directory -ErrorAction SilentlyContinue)
        if ($versions.Count -eq 0) { continue }
        $current = $versions | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $bin = Join-Path $current.FullName 'bin'
        $commands = New-Object System.Collections.Generic.List[string]
        if (Test-Path -LiteralPath $bin) {
            foreach ($file in @(Get-ChildItem -LiteralPath $bin -File -ErrorAction SilentlyContinue)) {
                $stem = Get-CmdPeekCommandStem -FileName $file.Name
                if ($stem -and $commands -notcontains $stem) { $commands.Add($stem) }
            }
        }
        if ($commands.Count -eq 0) { $commands.Add($formula.Name) }
        [pscustomobject]@{
            Name           = $formula.Name
            Version        = $current.Name
            PackageManager = 'brew'
            InstallDate    = $formula.LastWriteTime
            Commands       = @($commands)
            Path           = $current.FullName
        }
    }
    return @($packages)
}

function Add-CmdPeekPathCommands {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$History,
        [hashtable]$Catalog,
        [scriptblock]$CommandTester
    )

    if (-not $Catalog) { return @($History) }
    $existing = @{}
    foreach ($row in @($History)) {
        if ($row -and $row.Command) {
            foreach ($name in @(Get-CmdPeekCommandNamesFor -Command $row.Command -Catalog $Catalog)) {
                $existing[$name.ToLowerInvariant()] = $true
            }
        }
    }

    if (-not $CommandTester) {
        $CommandTester = {
            param($Name)
            return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
        }
    }

    $extra = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($Catalog.Keys)) {
        $names = @(Get-CmdPeekCommandNamesFor -Command $key -Catalog $Catalog)
        $foundName = $null
        foreach ($name in $names) {
            if ($existing.ContainsKey($name.ToLowerInvariant())) { $foundName = $null; break }
            $visible = $false
            try { $visible = [bool](& $CommandTester $name) } catch { $visible = $false }
            if ($visible) { $foundName = $name; break }
        }
        if (-not $foundName) { continue }
        $existing[$foundName.ToLowerInvariant()] = $true
        $existing[$key.ToLowerInvariant()] = $true
        $extra.Add([pscustomobject]@{
            Command        = $foundName
            PackageName    = $key
            PackageManager = 'path'
            InstallDate    = [datetime]'2000-01-01'
            Version        = $null
            Favorite       = $false
            Hidden         = $false
            Category       = Get-CmdPeekCommandCategory -Command $key -Catalog $Catalog
        })
    }

    return @(@($History) + @($extra.ToArray()))
}

function Get-CmdPeekDefaultUnixRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('apt', 'pacman')]
        [string]$Manager
    )

    switch ($Manager) {
        'apt' { return '/var/lib/dpkg/status' }
        'pacman' { return '/var/lib/pacman/local' }
    }
}

function Get-CmdPeekAptPackage {
    [CmdletBinding()]
    param(
        [string]$StatusPath
    )

    if (-not $StatusPath) { $StatusPath = Get-CmdPeekDefaultUnixRoot -Manager apt }
    if (-not (Test-Path -LiteralPath $StatusPath)) { return @() }

    $raw = Get-Content -LiteralPath $StatusPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

    $packages = New-Object System.Collections.Generic.List[object]
    $blocks = @($raw -split '(?m)(?=^Package: )')
    foreach ($block in $blocks) {
        if ([string]::IsNullOrWhiteSpace($block)) { continue }
        $name = $null
        $status = $null
        $version = $null
        $provides = New-Object System.Collections.Generic.List[string]
        foreach ($line in @($block -split '\r?\n')) {
            if ($line -match '^Package:\s*(.+)$') { $name = $Matches[1].Trim() }
            elseif ($line -match '^Status:\s*(.+)$') { $status = $Matches[1].Trim() }
            elseif ($line -match '^Version:\s*(.+)$') { $version = $Matches[1].Trim() }
            elseif ($line -match '^Provides:\s*(.+)$') {
                foreach ($p in @($Matches[1] -split ',')) {
                    $stem = $p.Trim()
                    if ($stem) { $provides.Add($stem) }
                }
            }
        }
        if (-not $name) { continue }
        if (-not $status -or $status -notmatch 'install ok installed') { continue }
        $commands = New-Object System.Collections.Generic.List[string]
        $commands.Add($name)
        foreach ($p in $provides) {
            if ($p -and $commands -notcontains $p) { $commands.Add($p) }
        }
        $packages.Add([pscustomobject]@{
            Name           = $name
            Version        = $version
            PackageManager = 'apt'
            InstallDate    = $null
            Commands       = @($commands)
            Path           = $StatusPath
        })
    }
    return @($packages.ToArray())
}

function Get-CmdPeekPacmanPackage {
    [CmdletBinding()]
    param(
        [string]$LocalRoot
    )

    if (-not $LocalRoot) { $LocalRoot = Get-CmdPeekDefaultUnixRoot -Manager pacman }
    if (-not (Test-Path -LiteralPath $LocalRoot)) { return @() }

    $packages = foreach ($dir in Get-ChildItem -LiteralPath $LocalRoot -Directory -ErrorAction SilentlyContinue) {
        $desc = Join-Path $dir.FullName 'desc'
        if (-not (Test-Path -LiteralPath $desc)) { continue }
        $text = Get-Content -LiteralPath $desc -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $name = $null
        $version = $null
        $buildDate = $null
        $commands = New-Object System.Collections.Generic.List[string]
        $section = ''
        foreach ($line in @($text -split '\r?\n')) {
            $trim = $line.Trim()
            if ($trim -match '^%([A-Z]+)%$') {
                $section = $Matches[1]
                continue
            }
            if (-not $trim) { continue }
            switch ($section) {
                'NAME' { if (-not $name) { $name = $trim } }
                'VERSION' { if (-not $version) { $version = $trim } }
                'BUILDDATE' {
                    if (-not $buildDate) {
                        $unix = [int64]0
                        if ([int64]::TryParse($trim, [ref]$unix) -and $unix -gt 0) {
                            $epoch = [datetime]::SpecifyKind([datetime]'1970-01-01', 'Utc')
                            $buildDate = $epoch.AddSeconds([double]$unix)
                        }
                    }
                }
                'FILES' {
                    if ($trim -match '(^|/)bin/([^/]+)$') {
                        $stem = Get-CmdPeekCommandStem -FileName $Matches[2]
                        if ($stem -and $commands -notcontains $stem) { $commands.Add($stem) }
                    }
                }
            }
        }
        if (-not $name) { continue }
        if ($commands.Count -eq 0) { $commands.Add($name) }
        [pscustomobject]@{
            Name           = $name
            Version        = $version
            PackageManager = 'pacman'
            InstallDate    = $buildDate
            Commands       = @($commands)
            Path           = $dir.FullName
        }
    }
    return @($packages)
}

function Get-CmdPeekWinGetReleaseInfo {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if (-not $Path) {
        $root = Split-Path -Parent $PSScriptRoot
        $Path = Join-Path $root (Join-Path 'examples\mocks' 'winget-release.json')
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    try {
        $info = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
    $dir = Split-Path -Parent $Path
    $payloadName = 'winget-portable-payload.txt'
    if ($info.PSObject.Properties['payloadFile'] -and $info.payloadFile) {
        $payloadName = [string]$info.payloadFile
    }
    $payload = Join-Path $dir $payloadName
    $hash = $null
    if (Test-Path -LiteralPath $payload) {
        $hash = (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
    }
    $expected = ''
    if ($info.PSObject.Properties['installerSha256'] -and $info.installerSha256) {
        $expected = ([string]$info.installerSha256).ToUpperInvariant()
    }
    return [pscustomobject]@{
        PackageIdentifier = $(if ($info.PSObject.Properties['packageIdentifier']) { [string]$info.packageIdentifier } else { '' })
        PackageVersion    = $(if ($info.PSObject.Properties['packageVersion']) { [string]$info.packageVersion } else { '' })
        InstallerUrl      = $(if ($info.PSObject.Properties['installerUrl']) { [string]$info.installerUrl } else { '' })
        InstallerSha256   = $expected
        PayloadPath       = $payload
        PayloadSha256     = $(if ($hash) { $hash.ToUpperInvariant() } else { $null })
        MatchesPayload    = $(if ($hash -and $expected) { $hash.ToUpperInvariant() -eq $expected } else { $false })
    }
}
