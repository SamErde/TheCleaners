@{
    RootModule           = 'TheCleaners.psm1'
    ModuleVersion        = '0.0.15'
    CompatiblePSEditions = @('Core', 'Desktop')
    GUID                 = '96512386-bbd2-4e95-badd-5d175310bace'
    Author               = 'Sam Erde'
    CompanyName          = 'Sam Erde'
    Copyright            = '(c) 2026 Sam Erde. All rights reserved.'
    Description          = 'Windows temporary-file maintenance and stale-profile discovery. IIS and Exchange log discovery are preview-only and cannot delete files. Product lab validation is deferred.'
    PowerShellVersion    = '5.1'
    FunctionsToExport    = @(
        'Clear-OldExchangeLog'
        'Clear-OldIISLog'
        'Clear-CurrentUserTemp'
        'Clear-WindowsTemp'
        'Get-StaleUserProfile'
        'Get-TheCleaners'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @(
        'Clean-CurrentUserTemp'
        'Clean-ExchangeLog'
        'Clean-IISLog'
        'Clean-WindowsTemp'
        'Start-Cleaning'
    )
    PrivateData          = @{
        PSData           = @{
            Tags                       = @('Windows', 'WindowsServer', 'Windows-Server', 'PowerShell', 'SysAdmin', 'Maintenance', 'Utility', 'Utilities', 'Exchange', 'ExchangeServer', 'IIS')
            LicenseUri                 = 'https://github.com/SamErde/TheCleaners/blob/main/LICENSE'
            ProjectUri                 = 'https://github.com/SamErde/TheCleaners'
            IconUri                    = 'https://raw.githubusercontent.com/SamErde/TheCleaners/main/media/TheCleaners-Icon.png'
            Prerelease                 = 'beta'
            ReleaseNotes               = '0.0.15-beta prepares 1.0 safety, typed results, quiet imports, compatibility aliases, and deterministic packaging. Windows, IIS, Exchange, and profile lab validation is future work and is not underway. IIS and Exchange require explicit WhatIf and remain deletion-disabled. See https://day3bits.com/TheCleaners/releases/0.0.15-beta/ for release notes and limitations.'
            ExternalModuleDependencies = @()
        }
        DocumentationUri = 'https://day3bits.com/TheCleaners/'
    }
}

