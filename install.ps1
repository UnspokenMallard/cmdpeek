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
    $tmp = Join-Path $env:TEMP ('cmdpeek-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'cmdpeek.zip'
    $url = 'https://github.com/cmdpeek/cmdpeek/archive/refs/heads/main.zip'
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

$entry = Join-Path $moduleDest 'cmdpeek.ps1'
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

$ps7Modules = Join-Path $HOME 'Documents\PowerShell\Modules\cmdpeek'
$ps5Modules = Join-Path $HOME 'Documents\WindowsPowerShell\Modules\cmdpeek'
foreach ($modPath in @($ps7Modules, $ps5Modules)) {
    $parent = Split-Path -Parent $modPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $modPath) {
        Remove-Item -LiteralPath $modPath -Recurse -Force
    }
    New-Item -ItemType Junction -Path $modPath -Target $moduleDest -ErrorAction SilentlyContinue | Out-Null
    if (-not (Test-Path -LiteralPath $modPath)) {
        New-Item -ItemType Directory -Path $modPath -Force | Out-Null
        Copy-Item -Path (Join-Path $moduleDest '*') -Destination $modPath -Recurse -Force
    }
}

if (-not $SkipPath) {
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
