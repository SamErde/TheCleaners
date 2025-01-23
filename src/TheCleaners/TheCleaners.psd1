@{

    # Script module or binary module file associated with this manifest.
    RootModule           = 'TheCleaners.psm1'

    # Version number of this module.
    ModuleVersion        = '0.0.14'

    # Supported PSEditions
    CompatiblePSEditions = @('Core', 'Desktop')

    # ID used to uniquely identify this module
    GUID                 = '96512386-bbd2-4e95-badd-5d175310bace'

    # Author of this module
    Author               = 'Sam Erde'

    # Company or vendor of this module
    CompanyName          = 'Sam Erde'

    # Copyright statement for this module
    Copyright            = '(c) 2025 Sam Erde. All rights reserved.'

    # Description of the functionality provided by this module
    Description          = 'The Cleaners do the dirty work in your servers for you. We take care of temp files, IIS logs, Exchange Server logs, and more!'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion    = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    # RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport    = @(
        'Clear-OldExchangeLog',
        'Clear-OldIISLog',
        'Clear-CurrentUserTemp',
        'Clear-WindowsTemp',
        'Get-StaleUserProfile',
        'Start-Cleaning'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport      = @()

    # Variables to export from this module
    VariablesToExport    = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport      = @(
        'Clean-CurrentUserTemp',
        'Clean-ExchangeLog',
        'Clean-IISLog',
        'Clean-WindowsTemp'
    )

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData          = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags       = @('Windows', 'WindowsServer', 'Windows-Server', 'PowerShell', 'SysAdmin', 'Maintenance', 'Utility', 'Utilities', 'Exchange', 'ExchangeServer', 'IIS')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/SamErde/TheCleaners/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/SamErde/TheCleaners'

            # A URL to an icon representing this module.
            IconUri    = 'https://raw.githubusercontent.com/SamErde/TheCleaners/main/media/TheCleaners-Icon.png'

            # ReleaseNotes of this module
            # ReleaseNotes = ''

            # Prerelease string of this module
            Prerelease = 'alpha'

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()

        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    HelpInfoURI          = 'https://raw.githubusercontent.com/SamErde/TheCleaners/main/src/Help/'

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''

}
