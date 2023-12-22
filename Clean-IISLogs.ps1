<#
    .SYNOPSIS
    A script to clean out old IIS log files.

    .DESCRIPTION
    This is a work in progress still. It will attempt to find IIS log folders and clean out files older than [x] days. 
    It checks the default log folder locations first, and if the WebAdministration PowerShell module is available, it 
    will use that to check the specific log file locations for each web site as well.
#>

# Check default log file location without requiring the WebAdministration module
$DefaultIISLogLocation = "$env:SystemDrive\inetpub\logs\LogFiles"
if (Test-Path -Path $DefaultIISLogLocation) {
    Remove-OldFiles -Path $DefaultIISLogLocation -Days 60
}

# Check registry for log file lcoation without requiring the WebAdministration module
$LogDir = Get-ItemProperty -Path "HKLM:\\System\\CurrentControlSet\\Services\\InetInfo\\Parameters" -Name "LogDir" | Select-Object -ExpandProperty LogDir
if (Test-Path -Path $LogDir) {
    Remove-OldFiles -Path $DefaultIISLogLocation -Days 60
} else {
    # Add some info and verbose messaging
}

# If the WebAdministration module is installed:
$WebSites = Get-WebSite
foreach ($item in $WebSites) {
    $LogFileFolder = [string]($($WebSite.logFile.directory)\w3svc$($WebSite.id)).replace("%SystemDrive%",$env:SystemDrive)

    # Create verbose and info output for this step
    Remove-OldFiles -Path $LogFileFolder -Days 60
}

# Alternative approach to test
$WebSites = Get-ChildItem IIS:\Sites
foreach ($item in $WebSites) {
    $LogFileFolder = $($item.logfile.directory) + "\w3svc" + $($item.id)

    # Create verbose and info output for this step
    Remove-OldFiles -Path $LogFileFolder -Days 60
}


function Remove-OldFiles {
    [CmdletBinding()]
    param (
        [parameter]
        $Path,

        [parameter]
        [int]$Days = 60
    )
    
    begin {
        
    }
    
    process {
        Get-ChildItem -Path $Path | Where-Object {$_.CreationTime -le ([datetime]::Now.AddDays( -$Days ))} | Remove-Item
    }
    
    end {
        
    }
}
