<#PSScriptInfo
.DESCRIPTION The Cleaners do the dirty work in your servers for you. We take care of temp files, IIS logs, Exchange Server logs, and more!
.VERSION 0.0.15
.GUID bec6a004-45da-4062-ab78-b8eae99f29be
.AUTHOR Sam Erde
.COPYRIGHT (c) 2025 Sam Erde. All rights reserved.
.TAGS PowerShell Windows Utility
.LICENSEURI https://github.com/SamErde/TheCleaners/blob/main/LICENSE
.PROJECTURI https://github.com/SamErde/TheCleaners/
#>

function Invoke-TheCleaners {
    <#
    .SYNOPSIS
    Show a welcome message when the module is imported explicitly by the user.

    .DESCRIPTION
    This function shows a welcome message to help the user get started when they explicitly import the module. If the
    module is automatically imported by invoking one of its exported functions, we assume the user already knows the
    command that they want to run and do not show the welcome message.

    .PARAMETER InvokingCommand
    A parameter to receive the command line that called this function. This is used to determine if the module was
    imported explicitly by the user or automatically by invoking one of its exported functions. This information must
    come from outside the function in order to be able to determine what command invoked the script itself.

    .EXAMPLE
    Invoke-TheCleaners -InvokingCommand "$( ((Get-PSCallStack)[1]).InvocationInfo.MyCommand )"

    .NOTES
    Author: Sam Erde
    Company: Sentinel Technologies, Inc
    Date: 2025-03-11
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param (
        # The command that called this function.
        [Parameter(Mandatory)]
        [string]
        $InvokingCommand
    )

    if ($InvokingCommand -match 'ipmo|Import-Module') {
        Write-Host "Thank you for calling The Cleaners! 🧹`nRun " -ForegroundColor Green -NoNewline
        Write-Host 'Start-Cleaning' -BackgroundColor Black -ForegroundColor White -NoNewline
        Write-Host " to see the services we offer today.`n" -ForegroundColor Green
    }

}

Invoke-TheCleaners -InvokingCommand "$( ((Get-PSCallStack)[1]).InvocationInfo.MyCommand )"
