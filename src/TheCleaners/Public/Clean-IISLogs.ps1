function Remove-OldIISLogFiles {
    <#
        .SYNOPSIS
            A script to clean out old IIS log files.

        .DESCRIPTION
            This is a work in progress still. It will attempt to find IIS log folders and clean out files older than [x] days.
            It checks the default log folder locations first, and if the WebAdministration PowerShell module is available, it
            will use that to check the specific log file locations for each web site as well.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [int]
        $Days = 60
    )

    # Check default log file location without depending on the WebAdministration module
    $DefaultIISLogLocation = "$env:SystemDrive\inetpub\logs\LogFiles"
    if (Test-Path -Path $DefaultIISLogLocation) {
        Remove-OldFiles -Path $DefaultIISLogLocation -Days $Days
    }

    # Check registry for log file lcoation without depending on the WebAdministration module
    $LogDir = Get-ItemProperty -Path "HKLM:\\System\\CurrentControlSet\\Services\\InetInfo\\Parameters" -Name "LogDir" | Select-Object -ExpandProperty LogDir
    if (Test-Path -Path $LogDir) {
        Remove-OldFiles -Path $DefaultIISLogLocation -Days $Days
    }

    # Use the WebAdministration module if it is available
    if (Get-Module -Name 'WebAdministration' -ListAvailable) {

        # The the log file folder setting for each managed web site
        $WebSites = Get-WebSite
        foreach ($item in $WebSites) {
            $SiteLogFileFolder = [string]"($($WebSite.logFile.directory)\w3svc$($WebSite.id)).replace('%SystemDrive%','$env:SystemDrive')"
            Remove-OldFiles -Path $SiteLogFileFolder -Days $Days
        }

        # Alternative approach to test getting each managed web site
        $WebSites = Get-ChildItem IIS:\Sites
        foreach ($item in $WebSites) {
            $SiteLogFileFolder = $($item.logfile.directory) + "\w3svc" + $($item.id)
            Remove-OldFiles -Path $SiteLogFileFolder -Days $Days
        }
    } else {
        Write-Information "The WebAdministration module is not installed. Installing it may allow you to target site-specific log file paths." -InformationAction Continue
    }
}
