#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'Tui.ps1')
}

Describe 'Move-CmdPeekIndex' {
    It 'clamps at the start and end of the list' {
        Move-CmdPeekIndex -Index 0 -Delta -1 -Count 5 | Should -Be 0
        Move-CmdPeekIndex -Index 4 -Delta 1 -Count 5 | Should -Be 4
        Move-CmdPeekIndex -Index 2 -Delta 1 -Count 5 | Should -Be 3
    }

    It 'returns 0 when the list is empty' {
        Move-CmdPeekIndex -Index 3 -Delta -1 -Count 0 | Should -Be 0
    }
}

Describe 'Get-CmdPeekScrollOffset' {
    It 'scrolls down when the selection leaves the window' {
        Get-CmdPeekScrollOffset -Selected 9 -Offset 0 -PageSize 5 -Count 20 | Should -Be 5
    }

    It 'scrolls up when the selection moves above the window' {
        Get-CmdPeekScrollOffset -Selected 1 -Offset 5 -PageSize 5 -Count 20 | Should -Be 1
    }

    It 'keeps the offset when the selection stays in view' {
        Get-CmdPeekScrollOffset -Selected 6 -Offset 5 -PageSize 5 -Count 20 | Should -Be 5
    }
}

Describe 'Convert-CmdPeekKey' {
    It 'maps arrows, enter, escape, and slash' {
        Convert-CmdPeekKey -Key 'UpArrow' | Should -Be 'Up'
        Convert-CmdPeekKey -Key 'DownArrow' | Should -Be 'Down'
        Convert-CmdPeekKey -Key 'Enter' | Should -Be 'Enter'
        Convert-CmdPeekKey -Key 'Escape' | Should -Be 'Escape'
        Convert-CmdPeekKey -Key 'Oem2' -KeyChar ([char]47) | Should -Be 'Search'
        Convert-CmdPeekKey -Key 'Divide' -KeyChar ([char]47) | Should -Be 'Search'
    }

    It 'maps letters to named actions outside search mode' {
        Convert-CmdPeekKey -Key 'Q' -KeyChar 'q' | Should -Be 'Quit'
        Convert-CmdPeekKey -Key 'F' -KeyChar 'f' | Should -Be 'Favorite'
        Convert-CmdPeekKey -Key 'H' -KeyChar 'h' | Should -Be 'Hide'
        Convert-CmdPeekKey -Key 'G' -KeyChar 'g' | Should -Be 'Gaps'
        Convert-CmdPeekKey -Key 'U' -KeyChar 'u' | Should -Be 'Have'
        Convert-CmdPeekKey -Key 'C' -KeyChar 'c' | Should -Be 'Copy'
        Convert-CmdPeekKey -Key 'R' -KeyChar 'r' | Should -Be 'Run'
        Convert-CmdPeekKey -Key 'Oem2' -KeyChar '?' | Should -Be 'Help'
    }

    It 'maps Shift+C and Shift+F to category and favorites filters' {
        Convert-CmdPeekKey -Key 'C' -KeyChar 'C' -Modifiers 'Shift' | Should -Be 'CategoryFilter'
        Convert-CmdPeekKey -Key 'F' -KeyChar 'F' -Modifiers 'Shift' | Should -Be 'FavoritesFilter'
        Convert-CmdPeekKey -Key 'C' -KeyChar 'c' -Modifiers 'None' | Should -Be 'Copy'
        Convert-CmdPeekKey -Key 'F' -KeyChar 'f' -Modifiers 'None' | Should -Be 'Favorite'
    }

    It 'maps Shift+H to hidden-only filter without stealing hide' {
        Convert-CmdPeekKey -Key 'H' -KeyChar 'H' -Modifiers 'Shift' | Should -Be 'HiddenFilter'
        Convert-CmdPeekKey -Key 'H' -KeyChar 'h' -Modifiers 'None' | Should -Be 'Hide'
    }

    It 'maps letters to type-in actions while searching' {
        Convert-CmdPeekKey -Key 'A' -KeyChar 'a' -SearchMode | Should -Be 'Type'
        Convert-CmdPeekKey -Key 'Backspace' -SearchMode | Should -Be 'Backspace'
        Convert-CmdPeekKey -Key 'Enter' -SearchMode | Should -Be 'Enter'
    }
}

