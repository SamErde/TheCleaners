<#
.SYNOPSIS
    Rehearse exact-artifact publication and acquisition through an isolated local feed.
.DESCRIPTION
    Creates a GUID-named local PowerShellGet repository, launches a fresh instance
    of the current PowerShell host with synthetic tag metadata, invokes the real
    publisher, saves the exact published version into an isolated module root,
    verifies the installed payload and runtime contract, and confirms a second
    publication is refused as a duplicate. It never reads a Gallery credential,
    creates a Git tag, installs globally, or contacts PSGallery for publication.
.PARAMETER ArtifactPath
    Exact built module artifact directory.
.PARAMETER ArchiveDirectory
    Directory containing the tested archive, sidecar, and content manifest.
.PARAMETER OutputPath
    JSON evidence path. Defaults to a unique file in the system temporary directory.
.PARAMETER RehearsalWorker
    Internal switch used only by the fresh child process.
.EXAMPLE
    ./Invoke-LocalPublicationRehearsal.ps1 -ArtifactPath ./src/Artifacts -ArchiveDirectory ./src/Archive -OutputPath ./src/Reports/LocalPublicationRehearsal.json
#>
[CmdletBinding(DefaultParameterSetName = 'Orchestrator')]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ArtifactPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ArchiveDirectory,

    [Parameter(ParameterSetName = 'Orchestrator')]
    [ValidateNotNullOrEmpty()]
    [string]
    $OutputPath = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('TheCleaners-LocalPublicationRehearsal-{0}.json' -f ([guid]::NewGuid().Guid))),

    [Parameter(Mandatory, ParameterSetName = 'Worker', DontShow)]
    [switch]
    $RehearsalWorker,

    [Parameter(Mandatory, ParameterSetName = 'Worker', DontShow)]
    [ValidateNotNullOrEmpty()]
    [string]
    $LocalRepository,

    [Parameter(Mandatory, ParameterSetName = 'Worker', DontShow)]
    [ValidateNotNullOrEmpty()]
    [string]
    $RehearsalRoot,

    [Parameter(Mandatory, ParameterSetName = 'Worker', DontShow)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string]
    $ExpectedCommit,

    [Parameter(Mandatory, ParameterSetName = 'Worker', DontShow)]
    [ValidatePattern('^v\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$')]
    [string]
    $ExpectedTag
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $PSCommandPath
$RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path -Path $ScriptRoot -ChildPath '../..')).Path
$PublisherPath = Join-Path -Path $RepositoryRoot -ChildPath '.github/workflows/publish.ps1'
$CheckerPath = Join-Path -Path $ScriptRoot -ChildPath 'Test-RepositoryModule.ps1'

function Write-RehearsalJson {
    <#
    .SYNOPSIS
        Write deterministic UTF-8 JSON evidence.
    #>
    param (
        [Parameter(Mandatory)]
        [psobject]
        $InputObject,

        [Parameter(Mandatory)]
        [string]
        $Path
    )

    $ResolvedOutputPath = [System.IO.Path]::GetFullPath($Path)
    $OutputDirectory = [System.IO.Path]::GetDirectoryName($ResolvedOutputPath)
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force -ErrorAction Stop
    }
    $Json = $InputObject | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($ResolvedOutputPath, $Json, [System.Text.UTF8Encoding]::new($false))
}

