function Get-TheCleaners {
    <#
    .SYNOPSIS
        Get the available TheCleaners commands and their current maturity.
    .DESCRIPTION
        Return one TheCleaners.CommandInfo object per public function. The command never
        performs cleanup. No command is labeled stable before its acceptance gates pass.
        Start-Cleaning remains a deprecated compatibility alias through the 1.x releases.
    .PARAMETER Dedication
        Show a dedication before the command inventory.
    .PARAMETER NoLogo
        Omit the interactive logo. Use this for pipeline and automation scenarios.
    .EXAMPLE
        Get-TheCleaners
    .EXAMPLE
        Get-TheCleaners -NoLogo | Where-Object Maturity -EQ 'PreviewOnly'
    .OUTPUTS
        TheCleaners.CommandInfo
    .LINK
        https://day3bits.com/thecleaners/Get-TheCleaners/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Opt-in dedication, not pipeline data.')]
    [CmdletBinding()]
    [Alias('Start-Cleaning')]
    [OutputType('TheCleaners.CommandInfo')]
    param (
        [Parameter()]
        [switch]
        $Dedication,

        [Parameter()]
        [switch]
        $NoLogo
    )

    if ($Dedication) {
        Write-Host -Object 'Dedicated to the friends I spent years working with and learning PowerShell with. Cheers to Alex, Lyle, Jon, and Rick!' -ForegroundColor Yellow
    }
    if (-not $NoLogo) {
        Show-TheCleanersLogo
    }

    $Module = $ExecutionContext.SessionState.Module
    foreach ($Command in @($Module.ExportedFunctions.Values | Sort-Object -Property Name)) {
        $IsPreviewOnly = $Command.Name -in @('Clear-OldExchangeLog', 'Clear-OldIISLog')
        [pscustomobject]@{
            PSTypeName     = 'TheCleaners.CommandInfo'
            Name           = $Command.Name
            Maturity       = if ($IsPreviewOnly) { 'PreviewOnly' } else { 'Prerelease' }
            RemovalEnabled = $Command.Name -like 'Clear-*' -and -not $IsPreviewOnly
            SupportsWhatIf = $Command.Parameters.ContainsKey('WhatIf')
        }
    }
}