Describe 'Update-CmdPeekTuiState' {
    It 'moves the selection down and up' {
        $state = New-CmdPeekTuiState
        $state = Update-CmdPeekTuiState -State $state -Action 'Down' -ViewCount 10
        $state.Selected | Should -Be 1
        $state = Update-CmdPeekTuiState -State $state -Action 'Up' -ViewCount 10
        $state.Selected | Should -Be 0
    }

    It 'opens search mode and types into the query' {
        $state = New-CmdPeekTuiState
        $state = Update-CmdPeekTuiState -State $state -Action 'Search' -ViewCount 3
        $state.View | Should -Be 'search'
        $state = Update-CmdPeekTuiState -State $state -Action 'Type' -Char 'f' -ViewCount 3
        $state = Update-CmdPeekTuiState -State $state -Action 'Type' -Char 'd' -ViewCount 3
        $state.Query | Should -Be 'fd'
        $state = Update-CmdPeekTuiState -State $state -Action 'Enter' -ViewCount 3
        $state.View | Should -Be 'list'
        $state.Query | Should -Be 'fd'
    }

    It 'toggles the gaps view with g and leaves it with escape' {
        $state = New-CmdPeekTuiState
        $state = Update-CmdPeekTuiState -State $state -Action 'Gaps' -ViewCount 3
        $state.View | Should -Be 'gaps'
        $state = Update-CmdPeekTuiState -State $state -Action 'Escape' -ViewCount 3
        $state.View | Should -Be 'list'
    }

    It 'opens the use-what-you-have view with Have and leaves it with escape' {
        $state = New-CmdPeekTuiState
        $state = Update-CmdPeekTuiState -State $state -Action 'Have' -ViewCount 3
        $state.View | Should -Be 'have'
        $state = Update-CmdPeekTuiState -State $state -Action 'Escape' -ViewCount 3
        $state.View | Should -Be 'list'
    }

    It 'cycles category filter and toggles favorites-only' {
        $state = New-CmdPeekTuiState
        $cats = @('dev-tools', 'media')
        $state = Update-CmdPeekTuiState -State $state -Action 'CategoryFilter' -ViewCount 3 -CategoryList $cats
        $state.Category | Should -Be 'dev-tools'
        $state = Update-CmdPeekTuiState -State $state -Action 'CategoryFilter' -ViewCount 3 -CategoryList $cats
        $state.Category | Should -Be 'media'
        $state = Update-CmdPeekTuiState -State $state -Action 'CategoryFilter' -ViewCount 3 -CategoryList $cats
        $state.Category | Should -Be ''
        $state = Update-CmdPeekTuiState -State $state -Action 'FavoritesFilter' -ViewCount 3
        $state.FavoritesOnly | Should -BeTrue
        $state = Update-CmdPeekTuiState -State $state -Action 'FavoritesFilter' -ViewCount 3
        $state.FavoritesOnly | Should -BeFalse
        $state = Update-CmdPeekTuiState -State $state -Action 'HiddenFilter' -ViewCount 3
        $state.HiddenOnly | Should -BeTrue
        $state = Update-CmdPeekTuiState -State $state -Action 'HiddenFilter' -ViewCount 3
        $state.HiddenOnly | Should -BeFalse
    }
}

Describe 'Update-CmdPeekTuiState hide' {
    It 'requests a hide toggle from the list view' {
        $state = New-CmdPeekTuiState
        $state = Update-CmdPeekTuiState -State $state -Action 'Hide' -ViewCount 3
        $state.HideToggle | Should -BeTrue
    }
}

Describe 'Get-CmdPeekProbeWindow' {
    It 'returns the visible page of rows' {
        $view = 0..9 | ForEach-Object { [pscustomobject]@{ Command = "c$_" } }
        $slice = @(Get-CmdPeekProbeWindow -View $view -Selected 1 -Scroll 0 -PageSize 3)
        $slice.Count | Should -Be 3
        $slice.Command | Should -Be @('c0', 'c1', 'c2')
    }

    It 'includes the selected row even when it is off the current page' {
        $view = 0..9 | ForEach-Object { [pscustomobject]@{ Command = "c$_" } }
        $slice = @(Get-CmdPeekProbeWindow -View $view -Selected 8 -Scroll 0 -PageSize 3)
        $slice.Command | Should -Contain 'c8'
        $slice.Command | Should -Contain 'c0'
        $slice.Count | Should -Be 4
    }

    It 'returns an empty list when the view is empty' {
        @(Get-CmdPeekProbeWindow -View @() -Selected 0 -Scroll 0 -PageSize 5).Count | Should -Be 0
    }
}

Describe 'Get-CmdPeekPadded' {
    It 'keeps category-neighbor intact at width 18' {
        Get-CmdPeekPadded 'category-neighbor' 18 | Should -Be 'category-neighbor '
        Get-CmdPeekPadded 'category-neighbor' 16 | Should -Be 'category-neighbo'
    }
}

Describe 'Write-CmdPeekTuiFrame gaps kind width' {
    It 'pads gap kinds to 18 characters' {
        $src = Join-Path $PSScriptRoot '..\src\Tui.ps1'
        $text = Get-Content -LiteralPath $src -Raw -Encoding UTF8
        $text | Should -Match 'Get-CmdPeekPadded \$g\.Kind 18'
    }
}
