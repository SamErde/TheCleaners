<#
.SYNOPSIS
    Clean out old Exchange Server logs.

.DESCRIPTION
    Remove any Exchange logs that are older than a specified date.

.PARAMETER Days
    The number of days to keep logs for. Any logs older than this will be removed.

.EXAMPLE
    Remove-ExchangeLogs -Days 60

    This will remove all Exchange logs older than 60 days.

.NOTES
    Author: Sam Erde
            https://twitter.com/SamErde
            https://github.com/SamErde
#>
function Clear-OldExchangeLogs {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Clear-OldExchangeLogs')]
    # Logs older than this number of days will be removed.
    param (
        [Parameter()]
        [int]
        $Days = 60
    )

    begin {

        try {
            $ExchangeInstallPath = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup).MsiInstallPath
        } catch {
            Write-Warning -WarningAction Continue "The Exchange Server installation path could not be found. Please ensure that Exchange Server is installed on this machine."
            return
        }

        # Define the paths to the Exchange log files
        $LogLocations = @{
            ExchangeLoggingPath     = Join-Path -Path $ExchangeInstallPath -ChildPath 'Logging\' -ErrorAction Ignore
            ETLTracesPath           = Join-Path -Path $ExchangeInstallPath -ChildPath 'Bin\Search\Ceres\Diagnostics\ETLTraces\' -ErrorAction Ignore
            DiagnosticLogsPath      = Join-Path -Path $ExchangeInstallPath -ChildPath '\Bin\Search\Ceres\Diagnostics\Logs' -ErrorAction Ignore
            MessageTrackingLogsPath = Join-Path -Path $ExchangeInstallPath -ChildPath '\TransportRoles\Logs\MessageTracking\' -ErrorAction Ignore
        }

        $LastWriteDate = (Get-Date).AddDays(-$Days)
    } # end begin

    process {
        # Clean up the IIS log files
        Clear-OldIisLogFiles -Days $Days

        foreach ($LogLocation in $LogLocations.GetEnumerator()) {
            if (-not (Test-Path -Path $LogLocation.Value)) {
                Write-Warning -WarningAction Continue "The folder $($LogLocation.Key) doesn't exist. Skipping this folder."
                continue
            }

            $OldFiles = Get-ChildItem -Path $($LogLocation.Value) -Recurse |
                Where-Object { ($_.Name -like "*.log") -and ($_.lastWriteTime -le "$LastWriteDate") } |
                Select-Object FullName

            foreach ($file in $OldFiles) {
                if ( $PSCmdlet.ShouldProcess($file.Name) ) {
                    $file.Delete()
                }
            } # end foreach $file

        } # end foreach LogLocation
    } # end process

    end {
        # Summarize the count and total size of files removed.
    }
}
