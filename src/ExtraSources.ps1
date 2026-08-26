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
