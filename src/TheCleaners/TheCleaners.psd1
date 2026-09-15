@{
    RootModule           = 'TheCleaners.psm1'
    ModuleVersion        = '0.0.15'
    CompatiblePSEditions = @('Core', 'Desktop')
    GUID                 = '96512386-bbd2-4e95-badd-5d175310bace'
    Author               = 'Sam Erde'
    CompanyName          = 'Sam Erde'
    Copyright            = '(c) 2026 Sam Erde. All rights reserved.'
    Description          = 'Windows maintenance commands for temporary files, IIS logs, and stale-profile discovery. Exchange log discovery is preview-only; Exchange deletion is unavailable.'
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
        PSData          = @{
            Tags                       = @('Windows', 'WindowsServer', 'Windows-Server', 'PowerShell', 'SysAdmin', 'Maintenance', 'Utility', 'Utilities', 'Exchange', 'ExchangeServer', 'IIS')
            LicenseUri                 = 'https://github.com/SamErde/TheCleaners/blob/main/LICENSE'
            ProjectUri                 = 'https://github.com/SamErde/TheCleaners'
            IconUri                    = 'https://raw.githubusercontent.com/SamErde/TheCleaners/main/media/TheCleaners-Icon.png'
            Prerelease                 = 'beta'
            ExternalModuleDependencies = @()
        }
        DocumentationUri = 'https://day3bits.com/thecleaners/'
    }
}

