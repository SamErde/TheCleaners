function Clear-WindowsTemp {
    <#
    .SYNOPSIS
        A script to clean out old Windows Temp files.

    .DESCRIPTION
        This script will clean out Windows Temp files older than x days.

    .PARAMETER Days
        The number of days to keep temp files. The default is 60 days.

    .EXAMPLE
        Clear-WindowsTemp -Days 60

        Removes all Windows Temp files that are older than 60 days.

    .NOTES
        Author:     Sam Erde
                    https://twitter.com/SamErde
                    https://github.com/SamErde
        Modified:   2024-08-12

    .COMPONENT
        TheCleaners
    #>
    [CmdletBinding()]
    param (
        # How many days worth of temp files to retain (how far back to filter).
        [int16]
        $Days = 60
    )

    begin {
        $TempPath = Join-Path -Path $env:SystemRoot -ChildPath 'Temp'
        if (-not (Test-Path -Path $TempPath)) {
            return
        }
        $OldFiles = Get-ChildItem -Path $TempPath -Recurse | Where-Object {
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
        Write-Output "Removed $($OldFiles.Count) files older than $Days days from the system temp folder."
    }
}
