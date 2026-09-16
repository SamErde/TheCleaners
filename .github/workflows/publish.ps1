<#
.SYNOPSIS
    Publish one already-tested TheCleaners artifact.
.DESCRIPTION
    Refuse source-directory publication, require a release tag whose version
    matches the module manifest, verify the archive manifest/hash, and refuse a
    duplicate Gallery version. The protected workflow environment supplies the
    API key; this script does not create tags or build a second artifact.
.PARAMETER PSGalleryApiKey
    PowerShell Gallery API key.
.PARAMETER ArtifactPath
    Exact source-layout module directory produced by the build.
.PARAMETER ArchiveDirectory
    Directory containing the content manifest produced beside the tested archive.
.EXAMPLE
    ./.github/workflows/publish.ps1 -PSGalleryApiKey $env:PSGALLERY_API_KEY
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $PSGalleryApiKey,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $ArtifactPath = './src/Artifacts',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $ArchiveDirectory = './src/Archive'
)

$ErrorActionPreference = 'Stop'
$ResolvedArtifactPath = (Resolve-Path -LiteralPath $ArtifactPath).Path
if ([System.IO.Path]::GetFileName($ResolvedArtifactPath) -eq 'TheCleaners' -and $ResolvedArtifactPath -like '*\src\TheCleaners') {
    throw 'Refusing to publish the source directory. Pass the exact built artifact directory.'
}

$ManifestPath = Join-Path -Path $ResolvedArtifactPath -ChildPath 'TheCleaners.psd1'
$ModuleManifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
if ([string]$env:GITHUB_REF_TYPE -ne 'tag') {
    throw "Publishing requires a tag ref; GITHUB_REF_TYPE was '$($env:GITHUB_REF_TYPE)'."
}
$Tag = [string]$env:GITHUB_REF_NAME
if ($Tag -notmatch '^v(?<Version>\d+\.\d+\.\d+)(-(?<Prerelease>[A-Za-z0-9.-]+))?$') {
    throw "Publishing requires a release tag such as v1.0.0 or v1.0.0-beta; GITHUB_REF_NAME was '$Tag'."
}
if ([string]$ModuleManifest.Version -ne $Matches.Version) {
    throw "Release tag version '$($Matches.Version)' does not match module version '$($ModuleManifest.Version)'."
}
$ManifestPrerelease = [string]$ModuleManifest.PrivateData.PSData.Prerelease
if ([string]$Matches.Prerelease -ne $ManifestPrerelease) {
    throw "Release tag prerelease '$($Matches.Prerelease)' does not match manifest prerelease '$ManifestPrerelease'."
}

$ArchiveManifests = @(Get-ChildItem -LiteralPath $ArchiveDirectory -Filter '*.manifest.json' -File)
if ($ArchiveManifests.Count -ne 1) {
    throw "Expected exactly one archive content manifest under '$ArchiveDirectory'; found $($ArchiveManifests.Count)."
}
$ArchiveManifest = Get-Content -LiteralPath $ArchiveManifests[0].FullName -Raw | ConvertFrom-Json
if ($ArchiveManifest.ModuleName -ne 'TheCleaners' -or [string]$ArchiveManifest.ModuleVersion -ne [string]$ModuleManifest.Version) {
    throw 'The archive manifest does not describe the artifact manifest.'
}
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -and $ArchiveManifest.Commit -ne $env:GITHUB_SHA) {
    throw 'The archive manifest commit does not match the workflow commit.'
}

