BeforeAll {
    $RepositoryRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    $Workflow = Get-Content -LiteralPath (Join-Path $RepositoryRoot '.github/workflows/Publish.yml') -Raw
    $Match = [regex]::Match($Workflow, '(?ms)^    - name: Verify and publish the exact artifact\r?\n      shell: pwsh\r?\n      run: \|\r?\n(?<Script>.*?)^      env:')
    if (-not $Match.Success) { throw 'Cannot locate the publication approval step.' }
    $ApprovalScript = [scriptblock]::Create(($Match.Groups['Script'].Value -replace '(?m)^        ', ''))
}

Describe 'Concrete archive approval before publication' {
    BeforeEach {
        $PreviousKey = $env:PSGALLERY_API_KEY
        $PreviousDigest = $env:APPROVED_ARCHIVE_SHA256
        $FixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $FixtureRoot 'src/Archive') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $FixtureRoot '.github/workflows') -Force
        # A fixture publisher records reachability; it has no repository or network access.
        Set-Content -LiteralPath (Join-Path $FixtureRoot '.github/workflows/publish.ps1') -Value @'
param($PSGalleryApiKey, $ArtifactPath, $ArchiveDirectory)
Set-Content -LiteralPath ./PublisherReached.txt -Value 'reached'
'@
        $ArchivePath = Join-Path $FixtureRoot 'src/Archive/TheCleaners_0.0.15.zip'
        [System.IO.File]::WriteAllBytes($ArchivePath, [byte[]](1, 2, 3, 4))
        $env:PSGALLERY_API_KEY = 'fixture-key-with-no-authority'
        $env:APPROVED_ARCHIVE_SHA256 = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash
        Push-Location -LiteralPath $FixtureRoot
    }

    AfterEach {
        Pop-Location
        $env:PSGALLERY_API_KEY = $PreviousKey
        $env:APPROVED_ARCHIVE_SHA256 = $PreviousDigest
    }

    It 'refuses a missing publishing credential before reaching the publisher' {
        $env:PSGALLERY_API_KEY = ' '
        { & $ApprovalScript } | Should -Throw '*Configure the PSGALLERY_PUBLISH_API_KEY*'
        Test-Path -LiteralPath ./PublisherReached.txt | Should -BeFalse
    }

    It 'refuses an absent or malformed approved digest' -ForEach @('', 'not-a-digest', ('a' * 63)) {
        $env:APPROVED_ARCHIVE_SHA256 = $_
        { & $ApprovalScript } | Should -Throw '*approved archive SHA-256*'
        Test-Path -LiteralPath ./PublisherReached.txt | Should -BeFalse
    }

    It 'refuses bytes changed after approval' {
        [System.IO.File]::WriteAllBytes($ArchivePath, [byte[]](4, 3, 2, 1))
        { & $ApprovalScript } | Should -Throw '*does not match the approved release digest*'
        Test-Path -LiteralPath ./PublisherReached.txt | Should -BeFalse
    }

    It 'refuses a missing archive' {
        Remove-Item -LiteralPath $ArchivePath
        { & $ApprovalScript } | Should -Throw '*does not match the approved release digest*'
        Test-Path -LiteralPath ./PublisherReached.txt | Should -BeFalse
    }

    It 'refuses multiple candidate archives' {
        Copy-Item -LiteralPath $ArchivePath -Destination ./src/Archive/Unexpected.zip
        { & $ApprovalScript } | Should -Throw '*does not match the approved release digest*'
        Test-Path -LiteralPath ./PublisherReached.txt | Should -BeFalse
    }

    It 'allows the approved archive and ignores the separately tested repeat archive' {
        Copy-Item -LiteralPath $ArchivePath -Destination ./src/Archive/TheCleaners_0.0.15.repeat.zip
        $env:APPROVED_ARCHIVE_SHA256 = $env:APPROVED_ARCHIVE_SHA256.ToLowerInvariant()
        & $ApprovalScript | Out-Null
        Get-Content -LiteralPath ./PublisherReached.txt | Should -Be 'reached'
    }
}

