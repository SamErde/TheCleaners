<#
.SYNOPSIS
    Record read-only IIS and Exchange preview-lab state.
.DESCRIPTION
    Collect exact host, product, service, protected-path, and preview-result
    evidence without enabling or performing deletion. A missing product is an
    explicit lab limitation, not an empty successful candidate discovery.
.EXAMPLE
    .\lab\Invoke-TheCleanersProductPreviewLab.ps1 -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param ()

$ErrorActionPreference = 'Stop'
if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Run read-only IIS and Exchange preview probes')) {
    return
}

$ModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/TheCleaners/TheCleaners.psd1'
Import-Module -Name $ModuleManifest -Force
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [System.Security.Principal.WindowsPrincipal]::new($Identity)
$OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
$Volumes = @(Get-Volume | Where-Object FileSystem | Select-Object DriveLetter, FileSystem, FileSystemLabel, Size, SizeRemaining)

function Get-ServiceEvidence {
    param (
        [Parameter(Mandatory)]
        [string[]]
        $Names
    )

    foreach ($Name in $Names) {
        try {
            $Service = Get-Service -Name $Name -ErrorAction Stop | Select-Object -First 1
        } catch {
            $ServiceIsAbsent = $_.FullyQualifiedErrorId -match '^NoServiceFoundForGivenName,'
            if ($ServiceIsAbsent) {
                $Service = $null
            } else {
                $Failure = [System.InvalidOperationException]::new(
                    "Unable to determine service state for '$Name': $($_.Exception.Message)",
                    $_.Exception
                )
                throw $Failure
            }
        }
        [ordered]@{
            Name   = $Name
            Exists = $null -ne $Service
            Status = if ($null -eq $Service) { 'NotInstalled' } else { [string]$Service.Status }
            StartType = if ($null -eq $Service) { $null } else { [string]$Service.StartType }
        }
    }
}

function Get-OptionalRegistryProperty {
    param (
        [Parameter(Mandatory)]
        [string]
        $LiteralPath
    )

    try {
        Get-ItemProperty -LiteralPath $LiteralPath -ErrorAction Stop
    } catch {
        $RegistryKeyIsAbsent = (
            $_.Exception -is [System.Management.Automation.ItemNotFoundException] -or
            $_.FullyQualifiedErrorId -match 'PathNotFound|ItemNotFound|RegistryKeyNotFound'
        )
        if ($RegistryKeyIsAbsent) {
            return $null
        }
        $Failure = [System.InvalidOperationException]::new(
            "Unable to determine product state from registry path '$LiteralPath': $($_.Exception.Message)",
            $_.Exception
        )
        throw $Failure
    }
}

function Get-ExchangeManagementCommandEvidence {
    [CmdletBinding()]
    param ()

    $Evidence = [System.Collections.Generic.List[object]]::new()
    foreach ($Name in @('Get-ExchangeServer', 'Get-MailboxDatabase')) {
        try {
            $Command = Get-Command -Name $Name -ErrorAction Stop | Select-Object -First 1
            if ($null -ne $Command) {
                $Evidence.Add([pscustomobject]@{
                        Name        = $Command.Name
                        CommandType = [string]$Command.CommandType
                        Version     = if ($null -eq $Command.Version) { $null } else { $Command.Version.ToString() }
                    })
            }
        } catch {
            $CommandIsAbsent = (
                $_.Exception -is [System.Management.Automation.CommandNotFoundException] -or
                $_.FullyQualifiedErrorId -match 'CommandNotFound'
            )
            if (-not $CommandIsAbsent) {
                throw [System.InvalidOperationException]::new(
                    "Unable to determine Exchange management command '$Name': $($_.Exception.Message)",
                    $_.Exception
                )
            }
        }
    }
    @($Evidence.ToArray())
}

