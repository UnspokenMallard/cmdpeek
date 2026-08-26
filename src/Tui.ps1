#Requires -Version 5.1
Set-StrictMode -Version Latest

function New-CmdPeekTuiState {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        View            = 'list'
        Selected        = 0
        Scroll          = 0
        Pane            = 'list'
        UsageSelected   = 0
        Query           = ''
        Category        = ''
        FavoritesOnly   = $false
        HiddenOnly      = $false
        Status          = ''
        Quit            = $false
        CopyRequested   = $false
        RunRequested    = $false
        FavoriteToggle  = $false
        HideToggle      = $false
    }
}

function Move-CmdPeekIndex {
    [CmdletBinding()]
    param(
        [int]$Index,
        [int]$Delta,
        [int]$Count
    )

    if ($Count -le 0) { return 0 }
    $next = $Index + $Delta
    if ($next -lt 0) { return 0 }
    if ($next -ge $Count) { return ($Count - 1) }
    return $next
}

function Get-CmdPeekScrollOffset {
    [CmdletBinding()]
    param(
        [int]$Selected,
        [int]$Offset,
        [int]$PageSize,
        [int]$Count
    )

    if ($PageSize -le 0 -or $Count -le $PageSize) { return 0 }
    $next = $Offset
    if ($Selected -lt $next) {
        $next = $Selected
    }
    elseif ($Selected -ge ($next + $PageSize)) {
        $next = $Selected - $PageSize + 1
    }
    $maxOffset = $Count - $PageSize
    if ($next -gt $maxOffset) { $next = $maxOffset }
    if ($next -lt 0) { $next = 0 }
    return $next
}

function Get-CmdPeekProbeWindow {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$View,
        [int]$Selected = 0,
        [int]$Scroll = 0,
        [int]$PageSize = 10
    )

    $rows = @($View)
    if ($rows.Count -eq 0) { return @() }
    if ($PageSize -lt 1) { $PageSize = 1 }

    $start = $Scroll
    if ($start -lt 0) { $start = 0 }
    if ($start -ge $rows.Count) { $start = 0 }

    $end = $start + $PageSize
    if ($end -gt $rows.Count) { $end = $rows.Count }

    $indexes = New-Object 'System.Collections.Generic.HashSet[int]'
    for ($i = $start; $i -lt $end; $i++) {
        [void]$indexes.Add($i)
    }
    if ($Selected -ge 0 -and $Selected -lt $rows.Count) {
        [void]$indexes.Add($Selected)
    }

    foreach ($i in ($indexes | Sort-Object)) {
        $rows[$i]
    }
}

function Convert-CmdPeekKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [char]$KeyChar = [char]0,
        [string]$Modifiers = 'None',
        [switch]$SearchMode
    )

    if ($SearchMode) {
        switch ($Key) {
            'Enter'     { return 'Enter' }
            'Escape'    { return 'Escape' }
            'Backspace' { return 'Backspace' }
            'UpArrow'   { return 'Up' }
            'DownArrow' { return 'Down' }
            'LeftArrow' { return 'Left' }
            'RightArrow'{ return 'Right' }
        }
        if ($KeyChar -ne [char]0 -and -not [char]::IsControl($KeyChar)) {
            return 'Type'
        }
        return 'Ignore'
    }

    switch ($Key) {
        'UpArrow'    { return 'Up' }
        'DownArrow'  { return 'Down' }
        'PageUp'     { return 'PageUp' }
        'PageDown'   { return 'PageDown' }
        'Home'       { return 'Home' }
        'End'        { return 'End' }
        'LeftArrow'  { return 'Left' }
        'RightArrow' { return 'Right' }
        'Tab'        { return 'Tab' }
        'Enter'      { return 'Enter' }
        'Escape'     { return 'Escape' }
        'F1'         { return 'Help' }
    }

    if ($KeyChar -eq '?') { return 'Help' }
    if ($KeyChar -eq [char]47 -or $Key -eq 'Divide') { return 'Search' }
    if ($Key -eq 'Oem2') {
        if ($KeyChar -eq '?') { return 'Help' }
        return 'Search'
    }

    $shift = $Modifiers -match 'Shift'
    $letter = ([string]$KeyChar).ToLowerInvariant()
    switch ($letter) {
        'q' { return 'Quit' }
        'f' { if ($shift) { return 'FavoritesFilter' } else { return 'Favorite' } }
        'h' { if ($shift) { return 'HiddenFilter' } else { return 'Hide' } }
        'g' { return 'Gaps' }
        'u' { return 'Have' }
        'c' { if ($shift) { return 'CategoryFilter' } else { return 'Copy' } }
        'r' { return 'Run' }
        'a' { return 'All' }
        '/' { return 'Search' }
        '?' { return 'Help' }
    }

    return 'Ignore'
}

