BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $TempCases = @(
        @{ CommandName = 'Clear-CurrentUserTemp' }
        @{ CommandName = 'Clear-WindowsTemp' }
    )
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners') -ErrorAction Stop).Path
    foreach ($RelativePath in @(
        'Private/ResultContracts.ps1'
        'Private/Initialize-TheCleanersNativeFileInterop.ps1'
        'Private/Get-TheCleanersWindowsTempRoot.ps1'
        'Private/Get-TheCleanersTempPlan.ps1'
        'Private/Resolve-TheCleanersFileSystemPath.ps1'
        'Public/Clear-CurrentUserTemp.ps1'
        'Public/Clear-WindowsTemp.ps1'
    )) {
        . (Join-Path -Path $ModuleRoot -ChildPath $RelativePath)
    }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Initialize-TheCleanersNativeFileInterop
    }
    $OriginalTempPlan = ${function:Get-TheCleanersTempPlan}
}

Describe 'Temp deletion rights: <CommandName>' -ForEach $TempCases -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $TempRoot = Join-Path -Path $FixtureRoot -ChildPath 'Temp'
        $null = New-Item -Path $TempRoot -ItemType Directory -Force -ErrorAction Stop
        $CandidatePath = Join-Path -Path $TempRoot -ChildPath 'candidate.tmp'
        [System.IO.File]::WriteAllBytes($CandidatePath, [byte[]](1, 2, 3, 4))
        $Now = [DateTime]::UtcNow
        [System.IO.File]::SetLastWriteTimeUtc($CandidatePath, $Now.AddDays(-31))
        $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $OriginalCandidateAcl = Get-Acl -LiteralPath $CandidatePath -ErrorAction Stop
        $OriginalRootAcl = Get-Acl -LiteralPath $TempRoot -ErrorAction Stop
        $AclState = [pscustomobject]@{
            CandidateChanged = $false
            RootChanged      = $false
        }
        $env:TEMP = $TempRoot
        $env:TMP = $TempRoot

        Mock Get-TheCleanersWindowsTempRoot { Resolve-TheCleanersFileSystemPath -LiteralPath $TempRoot }
        Mock Get-Date { $Now }

        $SetReadDeniedDeleteAllowed = {
            $CandidateAcl = Get-Acl -LiteralPath $CandidatePath -ErrorAction Stop
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
            $CandidateAcl.SetAccessRule($DeleteAllow)
            $CandidateAcl.AddAccessRule($ReadDeny)
            Set-Acl -LiteralPath $CandidatePath -AclObject $CandidateAcl -ErrorAction Stop
            $AclState.CandidateChanged = $true
        }

        $SetDeleteDenied = {
            $CandidateAcl = Get-Acl -LiteralPath $CandidatePath -ErrorAction Stop
            $DeleteDeny = [System.Security.AccessControl.FileSystemAccessRule]::new(
                $Identity.User,
                [System.Security.AccessControl.FileSystemRights]::Delete,
                [System.Security.AccessControl.AccessControlType]::Deny
            )
            $CandidateAcl.AddAccessRule($DeleteDeny)
            Set-Acl -LiteralPath $CandidatePath -AclObject $CandidateAcl -ErrorAction Stop
            $AclState.CandidateChanged = $true

            # DELETE on the file or FILE_DELETE_CHILD on its parent can authorize
            # deletion. Deny both routes so this fixture exercises the error path.
            $RootAcl = Get-Acl -LiteralPath $TempRoot -ErrorAction Stop
            $DeleteChildDeny = [System.Security.AccessControl.FileSystemAccessRule]::new(
                $Identity.User,
                [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles,
                [System.Security.AccessControl.AccessControlType]::Deny
            )
            $RootAcl.AddAccessRule($DeleteChildDeny)
            Set-Acl -LiteralPath $TempRoot -AclObject $RootAcl -ErrorAction Stop
            $AclState.RootChanged = $true
        }

        $AssertDeleteDenied = {
            $CandidateRules = @((Get-Acl -LiteralPath $CandidatePath -ErrorAction Stop).GetAccessRules(
                    $true,
                    $true,
                    [System.Security.Principal.SecurityIdentifier]
                ) | Where-Object IdentityReference -EQ $Identity.User)
            @($CandidateRules | Where-Object {
                    $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
                    ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Delete)
                }) | Should -Not -BeNullOrEmpty
            $ParentRules = @((Get-Acl -LiteralPath $TempRoot -ErrorAction Stop).GetAccessRules(
                    $true,
                    $true,
                    [System.Security.Principal.SecurityIdentifier]
                ) | Where-Object IdentityReference -EQ $Identity.User)
            @($ParentRules | Where-Object {
                    $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
                    ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles)
                }) | Should -Not -BeNullOrEmpty
        }

        $GetReadAttemptException = {
            $ReadStream = $null
            try {
                $ReadStream = [System.IO.File]::Open(
                    $CandidatePath,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite
                )
                return $null
            } catch {
                return $_.Exception.GetBaseException()
            } finally {
                if ($null -ne $ReadStream) {
                    $ReadStream.Dispose()
                }
            }
        }
    }

    AfterEach {
        # Restore ACLs before Pester removes its isolated TestDrive fixture.
        $RestoreErrors = [System.Collections.Generic.List[System.Management.Automation.ErrorRecord]]::new()
        try {
            try {
                if ($AclState.CandidateChanged -and [System.IO.File]::Exists($CandidatePath)) {
                    Set-Acl -LiteralPath $CandidatePath -AclObject $OriginalCandidateAcl -ErrorAction Stop
                }
            } catch {
                $RestoreErrors.Add($_)
            }
            try {
                if ($AclState.RootChanged -and [System.IO.Directory]::Exists($TempRoot)) {
                    Set-Acl -LiteralPath $TempRoot -AclObject $OriginalRootAcl -ErrorAction Stop
                }
            } catch {
                $RestoreErrors.Add($_)
            }
        } finally {
            $env:TEMP = $PreviousTemp
            $env:TMP = $PreviousTmp
            if ($null -ne $Identity) {
                $Identity.Dispose()
            }
        }
        if ($RestoreErrors.Count -gt 0) {
            throw $RestoreErrors[0]
        }
    }

    It 'deletes an old file when content reads are actually denied but DELETE and attributes are allowed' {
        & $SetReadDeniedDeleteAllowed

        $Rules = @((Get-Acl -LiteralPath $CandidatePath -ErrorAction Stop).GetAccessRules(
                $true,
                $true,
                [System.Security.Principal.SecurityIdentifier]
            ) | Where-Object IdentityReference -EQ $Identity.User)
        @($Rules | Where-Object {
                $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
                ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadData)
            }) | Should -Not -BeNullOrEmpty
        @($Rules | Where-Object {
                $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
                ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Delete)
            }) | Should -Not -BeNullOrEmpty

        # This assertion is mandatory even for an elevated token. The fixture must
        # prove that the process cannot read content rather than infer it from ACLs.
        (& $GetReadAttemptException) | Should -BeOfType ([System.UnauthorizedAccessException])
        $NativeHandle = [TheCleaners.NativeFileInterop]::OpenForDeletion($CandidatePath, $false)
        try {
            $NativeIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($NativeHandle)
            $NativeIdentity.Key | Should -Match '^[0-9A-F]{16}:[0-9A-F]{32}$'
            $NativeIdentity.Length | Should -Be 4
        } finally {
            $NativeHandle.Dispose()
        }

        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru -ErrorAction Stop

        $CandidatePath | Should -Not -Exist
        $Result.FileCandidateCount | Should -Be 1
        $Result.FilesRemoved | Should -Be 1
        $Result.FilesSkipped | Should -Be 0
        $Result.FileFailureCount | Should -Be 0
        $Result.BytesReclaimed | Should -Be 4
        $Result.ErrorIds | Should -BeNullOrEmpty
        $Result.Status | Should -Be 'Completed'
    }

    It 'reports denied DELETE through the error stream and reconciles counters' {
        & $SetDeleteDenied
        & $AssertDeleteDenied

        $OpenException = $null
        try {
            $UnexpectedHandle = [TheCleaners.NativeFileInterop]::OpenForDeletion($CandidatePath, $false)
            $UnexpectedHandle.Dispose()
        } catch {
            $OpenException = $_.Exception.GetBaseException()
        }
        $OpenException | Should -BeOfType ([System.ComponentModel.Win32Exception])
        $OpenException.NativeErrorCode | Should -Be 5
        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru -ErrorAction SilentlyContinue -ErrorVariable Failure

        $CandidatePath | Should -Exist
        $Result.FileCandidateCount | Should -Be 1
        $Result.FilesRemoved | Should -Be 0
        $Result.FilesSkipped | Should -Be 0
        $Result.FileFailureCount | Should -Be 1
        $Result.BytesReclaimed | Should -Be 0
        $Result.ErrorIds | Should -Contain 'TempFileRemovalFailed'
        $Result.Status | Should -Be 'PartialFailure'
        $Reported = @($Failure | Where-Object FullyQualifiedErrorId -Like 'TempFileRemovalFailed,*')
        $Reported | Should -HaveCount 1
        [string]$Reported[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        $Reported[0].TargetObject | Should -Be $CandidatePath
    }

    It 'honors ErrorAction Stop when DELETE is denied' {
        & $SetDeleteDenied
        & $AssertDeleteDenied

        { & $CommandName -Days 30 -Confirm:$false -ErrorAction Stop } |
            Should -Throw -ErrorId 'TempFileRemovalFailed,*'
        $CandidatePath | Should -Exist
    }

    It 'counts a read-denied candidate that disappears after discovery as skipped' {
        & $SetReadDeniedDeleteAllowed
        (& $GetReadAttemptException) | Should -BeOfType ([System.UnauthorizedAccessException])
        Mock Get-TheCleanersTempPlan {
            $Plan = & $OriginalTempPlan -Root $Root -TraversalRootPath $TraversalRootPath -CutoffUtc $CutoffUtc -RemoveEmptyDirectory:$RemoveEmptyDirectory -CaptureIdentity:$CaptureIdentity -ValidatedRootIdentity $ValidatedRootIdentity
            [System.IO.File]::Delete($CandidatePath)
            $Plan
        }

        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru -ErrorAction Stop

        $CandidatePath | Should -Not -Exist
        $Result.FileCandidateCount | Should -Be 1
        $Result.FilesRemoved | Should -Be 0
        $Result.FilesSkipped | Should -Be 1
        $Result.FileFailureCount | Should -Be 0
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
    }

    It 'preserves a directory substituted for a read-denied candidate after discovery' {
        & $SetReadDeniedDeleteAllowed
        (& $GetReadAttemptException) | Should -BeOfType ([System.UnauthorizedAccessException])
        Mock Get-TheCleanersTempPlan {
            $Plan = & $OriginalTempPlan -Root $Root -TraversalRootPath $TraversalRootPath -CutoffUtc $CutoffUtc -RemoveEmptyDirectory:$RemoveEmptyDirectory -CaptureIdentity:$CaptureIdentity -ValidatedRootIdentity $ValidatedRootIdentity
            [System.IO.File]::Delete($CandidatePath)
            $null = New-Item -Path $CandidatePath -ItemType Directory -ErrorAction Stop
            $Plan
        }

        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru -ErrorAction Stop

        [System.IO.Directory]::Exists($CandidatePath) | Should -BeTrue
        $Result.FileCandidateCount | Should -Be 1
        $Result.FilesRemoved | Should -Be 0
        $Result.FilesSkipped | Should -Be 1
        $Result.FileFailureCount | Should -Be 0
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
    }
}

