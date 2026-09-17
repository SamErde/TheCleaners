BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $TempCases = @(
        @{ CommandName = 'Clear-CurrentUserTemp' }
        @{ CommandName = 'Clear-WindowsTemp' }
    )
}

BeforeAll {
    $ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners'
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
    $OriginalTempPlan = ${function:Get-TheCleanersTempPlan}
}

Describe 'Temp failure branches: <CommandName>' -ForEach $TempCases -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $TempRoot = Join-Path -Path $FixtureRoot -ChildPath 'Temp'
        $ParentPath = Join-Path -Path $TempRoot -ChildPath 'Parent'
        $ChildPath = Join-Path -Path $ParentPath -ChildPath 'Child'
        $null = New-Item -Path $ChildPath -ItemType Directory -Force
        $CandidatePath = Join-Path -Path $ChildPath -ChildPath 'candidate.tmp'
        $SiblingPath = Join-Path -Path $ChildPath -ChildPath 'sibling.tmp'
        $Now = [DateTime]::UtcNow
        foreach ($Path in @($CandidatePath, $SiblingPath)) {
            [System.IO.File]::WriteAllText($Path, 'old')
            [System.IO.File]::SetLastWriteTimeUtc($Path, $Now.AddDays(-31))
        }
        $env:TEMP = $TempRoot
        $env:TMP = $TempRoot
        $State = [pscustomobject]@{ Handles = @() }
        Mock Get-TheCleanersWindowsTempRoot { Resolve-TheCleanersFileSystemPath -LiteralPath $TempRoot }
        Mock Get-Date { $Now }
        Mock Get-TheCleanersTempPlan {
            $Plan = & $OriginalTempPlan -Root $Root -TraversalRootPath $TraversalRootPath -CutoffUtc $CutoffUtc -RemoveEmptyDirectory:$RemoveEmptyDirectory -CaptureIdentity:$CaptureIdentity -ValidatedRootIdentity $ValidatedRootIdentity
            $State.Handles = @($Plan.HeldDirectoryHandles | ForEach-Object { $_.Handle })
            $Plan
        }
    }

    AfterEach {
        # A failed assertion must not leave handles or redirected temp variables behind.
        foreach ($Handle in $State.Handles) { $Handle.Dispose() }
        $env:TEMP = $PreviousTemp
        $env:TMP = $PreviousTmp
    }

    It 'rejects a changed root identity and releases its plan handles (Stop=<Stop>)' -TestCases @(
        @{ Stop = $false }
        @{ Stop = $true }
    ) {
        param($Stop)
        Mock Get-TheCleanersTempPlan {
            $Plan = & $OriginalTempPlan -Root $Root -TraversalRootPath $TraversalRootPath -CutoffUtc $CutoffUtc -RemoveEmptyDirectory:$RemoveEmptyDirectory -CaptureIdentity:$CaptureIdentity -ValidatedRootIdentity $ValidatedRootIdentity
            $State.Handles = @($Plan.HeldDirectoryHandles | ForEach-Object { $_.Handle })
            # Inject a different real identity at the discovery/revalidation boundary.
            # Stable production handles normally prevent a physical root replacement.
            $Plan.RootIdentity = Get-TheCleanersFileIdentity -LiteralPath $FixtureRoot -Directory
            $Plan
        }

        if ($Stop) {
            { & $CommandName -RemoveEmptyDirectory -Confirm:$false -ErrorAction Stop } | Should -Throw -ErrorId 'TempRootChanged,*'
        } else {
            $Result = & $CommandName -RemoveEmptyDirectory -Confirm:$false -PassThru -ErrorAction SilentlyContinue -ErrorVariable Failure
            $Result.Status | Should -Be 'DiscoveryFailed'
            $Result.DiscoveryErrorCount | Should -Be 1
            $Result.ErrorIds | Should -Contain 'TempRootChanged'
            $Result.FilesRemoved | Should -Be 0
            $Result.DirectoriesRemoved | Should -Be 0
            @($Failure | Where-Object FullyQualifiedErrorId -Like 'TempRootChanged,*') | Should -HaveCount 1
        }
        $CandidatePath | Should -Exist
        $SiblingPath | Should -Exist
        $State.Handles.Count | Should -BeGreaterThan 0
        @($State.Handles | Where-Object { -not $_.IsClosed }) | Should -HaveCount 0
    }

    It 'preserves a <Change> candidate and disqualifies its ancestors from pruning' -TestCases @(
        @{ Change = 'recent' }
        @{ Change = 'replacement' }
    ) {
        param($Change)
        Mock Get-TheCleanersTempPlan {
            $Plan = & $OriginalTempPlan -Root $Root -TraversalRootPath $TraversalRootPath -CutoffUtc $CutoffUtc -RemoveEmptyDirectory:$RemoveEmptyDirectory -CaptureIdentity:$CaptureIdentity -ValidatedRootIdentity $ValidatedRootIdentity
            $State.Handles = @($Plan.HeldDirectoryHandles | ForEach-Object { $_.Handle })
            if ($Change -eq 'replacement') {
                # Keep the original object alive at another name to avoid file-ID reuse.
                [System.IO.File]::Move($CandidatePath, (Join-Path -Path $FixtureRoot -ChildPath 'original.tmp'))
                [System.IO.File]::WriteAllText($CandidatePath, 'replacement')
                [System.IO.File]::SetLastWriteTimeUtc($CandidatePath, $Now.AddDays(-31))
            } else {
                [System.IO.File]::SetLastWriteTimeUtc($CandidatePath, $Now)
            }
            $Plan
        }

        $Result = & $CommandName -RemoveEmptyDirectory -Confirm:$false -PassThru -ErrorAction Stop

        $Result.FileCandidateCount | Should -Be 2
        $Result.FilesRemoved | Should -Be 1
        $Result.FilesSkipped | Should -Be 1
        $Result.FileFailureCount | Should -Be 0
        $Result.BytesReclaimed | Should -Be 3
        $Result.DirectoryCandidateCount | Should -Be 2
        $Result.DirectoriesSkipped | Should -Be 2
        $Result.DirectoriesRemoved | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
        $CandidatePath | Should -Exist
        $SiblingPath | Should -Not -Exist
        $ChildPath | Should -Exist
        $ParentPath | Should -Exist
        if ($Change -eq 'replacement') {
            [System.IO.File]::ReadAllText($CandidatePath) | Should -Be 'replacement'
        }
        @($State.Handles | Where-Object { -not $_.IsClosed }) | Should -HaveCount 0
    }

    It 'reports a pruning <FailureKind> without removing ancestors (Stop=<Stop>)' -TestCases @(
        @{ FailureKind = 'access denial'; Stop = $false; Category = 'PermissionDenied' }
        @{ FailureKind = 'I/O error'; Stop = $false; Category = 'WriteError' }
        @{ FailureKind = 'access denial'; Stop = $true; Category = 'PermissionDenied' }
    ) {
        param($FailureKind, $Stop, $Category)
        $PruningAccessDenied = $FailureKind -eq 'access denial'
        Mock Get-ChildItem {
            if ($PruningAccessDenied) {
                throw [System.UnauthorizedAccessException]::new('Fixture pruning access denial.')
            }
            throw [System.IO.IOException]::new('Fixture pruning I/O failure.')
        } -ParameterFilter { $LiteralPath -eq $ChildPath -and -not [System.IO.File]::Exists($SiblingPath) }

        if ($Stop) {
            { & $CommandName -RemoveEmptyDirectory -Confirm:$false -ErrorAction Stop } | Should -Throw -ErrorId 'TempDirectoryRemovalFailed,*'
        } else {
            $Result = & $CommandName -RemoveEmptyDirectory -Confirm:$false -PassThru -ErrorAction SilentlyContinue -ErrorVariable Failure
            $Result.FilesRemoved | Should -Be 2
            $Result.BytesReclaimed | Should -Be 6
            $Result.DirectoryFailureCount | Should -Be 1
            $Result.DirectoriesSkipped | Should -Be 1
            $Result.DirectoriesRemoved | Should -Be 0
            $Result.Status | Should -Be 'PartialFailure'
            $Reported = @($Failure | Where-Object FullyQualifiedErrorId -Like 'TempDirectoryRemovalFailed,*')
            $Reported | Should -HaveCount 1
            [string]$Reported[0].CategoryInfo.Category | Should -Be $Category
            $Reported[0].TargetObject | Should -Be $ChildPath
        }
        $CandidatePath | Should -Not -Exist
        $SiblingPath | Should -Not -Exist
        $ChildPath | Should -Exist
        $ParentPath | Should -Exist
        @($State.Handles | Where-Object { -not $_.IsClosed }) | Should -HaveCount 0
    }

    It 'fails discovery when a queued child identity is inaccessible' {
        Mock Get-TheCleanersFileIdentity {
            throw [System.UnauthorizedAccessException]::new('Fixture queued identity denial.')
        } -ParameterFilter { $LiteralPath -eq $ChildPath }

        $Result = & $CommandName -RemoveEmptyDirectory -Confirm:$false -PassThru -ErrorAction SilentlyContinue -ErrorVariable Failure

        $Result.Status | Should -Be 'DiscoveryFailed'
        $Result.FileCandidateCount | Should -BeNullOrEmpty
        $Result.DirectoryCandidateCount | Should -BeNullOrEmpty
        $Result.ErrorIds | Should -Contain 'TempDiscoveryFailed'
        $Result.FilesRemoved | Should -Be 0
        @($Failure | Where-Object FullyQualifiedErrorId -Like 'TempDiscoveryFailed,*') | Should -HaveCount 1
        $Reported = $Failure | Where-Object FullyQualifiedErrorId -Like 'TempDiscoveryFailed,*'
        $Reported.Exception.Message | Should -BeLike '*queued directory identity required for safe mutation*'
        $CandidatePath | Should -Exist
        $SiblingPath | Should -Exist
        # A rename after failure proves discovery released the already-open ancestor.
        $RenamedParent = Join-Path -Path $TempRoot -ChildPath 'ReleasedParent'
        [System.IO.Directory]::Move($ParentPath, $RenamedParent)
        $RenamedParent | Should -Exist
    }
}
