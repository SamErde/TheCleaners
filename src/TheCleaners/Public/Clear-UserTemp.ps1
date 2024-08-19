function Clear-UserTemp {
    <#
    .SYNOPSIS
        Clean old temp files from user profiles.

    .DESCRIPTION
        Remove temp files older than 60 days from users' local temp folder.

    .PARAMETER Days
        How many days worth of temp files to keep. This can help avoid getting errors when trying to delete temp files that are still in use.

    .EXAMPLE
        Clear-UserTemp -Days 30

    .NOTES
        Author:     Sam Erde
        https://twitter.com/SamErde
        https://github.com/SamErde
        Modified:   2024-08-12

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding()]
    #[Alias('Clean-UserTemp')]
    param (
        # How many days worth of temp files to retain (how far back to filter).
        [int16]
        $Days = 60
    )

    begin {
        $UserTempPath = Join-Path -Path $env:TEMP
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
