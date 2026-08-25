#Requires -Version 5.1
Set-StrictMode -Version Latest

function Format-CmdPeekDate {
    param($Value)
    if (-not $Value) { return '' }
    try {
        return ([datetime]$Value).ToString('yyyy-MM-dd')
    }
    catch {
        return [string]$Value
    }
}

function Format-CmdPeekQuickOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [int]$ExampleCount = 3,
        [string]$Header,
        [switch]$CheatSheet,
        [switch]$Rusty
    )

    $items = @($History)
    if ($items.Count -eq 0) {
        if ($Rusty) {
            return "No rusty tools.`n"
        }
        return "No installed commands found.`nInstall packages with scoop, choco, or winget, then run cmdpeek again."
    }

    if ($ExampleCount -lt 1) { $ExampleCount = 3 }

    $display = foreach ($row in $items) {
        $raw = @()
        if ($row.PSObject.Properties['Usages'] -and $row.Usages) {
            $raw = @($row.Usages)
        }
        [pscustomobject]@{
            Row    = $row
            Usages = @(Select-CmdPeekDisplayUsage -Usage $raw -Count $ExampleCount)
        }
    }

    $commentColumn = 0
    $allParts = @(
        $display |
            ForEach-Object { $_.Usages } |
            ForEach-Object { Split-CmdPeekUsage -Usage $_ }
    )
    if ($allParts.Count -gt 0) {
        $commentColumn = ($allParts | ForEach-Object { $_.Command.Length } | Measure-Object -Maximum).Maximum
    }

    $lines = New-Object System.Collections.Generic.List[string]
    if (-not $CheatSheet) {
        if ($Header) {
            $lines.Add($Header)
        }
        elseif ($Rusty) {
            $lines.Add('Rusty tools (not in recent history):')
        }
        else {
            $lines.Add("Last $($items.Count) installed commands:")
        }
        $lines.Add('')
    }

    $index = 1
    foreach ($entry in @($display)) {
        $row = $entry.Row
        if ($CheatSheet -or $Rusty) {
            $title = '{0} ({1})' -f $row.Command, $row.PackageManager
        }
        else {
            $title = '{0}. {1} ({2})' -f $index, $row.Command, $row.PackageManager
        }
        if ($row.PSObject.Properties['OnPath'] -and -not $row.OnPath) {
            $title += '  not on PATH'
        }
        $lines.Add($title)
        $last = ''
        if ($row.PSObject.Properties['LastLine'] -and $row.LastLine) { $last = [string]$row.LastLine }
        elseif ($row.PSObject.Properties['lastLine'] -and $row.lastLine) { $last = [string]$row.lastLine }
        if ($Rusty -and $last) { $lines.Add(('   last: {0}' -f $last)) }
        $aligned = @(Format-CmdPeekAlignedUsage -Usage $entry.Usages -Count $ExampleCount -CommentColumn $commentColumn)
        foreach ($usage in $aligned) {
            $lines.Add(('   -  {0}' -f $usage))
        }
        if (-not $CheatSheet -and -not $Rusty -and $row.PSObject.Properties['Shims'] -and $row.Shims -and @($row.Shims).Count -gt 0) {
            $lines.Add(('   also: {0}' -f ((@($row.Shims) -join ', '))))
        }
        if ($CheatSheet) {
            $missing = @()
            if ($row.PSObject.Properties['MissingRelated'] -and $row.MissingRelated) {
                $missing = @($row.MissingRelated | Where-Object { $_ })
            }
            if ($missing.Count -gt 0) {
                $lines.Add(('   gaps: {0}' -f ($missing -join ', ')))
            }
        }
        elseif (-not $Rusty -and $row.PSObject.Properties['Related'] -and $row.Related -and @($row.Related).Count -gt 0) {
            $lines.Add(('   suggestions: {0}' -f ((@($row.Related) | Select-Object -First 3) -join ', ')))
        }
        $lines.Add('')
        $index++
    }

    return ($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
}

function Copy-CmdPeekText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    try {
        if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value $Text
            return $true
        }
        Set-Clipboard -Value $Text
        return $true
    }
    catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            [System.Windows.Forms.Clipboard]::SetText($Text)
            return $true
        }
        catch {
            return $false
        }
    }
}

function Read-CmdPeekChoice {
    param([string]$Prompt)
    return (Read-Host $Prompt)
}

