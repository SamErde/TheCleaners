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

    .NOTES
        This is an OLD script that I want to loop back and freshen up. It works, but isn't pretty.

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding()]

    $objUser = New-Object System.Security.Principal.NTAccount($domain,$samaccountname)
    $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
    $strsid.Value
} # End function TranslateSamToSid
