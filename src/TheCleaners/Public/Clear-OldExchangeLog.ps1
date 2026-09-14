function Clear-OldExchangeLog {
    <#
    .SYNOPSIS
        Preview old Exchange Server log candidates without removing anything.
    .DESCRIPTION
        This command is structurally preview-only: it has no deletion implementation and
        never invokes IIS cleanup. Explicit -WhatIf is required, even when a caller has
        set WhatIfPreference. Discovery remains experimental and is not a validated list
        of files safe to delete. The initial preview retains the existing .log-only scope.
        Product-specific patterns and acceptance testing are tracked in the 1.0 plan.
    .PARAMETER Days
        Preview files whose LastWriteTimeUtc is at or before one UTC cutoff, Days days ago.
        The default is 60 days.
    .PARAMETER PassThru
        Return a TheCleaners.CleanupResult preview summary for each existing log root.
        CandidatePaths contains the discovered file names. Nothing is removed.
    .EXAMPLE
        Clear-OldExchangeLog -Days 60 -WhatIf
    .EXAMPLE
        Clear-OldExchangeLog -Days 30 -WhatIf -PassThru
    .OUTPUTS
        TheCleaners.CleanupResult
    .LINK
        https://day3bits.com/thecleaners/Clear-OldExchangeLog/
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [Alias('Clean-ExchangeLog')]
    [OutputType('TheCleaners.CleanupResult')]
    param (
        [Parameter()]
        [ValidateRange(1, [Int16]::MaxValue)]
        [Int16]
        $Days = 60,

        [Parameter()]
        [switch]
        $PassThru
    )

    # Reject before registry access or discovery. Do not implement an unlock or a preference override.
    if (-not $PSBoundParameters.ContainsKey('WhatIf') -or -not $PSBoundParameters['WhatIf']) {
        $Exception = [System.NotSupportedException]::new('Exchange cleanup is preview-only. Run Clear-OldExchangeLog -WhatIf. Removal is not available in this version.')
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new($Exception, 'ExchangeCleanupPreviewOnly', [System.Management.Automation.ErrorCategory]::NotImplemented, $null)
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw [System.PlatformNotSupportedException]::new('Exchange log discovery requires Windows.')
    }
    Write-Warning -Message 'Exchange preview only: no files will be removed. Candidate discovery is experimental, not a deletion allowlist.'

    $Setup = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup' -Name MsiInstallPath -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Setup.MsiInstallPath)) {
        throw 'The Exchange Server installation path is missing.'
    }
    $InstallRoot = Resolve-TheCleanersFileSystemPath -LiteralPath $Setup.MsiInstallPath
    $CutoffUtc = (Get-Date).ToUniversalTime().AddDays(-$Days)
    $RelativeRoots = @(
        'Logging'
        'Bin/Search/Ceres/Diagnostics/ETLTraces'
        'Bin/Search/Ceres/Diagnostics/Logs'
        'TransportRoles/Logs/MessageTracking'
    )
    foreach ($RelativeRoot in $RelativeRoots) {
        $RootPath = Join-Path -Path $InstallRoot.FullName -ChildPath $RelativeRoot
        if (-not (Test-Path -LiteralPath $RootPath)) {
            Write-Verbose -Message "Log root not present: $RootPath"
            continue
        }
        $OldFiles = @()
        try {
            $LogRoot = Resolve-TheCleanersFileSystemPath -LiteralPath $RootPath -RootPath $InstallRoot.FullName
            $Pending = [System.Collections.Generic.Stack[string]]::new()
            $Pending.Push($LogRoot.FullName)
            $Candidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            while ($Pending.Count -gt 0) {
                $DirectoryPath = $Pending.Pop()
                if ($DirectoryPath -ne $LogRoot.FullName) {
                    $null = Resolve-TheCleanersFileSystemPath -LiteralPath $DirectoryPath -RootPath $LogRoot.FullName
                }
                foreach ($Item in @(Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction Stop)) {
                    if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                        Write-Verbose -Message "Skipping reparse point: $($Item.FullName)"
                        continue
                    }
                    if ($Item.PSIsContainer) {
                        $Pending.Push($Item.FullName)
                    } elseif ($Item.Extension -eq '.log' -and $Item.LastWriteTimeUtc -le $CutoffUtc) {
                        $Candidates.Add($Item)
                    }
                }
            }
            $OldFiles = @($Candidates.ToArray() | Sort-Object -Property FullName)
        } catch {
            $PSCmdlet.WriteError($_)
            # A failed discovery must not masquerade as an empty, successful preview.
            continue
        }
        foreach ($File in $OldFiles) {
            # This invokes normal WhatIf output. Even a true return value cannot trigger a mutation.
            $null = $PSCmdlet.ShouldProcess($File.FullName, 'Preview candidate only; Exchange removal is unavailable')
        }
        if ($PassThru) {
            [pscustomobject]@{
                PSTypeName              = 'TheCleaners.CleanupResult'
                Command                 = 'Clear-OldExchangeLog'
                RootPath                = $LogRoot.FullName
                CutoffUtc               = $CutoffUtc
                FileCandidateCount      = $OldFiles.Count
                FilesRemoved            = 0
                FileFailureCount        = 0
                DirectoryCandidateCount = 0
                DirectoriesRemoved      = 0
                DirectoryFailureCount   = 0
                BytesReclaimed          = [Int64]0
                Status                  = 'WhatIf'
                DiscoveryStatus         = 'Experimental'
                CandidatePaths          = @($OldFiles | ForEach-Object { $_.FullName })
            }
        }
    }
}

