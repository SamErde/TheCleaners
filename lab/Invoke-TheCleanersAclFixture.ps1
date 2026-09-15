<#
.SYNOPSIS
    Exercise the temp cleaner against an isolated ACL fixture.
.DESCRIPTION
    This lab-only harness creates a disposable directory under the supplied
    parent, denies the current user file-content read access on one old file,
    and records the cleanup result. It must not be pointed at a real temp
    directory or a production path.
.PARAMETER FixtureParent
    Existing disposable parent directory. A new uniquely named child is used.
.EXAMPLE
    .\lab\Invoke-TheCleanersAclFixture.ps1 -FixtureParent (Join-Path $env:LOCALAPPDATA 'Temp')
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $FixtureParent
)

$ErrorActionPreference = 'Stop'
$Parent = Resolve-Path -LiteralPath $FixtureParent
if (-not (Test-Path -LiteralPath $Parent.Path -PathType Container)) {
    throw "FixtureParent must already exist as a directory: $FixtureParent"
}

$FixtureRoot = Join-Path -Path $Parent.Path -ChildPath ('TheCleaners-Acl-{0}' -f ([guid]::NewGuid().Guid))
$OldReadablePath = Join-Path -Path $FixtureRoot -ChildPath 'old-readable.tmp'
$OldNoContentReadPath = Join-Path -Path $FixtureRoot -ChildPath 'old-delete-without-read.tmp'
$PreviousTemp = $env:TEMP
$PreviousTmp = $env:TMP
$CleanupErrors = @()

if (-not $PSCmdlet.ShouldProcess($FixtureRoot, 'Run Clear-CurrentUserTemp against the isolated ACL fixture')) {
    return
}

try {
    $null = New-Item -Path $FixtureRoot -ItemType Directory -Force
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
    try {
        $null = Get-Content -LiteralPath $OldNoContentReadPath -Raw -ErrorAction Stop
    } catch {
        $ReadWasDenied = $true
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
    $Volume = Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue | Select-Object -First 1
    $IsElevated = ([System.Security.Principal.WindowsPrincipal]$Identity).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    $BeforeCandidates = @($OldReadablePath, $OldNoContentReadPath)
    $ExpectedFileCount = $BeforeCandidates.Count
    $ExpectedBytes = [int64]0
    foreach ($CandidatePath in $BeforeCandidates) {
        $ExpectedBytes += [int64](Get-Item -LiteralPath $CandidatePath -Force -ErrorAction Stop).Length
    }

    $env:TEMP = $FixtureRoot
    $env:TMP = $FixtureRoot
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/TheCleaners/TheCleaners.psd1') -Force

    $Result = Clear-CurrentUserTemp -Days 30 -Confirm:$false -PassThru -ErrorAction SilentlyContinue -ErrorVariable CleanupErrors
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
    [ordered]@{
        FixtureRoot           = $FixtureRoot
        Runtime               = $PSVersionTable.PSVersion.ToString()
        PSEdition             = $PSVersionTable.PSEdition
        OS                    = $OperatingSystem.Caption
        OSVersion             = $OperatingSystem.Version
        OSBuild               = $OperatingSystem.BuildNumber
        IsElevated            = $IsElevated
        Drive                 = $DriveLetter
        FileSystem            = if ($null -eq $Volume) { 'unknown' } else { $Volume.FileSystem }
        ReadWasDenied         = $ReadWasDenied
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
        ResultErrorCount      = $ResultErrorCount
        RemainingNoReadFile   = [System.IO.File]::Exists($OldNoContentReadPath)
        OutcomeReconciles     = $OutcomeReconciles
        Acceptance            = (@($CleanupErrors).Count -eq 0 -and $ReadWasDenied -and $null -ne $DeleteAllowRule -and $null -ne $ReadDenyRule -and $AfterCandidates.Count -eq 0 -and $OutcomeReconciles)
        Note                  = 'This is an isolated fixture. It does not authorize cleanup of a real Windows temporary root.'
    } | ConvertTo-Json -Depth 8
} finally {
    $env:TEMP = $PreviousTemp
    $env:TMP = $PreviousTmp
    if (Test-Path -LiteralPath $FixtureRoot) {
        & icacls.exe $FixtureRoot /reset /t /c | Out-Null
        Remove-Item -LiteralPath $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