function Update-CmdPeekTuiState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,
        [Parameter(Mandatory)]
        [string]$Action,
        [char]$Char = [char]0,
        [int]$ViewCount = 0,
        [int]$UsageCount = 0,
        [int]$PageSize = 10,
        [string[]]$CategoryList
    )

    $State.CopyRequested = $false
    $State.RunRequested = $false
    $State.FavoriteToggle = $false
    $State.HideToggle = $false

    switch ($State.View) {
        'search' {
            switch ($Action) {
                'Type' {
                    if ($Char -ne [char]0) { $State.Query = $State.Query + ([string]$Char) }
                    $State.Selected = 0
                }
                'Backspace' {
                    if ($State.Query.Length -gt 0) {
                        $State.Query = $State.Query.Substring(0, $State.Query.Length - 1)
                    }
                    $State.Selected = 0
                }
                'Enter' { $State.View = 'list' }
                'Escape' {
                    $State.Query = ''
                    $State.View = 'list'
                }
                'Up' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta -1 -Count $ViewCount }
                'Down' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta 1 -Count $ViewCount }
                'Quit' { $State.Quit = $true }
            }
        }
        'gaps' {
            switch ($Action) {
                'Up' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta -1 -Count $ViewCount }
                'Down' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta 1 -Count $ViewCount }
                'PageUp' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta (-1 * $PageSize) -Count $ViewCount }
                'PageDown' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta $PageSize -Count $ViewCount }
                'Home' { $State.Selected = 0 }
                'End' { $State.Selected = Move-CmdPeekIndex -Index 0 -Delta ([Math]::Max(0, $ViewCount - 1)) -Count $ViewCount }
                'Escape' { $State.View = 'list'; $State.Selected = 0 }
                'Quit' { $State.Quit = $true }
                'Help' { $State.View = 'help' }
                'Search' { $State.View = 'search' }
                'Have' { $State.View = 'have'; $State.Selected = 0; $State.Scroll = 0 }
            }
        }
        'have' {
            switch ($Action) {
                'Up' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta -1 -Count $ViewCount }
                'Down' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta 1 -Count $ViewCount }
                'PageUp' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta (-1 * $PageSize) -Count $ViewCount }
                'PageDown' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta $PageSize -Count $ViewCount }
                'Home' { $State.Selected = 0 }
                'End' { $State.Selected = Move-CmdPeekIndex -Index 0 -Delta ([Math]::Max(0, $ViewCount - 1)) -Count $ViewCount }
                'Escape' { $State.View = 'list'; $State.Selected = 0 }
                'Quit' { $State.Quit = $true }
                'Help' { $State.View = 'help' }
                'Gaps' { $State.View = 'gaps'; $State.Selected = 0; $State.Scroll = 0 }
            }
        }
        'help' {
            switch ($Action) {
                { $_ -in @('Escape', 'Enter', 'Help', 'Quit') } {
                    if ($Action -eq 'Quit') { $State.Quit = $true }
                    else { $State.View = 'list' }
                }
            }
        }
        'detail' {
            switch ($Action) {
                'Up' { $State.UsageSelected = Move-CmdPeekIndex -Index $State.UsageSelected -Delta -1 -Count $UsageCount }
                'Down' { $State.UsageSelected = Move-CmdPeekIndex -Index $State.UsageSelected -Delta 1 -Count $UsageCount }
                'Escape' { $State.View = 'list' }
                'Quit' { $State.Quit = $true }
                'Copy' { $State.CopyRequested = $true }
                'Run' { $State.RunRequested = $true }
                'Enter' { $State.CopyRequested = $true }
                'Favorite' { $State.FavoriteToggle = $true }
                'Hide' { $State.HideToggle = $true }
                'Help' { $State.View = 'help' }
            }
        }
        default {
            switch ($Action) {
                'Up' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta -1 -Count $ViewCount }
                'Down' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta 1 -Count $ViewCount }
                'PageUp' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta (-1 * $PageSize) -Count $ViewCount }
                'PageDown' { $State.Selected = Move-CmdPeekIndex -Index $State.Selected -Delta $PageSize -Count $ViewCount }
                'Home' { $State.Selected = 0 }
                'End' { $State.Selected = Move-CmdPeekIndex -Index 0 -Delta ([Math]::Max(0, $ViewCount - 1)) -Count $ViewCount }
                'Left' { $State.Pane = 'list' }
                'Right' { $State.Pane = 'preview' }
                'Tab' {
                    if ($State.Pane -eq 'list') { $State.Pane = 'preview' }
                    else { $State.Pane = 'list' }
                }
                'Enter' {
                    if ($State.Pane -eq 'preview') { $State.CopyRequested = $true }
                    else { $State.View = 'detail'; $State.UsageSelected = 0 }
                }
                'Search' { $State.View = 'search' }
                'Gaps' { $State.View = 'gaps'; $State.Selected = 0; $State.Scroll = 0 }
                'Have' { $State.View = 'have'; $State.Selected = 0; $State.Scroll = 0 }
                'Help' { $State.View = 'help' }
                'Quit' { $State.Quit = $true }
                'Escape' {
                    if ($State.Query -or $State.Category -or $State.FavoritesOnly -or $State.HiddenOnly) {
                        $State.Query = ''
                        $State.Category = ''
                        $State.FavoritesOnly = $false
                        $State.HiddenOnly = $false
                    }
                    else {
                        $State.Quit = $true
                    }
                }
                'Favorite' { $State.FavoriteToggle = $true }
                'Hide' { $State.HideToggle = $true }
                'Copy' { $State.CopyRequested = $true }
                'Run' { $State.RunRequested = $true }
                'CategoryFilter' {
                    $State.Category = Get-CmdPeekNextCategory -Current $State.Category -Category $CategoryList
                    $State.Selected = 0
                    $State.Scroll = 0
                }
                'FavoritesFilter' {
                    $State.FavoritesOnly = -not $State.FavoritesOnly
                    $State.Selected = 0
                    $State.Scroll = 0
                }
                'HiddenFilter' {
                    $State.HiddenOnly = -not $State.HiddenOnly
                    $State.Selected = 0
                    $State.Scroll = 0
                }
                'All' {
                    $State.Query = ''
                    $State.Category = ''
                    $State.FavoritesOnly = $false
                    $State.HiddenOnly = $false
                }
            }
        }
    }

    if ($ViewCount -le 0) {
        $State.Selected = 0
        $State.Scroll = 0
    }
    elseif ($State.Selected -ge $ViewCount) {
        $State.Selected = $ViewCount - 1
    }

    $State.Scroll = Get-CmdPeekScrollOffset -Selected $State.Selected -Offset $State.Scroll -PageSize $PageSize -Count $ViewCount
    return $State
}

