#Requires -Version 5.1
<#
.SYNOPSIS
    Build a portable cmdpeek zip and print its SHA256 for WinGet.
.EXAMPLE
    .\scripts\New-CmdPeekReleaseArchive.ps1 -OutputDirectory .\dist
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$OutputDirectory,
    [string]$Version,
    [switch]$UpdateManifest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
$manifestPath = Join-Path (Join-Path $RepoRoot 'src') 'cmdpeek.psd1'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Repo root '$RepoRoot' does not contain src/cmdpeek.psd1"
}

if (-not $Version) {
    $psd1 = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    if ($psd1 -match "ModuleVersion\s*=\s*'([^']+)'") {
        $Version = $Matches[1]
    }
    else {
        $Version = '0.0.0'
    }
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $RepoRoot 'dist'
}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$stage = Join-Path $OutputDirectory ('cmdpeek-stage-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
    Copy-Item -Path (Join-Path $RepoRoot 'src') -Destination (Join-Path $stage 'src') -Recurse -Force
    $examplesSrc = Join-Path $RepoRoot 'examples'
    if (Test-Path -LiteralPath $examplesSrc) {
        Copy-Item -Path $examplesSrc -Destination (Join-Path $stage 'examples') -Recurse -Force
    }
    foreach ($name in @('install.ps1', 'LICENSE', 'README.md', 'cmdpeek.cmd')) {
        $item = Join-Path $RepoRoot $name
        if (Test-Path -LiteralPath $item) {
            Copy-Item -LiteralPath $item -Destination (Join-Path $stage $name) -Force
        }
    }

    $zipName = 'cmdpeek-win-x64-v' + $Version + '.zip'
    $zipPath = Join-Path $OutputDirectory $zipName
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -Force
}
finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
$infoPath = Join-Path $OutputDirectory 'cmdpeek-win-x64.sha256.json'
$info = @{
    schemaVersion     = 1
    packageIdentifier = 'cmdpeek.cmdpeek'
    packageVersion    = $Version
    installerUrl      = ('https://github.com/cmdpeek/cmdpeek/releases/download/v{0}/{1}' -f $Version, $zipName)
    installerSha256   = $hash
    zipFile           = $zipName
}
($info | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $infoPath -Encoding UTF8

if ($UpdateManifest) {
    $manifest = Join-Path (Join-Path $RepoRoot 'winget') 'manifest.yaml'
    if (Test-Path -LiteralPath $manifest) {
        $text = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8
        $text = [regex]::Replace($text, '(?m)^PackageVersion:\s*.*$', ('PackageVersion: {0}' -f $Version))
        $text = [regex]::Replace($text, '(?m)^    InstallerUrl:\s*.*$', ('    InstallerUrl: {0}' -f $info.installerUrl))
        $text = [regex]::Replace($text, '(?m)^    InstallerSha256:\s*.*$', ('    InstallerSha256: {0}' -f $hash))
        Set-Content -LiteralPath $manifest -Value $text -Encoding UTF8
    }
}

Write-Output ([pscustomobject]@{
    ZipPath         = $zipPath
    InstallerSha256 = $hash
    InfoPath        = $infoPath
    PackageVersion  = $Version
})
