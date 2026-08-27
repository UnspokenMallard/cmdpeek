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

    It 'updates winget, scoop, and chocolatey manifests in a fake repo' {
        $srcRepo = Join-Path $PSScriptRoot '..'
        $fake = Join-Path $TestDrive 'release-repo'
        New-Item -ItemType Directory -Force -Path (Join-Path $fake 'src') | Out-Null
        Copy-Item -Path (Join-Path $srcRepo 'src\*') -Destination (Join-Path $fake 'src') -Recurse -Force
        foreach ($name in @('examples', 'scoop', 'winget', 'chocolatey', 'scripts')) {
            $from = Join-Path $srcRepo $name
            if (Test-Path -LiteralPath $from) {
                Copy-Item -Path $from -Destination (Join-Path $fake $name) -Recurse -Force
            }
        }
        foreach ($name in @('install.ps1', 'LICENSE', 'README.md', 'cmdpeek.cmd')) {
            $from = Join-Path $srcRepo $name
            if (Test-Path -LiteralPath $from) {
                Copy-Item -LiteralPath $from -Destination (Join-Path $fake $name) -Force
            }
        }
        $out = Join-Path $TestDrive 'release-dist'
        $script = Join-Path (Join-Path $fake 'scripts') 'New-CmdPeekReleaseArchive.ps1'
        $null = & $script -RepoRoot $fake -OutputDirectory $out -Version '9.9.9-test' -UpdateManifest
        $hash = (Get-FileHash -LiteralPath (Join-Path $out 'cmdpeek-win-x64-v9.9.9-test.zip') -Algorithm SHA256).Hash.ToUpperInvariant()
        $winget = Get-Content -LiteralPath (Join-Path (Join-Path $fake 'winget') 'manifest.yaml') -Raw -Encoding UTF8
        $winget | Should -Match 'PackageVersion: 9.9.9-test'
        $winget | Should -Match $hash
        $scoop = Get-Content -LiteralPath (Join-Path (Join-Path $fake 'scoop') 'cmdpeek.json') -Raw -Encoding UTF8
        $scoop | Should -Match '"version": "9.9.9-test"'
        $scoop | Should -Match ($hash.ToLowerInvariant())
        $scoop | Should -Match 'cmdpeek.cmd'
        $scoop | Should -Not -Match 'extract_dir'
        $nuspec = Get-Content -LiteralPath (Join-Path (Join-Path $fake 'chocolatey') 'cmdpeek.nuspec') -Raw -Encoding UTF8
        $nuspec | Should -Match '<version>9.9.9-test</version>'
        { $null = $scoop | ConvertFrom-Json } | Should -Not -Throw
    }
}
