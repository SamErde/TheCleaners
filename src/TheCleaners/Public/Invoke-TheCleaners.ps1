﻿function Invoke-TheCleaners {
    <#
        .SYNOPSIS
            Calls in the cleaners to clean up the mess in your log folders.

        .DESCRIPTION
            Start the cleaning operation. Put documents in the shredder, clean up the mess in the log folders, and make sure the evidence is gone.

        .EXAMPLE
            Invoke-TheCleaners

            View the menu of services that The Cleaners provide.

        .NOTES
            Author:     Sam Erde
                        https://twitter.com/SamErde
                        https://github.com/SamErde
            Modified:   2024-02-19
    #>
    [CmdletBinding()]
    param (
        # Nothing here yet
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
        Write-Output $Logo
        Write-Output "The Cleaners are here to help you clean up that crime scene in your log folders."
        Write-Output "This function hasn't been implemented yet."
        Get-Command -Module TheCleaners
    }

    end {

    }
}
