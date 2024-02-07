function Remove-ExchangeLogs {
    <#
        .SYNOPSIS
            Clean out old Exchange Server logs

        .DESCRIPTION
            Remove any Exchange logs that are older than a specified date.

        .EXAMPLE
            Remove-ExchangeLogs
    #>
    [CmdletBinding(SupportsShouldProcess)]

    $Days = 60

    $IISLogPath             = "C:\inetpub\logs\LogFiles\"
    $ExchangeInstallPath    = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup).MsiInstallPath
    $ExchangeLoggingPath    = $ExchangeInstallPath + "Logging\"
    $ETLLoggingPath         = $ExchangeInstallPath + "Bin\Search\Ceres\Diagnostics\ETLTraces\"
    $ETLLoggingPath2        = $ExchangeInstallPath + "\Bin\Search\Ceres\Diagnostics\Logs"
    $MessageTrackingLogs    = $ExchangeInstallPath + "\TransportRoles\Logs\MessageTracking\"

    Test-Path $IISLogPath
    Test-Path $ExchangeInstallPath
    Test-Path $ExchangeLoggingPath
    Test-Path $ETLLoggingPath
    Test-Path $ETLLoggingPath2
    Test-Path $MessageTrackingLogs

    Write-Information -MessageData $TargetFolder -InformationAction Continue

    if (Test-Path $TargetFolder) {
        $Now = Get-Date
        $LastWrite = $Now.AddDays(-$Days)
        $Files = Get-ChildItem -Path $ExchangeLoggingPath -Recurse | Where-Object { ($_.Name -like "*.log" -or $_.Name -like "*.blg" -or $_.Name -like "*.etl") -and ($_.lastWriteTime -le "$lastwrite") } | Select-Object FullName
        foreach ($file in $Files) {
            Write-Information "Deleting file $($file.FullName)." -InformationAction Continue
            # Call the Remove-OldFile function
            # Remove-Item $($file.FullName) -ErrorAction SilentlyContinue
        }
    } else {
        Write-Warning -WarningAction Continue "The folder $TargetFolder doesn't exist! Check the folder path!"
    }
}
