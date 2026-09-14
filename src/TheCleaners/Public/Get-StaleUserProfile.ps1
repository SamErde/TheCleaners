function Get-StaleUserProfile {
    <#
    .SYNOPSIS
        Return typed read-only information about stale Windows user profiles.
    .DESCRIPTION
        Query Win32_UserProfile and return one TheCleaners.StaleUserProfile object
        per eligible profile. Missing or invalid LastUseTime is unknown and is not
        classified as stale unless -IncludeUnknownLastUseTime is requested. The
        command never deletes profiles and never writes presentation output to the
        host. SID translation is best effort; an unresolved SID is retained in the
        object with an explicit resolution status. Optional size enumeration skips
        reparse points and reports unavailable sizes without changing profile state.
    .PARAMETER Days
        A profile is stale when its known last-use time is at or before this many
        days ago. The default is 90 days.
    .PARAMETER IncludeSize
        Recursively calculate logical file size for returned profiles. The legacy
        -ShowSummary name remains an alias for this read-only behavior.
    .PARAMETER IncludeUnknownLastUseTime
        Include otherwise eligible profiles whose LastUseTime is missing or invalid.
        They are returned with IsStale set to false and DateStatus set to Unknown.
    .EXAMPLE
        Get-StaleUserProfile -Days 90
    .EXAMPLE
        Get-StaleUserProfile -Days 90 -IncludeSize -IncludeUnknownLastUseTime
    .OUTPUTS
        TheCleaners.StaleUserProfile
    .LINK
        https://day3bits.com/thecleaners/Get-StaleUserProfile/
    #>
    [CmdletBinding()]
    [OutputType('TheCleaners.StaleUserProfile')]
    param (
        [Parameter(Position = 0)]
        [ValidateRange(1, [int16]::MaxValue)]
        [Int16]
        $Days = 90,

        [Parameter()]
        [Alias('ShowSummary')]
        [switch]
        $IncludeSize,

        [Parameter()]
        [switch]
        $IncludeUnknownLastUseTime
    )

    $IsWindowsHost = $PSVersionTable.PSEdition -eq 'Desktop' -or ($PSVersionTable.PSVersion.Major -ge 6 -and $IsWindows)
    if (-not $IsWindowsHost) {
        $Exception = [System.PlatformNotSupportedException]::new('Get-StaleUserProfile requires Windows because it queries Win32_UserProfile.')
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'ProfileWindowsRequired' -Category NotImplemented
        $PSCmdlet.WriteError($ErrorRecord)
        return
    }

    $NowUtc = (Get-Date).ToUniversalTime()
    $CutoffUtc = $NowUtc.AddDays(-$Days)
    $Profiles = $null
    try {
        $Profiles = @(Get-CimInstance -Class Win32_UserProfile -ErrorAction Stop)
    } catch {
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'ProfileQueryFailed' -Category ReadError
        $PSCmdlet.WriteError($ErrorRecord)
        return
    }

    $ServiceSids = @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')
    $ProtectedLeaves = @('Default', 'Default User', 'Public', 'All Users', 'systemprofile', 'LocalService', 'NetworkService')
    foreach ($ProfileRecord in $Profiles) {
        $LocalPath = [string]$ProfileRecord.LocalPath
        $Sid = [string]$ProfileRecord.SID
        $Leaf = if ([string]::IsNullOrWhiteSpace($LocalPath)) { '' } else { (Split-Path -Path $LocalPath.TrimEnd([char[]]@('\', '/')) -Leaf) }
        $IsService = $ServiceSids -contains $Sid.ToUpperInvariant() -or $Leaf -in @('systemprofile', 'LocalService', 'NetworkService')
        $IsDefault = $ProtectedLeaves -contains $Leaf
        $IsSystem = $ServiceSids -contains $Sid.ToUpperInvariant()
        if ($ProfileRecord.Special -or $ProfileRecord.Loaded -or $IsDefault -or $IsService) {
            continue
        }

        $LastUseTimeUtc = $null
        $DateStatus = 'Unknown'
        if ($null -ne $ProfileRecord.LastUseTime -and -not [string]::IsNullOrWhiteSpace([string]$ProfileRecord.LastUseTime)) {
            try {
                if ($ProfileRecord.LastUseTime -is [DateTime]) {
                    $LastUseTimeUtc = ([DateTime]$ProfileRecord.LastUseTime).ToUniversalTime()
                } else {
                    $LastUseTimeUtc = [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$ProfileRecord.LastUseTime).ToUniversalTime()
                }
                $DateStatus = 'Known'
            } catch {
                $DateStatus = 'Unknown'
            }
        }
        $IsStale = $null -ne $LastUseTimeUtc -and $LastUseTimeUtc -le $CutoffUtc
        if (-not $IsStale -and -not ($IncludeUnknownLastUseTime -and $DateStatus -eq 'Unknown')) {
            continue
        }

        $Account = $null
        $AccountResolutionStatus = 'Unresolved'
        try {
            if (-not [string]::IsNullOrWhiteSpace($Sid)) {
                $SidObject = [System.Security.Principal.SecurityIdentifier]::new($Sid)
                $Account = $SidObject.Translate([System.Security.Principal.NTAccount]).Value
                $AccountResolutionStatus = 'Resolved'
            }
        } catch {
            $AccountResolutionStatus = 'Unresolved'
        }

        $SizeBytes = $null
        $SizeStatus = 'NotRequested'
        if ($IncludeSize) {
            $SizeStatus = 'Unavailable'
            try {
                if (-not [string]::IsNullOrWhiteSpace($LocalPath) -and [System.IO.Directory]::Exists($LocalPath)) {
                    $SizeTotal = [Int64]0
                    $PendingDirectories = [System.Collections.Generic.Stack[string]]::new()
                    $PendingDirectories.Push($LocalPath)
                    while ($PendingDirectories.Count -gt 0) {
                        $DirectoryPath = $PendingDirectories.Pop()
                        foreach ($Item in @(Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction Stop)) {
                            if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                                continue
                            }
                            if ($Item.PSIsContainer) {
                                $PendingDirectories.Push($Item.FullName)
                            } else {
                                $SizeTotal += [Int64]$Item.Length
                            }
                        }
                    }
                    $SizeBytes = $SizeTotal
                    $SizeStatus = 'Available'
                }
            } catch {
                Write-Warning -Message ('ProfileSizeUnavailable: failed to measure profile ''{0}'': {1}' -f $LocalPath, $_.Exception.Message)
            }
        }

        [pscustomobject]@{
            PSTypeName              = 'TheCleaners.StaleUserProfile'
            ContractVersion         = '1.0'
            SID                     = $Sid
            Account                 = $Account
            AccountResolutionStatus = $AccountResolutionStatus
            LocalPath               = $LocalPath
            PathExists              = [System.IO.Directory]::Exists($LocalPath)
            LastUseTime             = if ($null -ne $LastUseTimeUtc) { $LastUseTimeUtc.ToLocalTime() } else { $null }
            LastUseTimeUtc          = $LastUseTimeUtc
            DateStatus              = $DateStatus
            AgeDays                 = if ($null -ne $LastUseTimeUtc) { [math]::Floor(($NowUtc - $LastUseTimeUtc).TotalDays) } else { $null }
            IsStale                 = [bool]$IsStale
            Loaded                  = [bool]$ProfileRecord.Loaded
            Special                 = [bool]$ProfileRecord.Special
            IsDefault               = [bool]$IsDefault
            IsSystem                = [bool]$IsSystem
            IsService               = [bool]$IsService
            SizeBytes               = $SizeBytes
            SizeStatus              = $SizeStatus
        }
    }
}
