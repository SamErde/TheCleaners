BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $TempCases = @(
        @{ CommandName = 'Clear-CurrentUserTemp' }
        @{ CommandName = 'Clear-WindowsTemp' }
    )
    $ReplacementCases = @(
        @{ Article = 'an'; ReplacementKind = 'empty'; HasReplacementContent = $false }
        @{ Article = 'a'; ReplacementKind = 'populated'; HasReplacementContent = $true }
    )
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
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
    Initialize-TheCleanersNativeFileInterop
    $OriginalTempPlan = ${function:Get-TheCleanersTempPlan}
}

Describe 'Temp directory identity closure: <CommandName>' -ForEach $TempCases -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        $PreviousSystemRoot = $env:SystemRoot
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $FakeWindows = Join-Path -Path $FixtureRoot -ChildPath 'Windows'
        $TempRoot = Join-Path -Path $FakeWindows -ChildPath 'Temp'
        $ParentPath = Join-Path -Path $TempRoot -ChildPath 'Touched'
        $ChildPath = Join-Path -Path $ParentPath -ChildPath 'Child'
        $UnrelatedPath = Join-Path -Path $TempRoot -ChildPath 'UnrelatedEmpty'
        $RecentPath = Join-Path -Path $TempRoot -ChildPath 'RecentBranch'
        $OutsidePath = Join-Path -Path $FixtureRoot -ChildPath 'Outside'
        $ReparsePath = Join-Path -Path $TempRoot -ChildPath 'ReparseBranch'
        foreach ($Path in @($ChildPath, $UnrelatedPath, $RecentPath, $OutsidePath)) {
            $null = New-Item -Path $Path -ItemType Directory -Force
        }
        $CandidatePath = Join-Path -Path $ChildPath -ChildPath 'old.tmp'
        [System.IO.File]::WriteAllText($CandidatePath, 'old')
        $RecentFilePath = Join-Path -Path $RecentPath -ChildPath 'recent.tmp'
        [System.IO.File]::WriteAllText($RecentFilePath, 'recent')
        $OutsideFilePath = Join-Path -Path $OutsidePath -ChildPath 'outside.tmp'
        [System.IO.File]::WriteAllText($OutsideFilePath, 'outside')
        $Now = [DateTime]::UtcNow
        [System.IO.File]::SetLastWriteTimeUtc($CandidatePath, $Now.AddDays(-31))
        [System.IO.File]::SetLastWriteTimeUtc($RecentFilePath, $Now)
        [System.IO.File]::SetLastWriteTimeUtc($OutsideFilePath, $Now.AddDays(-31))
        $null = New-Item -Path $ReparsePath -ItemType Junction -Target $OutsidePath -ErrorAction Stop

        $env:TEMP = $TempRoot
        $env:TMP = $TempRoot
        $env:SystemRoot = $FakeWindows
        $State = [pscustomobject]@{
            Handles = @()
        }
        Mock Get-TheCleanersWindowsTempRoot { Resolve-TheCleanersFileSystemPath -LiteralPath $TempRoot }
        Mock Get-Date { $Now }
    }

    AfterEach {
        foreach ($Handle in @($State.Handles)) {
            if ($null -ne $Handle -and -not $Handle.IsClosed) {
                $Handle.Dispose()
            }
        }
        if ([System.IO.Directory]::Exists($ReparsePath)) {
            [System.IO.Directory]::Delete($ReparsePath)
        }
        $env:TEMP = $PreviousTemp
        $env:TMP = $PreviousTmp
        $env:SystemRoot = $PreviousSystemRoot
    }

    It 'prevents a same-path replacement attempt with <Article> <ReplacementKind> payload while the planned handle is retained' -TestCases $ReplacementCases {
        param($Article, $ReplacementKind, $HasReplacementContent)

        $ReplacementSource = Join-Path -Path $FixtureRoot -ChildPath "Replacement-$ReplacementKind"
        $DisplacedPath = Join-Path -Path $FixtureRoot -ChildPath "Displaced-$ReplacementKind"
        $null = New-Item -Path $ReplacementSource -ItemType Directory
        if ($HasReplacementContent) {
            [System.IO.File]::WriteAllText((Join-Path -Path $ReplacementSource -ChildPath 'new.tmp'), 'new')
        }
        $script:ReplacementAttempted = $false
        $script:ReplacementInstalled = $false
        $script:ReplacementFailure = $null

        Mock Get-TheCleanersTempPlan {
            $Plan = & $OriginalTempPlan -Root $Root -TraversalRootPath $TraversalRootPath -CutoffUtc $CutoffUtc -RemoveEmptyDirectory:$RemoveEmptyDirectory -CaptureIdentity:$CaptureIdentity -ValidatedRootIdentity $ValidatedRootIdentity
            $State.Handles = @($Plan.HeldDirectoryHandles | ForEach-Object { $_.Handle })
            $Plan
        }
        Mock Get-Item {
            if ($LiteralPath -eq $ChildPath -and
                -not [System.IO.File]::Exists($CandidatePath) -and
                -not $script:ReplacementAttempted) {
                $script:ReplacementAttempted = $true
                try {
                    [System.IO.Directory]::Move($ChildPath, $DisplacedPath)
                    [System.IO.Directory]::Move($ReplacementSource, $ChildPath)
                    $script:ReplacementInstalled = $true
                } catch {
                    $script:ReplacementFailure = $_.Exception.GetBaseException()
                }
            }

            if ([System.IO.Directory]::Exists($LiteralPath)) {
                $Item = [System.IO.DirectoryInfo]::new($LiteralPath)
                $Item | Add-Member -MemberType NoteProperty -Name PSIsContainer -Value $true -Force
                return $Item
            }
            if ([System.IO.File]::Exists($LiteralPath)) {
                $Item = [System.IO.FileInfo]::new($LiteralPath)
                $Item | Add-Member -MemberType NoteProperty -Name PSIsContainer -Value $false -Force
                return $Item
            }
            throw [System.IO.FileNotFoundException]::new("Fixture path was not found: '$LiteralPath'.")
        }

        $Result = & $CommandName -Days 30 -RemoveEmptyDirectory -Confirm:$false -PassThru -ErrorAction Stop

        $script:ReplacementAttempted | Should -BeTrue
        $script:ReplacementInstalled | Should -BeFalse
        $script:ReplacementFailure | Should -Not -BeNullOrEmpty
        $DisplacedPath | Should -Not -Exist
        $ReplacementSource | Should -Exist
        if ($HasReplacementContent) {
            (Join-Path -Path $ReplacementSource -ChildPath 'new.tmp') | Should -Exist
        } else {
            @(Get-ChildItem -LiteralPath $ReplacementSource -Force) | Should -HaveCount 0
        }
        $Result.FilesRemoved | Should -Be 1
        $Result.DirectoriesRemoved | Should -Be 2
        $Result.DirectoryFailureCount | Should -Be 0
        $Result.Status | Should -Be 'Completed'
        $ChildPath | Should -Not -Exist
        $ParentPath | Should -Not -Exist
        @($State.Handles | Where-Object { -not $_.IsClosed }) | Should -HaveCount 0
    }

    It 'rejects and preserves an injected same-path replacement with <Article> <ReplacementKind> payload by native identity' -TestCases $ReplacementCases {
        param($Article, $ReplacementKind, $HasReplacementContent)

        $ReplacementSource = Join-Path -Path $FixtureRoot -ChildPath "InjectedReplacement-$ReplacementKind"
        $DisplacedPath = Join-Path -Path $FixtureRoot -ChildPath "OriginalDirectory-$ReplacementKind"
        $null = New-Item -Path $ReplacementSource -ItemType Directory
        if ($HasReplacementContent) {
            [System.IO.File]::WriteAllText((Join-Path -Path $ReplacementSource -ChildPath 'new.tmp'), 'new')
        }
        $script:ReplacementInjected = $false
        $script:OriginalCreationTimeUtc = $null
        $script:OriginalAttributes = $null
        $script:OriginalIdentity = $null
        $script:ReplacementCreationTimeUtc = $null
        $script:ReplacementAttributes = $null
        $script:ReplacementIdentity = $null
        $script:ChildPlan = $null

        Mock Get-TheCleanersTempPlan {
            $Plan = & $OriginalTempPlan -Root $Root -TraversalRootPath $TraversalRootPath -CutoffUtc $CutoffUtc -RemoveEmptyDirectory:$RemoveEmptyDirectory -CaptureIdentity:$CaptureIdentity -ValidatedRootIdentity $ValidatedRootIdentity
            $State.Handles = @($Plan.HeldDirectoryHandles | ForEach-Object { $_.Handle })
            $script:ChildPlan = @($Plan.Directories | Where-Object Path -EQ $ChildPath)[0]
            $script:OriginalIdentity = $script:ChildPlan.Identity
            $script:OriginalCreationTimeUtc = [System.IO.Directory]::GetCreationTimeUtc($ChildPath)
            $script:OriginalAttributes = [System.IO.File]::GetAttributes($ChildPath)
            $Plan
        }
        Mock Get-Item {
            if ($LiteralPath -eq $ChildPath -and
                -not [System.IO.File]::Exists($CandidatePath) -and
                -not $script:ReplacementInjected) {
                # Production retains this handle and therefore prevents the move.
                # This isolated fault injection removes only that primary barrier
                # to exercise the public command's independent native-ID refusal.
                $script:ChildPlan.Handle.Dispose()
                $script:ChildPlan.Handle = $null
                [System.IO.Directory]::Move($ChildPath, $DisplacedPath)
                [System.IO.Directory]::Move($ReplacementSource, $ChildPath)
                # Match mutable metadata before the identity read so path,
                # timestamps and attributes cannot explain the rejection.
                [System.IO.Directory]::SetCreationTimeUtc($ChildPath, $script:OriginalCreationTimeUtc)
                [System.IO.Directory]::SetLastWriteTimeUtc($ChildPath, $script:OriginalIdentity.LastWriteTimeUtc)
                [System.IO.File]::SetAttributes($ChildPath, $script:OriginalAttributes)
                $script:ReplacementCreationTimeUtc = [System.IO.Directory]::GetCreationTimeUtc($ChildPath)
                $script:ReplacementAttributes = [System.IO.File]::GetAttributes($ChildPath)
                $script:ReplacementIdentity = Get-TheCleanersFileIdentity -LiteralPath $ChildPath -Directory
                $script:ReplacementInjected = $true
            }

            if ([System.IO.Directory]::Exists($LiteralPath)) {
                $Item = [System.IO.DirectoryInfo]::new($LiteralPath)
                $Item | Add-Member -MemberType NoteProperty -Name PSIsContainer -Value $true -Force
                return $Item
            }
            if ([System.IO.File]::Exists($LiteralPath)) {
                $Item = [System.IO.FileInfo]::new($LiteralPath)
                $Item | Add-Member -MemberType NoteProperty -Name PSIsContainer -Value $false -Force
                return $Item
            }
            throw [System.IO.FileNotFoundException]::new("Fixture path was not found: '$LiteralPath'.")
        }

        $Result = & $CommandName -Days 30 -RemoveEmptyDirectory -Confirm:$false -PassThru -ErrorAction Stop

        $script:ReplacementInjected | Should -BeTrue
        $script:ReplacementCreationTimeUtc.ToFileTimeUtc() | Should -Be $script:OriginalCreationTimeUtc.ToFileTimeUtc()
        $script:ReplacementIdentity.LastWriteTimeUtc.ToFileTimeUtc() | Should -Be $script:OriginalIdentity.LastWriteTimeUtc.ToFileTimeUtc()
        [uint32]$script:ReplacementAttributes | Should -Be ([uint32]$script:OriginalAttributes)
        [uint32]$script:ReplacementIdentity.Attributes | Should -Be ([uint32]$script:OriginalIdentity.Attributes)
        $script:OriginalIdentity.Equals($script:ReplacementIdentity) | Should -BeFalse
        $script:OriginalIdentity.Equals((Get-TheCleanersFileIdentity -LiteralPath $DisplacedPath -Directory)) | Should -BeTrue
        $ChildPath | Should -Exist
        $DisplacedPath | Should -Exist
        if ($HasReplacementContent) {
            (Join-Path -Path $ChildPath -ChildPath 'new.tmp') | Should -Exist
        } else {
            @(Get-ChildItem -LiteralPath $ChildPath -Force) | Should -HaveCount 0
        }
        $Result.FilesRemoved | Should -Be 1
        $Result.DirectoriesRemoved | Should -Be 0
        $Result.DirectoriesSkipped | Should -Be 2
        $Result.DirectoryFailureCount | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
        @($State.Handles | Where-Object { -not $_.IsClosed }) | Should -HaveCount 0
    }

    It 'prunes genuine directories deepest-first while preserving root, unrelated, recent, and reparse branches' {
        $Result = & $CommandName -Days 30 -RemoveEmptyDirectory -Confirm:$false -PassThru -ErrorAction Stop

        $Result.FilesRemoved | Should -Be 1
        $Result.DirectoryCandidateCount | Should -Be 2
        $Result.DirectoriesRemoved | Should -Be 2
        $Result.Status | Should -Be 'Completed'
        $ChildPath | Should -Not -Exist
        $ParentPath | Should -Not -Exist
        $TempRoot | Should -Exist
        $UnrelatedPath | Should -Exist
        $RecentFilePath | Should -Exist
        $ReparsePath | Should -Exist
        $OutsideFilePath | Should -Exist
    }

    It 'keeps every fixture intact under WhatIf' {
        $Result = & $CommandName -Days 30 -RemoveEmptyDirectory -WhatIf -PassThru -ErrorAction Stop

        $Result.Status | Should -Be 'WhatIf'
        $Result.FileCandidateCount | Should -Be 1
        $Result.DirectoryCandidateCount | Should -Be 2
        $Result.FilesRemoved | Should -Be 0
        $Result.DirectoriesRemoved | Should -Be 0
        $CandidatePath | Should -Exist
        $ChildPath | Should -Exist
        $ParentPath | Should -Exist
        $TempRoot | Should -Exist
        $UnrelatedPath | Should -Exist
        $RecentFilePath | Should -Exist
        $ReparsePath | Should -Exist
        $OutsideFilePath | Should -Exist
    }

    It 'honors ErrorAction Stop and preserves directory ancestry after candidate deletion fails' {
        $CandidateLock = [System.IO.File]::Open($CandidatePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            { & $CommandName -Days 30 -RemoveEmptyDirectory -Confirm:$false -ErrorAction Stop } | Should -Throw -ErrorId 'TempFileRemovalFailed,*'
        } finally {
            $CandidateLock.Dispose()
        }

        $CandidatePath | Should -Exist
        $ChildPath | Should -Exist
        $ParentPath | Should -Exist
        $TempRoot | Should -Exist
    }
}