function Get-RehearsalIdentity {
    <#
    .SYNOPSIS
        Resolve and cross-check the tested artifact, tag, and Git identity.
    #>
    param (
        [Parameter(Mandatory)]
        [string]
        $ArtifactDirectory,

        [Parameter(Mandatory)]
        [string]
        $ArchiveRoot
    )

    $ResolvedArtifactPath = (Resolve-Path -LiteralPath $ArtifactDirectory -ErrorAction Stop).Path
    $ResolvedArchiveDirectory = (Resolve-Path -LiteralPath $ArchiveRoot -ErrorAction Stop).Path
    $ArchiveManifests = @(Get-ChildItem -LiteralPath $ResolvedArchiveDirectory -Filter '*.manifest.json' -File)
    if ($ArchiveManifests.Count -ne 1) {
        throw "Expected exactly one archive content manifest; found $($ArchiveManifests.Count)."
    }
    $ArchiveManifest = Get-Content -LiteralPath $ArchiveManifests[0].FullName -Raw | ConvertFrom-Json
    if ($ArchiveManifest.ModuleName -ne 'TheCleaners' -or $ArchiveManifest.Commit -notmatch '^[a-fA-F0-9]{40}$') {
        throw 'The archive manifest does not contain valid TheCleaners commit identity.'
    }

    $ArtifactManifestPath = Join-Path -Path $ResolvedArtifactPath -ChildPath 'TheCleaners.psd1'
    $ArtifactManifest = Test-ModuleManifest -Path $ArtifactManifestPath -ErrorAction Stop
    if ([string]$ArtifactManifest.Version -ne [string]$ArchiveManifest.ModuleVersion) {
        throw 'The artifact and archive manifest versions differ.'
    }
    $Prerelease = [string]$ArtifactManifest.PrivateData.PSData.Prerelease
    $Tag = 'v{0}' -f $ArtifactManifest.Version
    if (-not [string]::IsNullOrWhiteSpace($Prerelease)) {
        $Tag = '{0}-{1}' -f $Tag, $Prerelease
    }

    $GitCommit = (& git -C $RepositoryRoot rev-parse HEAD 2>$null)
    if (-not $? -or $GitCommit -notmatch '^[a-fA-F0-9]{40}$') {
        throw 'Could not establish the current repository commit.'
    }
    $GitCommit = $GitCommit.Trim()
    if ($GitCommit -ne [string]$ArchiveManifest.Commit) {
        throw "The tested artifact commit '$($ArchiveManifest.Commit)' differs from current HEAD '$GitCommit'."
    }
    $TrackedChanges = @(& git -C $RepositoryRoot status --porcelain --untracked-files=no)
    if (-not $? -or $TrackedChanges.Count -gt 0) {
        throw 'Local publication rehearsal requires a clean tracked worktree.'
    }

    [pscustomobject]@{
        ArtifactPath = $ResolvedArtifactPath
        ArchiveDirectory = $ResolvedArchiveDirectory
        ArchiveManifestPath = $ArchiveManifests[0].FullName
        Commit = $GitCommit
        Tag = $Tag
        ModuleVersion = [string]$ArtifactManifest.Version
        Prerelease = $Prerelease
    }
}

