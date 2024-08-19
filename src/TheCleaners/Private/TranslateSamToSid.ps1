function TranslateSamToSid {
    <#
    .SYNOPSIS
        Translates a samaccountname to a SID.

    .DESCRIPTION
        Translates a samaccountname to a SID.

    .PARAMETER domain
        The domain to search for the SamAccountName.

    .PARAMETER SamAccountName
        The SamAccountName to translate to a SID.

    .EXAMPLE
        TranslateSamToSid -Domain "contoso" -SamAccountName "jdoe"

        Translates the SamAccountName "jdoe" to a SID.

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding()]
    param (
        # The Domain
        [Parameter(Mandatory)]
        [string]$Domain,

        # The SamAccountName
        [Parameter(Mandatory)]
        [string]$SamAccountName
    )

    $User = New-Object System.Security.Principal.NTAccount($Domain,$SamAccountName)
    $SID = $User.Translate([System.Security.Principal.SecurityIdentifier])
    $SID.Value
} # End function TranslateSamToSid
