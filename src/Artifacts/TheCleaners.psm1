# This is a locally sourced Imports file for local development.
# It can be imported by the psm1 in local development to add script level variables.
# It will merged in the build process. This is for local development only.

# region script variables
# $script:resourcePath = "$PSScriptRoot\Resources"


<#PSScriptInfo
.DESCRIPTION The Cleaners do the dirty work in your servers for you. We take care of temp files, IIS logs, Exchange Server logs, and more!
.VERSION 0.0.15
.GUID bec6a004-45da-4062-ab78-b8eae99f29be
.AUTHOR Sam Erde
.COPYRIGHT (c) 2025 Sam Erde. All rights reserved.
.TAGS PowerShell Windows Utility
.LICENSEURI https://github.com/SamErde/TheCleaners/blob/main/LICENSE
.PROJECTURI https://github.com/SamErde/TheCleaners/
#>

function Invoke-TheCleaners {
    <#
    .SYNOPSIS
    Show a welcome message when the module is imported explicitly by the user.

    .DESCRIPTION
    This function shows a welcome message to help the user get started when they explicitly import the module. If the
    module is automatically imported by invoking one of its exported functions, we assume the user already knows the
    command that they want to run and do not show the welcome message.

    .PARAMETER InvokingCommand
    A parameter to receive the command line that called this function. This is used to determine if the module was
    imported explicitly by the user or automatically by invoking one of its exported functions. This information must
    come from outside the function in order to be able to determine what command invoked the script itself.

    .EXAMPLE
    Invoke-TheCleaners -InvokingCommand "$( ((Get-PSCallStack)[1]).InvocationInfo.MyCommand )"

    .NOTES
    Author: Sam Erde
    Company: Sentinel Technologies, Inc
    Date: 2025-03-11
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param (
        # The command that called this function.
        [Parameter(Mandatory)]
        [string]
        $InvokingCommand
    )

    if ($InvokingCommand -match 'ipmo|Import-Module') {
        Write-Host "Thank you for calling The Cleaners! 🧹`nRun " -ForegroundColor Green -NoNewline
        Write-Host 'Start-Cleaning' -BackgroundColor Black -ForegroundColor White -NoNewline
        Write-Host " to see the services we offer today.`n" -ForegroundColor Green
    }

}

Invoke-TheCleaners -InvokingCommand "$( ((Get-PSCallStack)[1]).InvocationInfo.MyCommand )"