Describe 'Native FILE_ID_INFO contract' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'compares every byte of the 128-bit file ID and the volume serial' {
        $FileId = [byte[]](0..15)
        $Identity = [TheCleaners.NativeFileIdentity]::new(
            [uint64]42,
            $FileId,
            [int64]100,
            [DateTime]::UtcNow.ToFileTimeUtc(),
            [uint32][System.IO.FileAttributes]::Archive
        )
        $EqualIdentity = [TheCleaners.NativeFileIdentity]::new(
            [uint64]42,
            [byte[]]$FileId.Clone(),
            [int64]100,
            $Identity.LastWriteTimeUtcFileTime,
            [uint32][System.IO.FileAttributes]::Archive
        )
        $DifferentMetadata = [TheCleaners.NativeFileIdentity]::new(
            [uint64]42,
            [byte[]]$FileId.Clone(),
            [int64]999,
            $Identity.LastWriteTimeUtc.AddDays(1).ToFileTimeUtc(),
            [uint32][System.IO.FileAttributes]::Hidden
        )
        $DifferentVolume = [TheCleaners.NativeFileIdentity]::new(
            [uint64]43,
            [byte[]]$FileId.Clone(),
            $Identity.Length,
            $Identity.LastWriteTimeUtcFileTime,
            $Identity.Attributes
        )

        $Identity.Equals($EqualIdentity) | Should -BeTrue
        $EqualIdentity.Equals($Identity) | Should -BeTrue
        $Identity.GetHashCode() | Should -Be $EqualIdentity.GetHashCode()
        $Identity.Equals($DifferentMetadata) | Should -BeTrue
        $Identity.GetHashCode() | Should -Be $DifferentMetadata.GetHashCode()
        $Identity.Equals($DifferentVolume) | Should -BeFalse

        foreach ($Index in 0..15) {
            $DifferentFileId = [byte[]]$FileId.Clone()
            $DifferentFileId[$Index] = [byte]($DifferentFileId[$Index] -bxor 0xFF)
            $DifferentIdentity = [TheCleaners.NativeFileIdentity]::new(
                [uint64]42,
                $DifferentFileId,
                $Identity.Length,
                $Identity.LastWriteTimeUtcFileTime,
                $Identity.Attributes
            )

            $Identity.Equals($DifferentIdentity) | Should -BeFalse -Because "file-ID byte $Index changed"
        }
    }

    It 'uses the documented 128-bit file identifier and fails when native identity reads fail' {
        $InteropPath = Join-Path -Path $ModuleRoot -ChildPath 'Private/Initialize-TheCleanersNativeFileInterop.ps1'
        $InteropText = [System.IO.File]::ReadAllText($InteropPath)

        $InteropText | Should -Match 'ByValArray, SizeConst = 16'
        $InteropText | Should -Match 'throw new Win32Exception\(Marshal\.GetLastWin32Error\(\), "The Windows file identity could not be read\."\)'
        $InteropText | Should -Match 'Delete \| FileReadAttributes'
        $InteropText | Should -Not -Match 'Delete \| FileReadData'

        $InvalidHandle = [Microsoft.Win32.SafeHandles.SafeFileHandle]::new([IntPtr]::new(-1), $false)
        try {
            $IdentityException = $null
            try {
                $null = [TheCleaners.NativeFileInterop]::ReadIdentity($InvalidHandle)
            } catch {
                $IdentityException = $_.Exception.GetBaseException()
            }
            $IdentityException | Should -BeOfType ([System.ComponentModel.Win32Exception])
            $IdentityException.NativeErrorCode | Should -Be 6
        } finally {
            $InvalidHandle.Dispose()
        }
    }
}