function Test-RehearsalRemovalTarget {
    <#
    .SYNOPSIS
        Ensure cleanup is limited to the exact GUID rehearsal directory.
    #>
    param (
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    $FullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
    $TempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
    $Parent = [System.IO.Path]::GetDirectoryName($FullPath)
    $Leaf = [System.IO.Path]::GetFileName($FullPath)
    if ($Parent -ne $TempRoot -or $Leaf -notmatch '^TheCleaners-Publish-Rehearsal-[a-fA-F0-9-]{36}$') {
        throw "Refusing to remove an unexpected rehearsal path: $FullPath"
    }
    $FullPath
}

if ($PSCmdlet.ParameterSetName -eq 'Worker' -and $RehearsalWorker) {
    $WorkerEvidencePath = Join-Path -Path $RehearsalRoot -ChildPath 'WorkerEvidence.json'
    $CheckerEvidencePath = Join-Path -Path $RehearsalRoot -ChildPath 'RepositoryModule.json'
    $SaveRoot = Join-Path -Path $RehearsalRoot -ChildPath 'SavedModules'
    $WorkerEvidence = [ordered]@{
        SchemaVersion = 1
        Status = 'Running'
        Commit = $ExpectedCommit.ToLowerInvariant()
        Tag = $ExpectedTag
        Repository = $LocalRepository
        PublisherCompleted = $false
        SaveCompleted = $false
        CheckerCompleted = $false
        DuplicateRefused = $false
        RepositoryModule = $null
        Error = $null
    }
    $WorkerFailure = $null
    try {
        $env:GITHUB_REF_TYPE = 'tag'
        $env:GITHUB_REF_NAME = $ExpectedTag
        $env:GITHUB_SHA = $ExpectedCommit
        $null = New-Item -Path $SaveRoot -ItemType Directory -Force -ErrorAction Stop
        $PublishParameters = @{
            LocalRehearsal = $true
            LocalRepository = $LocalRepository
            ArtifactPath = $ArtifactPath
            ArchiveDirectory = $ArchiveDirectory
        }
        $null = & $PublisherPath @PublishParameters
        $WorkerEvidence.PublisherCompleted = $true

        $VersionText = $ExpectedTag.Substring(1)
        $SaveParameters = @{
            Name = 'TheCleaners'
            RequiredVersion = $VersionText
            Repository = $LocalRepository
            Path = $SaveRoot
            Force = $true
            ErrorAction = 'Stop'
        }
        if ($VersionText -match '-') {
            $SaveParameters.AllowPrerelease = $true
        }
        Save-Module @SaveParameters
        $WorkerEvidence.SaveCompleted = $true

        $SavedManifests = @(Get-ChildItem -LiteralPath $SaveRoot -Filter 'TheCleaners.psd1' -File -Recurse -Force)
        if ($SavedManifests.Count -ne 1) {
            throw "Expected one saved TheCleaners manifest; found $($SavedManifests.Count)."
        }
        $SavedModulePath = $SavedManifests[0].DirectoryName
        $CheckerParameters = @{
            ModulePath = $SavedModulePath
            ModuleSearchRoot = $SaveRoot
            ArchiveManifestPath = (Get-ChildItem -LiteralPath $ArchiveDirectory -Filter '*.manifest.json' -File).FullName
            ExpectedCommit = $ExpectedCommit
            ExpectedTag = $ExpectedTag
            RepositoryName = $LocalRepository
            OutputPath = $CheckerEvidencePath
        }
        $CheckerEvidence = & $CheckerPath @CheckerParameters
        if ($CheckerEvidence.Status -ne 'Passed') {
            throw 'The repository-installed module checker did not pass.'
        }
        $WorkerEvidence.CheckerCompleted = $true
        $WorkerEvidence.RepositoryModule = $CheckerEvidence

        $DuplicateError = $null
        try {
            $null = & $PublisherPath @PublishParameters
        } catch {
            $DuplicateError = $_
        }
        if ($null -eq $DuplicateError -or $DuplicateError.Exception.Message -notlike "*already exists in '$LocalRepository'*" ) {
            throw 'The second local publication did not produce the expected duplicate-version refusal.'
        }
        $WorkerEvidence.DuplicateRefused = $true
        $WorkerEvidence.Status = 'Passed'
    } catch {
        $WorkerFailure = $_
        $WorkerEvidence.Status = 'Failed'
        $WorkerEvidence.Error = $_.Exception.Message
    } finally {
        Write-RehearsalJson -InputObject $WorkerEvidence -Path $WorkerEvidencePath
    }
    if ($null -ne $WorkerFailure) {
        throw $WorkerFailure
    }
    [pscustomobject]$WorkerEvidence
    return
}

$ResolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$OutputDirectory = [System.IO.Path]::GetDirectoryName($ResolvedOutputPath)
$OutputName = [System.IO.Path]::GetFileNameWithoutExtension($ResolvedOutputPath)
$EvidenceDirectory = Join-Path -Path $OutputDirectory -ChildPath ($OutputName + '-artifacts')
$Identity = $null
$RehearsalRootPath = $null
$RepositoryName = 'TheCleanersLocal-{0}' -f ([guid]::NewGuid().ToString('N'))
$RepositoryRegistered = $false
$WorkerLogPath = $null
$WorkerExitCode = $null
$Failure = $null
$OriginalRefType = $env:GITHUB_REF_TYPE
$OriginalRefName = $env:GITHUB_REF_NAME
$OriginalSha = $env:GITHUB_SHA
$Evidence = [ordered]@{
    SchemaVersion = 1
    Status = 'Running'
    Commit = $null
    Tag = $null
    ModuleVersion = $null
    Prerelease = $null
    Repository = $RepositoryName
    Runtime = [ordered]@{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        PSEdition = $PSVersionTable.PSEdition
        OS = [Environment]::OSVersion.VersionString
        HostExecutable = (Get-Process -Id $PID).Path
    }
    Worker = $null
    Packages = @()
    EvidenceFiles = @()
    Recovery = [ordered]@{
        RepositoryUnregistered = $false
        TemporaryRootRemoved = $false
        EnvironmentRestored = $false
    }
    Error = $null
    Boundary = 'Isolated local-feed rehearsal only; no Git tag, Gallery credential, Gallery publication, global installation, or product cleanup.'
}

try {
    $Identity = Get-RehearsalIdentity -ArtifactDirectory $ArtifactPath -ArchiveRoot $ArchiveDirectory
    $Evidence.Commit = $Identity.Commit
    $Evidence.Tag = $Identity.Tag
    $Evidence.ModuleVersion = $Identity.ModuleVersion
    $Evidence.Prerelease = $Identity.Prerelease

    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $EvidenceDirectory) {
        throw "Refusing to mix rehearsal evidence with an existing path: $EvidenceDirectory"
    }
    $null = New-Item -Path $EvidenceDirectory -ItemType Directory -Force -ErrorAction Stop
    $RehearsalRootPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('TheCleaners-Publish-Rehearsal-{0}' -f ([guid]::NewGuid().Guid))
    $RehearsalRootPath = Test-RehearsalRemovalTarget -Path $RehearsalRootPath
    $FeedPath = Join-Path -Path $RehearsalRootPath -ChildPath 'Feed'
    $null = New-Item -Path $FeedPath -ItemType Directory -Force -ErrorAction Stop
    Register-PSRepository -Name $RepositoryName -SourceLocation $FeedPath -PublishLocation $FeedPath -InstallationPolicy Trusted -ErrorAction Stop
    $RepositoryRegistered = $true

    $CurrentHostPath = (Get-Process -Id $PID).Path
    $WorkerArguments = @(
        '-NoLogo'
        '-NoProfile'
        '-NonInteractive'
        '-File'
        $PSCommandPath
        '-ArtifactPath'
        $Identity.ArtifactPath
        '-ArchiveDirectory'
        $Identity.ArchiveDirectory
        '-RehearsalWorker'
        '-LocalRepository'
        $RepositoryName
        '-RehearsalRoot'
        $RehearsalRootPath
        '-ExpectedCommit'
        $Identity.Commit
        '-ExpectedTag'
        $Identity.Tag
    )
    $WorkerOutput = @(& $CurrentHostPath @WorkerArguments 2>&1)
    $WorkerExitCode = $LASTEXITCODE
    $WorkerLogPath = Join-Path -Path $EvidenceDirectory -ChildPath 'Worker.log'
    $WorkerOutput | Out-File -LiteralPath $WorkerLogPath -Encoding utf8 -Force

    $WorkerEvidencePath = Join-Path -Path $RehearsalRootPath -ChildPath 'WorkerEvidence.json'
    if (Test-Path -LiteralPath $WorkerEvidencePath -PathType Leaf) {
        $WorkerEvidenceDestination = Join-Path -Path $EvidenceDirectory -ChildPath 'WorkerEvidence.json'
        Copy-Item -LiteralPath $WorkerEvidencePath -Destination $WorkerEvidenceDestination -Force -ErrorAction Stop
        $Evidence.Worker = Get-Content -LiteralPath $WorkerEvidencePath -Raw | ConvertFrom-Json
    }
    $CheckerEvidencePath = Join-Path -Path $RehearsalRootPath -ChildPath 'RepositoryModule.json'
    if (Test-Path -LiteralPath $CheckerEvidencePath -PathType Leaf) {
        Copy-Item -LiteralPath $CheckerEvidencePath -Destination (Join-Path -Path $EvidenceDirectory -ChildPath 'RepositoryModule.json') -Force -ErrorAction Stop
    }
    $PublishedPackages = @(Get-ChildItem -LiteralPath $FeedPath -File -Filter '*.nupkg' -Force -ErrorAction SilentlyContinue)
    $PackageEvidence = @()
    foreach ($PublishedPackage in $PublishedPackages) {
        Copy-Item -LiteralPath $PublishedPackage.FullName -Destination $EvidenceDirectory -Force -ErrorAction Stop
        $PackageEvidence += [ordered]@{
            Name = $PublishedPackage.Name
            Length = $PublishedPackage.Length
            SHA256 = (Get-FileHash -LiteralPath $PublishedPackage.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $Evidence.Packages = $PackageEvidence
    $Evidence.EvidenceFiles = @(Get-ChildItem -LiteralPath $EvidenceDirectory -File -Force | ForEach-Object { $_.Name } | Sort-Object)

    if ($WorkerExitCode -ne 0) {
        throw "The isolated publication worker failed with exit code $WorkerExitCode. See '$WorkerLogPath'."
    }
    if ($null -eq $Evidence.Worker -or $Evidence.Worker.Status -ne 'Passed') {
        throw 'The isolated publication worker did not produce passing evidence.'
    }
    $Evidence.Status = 'Passed'
} catch {
    $Failure = $_
    $Evidence.Status = 'Failed'
    $Evidence.Error = $_.Exception.Message
} finally {
    $env:GITHUB_REF_TYPE = $OriginalRefType
    $env:GITHUB_REF_NAME = $OriginalRefName
    $env:GITHUB_SHA = $OriginalSha
    $Evidence.Recovery.EnvironmentRestored = $true

    if ($RepositoryRegistered) {
        try {
            Unregister-PSRepository -Name $RepositoryName -ErrorAction Stop
            $Evidence.Recovery.RepositoryUnregistered = $true
        } catch {
            if ($null -eq $Failure) {
                $Failure = $_
                $Evidence.Status = 'Failed'
                $Evidence.Error = $_.Exception.Message
            } else {
                $Evidence.Error = '{0} Cleanup also failed to unregister repository: {1}' -f $Evidence.Error, $_.Exception.Message
            }
        }
    } else {
        $Evidence.Recovery.RepositoryUnregistered = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($RehearsalRootPath) -and (Test-Path -LiteralPath $RehearsalRootPath)) {
        try {
            $ValidatedRemovalPath = Test-RehearsalRemovalTarget -Path $RehearsalRootPath
            Remove-Item -LiteralPath $ValidatedRemovalPath -Recurse -Force -ErrorAction Stop
            $Evidence.Recovery.TemporaryRootRemoved = $true
        } catch {
            if ($null -eq $Failure) {
                $Failure = $_
                $Evidence.Status = 'Failed'
                $Evidence.Error = $_.Exception.Message
            } else {
                $Evidence.Error = '{0} Cleanup also failed to remove the rehearsal directory: {1}' -f $Evidence.Error, $_.Exception.Message
            }
        }
    } else {
        $Evidence.Recovery.TemporaryRootRemoved = $true
    }

    Write-RehearsalJson -InputObject $Evidence -Path $ResolvedOutputPath
}

if ($null -ne $Failure) {
    throw $Failure
}
[pscustomobject]$Evidence
