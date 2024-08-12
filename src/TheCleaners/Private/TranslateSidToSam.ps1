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

    .NOTES
        This is an OLD script that I want to loop back and freshen up. It works, but isn't pretty.

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding()]

    $objSID = New-Object System.Security.Principal.SecurityIdentifier($sid)
    $strUser = $objSID.Translate([System.Security.Principal.NTAccount])
    $strUser.Value
} # End function TranslateSidToSam
