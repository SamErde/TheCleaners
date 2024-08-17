function Clear-OldIISLogs {
    <#
    .SYNOPSIS
        A script to clean out old IIS log files.

    .DESCRIPTION
        This script will clean out IIS log files older than x days.

    .PARAMETER Days
        The number of days to keep log files. The default is 60 days.

    .EXAMPLE
        Clear-OldIISLogFiles -Days 60

        Removes all IIS log files that are older than 60 days.

    .NOTES
        Author:     Sam Erde
                    https://twitter.com/SamErde
                    https://github.com/SamErde
        Modified:   2024-02-17

        If the WebAdministration module is available, it will use that to check the specific log file locations for
        each web site. Otherwise, it checks the assumed default log folder location and the registry for the IIS
        log file location.

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns')]
    param (
        [Parameter()]
        [int]
        $Days = 60
    )

    # Use the WebAdministration module if it is available
    if (Get-Module -Name 'WebAdministration' -ListAvailable) {
        # Get the logfile directory for each web site
        $WebSites = Get-Website
        foreach ($site in $WebSites) {
            $SiteLogFileDirectory = ("$($Site.logFile.directory)\W3SVC$($Site.id)").Replace( '%SystemDrive%',$env:SystemDrive )
            Write-Information -MessageData "Removing old IIS log files from $($Site.name) at $SiteLogFileDirectory." -InformationAction Continue
            try {
                Remove-OldFiles -Path $SiteLogFileDirectory -Days $Days
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorAction Continue
                Write-Warning "Failed to remove old IIS log files from $($Site.name) at $SiteLogFileDirectory." -WarningAction Continue
            }
        }
    } else {
        # If the WebAdministration module is not available, check the default log file location
        $DefaultIISLogLocation = "$env:SystemDrive\inetpub\logs\LogFiles"
        Write-Information "The WebAdministration module is not installed. We will check the default IIS log file location at '$DefaultIISLogLocation'." -InformationAction Continue
        if (Test-Path -Path $DefaultIISLogLocation -ErrorAction SilentlyContinue) {
            try {
                Remove-OldFiles -Path $DefaultIISLogLocation -Days $Days
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorAction Continue
                Write-Warning "Failed to remove old log files from the default IIS log file location at '$DefaultIISLogLocation'." -WarningAction Continue
            }
        } else {
            Write-Information -MessageData "The default IIS log file location at '$DefaultIISLogLocation' does not exist." -InformationAction Continue
        }

        # If the WebAdministration module is not available,try to check the IIS log file location from the registry (requires local admin rights to read this path)
        $LogDir = Get-ItemProperty -Path 'HKLM:\\System\CurrentControlSet\Services\W3SVC\Parameters' -Name "LogDir" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LogDir
        if ($LogDir -and (Test-Path -Path $LogDir)) {
            try {
                Remove-OldFiles -Path $LogDir -Days $Days
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorAction Continue
                Write-Warning "Failed to remove old IIS log files from the location specified in the directory ($LogDir)." -WarningAction Continue
            }
        } else {
            Write-Information -MessageData "Unable to find an alternate IIS log file location from the registry." -InformationAction Continue
        }
    }
    <#
        To Do: Add a summary of which blocks were run and possibly a count of log files removed.
    #>
}
