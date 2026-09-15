function Clear-OldExchangeLog {
    <#
    .SYNOPSIS
        Preview old Exchange Server log candidates without removing anything.
    .DESCRIPTION
        This command is structurally preview-only: explicit -WhatIf is required,
        no removal parameter exists, and IIS cleanup is never invoked. Discovery
        validates the Exchange v15 installation root, uses fixed product-owned log
        directories, applies per-directory filename and extension allowlists, and
        excludes mailbox database and transaction-log paths returned by the
        Exchange management command when available. Missing management metadata is
        reported as Unknown protection status and cannot authorize a later removal
        implementation. ETL discovery remains experimental until product-version
        and lab acceptance are recorded.
    .PARAMETER Days
        Preview files whose LastWriteTimeUtc is at or before one UTC cutoff, Days
        days ago. The default is 60 days.
    .PARAMETER PassThru
        Return a TheCleaners.CleanupResult preview summary for each existing root.
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

    if (-not $PSBoundParameters.ContainsKey('WhatIf') -or -not $PSBoundParameters['WhatIf']) {
        $Exception = [System.NotSupportedException]::new('Exchange cleanup is preview-only. Run Clear-OldExchangeLog -WhatIf. Removal is not available in this version.')
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'ExchangeCleanupPreviewOnly' -Category NotImplemented
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $Exception = [System.PlatformNotSupportedException]::new('Exchange log discovery requires Windows.')
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'ExchangeWindowsRequired' -Category NotImplemented
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }
    Write-Warning -Message 'Exchange preview only: no files will be removed. Candidate discovery is experimental, not a deletion allowlist.'

    $CutoffUtc = (Get-Date).ToUniversalTime().AddDays(-$Days)
    $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup'
    $Setup = $null
    try {
        $Setup = Get-ItemProperty -LiteralPath $RegistryPath -Name MsiInstallPath -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($Setup.MsiInstallPath)) {
            throw [System.IO.InvalidDataException]::new('The Exchange Server installation path is missing.')
        }
    } catch {
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'ExchangeRegistryDiscoveryFailed' -Category ReadError
        if ($PassThru) {
            $PSCmdlet.WriteError($ErrorRecord)
            $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldExchangeLog' -RootPath $RegistryPath -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus 'Unknown' -ProductVersion 'Exchange Server v15' -DiscoverySource 'v15 setup registry' -CandidatePaths @() -Status 'DiscoveryFailed'
            $Result.FileCandidateCount = $null
            $Result.DirectoryCandidateCount = $null
            $Result.DiscoveryErrorCount = 1
            $Result.ErrorIds = @('ExchangeRegistryDiscoveryFailed')
            $Result
        } else {
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
        return
    }

    $InstallRoot = $null
    try {
        $InstallRoot = Resolve-TheCleanersFileSystemPath -LiteralPath $Setup.MsiInstallPath
        if ($InstallRoot -isnot [System.IO.DirectoryInfo]) {
            throw [System.IO.InvalidDataException]::new("The Exchange Server installation path is not a directory: '$($Setup.MsiInstallPath)'.")
        }
    } catch {
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'ExchangeInstallRootValidationFailed' -Category InvalidData -TargetObject $Setup.MsiInstallPath
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    $Protected = $null
    try {
        $Protected = Get-TheCleanersExchangeProtectedPaths -InstallRoot $InstallRoot
    } catch {
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'ExchangeProtectedPathDiscoveryFailed' -Category ReadError -TargetObject $InstallRoot.FullName
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }

    $RelativeRoots = @(
        'Logging'
        'Bin/Search/Ceres/Diagnostics/ETLTraces'
        'Bin/Search/Ceres/Diagnostics/Logs'
        'TransportRoles/Logs/MessageTracking'
    )
    $FoundExistingRoot = $false
    $DiscoveryErrorIds = [System.Collections.Generic.List[string]]::new()
    foreach ($RelativeRoot in $RelativeRoots) {
        $RootPath = Join-Path -Path $InstallRoot.FullName -ChildPath $RelativeRoot
        $RootExists = $false
        try {
            $RootExists = Test-Path -LiteralPath $RootPath -PathType Container -ErrorAction Stop
        } catch {
            $null = $DiscoveryErrorIds.Add('ExchangeDiscoveryFailed')
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'ExchangeDiscoveryFailed' -Category ReadError -TargetObject $RootPath
            $PSCmdlet.WriteError($ErrorRecord)
            if ($PassThru) {
                $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldExchangeLog' -RootPath $RootPath -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus $Protected.Status -ProtectionPathCount @($Protected.Paths).Count -ProtectionPaths @($Protected.Paths) -ProductVersion 'Exchange Server v15' -DiscoverySource 'v15 setup registry and fixed product roots' -CandidatePaths @() -Status 'DiscoveryFailed'
                $Result.FileCandidateCount = $null
                $Result.DirectoryCandidateCount = $null
                $Result.DiscoveryErrorCount = 1
                $Result.ErrorIds = @('ExchangeDiscoveryFailed')
                $Result
            }
            continue
        }
        if (-not $RootExists) {
            Write-Verbose -Message "Exchange log root not present as a directory: $RootPath"
            continue
        }
        $FoundExistingRoot = $true
        $OldFiles = @()
        $NormalizedRoot = $null
        try {
            $LogRoot = Resolve-TheCleanersFileSystemPath -LiteralPath $RootPath -RootPath $InstallRoot.FullName
            if ($LogRoot -isnot [System.IO.DirectoryInfo]) {
                throw [System.IO.InvalidDataException]::new("Exchange log root is not a directory: '$RootPath'.")
            }
            $NormalizedRoot = Convert-TheCleanersPathForComparison -Path $LogRoot.FullName
            $RootIsProtected = $false
            foreach ($ProtectedPath in @($Protected.Paths)) {
                $RootContainsProtectedPath = $ProtectedPath.StartsWith($NormalizedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
                $ProtectedPathContainsRoot = $NormalizedRoot.StartsWith($ProtectedPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
                if ($NormalizedRoot -eq $ProtectedPath -or $RootContainsProtectedPath -or $ProtectedPathContainsRoot) {
                    $RootIsProtected = $true
                    break
                }
            }
            if ($RootIsProtected) {
                throw [System.UnauthorizedAccessException]::new("The Exchange log root overlaps a protected database or transaction-log path: '$NormalizedRoot'.")
            }

            $Pending = [System.Collections.Generic.Stack[string]]::new()
            $Pending.Push($NormalizedRoot)
            $Candidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            while ($Pending.Count -gt 0) {
                $DirectoryPath = $Pending.Pop()
                if ($DirectoryPath -ne $NormalizedRoot) {
                    $Directory = Resolve-TheCleanersFileSystemPath -LiteralPath $DirectoryPath -RootPath $NormalizedRoot
                    if ($Directory -isnot [System.IO.DirectoryInfo]) {
                        throw [System.IO.InvalidDataException]::new("Exchange traversal path is not a directory: '$DirectoryPath'.")
                    }
                }
                foreach ($Item in @(Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction Stop)) {
                    if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                        Write-Verbose -Message "Skipping reparse point: $($Item.FullName)"
                        continue
                    }
                    if ($Item.PSIsContainer) {
                        $Pending.Push($Item.FullName)
                        continue
                    }
                    $ComparableItemPath = Convert-TheCleanersPathForComparison -Path $Item.FullName
                    $IsProtected = $false
                    foreach ($ProtectedPath in @($Protected.Paths)) {
                        if ($ComparableItemPath -eq $ProtectedPath -or $ComparableItemPath.StartsWith($ProtectedPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $IsProtected = $true
                            break
                        }
                    }
                    if (-not $IsProtected -and (Test-TheCleanersExchangeLogFileName -Name $Item.Name -RelativeRoot $RelativeRoot) -and $Item.LastWriteTimeUtc -le $CutoffUtc) {
                        $Candidates.Add($Item)
                    }
                }
            }
            $OldFiles = @($Candidates.ToArray() | Sort-Object -Property FullName)
        } catch {
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'ExchangeDiscoveryFailed' -Category ReadError -TargetObject $RootPath
            $PSCmdlet.WriteError($ErrorRecord)
            if ($PassThru) {
                $ResultRootPath = if ($null -ne $NormalizedRoot) { $NormalizedRoot } else { $RootPath }
                $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldExchangeLog' -RootPath $ResultRootPath -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus $Protected.Status -ProtectionPathCount @($Protected.Paths).Count -ProtectionPaths @($Protected.Paths) -ProductVersion 'Exchange Server v15' -DiscoverySource 'v15 setup registry and fixed product roots' -CandidatePaths @() -Status 'DiscoveryFailed'
                $Result.FileCandidateCount = $null
                $Result.DirectoryCandidateCount = $null
                $Result.DiscoveryErrorCount = 1
                $Result.ErrorIds = @('ExchangeDiscoveryFailed')
                $Result
            }
            continue
        }

        foreach ($File in $OldFiles) {
            $null = $PSCmdlet.ShouldProcess($File.FullName, 'Preview allowlisted candidate only; Exchange removal is unavailable')
        }
        if ($PassThru) {
            $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldExchangeLog' -RootPath $NormalizedRoot -CutoffUtc $CutoffUtc -DiscoveryStatus 'Experimental' -ProtectionStatus $Protected.Status -ProtectionPathCount @($Protected.Paths).Count -ProtectionPaths @($Protected.Paths) -ProductVersion 'Exchange Server v15' -DiscoverySource 'v15 setup registry and fixed product roots' -CandidatePaths @($OldFiles | ForEach-Object { $_.FullName }) -Status 'WhatIf'
            $Result.FileCandidateCount = $OldFiles.Count
            $Result
        }
    }

    if (-not $FoundExistingRoot -and $DiscoveryErrorIds.Count -eq 0) {
        $Exception = [System.InvalidOperationException]::new('Exchange is installed but no configured product log root could be discovered.')
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'ExchangeDiscoveryUnavailable' -Category ObjectNotFound -TargetObject $InstallRoot.FullName
        $PSCmdlet.WriteError($ErrorRecord)
        if ($PassThru) {
            $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldExchangeLog' -RootPath $InstallRoot.FullName -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus $Protected.Status -ProtectionPathCount @($Protected.Paths).Count -ProtectionPaths @($Protected.Paths) -ProductVersion 'Exchange Server v15' -DiscoverySource 'v15 setup registry and fixed product roots' -CandidatePaths @() -Status 'DiscoveryFailed'
            $Result.FileCandidateCount = $null
            $Result.DirectoryCandidateCount = $null
            $Result.DiscoveryErrorCount = 1
            $Result.ErrorIds = @('ExchangeDiscoveryUnavailable')
            $Result
        }
    }
}
