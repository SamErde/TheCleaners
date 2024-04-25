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
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Remove-OldProfiles')]
    param (

    )

    $StaleUserProfiles = Get-StaleUserProfiles
    Remove-StaleUserProfiles
    Remove-OldProfiles
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
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Remove-StaleUserProfiles')]
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
        Write-Information "There are no profiles to clean out." -InformationAction Continue
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
            Write-Information "Removing $LocalPath (SID: $ProfileSID)" -InformationAction Continue
            try {
                $UserProfile | Remove-CimInstance -ErrorAction Stop
            } catch {
                Write-Error $Error[0].Exception
            }
        } # End if
    } # End foreach loop through profiles
} # End function Remove-StaleProfiles
