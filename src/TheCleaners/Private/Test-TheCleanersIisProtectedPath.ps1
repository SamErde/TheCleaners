function Get-TheCleanersIisProtectedPaths {
    <#
    .SYNOPSIS
        Return the IIS paths excluded from log-root discovery.
    .DESCRIPTION
        Keep the protected-path inventory in one place so the validation result
        and preview-lab evidence describe the same paths.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param ()

    $WindowsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    if ([string]::IsNullOrWhiteSpace($WindowsRoot)) {
        return @()
    }

    foreach ($ProtectedPath in @(
            (Join-Path -Path $WindowsRoot -ChildPath 'System32/inetsrv/config')
            (Join-Path -Path $WindowsRoot -ChildPath 'System32/inetsrv/history')
            (Join-Path -Path $WindowsRoot -ChildPath 'System32/inetsrv')
        )) {
        Convert-TheCleanersPathForComparison -Path $ProtectedPath
    }
}

function Test-TheCleanersIisProtectedPath {
    <#
    .SYNOPSIS
        Test whether an IIS root overlaps a protected configuration location.
    .DESCRIPTION
        IIS configuration, history, and executable directories are not log roots.
        Reject them before traversal even when a registry or site definition points
        at them. This validation is intentionally conservative and does not enable
        removal; it is a prerequisite for a later validated implementation.
    .PARAMETER Path
        Existing normalized IIS root.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
    )

    $ProtectedPaths = @(Get-TheCleanersIisProtectedPaths)
    if ($ProtectedPaths.Count -eq 0) {
        return $false
    }
    $ComparablePath = Convert-TheCleanersPathForComparison -Path $Path
    foreach ($ComparableProtectedPath in $ProtectedPaths) {
        $PathContainsProtectedLocation = (
            $ComparablePath -eq $ComparableProtectedPath -or
            $ComparablePath.StartsWith($ComparableProtectedPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
        )
        $ProtectedLocationContainsPath = $ComparableProtectedPath.StartsWith($ComparablePath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
        if ($PathContainsProtectedLocation -or $ProtectedLocationContainsPath) {
            return $true
        }
    }
    $false
}
