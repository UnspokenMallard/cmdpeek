#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'New-CmdPeekReleaseArchive' {
    It 'writes a zip whose SHA256 matches the sidecar JSON' {
        $repo = Join-Path $PSScriptRoot '..'
        $out = Join-Path $TestDrive 'dist'
        $script = Join-Path (Join-Path $repo 'scripts') 'New-CmdPeekReleaseArchive.ps1'
        $result = @(
            & $script -RepoRoot $repo -OutputDirectory $out -Version '0.0.0-test'
        ) | Select-Object -Last 1
        $result | Should -Not -BeNullOrEmpty
        $zip = Join-Path $out 'cmdpeek-win-x64-v0.0.0-test.zip'
        Test-Path -LiteralPath $zip | Should -BeTrue
        $infoPath = Join-Path $out 'cmdpeek-win-x64.sha256.json'
        Test-Path -LiteralPath $infoPath | Should -BeTrue
        $info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToUpperInvariant()
        $info.installerSha256 | Should -Be $hash
        $result.InstallerSha256 | Should -Be $hash
        $info.packageVersion | Should -Be '0.0.0-test'
    }
}
