###################################################################################
#                                                                                 #
# WARNING: This script is still being developed and tested. Use at your own risk. #
#                                                                                 #
###################################################################################
function Clear-OldExchangeLog {
    <#
    .SYNOPSIS
        Clean out old Exchange Server logs.

    .DESCRIPTION
        Remove any Exchange logs that are older than a specified date.

    .PARAMETER Days
        The number of days to keep logs for. Any logs older than this will be removed.

    .EXAMPLE
        Clear-OldExchangeLog -Days 60

        This will remove all Exchange logs older than 60 days.

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [Alias('Clean-ExchangeLog')]
    #[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns')]
    # Logs older than this number of days will be removed.
    param (
        [Parameter()]
        [ValidateRange(1, [int16]::MaxValue)]
        [int16]
        $Days = 60
    )

    begin {

        try {
            $ExchangeInstallPath = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup).MsiInstallPath
        } catch {
            Write-Warning -WarningAction Continue 'The Exchange Server installation path could not be found. Please ensure that Exchange Server is installed on this machine.'
            return
        }

        # Define the paths to the Exchange log files
        $LogLocations = @{
            ExchangeLoggingPath     = Join-Path -Path $ExchangeInstallPath -ChildPath 'Logging\'
            ETLTracesPath           = Join-Path -Path $ExchangeInstallPath -ChildPath 'Bin\Search\Ceres\Diagnostics\ETLTraces\'
            DiagnosticLogsPath      = Join-Path -Path $ExchangeInstallPath -ChildPath 'Bin\Search\Ceres\Diagnostics\Logs'
            MessageTrackingLogsPath = Join-Path -Path $ExchangeInstallPath -ChildPath 'TransportRoles\Logs\MessageTracking\'
        }

        $LastWriteDate = (Get-Date).AddDays(-$Days)
    } # end begin

    process {
        # Clean up the IIS log files
        Clear-OldIISLog -Days $Days -WhatIf:$WhatIfPreference

        foreach ($LogLocation in $LogLocations.GetEnumerator()) {
            if (-not (Test-Path -Path $LogLocation.Value)) {
                Write-Warning -WarningAction Continue "The folder $($LogLocation.Key) doesn't exist. Skipping this folder."
                continue
            }

            try {
                $OldFiles = @(Get-ChildItem -LiteralPath $LogLocation.Value -File -Recurse -Force -ErrorAction Stop |
                        Where-Object { ($_.Name -like '*.log') -and ($_.LastWriteTime -le $LastWriteDate) })
            } catch {
                Write-Warning -WarningAction Continue "Failed to enumerate $($LogLocation.Key): $($_.Exception.Message)"
                continue
            }

            foreach ($File in $OldFiles) {
                if ($PSCmdlet.ShouldProcess($File.FullName, 'Remove old Exchange log file')) {
                    try {
                        # Confirmation is handled by the outer ShouldProcess check, so suppress
                        # nested Remove-Item confirmation to avoid duplicate prompts.
                        Remove-Item -LiteralPath $File.FullName -Confirm:$false -ErrorAction Stop
                    } catch {
                        Write-Warning -WarningAction Continue "Failed to remove Exchange log '$($File.FullName)': $($_.Exception.Message)"
                    }
                }
            } # end foreach $file

        } # end foreach LogLocation
    } # end process

    end {
        # Summarize the count and total size of files removed.
    }
}
