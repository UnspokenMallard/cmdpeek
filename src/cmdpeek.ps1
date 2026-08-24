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

    [switch]$Json,

    [switch]$Gaps,

    [string]$Since,

    [switch]$Recent,

    [string]$Hide,

    [string]$Unhide,

    [string]$Star,

    [string]$Unstar,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help -or $Argument -in @('-h', '--help', '/?')) {
    @'
cmdpeek — show recently installed commands and common usages

Usage:
  cmdpeek                 Interactive browser
  cmdpeek 5               Quick: since last look (up to 5); fallback to newest 5
  cmdpeek -n 5            Same as cmdpeek 5
  cmdpeek -Since 7d       Window: last|all|ISO|24h|7d (not minutes)
  cmdpeek -i              Interactive mode
  cmdpeek -Search rg      Filter by name
  cmdpeek -Category media Filter by category
  cmdpeek --reinstall fd  Reinstall a tracked package
  cmdpeek -Json               Full inventory JSON (MCP / scripts)
  cmdpeek -Json -Recent       MCP recency envelope (since, mode, shims, onPath)
  cmdpeek -Gaps               JSON gaps: missing related, thin docs, not-on-path
  cmdpeek -Hide LogExpert     Hide a command from cmdpeek -n
  cmdpeek -Star fd            Favorite a command

Keys in interactive TUI:
  Arrows move     Tab/←→ pane     Enter open or copy
  / search        f favorite      F favorites only
  C category      h hide from -n  H hidden only
  g gaps          ? help          Esc back        q quit
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
if ($Json) { $invoke.Json = $true }
if ($Gaps) { $invoke.Gaps = $true }
if ($Since) { $invoke.Since = $Since }
if ($Recent) { $invoke.Recent = $true }
if ($Hide) { $invoke.Hide = $Hide }
if ($Unhide) { $invoke.Unhide = $Unhide }
if ($Star) { $invoke.Star = $Star }
if ($Unstar) { $invoke.Unstar = $Unstar }

Invoke-CmdPeek @invoke
