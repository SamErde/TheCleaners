<#
.SYNOPSIS
    Exercise the temp cleaner against an isolated ACL fixture.
.DESCRIPTION
    This lab-only harness creates a disposable directory under the supplied
    parent, denies the current user file-content read access on one old file,
    and records the cleanup result after restoring TEMP/TMP and releasing owned
    handles. The native type/module lifetime ends with the dedicated process.
    Only the new child is cleaned; the parent is never a cleaner target.
    The child is retained for inspection, even on failure. No recursive recovery
    or ACL reset is performed. Use a dedicated process and an exclusive fixture
    parent. This is fixture evidence, never product acceptance.
.PARAMETER FixtureParent
    Existing local disposable directory at or below the canonical user temp
    directory. Reparse ancestors, remote paths and other locations are rejected.
.EXAMPLE
    .\lab\Invoke-TheCleanersAclFixture.ps1 -FixtureParent C:\Users\LabUser\AppData\Local\Temp\TheCleanersLab -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $FixtureParent
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This fixture requires Windows.'
}
$Parent = Resolve-Path -LiteralPath $FixtureParent -ErrorAction Stop
if ($Parent.Provider.Name -ne 'FileSystem' -or $Parent.ProviderPath -notmatch '^[A-Za-z]:\\') {
    throw 'FixtureParent must be an existing local drive-qualified filesystem directory.'
}
$ParentPath = [System.IO.Path]::GetFullPath($Parent.ProviderPath).TrimEnd('\')
$CanonicalTemp = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'Temp'
$CanonicalTemp = [System.IO.Path]::GetFullPath($CanonicalTemp).TrimEnd('\')
if ($ParentPath -ne $CanonicalTemp -and -not $ParentPath.StartsWith($CanonicalTemp + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'FixtureParent must be at or below the canonical user temp directory; no cleaner will run.'
}
# Check every ancestor, then lock and recheck it after ShouldProcess approval.
$AncestorPaths = [System.Collections.Generic.List[string]]::new()
$Ancestor = Get-Item -LiteralPath $ParentPath -Force -ErrorAction Stop
while ($null -ne $Ancestor) {
    if ($Ancestor -isnot [IO.DirectoryInfo] -or ($Ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'FixtureParent and its ancestors must be ordinary directories.'
    }
    $AncestorPaths.Insert(0, $Ancestor.FullName)
    $Ancestor = $Ancestor.Parent
}

$FixtureRoot = Join-Path -Path $ParentPath -ChildPath ('TheCleaners-Acl-{0}' -f ([guid]::NewGuid().Guid))
$OldReadablePath = Join-Path -Path $FixtureRoot -ChildPath 'old-readable.tmp'
$OldNoContentReadPath = Join-Path -Path $FixtureRoot -ChildPath 'old-delete-without-read.tmp'
$PreviousTemp = $env:TEMP
$PreviousTmp = $env:TMP
$CleanupErrors = @()
$Handles = [System.Collections.Generic.List[object]]::new()
$Identity = $null
$RootHandle = $null
$RootIdentity = $null
$Evidence = [ordered]@{
    SchemaVersion = 1
    CaseId = 'ACL-READ-DENIED'
    Scope = 'IsolatedFixture'
    RecordedUtc = [DateTime]::UtcNow.ToString('o')
    Runtime = $PSVersionTable.PSVersion.ToString()
    PSEdition = $PSVersionTable.PSEdition
    OSVersion = [Environment]::OSVersion.VersionString
    Commit = $null
    WorkingTreeDirty = $null
    ApprovedFixtureParent = $ParentPath
    FixtureRoot = $FixtureRoot
    RootIdentity = $null
    BeforeIdentities = @()
    AfterIdentities = @()
    PreviewResult = $null
    PreviewPreserved = $false
    RunFailure = $null
    Recovery = $null
    Acceptance = $false
}

if (-not $PSCmdlet.ShouldProcess($FixtureRoot, 'Run Clear-CurrentUserTemp against the isolated ACL fixture')) {
    return
}

try {
    $RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $Commit = & git -C $RepositoryRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $Commit -notmatch '^[0-9a-f]{40}$') {
        throw 'Cannot establish the fixture source commit.'
    }
    $Evidence.Commit = $Commit.Trim()
    $Evidence.InputHashes = @(@(Get-Item -LiteralPath $PSCommandPath) + @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'src/TheCleaners') -File -Recurse) | ForEach-Object {
        [ordered]@{ Path = $_.FullName; SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    $TreeStatus = @(& git -C $RepositoryRoot status --porcelain --untracked-files=normal)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot establish source working-tree state.' }
    $Evidence.WorkingTreeDirty = $TreeStatus.Count -gt 0
    . (Join-Path $RepositoryRoot 'src/TheCleaners/Private/Initialize-TheCleanersNativeFileInterop.ps1')
    Initialize-TheCleanersNativeFileInterop
    foreach ($AncestorPath in $AncestorPaths) {
        $Handle = [TheCleaners.NativeFileInterop]::OpenForIdentityInspection($AncestorPath)
        $Handles.Add($Handle)
        $AncestorIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($Handle)
        if (-not $AncestorIdentity.IsDirectory -or $AncestorIdentity.IsReparsePoint) {
            throw 'A fixture ancestor changed before it could be locked.'
        }
    }
    # No -Force: never adopt an existing directory as this run's fixture.
    $null = New-Item -Path $FixtureRoot -ItemType Directory -ErrorAction Stop
    $RootHandle = [TheCleaners.NativeFileInterop]::OpenForIdentityInspection($FixtureRoot)
    $Handles.Add($RootHandle)
    $RootIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($RootHandle)
    if (-not $RootIdentity.IsDirectory -or $RootIdentity.IsReparsePoint) { throw 'Unsafe fixture root.' }
    $Evidence.RootIdentity = $RootIdentity.Key
    $null = New-Item -Path $OldReadablePath -ItemType File
    $null = New-Item -Path $OldNoContentReadPath -ItemType File
    [System.IO.File]::WriteAllBytes($OldReadablePath, [byte[]](1, 2, 3))
    [System.IO.File]::WriteAllBytes($OldNoContentReadPath, [byte[]](4, 5, 6))
    $OldTime = [DateTime]::UtcNow.AddDays(-31)
    [System.IO.File]::SetLastWriteTimeUtc($OldReadablePath, $OldTime)
    [System.IO.File]::SetLastWriteTimeUtc($OldNoContentReadPath, $OldTime)

    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Acl = Get-Acl -LiteralPath $OldNoContentReadPath
    $DeleteAllow = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $Identity.User,
        [System.Security.AccessControl.FileSystemRights]::Delete,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $ReadDeny = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $Identity.User,
        [System.Security.AccessControl.FileSystemRights]::ReadData,
        [System.Security.AccessControl.AccessControlType]::Deny
    )
    $Acl.SetAccessRule($DeleteAllow)
    $Acl.AddAccessRule($ReadDeny)
    Set-Acl -LiteralPath $OldNoContentReadPath -AclObject $Acl

    $ReadWasDenied = $false
    $ReadDenialError = $null
    try {
        $null = Get-Content -LiteralPath $OldNoContentReadPath -Raw -ErrorAction Stop
    } catch [System.UnauthorizedAccessException] {
        $ReadWasDenied = $true
        $ReadDenialError = [ordered]@{ Id = $_.FullyQualifiedErrorId; Category = [string]$_.CategoryInfo.Category; Message = $_.Exception.Message }
    }

    $EffectiveRules = @(Get-Acl -LiteralPath $OldNoContentReadPath).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]) | Where-Object {
        $_.IdentityReference.Value -eq $Identity.User.Value
    }
    $DeleteAllowRule = $EffectiveRules | Where-Object {
        $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
        (($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Delete) -eq [System.Security.AccessControl.FileSystemRights]::Delete)
    }
    $ReadDenyRule = $EffectiveRules | Where-Object {
        $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
        (($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadData) -eq [System.Security.AccessControl.FileSystemRights]::ReadData)
    }

    $OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $DriveQualifier = Split-Path -Path $FixtureRoot -Qualifier
    $DriveLetter = $DriveQualifier.TrimEnd([char[]]@(':', '\'))
    $Volume = $null
    $VolumeProbeError = $null
    try {
        $Volume = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $Volume) {
            $VolumeProbeError = "No volume was returned for drive '$DriveLetter'."
        } elseif ([string]::IsNullOrWhiteSpace([string]$Volume.FileSystem)) {
            $VolumeProbeError = "The volume for drive '$DriveLetter' did not report a filesystem."
        }
    } catch {
        $VolumeProbeError = $_.Exception.Message
    }
    $VolumeEvidenceAvailable = $null -ne $Volume -and -not [string]::IsNullOrWhiteSpace([string]$Volume.FileSystem)
    if (-not $VolumeEvidenceAvailable -or [string]$Volume.FileSystem -notin @('NTFS', 'ReFS')) {
        throw "An NTFS or ReFS volume must be identified before cleanup: $VolumeProbeError"
    }
    if (-not $ReadWasDenied -or $null -eq $DeleteAllowRule -or $null -eq $ReadDenyRule) {
        throw 'The intended read-denied/delete-allowed ACL was not established; cleanup was not attempted.'
    }
    $Principal = [System.Security.Principal.WindowsPrincipal]::new($Identity)
    $IsElevated = $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    $BeforeCandidates = @($OldReadablePath, $OldNoContentReadPath)
    $ExpectedFileCount = $BeforeCandidates.Count
    $ExpectedBytes = [int64]0
    foreach ($CandidatePath in $BeforeCandidates) {
        $ExpectedBytes += [int64](Get-Item -LiteralPath $CandidatePath -Force -ErrorAction Stop).Length
    }

    $Snapshot = {
        foreach ($CandidatePath in $BeforeCandidates) {
            if (Test-Path -LiteralPath $CandidatePath -ErrorAction Stop) {
                $FileIdentity = Get-TheCleanersFileIdentity -LiteralPath $CandidatePath
                [ordered]@{
                    Path = $CandidatePath
                    Identity = $FileIdentity.Key
                    Length = $FileIdentity.Length
                    LastWriteTimeUtc = $FileIdentity.LastWriteTimeUtc.ToString('o')
                    Attributes = $FileIdentity.Attributes
                    SHA256 = if ($CandidatePath -eq $OldReadablePath) { (Get-FileHash -LiteralPath $CandidatePath -Algorithm SHA256 -ErrorAction Stop).Hash } else { $null }
                    ContentEvidence = if ($CandidatePath -eq $OldReadablePath) { 'Hashed' } else { 'ReadDeniedByFixtureAcl' }
                }
            }
        }
    }
    $Evidence.BeforeIdentities = @(& $Snapshot)

    $env:TEMP = $FixtureRoot
    $env:TMP = $FixtureRoot
    # Local scope and no -Force preserve any caller's existing module instance.
    $Module = Import-Module -Name (Join-Path $RepositoryRoot 'src/TheCleaners/TheCleaners.psd1') -Scope Local -PassThru -ErrorAction Stop

    $Evidence.PreviewResult = & $Module { Clear-CurrentUserTemp -Days 30 -WhatIf -Confirm:$false -PassThru -ErrorAction Stop }
    $PreviewIdentities = @(& $Snapshot)
    $Evidence.PreviewPreserved = ($Evidence.BeforeIdentities | ConvertTo-Json -Depth 5 -Compress) -ceq ($PreviewIdentities | ConvertTo-Json -Depth 5 -Compress)
    $ExpectedPaths = @($BeforeCandidates | Sort-Object)
    $PreviewPaths = @($Evidence.PreviewResult.CandidatePaths | Sort-Object)
    $Evidence.PreviewInventoryMatches = ($PreviewPaths.Count -eq $ExpectedPaths.Count -and
        [string]::Join("`n", $PreviewPaths) -eq [string]::Join("`n", $ExpectedPaths))
    if (-not $Evidence.PreviewPreserved -or $Evidence.PreviewResult.Status -ne 'WhatIf' -or
        -not $Evidence.PreviewInventoryMatches -or
        $Evidence.PreviewResult.FileCandidateCount -ne $ExpectedFileCount -or
        $Evidence.PreviewResult.FilesRemoved -ne 0 -or $Evidence.PreviewResult.BytesReclaimed -ne 0) {
        throw 'Fixture WhatIf inventory or reconciliation failed; removal was not attempted.'
    }

    $Invocation = & $Module {
        $CommandErrors = @()
        $CommandResult = Clear-CurrentUserTemp -Days 30 -Confirm:$false -PassThru -ErrorAction SilentlyContinue -ErrorVariable CommandErrors
        [pscustomobject]@{ Result = $CommandResult; Errors = @($CommandErrors) }
    }
    $Result = $Invocation.Result
    $CleanupErrors = @($Invocation.Errors)
    $Evidence.AfterIdentities = @(& $Snapshot)
    $AfterCandidates = @($BeforeCandidates | Where-Object {
            [System.IO.File]::Exists($_) -or [System.IO.Directory]::Exists($_)
        })
    $ResultErrorCount = if ($null -eq $Result) { $null } else { @($Result.ErrorIds).Count }
    $OutcomeReconciles = $null -ne $Result -and
        $Result.Status -eq 'Completed' -and
        $Result.DiscoveryStatus -eq 'Validated' -and
        $Result.FileCandidateCount -eq $ExpectedFileCount -and
        $Result.FilesRemoved -eq $ExpectedFileCount -and
        $Result.FileFailureCount -eq 0 -and
        $Result.FilesSkipped -eq 0 -and
        $Result.BytesReclaimed -eq $ExpectedBytes -and
        $Result.DirectoryCandidateCount -eq 0 -and
        $Result.DirectoriesRemoved -eq 0 -and
        $Result.DirectoryFailureCount -eq 0 -and
        $Result.DirectoriesSkipped -eq 0 -and
        $ResultErrorCount -eq 0
    $OutcomeEvidence = [ordered]@{
        FixtureRoot           = $FixtureRoot
        Runtime               = $PSVersionTable.PSVersion.ToString()
        PSEdition             = $PSVersionTable.PSEdition
        OS                    = $OperatingSystem.Caption
        OSVersion             = $OperatingSystem.Version
        OSBuild               = $OperatingSystem.BuildNumber
        IsElevated            = $IsElevated
        TokenSid              = $Identity.User.Value
        Drive                 = $DriveLetter
        FileSystem            = if ($null -eq $Volume) { 'unknown' } else { $Volume.FileSystem }
        VolumeProbeStatus     = if ($VolumeEvidenceAvailable) { 'Validated' } else { 'Failed' }
        VolumeProbeError      = $VolumeProbeError
        ReadWasDenied         = $ReadWasDenied
        ReadDenialError        = $ReadDenialError
        DeleteAllowRuleFound  = ($null -ne $DeleteAllowRule)
        DeleteAllowAccessMask = [int][System.Security.AccessControl.FileSystemRights]::Delete
        ReadDenyRuleFound     = ($null -ne $ReadDenyRule)
        ReadDenyAccessMask    = [int][System.Security.AccessControl.FileSystemRights]::ReadData
        BeforeCandidates      = $BeforeCandidates
        ExpectedFileCount     = $ExpectedFileCount
        ExpectedBytes         = $ExpectedBytes
        AfterCandidates       = $AfterCandidates
        Result                = $Result
        ErrorIds              = @($Result.ErrorIds)
        ErrorCount            = @($CleanupErrors).Count
        Errors                = @($CleanupErrors | ForEach-Object { [ordered]@{ Id = $_.FullyQualifiedErrorId; Category = [string]$_.CategoryInfo.Category; Target = [string]$_.TargetObject; Message = $_.Exception.Message } })
        ResultErrorCount      = $ResultErrorCount
        RemainingNoReadFile   = [System.IO.File]::Exists($OldNoContentReadPath)
        OutcomeReconciles     = $OutcomeReconciles
        FixturePassed         = (@($CleanupErrors).Count -eq 0 -and $VolumeEvidenceAvailable -and [string]$Volume.FileSystem -in @('NTFS', 'ReFS') -and $ReadWasDenied -and $null -ne $DeleteAllowRule -and $null -ne $ReadDenyRule -and $AfterCandidates.Count -eq 0 -and $OutcomeReconciles)
        Note                  = 'This is an isolated fixture. It does not authorize cleanup of a real Windows temporary root.'
    }
    foreach ($Key in $OutcomeEvidence.Keys) { $Evidence[$Key] = $OutcomeEvidence[$Key] }
} catch {
    $Evidence.RunFailure = [ordered]@{ Id = $_.FullyQualifiedErrorId; Category = [string]$_.CategoryInfo.Category; Message = $_.Exception.Message }
} finally {
    $env:TEMP = $PreviousTemp
    $env:TMP = $PreviousTmp
    $RemainingEntries = $null
    $RecoveryProbeError = $null
    try {
        if ($null -ne $RootHandle -and -not $RootHandle.IsClosed) {
            $RemainingEntries = @(Get-ChildItem -LiteralPath $FixtureRoot -Force -ErrorAction Stop | ForEach-Object { $_.FullName })
        }
    } catch {
        $RecoveryProbeError = $_.Exception.Message
    }
    foreach ($Handle in $Handles) { $Handle.Dispose() }
    $RootReopenVerified = $false
    $RootReopenError = $null
    $ProbeHandle = $null
    try {
        if ($null -ne $RootIdentity) {
            # Request DELETE access solely as a sharing/identity probe. No delete
            # disposition or path mutation occurs, even if the object changed.
            $ProbeHandle = [TheCleaners.NativeFileInterop]::OpenForStableEnumeration($FixtureRoot)
            $ProbeIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($ProbeHandle)
            $RootReopenVerified = $ProbeIdentity.Equals($RootIdentity) -and $ProbeIdentity.IsDirectory -and -not $ProbeIdentity.IsReparsePoint
            if (-not $RootReopenVerified) { throw 'The retained fixture root identity changed after handle disposal.' }
        }
    } catch {
        $RootReopenError = [ordered]@{
            Id = $_.FullyQualifiedErrorId
            Message = $_.Exception.Message
            HResult = $_.Exception.HResult
            NativeErrorCode = if ($_.Exception.InnerException -is [ComponentModel.Win32Exception]) { $_.Exception.InnerException.NativeErrorCode } else { $null }
        }
    } finally {
        if ($null -ne $ProbeHandle) { $ProbeHandle.Dispose() }
    }
    if ($null -ne $Identity) { $Identity.Dispose() }
    $Evidence.Recovery = [ordered]@{
        Policy = 'RetainFixtureForInspection'
        EnvironmentRestored = ($env:TEMP -ceq $PreviousTemp -and $env:TMP -ceq $PreviousTmp)
        HandlesClosed = @($Handles | Where-Object { -not $_.IsClosed }).Count -eq 0
        HandleCount = $Handles.Count
        RemainingEntries = $RemainingEntries
        InventoryError = $RecoveryProbeError
        RootReopenVerified = $RootReopenVerified
        RootReopenError = $RootReopenError
        ProbeHandleClosed = ($null -eq $ProbeHandle -or $ProbeHandle.IsClosed)
        ProcessExitRequired = 'Exit the dedicated process to release module and native-type state.'
        RecursiveRecoveryAttempted = $false
        OperatorAction = 'Inspect retained fixture; use the approved disposable-host reset for recovery.'
    }
}
$Evidence.Acceptance = ($null -eq $Evidence.RunFailure -and -not $Evidence.WorkingTreeDirty -and
    $Evidence.FixturePassed -and $Evidence.PreviewPreserved -and
    $Evidence.PreviewInventoryMatches -and $Evidence.Recovery.RootReopenVerified -and $Evidence.Recovery.ProbeHandleClosed -and
    $Evidence.Recovery.EnvironmentRestored -and $Evidence.Recovery.HandlesClosed -and
    $null -eq $Evidence.Recovery.InventoryError -and $null -ne $Evidence.Recovery.RemainingEntries -and
    @($Evidence.Recovery.RemainingEntries).Count -eq 0)
$Evidence | ConvertTo-Json -Depth 10
