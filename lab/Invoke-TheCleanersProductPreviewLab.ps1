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
        $Service = Get-Service -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        [ordered]@{
            Name   = $Name
            Exists = $null -ne $Service
            Status = if ($null -eq $Service) { 'NotInstalled' } else { [string]$Service.Status }
            StartType = if ($null -eq $Service) { $null } else { [string]$Service.StartType }
        }
    }
}

function Get-PreviewEvidence {
    param (
        [Parameter(Mandatory)]
        [string]
        $CommandName
    )

    try {
        $Results = @(& $CommandName -WhatIf -Confirm:$false -PassThru -ErrorAction Stop)
        $CandidatePaths = @($Results | ForEach-Object { $_.CandidatePaths } | Where-Object { $_ })
        [ordered]@{
            ResultStatus        = 'Completed'
            ErrorId             = $null
            ErrorMessage        = $null
            CandidatesBefore    = $CandidatePaths
            CandidateCountBefore = $CandidatePaths.Count
            CandidatesAfter     = $CandidatePaths
            CandidateCountAfter = $CandidatePaths.Count
            ProtectedPaths      = @($Results | ForEach-Object { $_.ProtectionPathCount })
            Results             = $Results
        }
    } catch {
        [ordered]@{
            ResultStatus        = 'Unavailable'
            ErrorId             = $_.FullyQualifiedErrorId
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

$IisRegistry = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\InetStp' -ErrorAction SilentlyContinue
$ExchangeRegistry = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup' -ErrorAction SilentlyContinue
$IisModule = Get-Module -ListAvailable -Name WebAdministration | Sort-Object Version -Descending | Select-Object -First 1
$ExchangeCommands = @(
    Get-Command -Name 'Get-ExchangeServer', 'Get-MailboxDatabase' -ErrorAction SilentlyContinue |
        Select-Object Name, CommandType, Version
)

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
        ProtectedPaths   = @()
        Preview         = Get-PreviewEvidence -CommandName 'Clear-OldIISLog'
    }
    Exchange           = [ordered]@{
        ProductDetected = $null -ne $ExchangeRegistry
        ProductBuild    = if ($null -eq $ExchangeRegistry) { $null } else { [ordered]@{ DisplayVersion = $ExchangeRegistry.AdminDisplayVersion; ProductVersion = $ExchangeRegistry.MsiProductVersion; InstallPath = $ExchangeRegistry.MsiInstallPath } }
        ManagementCommands = $ExchangeCommands
        Services         = @(Get-ServiceEvidence -Names @('MSExchangeADTopology', 'MSExchangeTransport', 'MSExchangeIS', 'MSExchangeFrontEndTransport'))
        ProtectedPaths   = @()
        Preview          = Get-PreviewEvidence -CommandName 'Clear-OldExchangeLog'
    }
    DeletionEnabled    = $false
    Note               = 'This probe never enables or performs IIS or Exchange deletion. Product absence leaves acceptance evidence unavailable.'
} | ConvertTo-Json -Depth 10
