function Clear-OldIISLog {
    <#
    .SYNOPSIS
        A script to clean out old IIS log files.

    .DESCRIPTION
        This command is structurally preview-only until its refactor and acceptance gates
        pass. Explicit -WhatIf is required; no IIS log files are removed.

    .PARAMETER Days
        The number of days to keep log files. The default is 30 days.

    .EXAMPLE
        Clear-OldIISLog -Days 60 -WhatIf

        Previews IIS log cleanup without removing files.

    .NOTES
        If the WebAdministration module is available, it will use that to check the specific log file locations for
        each web site. Otherwise, it checks the assumed default log folder location and the registry for the IIS
        log file location.

        Future enhancements may add a summary of which locations were processed and how many log files were removed.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [Alias('Clean-IISLog')]
    #[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns')]
    param (
        [Parameter()]
        [ValidateRange(1, [int16]::MaxValue)] # Ensure it is a positive number.
        [int16]
        $Days = 60
    )

    if (-not $PSBoundParameters.ContainsKey('WhatIf') -or -not $PSBoundParameters['WhatIf']) {
        $Exception = [System.NotSupportedException]::new('IIS cleanup is preview-only. Run Clear-OldIISLog -WhatIf. Removal is not available in this version.')
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new($Exception, 'IISCleanupPreviewOnly', [System.Management.Automation.ErrorCategory]::NotImplemented, $null)
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    # Use the WebAdministration module if it is available
    if (Get-Module -Name 'WebAdministration' -ListAvailable) {
        # Get the logfile directory for each web site
        $WebSites = Get-Website
        foreach ($site in $WebSites) {
            $SiteLogFileDirectory = ("$($Site.logFile.directory)\W3SVC$($Site.id)").Replace( '%SystemDrive%', $env:SystemDrive )
            Write-Information -MessageData "Removing old IIS log files from $($Site.name) at $SiteLogFileDirectory." -InformationAction Continue
            try {
                if ($PSCmdlet.ShouldProcess($SiteLogFileDirectory, "Preview IIS log files older than $Days days; removal is unavailable")) {
                    Remove-OldFiles -Path $SiteLogFileDirectory -Days $Days -Confirm:$false
                }
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorAction Continue
                Write-Warning "Failed to remove old IIS log files from $($Site.name) at $SiteLogFileDirectory." -WarningAction Continue
            }
        }
    } else {
        # If the WebAdministration module is not available, check the default log file location
        $DefaultIISLogLocation = "$env:SystemDrive\inetpub\logs\LogFiles"
        Write-Information "The WebAdministration module is not installed. We will check the default IIS log file location at '$DefaultIISLogLocation'." -InformationAction Continue
        if (Test-Path -LiteralPath $DefaultIISLogLocation -PathType Container) {
            try {
                if ($PSCmdlet.ShouldProcess($DefaultIISLogLocation, "Preview IIS log files older than $Days days; removal is unavailable")) {
                    Remove-OldFiles -Path $DefaultIISLogLocation -Days $Days -Confirm:$false
                }
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorAction Continue
                Write-Warning "Failed to remove old log files from the default IIS log file location at '$DefaultIISLogLocation'." -WarningAction Continue
            }
        } else {
            Write-Information -MessageData "The default IIS log file location at '$DefaultIISLogLocation' does not exist." -InformationAction Continue
        }

        # If the WebAdministration module is not available, try to check the IIS log file location from the registry (requires local admin rights to read this path)
        try {
            $LogDir = Get-ItemProperty -LiteralPath 'HKLM:\System\CurrentControlSet\Services\W3SVC\Parameters' -Name 'LogDir' -ErrorAction Stop |
                Select-Object -ExpandProperty LogDir
        } catch {
            Write-Verbose -Message "Unable to read the alternate IIS log file location from the registry: $($_.Exception.Message)"
            $LogDir = $null
        }

        if ($LogDir -and (Test-Path -LiteralPath $LogDir -PathType Container)) {
            try {
                if ($PSCmdlet.ShouldProcess($LogDir, "Preview IIS log files older than $Days days; removal is unavailable")) {
                    Remove-OldFiles -Path $LogDir -Days $Days -Confirm:$false
                }
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorAction Continue
                Write-Warning "Failed to remove old IIS log files from the location specified in the directory ($LogDir)." -WarningAction Continue
            }
        } else {
            Write-Information -MessageData 'Unable to find an alternate IIS log file location from the registry.' -InformationAction Continue
        }
    }

}
