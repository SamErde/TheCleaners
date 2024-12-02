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
    $OldFiles = Get-ChildItem -Path $UserTempPath -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.LastWriteTime -le ( (Get-Date).AddDays(-$Days) )
    }

    if ($OldFiles.Count -eq 0) {
        Write-Output "No files found older than $Days days in `'$UserTempPath`'."
        return
    }

    Write-Output "Found $($OldFiles.Count) files and directories older than $Days days in $UserTempPath.`n"

    foreach ($file in $OldFiles) {
        if ( $PSCmdlet.ShouldProcess("Removing $($file.FullName)", $file.FullName, 'Remove-Item') ) {
            try {
                Remove-Item $file -Confirm:$false -ErrorAction Stop
                Write-Verbose -Message "Removed file: $($file.FullName)"
            } catch {
                Write-Output "  $($Error[-1].Exception.Message)"
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
    $ErrorActionPreference = 'SilentlyContinue'
    do {
        # Break from the do-until loop if the TimeLimit has been reached.
        if ((Get-Date) - $CleanEmptyDirectoriesStartTime -ge $TimeLimit ) {
            Write-Output "The CleanEmptyDirectories operation timed out after $TimeOut seconds. There are $($EmptyDirectories.Count) empty directories left."
            break
        }
        # Get directories that have 0 files in them.
        $EmptyDirectories = Get-ChildItem -Path $UserTempPath -Directory -Recurse | Where-Object { $_.GetFileSystemInfos().Count -eq 0 } | Out-Null
        Write-Verbose "$($EmptyDirectories.Count) empty directories found."
        $EmptyDirectories | Remove-Item
    } until (
        $EmptyDirectories.Count -eq 0
    )
    $ErrorActionPreference = $RunningErrorActionPreference
    #endregion CleanEmptyDirectories
}