function Show-CmdPeekDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Row
    )

    while ($true) {
        Clear-Host
        $date = Format-CmdPeekDate -Value $row.InstallDate
        $star = $(if ($Row.Favorite) { '*' } else { '' })
        $hiddenNote = $(if ($Row.PSObject.Properties['Hidden'] -and $Row.Hidden) { '  [hidden from -n]' } else { '' })
        Write-Host ("{0}{1} (installed via {2} on {3}){4}" -f $Row.Command, $star, $Row.PackageManager, $date, $hiddenNote) -ForegroundColor Cyan
        Write-Host ''
        Write-Host 'Common Usages:' -ForegroundColor Yellow
        $usages = @()
        if ($Row.PSObject.Properties['Usages']) { $usages = @($Row.Usages) }
        if ($usages.Count -eq 0) { Write-Host '   (none)' }
        $n = 1
        foreach ($usage in $usages) {
            Write-Host ('   [{0}] {1}' -f $n, $usage)
            $n++
        }

        if ($Row.PSObject.Properties['Related'] -and $Row.Related -and @($Row.Related).Count -gt 0) {
            Write-Host ''
            Write-Host ('Related: {0}' -f ($Row.Related -join ', ')) -ForegroundColor DarkGray
        }

        Write-Host ''
        Write-Host 'Actions:' -ForegroundColor Yellow
        Write-Host '  [C] Copy example to clipboard'
        Write-Host '  [R] Run this command'
        Write-Host '  [B] Back to list'
        Write-Host '  [Q] Quit'
        Write-Host ''

        $key = Read-Host '>'
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $choice = $key.Trim()

        if ($choice -match '^[Qq]$') { return 'quit' }
        if ($choice -match '^[Bb]$') { return 'back' }

        if ($choice -match '^[Cc]$') {
            if ($usages.Count -eq 0) { continue }
            $pick = Read-Host 'Example number to copy'
            $idx = 0
            if ([int]::TryParse($pick, [ref]$idx) -and $idx -ge 1 -and $idx -le $usages.Count) {
                $text = ($usages[$idx - 1] -split '#')[0].Trim()
                if (Copy-CmdPeekText -Text $text) {
                    Write-Host "Copied: $text" -ForegroundColor Green
                }
                else {
                    Write-Host "Clipboard unavailable. Command:`n$text" -ForegroundColor Yellow
                }
                [void](Read-Host 'Press Enter to continue')
            }
            continue
        }

        if ($choice -match '^[Rr]$') {
            if ($usages.Count -eq 0) { continue }
            $pick = Read-Host 'Example number to run'
            $idx = 0
            if ([int]::TryParse($pick, [ref]$idx) -and $idx -ge 1 -and $idx -le $usages.Count) {
                $text = ($usages[$idx - 1] -split '#')[0].Trim()
                if ($text -match '[<[]') {
                    Write-Host 'That example has placeholders. Copied instead of running.' -ForegroundColor Yellow
                    [void](Copy-CmdPeekText -Text $text)
                    Write-Host $text
                    [void](Read-Host 'Press Enter to continue')
                }
                else {
                    $confirm = Read-Host "Run ``$text``? [y/N]"
                    if ($confirm -match '^[Yy]') {
                        Write-Host ''
                        cmd.exe /c $text
                        [void](Read-Host 'Press Enter to continue')
                    }
                }
            }
            continue
        }

        $idx = 0
        if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $usages.Count) {
            $text = ($usages[$idx - 1] -split '#')[0].Trim()
            if (Copy-CmdPeekText -Text $text) {
                Write-Host "Copied: $text" -ForegroundColor Green
            }
            else {
                Write-Host $text
            }
            [void](Read-Host 'Press Enter to continue')
        }
    }
}

