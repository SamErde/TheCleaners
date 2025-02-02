function Get-StaleUserProfile {
    <#
    .SYNOPSIS
        A script to find old, unused user profiles in Windows.

    .DESCRIPTION
        This script finds old, unused profiles in Windows and helps you remove them. It should exclude special accounts and system profiles.

    .PARAMETER ShowSummary
        Show a summary of the stale profiles found.

    .EXAMPLE
        $StaleUserProfile = Get-StaleUserProfile -ShowSummary

        Gets stale user profiles into the StaleUserProfiles variable while also showing a summary.

    .NOTES
        Partially inspired by http://woshub.com/delete-old-user-profiles-gpo-powershell/

    .COMPONENT
        TheCleaners
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
