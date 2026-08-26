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
        $usedAt = $null
        if ($row.PSObject.Properties['LastUsedAt'] -and $row.LastUsedAt) { $usedAt = $row.LastUsedAt }
        elseif ($row.PSObject.Properties['lastUsedAt'] -and $row.lastUsedAt) { $usedAt = $row.lastUsedAt }
        if ($Rusty -and $usedAt) {
            $lines.Add(('   last used: {0}' -f (Format-CmdPeekDate -Value $usedAt)))
        }
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
            if ($row.PSObject.Properties['Version'] -and $row.Version) {
                $lines.Add(('   version: {0}' -f $row.Version))
            }
            if ($row.PSObject.Properties['SubstitutesInstalled'] -and $row.SubstitutesInstalled -and @($row.SubstitutesInstalled).Count -gt 0) {
                $lines.Add(('   you already have: {0}' -f ((@($row.SubstitutesInstalled) -join ', '))))
            }
            if ($row.PSObject.Properties['InstallCommands'] -and $row.InstallCommands -and @($row.InstallCommands).Count -gt 0) {
                $lines.Add(('   install: {0}' -f @($row.InstallCommands)[0]))
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

function Format-CmdPeekTaskOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Result
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('Task: {0}' -f $Result.query))
    $lines.Add('')
    $installed = @($Result.installed)
    if ($installed.Count -gt 0) {
        $lines.Add('You already have:')
        foreach ($hit in $installed) {
            $pm = $(if ($hit.packageManager) { $hit.packageManager } else { 'path' })
            $lines.Add(('  {0} ({1})  {2}' -f $hit.command, $pm, $hit.reason))
            foreach ($u in @($hit.usages | Select-Object -First 2)) {
                $lines.Add(('    -  {0}' -f $u))
            }
        }
        $lines.Add('')
    }
    $missing = @($Result.missing)
    if ($missing.Count -gt 0) {
        $header = $(if ($installed.Count -gt 0) { 'Also in the catalog (not installed):' } else { 'Catalog matches to install:' })
        $lines.Add($header)
        foreach ($hit in $missing) {
            $lines.Add(('  {0}  {1}' -f $hit.command, $hit.reason))
            $install = @($hit.installCommands)
            if ($install.Count -gt 0) {
                $lines.Add(('    install: {0}' -f $install[0]))
            }
            foreach ($u in @($hit.usages | Select-Object -First 1)) {
                $lines.Add(('    -  {0}' -f $u))
            }
        }
        $lines.Add('')
    }
    if ($installed.Count -eq 0 -and $missing.Count -eq 0) {
        $lines.Add('No catalog matches for that task.')
    }
    return (($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
}

function Format-CmdPeekWhyOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Result
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $title = '{0}' -f $Result.command
    if ($Result.installed) { $title += '  installed' } else { $title += '  not installed' }
    if ($Result.onPath) { $title += '  on PATH' }
    if ($Result.onPathManager) { $title += (' via {0}' -f $Result.onPathManager) }
    $lines.Add($title)
    if ($Result.category) { $lines.Add(('  category: {0}' -f $Result.category)) }
    if (@($Result.capabilities).Count -gt 0) { $lines.Add(('  capabilities: {0}' -f ($Result.capabilities -join ', '))) }
    if (@($Result.aliases).Count -gt 0) { $lines.Add(('  aliases: {0}' -f ($Result.aliases -join ', '))) }
    if (@($Result.packageManagers).Count -gt 1) {
        $lines.Add(('  managers: {0}' -f ($Result.packageManagers -join ', ')))
    }
    if (@($Result.substitutesInstalled).Count -gt 0) {
        $lines.Add(('  you already have: {0}' -f ($Result.substitutesInstalled -join ', ')))
    }
    if (@($Result.substitutesMissing).Count -gt 0) {
        $lines.Add(('  alternatives: {0}' -f ($Result.substitutesMissing -join ', ')))
    }
    foreach ($u in @($Result.usages | Select-Object -First 5)) {
        $lines.Add(('   -  {0}' -f $u))
    }
    if (-not $Result.installed -and @($Result.installCommands).Count -gt 0) {
        $lines.Add(('  install: {0}' -f @($Result.installCommands)[0]))
    }
    return (($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
}

function Format-CmdPeekHaveOutput {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$History
    )

    $items = @($History)
    if ($items.Count -eq 0) {
        return "No installed catalog tools match.`n"
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Installed tools you can use:')
    $lines.Add('')
    $currentCat = ''
    foreach ($row in $items) {
        $cat = $(if ($row.PSObject.Properties['Category'] -and $row.Category) { [string]$row.Category } else { 'other' })
        if ($cat -ne $currentCat) {
            $currentCat = $cat
            $lines.Add(('[{0}]' -f $cat))
        }
        $caps = ''
        if ($row.PSObject.Properties['Capabilities'] -and $row.Capabilities) {
            $caps = '  ' + ((@($row.Capabilities) -join ', '))
        }
        $lines.Add(('  {0} ({1}){2}' -f $row.Command, $row.PackageManager, $caps))
        foreach ($u in @($row.Usages | Select-Object -First 1)) {
            $lines.Add(('    -  {0}' -f $u))
        }
    }
    return (($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
}

function Format-CmdPeekGapOutput {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Gap
    )

    $items = @($Gap)
    if ($items.Count -eq 0) {
        return "No gaps.`n"
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Inventory gaps:')
    $lines.Add('')
    foreach ($g in $items) {
        $install = ''
        if ($g.PSObject.Properties['installCommands'] -and $g.installCommands -and @($g.installCommands).Count -gt 0) {
            $install = ('  {0}' -f @($g.installCommands)[0])
        }
        $lines.Add(('  [{0}] {1}  {2}{3}' -f $g.kind, $g.command, $g.reason, $install))
    }
    return (($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
}

function Format-CmdPeekAvailableOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Result
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('Search: {0}' -f $Result.query))
    $lines.Add('')
    $have = @($Result.catalogInstalled)
    if ($have.Count -gt 0) {
        $lines.Add('Already installed:')
        foreach ($hit in $have) {
            $pm = $(if ($hit.packageManager) { $hit.packageManager } else { 'path' })
            $lines.Add(('  {0} ({1})' -f $hit.command, $pm))
        }
        $lines.Add('')
    }
    $miss = @($Result.catalogMissing)
    if ($miss.Count -gt 0) {
        $lines.Add('Not installed (catalog):')
        foreach ($hit in $miss) {
            $line = '  {0}' -f $hit.command
            if ($hit.installCommands -and @($hit.installCommands).Count -gt 0) {
                $line += ('  -> {0}' -f @($hit.installCommands)[0])
            }
            $lines.Add($line)
        }
        $lines.Add('')
    }
    $pm = @($Result.packageManagers)
    if ($pm.Count -gt 0) {
        $lines.Add('Package manager hits:')
        foreach ($hit in $pm) {
            $name = $(if ($hit.PSObject.Properties['name']) { $hit.name } else { [string]$hit })
            $mgr = $(if ($hit.PSObject.Properties['manager']) { $hit.manager } else { '' })
            $lines.Add(('  {0} {1}' -f $name, $mgr))
        }
    }
    if ($have.Count -eq 0 -and $miss.Count -eq 0 -and $pm.Count -eq 0) {
        $lines.Add('No matches.')
    }
    return (($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
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
        [ValidateSet('chocolatey', 'scoop', 'winget', 'pipx', 'npm', 'cargo', 'brew')]
        [string]$PackageManager
    )

    $cmdline = switch ($PackageManager) {
        'scoop' { "scoop install $PackageName" }
        'chocolatey' { "choco install $PackageName -y" }
        'winget' { "winget install --id $PackageName -e --accept-package-agreements --accept-source-agreements" }
        'pipx' { "pipx install $PackageName" }
        'npm' { "npm install -g $PackageName" }
        'cargo' { "cargo install $PackageName" }
        'brew' { "brew install $PackageName" }
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
        $available = @('scoop', 'chocolatey', 'winget', 'pipx', 'npm', 'cargo', 'brew')
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
    Write-Host 'No Chocolatey, Scoop, or WinGet on PATH.' -ForegroundColor Yellow
    Write-Host 'cmdpeek still inventories pipx/npm/cargo/brew when present, plus catalog names already on PATH.' -ForegroundColor DarkGray
    Write-Host ''
    $i = 1
    foreach ($pm in $all) {
        Write-Host ('[{0}] {1}' -f $i, $pm.Name)
        Write-Host ('    {0}' -f $pm.InstallHint) -ForegroundColor DarkGray
        $i++
    }

    if ($NonInteractive) {
        Write-Host ''
        Write-Host 'Install a manager for package recency, or keep using PATH-only discovery.'
        return
    }

    Write-Host ''
    Write-Host 'Press Enter to continue with PATH-only discovery, or pick a manager to bootstrap.'
    $choice = Read-Host ('Install which manager? [1-{0}/n]' -f $all.Count)
    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $all.Count) {
        $hint = $all[$idx - 1].InstallHint
        Write-Host "Running bootstrap for $($all[$idx - 1].Name)..." -ForegroundColor Cyan
        $comSpec = [string]$env:ComSpec
        if (-not [string]::IsNullOrWhiteSpace($comSpec) -and (Test-Path -LiteralPath $comSpec)) {
            & $comSpec /c $hint
        }
        else {
            Write-Host $hint
        }
    }
}