function Get-CmdPeekNextCategory {
    [CmdletBinding()]
    param(
        [string]$Current,
        [string[]]$Category
    )

    $cats = @($Category | Where-Object { $_ } | Select-Object -Unique)
    if ($cats.Count -eq 0) { return '' }
    if ([string]::IsNullOrWhiteSpace($Current)) {
        return [string]$cats[0]
    }

    $idx = -1
    for ($i = 0; $i -lt $cats.Count; $i++) {
        if ($cats[$i] -eq $Current) {
            $idx = $i
            break
        }
    }
    if ($idx -lt 0 -or $idx -ge ($cats.Count - 1)) {
        return ''
    }
    return [string]$cats[$idx + 1]
}

function Test-CmdPeekTuiConsole {
    [CmdletBinding()]
    param()

    try {
        if ([Console]::IsInputRedirected) { return $false }
        if ([Console]::IsOutputRedirected) { return $false }
        return [Environment]::UserInteractive
    }
    catch {
        return $false
    }
}

function Enable-CmdPeekVirtualTerminal {
    [CmdletBinding()]
    param()

    $typeName = 'CmdPeekNativeConsole'
    if (-not ([System.Management.Automation.PSTypeName]$typeName).Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class CmdPeekNativeConsole {
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    public const int STD_OUTPUT_HANDLE = -11;
    public const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
    public static bool EnableVt() {
        IntPtr h = GetStdHandle(STD_OUTPUT_HANDLE);
        uint mode;
        if (!GetConsoleMode(h, out mode)) return false;
        return SetConsoleMode(h, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }
}
"@
    }
    try {
        return [CmdPeekNativeConsole]::EnableVt()
    }
    catch {
        return $false
    }
}

function Get-CmdPeekPadded {
    param([string]$Text, [int]$Width)
    if ($Width -le 0) { return '' }
    if ($null -eq $Text) { $Text = '' }
    if ($Text.Length -gt $Width) { return $Text.Substring(0, $Width) }
    return $Text.PadRight($Width)
}

function Get-CmdPeekUsageCommandText {
    param([string]$Usage)
    if ([string]::IsNullOrWhiteSpace($Usage)) { return '' }
    return ($Usage -split '#')[0].Trim()
}

function Write-CmdPeekTuiFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,
        [AllowEmptyCollection()]
        [object[]]$View,
        [AllowEmptyCollection()]
        [object[]]$Gap,
        [AllowEmptyCollection()]
        [object[]]$Have,
        [int]$Width,
        [int]$Height
    )

    $esc = [char]27
    $reset = "$esc[0m"
    $bold = "$esc[1m"
    $dim = "$esc[2m"
    $cyan = "$esc[36m"
    $yellow = "$esc[33m"
    $rev = "$esc[7m"
    $green = "$esc[32m"

    if ($Width -lt 40) { $Width = 40 }
    if ($Height -lt 12) { $Height = 12 }

    $lines = New-Object System.Collections.Generic.List[string]
    $title = 'cmdpeek'
    if ($State.View -eq 'gaps') { $title = 'cmdpeek  gaps' }
    elseif ($State.View -eq 'have') { $title = 'cmdpeek  use what you have' }
    elseif ($State.View -eq 'help') { $title = 'cmdpeek  keys' }
    elseif ($State.View -eq 'detail') { $title = 'cmdpeek  detail' }
    elseif ($State.View -eq 'search') { $title = 'cmdpeek  search' }

    $filterBits = @()
    if ($State.Query) { $filterBits += ('/' + $State.Query) }
    if ($State.FavoritesOnly) { $filterBits += 'fav' }
    if ($State.HiddenOnly) { $filterBits += 'hidden' }
    if ($State.Category) { $filterBits += ('cat:' + $State.Category) }
    $filter = $(if ($filterBits.Count) { '  ' + ($filterBits -join '  ') } else { '' })
    $header = Get-CmdPeekPadded (" $title$filter") ($Width - 1)
    $lines.Add("$cyan$bold$header$reset")

    $bodyHeight = $Height - 3
    $rows = @($View)
    $gaps = @($Gap)

    if ($State.View -eq 'help') {
        $help = @(
            'Arrow keys  Move selection (list and examples)'
            'Tab / Left / Right   Switch list and preview panes'
            'Enter       Open detail (list) or copy example (preview)'
            '/           Search by name, package, manager, or usage'
            'f           Toggle favorite on the selected command'
            'Shift+F     Show favorites only'
            'Shift+C     Cycle category filter'
            'Shift+H     Show hidden commands only'
            'h           Hide/unhide this command in cmdpeek -n quick view'
            'g           Gap view: related tools you do not have'
            'u           Use what you have: installed tools by category'
            'c           Copy highlighted usage to the clipboard'
            'r           Run usage if it has no <placeholders>'
            'a           Clear search / category / favorites filter'
            '? / F1      This help     Esc  Back     q  Quit'
        )
        foreach ($h in $help) { $lines.Add('  ' + $h) }
        while ($lines.Count -lt ($Height - 1)) { $lines.Add('') }
    }
    elseif ($State.View -eq 'gaps') {
        if ($gaps.Count -eq 0) {
            $lines.Add("$dim  No gaps. Related tools are installed and examples are curated.$reset")
        }
        else {
            $page = $bodyHeight
            $start = $State.Scroll
            $slice = @($gaps | Select-Object -Skip $start -First $page)
            $i = 0
            foreach ($g in $slice) {
                $idx = $start + $i
                $mark = $(if ($idx -eq $State.Selected) { '>' } else { ' ' })
                $kind = Get-CmdPeekPadded $g.Kind 18
                $cmd = Get-CmdPeekPadded ([string]$g.Command) 18
                $why = [string]$g.Reason
                $row = " $mark $kind $cmd $why"
                $row = Get-CmdPeekPadded $row $Width
                if ($idx -eq $State.Selected) { $lines.Add("$rev$row$reset") }
                else { $lines.Add($row) }
                $i++
            }
        }
        while ($lines.Count -lt ($Height - 1)) { $lines.Add('') }
    }
    elseif ($State.View -eq 'have') {
        $haveRows = @($Have)
        if ($haveRows.Count -eq 0) {
            $lines.Add("$dim  No installed catalog tools to show.$reset")
        }
        else {
            $page = $bodyHeight
            $start = $State.Scroll
            $slice = @($haveRows | Select-Object -Skip $start -First $page)
            $i = 0
            foreach ($h in $slice) {
                $idx = $start + $i
                $mark = $(if ($idx -eq $State.Selected) { '>' } else { ' ' })
                $caps = ''
                if ($h.PSObject.Properties['Capabilities'] -and $h.Capabilities) {
                    $caps = (@($h.Capabilities) -join ',')
                }
                $row = " $mark $(Get-CmdPeekPadded $h.Command 14) $(Get-CmdPeekPadded $h.PackageManager 10) $(Get-CmdPeekPadded $h.Category 12) $caps"
                $row = Get-CmdPeekPadded $row $Width
                if ($idx -eq $State.Selected) { $lines.Add("$rev$row$reset") }
                else { $lines.Add($row) }
                $i++
            }
        }
        while ($lines.Count -lt ($Height - 1)) { $lines.Add('') }
    }
    elseif ($State.View -eq 'detail') {
        $row = $null
        if ($rows.Count -gt 0 -and $State.Selected -lt $rows.Count) { $row = $rows[$State.Selected] }
        if ($row) {
            $star = $(if ($row.Favorite) { ' *' } else { '' })
            $hiddenNote = $(if ($row.PSObject.Properties['Hidden'] -and $row.Hidden) { '  hidden from -n' } else { '' })
            $lines.Add("$bold  $($row.Command)$star$reset  $($row.PackageManager)  $(Format-CmdPeekDate $row.InstallDate)$dim$hiddenNote$reset")
            $lines.Add($dim + '  ' + ([string]$row.Category) + $reset)
            $lines.Add('')
            $usages = @()
            if ($row.PSObject.Properties['Usages']) { $usages = @($row.Usages) }
            $u = 0
            foreach ($usage in $usages) {
                $mark = $(if ($u -eq $State.UsageSelected) { '>' } else { ' ' })
                $line = Get-CmdPeekPadded (" $mark  $usage") $Width
                if ($u -eq $State.UsageSelected) { $lines.Add("$rev$line$reset") }
                else { $lines.Add($line) }
                $u++
            }
            if ($row.PSObject.Properties['Related'] -and $row.Related -and @($row.Related).Count -gt 0) {
                $lines.Add('')
                $lines.Add("$yellow  Related not installed: $reset$($row.Related -join ', ')")
            }
        }
        else {
            $lines.Add('  (no command selected)')
        }
        while ($lines.Count -lt ($Height - 1)) { $lines.Add('') }
    }
    else {
        $leftW = [int]([Math]::Floor($Width * 0.46))
        if ($leftW -lt 24) { $leftW = 24 }
        if ($leftW -gt ($Width - 20)) { $leftW = $Width - 20 }
        $rightW = $Width - $leftW - 1
        $page = $bodyHeight
        $start = $State.Scroll
        $slice = @($rows | Select-Object -Skip $start -First $page)

        $leftLines = New-Object System.Collections.Generic.List[string]
        $rightLines = New-Object System.Collections.Generic.List[string]

        if ($rows.Count -eq 0) {
            $leftLines.Add("$dim no matching commands$reset")
        }
        else {
            $i = 0
            foreach ($item in $slice) {
                $idx = $start + $i
                $mark = $(if ($idx -eq $State.Selected) { '>' } else { ' ' })
                $hidden = [bool]($item.PSObject.Properties['Hidden'] -and $item.Hidden)
                $flag = ' '
                if ($item.Favorite -and $hidden) { $flag = '+' }
                elseif ($item.Favorite) { $flag = '*' }
                elseif ($hidden) { $flag = '-' }
                $cmd = Get-CmdPeekPadded ([string]$item.Command) 16
                $pm = Get-CmdPeekPadded ([string]$item.PackageManager) 11
                $date = Format-CmdPeekDate $item.InstallDate
                $text = Get-CmdPeekPadded ("$mark$flag $cmd $pm $date") $leftW
                if ($idx -eq $State.Selected -and $State.Pane -eq 'list') {
                    $leftLines.Add("$rev$text$reset")
                }
                elseif ($hidden) {
                    $leftLines.Add("$dim$text$reset")
                }
                else {
                    $leftLines.Add($text)
                }
                $i++
            }
        }

        $selected = $null
        if ($rows.Count -gt 0 -and $State.Selected -ge 0 -and $State.Selected -lt $rows.Count) {
            $selected = $rows[$State.Selected]
        }
        if ($selected) {
            $star = $(if ($selected.Favorite) { ' *' } else { '' })
            $rightLines.Add("$bold$($selected.Command)$star$reset")
            $meta = "$($selected.PackageManager)  $(Format-CmdPeekDate $selected.InstallDate)  $($selected.Category)"
            if ($selected.PSObject.Properties['Hidden'] -and $selected.Hidden) {
                $meta = $meta + '  hidden from -n'
            }
            $rightLines.Add($dim + $meta + $reset)
            $rightLines.Add('')
            $usages = @()
            if ($selected.PSObject.Properties['Usages']) { $usages = @($selected.Usages) }
            $u = 0
            foreach ($usage in $usages) {
                $mark = $(if ($u -eq $State.UsageSelected) { '>' } else { ' ' })
                $line = Get-CmdPeekPadded ("$mark $usage") $rightW
                if ($u -eq $State.UsageSelected -and $State.Pane -eq 'preview') {
                    $rightLines.Add("$rev$line$reset")
                }
                else {
                    $rightLines.Add($line)
                }
                $u++
            }
            if ($selected.PSObject.Properties['Related'] -and $selected.Related -and @($selected.Related).Count -gt 0) {
                $rightLines.Add('')
                $rightLines.Add("$yellow gaps:$reset $($selected.Related -join ', ')")
            }
        }
        else {
            $rightLines.Add("$dim preview$reset")
        }

        for ($r = 0; $r -lt $page; $r++) {
            $l = $(if ($r -lt $leftLines.Count) { $leftLines[$r] } else { ''.PadRight($leftW) })
            # padded visual width is approximate when ANSI is present; keep separator
            $ri = $(if ($r -lt $rightLines.Count) { $rightLines[$r] } else { '' })
            $sep = $(if ($State.Pane -eq 'preview') { "$dim|$reset" } else { "$dim|$reset" })
            $lines.Add($l + $sep + $ri)
        }
    }

    if ($State.View -eq 'search') {
        $footer = Get-CmdPeekPadded (" /$($State.Query)_") $Width
        $lines.Add("$green$footer$reset")
    }
    else {
        $hint = '↑↓ move  ←→ pane  ↵ open/copy  / search  f fav  g gaps  u have  h hide  ? help  q quit'
        if ($State.Status) { $hint = $State.Status }
        $lines.Add("$dim" + (Get-CmdPeekPadded $hint $Width) + "$reset")
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$esc[H$esc[J")
    foreach ($line in $lines) {
        [void]$sb.Append($line)
        [void]$sb.Append("`r`n")
    }
    [Console]::Write($sb.ToString())
}

function Invoke-CmdPeekTui {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [object]$State,
        [string]$DataDirectory,
        [AllowEmptyCollection()]
        [object[]]$Gap,
        [hashtable]$Catalog,
        [scriptblock]$HelpRunner
    )

    $all = @($History)
    $gaps = @($Gap)
    if ($gaps.Count -eq 0) {
        $gaps = @()
    }

    $ui = New-CmdPeekTuiState
    $savedCursor = $true
    try { $savedCursor = [Console]::CursorVisible } catch { $savedCursor = $true }
    $esc = [char]27
    [void](Enable-CmdPeekVirtualTerminal)
    $originalEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::CursorVisible = $false
        [Console]::Write("$esc[?1049h")

        while (-not $ui.Quit) {
            $view = @(Search-CmdPeekCommand -History $all -Query $ui.Query -Category $ui.Category -Favorite:$ui.FavoritesOnly -HiddenOnly:$ui.HiddenOnly)

            $width = 80
            $height = 24
            try { $width = [Console]::WindowWidth; $height = [Console]::WindowHeight } catch { }
            $page = [Math]::Max(5, $height - 3)

            if ($ui.View -ne 'gaps' -and $ui.View -ne 'help' -and $ui.View -ne 'have') {
                $window = @(Get-CmdPeekProbeWindow -View $view -Selected $ui.Selected -Scroll $ui.Scroll -PageSize $page)
                if ($window.Count -gt 0) {
                    [void](Add-CmdPeekUsageProbe -History $window -Catalog $Catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner)
                }
            }

            $haveRows = @(Get-CmdPeekHaveList -History $all -Catalog $Catalog)
            $activeCount = $view.Count
            $usageCount = 0
            if ($ui.View -eq 'gaps') {
                $activeCount = $gaps.Count
            }
            elseif ($ui.View -eq 'have') {
                $activeCount = $haveRows.Count
            }
            elseif ($view.Count -gt 0 -and $ui.Selected -lt $view.Count) {
                $row = $view[$ui.Selected]
                if ($row.PSObject.Properties['Usages'] -and $row.Usages) {
                    $usageCount = @($row.Usages).Count
                }
            }

            Write-CmdPeekTuiFrame -State $ui -View $view -Gap $gaps -Have $haveRows -Width $width -Height $height

            $key = [Console]::ReadKey($true)
            $searching = ($ui.View -eq 'search')
            $action = Convert-CmdPeekKey -Key $key.Key.ToString() -KeyChar $key.KeyChar -Modifiers $key.Modifiers.ToString() -SearchMode:$searching
            if ($action -eq 'Ignore') { continue }

            $ui = Update-CmdPeekTuiState -State $ui -Action $action -Char $key.KeyChar -ViewCount $activeCount -UsageCount $usageCount -PageSize $page -CategoryList @(
                $all |
                    Where-Object { $_ -and $_.PSObject.Properties['Category'] -and $_.Category } |
                    ForEach-Object { [string]$_.Category } |
                    Sort-Object -Unique
            )

            if ($ui.FavoriteToggle -and $view.Count -gt 0 -and $ui.Selected -lt $view.Count -and $State) {
                $cmd = $view[$ui.Selected].Command
                $nowFav = -not [bool]$view[$ui.Selected].Favorite
                $State = Set-CmdPeekFavorite -State $State -Command $cmd -Favorite $nowFav
                Save-CmdPeekState -State $State -DataDirectory $DataDirectory
                $all = @(Merge-CmdPeekFavorite -History $all -Favorite @($State.Favorites))
                $ui.Status = $(if ($nowFav) { "Favorited $cmd" } else { "Unfavorited $cmd" })
            }

            if ($ui.HideToggle -and $view.Count -gt 0 -and $ui.Selected -lt $view.Count -and $State) {
                $cmd = $view[$ui.Selected].Command
                $nowHidden = -not [bool]($view[$ui.Selected].PSObject.Properties['Hidden'] -and $view[$ui.Selected].Hidden)
                $State = Set-CmdPeekHidden -State $State -Command $cmd -Hidden $nowHidden
                Save-CmdPeekState -State $State -DataDirectory $DataDirectory
                $all = @(Merge-CmdPeekHidden -History $all -Hidden @($State.Hidden))
                $ui.Status = $(if ($nowHidden) { "Hidden $cmd from quick view (-n)" } else { "Unhidden $cmd" })
            }

            $copySource = $null
            if ($ui.CopyRequested -or $ui.RunRequested) {
                $row = $null
                if ($view.Count -gt 0 -and $ui.Selected -lt $view.Count) { $row = $view[$ui.Selected] }
                if ($row -and $row.PSObject.Properties['Usages']) {
                    $usages = @($row.Usages)
                    if ($usages.Count -gt 0) {
                        $idx = $ui.UsageSelected
                        if ($idx -ge $usages.Count) { $idx = 0 }
                        $copySource = Get-CmdPeekUsageCommandText -Usage $usages[$idx]
                    }
                }
            }

            if ($ui.CopyRequested -and $copySource) {
                if (Copy-CmdPeekText -Text $copySource) { $ui.Status = "Copied: $copySource" }
                else { $ui.Status = $copySource }
            }

            if ($ui.RunRequested -and $copySource) {
                if ($copySource -match '[<[]') {
                    [void](Copy-CmdPeekText -Text $copySource)
                    $ui.Status = "Placeholders — copied instead: $copySource"
                }
                else {
                    [Console]::Write("$esc[?1049l")
                    [Console]::CursorVisible = $true
                    Write-Host "Running: $copySource" -ForegroundColor Cyan
                    cmd.exe /c $copySource
                    Write-Host 'Press any key to return to cmdpeek...'
                    [void][Console]::ReadKey($true)
                    [Console]::CursorVisible = $false
                    [Console]::Write("$esc[?1049h")
                }
            }
        }
    }
    finally {
        try { [Console]::Write("$esc[?1049l$esc[?25h") } catch { }
        try { [Console]::CursorVisible = $savedCursor } catch { }
        try { [Console]::OutputEncoding = $originalEncoding } catch { }
    }
}
