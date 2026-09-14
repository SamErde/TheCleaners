function Get-TheCleanersTempPlan {
    <#
    .SYNOPSIS
        Discover old temporary files and identity-bound directory candidates.
    .DESCRIPTION
        This function only reads the approved root. It records native file IDs for
        candidates and touched directories so the owning public command can compare
        the object opened for mutation with the object found during discovery.
        Discovery errors are terminating to prevent partial plans from being used.
    .PARAMETER Root
        Previously validated temporary directory.
    .PARAMETER CutoffUtc
        Inclusive UTC retention cutoff.
    .PARAMETER RemoveEmptyDirectory
        Include directories that can become empty after file removal.
    .PARAMETER CaptureIdentity
        Capture native file and directory identities for a removal-enabled plan.
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
    $Pending = [System.Collections.Generic.Stack[string]]::new()
    $Pending.Push($RootPath)

    while ($Pending.Count -gt 0) {
        $Directory = Resolve-TheCleanersFileSystemPath -LiteralPath $Pending.Pop()
        foreach ($Item in @(Get-ChildItem -LiteralPath $Directory.FullName -Force -ErrorAction Stop)) {
            if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Write-Verbose -Message "Skipping reparse point: $($Item.FullName)"
                continue
            }
            if ($Item.PSIsContainer) {
                $Pending.Push($Item.FullName)
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
                    # The candidate remains visible in the plan. The mutation phase will
                    # report an access or sharing failure, or skip it when identity cannot
                    # be compared safely. A failed inspection must never authorize deletion.
                    Write-Verbose -Message "Could not capture candidate identity for '$($Item.FullName)': $($_.Exception.Message)"
                }
            }

            $ParentIdentity = $null
            if ($RemoveEmptyDirectory -and $CaptureIdentity) {
                try {
                    $ParentIdentity = Get-TheCleanersFileIdentity -LiteralPath $Item.Directory.FullName -Directory
                } catch {
                    Write-Verbose -Message "Could not capture parent identity for '$($Item.FullName)': $($_.Exception.Message)"
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
                Write-Verbose -Message "Could not capture directory identity for '$DirectoryPath': $($_.Exception.Message)"
            }
        }
        $ParentPath = Split-Path -Path $DirectoryPath -Parent
        $ParentIdentity = $null
        if ($ParentPath -and $ParentPath -ne $RootPath -and $CaptureIdentity) {
            try {
                $ParentIdentity = Get-TheCleanersFileIdentity -LiteralPath $ParentPath -Directory
            } catch {
                Write-Verbose -Message "Could not capture ancestor identity for '$DirectoryPath': $($_.Exception.Message)"
            }
        }

        $PlannedDirectories.Add([pscustomobject]@{
                Path           = $DirectoryPath
                Identity       = $DirectoryIdentity
                ParentPath     = $ParentPath
                ParentIdentity = $ParentIdentity
            })
        $null = $PlannedDirectoryPaths.Add($DirectoryPath)
    }

    [pscustomobject]@{
        RootPath     = $RootPath
        RootIdentity = $RootIdentity
        CutoffUtc    = $CutoffUtc.ToUniversalTime()
        Files        = @($Candidates.ToArray() | Sort-Object -Property Path)
        Directories  = @($PlannedDirectories.ToArray())
    }
}
