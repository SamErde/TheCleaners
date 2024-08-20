function Show-TCLogo {
    <#
    .SYNOPSIS
    Show an ASCII art logo for The Cleaners.

    .DESCRIPTION
    Show a color or plain ASCII art logo for The Cleaners whenever you need it in another function.

    .PARAMETER Plain
    Return a plan-text version of the logo instead of multi-colored Write-Host output.

    .EXAMPLE
    Show-Logo

    .EXAMPLE
    Show-Logo -Plain

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
    param (
        [Parameter()]
        [switch]
        $Plain
    )

    $Version = (Import-PowerShellDataFile -Path $PSScriptRoot\..\TheCleaners.psd1).ModuleVersion

    if ($Plain.IsPresent) {
        $Logo = @"

        ╭━━━━┳╮╱╱╱╱╱╭━━━┳╮
        ┃╭╮╭╮┃┃╱╱╱╱╱┃╭━╮┃┃          v$Version
        ╰╯┃┃╰┫╰━┳━━╮┃┃╱╰┫┃╭━━┳━━┳━╮ ╭━━┳━┳━━╮
        ╱╱┃┃╱┃╭╮┃┃━┫┃┃╱╭┫┃|┃━┫╭╮┃╭╮╮┃|━┫╭┫━━┫
        ╱╱┃┃╱┃┃┃┃┃━┫┃╰━╯┃╰┫┃━┫╭╮┃||┃┃|━┫|┣━━┃
        ╱╱╰╯╱╰╯╰┻━━╯╰━━━┻━┻━━┻╯╰┻╯╰┻┻━━┻╯╰━━╯

"@
        return $Logo
    } else {
        Write-Host ''
        Write-Host '    ╭━━━━┳╮' -ForegroundColor DarkCyan -NoNewline
        Write-Host '╱╱╱╱╱' -ForegroundColor Yellow -NoNewline
        Write-Host '╭━━━┳╮' -ForegroundColor DarkCyan #NewLine
        Write-Host '    ┃╭╮╭╮┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '╱╱╱╱╱' -ForegroundColor Yellow -NoNewline
        Write-Host '┃╭━╮┃┃' -ForegroundColor DarkCyan -NoNewline #NewLine
        Write-Host " v$Version" -ForegroundColor Yellow
        Write-Host '    ╰╯┃┃╰┫╰━┳━━╮┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '/' -ForegroundColor Yellow -NoNewline
        Write-Host '╰┫┃╭━━┳━━┳━╮' -ForegroundColor DarkCyan -NoNewline
        Write-Host '*' -ForegroundColor Yellow -NoNewline
        Write-Host '╭━━┳━┳━━╮' -ForegroundColor DarkCyan #NewLine
        Write-Host '    ╱╱' -ForegroundColor Yellow -NoNewline
        Write-Host '┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '/' -ForegroundColor Yellow -NoNewline
        Write-Host '┃╭╮┃┃━┫┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '/' -ForegroundColor Yellow -NoNewline
        Write-Host '╭┫┃|┃━┫╭╮┃╭╮╮┃|━┫╭┫━━┫' -ForegroundColor DarkCyan #NewLine
        Write-Host '    ╱╱' -ForegroundColor Yellow -NoNewline
        Write-Host '┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '/' -ForegroundColor Yellow -NoNewline
        Write-Host '┃┃┃┃┃━┫┃╰━╯┃╰┫┃━┫╭╮┃||┃┃|━┫|┣━━┃' -ForegroundColor DarkCyan #NewLine
        Write-Host '    ╱╱' -ForegroundColor Yellow -NoNewline
        Write-Host '┃┃' -ForegroundColor DarkCyan -NoNewline
        Write-Host '/' -ForegroundColor Yellow -NoNewline
        Write-Host '╰╯╰┻━━╯╰━━━┻━┻━━┻╯╰┻╯╰┻┻━━┻╯╰━━╯' -ForegroundColor DarkCyan #NewLine
        Write-Host ''
    }
}
