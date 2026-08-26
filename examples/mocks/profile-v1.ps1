# Mock PowerShell profile with the 0.1 cmdpeek hint (scoop/choco/winget only).
# Add-CmdPeekProfileHint upgrades this block in place to the 0.2 wrappers.

$env:EDITOR = 'code'

# BEGIN cmdpeek hint
function Invoke-CmdPeekHint {
    if (Get-Command cmdpeek -ErrorAction SilentlyContinue) {
        cmdpeek -NonInteractive -n 1
    }
}
function scoop {
    $app = Get-Command scoop -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { throw 'scoop not found on PATH' }
    & $app.Source @args
    if ($args.Count -ge 1 -and $args[0] -eq 'install') { Invoke-CmdPeekHint }
}
function choco {
    $app = Get-Command choco -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { throw 'choco not found on PATH' }
    & $app.Source @args
    if ($args.Count -ge 1 -and $args[0] -eq 'install') { Invoke-CmdPeekHint }
}
function winget {
    $app = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { throw 'winget not found on PATH' }
    & $app.Source @args
    if ($args.Count -ge 1 -and $args[0] -eq 'install') { Invoke-CmdPeekHint }
}
# END cmdpeek hint

Set-Alias ll Get-ChildItem
