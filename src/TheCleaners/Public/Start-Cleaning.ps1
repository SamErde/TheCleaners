function Start-Cleaning {
    <#
    .SYNOPSIS
        Calls in TheCleaners to clean up the mess in your log folders.

    .DESCRIPTION
        Start the cleaning operation. Put documents in the shredder, clean up the mess in the log folders, and make sure the evidence is gone.

    .PARAMETER NoLogo
        Do not display the logo.

    .EXAMPLE
        Start-Cleaning

        View the menu of services that TheCleaners provide.

    .NOTES
        Author:     Sam Erde
                    https://twitter.com/SamErde
                    https://github.com/SamErde
        Modified:   2024-08-19

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # Do not show a logo
        [switch]
        $NoLogo
    )

    begin {
        $Logo = @'
        ╭━━━━┳╮╱╱╱╱╱╭━━━┳╮
        ┃╭╮╭╮┃┃╱╱╱╱╱┃╭━╮┃┃
        ╰╯┃┃╰┫╰━┳━━╮┃┃╱╰┫┃╭━━┳━━┳━╮ ╭━━┳━┳━━╮
        ╱╱┃┃╱┃╭╮┃┃━┫┃┃╱╭┫┃|┃━┫╭╮┃╭╮╮┃|━┫╭┫━━┫
        ╱╱┃┃╱┃┃┃┃┃━┫┃╰━╯┃╰┫┃━┫╭╮┃||┃┃|━┫|┣━━┃
        ╱╱╰╯╱╰╯╰┻━━╯╰━━━┻━┻━━┻╯╰┻╯╰┻┻━━┻╯╰━━╯

'@
    }

    process {
        if (-not $NoLogo) {
            Write-Output $Logo
        }
        Write-Output "The Cleaners are here to help you clean up your log folders."
        Get-Command -Module TheCleaners
        if ( $PSCmdlet.ShouldProcess($Logo) ) {
            Write-Verbose "This is here because platyPS chokes on the suppression of ShouldProcess."
        }
    }

    end {

    }
}
