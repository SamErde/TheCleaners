<#
.SYNOPSIS
    Remove files in a path that are older than the specified number of days.

.DESCRIPTION
    Remove files in a path that are older than the specified number of days. This function is used by other functions within the module when removing old files.

.EXAMPLE
    Remove-OldFiles -Path "C:\Windows\Temp" -Days 60 -Recurse

    Removes all files older than 60 does in C:\Windows\Temp with recursion to clean subfolders.

.NOTES
    Author: Sam Erde
            https://twitter.com/SamErde
            https://github.com/SamErde
#>
function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('Remove-OldFiles')]
    param (
        # The path containing files to remove
        [string]
        $Path,

        # How many days worth of logs to retain (how far back to filter)
        [int16]
        $Days = 60
    )

    begin {

    }

    process {
        Write-Verbose -Message "Finding and removing files older than $Days."
        Get-ChildItem -Path $Path -Recurse | Where-Object {
            $_.CreationTime -le ([datetime]::Now.AddDays( -$Days ))
        } | Remove-Item
    }

    end {

    }
}
