function Test-TheCleanersFullyQualifiedPath {
    <#
    .SYNOPSIS
        Test whether a value uses a fully qualified Windows filesystem path syntax.
    .DESCRIPTION
        Accept standard and extended-length drive-qualified paths and UNC paths with
        both server and share components. Reject drive-relative, root-relative,
        provider-qualified, and device paths before filesystem resolution.
    .PARAMETER Path
        Path syntax to test without resolving it.
    .OUTPUTS
        System.Boolean
    #>
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $Comparison = [System.StringComparison]::OrdinalIgnoreCase
    $NormalizedPath = $Path.Replace('/', '\')
    if ($NormalizedPath.StartsWith('\\.\', $Comparison)) {
        return $false
    }

    if ($NormalizedPath.StartsWith('\\?\', $Comparison)) {
        if ($NormalizedPath -match '^\\\\\?\\[A-Za-z]:[\\/]') {
            return $true
        }
        if ($NormalizedPath -match '^\\\\\?\\UNC\\[^\\/]+\\[^\\/]') {
            return $true
        }
        return $false
    }

    if ($NormalizedPath.StartsWith('\\')) {
        $Segments = $NormalizedPath -split '\\'
        if ($Segments.Count -lt 4 -or
            [string]::IsNullOrWhiteSpace($Segments[2]) -or
            [string]::IsNullOrWhiteSpace($Segments[3])) {
            return $false
        }
        return $true
    }

    if ($NormalizedPath -match '^[A-Za-z]:[\\/]') {
        return $true
    }

    $false
}

function Convert-TheCleanersPathForComparison {
    <#
    .SYNOPSIS
        Normalize supported filesystem syntax for safe path comparisons.
    .DESCRIPTION
        Remove only the extended-length namespace prefix. The filesystem identity
        checks remain responsible for object identity; this helper is only for
        separator-boundary and broad-root comparisons.
    .PARAMETER Path
        Fully qualified filesystem path.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
    )

    $ComparablePath = $Path.Replace('/', '\')
    $IsExtendedLength = $ComparablePath.StartsWith('\\?\', [System.StringComparison]::OrdinalIgnoreCase)
    if ($IsExtendedLength) {
        if ($ComparablePath.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $ComparablePath = '\\' + $ComparablePath.Substring(8)
        } else {
            $ComparablePath = $ComparablePath.Substring(4)
        }

        # Windows PowerShell 5.1 can reject a long path after the namespace
        # prefix has been removed. Normalize the already-qualified string without
        # asking the legacy Path implementation to enforce MAX_PATH.
        $PathRoot = [System.IO.Path]::GetPathRoot($ComparablePath)
        if ([string]::IsNullOrWhiteSpace($PathRoot)) {
            throw "The extended-length path has no usable root: '$Path'."
        }
        $Remainder = $ComparablePath.Substring($PathRoot.Length)
        $Segments = [System.Collections.Generic.List[string]]::new()
        foreach ($Segment in @($Remainder -split '\\')) {
            if ([string]::IsNullOrEmpty($Segment) -or $Segment -eq '.') {
                continue
            }
            if ($Segment -eq '..') {
                if ($Segments.Count -gt 0) {
                    $Segments.RemoveAt($Segments.Count - 1)
                }
                continue
            }
            $Segments.Add($Segment)
        }
        return ($PathRoot.TrimEnd([char[]]@('\', '/')) + '\' + ($Segments -join '\')).TrimEnd([char[]]@('\', '/'))
    }

    [System.IO.Path]::GetFullPath($ComparablePath).TrimEnd([char[]]@('\', '/'))
}

function Resolve-TheCleanersFileSystemPath {
    <#
    .SYNOPSIS
        Validate an existing filesystem root or a literal descendant without changing it.
    .DESCRIPTION
        Require fully qualified Windows filesystem paths, reject broad cleanup roots, and
        reject reparse points anywhere in the current ancestry. With RootPath, require a
        strict descendant using a separator boundary, not a naive string-prefix check.
        Call again immediately before mutation. Extended-length drive and UNC forms are
        accepted when the Windows filesystem provider and long-path policy support them;
        device namespace paths remain rejected. These path-based checks do not provide
        an atomic security boundary against hostile concurrent filesystem changes.
    .PARAMETER LiteralPath
        Existing literal filesystem path to validate.
    .PARAMETER RootPath
        Previously validated cleanup root; LiteralPath must be strictly beneath it.
    .EXAMPLE
        Resolve-TheCleanersFileSystemPath -LiteralPath $env:TEMP
    .OUTPUTS
        System.IO.FileSystemInfo
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileSystemInfo])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $LiteralPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $RootPath
    )

    if (-not (Test-TheCleanersFullyQualifiedPath -Path $LiteralPath)) {
        throw 'A fully qualified Windows filesystem path is required.'
    }
    if ($PSBoundParameters.ContainsKey('RootPath') -and -not (Test-TheCleanersFullyQualifiedPath -Path $RootPath)) {
        throw 'A fully qualified Windows filesystem RootPath is required.'
    }
    $Item = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    if ($Item -isnot [System.IO.FileSystemInfo]) {
        throw "Not a filesystem path: $LiteralPath"
    }
    if ($PSBoundParameters.ContainsKey('RootPath')) {
        $Prefix = (Convert-TheCleanersPathForComparison -Path $RootPath) + [System.IO.Path]::DirectorySeparatorChar
        $ComparableItemPath = Convert-TheCleanersPathForComparison -Path $Item.FullName
        if (-not $ComparableItemPath.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Path is not a strict descendant of the approved root: $LiteralPath"
        }
    } else {
        if ($Item -isnot [System.IO.DirectoryInfo]) {
            throw "Cleanup root is not a directory: $LiteralPath"
        }
        $ForbiddenRoots = @(
            [System.IO.Path]::GetPathRoot($Item.FullName)
            $env:SystemRoot
            $env:USERPROFILE
            $env:ProgramFiles
            $env:ProgramData
        )
        $ComparableItemPath = Convert-TheCleanersPathForComparison -Path $Item.FullName
        foreach ($ForbiddenRoot in $ForbiddenRoots) {
            if (-not [string]::IsNullOrWhiteSpace($ForbiddenRoot) -and $ComparableItemPath -eq (Convert-TheCleanersPathForComparison -Path $ForbiddenRoot)) {
                throw "Refusing a broad cleanup root: $LiteralPath"
            }
        }
    }
    $Current = $Item
    while ($null -ne $Current) {
        $Current.Refresh()
        if (-not $Current.Exists -or ($Current.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw "Missing path or reparse point in cleanup ancestry: $($Current.FullName)"
        }
        if ($Current -is [System.IO.DirectoryInfo]) {
            $Current = $Current.Parent
        } else {
            $Current = $Current.Directory
        }
    }
    $Item
}

