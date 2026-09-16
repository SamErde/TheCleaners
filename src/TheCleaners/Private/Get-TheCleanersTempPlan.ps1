function Get-TheCleanersTempPlan {
    <#
    .SYNOPSIS
        Discover old temporary files and identity-bound directory candidates.
    .DESCRIPTION
        This function only reads the approved root. It records native file IDs for
        candidates and touched directories so the owning public command can compare
        the object opened for mutation with the object found during discovery.
        Discovery errors are terminating to prevent partial plans from being used.
        When identity capture is enabled, each queued directory is opened with a
        stable native handle while the provider enumerates it and its identity is
        captured, so directory replacement or rename fails closed. The returned
        plan retains only handles for candidate-file ancestors and planned empty
        directories; branches with no mutation candidate are released after
        discovery. Retained handles remain open through candidate mutation,
        preventing a required ancestor from being renamed or replaced by a
        reparse point before a file is opened for deletion.
    .PARAMETER Root
        Previously validated temporary directory.
    .PARAMETER CutoffUtc
        Inclusive UTC retention cutoff.
    .PARAMETER RemoveEmptyDirectory
        Include directories that can become empty after file removal.
    .PARAMETER CaptureIdentity
        Capture native file and directory identities for a removal-enabled plan
        and retain only the stable directory handles required through mutation.
        Omit this switch for WhatIf discovery so the preview does not initialize
        process-global native interop state.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]
        $Root,

        [Parameter(Mandatory)]
        [DateTime]
        $CutoffUtc,

        [Parameter()]
        [switch]
        $RemoveEmptyDirectory,

        [Parameter()]
        [switch]
        $CaptureIdentity
    )

    $HeldDirectoryHandles = [System.Collections.Generic.List[object]]::new()
    $HeldDirectoryHandleByPath = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    try {
        $RootPath = $Root.FullName.TrimEnd([char[]]@('\', '/'))
        $RootIdentity = $null
        if ($CaptureIdentity) {
            Initialize-TheCleanersNativeFileInterop
            $RootIdentity = Get-TheCleanersFileIdentity -LiteralPath $RootPath -Directory
            if ($RootIdentity.IsReparsePoint) {
                throw [System.IO.InvalidDataException]::new("The cleanup root is a reparse point: '$RootPath'.")
            }
        }

        $Candidates = [System.Collections.Generic.List[object]]::new()
        $FilePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $DirectoryPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Pending = [System.Collections.Generic.Stack[object]]::new()
        $Pending.Push([pscustomobject]@{
                Path     = $RootPath
                Identity = $RootIdentity
            })

        while ($Pending.Count -gt 0) {
            $DirectoryState = $Pending.Pop()
            $DirectoryPath = [string]$DirectoryState.Path
            $Directory = Resolve-TheCleanersFileSystemPath -LiteralPath $DirectoryPath
            if ($Directory -isnot [System.IO.DirectoryInfo]) {
                throw [System.IO.InvalidDataException]::new("The temp traversal path is not a directory: '$DirectoryPath'.")
            }
            $DirectoryHandle = $null
            try {
                if ($CaptureIdentity) {
                    Initialize-TheCleanersNativeFileInterop
                    $DirectoryHandle = [TheCleaners.NativeFileInterop]::OpenForStableEnumeration($DirectoryPath)
                    $HeldDirectoryEntry = [pscustomobject]@{
                        Path     = $DirectoryPath
                        Handle   = $DirectoryHandle
                        Identity = $null
                    }
                    $HeldDirectoryHandles.Add($HeldDirectoryEntry)
                    $HeldDirectoryHandleByPath[$DirectoryPath] = $HeldDirectoryEntry
                    $DirectoryHandle = $null
                    $DirectoryIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($HeldDirectoryEntry.Handle)
                    $HeldDirectoryEntry.Identity = $DirectoryIdentity
                    if (-not $DirectoryIdentity.IsDirectory -or $DirectoryIdentity.IsReparsePoint -or $null -eq $DirectoryState.Identity -or -not $DirectoryIdentity.Equals($DirectoryState.Identity)) {
                        throw [System.IO.InvalidDataException]::new("The queued temp directory changed before traversal: '$DirectoryPath'.")
                    }
                }

                foreach ($Item in @(Get-ChildItem -LiteralPath $Directory.FullName -Force -ErrorAction Stop)) {
                    if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                        Write-Verbose -Message "Skipping reparse point: $($Item.FullName)"
                        continue
                    }
                    if ($Item.PSIsContainer) {
                        $ChildIdentity = $null
                        if ($CaptureIdentity) {
                            try {
                                $ChildIdentity = Get-TheCleanersFileIdentity -LiteralPath $Item.FullName -Directory
                            } catch {
                                $BaseException = $_.Exception.GetBaseException()
                                throw [System.InvalidOperationException]::new("Could not capture the queued directory identity required for safe mutation: '$($Item.FullName)'.", $BaseException)
                            }
                        }
                        $Pending.Push([pscustomobject]@{
                                Path     = $Item.FullName
                                Identity = $ChildIdentity
                            })
                        continue
                    }
                    if ($Item.LastWriteTimeUtc -gt $CutoffUtc) {
                        continue
                    }

                    $CandidateIdentity = $null
                    if ($CaptureIdentity) {
                        try {
                            $CandidateIdentity = Get-TheCleanersFileIdentity -LiteralPath $Item.FullName
                        } catch {
                            $BaseException = $_.Exception.GetBaseException()
                            $CandidateMissing = (
                                $_.Exception -is [System.Management.Automation.ItemNotFoundException] -or
                                $BaseException -is [System.IO.FileNotFoundException] -or
                                $BaseException -is [System.IO.DirectoryNotFoundException] -or
                                ($BaseException -is [System.ComponentModel.Win32Exception] -and $BaseException.NativeErrorCode -in @(2, 3, 53, 123))
                            )
                            if ($CandidateMissing) {
                                Write-Verbose -Message "The candidate disappeared during identity capture and will be skipped: '$($Item.FullName)'"
                                continue
                            }
                            throw [System.InvalidOperationException]::new("Could not capture the candidate identity required for safe mutation: '$($Item.FullName)'.", $BaseException)
                        }
                    }

                    $ParentIdentity = $null
                    if ($RemoveEmptyDirectory -and $CaptureIdentity) {
                        try {
                            $ParentIdentity = Get-TheCleanersFileIdentity -LiteralPath $Item.Directory.FullName -Directory
                        } catch {
                            $BaseException = $_.Exception.GetBaseException()
                            throw [System.InvalidOperationException]::new("Could not capture the parent identity required for safe directory pruning: '$($Item.Directory.FullName)'.", $BaseException)
                        }
                    }

                    $Candidates.Add([pscustomobject]@{
                            Path             = $Item.FullName
                            Identity         = $CandidateIdentity
                            LastWriteTimeUtc = $Item.LastWriteTimeUtc
                            ParentPath       = $Item.Directory.FullName
                            ParentIdentity   = $ParentIdentity
                        })
                    $null = $FilePaths.Add($Item.FullName)

                    if ($RemoveEmptyDirectory) {
                        $Parent = $Item.Directory
                        while ($null -ne $Parent -and $Parent.FullName -ne $RootPath) {
                            $null = $DirectoryPaths.Add($Parent.FullName)
                            $Parent = $Parent.Parent
                        }
                    }
                }

                if ($CaptureIdentity) {
                    $CurrentDirectoryIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($HeldDirectoryEntry.Handle)
                    if (-not $DirectoryIdentity.Equals($CurrentDirectoryIdentity) -or $CurrentDirectoryIdentity.IsReparsePoint) {
                        throw [System.IO.InvalidDataException]::new("The temp traversal path changed while it was being enumerated: '$DirectoryPath'.")
                    }
                }
            } finally {
                if ($null -ne $DirectoryHandle) {
                    $DirectoryHandle.Dispose()
                }
            }
        }

        $PlannedDirectories = [System.Collections.Generic.List[object]]::new()
        $PlannedDirectoryPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $DirectoryOrder = @($DirectoryPaths | Sort-Object -Property @{ Expression = { $_.Length }; Descending = $true }, @{ Expression = { $_ }; Descending = $false })
        foreach ($DirectoryPath in $DirectoryOrder) {
            $null = Resolve-TheCleanersFileSystemPath -LiteralPath $DirectoryPath -RootPath $RootPath
            $Remaining = @(Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction Stop | Where-Object {
                    -not $FilePaths.Contains($_.FullName) -and -not $PlannedDirectoryPaths.Contains($_.FullName)
                })
            if ($Remaining.Count -ne 0) {
                continue
            }

            $DirectoryIdentity = $null
            if ($CaptureIdentity) {
                try {
                    $DirectoryIdentity = Get-TheCleanersFileIdentity -LiteralPath $DirectoryPath -Directory
                } catch {
                    $BaseException = $_.Exception.GetBaseException()
                    throw [System.InvalidOperationException]::new("Could not capture the directory identity required for safe pruning: '$DirectoryPath'.", $BaseException)
                }
            }
            $ParentPath = Split-Path -Path $DirectoryPath -Parent
            $ParentIdentity = $null
            if ($ParentPath -and $ParentPath -ne $RootPath -and $CaptureIdentity) {
                try {
                    $ParentIdentity = Get-TheCleanersFileIdentity -LiteralPath $ParentPath -Directory
                } catch {
                    $BaseException = $_.Exception.GetBaseException()
                    throw [System.InvalidOperationException]::new("Could not capture the ancestor identity required for safe pruning: '$ParentPath'.", $BaseException)
                }
            }

            $HeldDirectoryEntry = $null
            if ($CaptureIdentity) {
                if (-not $HeldDirectoryHandleByPath.ContainsKey($DirectoryPath)) {
                    throw [System.InvalidOperationException]::new("Could not retain the stable directory handle required for safe pruning: '$DirectoryPath'.")
                }
                $HeldDirectoryEntry = $HeldDirectoryHandleByPath[$DirectoryPath]
            }

            $PlannedDirectories.Add([pscustomobject]@{
                    Path           = $DirectoryPath
                    Identity       = $DirectoryIdentity
                    ParentPath     = $ParentPath
                    ParentIdentity = $ParentIdentity
                    Handle         = if ($null -eq $HeldDirectoryEntry) { $null } else { $HeldDirectoryEntry.Handle }
                })
            $null = $PlannedDirectoryPaths.Add($DirectoryPath)
        }

        if ($CaptureIdentity) {
            $RequiredDirectoryHandlePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $AddRequiredDirectoryPath = {
                param (
                    [Parameter(Mandatory)]
                    [string]
                    $Path
                )

                $CurrentPath = $Path
                while (-not [string]::IsNullOrWhiteSpace($CurrentPath)) {
                    $null = $RequiredDirectoryHandlePaths.Add($CurrentPath)
                    if ($CurrentPath -eq $RootPath) {
                        break
                    }
                    $ParentPath = Split-Path -Path $CurrentPath -Parent
                    if ([string]::IsNullOrWhiteSpace($ParentPath) -or $ParentPath -eq $CurrentPath) {
                        break
                    }
                    $CurrentPath = $ParentPath
                }
            }

            & $AddRequiredDirectoryPath -Path $RootPath
            foreach ($Candidate in $Candidates) {
                & $AddRequiredDirectoryPath -Path $Candidate.ParentPath
            }
            foreach ($DirectoryPlan in $PlannedDirectories) {
                & $AddRequiredDirectoryPath -Path $DirectoryPlan.Path
            }

            $RetainedDirectoryHandles = [System.Collections.Generic.List[object]]::new()
            foreach ($HeldDirectoryEntry in @($HeldDirectoryHandles.ToArray())) {
                if ($RequiredDirectoryHandlePaths.Contains($HeldDirectoryEntry.Path)) {
                    $RetainedDirectoryHandles.Add($HeldDirectoryEntry)
                } else {
                    $HeldDirectoryEntry.Handle.Dispose()
                }
            }
            $HeldDirectoryHandles = $RetainedDirectoryHandles
            $HeldDirectoryHandleByPath = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($HeldDirectoryEntry in $HeldDirectoryHandles) {
                $HeldDirectoryHandleByPath[$HeldDirectoryEntry.Path] = $HeldDirectoryEntry
            }
        }

        [pscustomobject]@{
            RootPath             = $RootPath
            RootIdentity         = $RootIdentity
            CutoffUtc            = $CutoffUtc.ToUniversalTime()
            Files                = @($Candidates.ToArray() | Sort-Object -Property Path)
            Directories          = @($PlannedDirectories.ToArray())
            HeldDirectoryHandles = @($HeldDirectoryHandles.ToArray())
        }
    } catch {
        foreach ($HeldDirectoryEntry in @($HeldDirectoryHandles.ToArray())) {
            if ($null -ne $HeldDirectoryEntry.Handle) {
                $HeldDirectoryEntry.Handle.Dispose()
            }
        }
        throw
    }
}

function Close-TheCleanersTempPlanHandles {
    <#
    .SYNOPSIS
        Release stable directory handles retained by a mutation plan.
    .DESCRIPTION
        Mutation-enabled discovery holds ancestor directory handles through the
        owning command's ShouldProcess decision and candidate operations. This
        helper releases those handles on every command exit path. WhatIf plans
        contain no native handles.
    .PARAMETER Plan
        Temporary cleanup plan returned by Get-TheCleanersTempPlan.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]
        $Plan
    )

    foreach ($HeldDirectoryEntry in @($Plan.HeldDirectoryHandles)) {
        if ($null -ne $HeldDirectoryEntry -and $null -ne $HeldDirectoryEntry.Handle) {
            $HeldDirectoryEntry.Handle.Dispose()
        }
    }
    if ($Plan.PSObject.Properties.Match('HeldDirectoryHandles').Count -gt 0) {
        $Plan.HeldDirectoryHandles = @()
    }
}
