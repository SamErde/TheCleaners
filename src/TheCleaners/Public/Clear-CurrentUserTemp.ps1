function Clear-CurrentUserTemp {
    <#
    .SYNOPSIS
        Remove old files from the current user's Windows temporary directory.
    .DESCRIPTION
        Discover candidates under the current user's temporary root using one
        inclusive UTC cutoff. Candidate file IDs and directory IDs are captured
        during discovery and compared with the same native handle used for the
        deletion request. The handle requests DELETE access only; it does not read
        file contents. Directory removal is opt-in, non-recursive, deepest-first,
        and limited to directories emptied by this invocation. Reparse points,
        roots, unrelated branches, replacements, hard-link identity changes, and
        paths outside the approved root are preserved. These checks are not an
        atomic defense against a hostile filesystem filter or a filesystem that
        does not provide stable file IDs.
    .PARAMETER Days
        Retain files newer than Days days ago. The default is 30 days.
    .PARAMETER RemoveEmptyDirectory
        Also remove directories emptied by this invocation and their now-empty
        ancestors. The cleanup root and pre-existing empty branches are preserved.
    .PARAMETER PassThru
        Return a TheCleaners.CleanupResult summary.
    .EXAMPLE
        Clear-CurrentUserTemp -Days 30 -WhatIf -PassThru
    .EXAMPLE
        Clear-CurrentUserTemp -Days 30 -RemoveEmptyDirectory -Confirm
    .OUTPUTS
        TheCleaners.CleanupResult
    .LINK
        https://day3bits.com/thecleaners/Clear-CurrentUserTemp/
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [Alias('Clean-CurrentUserTemp')]
    [OutputType('TheCleaners.CleanupResult')]
    param (
        [Parameter()]
        [ValidateRange(1, [Int16]::MaxValue)]
        [Int16]
        $Days = 30,

        [Parameter()]
        [switch]
        $RemoveEmptyDirectory,

        [Parameter()]
        [switch]
        $PassThru
    )

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $Exception = [System.PlatformNotSupportedException]::new('Clear-CurrentUserTemp requires Windows.')
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'TempWindowsRequired' -Category NotImplemented
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    $Root = $null
    try {
        $RequestedTempPath = [System.IO.Path]::GetTempPath()
        $Root = Resolve-TheCleanersFileSystemPath -LiteralPath $RequestedTempPath
        $LocalApplicationData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($LocalApplicationData)) {
            throw [System.InvalidOperationException]::new('The current user local application-data directory could not be resolved.')
        }
        $CanonicalUserTemp = Resolve-TheCleanersFileSystemPath -LiteralPath (Join-Path -Path $LocalApplicationData -ChildPath 'Temp')
        $CanonicalUserTempPath = Convert-TheCleanersPathForComparison -Path $CanonicalUserTemp.FullName
        $RequestedTempComparison = Convert-TheCleanersPathForComparison -Path $Root.FullName
        $AllowedDescendantPrefix = $CanonicalUserTempPath + [System.IO.Path]::DirectorySeparatorChar
        if ($RequestedTempComparison -ne $CanonicalUserTempPath -and -not $RequestedTempComparison.StartsWith($AllowedDescendantPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw [System.UnauthorizedAccessException]::new("The current-user temporary path is outside the canonical user temp root: '$($Root.FullName)'.")
        }
    } catch {
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'TempRootValidationFailed' -Category InvalidData
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    $CutoffUtc = (Get-Date).ToUniversalTime().AddDays(-$Days)
    $Result = Get-TheCleanersCleanupResult -Command 'Clear-CurrentUserTemp' -RootPath $Root.FullName.TrimEnd([char[]]@('\', '/')) -CutoffUtc $CutoffUtc -PrivilegeStatus (Get-TheCleanersPrivilegeStatus)
    try {
        $Plan = Get-TheCleanersTempPlan -Root $Root -CutoffUtc $CutoffUtc -RemoveEmptyDirectory:$RemoveEmptyDirectory -CaptureIdentity:(-not $WhatIfPreference)
    } catch {
        $Result.DiscoveryStatus = 'Failed'
        $Result.Status = 'DiscoveryFailed'
        $Result.FileCandidateCount = $null
        $Result.DirectoryCandidateCount = $null
        $Result.DiscoveryErrorCount = 1
        $Result.ErrorIds = @('TempDiscoveryFailed')
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'TempDiscoveryFailed' -Category ReadError -TargetObject $Result.RootPath
        $PSCmdlet.WriteError($ErrorRecord)
        if ($PassThru) {
            $Result
        }
        return
    }

    $Files = @($Plan.Files)
    $Directories = @($Plan.Directories)
    $Result.CandidatePaths = @($Files | ForEach-Object { $_.Path })
    $Result.FileCandidateCount = $Files.Count
    $Result.DirectoryCandidateCount = $Directories.Count
    foreach ($File in $Files) {
        Write-Verbose -Message ('Candidate file: {0}' -f $File.Path)
    }
    foreach ($Directory in $Directories) {
        Write-Verbose -Message ('Planned directory: {0}' -f $Directory.Path)
    }
    if ($Files.Count -eq 0) {
        if ($PassThru) {
            $Result
        }
        return
    }

    $Action = 'Remove {0} old temp files and up to {1} identity-checked directories; inclusive UTC cutoff {2:u}' -f $Files.Count, $Directories.Count, $CutoffUtc
    if (-not $PSCmdlet.ShouldProcess($Result.RootPath, $Action)) {
        $Result.Status = if ($WhatIfPreference) { 'WhatIf' } else { 'Declined' }
        if ($PassThru) {
            $Result
        }
        return
    }

    try {
        $CurrentRootIdentity = Get-TheCleanersFileIdentity -LiteralPath $Result.RootPath -Directory
        if ($CurrentRootIdentity.IsReparsePoint -or -not $CurrentRootIdentity.Equals($Plan.RootIdentity)) {
            throw [System.IO.InvalidDataException]::new("The cleanup root changed after discovery: '$($Result.RootPath)'.")
        }
    } catch {
        $Result.Status = 'DiscoveryFailed'
        $Result.DiscoveryStatus = 'Failed'
        $Result.DiscoveryErrorCount = 1
        $Result.ErrorIds = @('TempRootChanged')
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'TempRootChanged' -Category InvalidData -TargetObject $Result.RootPath
        $PSCmdlet.WriteError($ErrorRecord)
        if ($PassThru) {
            $Result
        }
        return
    }

    $TouchedIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ReparsePointAttributes = [System.IO.FileAttributes]::ReparsePoint
    foreach ($Candidate in $Files) {
        $CurrentHandle = $null
        try {
            $CurrentItem = Get-Item -LiteralPath $Candidate.Path -Force -ErrorAction Stop
            if ($CurrentItem.PSIsContainer -or ($CurrentItem.Attributes -band $ReparsePointAttributes)) {
                $Result.FilesSkipped++
                continue
            }
            $null = Resolve-TheCleanersFileSystemPath -LiteralPath $Candidate.Path -RootPath $Result.RootPath
            $CurrentItem.Refresh()
            if (-not $CurrentItem.Exists -or $CurrentItem.LastWriteTimeUtc -gt $Plan.CutoffUtc) {
                $Result.FilesSkipped++
                continue
            }
            $CurrentHandle = [TheCleaners.NativeFileInterop]::OpenForDeletion($Candidate.Path, $false)
            $CurrentIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($CurrentHandle)
            if ($CurrentIdentity.IsDirectory -or $CurrentIdentity.IsReparsePoint -or $null -eq $Candidate.Identity -or -not $CurrentIdentity.Equals($Candidate.Identity)) {
                $Result.FilesSkipped++
                continue
            }
            $Length = $CurrentIdentity.Length
            [TheCleaners.NativeFileInterop]::MarkForDeletion($CurrentHandle)
        } catch {
            $BaseException = $_.Exception.GetBaseException()
            $NativeErrorCode = if ($BaseException -is [System.ComponentModel.Win32Exception]) { $BaseException.NativeErrorCode } else { -1 }
            $MissingCandidate = $_.Exception -is [System.Management.Automation.ItemNotFoundException] -or $BaseException -is [System.IO.FileNotFoundException] -or $BaseException -is [System.IO.DirectoryNotFoundException] -or $NativeErrorCode -in @(2, 3, 53, 123)
            if ($MissingCandidate) {
                $Result.FilesSkipped++
            } else {
                $Result.FileFailureCount++
                $Result.ErrorIds = @($Result.ErrorIds + 'TempFileRemovalFailed')
                $Category = if ($BaseException -is [System.UnauthorizedAccessException] -or $NativeErrorCode -in @(5, 32, 33)) { 'PermissionDenied' } else { 'WriteError' }
                $ErrorRecord = Get-TheCleanersErrorRecord -Exception $BaseException -ErrorId 'TempFileRemovalFailed' -Category $Category -TargetObject $Candidate.Path
                $PSCmdlet.WriteError($ErrorRecord)
            }
            continue
        } finally {
            if ($null -ne $CurrentHandle) {
                $CurrentHandle.Dispose()
            }
        }

        if ([System.IO.File]::Exists($Candidate.Path) -or [System.IO.Directory]::Exists($Candidate.Path)) {
            $Result.FileFailureCount++
            $Result.ErrorIds = @($Result.ErrorIds + 'TempFileRemovalFailed')
            $Exception = [System.IO.IOException]::new("The candidate path still exists after its deletion handle closed: '$($Candidate.Path)'.")
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'TempFileRemovalFailed' -Category WriteError -TargetObject $Candidate.Path
            $PSCmdlet.WriteError($ErrorRecord)
            continue
        }

        $Result.FilesRemoved++
        $Result.BytesReclaimed += $Length
        if ($null -ne $Candidate.ParentIdentity) {
            $null = $TouchedIdentities.Add($Candidate.ParentIdentity.Key)
        }
    }

    foreach ($DirectoryPlan in $Directories) {
        if ($null -eq $DirectoryPlan.Identity -or -not $TouchedIdentities.Contains($DirectoryPlan.Identity.Key)) {
            $Result.DirectoriesSkipped++
            continue
        }

        $CurrentHandle = $null
        try {
            $CurrentDirectory = Get-Item -LiteralPath $DirectoryPlan.Path -Force -ErrorAction Stop
            if ($CurrentDirectory -isnot [System.IO.DirectoryInfo] -or ($CurrentDirectory.Attributes -band $ReparsePointAttributes)) {
                $Result.DirectoriesSkipped++
                continue
            }
            $null = Resolve-TheCleanersFileSystemPath -LiteralPath $DirectoryPlan.Path -RootPath $Result.RootPath
            $CurrentHandle = [TheCleaners.NativeFileInterop]::OpenForDeletion($DirectoryPlan.Path, $true)
            $CurrentIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($CurrentHandle)
            if (-not $CurrentIdentity.IsDirectory -or $CurrentIdentity.IsReparsePoint -or -not $CurrentIdentity.Equals($DirectoryPlan.Identity)) {
                $Result.DirectoriesSkipped++
                continue
            }
            if (@(Get-ChildItem -LiteralPath $DirectoryPlan.Path -Force -ErrorAction Stop).Count -gt 0) {
                $Result.DirectoriesSkipped++
                continue
            }
            [TheCleaners.NativeFileInterop]::MarkForDeletion($CurrentHandle)
        } catch {
            $BaseException = $_.Exception.GetBaseException()
            $NativeErrorCode = if ($BaseException -is [System.ComponentModel.Win32Exception]) { $BaseException.NativeErrorCode } else { -1 }
            $MissingDirectory = $_.Exception -is [System.Management.Automation.ItemNotFoundException] -or $BaseException -is [System.IO.DirectoryNotFoundException] -or $NativeErrorCode -in @(2, 3, 53, 123)
            if ($MissingDirectory) {
                $Result.DirectoriesSkipped++
            } else {
                $Result.DirectoryFailureCount++
                $Result.ErrorIds = @($Result.ErrorIds + 'TempDirectoryRemovalFailed')
                $Category = if ($BaseException -is [System.UnauthorizedAccessException] -or $NativeErrorCode -in @(5, 32, 33)) { 'PermissionDenied' } else { 'WriteError' }
                $ErrorRecord = Get-TheCleanersErrorRecord -Exception $BaseException -ErrorId 'TempDirectoryRemovalFailed' -Category $Category -TargetObject $DirectoryPlan.Path
                $PSCmdlet.WriteError($ErrorRecord)
            }
            continue
        } finally {
            if ($null -ne $CurrentHandle) {
                $CurrentHandle.Dispose()
            }
        }

        if ([System.IO.Directory]::Exists($DirectoryPlan.Path)) {
            $Result.DirectoryFailureCount++
            $Result.ErrorIds = @($Result.ErrorIds + 'TempDirectoryRemovalFailed')
            $Exception = [System.IO.IOException]::new("The directory path still exists after its deletion handle closed: '$($DirectoryPlan.Path)'.")
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'TempDirectoryRemovalFailed' -Category WriteError -TargetObject $DirectoryPlan.Path
            $PSCmdlet.WriteError($ErrorRecord)
            continue
        }

        $Result.DirectoriesRemoved++
        if ($null -ne $DirectoryPlan.ParentIdentity) {
            $null = $TouchedIdentities.Add($DirectoryPlan.ParentIdentity.Key)
        }
    }

    $Result.Status = if ($Result.FileFailureCount -gt 0 -or $Result.DirectoryFailureCount -gt 0) {
        'PartialFailure'
    } elseif ($Result.FilesSkipped -gt 0 -or $Result.DirectoriesSkipped -gt 0) {
        'CompletedWithSkips'
    } else {
        'Completed'
    }
    if ($PassThru) {
        $Result
    }
}
