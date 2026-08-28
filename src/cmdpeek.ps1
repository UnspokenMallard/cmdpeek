#Requires -Version 5.1
<#
.SYNOPSIS
    cmdpeek — recently installed commands and how to use them.
.EXAMPLE
    cmdpeek 5
.EXAMPLE
    cmdpeek -n 3
.EXAMPLE
    cmdpeek for json
.EXAMPLE
    cmdpeek -i
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Argument,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Remaining,

    [Alias('n')]
    [int]$Count,

    [Alias('i')]
    [switch]$Interactive,

    [string]$Search,

    [string]$Category,

    [switch]$NonInteractive,

    [string]$Reinstall,

    [ValidateSet('chocolatey', 'scoop', 'winget', 'pipx', 'npm', 'cargo', 'brew')]
    [string]$Manager,

    [string]$Export,

    [string]$Import,

    [switch]$Json,

    [switch]$Gaps,

    [string]$Since,

    [switch]$Recent,

    [switch]$Rusty,

    [string]$Hide,

    [string]$Unhide,

    [string]$Star,

    [string]$Unstar,

    [Alias('For')]
    [string]$Task,

    [string]$Why,

    [string]$Explain,

    [string]$SearchAvailable,

    [switch]$Have,

    [string]$Capability,

    [switch]$Refresh,

    [switch]$LastInstall,

    [switch]$AgentExport,

    [string]$AgentExportPath,

    [string]$Compare,

    [string]$Suggest,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help -or $Argument -in @('-h', '--help', '/?', 'help')) {
    @'
cmdpeek — recently installed commands, gaps, and how to use what you already have

Usage:
  cmdpeek                 Interactive browser
  cmdpeek 5               Quick: since last look (up to 5); fallback to newest 5
  cmdpeek -n 5            Same as cmdpeek 5
  cmdpeek recent          Same as cmdpeek 5
  cmdpeek fd              Cheat sheet if that name is unique; else search
  cmdpeek explain fd      Cheat sheet plus origin, gotchas, substitutes
  cmdpeek for json        Installed tools first, then catalog installs
  cmdpeek why jq          Why this tool, PATH winner, substitutes
  cmdpeek compare robocopy Copy-Item   Side-by-side command cards
  cmdpeek suggest "ps aux"             Map a command line to an installed equivalent
  cmdpeek have [cap]      Installed catalog tools you can use
  cmdpeek agent-export    Markdown playbook of installed tools for agents
  cmdpeek agent-export FILE   Write that playbook to FILE
  cmdpeek gaps            Human-readable inventory gaps
  cmdpeek rusty           Installed tools missing from recent history
  cmdpeek search-available fzf   Catalog + optional package-manager search
  cmdpeek -Since 7d       Window: last|all|ISO|24h|7d (not minutes)
  cmdpeek -i              Interactive mode
  cmdpeek -Search rg      Filter by name
  cmdpeek -Category media Filter by category
  cmdpeek --reinstall fd  Reinstall a tracked package
  cmdpeek -Json               Full inventory JSON (MCP / scripts)
  cmdpeek -Json -Recent       MCP recency envelope
  cmdpeek -Json -Refresh      Bypass inventory cache
  cmdpeek -Gaps               JSON gaps
  cmdpeek -Rusty              Rusty tools
  cmdpeek -Hide LogExpert     Hide a command from cmdpeek -n
  cmdpeek -Star fd            Favorite a command

Keys in interactive TUI:
  Arrows move     Tab/←→ pane     Enter open or copy
  / search        f favorite      F favorites only
  C category      h hide from -n  H hidden only
  g gaps          u use-what-you-have   s system commands
  ? help          Esc back        q quit
'@ | Write-Output
    exit 0
}

$moduleManifest = Join-Path $PSScriptRoot 'cmdpeek.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest)) {
    $moduleManifest = Join-Path $PSScriptRoot 'src\cmdpeek.psd1'
}

Import-Module $moduleManifest -Force

$invoke = @{}
$rest = ''
if ($Remaining) {
    $rest = (@($Remaining) -join ' ').Trim()
}

$verb = ''
if ($Argument) { $verb = $Argument.Trim().ToLowerInvariant() }

if ($verb -eq 'for') {
    $invoke.Task = $rest
}
elseif ($verb -eq 'explain') {
    $invoke.Explain = $(if ($rest) { $rest } else { '' })
}
elseif ($verb -eq 'why') {
    $invoke.Why = $(if ($rest) { ($rest -split '\s+')[0] } else { '' })
}
elseif ($verb -eq 'recent') {
    if (-not ($PSBoundParameters.ContainsKey('Count') -and $Count -gt 0)) {
        $invoke.Count = 5
    }
    $invoke.NonInteractive = $true
}
elseif ($verb -eq 'gaps') {
    $invoke.HumanGaps = $true
}
elseif ($verb -eq 'rusty') {
    $invoke.Rusty = $true
}
elseif ($verb -eq 'have') {
    $invoke.Have = $true
    if ($rest) { $invoke.Capability = $rest }
}
elseif ($verb -eq 'search-available') {
    $invoke.SearchAvailable = $rest
}
elseif ($verb -eq 'agent-export') {
    $invoke.AgentExport = $true
    if ($rest) { $invoke.AgentExportPath = $rest }
}
    elseif ($verb -eq 'compare') {
        $invoke.Compare = $rest
    }
    elseif ($verb -eq 'suggest') {
        $invoke.Suggest = $rest
    }
    elseif ($PSBoundParameters.ContainsKey('Count') -and $Count -gt 0) {
    $invoke.Count = $Count
}
elseif ($Argument -and $Argument -match '^\d+$') {
    $invoke.Count = [int]$Argument
}

if ($Interactive) { $invoke.Interactive = $true }
if ($Search) { $invoke.Search = $Search }
elseif ($Argument -and $Argument -notmatch '^\d+$' -and $Argument -notmatch '^-' -and $verb -notin @('for', 'explain', 'why', 'recent', 'gaps', 'rusty', 'have', 'search-available', 'agent-export', 'compare', 'suggest')) {
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
if ($Rusty) { $invoke.Rusty = $true }
if ($Hide) { $invoke.Hide = $Hide }
if ($Unhide) { $invoke.Unhide = $Unhide }
if ($Star) { $invoke.Star = $Star }
if ($Unstar) { $invoke.Unstar = $Unstar }
if ($Task) { $invoke.Task = $Task }
if ($Why) { $invoke.Why = $Why }
if ($Explain) { $invoke.Explain = $Explain }
if ($SearchAvailable) { $invoke.SearchAvailable = $SearchAvailable }
if ($Have) { $invoke.Have = $true }
if ($Capability) { $invoke.Capability = $Capability }
if ($Refresh) { $invoke.Refresh = $true }
if ($LastInstall) { $invoke.LastInstall = $true }
if ($AgentExport) { $invoke.AgentExport = $true }
if ($AgentExportPath) { $invoke.AgentExportPath = $AgentExportPath }
if ($Compare) { $invoke.Compare = $Compare }
if ($Suggest) { $invoke.Suggest = $Suggest }

Invoke-CmdPeek @invoke
