function Clear-WindowsTemp {
    <#
    .SYNOPSIS
        Remove old files from the Windows temporary directory.
    .DESCRIPTION
        Clean SystemRoot\Temp using one inclusive UTC LastWriteTime cutoff. Directory
        removal is opt-in and limited to directories emptied by this invocation and
        their now-empty ancestors. Preserve the cleanup root, unrelated empty branches,
        and reparse points. A single ShouldProcess decision authorizes the discovered
        file/directory plan. Revalidate paths and timestamps before removal. Run elevated
        for system-owned files; permission failures are reported through the error stream.
        This prerelease still requires the Windows acceptance and privilege-preflight work
        in the 1.0 plan. Path checks are not an atomic defense against hostile changes.
    .PARAMETER Days
        Retain files newer than Days days ago. The default is 30 days.
    .PARAMETER RemoveEmptyDirectory
        Also remove directories emptied by this invocation, deepest-first. Never remove
        pre-existing empty branches or the Windows temporary directory itself.
    .PARAMETER PassThru
        Return a TheCleaners.CleanupResult summary, including preview and failure counts.
    .EXAMPLE
        Clear-WindowsTemp -Days 60 -WhatIf -PassThru
    .EXAMPLE
        Clear-WindowsTemp -Days 30 -RemoveEmptyDirectory -Confirm
    .OUTPUTS
        TheCleaners.CleanupResult
    .LINK
        https://day3bits.com/thecleaners/Clear-WindowsTemp/
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [Alias('Clean-WindowsTemp')]
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
        throw [System.PlatformNotSupportedException]::new('Clear-WindowsTemp requires Windows.')
    }
    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        Write-Error -Message 'Clear-WindowsTemp requires the SystemRoot environment variable to locate the system temp folder.'
        return
    }
    $Root = Resolve-TheCleanersFileSystemPath -LiteralPath (Join-Path -Path $env:SystemRoot -ChildPath 'Temp')
    $RootPath = $Root.FullName.TrimEnd([char[]]@('\', '/'))
    $CutoffUtc = (Get-Date).ToUniversalTime().AddDays(-$Days)
    $Result = [pscustomobject]@{
        PSTypeName              = 'TheCleaners.CleanupResult'
        Command                 = 'Clear-WindowsTemp'
        RootPath                = $RootPath
        CutoffUtc               = $CutoffUtc
        FileCandidateCount      = 0
        FilesRemoved            = 0
        FileFailureCount        = 0
        FilesSkipped            = 0
        DirectoryCandidateCount = 0
        DirectoriesRemoved      = 0
        DirectoryFailureCount   = 0
        DirectoriesSkipped      = 0
        BytesReclaimed          = [Int64]0
        Status                  = 'NoCandidates'
    }
    $Candidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $FilePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $DirectoryPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $PlannedDirectories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    try {
        # Walk one level at a time so reparse points are excluded before traversal, not afterward.
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
                } elseif ($Item.LastWriteTimeUtc -le $CutoffUtc) {
                    $Candidates.Add($Item)
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
        }
        $DirectoryOrder = @($DirectoryPaths | Sort-Object -Property @{ Expression = { $_.Length }; Descending = $true }, @{ Expression = { $_ }; Descending = $false })
        foreach ($DirectoryPath in $DirectoryOrder) {
            $null = Resolve-TheCleanersFileSystemPath -LiteralPath $DirectoryPath -RootPath $RootPath
            $Remaining = @(Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction Stop | Where-Object {
                    -not $FilePaths.Contains($_.FullName) -and -not $PlannedDirectories.Contains($_.FullName)
                })
            if ($Remaining.Count -eq 0) {
                $null = $PlannedDirectories.Add($DirectoryPath)
            }
        }
    } catch {
        $Result.Status = 'DiscoveryFailed'
        $Result.FileCandidateCount = $null
        $Result.DirectoryCandidateCount = $null
        $PSCmdlet.WriteError($_)
        if ($PassThru) {
            $Result
        }
        return
    }
    $OldFiles = @($Candidates.ToArray() | Sort-Object -Property FullName)
    $Result.FileCandidateCount = $OldFiles.Count
    $Result.DirectoryCandidateCount = $PlannedDirectories.Count
    foreach ($File in $OldFiles) {
        Write-Verbose -Message "Candidate file: $($File.FullName)"
    }
    foreach ($DirectoryPath in $DirectoryOrder) {
        if ($PlannedDirectories.Contains($DirectoryPath)) {
            Write-Verbose -Message "Candidate directory after file cleanup: $DirectoryPath"
        }
    }
    if ($OldFiles.Count -eq 0) {
        if ($PassThru) {
            $Result
        }
        return
    }
    $Action = 'Remove {0} old temp files and up to {1} directories emptied by this cleanup; inclusive UTC cutoff {2:u}' -f $OldFiles.Count, $PlannedDirectories.Count, $CutoffUtc
    if (-not $PSCmdlet.ShouldProcess($RootPath, $Action)) {
        $Result.Status = if ($WhatIfPreference) { 'WhatIf' } else { 'Declined' }
        if ($PassThru) {
            $Result
        }
        return
    }

    $TouchedDirectories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($File in $OldFiles) {
        try {
            $CurrentFile = Resolve-TheCleanersFileSystemPath -LiteralPath $File.FullName -RootPath $RootPath
            if ($CurrentFile -isnot [System.IO.FileInfo] -or $CurrentFile.LastWriteTimeUtc -gt $CutoffUtc) {
                $Result.FilesSkipped++
                continue
            }
            $Length = $CurrentFile.Length
            Remove-Item -LiteralPath $CurrentFile.FullName -Force -Confirm:$false -ErrorAction Stop
            $Result.FilesRemoved++
            $Result.BytesReclaimed += $Length
            $Parent = $CurrentFile.Directory
            while ($null -ne $Parent -and $Parent.FullName -ne $RootPath) {
                $null = $TouchedDirectories.Add($Parent.FullName)
                $Parent = $Parent.Parent
            }
        } catch {
            $Result.FileFailureCount++
            $PSCmdlet.WriteError($_)
        }
    }
    foreach ($DirectoryPath in $DirectoryOrder) {
        if (-not $PlannedDirectories.Contains($DirectoryPath)) {
            continue
        }
        if (-not $TouchedDirectories.Contains($DirectoryPath)) {
            $Result.DirectoriesSkipped++
            continue
        }
        try {
            $CurrentDirectory = Resolve-TheCleanersFileSystemPath -LiteralPath $DirectoryPath -RootPath $RootPath
            if ($CurrentDirectory -isnot [System.IO.DirectoryInfo] -or @(Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction Stop).Count -gt 0) {
                $Result.DirectoriesSkipped++
                continue
            }
            # Non-recursive deletion fails if a file appears after the emptiness check; no nested prompt can escalate it.
            [System.IO.Directory]::Delete($CurrentDirectory.FullName, $false)
            $Result.DirectoriesRemoved++
        } catch {
            $Result.DirectoryFailureCount++
            $PSCmdlet.WriteError($_)
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

