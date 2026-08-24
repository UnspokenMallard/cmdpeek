#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-CmdPeekPackageManagerInstallHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('chocolatey', 'scoop', 'winget')]
        [string]$Name
    )

    switch ($Name) {
        'chocolatey' {
            return 'Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString(''https://community.chocolatey.org/install.ps1''))'
        }
        'scoop' {
            return 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser; Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression'
        }
        'winget' {
            return 'Install "App Installer" from the Microsoft Store to get winget, or run: Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
        }
    }
}

function Get-CmdPeekDefaultInstallRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('chocolatey', 'scoop', 'winget')]
        [string]$Manager
    )

    switch ($Manager) {
        'chocolatey' {
            if ($env:ChocolateyInstall) { return $env:ChocolateyInstall }
            return 'C:\ProgramData\chocolatey'
        }
        'scoop' {
            if ($env:SCOOP) { return $env:SCOOP }
            return (Join-Path $HOME 'scoop')
        }
        'winget' {
            return (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages')
        }
    }
}

function Get-CmdPeekPackageManager {
    [CmdletBinding()]
    param(
        [scriptblock]$CommandTester,
        [switch]$All
    )

    if (-not $CommandTester) {
        $CommandTester = {
            param($Name)
            return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
        }
    }

    $known = @(
        [pscustomobject]@{ Name = 'chocolatey'; Command = 'choco';  InstallHint = (Get-CmdPeekPackageManagerInstallHint -Name chocolatey) }
        [pscustomobject]@{ Name = 'scoop';      Command = 'scoop';  InstallHint = (Get-CmdPeekPackageManagerInstallHint -Name scoop) }
        [pscustomobject]@{ Name = 'winget';     Command = 'winget'; InstallHint = (Get-CmdPeekPackageManagerInstallHint -Name winget) }
    )

    $result = foreach ($pm in $known) {
        $present = $false
        try {
            $present = [bool](& $CommandTester $pm.Command)
        }
        catch {
            $present = $false
        }

        $row = [pscustomobject]@{
            Name         = $pm.Name
            Command      = $pm.Command
            Present      = $present
            InstallHint  = $pm.InstallHint
        }

        if ($All -or $present) {
            $row
        }
    }

    return @($result)
}

function Get-CmdPeekCommandStem {
    param([string]$FileName)
    if ([string]::IsNullOrWhiteSpace($FileName)) { return $null }
    return [System.IO.Path]::GetFileNameWithoutExtension($FileName)
}

function ConvertFrom-CmdPeekScoopBin {
    param($Bin)

    $names = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Bin) { return @() }

    foreach ($entry in @($Bin)) {
        if ($null -eq $entry) { continue }
        if ($entry -is [string]) {
            $stem = Get-CmdPeekCommandStem -FileName $entry
            if ($stem) { $names.Add($stem) }
            continue
        }

        foreach ($part in @($entry)) {
            if ($part -is [string]) {
                $stem = Get-CmdPeekCommandStem -FileName $part
                if ($stem) { $names.Add($stem) }
            }
        }
    }

    return @($names | Select-Object -Unique)
}

function Get-CmdPeekScoopPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScoopRoot
    )

    $appsRoot = Join-Path $ScoopRoot 'apps'
    if (-not (Test-Path -LiteralPath $appsRoot)) { return @() }

    $packages = foreach ($appDir in Get-ChildItem -LiteralPath $appsRoot -Directory -ErrorAction SilentlyContinue) {
        if ($appDir.Name -eq 'scoop') { continue }

        $current = Join-Path $appDir.FullName 'current'
        if (-not (Test-Path -LiteralPath $current)) {
            $versions = @(Get-ChildItem -LiteralPath $appDir.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'current' })
            if ($versions.Count -eq 0) { continue }
            $current = ($versions | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
        }

        $version = $null
        $commands = @()
        $manifestPath = Join-Path $current 'manifest.json'
        if (Test-Path -LiteralPath $manifestPath) {
            try {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($manifest.PSObject.Properties['version']) { $version = [string]$manifest.version }
                if ($manifest.PSObject.Properties['bin']) { $commands = @(ConvertFrom-CmdPeekScoopBin -Bin $manifest.bin) }
            }
            catch {
                $commands = @()
            }
        }

        if ($commands.Count -eq 0) {
            $exe = Get-ChildItem -LiteralPath $current -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '\.(exe|cmd|bat|ps1)$' -and $_.BaseName -notmatch 'uninstall|setup' }
            $commands = @($exe | ForEach-Object { $_.BaseName } | Select-Object -Unique)
        }

        if ($commands.Count -eq 0) { continue }

        [pscustomobject]@{
            Name           = $appDir.Name
            Version        = $version
            PackageManager = 'scoop'
            InstallDate    = $appDir.LastWriteTime
            Commands       = @($commands)
            Path           = $current
        }
    }

    return @($packages)
}

