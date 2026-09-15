function Get-StaleUserProfile {
    <#
    .SYNOPSIS
        Return typed read-only information about stale Windows user profiles.
    .DESCRIPTION
        Query Win32_UserProfile and return one TheCleaners.StaleUserProfile object
        per eligible profile. Missing or invalid LastUseTime is unknown and is not
        classified as stale unless -IncludeUnknownLastUseTime is requested. The
        command never deletes profiles and never writes presentation output to the
        host. Built-in, virtual service, and IIS application-pool SID families are
        excluded. SID translation is best effort; an unresolved SID is retained in
        the object with an explicit resolution status. Optional size enumeration
        skips reparse points throughout the profile path ancestry and reports
        unavailable sizes without changing profile state. Identity-checked native
        handles are held from the filesystem root through the profile and for
        every queued directory until traversal completes. Stable no-delete-sharing
        handles are used where the current token permits them; protected ancestors
        retain an identity handle and are revalidated before a size is reported.
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
        $IsServiceSid = $Sid.ToUpperInvariant() -match '^S-1-5-(80|82)(-\d+)+$'
        $IsService = $ServiceSids -contains $Sid.ToUpperInvariant() -or $IsServiceSid -or $Leaf -in @('systemprofile', 'LocalService', 'NetworkService')
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
            $HeldDirectoryHandles = [System.Collections.Generic.List[object]]::new()
            $HeldDirectoryHandleByPath = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            try {
                if (-not [string]::IsNullOrWhiteSpace($LocalPath)) {
                    $ProfileDirectory = Get-Item -LiteralPath $LocalPath -Force -ErrorAction Stop
                    if ($ProfileDirectory -isnot [System.IO.DirectoryInfo]) {
                        throw [System.IO.InvalidDataException]::new("The profile path is not a directory: '$LocalPath'.")
                    }
                    $ProfilePath = [System.IO.Path]::GetFullPath($LocalPath)
                    $AncestorPaths = [System.Collections.Generic.List[string]]::new()
                    while (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
                        $ProfilePathItem = Get-Item -LiteralPath $ProfilePath -Force -ErrorAction Stop
                        if ($ProfilePathItem -isnot [System.IO.DirectoryInfo]) {
                            throw [System.IO.InvalidDataException]::new("The profile path or an ancestor is not a directory and cannot be sized: '$LocalPath'.")
                        }
                        if ($ProfilePathItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                            throw [System.IO.InvalidDataException]::new("The profile path or an ancestor is a reparse point and cannot be sized: '$LocalPath'.")
                        }
                        $AncestorPaths.Add($ProfilePathItem.FullName)
                        $ParentPath = [System.IO.Path]::GetDirectoryName($ProfilePath)
                        if ([string]::IsNullOrWhiteSpace($ParentPath) -or $ParentPath -eq $ProfilePath) {
                            break
                        }
                        $ProfilePath = $ParentPath
                    }
                    $AncestorPaths.Reverse()
                    Initialize-TheCleanersNativeFileInterop
                    foreach ($AncestorPath in $AncestorPaths) {
                        $AncestorHandle = $null
                        try {
                            $AncestorHandle = [TheCleaners.NativeFileInterop]::OpenForStableEnumeration($AncestorPath)
                        } catch {
                            $AncestorHandle = [TheCleaners.NativeFileInterop]::OpenForIdentityInspection($AncestorPath)
                        }
                        $AncestorEntry = [pscustomobject]@{
                            Path     = $AncestorPath
                            Handle   = $AncestorHandle
                            Identity = $null
                        }
                        $HeldDirectoryHandles.Add($AncestorEntry)
                        $HeldDirectoryHandleByPath[$AncestorPath] = $AncestorEntry
                        $AncestorIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($AncestorHandle)
                        $AncestorEntry.Identity = $AncestorIdentity
                        if (-not $AncestorIdentity.IsDirectory -or $AncestorIdentity.IsReparsePoint) {
                            throw [System.IO.InvalidDataException]::new("The profile path or an ancestor changed before sizing: '$AncestorPath'.")
                        }
                    }
                    $SizeTotal = [Int64]0
                    $PendingDirectories = [System.Collections.Generic.Stack[string]]::new()
                    $PendingDirectories.Push($ProfileDirectory.FullName)
                    while ($PendingDirectories.Count -gt 0) {
                        $DirectoryPath = $PendingDirectories.Pop()
                        Initialize-TheCleanersNativeFileInterop
                        $DirectoryEntry = $null
                        if (-not $HeldDirectoryHandleByPath.TryGetValue($DirectoryPath, [ref]$DirectoryEntry)) {
                            $DirectoryHandle = [TheCleaners.NativeFileInterop]::OpenForStableEnumeration($DirectoryPath)
                            $DirectoryEntry = [pscustomobject]@{
                                Path     = $DirectoryPath
                                Handle   = $DirectoryHandle
                                Identity = $null
                            }
                            $HeldDirectoryHandles.Add($DirectoryEntry)
                            $HeldDirectoryHandleByPath[$DirectoryPath] = $DirectoryEntry
                        }
                        $DirectoryIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($DirectoryEntry.Handle)
                        $DirectoryEntry.Identity = $DirectoryIdentity
                        if (-not $DirectoryIdentity.IsDirectory) {
                            throw [System.IO.InvalidDataException]::new("The profile traversal path is not a directory: '$DirectoryPath'.")
                        }
                        if ($DirectoryIdentity.IsReparsePoint) {
                            throw [System.IO.InvalidDataException]::new("The profile traversal path became a reparse point and cannot be sized: '$DirectoryPath'.")
                        }
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
                        $CurrentDirectoryIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($DirectoryEntry.Handle)
                        if (-not $DirectoryIdentity.Equals($CurrentDirectoryIdentity) -or $CurrentDirectoryIdentity.IsReparsePoint) {
                            throw [System.IO.InvalidDataException]::new("The profile traversal path changed while it was being sized: '$DirectoryPath'.")
                        }
                    }
                    foreach ($AncestorEntry in $HeldDirectoryHandles) {
                        $CurrentAncestorHandle = [TheCleaners.NativeFileInterop]::OpenForIdentityInspection($AncestorEntry.Path)
                        try {
                            $CurrentAncestorIdentity = [TheCleaners.NativeFileInterop]::ReadIdentity($CurrentAncestorHandle)
                            if (-not $CurrentAncestorIdentity.IsDirectory -or $CurrentAncestorIdentity.IsReparsePoint -or -not $AncestorEntry.Identity.Equals($CurrentAncestorIdentity)) {
                                throw [System.IO.InvalidDataException]::new("The profile path or an ancestor changed while it was being sized: '$($AncestorEntry.Path)'.")
                            }
                        } finally {
                            $CurrentAncestorHandle.Dispose()
                        }
                    }
                    $SizeBytes = $SizeTotal
                    $SizeStatus = 'Available'
                }
            } catch {
                $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'ProfileSizeUnavailable' -Category ReadError -TargetObject $LocalPath
                $PSCmdlet.WriteError($ErrorRecord)
            } finally {
                foreach ($HeldDirectoryEntry in $HeldDirectoryHandles) {
                    if ($null -ne $HeldDirectoryEntry.Handle) {
                        $HeldDirectoryEntry.Handle.Dispose()
                    }
                }
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
