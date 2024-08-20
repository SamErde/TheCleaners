﻿function Start-Cleaning {
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param (
        # Show dedication
        [Parameter()]
        [switch]
        $Dedication
    )

    Show-TCLogo

    if ($Dedication) {
        Write-Host "`nThis is dedicated to the friends that I spent years working with`nand learning PowerShell with. Cheers to Alex, Lyle, Jon, & Rick! " -ForegroundColor Yellow -NoNewline
        Write-Host "❤️ `n" -ForegroundColor Red
    }

    Write-Output "The Cleaners are here to help you clean up your log folders! 🧹`n"
    Get-Command -Module TheCleaners
}
