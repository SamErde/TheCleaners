BeforeAll {
    $PublisherPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../.github/workflows/publish.ps1'
    Add-Type -AssemblyName 'System.IO.Compression'
    Add-Type -AssemblyName 'System.IO.Compression.FileSystem'

    function Get-PublisherFixture {
        <#
    .SYNOPSIS
        Creates a minimal internally consistent publisher fixture.
    #>
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [string]
            $Root,

            [Parameter()]
            [string]
            $Commit = '0123456789abcdef0123456789abcdef01234567'
        )

        $ArtifactPath = Join-Path -Path $Root -ChildPath 'artifact'
        $ArchiveDirectory = Join-Path -Path $Root -ChildPath 'archive'
        $null = New-Item -Path $ArtifactPath -ItemType Directory -Force
        $null = New-Item -Path $ArchiveDirectory -ItemType Directory -Force

        $ModulePath = Join-Path -Path $ArtifactPath -ChildPath 'TheCleaners.psm1'
        Set-Content -LiteralPath $ModulePath -Value '$script:PublisherFixtureLoaded = $true' -Encoding UTF8

        $ManifestPath = Join-Path -Path $ArtifactPath -ChildPath 'TheCleaners.psd1'
        $ManifestText = @"
@{
    RootModule = 'TheCleaners.psm1'
    ModuleVersion = '0.0.15'
    GUID = '743d0916-3fb7-4e36-a550-bac93454a64a'
    Author = 'TheCleaners test fixture'
    Description = 'Isolated publisher safety fixture.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Prerelease = 'beta'
        }
    }
}
"@
        Set-Content -LiteralPath $ManifestPath -Value $ManifestText -Encoding UTF8

        $ArtifactRoot = $ArtifactPath.TrimEnd([char[]]@('\', '/'))
        $FileRecords = @(Get-ChildItem -LiteralPath $ArtifactPath -File -Recurse -Force | Sort-Object -Property FullName | ForEach-Object {
                [pscustomobject]@{
                    Path   = $_.FullName.Substring($ArtifactRoot.Length + 1).Replace('\', '/')
                    Length = $_.Length
                    SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            })

        $ArchiveName = 'TheCleaners_0.0.15.zip'
        $ArchivePath = Join-Path -Path $ArchiveDirectory -ChildPath $ArchiveName
        $Archive = [System.IO.Compression.ZipFile]::Open($ArchivePath, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($FileRecord in $FileRecords) {
                $SourcePath = Join-Path -Path $ArtifactPath -ChildPath ($FileRecord.Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                $Entry = $Archive.CreateEntry($FileRecord.Path, [System.IO.Compression.CompressionLevel]::NoCompression)
                $InputStream = $null
                $OutputStream = $null
                try {
                    $InputStream = [System.IO.File]::OpenRead($SourcePath)
                    $OutputStream = $Entry.Open()
                    $InputStream.CopyTo($OutputStream)
                } finally {
                    if ($null -ne $OutputStream) {
                        $OutputStream.Dispose()
                    }
                    if ($null -ne $InputStream) {
                        $InputStream.Dispose()
                    }
                }
            }
        } finally {
            $Archive.Dispose()
        }

        $ArchiveHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $SidecarPath = "$ArchivePath.sha256"
        Set-Content -LiteralPath $SidecarPath -Value ('{0} *{1}' -f $ArchiveHash, $ArchiveName) -Encoding ASCII

        $ArchiveManifestPath = Join-Path -Path $ArchiveDirectory -ChildPath "$ArchiveName.manifest.json"
        $ArchiveManifest = [ordered]@{
            ModuleName    = 'TheCleaners'
            ModuleVersion = '0.0.15'
            Commit        = $Commit
            Archive       = $ArchiveName
            ArchiveSHA256 = $ArchiveHash
            Files         = $FileRecords
        }
        $ArchiveManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ArchiveManifestPath -Encoding UTF8

        [pscustomobject]@{
            ArtifactPath        = $ArtifactPath
            ArchiveDirectory    = $ArchiveDirectory
            ArchivePath         = $ArchivePath
            SidecarPath         = $SidecarPath
            ArchiveManifestPath = $ArchiveManifestPath
            Commit              = $Commit
            FileRecords         = $FileRecords
        }
    }
}

Describe 'Protected publisher refusal paths' {
    BeforeAll {
        $OriginalRefType = $env:GITHUB_REF_TYPE
        $OriginalRefName = $env:GITHUB_REF_NAME
        $OriginalSha = $env:GITHUB_SHA
    }

    AfterAll {
        $env:GITHUB_REF_TYPE = $OriginalRefType
        $env:GITHUB_REF_NAME = $OriginalRefName
        $env:GITHUB_SHA = $OriginalSha
    }

    BeforeEach {
        $Fixture = Get-PublisherFixture -Root (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid))
        $env:GITHUB_REF_TYPE = 'tag'
        $env:GITHUB_REF_NAME = 'v0.0.15-beta'
        $env:GITHUB_SHA = $Fixture.Commit

        Mock Find-Module { @() }
        Mock Publish-Module { throw 'Publish-Module must be explicitly inspected by the success test.' }
    }

    It 'requires the Gallery API key so an omitted value cannot reach publication' {
        $ApiKeyParameter = (Get-Command -Name $PublisherPath).Parameters['PSGalleryApiKey']
        @($ApiKeyParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -Be 1
        @($ApiKeyParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }).Count | Should -Be 1

        $PowerShell = [powershell]::Create()
        try {
            $null = $PowerShell.AddCommand($PublisherPath)
            $null = $PowerShell.AddParameter('ArtifactPath', $Fixture.ArtifactPath)
            $null = $PowerShell.AddParameter('ArchiveDirectory', $Fixture.ArchiveDirectory)
            { $null = $PowerShell.Invoke() } | Should -Throw -ExpectedMessage '*missing mandatory parameters: PSGalleryApiKey*'
        } finally {
            $PowerShell.Dispose()
        }

        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a whitespace Gallery API key before publication' {
        {
            & $PublisherPath -PSGalleryApiKey '   ' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*requires a nonblank API key*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a branch ref before publication' {
        $env:GITHUB_REF_TYPE = 'branch'

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*requires a tag ref*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a malformed release tag before publication' {
        $env:GITHUB_REF_NAME = 'release-0.0.15-beta'

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*requires a release tag*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a tag whose version differs from the module manifest' {
        $env:GITHUB_REF_NAME = 'v0.0.16-beta'

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*does not match module version*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a tag whose prerelease differs from the module manifest' {
        $env:GITHUB_REF_NAME = 'v0.0.15-alpha'

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*does not match manifest prerelease*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a missing workflow commit before publication' {
        Remove-Item Env:GITHUB_SHA

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*requires the exact workflow commit*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a malformed workflow commit before publication' {
        $env:GITHUB_SHA = 'not-a-commit'

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*requires the exact workflow commit*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a valid workflow commit that differs from the archive manifest' {
        $env:GITHUB_SHA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*manifest commit does not match*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a missing archive content manifest' {
        Remove-Item -LiteralPath $Fixture.ArchiveManifestPath -Force

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*Expected exactly one archive content manifest*found 0*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects multiple archive content manifests' {
        Copy-Item -LiteralPath $Fixture.ArchiveManifestPath -Destination (Join-Path -Path $Fixture.ArchiveDirectory -ChildPath 'duplicate.manifest.json')

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*Expected exactly one archive content manifest*found 2*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects mutated archive bytes before opening the archive' {
        Add-Content -LiteralPath $Fixture.ArchivePath -Value 'mutation' -Encoding ASCII

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*archive digest does not match*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a mutated archive sidecar' {
        Set-Content -LiteralPath $Fixture.SidecarPath -Value ('0' * 64 + ' *TheCleaners_0.0.15.zip') -Encoding ASCII

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*sidecar does not match*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects artifact mutation after the archive was produced' {
        Add-Content -LiteralPath (Join-Path -Path $Fixture.ArtifactPath -ChildPath 'TheCleaners.psm1') -Value '# mutation' -Encoding UTF8

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*Artifact digest mismatch*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects an artifact with an unrecorded extra file' {
        Set-Content -LiteralPath (Join-Path -Path $Fixture.ArtifactPath -ChildPath 'unexpected.txt') -Value 'extra' -Encoding ASCII

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*artifact file set does not match*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'rejects a version that already exists in the selected repository' {
        Mock Find-Module { [pscustomobject]@{ Name = 'TheCleaners'; Version = '0.0.15-beta' } }

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*already exists in*'
        Should -Invoke Find-Module -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'TheCleaners' -and $RequiredVersion -eq '0.0.15-beta' -and $AllowPrerelease -and $Repository -eq 'PSGallery'
        }
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'fails closed when the duplicate-version query fails' {
        Mock Find-Module {
            $Exception = [System.InvalidOperationException]::new('repository unavailable')
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new($Exception, 'RepositoryUnavailable', [System.Management.Automation.ErrorCategory]::ConnectionError, 'PSGallery')
            throw $ErrorRecord
        }

        {
            & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*Could not verify whether TheCleaners version*repository unavailable*'
        Should -Invoke Find-Module -Times 1 -Exactly
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'refuses PSGallery as a local rehearsal repository' {
        {
            & $PublisherPath -LocalRehearsal -LocalRepository 'PSGallery' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*requires an explicit switch and a separate local repository*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'refuses an HTTP local rehearsal repository location' {
        Mock Get-PSRepository {
            [pscustomobject]@{
                SourceLocation  = 'https://packages.example.invalid/source'
                PublishLocation = 'https://packages.example.invalid/source'
            }
        }

        {
            & $PublisherPath -LocalRehearsal -LocalRepository 'FixtureFeed' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*refuses network, URI, and relative repository locations*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'refuses a UNC local rehearsal repository location' {
        Mock Get-PSRepository {
            [pscustomobject]@{
                SourceLocation  = '\\server\share\source'
                PublishLocation = '\\server\share\source'
            }
        }

        {
            & $PublisherPath -LocalRehearsal -LocalRepository 'FixtureFeed' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*refuses network, URI, and relative repository locations*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'refuses different local source and publish directories' {
        $SourceLocation = Join-Path -Path $TestDrive -ChildPath 'source-feed'
        $PublishLocation = Join-Path -Path $TestDrive -ChildPath 'publish-feed'
        $null = New-Item -Path $SourceLocation -ItemType Directory
        $null = New-Item -Path $PublishLocation -ItemType Directory
        Mock Get-PSRepository {
            [pscustomobject]@{
                SourceLocation  = $SourceLocation
                PublishLocation = $PublishLocation
            }
        }

        {
            & $PublisherPath -LocalRehearsal -LocalRepository 'FixtureFeed' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*requires identical source and publish directories*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'refuses a local repository represented by a reparse-point directory' {
        $RepositoryLocation = Join-Path -Path $TestDrive -ChildPath 'reparse-feed'
        Mock Get-PSRepository {
            [pscustomobject]@{
                SourceLocation  = $RepositoryLocation
                PublishLocation = $RepositoryLocation
            }
        }
        Mock Get-Item {
            [pscustomobject]@{
                PSProvider    = [pscustomobject]@{ Name = 'FileSystem' }
                PSIsContainer = $true
                FullName      = $RepositoryLocation
                Attributes    = [System.IO.FileAttributes]::Directory -bor [System.IO.FileAttributes]::ReparsePoint
                Parent        = $null
            }
        } -ParameterFilter { $LiteralPath -eq $RepositoryLocation }

        {
            & $PublisherPath -LocalRehearsal -LocalRepository 'FixtureFeed' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory
        } | Should -Throw -ExpectedMessage '*refuses reparse-point repository ancestry*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'publishes one verified staged copy whose bytes match the tested artifact' {
        $ExpectedArtifactPath = $Fixture.ArtifactPath
        $PublishInspection = [ordered]@{
            PathIsStaged   = $false
            FileSetMatches = $false
            HashesMatch    = $false
            Repository     = $null
            ApiKey         = $null
        }
        Mock Publish-Module {
            $ArtifactRoot = $ExpectedArtifactPath.TrimEnd([char[]]@('\', '/'))
            $StagedRoot = $Path.TrimEnd([char[]]@('\', '/'))
            $ArtifactFiles = @(Get-ChildItem -LiteralPath $ExpectedArtifactPath -File -Recurse -Force | ForEach-Object {
                    $_.FullName.Substring($ArtifactRoot.Length + 1).Replace('\', '/')
                } | Sort-Object)
            $StagedFiles = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force | ForEach-Object {
                    $_.FullName.Substring($StagedRoot.Length + 1).Replace('\', '/')
                } | Sort-Object)
            $Differences = @(Compare-Object -ReferenceObject $ArtifactFiles -DifferenceObject $StagedFiles)
            $HashesMatch = $true
            foreach ($RelativePath in $ArtifactFiles) {
                $ArtifactFile = Join-Path -Path $ExpectedArtifactPath -ChildPath ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                $StagedFile = Join-Path -Path $Path -ChildPath ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                if ((Get-FileHash -LiteralPath $ArtifactFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $StagedFile -Algorithm SHA256).Hash) {
                    $HashesMatch = $false
                }
            }
            $PublishInspection.PathIsStaged = $Path -ne $ExpectedArtifactPath -and [System.IO.Path]::GetFileName($Path) -eq 'TheCleaners'
            $PublishInspection.FileSetMatches = $Differences.Count -eq 0
            $PublishInspection.HashesMatch = $HashesMatch
            $PublishInspection.Repository = $Repository
            $PublishInspection.ApiKey = $NuGetApiKey
        }

        & $PublisherPath -PSGalleryApiKey 'fixture-key' -ArtifactPath $Fixture.ArtifactPath -ArchiveDirectory $Fixture.ArchiveDirectory

        Should -Invoke Find-Module -Times 1 -Exactly
        Should -Invoke Publish-Module -Times 1 -Exactly
        $PublishInspection.PathIsStaged | Should -BeTrue
        $PublishInspection.FileSetMatches | Should -BeTrue
        $PublishInspection.HashesMatch | Should -BeTrue
        $PublishInspection.Repository | Should -Be 'PSGallery'
        $PublishInspection.ApiKey | Should -Be 'fixture-key'
    }
}
