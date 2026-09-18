BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $TempCases = @(
        @{ CommandName = 'Clear-CurrentUserTemp' }
        @{ CommandName = 'Clear-WindowsTemp' }
    )
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../TheCleaners')).Path
    foreach ($RelativePath in @(
        'Private/ResultContracts.ps1'
        'Private/Initialize-TheCleanersNativeFileInterop.ps1'
        'Private/Get-TheCleanersWindowsTempRoot.ps1'
        'Private/Get-TheCleanersTempPlan.ps1'
        'Private/Resolve-TheCleanersFileSystemPath.ps1'
        'Public/Clear-CurrentUserTemp.ps1'
        'Public/Clear-WindowsTemp.ps1'
    )) {
        . (Join-Path $ModuleRoot $RelativePath)
    }
    $RealResolver = (Get-Command Resolve-TheCleanersFileSystemPath).ScriptBlock
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Initialize-TheCleanersNativeFileInterop
        if (-not ('TheCleaners.Tests.RetentionAttributes' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace TheCleaners.Tests {
    public static class RetentionAttributes {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(string path, uint access, uint share,
            IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetFileTime(SafeFileHandle handle, IntPtr creation,
            IntPtr access, ref long write);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateHardLinkW(string path, string existing, IntPtr security);
        public static void Link(string path, string existing) {
            if (!CreateHardLinkW(path, existing, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        public static void SetLastWrite(string path, DateTime timestamp) {
            // FILE_WRITE_ATTRIBUTES is deliberately distinct from FILE_WRITE_DATA.
            using (SafeFileHandle handle = CreateFileW(path, 0x100, 7, IntPtr.Zero, 3,
                0x00200000, IntPtr.Zero)) {
                if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                long value = timestamp.ToFileTimeUtc();
                if (!SetFileTime(handle, IntPtr.Zero, IntPtr.Zero, ref value))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
    }
}
'@ -ErrorAction Stop
        }
    }
}

Describe 'Retention acquisition barrier: <CommandName>' -ForEach $TempCases -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        $PreviousSystemRoot = $env:SystemRoot
        $FixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $FakeWindows = Join-Path $FixtureRoot 'Windows'
        $TempRoot = Join-Path $FakeWindows 'Temp'
        $null = New-Item $TempRoot -ItemType Directory -Force
        $CandidatePath = Join-Path $TempRoot 'candidate.tmp'
        $SavedPath = Join-Path $FixtureRoot 'original.tmp'
        [System.IO.File]::WriteAllBytes($CandidatePath, [byte[]](1, 2, 3))
        $Now = [DateTime]::UtcNow
        [System.IO.File]::SetLastWriteTimeUtc($CandidatePath, $Now.AddDays(-31))
        $OriginalIdentity = Get-TheCleanersFileIdentity -LiteralPath $CandidatePath
        $env:TEMP = $TempRoot
        $env:TMP = $TempRoot
        $env:SystemRoot = $FakeWindows
        $Barrier = @{ Count = 0; Action = {}; Writer = $null }
        Mock Get-Date { $Now }
        Mock Get-TheCleanersWindowsTempRoot { & $RealResolver -LiteralPath $TempRoot }
        Mock Resolve-TheCleanersFileSystemPath {
            param($LiteralPath, $RootPath)
            $Arguments = @{ LiteralPath = $LiteralPath }
            if ($RootPath) { $Arguments.RootPath = $RootPath }
            $Resolved = & $RealResolver @Arguments
            if ($LiteralPath -eq $CandidatePath -and $RootPath) {
                # This call is after discovery, ShouldProcess and path/type preflight.
                # Refresh/Exists and the native open follow it; no timestamp precheck
                # can establish the replacement's eligibility for the deletion handle.
                $Barrier.Count++
                & $Barrier.Action
            }
            $Resolved
        }
    }

    AfterEach {
        if ($null -ne $Barrier.Writer) { $Barrier.Writer.Dispose() }
        $env:TEMP = $PreviousTemp
        $env:TMP = $PreviousTmp
        $env:SystemRoot = $PreviousSystemRoot
    }

    It 'rejects a <Age> regular replacement immediately before acquisition' -ForEach @(
        @{ Age = 'recent'; ReplacementDays = 0 }
        @{ Age = 'different old'; ReplacementDays = -40 }
    ) {
        $Barrier.Action = {
            # Keep the approved object alive at another name to prevent file-ID reuse.
            [System.IO.File]::Move($CandidatePath, $SavedPath)
            [System.IO.File]::WriteAllBytes($CandidatePath, [byte[]](8, 9, 10, 11))
            [System.IO.File]::SetLastWriteTimeUtc($CandidatePath, $Now.AddDays($ReplacementDays))
        }
        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru
        $Barrier.Count | Should -Be 1
        (Get-TheCleanersFileIdentity -LiteralPath $CandidatePath).Equals($OriginalIdentity) | Should -BeFalse
        (Get-TheCleanersFileIdentity -LiteralPath $SavedPath).Equals($OriginalIdentity) | Should -BeTrue
        [System.IO.File]::ReadAllBytes($CandidatePath) | Should -Be @(8, 9, 10, 11)
        $Result.FileCandidateCount | Should -Be 1
        $Result.FilesSkipped | Should -Be 1
        $Result.FilesRemoved | Should -Be 0
        $Result.FileFailureCount | Should -Be 0
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
    }

    It 'uses current same-object retention after <Change> before acquisition' -ForEach @(
        @{ Change = 'timestamp update'; WriteContent = $false }
        @{ Change = 'content and timestamp update'; WriteContent = $true }
    ) {
        $Barrier.Action = {
            if ($WriteContent) { [System.IO.File]::WriteAllBytes($CandidatePath, [byte[]](4, 5, 6, 7, 8)) }
            [System.IO.File]::SetLastWriteTimeUtc($CandidatePath, $Now)
        }
        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru
        $Barrier.Count | Should -Be 1
        (Get-TheCleanersFileIdentity -LiteralPath $CandidatePath).Equals($OriginalIdentity) | Should -BeTrue
        $Result.FilesSkipped | Should -Be 1
        $Result.FilesRemoved | Should -Be 0
        $Result.FileFailureCount | Should -Be 0
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
    }

    It 'counts the current logical length when the same object still meets the inclusive cutoff' {
        $Barrier.Action = {
            [System.IO.File]::WriteAllBytes($CandidatePath, [byte[]](1, 2, 3, 4, 5, 6, 7))
            [System.IO.File]::SetLastWriteTimeUtc($CandidatePath, $Now.AddDays(-30))
        }
        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru
        $Barrier.Count | Should -Be 1
        $CandidatePath | Should -Not -Exist
        $Result.FilesRemoved | Should -Be 1
        $Result.FilesSkipped | Should -Be 0
        $Result.FileFailureCount | Should -Be 0
        $Result.BytesReclaimed | Should -Be 7
    }

    It 'skips a renamed approved object without chasing its new path' {
        $Barrier.Action = { [System.IO.File]::Move($CandidatePath, $SavedPath) }
        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru
        $Barrier.Count | Should -Be 1
        $CandidatePath | Should -Not -Exist
        (Get-TheCleanersFileIdentity -LiteralPath $SavedPath).Equals($OriginalIdentity) | Should -BeTrue
        $Result.FilesSkipped | Should -Be 1
        $Result.FilesRemoved | Should -Be 0
        $Result.FileFailureCount | Should -Be 0
        $Result.BytesReclaimed | Should -Be 0
    }

    It 'preserves a <ReplacementType> substituted after path preflight' -ForEach @(
        @{ ReplacementType = 'directory' }
        @{ ReplacementType = 'junction' }
    ) {
        $TargetPath = Join-Path $FixtureRoot 'Target'
        $null = New-Item $TargetPath -ItemType Directory
        $ProtectedPath = Join-Path $TargetPath 'protected.tmp'
        [System.IO.File]::WriteAllBytes($ProtectedPath, [byte[]](4, 5, 6))
        $Barrier.Action = {
            [System.IO.File]::Move($CandidatePath, $SavedPath)
            if ($ReplacementType -eq 'junction') {
                $null = New-Item -Path $CandidatePath -ItemType Junction -Target $TargetPath -ErrorAction Stop
            } else {
                $null = New-Item -Path $CandidatePath -ItemType Directory -ErrorAction Stop
            }
        }
        try {
            $Result = & $CommandName -Days 30 -Confirm:$false -PassThru
            $Barrier.Count | Should -Be 1
            [System.IO.Directory]::Exists($CandidatePath) | Should -BeTrue
            $SavedPath | Should -Exist
            [System.IO.File]::ReadAllBytes($ProtectedPath) | Should -Be @(4, 5, 6)
            $Result.FilesRemoved | Should -Be 0
            $Result.FilesSkipped | Should -Be 1
            $Result.FileFailureCount | Should -Be 0
            $Result.BytesReclaimed | Should -Be 0
        } finally {
            # Remove only the fixture link itself before Pester cleans TestDrive.
            if ($ReplacementType -eq 'junction' -and [System.IO.Directory]::Exists($CandidatePath)) {
                [System.IO.Directory]::Delete($CandidatePath)
            }
        }
    }

    It 'removes an approved name relinked to the same object and preserves its other name' {
        $Barrier.Action = {
            [System.IO.File]::Move($CandidatePath, $SavedPath)
            [TheCleaners.Tests.RetentionAttributes]::Link($CandidatePath, $SavedPath)
        }
        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru
        $Barrier.Count | Should -Be 1
        $CandidatePath | Should -Not -Exist
        (Get-TheCleanersFileIdentity -LiteralPath $SavedPath).Equals($OriginalIdentity) | Should -BeTrue
        [System.IO.File]::ReadAllBytes($SavedPath) | Should -Be @(1, 2, 3)
        $Result.FilesRemoved | Should -Be 1
        $Result.FilesSkipped | Should -Be 0
        $Result.FileFailureCount | Should -Be 0
        $Result.BytesReclaimed | Should -Be 3
    }

    It 'reports a writer arriving after discovery as a permission failure' {
        $Barrier.Action = {
            $Barrier.Writer = [System.IO.File]::Open($CandidatePath, 'Open', 'Write', 'ReadWrite, Delete')
        }
        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru -ErrorAction SilentlyContinue -ErrorVariable CleanupErrors
        $Barrier.Count | Should -Be 1
        $CandidatePath | Should -Exist
        # ErrorVariable also collects the caught method-invocation exception.
        $ReportedErrors = @($CleanupErrors | Where-Object FullyQualifiedErrorId -Match '^TempFileRemovalFailed')
        $ReportedErrors | Should -HaveCount 1
        $ReportedErrors[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        $ReportedErrors[0].Exception.GetBaseException().NativeErrorCode | Should -Be 32
        $Result.FilesRemoved | Should -Be 0
        $Result.FilesSkipped | Should -Be 0
        $Result.FileFailureCount | Should -Be 1
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'PartialFailure'
    }

    It 'terminates on acquisition failure with ErrorAction Stop and releases plan handles' {
        $Barrier.Action = {
            $Barrier.Writer = [System.IO.File]::Open($CandidatePath, 'Open', 'Write', 'ReadWrite, Delete')
        }
        $Caught = $null
        try { $null = & $CommandName -Days 30 -Confirm:$false -PassThru -ErrorAction Stop } catch { $Caught = $_ }
        $Barrier.Count | Should -Be 1
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -Match '^TempFileRemovalFailed'
        $Caught.Exception.GetBaseException().NativeErrorCode | Should -Be 32
        $Barrier.Writer.Dispose()
        $Barrier.Writer = $null
        $MovedRoot = Join-Path $FakeWindows 'Released'
        [System.IO.Directory]::Move($TempRoot, $MovedRoot)
        (Join-Path $MovedRoot 'candidate.tmp') | Should -Exist
    }

    It 'never reaches the acquisition barrier under WhatIf' {
        $Result = & $CommandName -Days 30 -WhatIf -PassThru
        $Barrier.Count | Should -Be 0
        $CandidatePath | Should -Exist
        $Result.FilesRemoved | Should -Be 0
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'WhatIf'
    }
}

Describe 'Native retention observation contract' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $CandidatePath = Join-Path $TestDrive ('retention-' + [guid]::NewGuid().Guid + '.tmp')
        [System.IO.File]::WriteAllBytes($CandidatePath, [byte[]](1, 2, 3))
        $OldTime = [DateTime]::UtcNow.AddDays(-31)
        [System.IO.File]::SetLastWriteTimeUtc($CandidatePath, $OldTime)
    }

    It 'leaves the object intact when an acquired and inspected handle closes without disposition' {
        $Identity = Get-TheCleanersFileIdentity -LiteralPath $CandidatePath
        $Handle = [TheCleaners.NativeFileInterop]::OpenForDeletion($CandidatePath, $false)
        try {
            ([TheCleaners.NativeFileInterop]::ReadIdentity($Handle)).Equals($Identity) | Should -BeTrue
        } finally { $Handle.Dispose() }
        $CandidatePath | Should -Exist
        [System.IO.File]::ReadAllBytes($CandidatePath) | Should -Be @(1, 2, 3)
    }

    It 'rejects a new data writer until the inspected handle closes' {
        $Handle = [TheCleaners.NativeFileInterop]::OpenForDeletion($CandidatePath, $false)
        try {
            $Writer = $null
            $Caught = $null
            try { $Writer = [System.IO.File]::Open($CandidatePath, 'Open', 'Write', 'ReadWrite, Delete') } catch { $Caught = $_ }
            finally { if ($null -ne $Writer) { $Writer.Dispose() } }
            $Caught | Should -Not -BeNullOrEmpty
            ($Caught.Exception.GetBaseException().HResult -band 0xffff) | Should -Be 32
        } finally { $Handle.Dispose() }
        $Writer = [System.IO.File]::Open($CandidatePath, 'Open', 'Write', 'ReadWrite, Delete')
        $Writer.Dispose()
    }

    It 'permits attribute-only timestamp changes and observes them on the same handle' {
        $Handle = [TheCleaners.NativeFileInterop]::OpenForDeletion($CandidatePath, $false)
        try {
            $Before = [TheCleaners.NativeFileInterop]::ReadIdentity($Handle)
            $RecentTime = [DateTime]::UtcNow
            [TheCleaners.Tests.RetentionAttributes]::SetLastWrite($CandidatePath, $RecentTime)
            $After = [TheCleaners.NativeFileInterop]::ReadIdentity($Handle)
            $After.Equals($Before) | Should -BeTrue
            $Before.LastWriteTimeUtc | Should -Be $OldTime
            $After.LastWriteTimeUtc | Should -Be $RecentTime
        } finally { $Handle.Dispose() }
        $CandidatePath | Should -Exist
    }

    It 'does not turn an earlier metadata observation into an atomic timestamp predicate at disposition' {
        $Handle = [TheCleaners.NativeFileInterop]::OpenForDeletion($CandidatePath, $false)
        try {
            $Observed = [TheCleaners.NativeFileInterop]::ReadIdentity($Handle)
            $Observed.LastWriteTimeUtc | Should -Be $OldTime
            [TheCleaners.Tests.RetentionAttributes]::SetLastWrite($CandidatePath, [DateTime]::UtcNow)
            # Deliberately demonstrate the documented native limit using fixture data.
            [TheCleaners.NativeFileInterop]::MarkForDeletion($Handle)
        } finally { $Handle.Dispose() }
        $CandidatePath | Should -Not -Exist
    }
}
