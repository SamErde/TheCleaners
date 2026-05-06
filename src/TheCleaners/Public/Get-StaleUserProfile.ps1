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
        [ValidateRange(1, [int16]::MaxValue)]
        [Int16]
        $Days = 90,

        # Show a summary of the stale user profiles that were found.
        [Parameter()]
        [switch]
        $ShowSummary
    )

    $IsWindowsHost = $PSVersionTable.PSEdition -eq 'Desktop' -or ($PSVersionTable.PSVersion.Major -ge 6 -and $IsWindows)
    if (-not $IsWindowsHost) {
        Write-Error -Message 'Get-StaleUserProfile requires Windows because it queries Win32_UserProfile.'
        return
    }

    try {
        $CutoffDate = (Get-Date).AddDays(-$Days)
        [array]$StaleUserProfiles = Get-CimInstance -Class Win32_UserProfile -ErrorAction Stop | Where-Object {
            ($_.LastUseTime -lt $CutoffDate) -and (-not $_.Special) -and (-not $_.Loaded)
        }
    } catch {
        Write-Error -Message "Failed to query Win32_UserProfile: $($_.Exception.Message)"
        return
    }
    # Might need to check last modified date using NTFS: foreach ($profile in $StaleUserProfiles) { Get-Item -Path $($_.LocalPath).LastWriteTime }

    if ($StaleUserProfiles.Count -lt 1 -or -not $StaleUserProfiles) {
        Write-Information 'No stale user profiles were found.' -InformationAction Continue
    } else {
        if ($ShowSummary) {
            $StaleUserProfiles | Select-Object LocalPath, SID, @{
                Name       = 'Size'
                Expression = {
                    try {
                        '{0} MB' -f [math]::Round(((Get-ChildItem -LiteralPath $_.LocalPath -Recurse -File -Force -ErrorAction Stop | Measure-Object -Property Length -Sum).Sum / 1MB))
                    } catch {
                        Write-Warning -Message "Failed to measure profile '$($_.LocalPath)': $($_.Exception.Message)"
                        'Unavailable'
                    }
                }
            } | Out-Host
            Write-Information -InformationAction Continue 'NOTE: If you do not have access to a profile folder, the size will show as Unavailable.'
        }
        $StaleUserProfiles
    }
}
