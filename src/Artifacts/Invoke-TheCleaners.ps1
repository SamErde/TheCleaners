<#PSScriptInfo
.DESCRIPTION The Cleaners do the dirty work in your servers for you. We take care of temp files, IIS logs, Exchange Server logs, and more!
.VERSION 0.0.15
.GUID bec6a004-45da-4062-ab78-b8eae99f29be
.AUTHOR Sam Erde
.COPYRIGHT (c) 2025 Sam Erde. All rights reserved.
.TAGS Update PowerShell Windows
.LICENSEURI https://github.com/SamErde/TheCleaners/blob/main/LICENSE
.PROJECTURI https://github.com/SamErde/TheCleaners/
#>
function Invoke-TheCleaners {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    Write-Host "Thank you for calling The Cleaners! 🧹`nRun " -ForegroundColor Green -NoNewline
    Write-Host 'Start-Cleaning' -BackgroundColor Black -ForegroundColor White -NoNewline
    Write-Host " to see the services we offer today.`n" -ForegroundColor Green
}

Invoke-TheCleaners
