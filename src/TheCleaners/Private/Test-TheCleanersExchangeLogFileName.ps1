function Test-TheCleanersExchangeLogFileName {
    <#
    .SYNOPSIS
        Test an Exchange preview filename against its directory allowlist.
    .DESCRIPTION
        Exchange has multiple product-owned log families. The preview accepts only
        the documented extensions and safe filename characters for the four known
        roots; mailbox message-tracking names receive a narrower prefix check.
        Database and transaction-log locations are filtered separately.
    .PARAMETER Name
        File name without a directory path.
    .PARAMETER RelativeRoot
        One of the fixed Exchange preview roots.
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

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $RelativeRoot
    )

    switch ($RelativeRoot) {
        'TransportRoles/Logs/MessageTracking' {
            return $Name -match '^MSGTRK(?:MS|MD|MA)?\d{8}-\d+\.log$'
        }
        'Bin/Search/Ceres/Diagnostics/ETLTraces' {
            return $Name -match '^[A-Za-z][A-Za-z0-9_.-]{0,127}\.etl$'
        }
        'Logging' { return $Name -match '^[A-Za-z][A-Za-z0-9_.-]{0,127}\.log$' }
        'Bin/Search/Ceres/Diagnostics/Logs' { return $Name -match '^[A-Za-z][A-Za-z0-9_.-]{0,127}\.log$' }
        default { return $false }
    }
}