function Get-PreviewEvidence {
    param (
        [Parameter(Mandatory)]
        [string]
        $CommandName
    )

    try {
        $BeforeResults = @(& $CommandName -WhatIf -Confirm:$false -PassThru -ErrorAction Stop)
        if ($BeforeResults.Count -eq 0) {
            $NoResultErrorId = if ($CommandName -eq 'Clear-OldIISLog') { 'IISPreviewNoResults' } else { 'ExchangePreviewNoResults' }
            throw [System.InvalidOperationException]::new("$CommandName returned no preview result for an existing product or configured root.")
        }
        $AfterResults = @(& $CommandName -WhatIf -Confirm:$false -PassThru -ErrorAction Stop)
        if ($AfterResults.Count -eq 0) {
            $NoResultErrorId = if ($CommandName -eq 'Clear-OldIISLog') { 'IISPreviewNoResults' } else { 'ExchangePreviewNoResults' }
            throw [System.InvalidOperationException]::new("$CommandName returned no preview result during the after snapshot.")
        }
        $CandidatesBefore = @($BeforeResults | ForEach-Object { $_.CandidatePaths } | Where-Object { $_ })
        $CandidatesAfter = @($AfterResults | ForEach-Object { $_.CandidatePaths } | Where-Object { $_ })
        $ProtectedPaths = @($AfterResults | ForEach-Object { $_.ProtectionPaths } | Where-Object { $_ } | Sort-Object -Unique)
        [ordered]@{
            ResultStatus        = 'Completed'
            ErrorId             = $null
            ErrorMessage        = $null
            CandidatesBefore    = $CandidatesBefore
            CandidateCountBefore = $CandidatesBefore.Count
            CandidatesAfter     = $CandidatesAfter
            CandidateCountAfter = $CandidatesAfter.Count
            ProtectedPaths      = $ProtectedPaths
            Results             = $AfterResults
        }
    } catch {
        $ErrorId = if ($null -ne $NoResultErrorId) { $NoResultErrorId } else { $_.FullyQualifiedErrorId }
        [ordered]@{
            ResultStatus        = 'Unavailable'
            ErrorId             = $ErrorId
            ErrorMessage        = $_.Exception.Message
            CandidatesBefore    = @()
            CandidateCountBefore = $null
            CandidatesAfter     = @()
            CandidateCountAfter = $null
            ProtectedPaths      = @()
            Results             = @()
        }
    }
}

$IisRegistry = Get-OptionalRegistryProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\InetStp'
$ExchangeRegistry = Get-OptionalRegistryProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup'
$IisModule = Get-Module -ListAvailable -Name WebAdministration | Sort-Object Version -Descending | Select-Object -First 1
$ExchangeCommands = @()
$ExchangeCommandProbe = [ordered]@{
    Status        = $null
    ErrorId       = $null
    ErrorMessage  = $null
    CommandCount  = 0
}
try {
    $ExchangeCommands = @(Get-ExchangeManagementCommandEvidence)
    $ExchangeCommandProbe.Status = if ($ExchangeCommands.Count -eq 0) { 'NotInstalled' } else { 'Validated' }
    $ExchangeCommandProbe.CommandCount = $ExchangeCommands.Count
} catch {
    $ExchangeCommandProbe.Status = 'Failed'
    $ExchangeCommandProbe.ErrorId = 'ExchangeManagementCommandProbeFailed'
    $ExchangeCommandProbe.ErrorMessage = $_.Exception.Message
}
$IisPreview = Get-PreviewEvidence -CommandName 'Clear-OldIISLog'
$ExchangePreview = Get-PreviewEvidence -CommandName 'Clear-OldExchangeLog'

[ordered]@{
    RecordedUtc       = [DateTime]::UtcNow.ToString('o')
    ComputerName      = $env:COMPUTERNAME
    Runtime           = [ordered]@{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        PSEdition          = $PSVersionTable.PSEdition
        OS                 = $OperatingSystem.Caption
        OSVersion          = $OperatingSystem.Version
        OSBuild            = $OperatingSystem.BuildNumber
        IsElevated         = $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    Volumes            = $Volumes
    IIS                = [ordered]@{
        ProductDetected = $null -ne $IisRegistry
        ProductBuild    = if ($null -eq $IisRegistry) { $null } else { [ordered]@{ Major = $IisRegistry.MajorVersion; Minor = $IisRegistry.MinorVersion; Build = $IisRegistry.BuildNumber; Version = $IisRegistry.VersionString } }
        WebAdministration = if ($null -eq $IisModule) { $null } else { [ordered]@{ Version = $IisModule.Version.ToString(); Path = $IisModule.Path } }
        Services         = @(Get-ServiceEvidence -Names @('W3SVC', 'WAS'))
        ProtectedPaths   = @($IisPreview.ProtectedPaths)
        Preview         = $IisPreview
    }
    Exchange           = [ordered]@{
        ProductDetected = $null -ne $ExchangeRegistry
        ProductBuild    = if ($null -eq $ExchangeRegistry) { $null } else { [ordered]@{ DisplayVersion = $ExchangeRegistry.AdminDisplayVersion; ProductVersion = $ExchangeRegistry.MsiProductVersion; InstallPath = $ExchangeRegistry.MsiInstallPath } }
        ManagementCommands = $ExchangeCommands
        ManagementCommandProbe = $ExchangeCommandProbe
        Services         = @(Get-ServiceEvidence -Names @('MSExchangeADTopology', 'MSExchangeTransport', 'MSExchangeIS', 'MSExchangeFrontEndTransport'))
        ProtectedPaths   = @($ExchangePreview.ProtectedPaths)
        Preview          = $ExchangePreview
    }
    DeletionEnabled    = $false
    Note               = 'This probe never enables or performs IIS or Exchange deletion. Product absence leaves acceptance evidence unavailable.'
} | ConvertTo-Json -Depth 10
