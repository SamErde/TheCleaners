function Invoke-TheCleaners {
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
