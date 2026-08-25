@{
    RootModule        = 'cmdpeek.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '8f3c2a91-4e6b-4d7a-9c1e-2b8f6a0d5e31'
    Author            = 'cmdpeek contributors'
    CompanyName       = 'cmdpeek'
    Copyright         = '(c) cmdpeek contributors. MIT License.'
    Description       = 'Show the most recently installed CLI commands from Chocolatey, Scoop, and WinGet, with common usage examples.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-CmdPeekPackageManager'
        'Get-CmdPeekPackageManagerInstallHint'
        'Get-CmdPeekInstalledPackage'
        'Get-CmdPeekCommandHistory'
        'Find-CmdPeekMissingCommand'
        'Search-CmdPeekCommand'
        'Select-CmdPeekExactCommand'
        'Get-CmdPeekState'
        'Save-CmdPeekState'
        'Set-CmdPeekFavorite'
        'Set-CmdPeekHidden'
        'Set-CmdPeekPreferredPackageManager'
        'Export-CmdPeekState'
        'Import-CmdPeekState'
        'Get-CmdPeekUsageExample'
        'Get-CmdPeekExampleCatalog'
        'Get-CmdPeekCatalogKits'
        'Invoke-CmdPeek'
        'Invoke-CmdPeekInteractive'
        'Format-CmdPeekQuickOutput'
        'Install-CmdPeekTrackedPackage'
        'Get-CmdPeekGap'
        'Get-CmdPeekInventory'
        'ConvertTo-CmdPeekSnapshot'
        'Add-CmdPeekProfileHint'
        'Convert-CmdPeekSince'
        'Select-CmdPeekJustInstalled'
        'Get-CmdPeekRusty'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('windows', 'cli', 'scoop', 'chocolatey', 'winget', 'packages')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/cmdpeek/cmdpeek'
            ReleaseNotes = 'Initial public release.'
        }
    }
}
