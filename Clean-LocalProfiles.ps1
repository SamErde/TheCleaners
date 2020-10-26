<#  Clean-LocalProfiles.ps1

    A script to find and remove old, unused user profiles in Windows. 
    Exclude special accounts and profiles that should not be removed. 
#>

# Get all user profiles that have not been used in 60 days, are not currently loaded, and are not special accounts.
$UserProfiles = Get-CimInstance -Class Win32_UserProfile | `
    Where-Object { ($_.LastUseTime -lt (Get-Date).AddDays(-60)) -and (!$_.Special) -and (!$_.Loaded) }

    If ($UserProfiles.Count -lt 1) { Write-Host "No applicable user profiles were found." -ForegroundColor Yellow }
    Else { 
        $UserProfiles | Select-Object LocalPath,SID, `
            @{Name="Size";Expression={"{0} MB" -f [math]::Round(((Get-ChildItem $_.LocalPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB))}}
        Write-Host $UserProfiles "`nRun the function CleanProfiles to remove these objects. Note, if you do not have access to a profile folder, the size will show as 0 MB." 
    } # End if/else

Function TranslateSamToSid ($domain, $samaccountname) 
{
    # Translate samaccountname to SID; use if getting additional account information from AD, such as special group membership
    $objUser = New-Object System.Security.Principal.NTAccount($domain,$samaccountname)
    $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
    Return $strsid.Value
} # End function

Function TranslateSidtoSam ($sid) 
{
    # Translate SID to samaccountname; use if getting additional account information from AD, such as special group membership
    $objSID = New-object System.Security.Principal.SecurityIdentifier($sid)
    $strUser = $objSID.Translate([System.Security.Principal.NTAccount])
    Return $strUser.Value
} # End function

Function CleanProfiles 
{   
    <# Need to finish with check to see if the account is a member of special domain groups, such as: 
        Service Accounts
        URA Groups
        Admin Groups
        IIS* Groups
    #>
    
    # Walk away if there are no profiles to clean out.
    if ($UserProfiles.Count -lt 1) { 
        Write-Host "There are no profiles to clean out." -ForegroundColor Yellow
        Exit
    } # Only continue if there ARE profiles to clean up.

    $AlwaysExcluded ="Public","svc","admin" #Etc

    foreach ($UserProfile in $UserProfiles)
    {
        # Grab properties to use for informative host output.
        $LocalPath = $UserProfile.LocalPath
        $ProfileSID = $UserProfile.SID

        # If the user profile's local path does not match anything in $AlwaysExcluded, the profile will be removed.
        # This part of the logic does have some gaps, eg account names that don't match their profile folder name.
        if (!($AlwaysExcluded -like $LocalPath.Replace("C:\Users\",""))) 
            {
                Write-Host "Removing $LocalPath (SID: $ProfileSID)" -ForegroundColor Yellow
                Try { $UserProfile | Remove-CimInstance -ErrorAction Stop }
                Catch { Write-Host $Error[0].Exception -ForegroundColor Magenta }
            } # End if
    } # End foreach loop through profiles
} # End function

# Add a switch parameter handler to the script so running it with -Clean will execute the CleanProfiles function. 