function Clear-CurrentUserTemp {
    <#
.EXTERNALHELP TheCleaners-help.xml
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



###################################################################################
#                                                                                 #
# WARNING: This script is still being developed and tested. Use at your own risk. #
#                                                                                 #
###################################################################################
function Clear-OldExchangeLog {
    <#
.EXTERNALHELP TheCleaners-help.xml
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [Alias('Clean-ExchangeLog')]
    #[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns')]
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
            Write-Warning -WarningAction Continue 'The Exchange Server installation path could not be found. Please ensure that Exchange Server is installed on this machine.'
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
                Where-Object { ($_.Name -like '*.log') -and ($_.lastWriteTime -le "$LastWriteDate") } | Select-Object FullName

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



function Clear-OldIISLog {
    <#
.EXTERNALHELP TheCleaners-help.xml
#>
    [CmdletBinding()]
    [Alias('Clean-IISLog')]
    #[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns')]
    param (
        [Parameter()]
        [ValidateRange(1, [int16]::MaxValue)] # Ensure it is a positive number.
        [int16]
        $Days = 60
    )

    # Use the WebAdministration module if it is available
    if (Get-Module -Name 'WebAdministration' -ListAvailable) {
        # Get the logfile directory for each web site
        $WebSites = Get-Website
        foreach ($site in $WebSites) {
            $SiteLogFileDirectory = ("$($Site.logFile.directory)\W3SVC$($Site.id)").Replace( '%SystemDrive%', $env:SystemDrive )
            Write-Information -MessageData "Removing old IIS log files from $($Site.name) at $SiteLogFileDirectory." -InformationAction Continue
            try {
                Remove-OldFiles -Path $SiteLogFileDirectory -Days $Days -WhatIf
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
        $LogDir = Get-ItemProperty -Path 'HKLM:\\System\CurrentControlSet\Services\W3SVC\Parameters' -Name 'LogDir' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LogDir
        if ($LogDir -and (Test-Path -Path $LogDir)) {
            try {
                Remove-OldFiles -Path $LogDir -Days $Days
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorAction Continue
                Write-Warning "Failed to remove old IIS log files from the location specified in the directory ($LogDir)." -WarningAction Continue
            }
        } else {
            Write-Information -MessageData 'Unable to find an alternate IIS log file location from the registry.' -InformationAction Continue
        }
    }

}



function Clear-WindowsTemp {
    <#
.EXTERNALHELP TheCleaners-help.xml
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
        if ( $PSCmdlet.ShouldProcess("Removing $($file.FullName)", $file.FullName, 'Remove-Item') ) {
            try {
                Remove-Item $file -Confirm:$false -ErrorAction Stop
                Write-Verbose -Message "Removed file: $($file.FullName)"
            } catch {
                Write-Output "  $($Error[-1].Exception.Message)"
            }
        }
    }

}



function Get-StaleUserProfile {
    <#
.EXTERNALHELP TheCleaners-help.xml
#>
    [CmdletBinding()]
    param (
        # Number of days to consider a profile stale. The default is 90.
        [Parameter(Position = 0)]
        [Int16]
        $Days = 90,

        # Show a summary of the stale user profiles that were found.
        [Parameter()]
        [switch]
        $ShowSummary
    )

    # Get all user profiles that have not been used in 60 days, are not currently loaded, and are not special accounts.
    [array]$StaleUserProfiles = Get-CimInstance -Class Win32_UserProfile | Where-Object { ($_.LastUseTime -lt (Get-Date).AddDays(-$Days)) -and (!$_.Special) -and (!$_.Loaded) }
    # Might need to check last modified date using NTFS: foreach ($profile in $StaleUserProfiles) { Get-Item -Path $($_.LocalPath).LastWriteTime }

    if ($StaleUserProfiles.Count -lt 1 -or !(StaleUserProfiles)) {
        Write-Information 'No stale user profiles were found.' -InformationAction Continue
    } else {
        if ($ShowSummary) {
            $StaleUserProfiles | Select-Object LocalPath, SID, @{ Name = 'Size'; Expression = { '{0} MB' -f [math]::Round(((Get-ChildItem $_.LocalPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB)) } } | Out-Host
            Write-Information -InformationAction Continue 'NOTE: If you do not have access to a profile folder, the size will show as 0 MB.'
        }
        $StaleUserProfiles
    }
}



function Start-Cleaning {
    <#
.EXTERNALHELP TheCleaners-help.xml
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param (
        # Show dedication
        [Parameter()]
        [switch]
        $Dedication
    )

    if ($Dedication) {
        Write-Host "`nThis is dedicated to the friends that I spent years working with`nand learning PowerShell with. Cheers to Alex, Lyle, Jon, & Rick! " -ForegroundColor Yellow -NoNewline
        Write-Host "❤️`n" -ForegroundColor Red ; Write-Host ''
    }

    Show-TCLogo

    Get-Command -Module TheCleaners | Select-Object @{Name = 'The Cleaners Offer These Services: 🧹'; Expression = { $_.Name } }
}



function Convert-SamAccountNameToSID {
    <#
    .SYNOPSIS
        Translates a SamAccountName to a SID.

    .DESCRIPTION
        Translates a SamAccountName to a SID.

    .PARAMETER domain
        The domain to search for the SamAccountName.

    .PARAMETER SamAccountName
        The SamAccountName to translate to a SID.

    .EXAMPLE
        Convert-SamAccountNameToSID -Domain "contoso" -SamAccountName "jdoe"

        Translates the SamAccountName "jdoe" to a SID.

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding()]
    param (
        # The Domain
        [Parameter(Mandatory)]
        [string]$Domain,

        # The SamAccountName
        [Parameter(Mandatory)]
        [string]$SamAccountName
    )

    $User = New-Object System.Security.Principal.NTAccount($Domain,$SamAccountName)
    $SID = $User.Translate([System.Security.Principal.SecurityIdentifier])
    $SID.Value
} # End function Convert-SamAccountNameToSID


function Convert-SIDtoSamAccountName {
    <#
    .SYNOPSIS
        Translates a SID to a SamAccountName.

    .DESCRIPTION
        Translates a SID to a SamAccountName.

    .PARAMETER SID
        The SID to translate to a SamAccountName.

    .EXAMPLE
        Convert-SIDtoSamAccountName -SID "S-1-5-21-3623811015-3361044348-30300820"

        Translates the SID to a SamAccountName.

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding()]
    param (
        # The SID as a string or a SID object.
        [Parameter(Mandatory)]
        $SID
    )

    $SID = New-Object System.Security.Principal.SecurityIdentifier($SID)
    $User = $SID.Translate([System.Security.Principal.NTAccount])
    $User.Value
} # End function Convert-SIDtoSamAccountName


<#
.SYNOPSIS
    Remove files in a path that are older than the specified number of days.

.DESCRIPTION
    Remove files in a path that are older than the specified number of days. This function is used by other functions within the module when removing old files.

.EXAMPLE
    Remove-OldFiles -Path "C:\Windows\Temp" -Days 60 -Recurse

    Removes all files older than 60 does in C:\Windows\Temp with recursion to clean subfolders.
#>
function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns')]
    param (
        # The path containing files to remove
        [string]
        $Path,

        # How many days worth of logs to retain (how far back to filter)
        [int16]
        $Days = 60
    )

    begin {

    }

    process {
        Write-Verbose -Message "Finding and removing files older than $Days."
        Get-ChildItem -Path $Path -Recurse | Where-Object {
            $_.CreationTime -le ([datetime]::Now.AddDays( -$Days ))
        } | Remove-Item
    }

    end {

    }
}


function Show-TCLogo {
    <#
    .SYNOPSIS
    Show an ASCII art logo for The Cleaners.

    .DESCRIPTION
    Show a color or plain ASCII art logo for The Cleaners whenever you need it in another function.

    .PARAMETER Plain
    Return a plan-text version of the logo instead of multi-colored Write-Host output.

    .EXAMPLE
    Show-Logo

    .EXAMPLE
    Show-Logo -Plain

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
    param (
        [Parameter()]
        [switch]
        $Plain
    )

    $Version = (Import-PowerShellDataFile -Path $PSScriptRoot\..\TheCleaners.psd1).ModuleVersion

    if ($Plain.IsPresent) {
        $Logo = @"

        ╭━━━━┳╮╱╱╱╱╱╭━━━┳╮
        ┃╭╮╭╮┃┃╱╱╱╱╱┃╭━╮┃┃          v$Version
        ╰╯┃┃╰┫╰━┳━━╮┃┃╱╰┫┃╭━━┳━━┳━╮ ╭━━┳━┳━━╮
        ╱╱┃┃╱┃╭╮┃┃━┫┃┃╱╭┫┃|┃━┫╭╮┃╭╮╮┃|━┫╭┫━━┫
        ╱╱┃┃╱┃┃┃┃┃━┫┃╰━╯┃╰┫┃━┫╭╮┃||┃┃|━┫|┣━━┃
        ╱╱╰╯╱╰╯╰┻━━╯╰━━━┻━┻━━┻╯╰┻╯╰┻┻━━┻╯╰━━╯

"@
        return $Logo
    } else {
        Write-Host ''
        Write-Host '    ╭━━━━┳╮' -ForegroundColor DarkCyan -NoNewline
        Write-Host '╱╱╱╱╱' -ForegroundColor Yellow -NoNewline
        Write-Host '╭━━━┳╮' -ForegroundColor DarkCyan #NewLine
        Write-Host '    ┃╭╮╭╮┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '╱╱╱╱╱' -ForegroundColor Yellow -NoNewline
        Write-Host '┃╭━╮┃┃' -ForegroundColor DarkCyan -NoNewline #NewLine
        Write-Host " v$Version" -ForegroundColor Yellow
        Write-Host '    ╰╯┃┃╰┫╰━┳━━╮┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '/' -ForegroundColor Yellow -NoNewline
        Write-Host '╰┫┃╭━━┳━━┳━╮' -ForegroundColor DarkCyan -NoNewline
        Write-Host '*' -ForegroundColor Yellow -NoNewline
        Write-Host '╭━━┳━┳━━╮' -ForegroundColor DarkCyan #NewLine
        Write-Host '    ╱╱' -ForegroundColor Yellow -NoNewline
        Write-Host '┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '/' -ForegroundColor Yellow -NoNewline
        Write-Host '┃╭╮┃┃━┫┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '/' -ForegroundColor Yellow -NoNewline
        Write-Host '╭┫┃|┃━┫╭╮┃╭╮╮┃|━┫╭┫━━┫' -ForegroundColor DarkCyan #NewLine
        Write-Host '    ╱╱' -ForegroundColor Yellow -NoNewline
        Write-Host '┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '/' -ForegroundColor Yellow -NoNewline
        Write-Host '┃┃┃┃┃━┫┃╰━╯┃╰┫┃━┫╭╮┃||┃┃|━┫|┣━━┃' -ForegroundColor DarkCyan #NewLine
        Write-Host '    ╱╱' -ForegroundColor Yellow -NoNewline
        Write-Host '┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '/' -ForegroundColor Yellow -NoNewline
        Write-Host '╰╯╰┻━━╯╰━━━┻━┻━━┻╯╰┻╯╰┻┻━━┻╯╰━━╯' -ForegroundColor DarkCyan #NewLine
        Write-Host ''
    }
}



