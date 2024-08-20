function Clear-WindowsTemp {
    <#
    .SYNOPSIS
        A script to clean out old Windows Temp files.

    .DESCRIPTION
        This script will clean out Windows Temp files older than x days.

    .PARAMETER Days
        The number of days to keep temp files. The default is 30 days.

    .EXAMPLE
        Clear-WindowsTemp -Days 60

        Removes all Windows Temp files that are older than 60 days.

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [Alias('Clean-WindowsTemp')]
    param (
        # How many days worth of temp files to retain (how far back to filter).
        [ValidateRange(1, [int16]::MaxValue)] # Ensure it is a positive number.
        [int16]
        $Days = 30
    )

    $TempPath = Join-Path -Path $env:SystemRoot -ChildPath 'Temp'
    if (-not (Test-Path -Path $TempPath)) {
        Write-Warning -Message "Unable to find $TempPath."
        return
    }
    $OldFiles = Get-ChildItem -Path $TempPath -Recurse | Where-Object {
        $_.LastWriteTime -le ( (Get-Date).AddDays(-$Days) )
    }

    if ($OldFiles.Count -eq 0) {
        Write-Output "No files found older than $Days days."
        return
    }

    Write-Output "Found $($OldFiles.Count) files and directories older than $Days days in the system temp folder.`n"

    foreach ($file in $OldFiles) {
        if ( $PSCmdlet.ShouldProcess($file.FullName, 'Remove file') ) {
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                Write-Verbose -Message "Removed file: $($file.FullName)"
            } catch {
                Write-Output "  $($Error[-1].Exception.Message)"
            }
        }
    }
}
