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

    [string]$DataDirectory,

    [string]$ExamplesPath,

    [string]$Reinstall,

    [ValidateSet('chocolatey', 'scoop', 'winget', 'pipx', 'npm', 'cargo', 'brew', 'apt', 'pacman')]
    [string]$Manager,

    [string]$Export,

    [string]$Import,

    [switch]$Json,

    [switch]$Gaps,

    [ValidateSet('kit', 'missing-related', 'shadowing', 'not-on-path', 'category-neighbor', 'thin-docs', 'all')]
    [string[]]$GapKind,

    [int]$GapLimit = -1,

    [int]$ProbeLimit = -1,

    [string]$Since,

    [switch]$Recent,

    [switch]$Rusty,

    [string]$Hide,

    [string]$Unhide,

    [string]$Star,

    [string]$Unstar,

    [Alias('For')]
    [string]$Task,

    [int]$TaskLimit = 0,

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

    [switch]$IncludeUndocumented,

    [switch]$Doctor,

    [switch]$Timing,

    [Alias('v')]
    [switch]$Version,

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
  cmdpeek agent-export -IncludeUndocumented   Add PATH commands with no usages
  cmdpeek gaps            Human-readable inventory gaps (ranked, capped, no thin-docs)
  cmdpeek gaps -GapKind thin-docs -GapLimit 0    One gap kind, uncapped
  cmdpeek rusty           Installed tools missing from recent history
  cmdpeek doctor          Environment, catalog, and cache health check
  cmdpeek doctor -Timing  Same, plus per-stage scan timings
  cmdpeek --version       Module and MCP server versions
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
    # ValueFromRemainingArguments swallows anything it does not recognise, so a typo like
    # -Jsonn or a flag this script does not declare would silently become the search term
    # or the agent-export filename. Say so instead.
    $stray = @(@($Remaining) | Where-Object { $_ -and $_.Length -gt 1 -and $_.StartsWith('-') })
    if ($stray.Count -gt 0) {
        [Console]::Error.WriteLine("cmdpeek: unknown option $($stray -join ', '). Run 'cmdpeek --help' for the list.")
        exit 2
    }
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
elseif ($verb -eq 'doctor') {
    $invoke.Doctor = $true
}
elseif ($verb -eq 'version') {
    $invoke.Version = $true
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
elseif ($Argument -and $Argument -notmatch '^\d+$' -and $Argument -notmatch '^-' -and $verb -notin @('for', 'explain', 'why', 'recent', 'gaps', 'rusty', 'doctor', 'version', 'have', 'search-available', 'agent-export', 'compare', 'suggest')) {
    $invoke.Search = $Argument
}
if ($Category) { $invoke.Category = $Category }
if ($NonInteractive) { $invoke.NonInteractive = $true }
if ($DataDirectory) { $invoke.DataDirectory = $DataDirectory }
if ($ExamplesPath) { $invoke.ExamplesPath = $ExamplesPath }
if ($Reinstall) { $invoke.Reinstall = $Reinstall }
if ($Manager) { $invoke.Manager = $Manager }
if ($Export) { $invoke.Export = $Export }
if ($Import) { $invoke.Import = $Import }
if ($Json) { $invoke.Json = $true }
if ($Gaps) { $invoke.Gaps = $true }
if ($GapKind) { $invoke.GapKind = $GapKind }
if ($PSBoundParameters.ContainsKey('GapLimit')) { $invoke.GapLimit = $GapLimit }
if ($PSBoundParameters.ContainsKey('ProbeLimit')) { $invoke.ProbeLimit = $ProbeLimit }
if ($Since) { $invoke.Since = $Since }
if ($Recent) { $invoke.Recent = $true }
if ($Rusty) { $invoke.Rusty = $true }
if ($Hide) { $invoke.Hide = $Hide }
if ($Unhide) { $invoke.Unhide = $Unhide }
if ($Star) { $invoke.Star = $Star }
if ($Unstar) { $invoke.Unstar = $Unstar }
if ($Task) { $invoke.Task = $Task }
if ($TaskLimit -gt 0) { $invoke.TaskLimit = $TaskLimit }
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
if ($IncludeUndocumented) { $invoke.IncludeUndocumented = $true }
if ($Doctor) { $invoke.Doctor = $true }
if ($Timing) { $invoke.Timing = $true }
if ($Version) { $invoke.Version = $true }

Invoke-CmdPeek @invoke
