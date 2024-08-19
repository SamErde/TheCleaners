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
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # Do not show a logo
        [switch]
        $NoLogo
    )

    $Logo = @'
        ╭━━━━┳╮╱╱╱╱╱╭━━━┳╮
        ┃╭╮╭╮┃┃╱╱╱╱╱┃╭━╮┃┃
        ╰╯┃┃╰┫╰━┳━━╮┃┃╱╰┫┃╭━━┳━━┳━╮ ╭━━┳━┳━━╮
        ╱╱┃┃╱┃╭╮┃┃━┫┃┃╱╭┫┃|┃━┫╭╮┃╭╮╮┃|━┫╭┫━━┫
        ╱╱┃┃╱┃┃┃┃┃━┫┃╰━╯┃╰┫┃━┫╭╮┃||┃┃|━┫|┣━━┃
        ╱╱╰╯╱╰╯╰┻━━╯╰━━━┻━┻━━┻╯╰┻╯╰┻┻━━┻╯╰━━╯

'@

    if (-not $NoLogo) {
        Write-Output $Logo
    }
    Write-Output "The Cleaners are here to help you clean up your log folders."
    Get-Command -Module TheCleaners
    if ( $PSCmdlet.ShouldProcess($Logo) ) {
        Write-Verbose "This is here because platyPS chokes on the suppression of ShouldProcess."
    }
}