function Invoke-CmdPeekInteractive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$History,
        [object]$State,
        [string]$DataDirectory,
        [scriptblock]$ChoiceReader,
        [AllowEmptyCollection()]
        [object[]]$Gap,
        [hashtable]$Catalog,
        [scriptblock]$HelpRunner
    )

    if (-not $ChoiceReader -and (Test-CmdPeekTuiConsole)) {
        Invoke-CmdPeekTui -History $History -State $State -DataDirectory $DataDirectory -Gap @($Gap) -Catalog $Catalog -HelpRunner $HelpRunner
        return
    }

    if (-not $ChoiceReader) {
        $ChoiceReader = { param($Prompt) Read-Host $Prompt }
    }

    $all = @($History)
    $filter = ''
    $category = ''
    $favoritesOnly = $false

    while ($true) {
        $view = @(Search-CmdPeekCommand -History $all -Query $filter -Category $category -Favorite:$favoritesOnly)
        Clear-Host
        Write-Host 'cmdpeek - Recently Installed Commands' -ForegroundColor Cyan
        Write-Host ''

        if ($filter) { Write-Host ("Filter: {0}" -f $filter) -ForegroundColor DarkGray }
        if ($category) { Write-Host ("Category: {0}" -f $category) -ForegroundColor DarkGray }
        if ($favoritesOnly) { Write-Host 'Showing favorites only' -ForegroundColor DarkGray }

        if ($view.Count -eq 0) {
            Write-Host '  (no commands match)'
        }
        else {
            $i = 1
            foreach ($row in $view) {
                $date = Format-CmdPeekDate -Value $row.InstallDate
                $star = $(if ($row.Favorite) { '*' } else { ' ' })
                if ($row.PSObject.Properties['Hidden'] -and $row.Hidden) { $star = '-' }
                if ($row.Favorite -and $row.PSObject.Properties['Hidden'] -and $row.Hidden) { $star = '+' }
                $line = ('{0} {1,-18} {2,-12} {3}' -f $star, $row.Command, ('({0})' -f $row.PackageManager), $date)
                Write-Host (' [{0}] {1}' -f $i, $line.TrimEnd())
                $i++
            }
        }

        Write-Host ''
        Write-Host '  # Open   / Search   C Category   F Favorite   H Hide   A All   E Export   Q Quit' -ForegroundColor DarkGray
        Write-Host ''

        $choice = & $ChoiceReader '>'
        if ($null -eq $choice) { return }
        $choice = [string]$choice
        if ([string]::IsNullOrWhiteSpace($choice)) { continue }

        $trim = $choice.Trim()
        if ($trim -match '^[Qq]$') { return }

        if ($trim -match '^/') {
            $filter = $trim.Substring(1).Trim()
            if (-not $filter) {
                $filter = [string](& $ChoiceReader 'Search')
            }
            continue
        }

        if ($trim -match '^[Cc]$') {
            $category = [string](& $ChoiceReader 'Category (blank to clear)')
            continue
        }

        if ($trim -match '^[Aa]$') {
            $filter = ''
            $category = ''
            $favoritesOnly = $false
            continue
        }

        if ($trim -match '^[Ee]$') {
            $path = [string](& $ChoiceReader 'Export path')
            if ($path) {
                Export-CmdPeekState -Path $path -DataDirectory $DataDirectory
                Write-Host "Exported to $path" -ForegroundColor Green
                [void](& $ChoiceReader 'Press Enter')
            }
            continue
        }

        if ($trim -match '^[Ff]$') {
            if ($view.Count -eq 0) {
                $favoritesOnly = -not $favoritesOnly
                continue
            }
            $pick = [string](& $ChoiceReader 'Number to toggle favorite (blank = show favorites)')
            if ([string]::IsNullOrWhiteSpace($pick)) {
                $favoritesOnly = -not $favoritesOnly
                continue
            }
            $idx = 0
            if ([int]::TryParse($pick, [ref]$idx) -and $idx -ge 1 -and $idx -le $view.Count) {
                $cmd = $view[$idx - 1].Command
                $nowFav = -not [bool]$view[$idx - 1].Favorite
                if ($State) {
                    $State = Set-CmdPeekFavorite -State $State -Command $cmd -Favorite $nowFav
                    Save-CmdPeekState -State $State -DataDirectory $DataDirectory
                }
                $all = @(Merge-CmdPeekFavorite -History $all -Favorite @($State.Favorites))
            }
            continue
        }

        if ($trim -match '^[Hh]$') {
            if ($view.Count -eq 0) { continue }
            $pick = [string](& $ChoiceReader 'Number to hide/unhide from quick view (-n)')
            if ([string]::IsNullOrWhiteSpace($pick)) { continue }
            $idx = 0
            if ([int]::TryParse($pick, [ref]$idx) -and $idx -ge 1 -and $idx -le $view.Count) {
                $cmd = $view[$idx - 1].Command
                $nowHidden = -not [bool]($view[$idx - 1].PSObject.Properties['Hidden'] -and $view[$idx - 1].Hidden)
                if ($State) {
                    $State = Set-CmdPeekHidden -State $State -Command $cmd -Hidden $nowHidden
                    Save-CmdPeekState -State $State -DataDirectory $DataDirectory
                    $all = @(Merge-CmdPeekHidden -History $all -Hidden @($State.Hidden))
                }
            }
            continue
        }

        $idx = 0
        if ([int]::TryParse($trim, [ref]$idx) -and $idx -ge 1 -and $idx -le $view.Count) {
            $picked = $view[$idx - 1]
            [void](Add-CmdPeekUsageProbe -History @($picked) -Catalog $Catalog -DataDirectory $DataDirectory -HelpRunner $HelpRunner)
            $result = Show-CmdPeekDetail -Row $picked
            if ($result -eq 'quit') { return }
        }
    }
}

