function Remove-OldProfiles {
    <#
        .SYNOPSIS
            Removes old, inactive user profiles from the local system.

        .DESCRIPTION
            Removes old, inactive user profiles from the local system.

        .EXAMPLE
            Remove-OldProfiles

            Removes old, inactive user profiles from the local system.
        .NOTES
            Author:     Sam Erde
                        https://twitter.com/SamErde
                        https://github.com/SamErde
            Modified:   2024-02-19
    #>

    $StaleUserProfiles = Get-StaleUserProfiles
    Remove-StaleUserProfiles
    Remove-OldProfiles
}

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
    #>
    [CmdletBinding()]
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

function Remove-StaleUserProfiles {
    <#
        .SYNOPSIS
            Removes stale user profiles from the local system.
        .DESCRIPTION
            Removes stale user profiles from the local system.
        .PARAMETER StaleUserProfiles
            The stale user profiles to remove.
        .EXAMPLE
            Remove-StaleUserProfiles -StaleUserProfiles $StaleUserProfiles

            Removes the stale user profiles from the local system.
    #>
    [CmdletBinding()]
    <#
        .SYNOPSIS
            Removes stale user profiles from the local system.
        .DESCRIPTION
            Removes stale user profiles from the local system.
        .PARAMETER StaleUserProfiles
            The stale user profiles to remove.
        .EXAMPLE
            Remove-StaleUserProfiles -StaleUserProfiles $StaleUserProfiles

            Removes the stale user profiles from the local system.
    #>
    param (
        [Parameter(Mandatory)]
        $StaleUserProfiles
    )
    <#
        May need to finish with a check to see if the account is a member of special domain groups. Are there
        any domain groups whose users that might need to be left even if they appear to be inactive?
    #>

    # Walk away if there are no profiles to clean out.
    if ($StaleUserProfiles.Count -lt 1) {
        Write-Host "There are no profiles to clean out." -ForegroundColor Yellow
        break
    } # Only continue if there ARE profiles to clean up.

    $AlwaysExcluded ="Public","svc","admin" #Etc

    foreach ($UserProfile in $StaleUserProfiles) {
        # Grab properties to use for informative host output.
        $LocalPath = $UserProfile.LocalPath
        $ProfileSID = $UserProfile.SID

        # If the user profile's local path does not match anything in $AlwaysExcluded, the profile will be removed.
        # This part of the logic does have some gaps, eg account names that don't match their profile folder name.
        if (!($AlwaysExcluded -like $LocalPath.Replace("C:\Users\",""))) {
            Write-Host "Removing $LocalPath (SID: $ProfileSID)" -ForegroundColor Yellow
            try {
                $UserProfile | Remove-CimInstance -ErrorAction Stop
            } catch {
                Write-Host $Error[0].Exception -ForegroundColor Magenta
            }
        } # End if
    } # End foreach loop through profiles
} # End function Remove-StaleProfiles

function TranslateSamToSid ($domain, $samaccountname) {
    <#
        .SYNOPSIS
            Translates a samaccountname to a SID.
        .DESCRIPTION
            Translates a samaccountname to a SID.
        .PARAMETER domain
            The domain to search for the samaccountname.
        .PARAMETER samaccountname
            The samaccountname to translate to a SID.
        .EXAMPLE
            TranslateSamToSid -domain "contoso" -samaccountname "jdoe"

            Translates the samaccountname "jdoe" to a SID.
    #>
    [CmdletBinding()]

    $objUser = New-Object System.Security.Principal.NTAccount($domain,$samaccountname)
    $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
    $strsid.Value
} # End function TranslateSamToSid

function TranslateSidToSam ($sid) {
    <#
        .SYNOPSIS
            Translates a SID to a samaccountname.
        .DESCRIPTION
            Translates a SID to a samaccountname.
        .PARAMETER sid
            The SID to translate to a samaccountname.
        .EXAMPLE
            TranslateSidToSam -sid "S-1-5-21-3623811015-3361044348-30300820"

            Translates the SID to a samaccountname.
    #>
    [CmdletBinding()]

    $objSID = New-Object System.Security.Principal.SecurityIdentifier($sid)
    $strUser = $objSID.Translate([System.Security.Principal.NTAccount])
    $strUser.Value
} # End function TranslateSidToSam
