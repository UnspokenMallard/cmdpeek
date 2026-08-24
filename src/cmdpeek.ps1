#Requires -Version 5.1
<#
.SYNOPSIS
    cmdpeek — recently installed commands and how to use them.
.EXAMPLE
    cmdpeek 5
.EXAMPLE
    cmdpeek -n 3
.EXAMPLE
    cmdpeek -i
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Argument,

    [Alias('n')]
    [int]$Count,

    [Alias('i')]
    [switch]$Interactive,

    [string]$Search,

    [string]$Category,

    [switch]$NonInteractive,

    [string]$Reinstall,

    [ValidateSet('chocolatey', 'scoop', 'winget')]
    [string]$Manager,

    [string]$Export,

    [string]$Import,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help -or $Argument -in @('-h', '--help', '/?')) {
    @'
cmdpeek — show recently installed commands and common usages

Usage:
  cmdpeek                 Interactive browser
  cmdpeek 5               Quick mode: last 5 commands
  cmdpeek -n 5            Same as cmdpeek 5
  cmdpeek -i              Interactive mode
  cmdpeek -Search rg      Filter by name
  cmdpeek -Category media Filter by category
  cmdpeek --reinstall fd  Reinstall a tracked package
  cmdpeek -Export out.json
  cmdpeek -Import out.json

Keys in interactive mode:
  #  open command     /  search     C  category
  F  favorite         A  show all   E  export     Q  quit
'@ | Write-Output
    exit 0
}

$moduleManifest = Join-Path $PSScriptRoot 'cmdpeek.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest)) {
    $moduleManifest = Join-Path $PSScriptRoot 'src\cmdpeek.psd1'
}

Import-Module $moduleManifest -Force

$invoke = @{}

if ($PSBoundParameters.ContainsKey('Count') -and $Count -gt 0) {
    $invoke.Count = $Count
}
elseif ($Argument -and $Argument -match '^\d+$') {
    $invoke.Count = [int]$Argument
}

if ($Interactive) { $invoke.Interactive = $true }
if ($Search) { $invoke.Search = $Search }
elseif ($Argument -and $Argument -notmatch '^\d+$' -and $Argument -notmatch '^-') {
    $invoke.Search = $Argument
}
if ($Category) { $invoke.Category = $Category }
if ($NonInteractive) { $invoke.NonInteractive = $true }
if ($Reinstall) { $invoke.Reinstall = $Reinstall }
if ($Manager) { $invoke.Manager = $Manager }
if ($Export) { $invoke.Export = $Export }
if ($Import) { $invoke.Import = $Import }

Invoke-CmdPeek @invoke
