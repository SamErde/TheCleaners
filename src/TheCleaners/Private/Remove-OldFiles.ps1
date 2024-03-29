function Remove-OldFiles {
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
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # The path containing files to remove
        [string]
        $Path,

        # How many days worth of logs to retain (how far back to filter)
        [int16]
        $Days = 60,

        # Use this switch to enable recursion and delete old files within subfolders
        [parameter()]
        [switch]
        $Recurse
    )

    begin {
        if (-not $Recurse) {
            $Recurse = $false
        }
    }

    process {
        Write-Verbose -Message "Finding and removing files older than $Days."
        Get-ChildItem -Path $Path -Recurse:$Recurse | Where-Object {
            $_.CreationTime -le ([datetime]::Now.AddDays( -$Days ))
        } | Remove-Item
    }

    end {

    }
}
