#Requires -Version 5.1
<#
.SYNOPSIS
    Install cmdpeek for the current user (PowerShell 5.1 and PowerShell 7).
.EXAMPLE
    irm https://raw.githubusercontent.com/cmdpeek/cmdpeek/main/install.ps1 | iex
.EXAMPLE
    .\install.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallDir,
    [switch]$AddToPath,
    [switch]$SkipPath,
    [switch]$AddProfileHint,
    [string]$ProfilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $IsWindows does not exist in Windows PowerShell 5.1, so ask the runtime directly.
$onWindows = ($env:OS -eq 'Windows_NT') -or ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)

if (-not $InstallDir) {
    $localApp = $env:LOCALAPPDATA
    if (-not $localApp) {
        if ($env:XDG_DATA_HOME) { $localApp = $env:XDG_DATA_HOME }
        elseif ($HOME) { $localApp = Join-Path $HOME '.local/share' }
        else { $localApp = [System.IO.Path]::GetTempPath() }
    }
    $InstallDir = Join-Path $localApp 'cmdpeek'
}

$repoRoot = $PSScriptRoot
if (-not $repoRoot) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('cmdpeek-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'cmdpeek.zip'
    $url = 'https://github.com/UnspokenMallard/cmdpeek/archive/refs/heads/main.zip'
    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $repoRoot = Get-ChildItem -LiteralPath $tmp -Directory | Where-Object { $_.Name -like 'cmdpeek-*' } | Select-Object -First 1 -ExpandProperty FullName
}

$src = Join-Path $repoRoot 'src'
$examples = Join-Path $repoRoot 'examples'
if (-not (Test-Path -LiteralPath (Join-Path $src 'cmdpeek.psd1'))) {
    throw "Cannot find cmdpeek sources next to install.ps1 (expected $src)."
}

$moduleDest = Join-Path $InstallDir 'module'
$binDest = Join-Path $InstallDir 'bin'
New-Item -ItemType Directory -Force -Path $moduleDest, $binDest | Out-Null

Copy-Item -Path (Join-Path $src '*') -Destination $moduleDest -Force
if (Test-Path -LiteralPath $examples) {
    $exampleDest = Join-Path $moduleDest 'examples'
    New-Item -ItemType Directory -Force -Path $exampleDest | Out-Null
    Copy-Item -Path (Join-Path $examples '*') -Destination $exampleDest -Force
}

# The MCP server runs from a checkout (see README), so only its manifest is
# installed: without it cmdpeek doctor reads no MCP version and the module/MCP
# drift check silently passes.
$mcpPackageJson = Join-Path $repoRoot 'mcp/package.json'
if (Test-Path -LiteralPath $mcpPackageJson) {
    $mcpDest = Join-Path $InstallDir 'mcp'
    New-Item -ItemType Directory -Force -Path $mcpDest | Out-Null
    Copy-Item -Path $mcpPackageJson -Destination $mcpDest -Force
}

if ($onWindows) {
    $shim = Join-Path $binDest 'cmdpeek.cmd'
    @(
        '@echo off'
        'setlocal'
        'set "SCRIPT=%~dp0..\module\cmdpeek.ps1"'
        'where pwsh >nul 2>&1 && ('
        '  pwsh -NoProfile -File "%SCRIPT%" %*'
        '  exit /b %ERRORLEVEL%'
        ')'
        'powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*'
    ) | Set-Content -LiteralPath $shim -Encoding ASCII
}
else {
    # macOS and Linux have no cmdpeek.cmd. A POSIX shim runs pwsh on the installed script.
    $shim = Join-Path $binDest 'cmdpeek'
    $script = Join-Path $moduleDest 'cmdpeek.ps1'
    $quotedScript = "'" + ($script -replace "'", "'\''") + "'"
    @(
        '#!/bin/sh'
        'command -v pwsh >/dev/null 2>&1 || { echo "cmdpeek needs PowerShell 7 (pwsh) on PATH: brew install powershell" >&2; exit 1; }'
        "exec pwsh -NoProfile -File $quotedScript `"`$@`""
    ) | Set-Content -LiteralPath $shim -Encoding ASCII
    & chmod +x $shim
}

