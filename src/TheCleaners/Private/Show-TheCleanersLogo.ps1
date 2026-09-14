function Show-TheCleanersLogo {
    <#
    .SYNOPSIS
        Show an ASCII art logo for The Cleaners.
    .DESCRIPTION
        Show a color or plain-text logo only when explicitly requested by a command.
    .PARAMETER Plain
        Return the logo as a string instead of colored host output.
    .EXAMPLE
        Show-TheCleanersLogo
    .EXAMPLE
        Show-TheCleanersLogo -Plain
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Explicit interactive branding, never called during module import.')]
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()]
        [switch]
        $Plain
    )

    # Works in both the source-layout and legacy merged package.
    $Version = $ExecutionContext.SessionState.Module.Version
    $Logo = @"

        ╭━━━━┳╮╱╱╱╱╱╭━━━┳╮
        ┃╭╮╭╮┃┃╱╱╱╱╱┃╭━╮┃┃          v$Version
        ╰╯┃┃╰┫╰━┳━━╮┃┃╱╰┫┃╭━━┳━━┳━╮ ╭━━┳━┳━━╮
        ╱╱┃┃╱┃╭╮┃┃━┫┃┃╱╭┫┃|┃━┫╭╮┃╭╮╮┃|━┫╭┫━━┫
        ╱╱┃┃╱┃┃┃┃┃━┫┃╰━╯┃╰┫┃━┫╭╮┃||┃┃|━┫|┣━━┃
        ╱╱╰╯╱╰╯╰┻━━╯╰━━━┻━┻━━┻╯╰┻╯╰┻┻━━┻╯╰━━╯

"@
    if ($Plain) {
        $Logo
    } else {
        Write-Host -Object $Logo -ForegroundColor DarkCyan
    }
}

