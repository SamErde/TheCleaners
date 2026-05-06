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

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [Alias('Clean-WindowsTemp')]
    param (
        # How many days worth of temp files to retain (how far back to filter).
        [Parameter()]
        [ValidateRange(1, [int16]::MaxValue)] # Ensure it is a positive number.
        [int16]
        $Days = 30
    )

    $TempPath = Join-Path -Path $env:SystemRoot -ChildPath 'Temp'
    if (-not (Test-Path -Path $TempPath)) {
        Write-Warning -Message "Unable to find $TempPath."
        return
    }
    try {
        $CutoffDate = (Get-Date).AddDays(-$Days)
        $OldFiles = @(Get-ChildItem -LiteralPath $TempPath -Recurse -Force -ErrorAction Stop | Where-Object {
                $_.LastWriteTime -le $CutoffDate
            })
    } catch {
        Write-Warning -Message "Failed to enumerate '$TempPath': $($_.Exception.Message)"
        return
    }

    if ($OldFiles.Count -eq 0) {
        Write-Information -MessageData "No files found older than $Days days." -InformationAction Continue
        return
    }

    Write-Information -MessageData "Found $($OldFiles.Count) files and directories older than $Days days in the system temp folder." -InformationAction Continue

    foreach ($File in $OldFiles) {
        if ($PSCmdlet.ShouldProcess($File.FullName, 'Remove temp item')) {
            try {
                Remove-Item -LiteralPath $File.FullName -Recurse -Confirm:$false -ErrorAction Stop
                Write-Verbose -Message "Removed temp item: $($File.FullName)"
            } catch {
                Write-Warning -Message "Failed to remove '$($File.FullName)': $($_.Exception.Message)"
            }
        }
    }

}
