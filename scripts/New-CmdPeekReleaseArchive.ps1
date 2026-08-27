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
    [string]$GitHubRepository,
    [string]$Tag,
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

    Get-ChildItem -LiteralPath $stage -Recurse -Force | ForEach-Object {
        if ($_.LastWriteTime.Year -lt 1980) {
            $_.LastWriteTime = [datetime]'2020-01-01T00:00:00Z'
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

if (-not $GitHubRepository) {
    $GitHubRepository = [string]$env:GITHUB_REPOSITORY
}
if (-not $GitHubRepository) {
    try {
        $remote = git -C $RepoRoot remote get-url origin 2>$null
        if ($remote -match 'github\.com[:/]([^/]+/[^/.]+)') {
            $GitHubRepository = $Matches[1] -replace '\.git$', ''
        }
    }
    catch { }
}
if (-not $GitHubRepository) { $GitHubRepository = 'UnspokenMallard/cmdpeek' }

if (-not $Tag) {
    if ($env:GITHUB_REF_TYPE -eq 'tag' -and $env:GITHUB_REF_NAME) {
        $Tag = [string]$env:GITHUB_REF_NAME
    }
    elseif ($env:CMDPEEK_RELEASE_TAG) {
        $Tag = [string]$env:CMDPEEK_RELEASE_TAG
    }
    else {
        $Tag = 'v' + $Version
    }
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
$infoPath = Join-Path $OutputDirectory 'cmdpeek-win-x64.sha256.json'
$installerUrl = 'https://github.com/{0}/releases/download/{1}/{2}' -f $GitHubRepository, $Tag, $zipName
$info = @{
    schemaVersion     = 1
    packageIdentifier = 'cmdpeek.cmdpeek'
    packageVersion    = $Version
    installerUrl      = $installerUrl
    installerSha256   = $hash
    zipFile           = $zipName
    tag               = $Tag
}
($info | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $infoPath -Encoding UTF8

if ($UpdateManifest) {
    $url = $info.installerUrl
    $hashLower = $hash.ToLowerInvariant()

    $manifest = Join-Path (Join-Path $RepoRoot 'winget') 'manifest.yaml'
    if (Test-Path -LiteralPath $manifest) {
        $text = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8
        $text = [regex]::Replace($text, '(?m)^PackageVersion:\s*.*$', ('PackageVersion: {0}' -f $Version))
        $text = [regex]::Replace($text, '(?m)^    InstallerUrl:\s*.*$', ('    InstallerUrl: {0}' -f $url))
        $text = [regex]::Replace($text, '(?m)^    InstallerSha256:\s*.*$', ('    InstallerSha256: {0}' -f $hash))
        Set-Content -LiteralPath $manifest -Value $text -Encoding UTF8
    }

    $scoopPath = Join-Path (Join-Path $RepoRoot 'scoop') 'cmdpeek.json'
    if (Test-Path -LiteralPath $scoopPath) {
        $scoop = Get-Content -LiteralPath $scoopPath -Raw -Encoding UTF8
        $scoop = [regex]::Replace($scoop, '(?m)^  "version":\s*"[^"]*"', ('  "version": "{0}"' -f $Version))
        $urlPattern = '(?m)^  "url":\s*"[^"]*"\s*,?'
        if ($scoop -match '(?m)^  "hash":\s*"') {
            $scoop = [regex]::Replace($scoop, $urlPattern, ('  "url": "{0}",' -f $url))
            $scoop = [regex]::Replace($scoop, '(?m)^  "hash":\s*"[^"]*"\s*,?', ('  "hash": "{0}",' -f $hashLower))
        }
        else {
            $scoop = [regex]::Replace($scoop, $urlPattern, ('  "url": "{0}",{1}  "hash": "{2}",' -f $url, [Environment]::NewLine, $hashLower))
        }
        $scoop = [regex]::Replace($scoop, '(?m)^\s*"extract_dir":\s*"[^"]*"\s*,?\s*(\r?\n)?', '')
        if ($scoop -match '(?m)^  "bin":\s*"') {
            $scoop = [regex]::Replace($scoop, '(?m)^  "bin":\s*"[^"]*"', '  "bin": "cmdpeek.cmd"')
        }
        else {
            $scoop = [regex]::Replace($scoop, '(?s)"bin":\s*\[\s*\[[^\]]*\]\s*\]', '"bin": "cmdpeek.cmd"')
        }
        Set-Content -LiteralPath $scoopPath -Value $scoop -Encoding UTF8
    }

    $nuspec = Join-Path (Join-Path $RepoRoot 'chocolatey') 'cmdpeek.nuspec'
    if (Test-Path -LiteralPath $nuspec) {
        $choco = Get-Content -LiteralPath $nuspec -Raw -Encoding UTF8
        $choco = [regex]::Replace($choco, '<version>[^<]*</version>', ('<version>{0}</version>' -f $Version))
        Set-Content -LiteralPath $nuspec -Value $choco -Encoding UTF8
    }
}

Write-Output ([pscustomobject]@{
    ZipPath         = $zipPath
    InstallerSha256 = $hash
    InfoPath        = $infoPath
    PackageVersion  = $Version
    InstallerUrl    = $installerUrl
    Tag             = $Tag
})
