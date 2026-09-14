function Resolve-TheCleanersFileSystemPath {
    <#
    .SYNOPSIS
        Validate an existing filesystem root or a literal descendant without changing it.
    .DESCRIPTION
        Reject non-filesystem paths, broad cleanup roots, and reparse points anywhere in
        the current ancestry. With RootPath, require a strict descendant using a separator
        boundary, not a naive string-prefix check. Call again immediately before mutation.
        These path-based checks do not provide an atomic security boundary against hostile
        concurrent filesystem changes.
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

    if ([string]::IsNullOrWhiteSpace($LiteralPath) -or -not [System.IO.Path]::IsPathRooted($LiteralPath)) {
        throw 'An absolute, non-empty filesystem path is required.'
    }
    $Item = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    if ($Item -isnot [System.IO.FileSystemInfo]) {
        throw "Not a filesystem path: $LiteralPath"
    }
    $TrimCharacters = [char[]]@('\', '/')
    if ($PSBoundParameters.ContainsKey('RootPath')) {
        $Prefix = [System.IO.Path]::GetFullPath($RootPath).TrimEnd($TrimCharacters) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $Item.FullName.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
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
        foreach ($ForbiddenRoot in $ForbiddenRoots) {
            if (-not [string]::IsNullOrWhiteSpace($ForbiddenRoot) -and $Item.FullName.TrimEnd($TrimCharacters) -eq $ForbiddenRoot.TrimEnd($TrimCharacters)) {
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

