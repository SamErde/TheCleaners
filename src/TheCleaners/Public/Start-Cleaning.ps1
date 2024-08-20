function Start-Cleaning {
    <#
    .SYNOPSIS
        Show the commands you can give The Cleaners.

    .DESCRIPTION
        Get started with a menu of services The Cleaners can offer.

    .PARAMETER NoLogo
        Do not display the logo.

    .EXAMPLE
        Start-Cleaning

        View the menu of services that TheCleaners provide.

    .COMPONENT
        TheCleaners
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param (
        # Show dedication
        [Parameter()]
        [switch]
        $Dedication
    )

    Show-TCLogo

    if ($Dedication) {
        Write-Output "This module is dedicated to the old SEs I ""grew up"" and learned PowerShell with. Cheers to Alex, Lyle, Jon, and Rick! ❤️`n"
    }

    Write-Output "The Cleaners are here to help you clean up your log folders! 🧹"
    Get-Command -Module TheCleaners
}
