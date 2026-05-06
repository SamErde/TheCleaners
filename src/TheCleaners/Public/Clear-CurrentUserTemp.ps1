function Clear-CurrentUserTemp {
    <#
    .SYNOPSIS
        Clean old temp files from user profiles.

    .DESCRIPTION
        Remove temp files older than a given number of days from the user's local temp folder.

    .PARAMETER Days
        Remove temp files that are $Days days old or older. The default is 30.

    .PARAMETER TimeOut
        A time limit (seconds) for the looping operation that removes empty directories. The default is 30.

    .EXAMPLE
        Clear-CurrentUserTemp -Days 30

    .EXAMPLE
        Clean-CurrentUserTemp -Days 21 -TimeOut 30
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('Clean-CurrentUserTemp')]
    param (
        # Remove temp files that are $Days days old or older.
        [Parameter()]
        [ValidateRange(1, [int16]::MaxValue)] # Ensure it is a positive number.
        [int16]
        $Days = 30,

        # Time limit (seconds) for running the CleanEmptyDirectories loop. The default is 30 (seconds).
        [Parameter()]
        [ValidateRange(1, [int16]::MaxValue)] # Ensure it is a positive number.
        [Int16]
        $TimeOut = 30
    )

    if ($IsLinux) {
        $UserTempPath = '/tmp'
    } else {
        $UserTempPath = $env:TEMP
    }

    if (-not (Test-Path -Path $UserTempPath)) {
        Write-Warning -Message "Unable to find $UserTempPath."
        return
    }

    Write-Verbose "Getting files older than $($Days) days (inclusive) in `'$UserTempPath`'."
    try {
        $CutoffDate = (Get-Date).AddDays(-$Days)
        $OldFiles = @(Get-ChildItem -LiteralPath $UserTempPath -File -Recurse -Force -ErrorAction Stop | Where-Object {
                $_.LastWriteTime -le $CutoffDate
            })
    } catch {
        Write-Warning -Message "Failed to enumerate '$UserTempPath': $($_.Exception.Message)"
        return
    }

    if ($OldFiles.Count -eq 0) {
        Write-Information -MessageData "No files found older than $Days days in `'$UserTempPath`'." -InformationAction Continue
        return
    }

    Write-Information -MessageData "Found $($OldFiles.Count) files older than $Days days in $UserTempPath." -InformationAction Continue

    foreach ($File in $OldFiles) {
        if ($PSCmdlet.ShouldProcess($File.FullName, 'Remove temp file')) {
            try {
                Remove-Item -LiteralPath $File.FullName -Confirm:$false -ErrorAction Stop
                Write-Verbose -Message "Removed file: $($File.FullName)"
            } catch {
                Write-Warning -Message "Failed to remove file '$($File.FullName)': $($_.Exception.Message)"
            }
        }
    }

    #region CleanEmptyDirectories
    <#
        Find empty directories and then loop through them to remove sub-directories and then empty parent directories.
    #>
    # Set a timeout in case the do-until loop encounters a condition that prevents it from reaching zero (0).
    $CleanEmptyDirectoriesStartTime = Get-Date
    $TimeLimit = [timespan]::FromSeconds($TimeOut)
    # Save the current ErrorActionPreference so we can restore it after using SilentlyContinue.
    $RunningErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'
        do {
            # Break from the do-until loop if the TimeLimit has been reached.
            if ((Get-Date) - $CleanEmptyDirectoriesStartTime -ge $TimeLimit ) {
                Write-Warning -Message "The CleanEmptyDirectories operation timed out after $TimeOut seconds. There are $($EmptyDirectories.Count) empty directories left."
                break
            }
            # Get directories that have 0 files in them.
            $EmptyDirectories = @(Get-ChildItem -LiteralPath $UserTempPath -Directory -Recurse -Force | Where-Object { $_.GetFileSystemInfos().Count -eq 0 })
            Write-Verbose "$($EmptyDirectories.Count) empty directories found."
            $RemovedDirectory = $false
            foreach ($Directory in $EmptyDirectories) {
                if ($PSCmdlet.ShouldProcess($Directory.FullName, 'Remove empty temp directory')) {
                    try {
                        Remove-Item -LiteralPath $Directory.FullName -Confirm:$false -ErrorAction Stop
                        $RemovedDirectory = $true
                    } catch {
                        Write-Warning -Message "Failed to remove directory '$($Directory.FullName)': $($_.Exception.Message)"
                    }
                }
            }

            if ($EmptyDirectories.Count -gt 0 -and -not $RemovedDirectory) {
                break
            }
        } until (
            $EmptyDirectories.Count -eq 0
        )
    } finally {
        $ErrorActionPreference = $RunningErrorActionPreference
    }
    #endregion CleanEmptyDirectories
}
