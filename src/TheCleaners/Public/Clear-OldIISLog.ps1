function Clear-OldIISLog {
    <#
    .SYNOPSIS
        Preview old allowlisted IIS log candidates without removing anything.
    .DESCRIPTION
        This command is structurally preview-only while IIS server acceptance is
        incomplete. Explicit -WhatIf is required. Discovery expands and validates
        configured web and FTP roots, rejects protected IIS configuration paths,
        skips reparse points, deduplicates normalized roots, and applies a
        per-format filename allowlist before the inclusive UTC cutoff. A
        WebAdministration dependency imported for discovery is removed afterward,
        while an already loaded dependency is preserved. No deletion command or
        generic mutation helper is called. The allowlist is a discovery safety
        boundary, not stable-removal evidence; a disposable IIS lab is still
        required before any future removal.
    .PARAMETER Days
        Preview allowlisted log files whose LastWriteTimeUtc is at or before one UTC
        cutoff, Days days ago. The default is 60 days.
    .PARAMETER PassThru
        Return a TheCleaners.CleanupResult preview summary for each existing root,
        including failed discovery results with null candidate counts.
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
    $IisProtectedPaths = @(Get-TheCleanersIisProtectedPaths)
    $WebAdministrationModule = Get-Module -Name 'WebAdministration' -ListAvailable | Select-Object -First 1
    $DiscoveryErrorReported = $false
    $DiscoveryErrorIds = [System.Collections.Generic.List[string]]::new()
    $DiscoveryFailureResultReported = $false

    if ($null -ne $WebAdministrationModule) {
        try {
            $WebAdministrationDiscovery = [System.Management.Automation.PowerShell]::Create()
            try {
                $null = $WebAdministrationDiscovery.AddScript({
                        param (
                            [Parameter(Mandatory)]
                            [string]
                            $ModulePath
                        )

                        $ErrorActionPreference = 'Stop'
                        Import-Module -Name $ModulePath -Scope Local -ErrorAction Stop
                        foreach ($Site in @(WebAdministration\Get-Website -ErrorAction Stop)) {
                            $FtpLogConfiguration = $null
                            $FtpConfigurationErrorMessage = $null
                            $FtpBindings = @($Site.Bindings | Where-Object { [string]$_.Protocol -ieq 'ftp' })
                            if ($FtpBindings.Count -gt 0) {
                                try {
                                    $SiteNameForFilter = ([string]$Site.Name).Replace("'", "''")
                                    $FtpFilter = "system.applicationHost/sites/site[@name='$SiteNameForFilter']/ftpServer/logFile"
                                    $FtpLogConfiguration = @(WebAdministration\Get-WebConfiguration -Filter $FtpFilter -PSPath 'MACHINE/WEBROOT/APPHOST' -ErrorAction Stop | Select-Object -First 1)
                                    if ($FtpLogConfiguration.Count -eq 0) {
                                        throw [System.InvalidOperationException]::new("The IIS FTP log configuration was not returned for site '$($Site.Name)'.")
                                    }
                                    $FtpLogConfiguration = $FtpLogConfiguration[0]
                                } catch {
                                    $FtpConfigurationErrorMessage = $_.Exception.Message
                                }
                            }
                            [pscustomobject]@{
                                Name                         = $Site.Name
                                Id                           = $Site.Id
                                LogFile                      = $Site.LogFile
                                Bindings                     = $Site.Bindings
                                FtpLogConfiguration          = $FtpLogConfiguration
                                FtpConfigurationErrorMessage = $FtpConfigurationErrorMessage
                            }
                        }
                    }).AddArgument($WebAdministrationModule.Path)
                $DiscoveredSites = @($WebAdministrationDiscovery.Invoke())
                if ($WebAdministrationDiscovery.HadErrors) {
                    $DiscoveryError = @($WebAdministrationDiscovery.Streams.Error | Select-Object -First 1)
                    if ($DiscoveryError.Count -gt 0) {
                        throw $DiscoveryError[0].Exception
                    }
                    throw [System.InvalidOperationException]::new('IIS website discovery failed in the isolated dependency runspace.')
                }
            } finally {
                $WebAdministrationDiscovery.Dispose()
            }

            foreach ($Site in $DiscoveredSites) {
                $ConfiguredRoot = [Environment]::ExpandEnvironmentVariables([string]$Site.LogFile.Directory)
                $SiteName = [string]$Site.Name
                $WebRootDefinition = $null
                if ([string]::IsNullOrWhiteSpace($ConfiguredRoot)) {
                    Write-Verbose -Message "IIS site '$($Site.Name)' has no log directory."
                } else {
                    $Format = [string]$Site.LogFile.LogFormat
                    $WebDiscoveryErrorIds = [System.Collections.Generic.List[string]]::new()
                    if ([string]::IsNullOrWhiteSpace($Format)) {
                        $null = $WebDiscoveryErrorIds.Add('IISLogFormatUnavailable')
                    }
                    $WebRootDefinition = [pscustomobject]@{
                        Path              = Join-Path -Path $ConfiguredRoot -ChildPath ('W3SVC{0}' -f $Site.Id)
                        DisplayName       = $SiteName
                        Source            = 'WebAdministration'
                        Format            = if ([string]::IsNullOrWhiteSpace($Format)) { $null } else { $Format }
                        Service           = 'W3SVC'
                        LocalTimeRollover = [bool]$Site.LogFile.LocalTimeRollover
                        DiscoveryErrorIds = $WebDiscoveryErrorIds
                    }
                    $Roots.Add($WebRootDefinition)
                }

                $FtpBindings = @($Site.Bindings | Where-Object { [string]$_.Protocol -ieq 'ftp' })
                if ($FtpBindings.Count -eq 0) {
                    continue
                }
                try {
                    if (-not [string]::IsNullOrWhiteSpace([string]$Site.FtpConfigurationErrorMessage)) {
                        throw [System.InvalidOperationException]::new($Site.FtpConfigurationErrorMessage)
                    }
                    if ($null -eq $Site.FtpLogConfiguration) {
                        throw [System.InvalidOperationException]::new("The IIS FTP log configuration was unavailable for site '$SiteName'.")
                    }
                    $FtpConfiguredRoot = [Environment]::ExpandEnvironmentVariables([string]$Site.FtpLogConfiguration.Directory)
                    if ([string]::IsNullOrWhiteSpace($FtpConfiguredRoot)) {
                        if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) {
                            throw [System.InvalidOperationException]::new("Cannot determine the default IIS FTP log directory for site '$SiteName'.")
                        }
                        $FtpConfiguredRoot = Join-Path -Path $env:SystemDrive -ChildPath 'inetpub/logs/LogFiles'
                    }
                    $FtpFormat = [string]$Site.FtpLogConfiguration.LogFormat
                    if ([string]::IsNullOrWhiteSpace($FtpFormat)) {
                        throw [System.InvalidOperationException]::new("The IIS FTP logging format was unavailable for site '$SiteName'.")
                    }
                    $Roots.Add([pscustomobject]@{
                            Path              = Join-Path -Path $FtpConfiguredRoot -ChildPath ('FTPSVC{0}' -f $Site.Id)
                            DisplayName       = "$SiteName FTP"
                            Source            = 'WebAdministration'
                            Format            = $FtpFormat
                            Service           = 'FTPSVC'
                            LocalTimeRollover = [bool]$Site.FtpLogConfiguration.LocalTimeRollover
                            DiscoveryErrorIds = [System.Collections.Generic.List[string]]::new()
                        })
                } catch {
                    $DiscoveryErrorReported = $true
                    $DiscoveryFailureResultReported = $true
                    $null = $DiscoveryErrorIds.Add('IISFtpDiscoveryFailed')
                    if ($PassThru) {
                        $FtpFailureRootPath = "IIS FTP log root unavailable for '$SiteName'"
                        $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldIISLog' -RootPath $FtpFailureRootPath -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus 'Validated' -ProtectionPathCount $IisProtectedPaths.Count -ProtectionPaths $IisProtectedPaths -DiscoverySource 'WebAdministration' -DisplayName "$SiteName FTP" -CandidatePaths @() -Status 'DiscoveryFailed'
                        $Result.FileCandidateCount = $null
                        $Result.DirectoryCandidateCount = $null
                        $Result.DiscoveryErrorCount = 1
                        $Result.ErrorIds = @('IISFtpDiscoveryFailed')
                        $Result | Add-Member -MemberType NoteProperty -Name AllowedFilePatterns -Value @('IIS format allowlist')
                        $Result
                    }
                    $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'IISFtpDiscoveryFailed' -Category ReadError -TargetObject $SiteName
                    $PSCmdlet.WriteError($ErrorRecord)
                }
            }
        } catch {
            $DiscoveryErrorReported = $true
            $null = $DiscoveryErrorIds.Add('IISDiscoveryFailed')
            foreach ($RootDefinition in @($Roots | Where-Object { $_.Source -eq 'WebAdministration' })) {
                $null = $RootDefinition.DiscoveryErrorIds.Add('IISDiscoveryFailed')
            }
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'IISDiscoveryFailed' -Category ReadError
            $PSCmdlet.WriteError($ErrorRecord)
        }
    } else {
        $DefaultRootDefinition = $null
        $DefaultDiscoveryErrorIds = [System.Collections.Generic.List[string]]::new()
        $null = $DefaultDiscoveryErrorIds.Add('IISLogFormatUnavailable')
        if (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
            $DefaultRootDefinition = [pscustomobject]@{
                Path              = Join-Path -Path $env:SystemDrive -ChildPath 'inetpub/logs/LogFiles'
                DisplayName       = 'Default IIS log root'
                Source            = 'DefaultPath'
                Format            = $null
                Service           = 'W3SVC'
                LocalTimeRollover = $null
                DiscoveryErrorIds = $DefaultDiscoveryErrorIds
            }
            $Roots.Add($DefaultRootDefinition)
        }
        try {
            $RegistrySettings = Get-ItemProperty -LiteralPath 'HKLM:\System\CurrentControlSet\Services\W3SVC\Parameters' -Name 'LogDir' -ErrorAction Stop
            $RegistryRoot = $RegistrySettings.LogDir
            $RegistryRoot = [Environment]::ExpandEnvironmentVariables([string]$RegistryRoot)
            $RegistryFormat = $null
            try {
                $RegistryFormatSettings = Get-ItemProperty -LiteralPath 'HKLM:\System\CurrentControlSet\Services\W3SVC\Parameters' -Name 'LogFormat' -ErrorAction Stop
                $RegistryFormat = [string]$RegistryFormatSettings.LogFormat
            } catch {
                $OptionalRegistryFormatIsAbsent = (
                    $_.Exception -is [System.Management.Automation.ItemNotFoundException] -or
                    ($_.Exception -is [System.Management.Automation.PSArgumentException] -and $_.Exception.Message -match '^Property .+ does not exist') -or
                    $_.FullyQualifiedErrorId -match 'PathNotFound|PropertyNotFound|ItemNotFound'
                )
                if (-not $OptionalRegistryFormatIsAbsent) {
                    throw
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($RegistryRoot)) {
                $RegistryDiscoveryErrorIds = [System.Collections.Generic.List[string]]::new()
                if ([string]::IsNullOrWhiteSpace($RegistryFormat)) {
                    $null = $RegistryDiscoveryErrorIds.Add('IISLogFormatUnavailable')
                }
                $Roots.Add([pscustomobject]@{
                        Path              = $RegistryRoot
                        DisplayName       = 'Registry IIS log root'
                        Source            = 'Registry'
                        Format            = if ([string]::IsNullOrWhiteSpace($RegistryFormat)) { $null } else { $RegistryFormat }
                        Service           = 'W3SVC'
                        LocalTimeRollover = $null
                        DiscoveryErrorIds = $RegistryDiscoveryErrorIds
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
                $DiscoveryErrorReported = $true
                $null = $DiscoveryErrorIds.Add('IISRegistryDiscoveryFailed')
                if ($null -ne $DefaultRootDefinition) {
                    $null = $DefaultRootDefinition.DiscoveryErrorIds.Add('IISRegistryDiscoveryFailed')
                }
                $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'IISRegistryDiscoveryFailed' -Category ReadError
                $PSCmdlet.WriteError($ErrorRecord)
            }
        }
    }

    $RootDefinitionsByPath = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $MergedRoots = [System.Collections.Generic.List[object]]::new()
    foreach ($RootDefinition in @($Roots.ToArray())) {
        try {
            $RootDefinitionPath = Convert-TheCleanersPathForComparison -Path ([string]$RootDefinition.Path)
        } catch {
            $MergedRoots.Add($RootDefinition)
            continue
        }
        if (-not $RootDefinitionsByPath.ContainsKey($RootDefinitionPath)) {
            $RootDefinitionsByPath.Add($RootDefinitionPath, $RootDefinition)
            $MergedRoots.Add($RootDefinition)
            continue
        }

        $ExistingRootDefinition = $RootDefinitionsByPath[$RootDefinitionPath]
        $ExistingFormat = [string]$ExistingRootDefinition.Format
        $CurrentFormat = [string]$RootDefinition.Format
        if ([string]::IsNullOrWhiteSpace($ExistingFormat) -and -not [string]::IsNullOrWhiteSpace($CurrentFormat)) {
            $ExistingRootDefinition.Format = $CurrentFormat
            $ExistingRootDefinition.LocalTimeRollover = $RootDefinition.LocalTimeRollover
            $FilteredErrorIds = [System.Collections.Generic.List[string]]::new()
            foreach ($ExistingErrorId in @($ExistingRootDefinition.DiscoveryErrorIds)) {
                if ($ExistingErrorId -ne 'IISLogFormatUnavailable') {
                    $null = $FilteredErrorIds.Add($ExistingErrorId)
                }
            }
            $ExistingRootDefinition.DiscoveryErrorIds = $FilteredErrorIds
        }

        $MergedRootFormat = [string]$ExistingRootDefinition.Format
        foreach ($RootErrorId in @($RootDefinition.DiscoveryErrorIds)) {
            if ($RootErrorId -eq 'IISLogFormatUnavailable' -and -not [string]::IsNullOrWhiteSpace($MergedRootFormat)) {
                continue
            }
            if (-not $ExistingRootDefinition.DiscoveryErrorIds.Contains($RootErrorId)) {
                $null = $ExistingRootDefinition.DiscoveryErrorIds.Add($RootErrorId)
            }
        }
    }
    $Roots = $MergedRoots

    $FoundExistingRoot = $false
    foreach ($RootDefinition in $Roots) {
        $RootDiscoveryErrorIds = [System.Collections.Generic.List[string]]::new()
        foreach ($RootErrorId in @($RootDefinition.DiscoveryErrorIds)) {
            $null = $RootDiscoveryErrorIds.Add($RootErrorId)
        }
        $RootExists = $false
        $ProtectedRoot = $false
        try {
            if (-not (Test-TheCleanersFullyQualifiedPath -Path $RootDefinition.Path)) {
                throw [System.IO.InvalidDataException]::new("The IIS log root is not a fully qualified filesystem path: '$($RootDefinition.Path)'.")
            }
            $ProtectedRoot = Test-TheCleanersIisProtectedPath -Path $RootDefinition.Path
            $RootExists = Test-Path -LiteralPath $RootDefinition.Path -PathType Container -ErrorAction Stop
        } catch {
            $DiscoveryErrorReported = $true
            $DiscoveryFailureResultReported = $true
            $null = $RootDiscoveryErrorIds.Add('IISDiscoveryFailed')
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'IISDiscoveryFailed' -Category ReadError -TargetObject $RootDefinition.Path
            $PSCmdlet.WriteError($ErrorRecord)
            if ($PassThru) {
                $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldIISLog' -RootPath $RootDefinition.Path -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus 'Validated' -ProtectionPathCount $IisProtectedPaths.Count -ProtectionPaths $IisProtectedPaths -DiscoverySource $RootDefinition.Source -DisplayName $RootDefinition.DisplayName -CandidatePaths @() -Status 'DiscoveryFailed'
                $Result.FileCandidateCount = $null
                $Result.DirectoryCandidateCount = $null
                $Result.DiscoveryErrorCount = $RootDiscoveryErrorIds.Count
                $Result.ErrorIds = @($RootDiscoveryErrorIds | Sort-Object -Unique)
                $Result | Add-Member -MemberType NoteProperty -Name AllowedFilePatterns -Value @('IIS format allowlist')
                $Result
            }
            continue
        }
        if ($ProtectedRoot) {
            $FoundExistingRoot = $true
            $DiscoveryErrorReported = $true
            $null = $RootDiscoveryErrorIds.Add('IISProtectedRoot')
            $Exception = [System.UnauthorizedAccessException]::new("The IIS path is protected and cannot be used as a log root: '$($RootDefinition.Path)'.")
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'IISProtectedRoot' -Category PermissionDenied -TargetObject $RootDefinition.Path
            $PSCmdlet.WriteError($ErrorRecord)
            if ($PassThru) {
                $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldIISLog' -RootPath $RootDefinition.Path -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus 'Validated' -ProtectionPathCount $IisProtectedPaths.Count -ProtectionPaths $IisProtectedPaths -DiscoverySource $RootDefinition.Source -DisplayName $RootDefinition.DisplayName -CandidatePaths @() -Status 'DiscoveryFailed'
                $Result.FileCandidateCount = $null
                $Result.DirectoryCandidateCount = $null
                $Result.DiscoveryErrorCount = $RootDiscoveryErrorIds.Count
                $Result.ErrorIds = @($RootDiscoveryErrorIds | Sort-Object -Unique)
                $Result | Add-Member -MemberType NoteProperty -Name AllowedFilePatterns -Value @('IIS format allowlist')
                $Result
            }
            continue
        }
        if (-not $RootExists) {
            if ($RootDiscoveryErrorIds -contains 'IISFtpDiscoveryFailed') {
                $DiscoveryFailureResultReported = $true
                if ($PassThru) {
                    $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldIISLog' -RootPath $RootDefinition.Path -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus 'Validated' -ProtectionPathCount $IisProtectedPaths.Count -ProtectionPaths $IisProtectedPaths -DiscoverySource $RootDefinition.Source -DisplayName $RootDefinition.DisplayName -CandidatePaths @() -Status 'DiscoveryFailed'
                    $Result.FileCandidateCount = $null
                    $Result.DirectoryCandidateCount = $null
                    $Result.DiscoveryErrorCount = $RootDiscoveryErrorIds.Count
                    $Result.ErrorIds = @($RootDiscoveryErrorIds | Sort-Object -Unique)
                    $Result | Add-Member -MemberType NoteProperty -Name AllowedFilePatterns -Value @('IIS format allowlist')
                    $Result
                }
            } else {
                Write-Verbose -Message "IIS log root not present as a directory: $($RootDefinition.Path)"
            }
            continue
        }
        $FoundExistingRoot = $true

        $OldFiles = @()
        $NormalizedRoot = $null
        try {
            $LogRoot = Resolve-TheCleanersFileSystemPath -LiteralPath $RootDefinition.Path
            if ($LogRoot -isnot [System.IO.DirectoryInfo]) {
                throw [System.IO.InvalidDataException]::new("IIS log root is not a directory: '$($RootDefinition.Path)'.")
            }
            $TraversalRoot = $LogRoot.FullName
            $NormalizedRoot = Convert-TheCleanersPathForComparison -Path $LogRoot.FullName
            if (-not $SeenRoots.Add($NormalizedRoot)) {
                Write-Verbose -Message "Skipping duplicate IIS log root: $NormalizedRoot"
                continue
            }
            if ($RootDiscoveryErrorIds.Count -gt 0) {
                if ($PassThru) {
                    $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldIISLog' -RootPath $NormalizedRoot -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus 'Validated' -ProtectionPathCount $IisProtectedPaths.Count -ProtectionPaths $IisProtectedPaths -DiscoverySource $RootDefinition.Source -DisplayName $RootDefinition.DisplayName -CandidatePaths @() -Status 'DiscoveryFailed'
                    $Result.FileCandidateCount = $null
                    $Result.DirectoryCandidateCount = $null
                    $Result.DiscoveryErrorCount = $RootDiscoveryErrorIds.Count
                    $Result.ErrorIds = @($RootDiscoveryErrorIds | Sort-Object -Unique)
                    $Result | Add-Member -MemberType NoteProperty -Name AllowedFilePatterns -Value @('IIS format allowlist')
                    $Result
                }
                continue
            }
            $Pending = [System.Collections.Generic.Stack[object]]::new()
            $InitialService = [string]$RootDefinition.Service
            $InitialDirectoryName = [System.IO.Path]::GetFileName($TraversalRoot.TrimEnd([char[]]@('\', '/')))
            if ($InitialDirectoryName -match '^(FTPSVC|MSFTPSVC)\d+$') {
                $InitialService = $Matches[1]
            } elseif ($InitialDirectoryName -match '^W3SVC\d+$') {
                $InitialService = 'W3SVC'
            }
            $Pending.Push([pscustomobject]@{
                    Path    = $TraversalRoot
                    Service = $InitialService
                })
            $Candidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            while ($Pending.Count -gt 0) {
                $DirectoryState = $Pending.Pop()
                $DirectoryPath = [string]$DirectoryState.Path
                $DirectoryService = [string]$DirectoryState.Service
                if ($DirectoryPath -ne $TraversalRoot) {
                    $Directory = Resolve-TheCleanersFileSystemPath -LiteralPath $DirectoryPath -RootPath $TraversalRoot
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
                        $ChildService = $DirectoryService
                        $ChildDirectoryName = [System.IO.Path]::GetFileName($Item.FullName.TrimEnd([char[]]@('\', '/')))
                        if ($ChildDirectoryName -match '^(FTPSVC|MSFTPSVC)\d+$') {
                            $ChildService = $Matches[1]
                        } elseif ($ChildDirectoryName -match '^W3SVC\d+$') {
                            $ChildService = 'W3SVC'
                        }
                        $Pending.Push([pscustomobject]@{
                                Path    = $Item.FullName
                                Service = $ChildService
                            })
                    } elseif ((Test-TheCleanersIisLogFileName -Name $Item.Name -Format $RootDefinition.Format -Service $DirectoryService -LocalTimeRollover:$RootDefinition.LocalTimeRollover) -and $Item.LastWriteTimeUtc -le $CutoffUtc) {
                        $Candidates.Add($Item)
                    }
                }
            }
            $OldFiles = @($Candidates.ToArray() | Sort-Object -Property FullName)
        } catch {
            $null = $RootDiscoveryErrorIds.Add('IISDiscoveryFailed')
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $_.Exception -ErrorId 'IISDiscoveryFailed' -Category ReadError -TargetObject $RootDefinition.Path
            $PSCmdlet.WriteError($ErrorRecord)
            if ($PassThru) {
                $ResultRootPath = if ($null -ne $NormalizedRoot) { $NormalizedRoot } else { $RootDefinition.Path }
                $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldIISLog' -RootPath $ResultRootPath -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus 'Validated' -ProtectionPathCount $IisProtectedPaths.Count -ProtectionPaths $IisProtectedPaths -DiscoverySource $RootDefinition.Source -DisplayName $RootDefinition.DisplayName -CandidatePaths @() -Status 'DiscoveryFailed'
                $Result.FileCandidateCount = $null
                $Result.DirectoryCandidateCount = $null
                $Result.DiscoveryErrorCount = $RootDiscoveryErrorIds.Count
                $Result.ErrorIds = @($RootDiscoveryErrorIds | Sort-Object -Unique)
                $Result | Add-Member -MemberType NoteProperty -Name AllowedFilePatterns -Value @('IIS format allowlist')
                $Result
            }
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

    if (-not $FoundExistingRoot -and -not $DiscoveryFailureResultReported) {
        $FinalErrorIds = @($DiscoveryErrorIds | Sort-Object -Unique)
        if (-not $DiscoveryErrorReported) {
            $Exception = [System.InvalidOperationException]::new('IIS is not installed or no configured IIS log root could be discovered.')
            $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'IISDiscoveryUnavailable' -Category ObjectNotFound
            $PSCmdlet.WriteError($ErrorRecord)
            $FinalErrorIds = @('IISDiscoveryUnavailable')
        } elseif ($FinalErrorIds.Count -eq 0) {
            $FinalErrorIds = @('IISDiscoveryFailed')
        }
        if ($PassThru) {
            $UnavailableRootPath = $null
            if ($Roots.Count -gt 0) {
                $UnavailableRootPath = [string]$Roots[0].Path
            } elseif (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
                $UnavailableRootPath = Join-Path -Path $env:SystemDrive -ChildPath 'inetpub/logs/LogFiles'
            } else {
                $UnavailableRootPath = 'IIS log roots'
            }
            $Result = Get-TheCleanersCleanupResult -Command 'Clear-OldIISLog' -RootPath $UnavailableRootPath -CutoffUtc $CutoffUtc -DiscoveryStatus 'Failed' -ProtectionStatus 'Validated' -ProtectionPathCount $IisProtectedPaths.Count -ProtectionPaths $IisProtectedPaths -DiscoverySource 'IIS default, registry, and WebAdministration roots' -DisplayName 'IIS discovery' -CandidatePaths @() -Status 'DiscoveryFailed'
            $Result.FileCandidateCount = $null
            $Result.DirectoryCandidateCount = $null
            $Result.DiscoveryErrorCount = $FinalErrorIds.Count
            $Result.ErrorIds = $FinalErrorIds
            $Result | Add-Member -MemberType NoteProperty -Name AllowedFilePatterns -Value @('IIS format allowlist')
            $Result
        }
    }
}
