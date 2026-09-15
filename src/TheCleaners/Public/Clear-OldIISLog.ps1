function Clear-OldIISLog {
    <#
    .SYNOPSIS
        Preview old allowlisted IIS log candidates without removing anything.
    .DESCRIPTION
        This command is structurally preview-only while IIS server acceptance is
        incomplete. Explicit -WhatIf is required. Discovery expands and validates
        configured roots, rejects protected IIS configuration paths, skips reparse
        points, deduplicates normalized roots, and applies a per-format filename
        allowlist before the inclusive UTC cutoff. A WebAdministration dependency
        imported for discovery is removed afterward, while an already loaded
        dependency is preserved. No deletion command or generic mutation helper is
        called. The allowlist is a discovery safety boundary, not stable-removal
        evidence; a disposable IIS lab is still required before any future removal.
    .PARAMETER Days
        Preview allowlisted log files whose LastWriteTimeUtc is at or before one UTC
        cutoff, Days days ago. The default is 60 days.
    .PARAMETER PassThru
        Return a TheCleaners.CleanupResult preview summary for each existing root.
    .EXAMPLE
        Clear-OldIISLog -Days 60 -WhatIf
    .EXAMPLE
        Clear-OldIISLog -Days 30 -WhatIf -PassThru
    .OUTPUTS
        TheCleaners.CleanupResult
    .LINK
        https://day3bits.com/thecleaners/Clear-OldIISLog/
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [Alias('Clean-IISLog')]
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
        $Exception = [System.NotSupportedException]::new('IIS cleanup is preview-only. Run Clear-OldIISLog -WhatIf. Removal is not available in this version.')
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'IISCleanupPreviewOnly' -Category NotImplemented
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $Exception = [System.PlatformNotSupportedException]::new('IIS log discovery requires Windows.')
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'IISWindowsRequired' -Category NotImplemented
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }
    Write-Warning -Message 'IIS preview only: no files will be removed. Candidate discovery is experimental, not a deletion allowlist.'

    $CutoffUtc = (Get-Date).ToUniversalTime().AddDays(-$Days)
    $Roots = [System.Collections.Generic.List[object]]::new()
    $SeenRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $GlobalDiscoveryErrorIds = [System.Collections.Generic.List[string]]::new()
    $IisProtectedPaths = @(Get-TheCleanersIisProtectedPaths)
    $WebAdministrationModule = Get-Module -Name 'WebAdministration' -ListAvailable | Select-Object -First 1

    if ($null -ne $WebAdministrationModule) {
        $WebAdministrationWasLoaded = @(Get-Module -Name 'WebAdministration' -All).Count -gt 0
        try {
            if (-not $WebAdministrationWasLoaded) {
                Import-Module -Name $WebAdministrationModule.Path -Scope Local -ErrorAction Stop
            }
            foreach ($Site in @(WebAdministration\Get-Website -ErrorAction Stop)) {
                $ConfiguredRoot = [Environment]::ExpandEnvironmentVariables([string]$Site.LogFile.Directory)
                if ([string]::IsNullOrWhiteSpace($ConfiguredRoot)) {
                    Write-Verbose -Message "IIS site '$($Site.Name)' has no log directory."
                    continue
                }
                $Format = if ($null -eq $Site.LogFile.LogFormat) { 'W3C' } else { [string]$Site.LogFile.LogFormat }
                $Roots.Add([pscustomobject]@{
                        Path        = Join-Path -Path $ConfiguredRoot -ChildPath ('W3SVC{0}' -f $Site.Id)
                        DisplayName = [string]$Site.Name
                        Source      = 'WebAdministration'
                        Format      = $Format
                        Service     = 'W3SVC'
                    })
            }
        } catch {
            $null = $GlobalDiscoveryErrorIds.Add('IISDiscoveryFailed')
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'IISDiscoveryFailed' -Category ReadError
            $PSCmdlet.WriteError($ErrorRecord)
        } finally {
            if (-not $WebAdministrationWasLoaded) {
                # Restore only the dependency this invocation introduced. This is
                # session cleanup, not file cleanup, and must ignore WhatIf.
                foreach ($Dependency in @(Get-Module -Name 'WebAdministration' -All)) {
                    Remove-Module -ModuleInfo $Dependency -WhatIf:$false -Confirm:$false -ErrorAction Stop
                }
            }
        }
    } else {
        if (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
            $Roots.Add([pscustomobject]@{
                    Path        = Join-Path -Path $env:SystemDrive -ChildPath 'inetpub/logs/LogFiles'
                    DisplayName = 'Default IIS log root'
                    Source      = 'DefaultPath'
                    Format      = 'W3C'
                    Service     = 'W3SVC'
                })
        }
        try {
            $RegistryRoot = Get-ItemProperty -LiteralPath 'HKLM:\System\CurrentControlSet\Services\W3SVC\Parameters' -Name 'LogDir' -ErrorAction Stop |
                Select-Object -ExpandProperty LogDir
            $RegistryRoot = [Environment]::ExpandEnvironmentVariables([string]$RegistryRoot)
            if (-not [string]::IsNullOrWhiteSpace($RegistryRoot)) {
                $Roots.Add([pscustomobject]@{
                        Path        = $RegistryRoot
                        DisplayName = 'Registry IIS log root'
                        Source      = 'Registry'
                        Format      = 'W3C'
                        Service     = 'W3SVC'
                    })
            }
        } catch {
            $OptionalRegistryValueIsAbsent = (
                $_.Exception -is [System.Management.Automation.ItemNotFoundException] -or
                ($_.Exception -is [System.Management.Automation.PSArgumentException] -and $_.Exception.Message -match '^Property .+ does not exist') -or
                $_.FullyQualifiedErrorId -match 'PathNotFound|PropertyNotFound|ItemNotFound'
            )
            if ($OptionalRegistryValueIsAbsent) {
                Write-Verbose -Message "The optional alternate IIS log location is not configured: $($_.Exception.Message)"
            } else {
                $null = $GlobalDiscoveryErrorIds.Add('IISRegistryDiscoveryFailed')
                $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'IISRegistryDiscoveryFailed' -Category ReadError
                $PSCmdlet.WriteError($ErrorRecord)
            }
        }
    }

    foreach ($RootDefinition in $Roots) {
        $RootDiscoveryErrorIds = [System.Collections.Generic.List[string]]::new()
        foreach ($GlobalErrorId in @($GlobalDiscoveryErrorIds)) {
            $null = $RootDiscoveryErrorIds.Add($GlobalErrorId)
        }
        if (Test-TheCleanersIisProtectedPath -Path $RootDefinition.Path) {
            $null = $RootDiscoveryErrorIds.Add('IISProtectedRoot')
            $Exception = [System.UnauthorizedAccessException]::new("The IIS path is protected and cannot be used as a log root: '$($RootDefinition.Path)'.")
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'IISProtectedRoot' -Category PermissionDenied -TargetObject $RootDefinition.Path
            $PSCmdlet.WriteError($ErrorRecord)
            continue
        }
        if (-not (Test-Path -LiteralPath $RootDefinition.Path -PathType Container)) {
            Write-Verbose -Message "IIS log root not present as a directory: $($RootDefinition.Path)"
            continue
        }

        $OldFiles = @()
        $NormalizedRoot = $null
        try {
            $LogRoot = Resolve-TheCleanersFileSystemPath -LiteralPath $RootDefinition.Path
            if ($LogRoot -isnot [System.IO.DirectoryInfo]) {
                throw [System.IO.InvalidDataException]::new("IIS log root is not a directory: '$($RootDefinition.Path)'.")
            }
            $NormalizedRoot = Convert-TheCleanersPathForComparison -Path $LogRoot.FullName
            if (-not $SeenRoots.Add($NormalizedRoot)) {
                Write-Verbose -Message "Skipping duplicate IIS log root: $NormalizedRoot"
                continue
            }
            $RootDefinition.Path = $NormalizedRoot
            $Pending = [System.Collections.Generic.Stack[string]]::new()
            $Pending.Push($NormalizedRoot)
            $Candidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            while ($Pending.Count -gt 0) {
                $DirectoryPath = $Pending.Pop()
                if ($DirectoryPath -ne $NormalizedRoot) {
                    $Directory = Resolve-TheCleanersFileSystemPath -LiteralPath $DirectoryPath -RootPath $NormalizedRoot
                    if ($Directory -isnot [System.IO.DirectoryInfo]) {
                        throw [System.IO.InvalidDataException]::new("IIS traversal path is not a directory: '$DirectoryPath'.")
                    }
                }
                foreach ($Item in @(Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction Stop)) {
                    if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                        Write-Verbose -Message "Skipping reparse point: $($Item.FullName)"
                        continue
                    }
                    if ($Item.PSIsContainer) {
                        $Pending.Push($Item.FullName)
                    } elseif ((Test-TheCleanersIisLogFileName -Name $Item.Name -Format $RootDefinition.Format -Service $RootDefinition.Service) -and $Item.LastWriteTimeUtc -le $CutoffUtc) {
                        $Candidates.Add($Item)
                    }
                }
            }
            $OldFiles = @($Candidates.ToArray() | Sort-Object -Property FullName)
        } catch {
            $null = $RootDiscoveryErrorIds.Add('IISDiscoveryFailed')
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'IISDiscoveryFailed' -Category ReadError -TargetObject $RootDefinition.Path
            $PSCmdlet.WriteError($ErrorRecord)
            continue
        }

        foreach ($File in $OldFiles) {
            $null = $PSCmdlet.ShouldProcess($File.FullName, 'Preview allowlisted candidate only; IIS removal is unavailable')
        }
        if ($PassThru) {
            $ResultDiscoveryStatus = 'Experimental'
            $ResultErrorIds = @($RootDiscoveryErrorIds | Sort-Object -Unique)
            if ($ResultErrorIds.Count -gt 0) {
                $ResultDiscoveryStatus = 'Failed'
            }
            $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldIISLog' -RootPath $NormalizedRoot -CutoffUtc $CutoffUtc -DiscoveryStatus $ResultDiscoveryStatus -ProtectionStatus 'Validated' -ProtectionPathCount $IisProtectedPaths.Count -ProtectionPaths $IisProtectedPaths -DiscoverySource $RootDefinition.Source -DisplayName $RootDefinition.DisplayName -CandidatePaths @($OldFiles | ForEach-Object { $_.FullName }) -Status 'WhatIf'
            if ($ResultErrorIds.Count -gt 0) {
                $Result.DiscoveryErrorCount = $ResultErrorIds.Count
                $Result.ErrorIds = $ResultErrorIds
            }
            $Result.FileCandidateCount = $OldFiles.Count
            $Result | Add-Member -MemberType NoteProperty -Name AllowedFilePatterns -Value @('IIS format allowlist')
            $Result
        }
    }
}
