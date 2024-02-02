<#
.SYNOPSIS
    Clean out old Exchange Server logs

.DESCRIPTION
    WORK IN PROGRESS
#>
$Days = 60

$IISLogPath = "C:\inetpub\logs\LogFiles\"
$ExchangeInstallPath        = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup).MsiInstallPath
    $ExchangeLoggingPath    = $ExchangeInstallPath + "Logging\"
    $ETLLoggingPath         = $ExchangeInstallPath + "Bin\Search\Ceres\Diagnostics\ETLTraces\"
    $ETLLoggingPath2        = $ExchangeInstallPath + "\Bin\Search\Ceres\Diagnostics\Logs"
    $MessageTrackingLogs    = $ExchangeInstallPath + "\TransportRoles\Logs\MessageTracking\"

function CleanLogfiles ($TargetFolder) {
  Write-Host -Debug -ForegroundColor Yellow -BackgroundColor Cyan $TargetFolder

    if (Test-Path $TargetFolder) {
        $Now = Get-Date
        $LastWrite = $Now.AddDays(-$Days)
        $Files = Get-ChildItem -Path $ExchangeLoggingPath -Recurse | Where-Object { ($_.Name -like "*.log" -or $_.Name -like "*.blg" -or $_.Name -like "*.etl") -and ($_.lastWriteTime -le "$lastwrite") } | Select-Object FullName  
        foreach ($file in $Files) {
            Write-Host "Deleting file $($file.FullName)." -ForegroundColor "Yellow"
            Remove-Item $($file.FullName) -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "The folder $TargetFolder doesn't exist! Check the folder path!" -ForegroundColor "Red"
    }
}

CleanLogfiles($IISLogPath)
CleanLogfiles($ExchangeLoggingPath)
CleanLogfiles($ETLLoggingPath)
CleanLogfiles($ETLLoggingPath2)
