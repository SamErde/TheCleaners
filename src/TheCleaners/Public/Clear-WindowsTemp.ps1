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

    $IsWindowsHost = $PSVersionTable.PSEdition -eq 'Desktop' -or ($PSVersionTable.PSVersion.Major -ge 6 -and $IsWindows)
    if (-not $IsWindowsHost) {
        Write-Error -Message 'Clear-WindowsTemp requires Windows because it cleans the system temp folder under SystemRoot.'
        return
    }

    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        Write-Error -Message 'Clear-WindowsTemp requires the SystemRoot environment variable to locate the system temp folder.'
        return
    }

    $TempPath = Join-Path -Path $env:SystemRoot -ChildPath 'Temp'
    if (-not (Test-Path -Path $TempPath)) {
        Write-Warning -Message "Unable to find $TempPath."
        return
    }
    try {
        $CutoffDate = (Get-Date).AddDays(-$Days)
        $OldFiles = @(Get-ChildItem -LiteralPath $TempPath -File -Recurse -Force -ErrorAction Stop | Where-Object {
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

    Write-Information -MessageData "Found $($OldFiles.Count) files older than $Days days in the system temp folder." -InformationAction Continue

    foreach ($File in $OldFiles) {
        if ($PSCmdlet.ShouldProcess($File.FullName, 'Remove temp item')) {
            try {
                Remove-Item -LiteralPath $File.FullName -Confirm:$false -ErrorAction Stop
                Write-Verbose -Message "Removed temp file: $($File.FullName)"
            } catch {
                Write-Warning -Message "Failed to remove '$($File.FullName)': $($_.Exception.Message)"
            }
        }
    }

}