if ($onWindows) {
    $ps7Modules = Join-Path $HOME 'Documents\PowerShell\Modules\cmdpeek'
    $ps5Modules = Join-Path $HOME 'Documents\WindowsPowerShell\Modules\cmdpeek'
    $moduleLocations = @($ps7Modules, $ps5Modules)
}
else {
    # pwsh on macOS and Linux finds user modules under ~/.local/share/powershell/Modules.
    $moduleLocations = @(Join-Path $HOME '.local/share/powershell/Modules/cmdpeek')
}
foreach ($modPath in $moduleLocations) {
    $parent = Split-Path -Parent $modPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $existing = Get-Item -LiteralPath $modPath -Force -ErrorAction SilentlyContinue
    if ($existing) {
        # A link is removed alone. Recursing through it could delete the module's source.
        if ($existing.LinkType) { Remove-Item -LiteralPath $modPath -Force }
        else { Remove-Item -LiteralPath $modPath -Recurse -Force }
    }
    if ($onWindows) {
        New-Item -ItemType Junction -Path $modPath -Target $moduleDest -ErrorAction SilentlyContinue | Out-Null
    }
    else {
        New-Item -ItemType SymbolicLink -Path $modPath -Target $moduleDest -ErrorAction SilentlyContinue | Out-Null
    }
    if (-not (Test-Path -LiteralPath $modPath)) {
        New-Item -ItemType Directory -Path $modPath -Force | Out-Null
        Copy-Item -Path (Join-Path $moduleDest '*') -Destination $modPath -Recurse -Force
    }
}

# The user PATH is updated by default. -AddToPath is accepted so the intent can be
# stated explicitly, and it wins if both switches are somehow passed.
if ($AddToPath -or -not $SkipPath) {
    if ($onWindows) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not $userPath) { $userPath = '' }
        $parts = @($userPath -split ';' | Where-Object { $_ })
        if ($parts -notcontains $binDest) {
            $newPath = ($parts + $binDest) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            $env:Path = $binDest + ';' + $env:Path
            Write-Host "Added $binDest to your user PATH. Open a new terminal to use cmdpeek."
        }
    }
    else {
        # Windows keeps PATH in the registry. macOS and Linux read it from a shell
        # startup file, so add one marked line to ~/.zprofile (the macOS login shell).
        $zprofile = Join-Path $HOME '.zprofile'
        $pathLine = 'export PATH="' + $binDest + ':$PATH"'
        $existingProfile = ''
        if (Test-Path -LiteralPath $zprofile) { $existingProfile = Get-Content -LiteralPath $zprofile -Raw }
        if ($existingProfile -notlike "*$pathLine*") {
            Add-Content -LiteralPath $zprofile -Value @('', '# cmdpeek', $pathLine)
            Write-Host "Added $binDest to PATH in $zprofile. Open a new terminal to use cmdpeek."
        }
        if (($env:PATH -split ':') -notcontains $binDest) { $env:PATH = $binDest + ':' + $env:PATH }
    }
}

Write-Host ''
Write-Host "cmdpeek installed to $InstallDir" -ForegroundColor Green
Write-Host 'Try:  cmdpeek 5'
Write-Host '      cmdpeek -i'

if ($AddProfileHint) {
    . (Join-Path $moduleDest 'Config.ps1')
    $target = $ProfilePath
    if (-not $target) { $target = $PROFILE }
    Add-CmdPeekProfileHint -ProfilePath $target
    Write-Host "Added scoop/choco install hint to $target"
}
else {
    Write-Host 'Optional:  .\install.ps1 -AddProfileHint   (print cmdpeek -n 1 after scoop/choco install)'
}
