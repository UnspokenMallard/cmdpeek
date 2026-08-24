#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

BeforeAll {
    $src = Join-Path $PSScriptRoot '..\src'
    . (Join-Path $src 'UsageExamples.ps1')
}

Describe 'Get-CmdPeekUsageExample' {
    BeforeAll {
        $script:catalogPath = Join-Path $TestDrive 'usage-examples.json'
        $catalog = @{
            commands = @{
                'yt-dlp' = @{
                    category = 'media'
                    related  = @('ffmpeg')
                    usages   = @(
                        'yt-dlp <URL>                    # Download video'
                        'yt-dlp -f bestaudio <URL>       # Extract audio only'
                    )
                }
                'fd' = @{
                    category = 'dev-tools'
                    usages   = @(
                        'fd <pattern>                    # Find files'
                    )
                }
            }
        }
        $catalog | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:catalogPath -Encoding UTF8
        $script:catalog = Get-CmdPeekExampleCatalog -Path $script:catalogPath
    }

    It 'returns curated usages for a known command' {
        $examples = @(Get-CmdPeekUsageExample -Command 'yt-dlp' -Catalog $script:catalog -Count 2)
        $examples.Count | Should -Be 2
        $examples[0] | Should -Match 'yt-dlp <URL>'
    }

    It 'limits the number of usages' {
        $examples = @(Get-CmdPeekUsageExample -Command 'yt-dlp' -Catalog $script:catalog -Count 1)
        $examples.Count | Should -Be 1
    }

    It 'falls back to a help hint for unknown commands' {
        $examples = @(Get-CmdPeekUsageExample -Command 'some-new-cli' -Catalog $script:catalog)
        $examples.Count | Should -BeGreaterThan 0
        $examples[0] | Should -Match 'some-new-cli'
    }

    It 'looks up category from the catalog' {
        Get-CmdPeekCommandCategory -Command 'yt-dlp' -Catalog $script:catalog | Should -Be 'media'
        Get-CmdPeekCommandCategory -Command 'unknown' -Catalog $script:catalog | Should -Be 'other'
    }

    It 'suggests related tools that are not already installed' {
        $installed = @('yt-dlp')
        $related = @(Get-CmdPeekRelatedCommand -Command 'yt-dlp' -Catalog $script:catalog -InstalledCommand $installed)
        $related | Should -Contain 'ffmpeg'
        $related | Should -Not -Contain 'yt-dlp'
    }
}
