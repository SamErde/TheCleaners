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
