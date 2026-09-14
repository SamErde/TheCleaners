function Get-TheCleanersErrorRecord {
    <#
    .SYNOPSIS
        Create a stable TheCleaners error record.
    .DESCRIPTION
        Keep error identifiers and categories consistent without replacing the
        underlying exception. Public commands use this function at their error
        boundaries so callers can automate against stable IDs.
    .PARAMETER Exception
        The exception that caused the error.
    .PARAMETER ErrorId
        Stable TheCleaners error identifier.
    .PARAMETER Category
        PowerShell error category.
    .PARAMETER TargetObject
        Optional object associated with the failure.
    .OUTPUTS
        System.Management.Automation.ErrorRecord
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param (
        [Parameter(Mandatory)]
        [System.Exception]
        $Exception,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ErrorId,

        [Parameter()]
        [System.Management.Automation.ErrorCategory]
        $Category = [System.Management.Automation.ErrorCategory]::NotSpecified,

        [Parameter()]
        $TargetObject
    )

    [System.Management.Automation.ErrorRecord]::new($Exception, $ErrorId, $Category, $TargetObject)
}

function Get-TheCleanersCleanupResult {
    <#
    .SYNOPSIS
        Create the shared cleanup result contract.
    .DESCRIPTION
        Return the same fields for temp cleanup and preview commands. Candidate
        counts describe discovery; removal and byte fields describe successful
        mutations only. BytesReclaimed is logical file length, not measured free
        space.
    .PARAMETER Command
        Public command name.
    .PARAMETER RootPath
        Validated root represented by the result.
    .PARAMETER CutoffUtc
        Inclusive UTC retention cutoff.
    .PARAMETER DiscoveryStatus
        Validated, Experimental, or Failed discovery state.
    .PARAMETER Status
        Current operation status.
    .PARAMETER CandidatePaths
        Discovered file paths. Directory candidates are represented by their count.
    .OUTPUTS
        TheCleaners.CleanupResult
    #>
    [CmdletBinding()]
    [OutputType('TheCleaners.CleanupResult')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Command,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $RootPath,

        [Parameter(Mandatory)]
        [DateTime]
        $CutoffUtc,

        [Parameter()]
        [ValidateSet('Validated', 'Experimental', 'Failed')]
        [string]
        $DiscoveryStatus = 'Validated',

        [Parameter()]
        [ValidateSet('NotApplicable', 'Unknown', 'Protected', 'Validated')]
        [string]
        $ProtectionStatus = 'NotApplicable',

        [Parameter()]
        [ValidateSet('NotApplicable', 'Elevated', 'NotElevated', 'Unsupported', 'Unknown')]
        [string]
        $PrivilegeStatus = 'NotApplicable',

        [Parameter()]
        [string]
        $DiscoverySource,

        [Parameter()]
        [string]
        $DisplayName,

        [Parameter()]
        [string]
        $ProductVersion,

        [Parameter()]
        [int]
        $ProtectionPathCount = 0,

        [Parameter()]
        [string[]]
        $CandidatePaths = @(),

        [Parameter()]
        [ValidateSet('NoCandidates', 'WhatIf', 'Declined', 'Completed', 'CompletedWithSkips', 'PartialFailure', 'DiscoveryFailed')]
        [string]
        $Status = 'NoCandidates'
    )

    [pscustomobject]@{
        PSTypeName              = 'TheCleaners.CleanupResult'
        ContractVersion         = '1.0'
        Command                 = $Command
        RootPath                = $RootPath
        CutoffUtc               = $CutoffUtc.ToUniversalTime()
        DiscoveryStatus         = $DiscoveryStatus
        DiscoverySource         = $DiscoverySource
        DisplayName             = $DisplayName
        ProtectionStatus        = $ProtectionStatus
        ProtectionPathCount     = $ProtectionPathCount
        PrivilegeStatus         = $PrivilegeStatus
        ProductVersion          = $ProductVersion
        CandidatePaths          = @($CandidatePaths)
        FileCandidateCount      = 0
        FilesRemoved            = 0
        FileFailureCount        = 0
        FilesSkipped            = 0
        DirectoryCandidateCount = 0
        DirectoriesRemoved      = 0
        DirectoryFailureCount   = 0
        DirectoriesSkipped      = 0
        BytesReclaimed          = [Int64]0
        DiscoveryErrorCount     = 0
        ErrorIds                = @()
        Status                  = $Status
    }
}

function Get-TheCleanersPrivilegeStatus {
    <#
    .SYNOPSIS
        Report whether the current Windows process is elevated.
    .DESCRIPTION
        This is an informational preflight. It does not grant rights or make a
        non-elevated run destructive; individual deletion errors remain explicit.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        return 'Unsupported'
    }

    try {
        $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $Principal = [System.Security.Principal.WindowsPrincipal]::new($Identity)
        if ($Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            'Elevated'
        } else {
            'NotElevated'
        }
    } catch {
        'Unknown'
    }
}
