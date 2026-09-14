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

    $WindowsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    if ([string]::IsNullOrWhiteSpace($WindowsRoot)) {
        return $false
    }
    $ComparablePath = Convert-TheCleanersPathForComparison -Path $Path
    foreach ($ProtectedPath in @(
            (Join-Path -Path $WindowsRoot -ChildPath 'System32/inetsrv/config')
            (Join-Path -Path $WindowsRoot -ChildPath 'System32/inetsrv/history')
            (Join-Path -Path $WindowsRoot -ChildPath 'System32/inetsrv')
        )) {
        $ComparableProtectedPath = Convert-TheCleanersPathForComparison -Path $ProtectedPath
        if ($ComparablePath -eq $ComparableProtectedPath -or $ComparablePath.StartsWith($ComparableProtectedPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    $false
}
