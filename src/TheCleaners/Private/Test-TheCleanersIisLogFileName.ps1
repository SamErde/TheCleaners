function Test-TheCleanersIisRolloverSuffix {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Suffix
    )

    switch ($Suffix.Length) {
        4 {
            return $Suffix -match '^\d{2}(0[1-9]|1[0-2])$'
        }
        6 {
            if ($Suffix -notmatch '^\d{6}$') {
                return $false
            }
        }
        8 {
            if ($Suffix -notmatch '^\d{8}$') {
                return $false
            }
        }
        default {
            return $false
        }
    }

    $Year = 2000 + [int]$Suffix.Substring(0, 2)
    $Month = [int]$Suffix.Substring(2, 2)
    $Day = [int]$Suffix.Substring(4, 2)
    if ($Month -lt 1 -or $Month -gt 12) {
        return $false
    }

    $DaysInMonth = [DateTime]::DaysInMonth($Year, $Month)
    if ($Day -lt 1 -or $Day -gt $DaysInMonth) {
        return $false
    }

    if ($Suffix.Length -eq 8) {
        $Hour = [int]$Suffix.Substring(6, 2)
        if ($Hour -lt 0 -or $Hour -gt 23) {
            return $false
        }
    }

    return $true
}

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
            if ($ServiceName -in @('FTPSVC', 'MSFTPSVC', 'W3SVC')) {
                # IIS uses the extendNN family for size rollover. Some site and
                # FTP deployments also append a bounded sequence to the
                # date-based name; keep both forms exact and format-scoped.
                $Pattern = '^{0}(?:ex(?<Suffix>\d{{4}}|\d{{6}}|\d{{8}})(?:_(?<Sequence>\d{{1,3}}))?|extend\d{{1,3}})\.log$' -f $W3cPrefix
                $Match = [regex]::Match($Name, $Pattern)
                if (-not $Match.Success) {
                    return $false
                }
                if ($Match.Groups['Suffix'].Success) {
                    return Test-TheCleanersIisRolloverSuffix -Suffix $Match.Groups['Suffix'].Value
                }
                return $true
            }
            return $false
        }
        'IIS' { return $Name -match '^inetsv(?:\d{2}|\d{4}|\d{6}|\d{8})\.log$' }
        'NCSA' { return $Name -match '^ncsa(?:\d{2}|\d{4}|\d{6}|\d{8})\.log$' }
        default { return $false }
    }
}