function Install-CmdPeekTrackedPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,
        [Parameter(Mandatory)]
        [ValidateSet('chocolatey', 'scoop', 'winget')]
        [string]$PackageManager
    )

    $cmdline = switch ($PackageManager) {
        'scoop' { "scoop install $PackageName" }
        'chocolatey' { "choco install $PackageName -y" }
        'winget' { "winget install --id $PackageName -e --accept-package-agreements --accept-source-agreements" }
    }

    if ($PSCmdlet.ShouldProcess($PackageName, $cmdline)) {
        Write-Host "Running: $cmdline" -ForegroundColor Cyan
        cmd.exe /c $cmdline
        return $LASTEXITCODE
    }

    return 0
}

function Confirm-CmdPeekMissingCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Missing,
        [object[]]$Managers,
        [object]$State,
        [switch]$NonInteractive
    )

    $rows = @($Missing)
    if ($rows.Count -eq 0) { return $State }

    $available = @($Managers | Where-Object { $_.Present } | Select-Object -ExpandProperty Name)
    if ($available.Count -eq 0) {
        $available = @('scoop', 'chocolatey', 'winget')
    }

    foreach ($row in $rows) {
        $pkg = $(if ($row.PSObject.Properties['PackageName'] -and $row.PackageName) { $row.PackageName } else { $row.Command })
        $hint = ($available -join '/')
        if ($NonInteractive) {
            Write-Warning ("Command '{0}' was uninstalled. Reinstall it? Use: cmdpeek -Reinstall {1} -Manager {2}" -f $row.Command, $pkg, $row.PackageManager)
            continue
        }

        $answer = Read-Host ("Command '{0}' was uninstalled. Reinstall it? [Y/n/{1}]" -f $row.Command, $hint)
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]') {
            $manager = $row.PackageManager
            if ($available -notcontains $manager) { $manager = $available[0] }
            [void](Install-CmdPeekTrackedPackage -PackageName $pkg -PackageManager $manager)
            if ($State) {
                $State = Set-CmdPeekPreferredPackageManager -State $State -PackageManager $manager
            }
            continue
        }
        if ($answer -match '^[Nn]') { continue }

        $picked = $answer.Trim().ToLowerInvariant()
        if ($picked -eq 'choco') { $picked = 'chocolatey' }
        if (@('chocolatey', 'scoop', 'winget') -contains $picked) {
            [void](Install-CmdPeekTrackedPackage -PackageName $pkg -PackageManager $picked)
            if ($State) {
                $State = Set-CmdPeekPreferredPackageManager -State $State -PackageManager $picked
            }
        }
    }

    return $State
}

function Show-CmdPeekNoManagerPrompt {
    [CmdletBinding()]
    param(
        [switch]$NonInteractive
    )

    $all = @(Get-CmdPeekPackageManager -All)
    Write-Host 'No package managers found (Chocolatey, Scoop, or WinGet).' -ForegroundColor Yellow
    Write-Host ''
    $i = 1
    foreach ($pm in $all) {
        Write-Host ('[{0}] {1}' -f $i, $pm.Name)
        Write-Host ('    {0}' -f $pm.InstallHint) -ForegroundColor DarkGray
        $i++
    }

    if ($NonInteractive) {
        Write-Host ''
        Write-Host 'Install one of the managers above, then re-run cmdpeek.'
        return
    }

    Write-Host ''
    $choice = Read-Host 'Install which manager? [1/2/3/n]'
    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $all.Count) {
        $hint = $all[$idx - 1].InstallHint
        Write-Host "Running bootstrap for $($all[$idx - 1].Name)..." -ForegroundColor Cyan
        cmd.exe /c $hint
    }
}
