function Get-StaleUserProfiles {
    <#
    .SYNOPSIS
        A script to find old, unused user profiles in Windows.

    .DESCRIPTION
        THIS IS AN EARLY POC SCRIPT THAT NEEDS TO BE TESTED FOR PROPER EXCLUSIONS. This script finds old, unused
        profiles in Windows and helps you remove them. It should exclude special accounts and system profiles.

    .EXAMPLE
        $StaleUserProfiles = Get-StaleUserProfiles -ShowSummary

        Gets stale user profiles into the StaleUserProfiles variable while also showing a summary.

    .NOTES
        Author: Sam Erde
                https://twitter.com/SamErde
                https://github.com/SamErde

        Partially inspired by http://woshub.com/delete-old-user-profiles-gpo-powershell/

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns')]
    param (
        [Parameter()]
        [switch]
        $ShowSummary
    )

    # Get all user profiles that have not been used in 60 days, are not currently loaded, and are not special accounts.
    [array]$StaleUserProfiles = Get-CimInstance -Class Win32_UserProfile | Where-Object { ($_.LastUseTime -lt (Get-Date).AddDays(-60)) -and (!$_.Special) -and (!$_.Loaded) }

    if ($StaleUserProfiles.Count -lt 1 -or !(StaleUserProfiles)) {
        Write-Information "No stale user profiles were found." -InformationAction Continue
    } else {
        if ($ShowSummary) {
            $StaleUserProfiles | Select-Object LocalPath,SID, @{ Name="Size"; Expression={"{0} MB" -f [math]::Round(((Get-ChildItem $_.LocalPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB))} } | Out-Host
            Write-Information -InformationAction Continue "NOTE: If you do not have access to a profile folder, the size will show as 0 MB."
        }
        $StaleUserProfiles
    }
}
