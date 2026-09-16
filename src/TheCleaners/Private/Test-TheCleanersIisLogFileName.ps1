function Test-TheCleanersIisLogFileName {
    <#
    .SYNOPSIS
        Test an IIS log filename against the configured format allowlist.
    .DESCRIPTION
        IIS custom logging formats are not safe to infer from an extension alone.
        Only the documented rollover names for the known built-in formats are
        accepted; custom formats are excluded until a product-specific lab gate
        validates their schema.
    .PARAMETER Name
        File name without a directory path.
    .PARAMETER Format
        IIS logging format name or numeric value.
    .PARAMETER Service
        IIS service family represented by the root.
    .PARAMETER LocalTimeRollover
        Use the local-time W3C rollover name instead of the UTC-prefixed name.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [Parameter()]
        [string]
        $Format = 'W3C',

        [Parameter()]
        [string]
        $Service = 'W3SVC',

        [Parameter()]
        [switch]
        $LocalTimeRollover
    )

    $NormalizedFormat = switch ($Format.ToString().ToUpperInvariant()) {
        '0' { 'IIS'; break }
        'IIS' { 'IIS'; break }
        '1' { 'NCSA'; break }
        'NCSA' { 'NCSA'; break }
        '2' { 'W3C'; break }
        'W3C' { 'W3C'; break }
        '3' { 'Custom'; break }
        default { 'Custom' }
    }
    $ServiceName = $Service.ToUpperInvariant()
    switch ($NormalizedFormat) {
        'W3C' {
            $W3cPrefix = if ($LocalTimeRollover) { '' } else { 'u_' }
            if ($ServiceName -in @('FTPSVC', 'MSFTPSVC')) {
                return $Name -match ('^{0}ex\d{{6}}\.log$' -f $W3cPrefix)
            }
            if ($ServiceName -eq 'W3SVC') {
                return $Name -match ('^{0}ex\d{{6}}\.log$' -f $W3cPrefix)
            }
            return $false
        }
        'IIS' { return $Name -match '^in(?:etsv\d{2}|\d{4}|\d{6}|\d{8})\.log$' }
        'NCSA' { return $Name -match '^nc(?:sa\d{2}|\d{4}|\d{6}|\d{8})\.log$' }
        default { return $false }
    }
}