$ArchiveName = [string]$ArchiveManifest.Archive
if ([string]::IsNullOrWhiteSpace($ArchiveName) -or [System.IO.Path]::GetFileName($ArchiveName) -ne $ArchiveName) {
    throw 'The archive manifest contains an invalid archive name.'
}
$ArchivePath = Join-Path -Path $ArchiveManifests[0].DirectoryName -ChildPath $ArchiveName
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "The tested archive is missing: $ArchivePath"
}
$ArchiveHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ArchiveHash -ne [string]$ArchiveManifest.ArchiveSHA256) {
    throw 'The tested archive digest does not match its content manifest.'
}
$ArchiveSidecarPath = "$ArchivePath.sha256"
if (-not (Test-Path -LiteralPath $ArchiveSidecarPath -PathType Leaf)) {
    throw "The tested archive sidecar is missing: $ArchiveSidecarPath"
}
$ExpectedSidecar = '{0} *{1}' -f $ArchiveHash, $ArchiveName
if ((Get-Content -LiteralPath $ArchiveSidecarPath -Raw).Trim() -ne $ExpectedSidecar) {
    throw 'The tested archive SHA-256 sidecar does not match the archive.'
}

Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
$Archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
try {
    $ArchiveEntries = @($Archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | ForEach-Object { $_.FullName.Replace('\', '/') } | Sort-Object)
    $ExpectedEntries = @($ArchiveManifest.Files | ForEach-Object { [string]$_.Path } | Sort-Object)
    $EntryDifferences = @(Compare-Object -ReferenceObject $ExpectedEntries -DifferenceObject $ArchiveEntries)
    if ($EntryDifferences.Count -gt 0) {
        throw 'The tested archive entries do not match its content manifest.'
    }

    foreach ($FileRecord in @($ArchiveManifest.Files)) {
        $ExpectedEntryPath = [string]$FileRecord.Path
        $ArchiveEntry = @($Archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq $ExpectedEntryPath }) | Select-Object -First 1
        if ($null -eq $ArchiveEntry) {
            throw "The tested archive is missing a manifest file: $ExpectedEntryPath"
        }
        if ([int64]$ArchiveEntry.Length -ne [int64]$FileRecord.Length) {
            throw "Archive length mismatch: $ExpectedEntryPath"
        }
        $EntryStream = $null
        try {
            $EntryStream = $ArchiveEntry.Open()
            $EntryHash = (Get-FileHash -InputStream $EntryStream -Algorithm SHA256).Hash.ToLowerInvariant()
        } finally {
            if ($null -ne $EntryStream) {
                $EntryStream.Dispose()
            }
        }
        if ($EntryHash -ne [string]$FileRecord.SHA256) {
            throw "Archive digest mismatch: $ExpectedEntryPath"
        }
    }
} finally {
    $Archive.Dispose()
}

$ArtifactRoot = $ResolvedArtifactPath.TrimEnd([char[]]@('\', '/'))
$ExpectedArtifactFiles = @($ArchiveManifest.Files | ForEach-Object { [string]$_.Path } | Sort-Object)
$ActualArtifactFiles = @(Get-ChildItem -LiteralPath $ResolvedArtifactPath -File -Recurse -Force | ForEach-Object {
        $_.FullName.Substring($ArtifactRoot.Length + 1).Replace('\', '/')
    } | Sort-Object)
$ArtifactFileDifferences = @(Compare-Object -ReferenceObject $ExpectedArtifactFiles -DifferenceObject $ActualArtifactFiles)
if ($ArtifactFileDifferences.Count -gt 0) {
    throw 'The artifact file set does not match its content manifest.'
}

foreach ($FileRecord in @($ArchiveManifest.Files)) {
    $ArtifactFile = Join-Path -Path $ResolvedArtifactPath -ChildPath ($FileRecord.Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $ArtifactFile -PathType Leaf)) {
        throw "Artifact file from the tested manifest is missing: $($FileRecord.Path)"
    }
    $ActualHash = (Get-FileHash -LiteralPath $ArtifactFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ActualHash -ne [string]$FileRecord.SHA256) {
        throw "Artifact digest mismatch: $($FileRecord.Path)"
    }
}

$GalleryVersion = [string]$ModuleManifest.Version
if (-not [string]::IsNullOrWhiteSpace($ManifestPrerelease)) {
    $GalleryVersion = '{0}-{1}' -f $GalleryVersion, $ManifestPrerelease
}
try {
    $Existing = @(Find-Module -Name TheCleaners -RequiredVersion $GalleryVersion -AllowPrerelease -Repository PSGallery -ErrorAction Stop)
} catch {
    if ([string]$_.FullyQualifiedErrorId -like 'NoMatchFoundForCriteria*') {
        $Existing = @()
    } else {
        throw "Could not verify whether TheCleaners version '$GalleryVersion' already exists in PSGallery: $($_.Exception.Message)"
    }
}
if ($Existing.Count -gt 0) {
    throw "TheCleaners version '$GalleryVersion' already exists in PSGallery."
}

$PublishRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('TheCleaners-Publish-{0}' -f ([guid]::NewGuid().Guid))
$PublishPath = Join-Path -Path $PublishRoot -ChildPath 'TheCleaners'
try {
    $null = New-Item -Path $PublishPath -ItemType Directory -Force -ErrorAction Stop
    foreach ($ArtifactItem in @(Get-ChildItem -LiteralPath $ResolvedArtifactPath -Force)) {
        Copy-Item -LiteralPath $ArtifactItem.FullName -Destination $PublishPath -Recurse -Force -ErrorAction Stop
    }

    $StagedManifestPath = Join-Path -Path $PublishPath -ChildPath 'TheCleaners.psd1'
    $StagedManifest = Test-ModuleManifest -Path $StagedManifestPath -ErrorAction Stop
    if ($StagedManifest.Name -ne $ModuleManifest.Name -or [string]$StagedManifest.Version -ne [string]$ModuleManifest.Version) {
        throw 'The staged publish directory does not contain the exact tested module manifest.'
    }
    $StagedRoot = $PublishPath.TrimEnd([char[]]@('\', '/'))
    $ActualStagedFiles = @(Get-ChildItem -LiteralPath $PublishPath -File -Recurse -Force | ForEach-Object {
            $_.FullName.Substring($StagedRoot.Length + 1).Replace('\', '/')
        } | Sort-Object)
    $StagedFileDifferences = @(Compare-Object -ReferenceObject $ExpectedArtifactFiles -DifferenceObject $ActualStagedFiles)
    if ($StagedFileDifferences.Count -gt 0) {
        throw 'The staged publish directory does not contain the exact tested artifact file set.'
    }
    foreach ($FileRecord in @($ArchiveManifest.Files)) {
        $StagedFile = Join-Path -Path $PublishPath -ChildPath ($FileRecord.Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $StagedHash = (Get-FileHash -LiteralPath $StagedFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($StagedHash -ne [string]$FileRecord.SHA256) {
            throw "Staged artifact digest mismatch: $($FileRecord.Path)"
        }
    }

    Publish-Module -Path $PublishPath -NuGetApiKey $PSGalleryApiKey -Repository PSGallery -ErrorAction Stop
} finally {
    if (Test-Path -LiteralPath $PublishRoot) {
        Remove-Item -LiteralPath $PublishRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