function Get-CmdPeekNuspecVersion {
    param([string]$NuspecPath)
    if (-not (Test-Path -LiteralPath $NuspecPath)) { return $null }
    $raw = Get-Content -LiteralPath $NuspecPath -Raw -Encoding UTF8
    $match = [regex]::Match($raw, '<version>\s*([^<]+?)\s*</version>', 'IgnoreCase')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Get-CmdPeekChocolateyPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChocolateyRoot
    )

    $libRoot = Join-Path $ChocolateyRoot 'lib'
    $binRoot = Join-Path $ChocolateyRoot 'bin'
    if (-not (Test-Path -LiteralPath $libRoot)) { return @() }

    $shims = @()
    if (Test-Path -LiteralPath $binRoot) {
        $shims = @(
            Get-ChildItem -LiteralPath $binRoot -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '\.(exe|cmd|bat|ps1)$' -and $_.BaseName -notmatch '^(choco|chocolatey|RefreshEnv)$' }
        )
    }

    $packages = foreach ($pkgDir in Get-ChildItem -LiteralPath $libRoot -Directory -ErrorAction SilentlyContinue) {
        $id = $pkgDir.Name
        $bare = $id -replace '\.(install|portable|commandline)$', ''
        $candidates = @($id, $bare) | Select-Object -Unique

        $matched = @(
            $shims | Where-Object {
                $stem = $_.BaseName
                $candidates -contains $stem
            }
        )

        $commands = @($matched | ForEach-Object { $_.BaseName } | Select-Object -Unique)
        if ($commands.Count -eq 0) { continue }

        $nuspec = Get-ChildItem -LiteralPath $pkgDir.FullName -Filter '*.nuspec' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $version = $null
        if ($nuspec) { $version = Get-CmdPeekNuspecVersion -NuspecPath $nuspec.FullName }

        [pscustomobject]@{
            Name           = $bare
            Version        = $version
            PackageManager = 'chocolatey'
            InstallDate    = $pkgDir.LastWriteTime
            Commands       = @($commands)
            Path           = $pkgDir.FullName
        }
    }

    return @($packages)
}

function Get-CmdPeekWinGetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WinGetRoot,
        [scriptblock]$CommandTester
    )

    if (-not (Test-Path -LiteralPath $WinGetRoot)) { return @() }

    $tester = $CommandTester
    if (-not $tester) {
        $tester = {
            param($Name)
            return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
        }
    }

    $packages = foreach ($pkgDir in Get-ChildItem -LiteralPath $WinGetRoot -Directory -ErrorAction SilentlyContinue) {
        $id = ($pkgDir.Name -split '_')[0]
        if ([string]::IsNullOrWhiteSpace($id)) { continue }

        $exe = @(
            Get-ChildItem -LiteralPath $pkgDir.FullName -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Extension -eq '.exe' -and
                    $_.BaseName -notmatch 'uninstall|setup|installer|crashpad|update'
                }
        )

        $commands = New-Object System.Collections.Generic.List[string]
        foreach ($file in $exe) {
            $name = $file.BaseName
            if (Get-Command Get-CmdPeekPeSubsystem -ErrorAction SilentlyContinue) {
                $subsystem = Get-CmdPeekPeSubsystem -Path $file.FullName
                if ($subsystem -eq 2) { continue }
            }
            $visible = $false
            try { $visible = [bool](& $tester $name) } catch { $visible = $false }
            if (-not $visible) { continue }
            if ($commands -notcontains $name) { [void]$commands.Add($name) }
        }
        if ($commands.Count -eq 0) { continue }

        [pscustomobject]@{
            Name           = $id
            Version        = $null
            PackageManager = 'winget'
            InstallDate    = $pkgDir.LastWriteTime
            Commands       = @($commands)
            Path           = $pkgDir.FullName
        }
    }

    return @($packages)
}

function Get-CmdPeekInstalledPackage {
    [CmdletBinding()]
    param(
        [string]$ChocolateyRoot,
        [string]$ScoopRoot,
        [string]$WinGetRoot,
        [string[]]$EnabledManagers,
        [scriptblock]$CommandTester
    )

    if (-not $EnabledManagers -or $EnabledManagers.Count -eq 0) {
        $EnabledManagers = @(Get-CmdPeekPackageManager -CommandTester $CommandTester | Select-Object -ExpandProperty Name)
    }

    if (-not $ChocolateyRoot) { $ChocolateyRoot = Get-CmdPeekDefaultInstallRoot -Manager chocolatey }
    if (-not $ScoopRoot) { $ScoopRoot = Get-CmdPeekDefaultInstallRoot -Manager scoop }
    if (-not $WinGetRoot) { $WinGetRoot = Get-CmdPeekDefaultInstallRoot -Manager winget }

    $packages = New-Object System.Collections.Generic.List[object]

    foreach ($manager in $EnabledManagers) {
        switch ($manager) {
            'scoop' {
                foreach ($pkg in @(Get-CmdPeekScoopPackage -ScoopRoot $ScoopRoot)) { $packages.Add($pkg) }
            }
            'chocolatey' {
                foreach ($pkg in @(Get-CmdPeekChocolateyPackage -ChocolateyRoot $ChocolateyRoot)) { $packages.Add($pkg) }
            }
            'winget' {
                foreach ($pkg in @(Get-CmdPeekWinGetPackage -WinGetRoot $WinGetRoot -CommandTester $CommandTester)) { $packages.Add($pkg) }
            }
        }
    }

    return @($packages.ToArray())
}
