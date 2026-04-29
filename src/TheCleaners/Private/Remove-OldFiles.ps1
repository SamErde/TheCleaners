<#
.SYNOPSIS
    Remove files in a path that are older than the specified number of days.

.DESCRIPTION
    Remove files in a path that are older than the specified number of days. This function is used by other functions within the module when removing old files.

.EXAMPLE
    Remove-OldFiles -Path "C:\Windows\Temp" -Days 60 -Recurse

    Removes all files older than 60 does in C:\Windows\Temp with recursion to clean subfolders.
#>
function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param (
        # The path containing files to remove
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]
        $Path,

        # How many days worth of logs to retain (how far back to filter)
        [Parameter()]
        [ValidateRange(1, [int16]::MaxValue)]
        [int16]
        $Days = 60
    )

    begin {

    }

    process {
        Write-Verbose -Message "Finding and removing files older than $Days."
        $OldFiles = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction Stop | Where-Object {
            $_.LastWriteTime -le ([datetime]::Now.AddDays(-$Days))
        }

        foreach ($File in $OldFiles) {
            if ($PSCmdlet.ShouldProcess($File.FullName, 'Remove old file')) {
                Remove-Item -LiteralPath $File.FullName -ErrorAction Stop
            }
        }
    }

    end {

    }
}
