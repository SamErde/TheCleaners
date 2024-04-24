# Clear the temp folders from all local user profiles
function Clear-UserTemp {
    [CmdletBinding()]
    param (
        # How many days worth of temp files to retain (how far back to filter).
        [int16]
        $Days = 60
    )

    begin {
        $UserTempPath = Join-Path -Path $env:SystemDrive -ChildPath 'Users'
        if (-not (Test-Path -Path $UserTempPath)) {
            return
        }
        $OldFiles = Get-ChildItem -Path $UserTempPath -Recurse | Where-Object {
            $_.LastWriteTime -le ( (Get-Date).AddDays(-$Days) )
        }

        if ($OldFiles.Count -eq 0) {
            Write-Output "No files found older than $Days days."
            return
        }
    }

    process {
        Remove-OldFiles -Files $OldFiles
    }

    end {
        Write-Output "Removed $($OldFiles.Count) files older than $Days days from the user temp folders."
    }
}
