function Get-TheCleanersWindowsTempRoot {
    <#
    .SYNOPSIS
        Resolve the actual Windows temporary directory.
    .DESCRIPTION
        Prefer the Windows special-folder API and use the machine SystemRoot only
        as a fallback. Callers still validate the resulting directory and reject
        broad or reparse-point roots.
    .OUTPUTS
        System.IO.DirectoryInfo
    #>
    [CmdletBinding()]
    [OutputType([System.IO.DirectoryInfo])]
    param ()

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw [System.PlatformNotSupportedException]::new('The Windows temporary root requires Windows.')
    }

    $SystemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    if ([string]::IsNullOrWhiteSpace($SystemRoot)) {
        $SystemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Machine')
    }
    if ([string]::IsNullOrWhiteSpace($SystemRoot)) {
        throw [System.InvalidOperationException]::new('The Windows directory could not be resolved from the operating system.')
    }

    Resolve-TheCleanersFileSystemPath -LiteralPath (Join-Path -Path $SystemRoot -ChildPath 'Temp')
}
