function Remove-OldFiles {
<#
    .SYNOPSIS
        Remove files in a path that are older than the specified number of days.

    .DESCRIPTION


    .NOTES

#>
    [CmdletBinding()]
    param (
        [parameter]
        $Path,

        [parameter]
        [int]$Days = 60,

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
        Get-ChildItem -Path $Path -Recurse:$Recurse | Where-Object {$_.CreationTime -le ([datetime]::Now.AddDays( -$Days ))} | Remove-Item
    }

    end {

    }
}
