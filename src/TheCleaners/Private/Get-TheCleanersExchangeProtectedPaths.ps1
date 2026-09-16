function Get-TheCleanersExchangeProtectedPaths {
    <#
    .SYNOPSIS
        Discover Exchange database and transaction-log paths for exclusion.
    .DESCRIPTION
        Query the installed Exchange management command when it is available. A
        missing management command is reported as Unknown rather than treated as
        proof that no protected paths exist. The preview can remain experimental,
        but a later removal gate must not proceed with Unknown protection status.
    .PARAMETER InstallRoot
        Validated Exchange installation root.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]
        $InstallRoot
    )

    try {
        $DatabaseCommand = Get-Command -Name 'Get-MailboxDatabase' -CommandType Cmdlet, Function -ErrorAction Stop | Select-Object -First 1
    } catch {
        $CommandIsAbsent = (
            $_.Exception -is [System.Management.Automation.CommandNotFoundException] -or
            $_.FullyQualifiedErrorId -match 'CommandNotFound'
        )
        if ($CommandIsAbsent) {
            $DatabaseCommand = $null
        } else {
            throw [System.InvalidOperationException]::new(
                "Unable to determine Exchange management command 'Get-MailboxDatabase': $($_.Exception.Message)",
                $_.Exception
            )
        }
    }
    if ($null -eq $DatabaseCommand) {
        return [pscustomobject]@{
            Paths  = @()
            Status = 'Unknown'
        }
    }

    $ProtectedPaths = [System.Collections.Generic.List[string]]::new()
    $MetadataIncomplete = $false
    $DatabaseCount = 0
    foreach ($Database in @(& $DatabaseCommand.Name -Status -ErrorAction Stop)) {
        $DatabaseCount++
        foreach ($PropertyName in @('EdbFilePath', 'LogFolderPath')) {
            $Value = $Database.$PropertyName
            if ($null -eq $Value) {
                $MetadataIncomplete = $true
                continue
            }
            $CandidatePath = if ($Value -is [string]) { $Value } elseif ($Value.PSObject.Properties['PathName']) { [string]$Value.PathName } else { [string]$Value }
            if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
                $MetadataIncomplete = $true
                continue
            }
            $ExpandedPath = [Environment]::ExpandEnvironmentVariables($CandidatePath)
            if (-not (Test-TheCleanersFullyQualifiedPath -Path $ExpandedPath)) {
                throw [System.IO.InvalidDataException]::new("Exchange returned a non-qualified protected path: '$CandidatePath'.")
            }
            $ProtectedPaths.Add((Convert-TheCleanersPathForComparison -Path $ExpandedPath))
        }
    }

    [pscustomobject]@{
        InstallRoot = $InstallRoot.FullName
        Paths       = @($ProtectedPaths | Sort-Object -Unique)
        Status      = if ($DatabaseCount -eq 0 -or $MetadataIncomplete -or $ProtectedPaths.Count -eq 0) { 'Unknown' } else { 'Validated' }
    }
}
