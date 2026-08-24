$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$moduleSrc = Join-Path $toolsDir 'cmdpeek'
$installDir = Join-Path $env:ChocolateyPackageFolder 'cmdpeek-install'

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item -Path (Join-Path $moduleSrc '*') -Destination $installDir -Recurse -Force

$shimTarget = Join-Path $installDir 'cmdpeek.ps1'
Install-BinFile -Name 'cmdpeek' -Path $shimTarget
