function Clear-OldIISLog {
    <#
    .SYNOPSIS
        Preview old IIS log candidates without removing anything.
    .DESCRIPTION
        This command is structurally preview-only while IIS path, file-pattern, and
        server acceptance work remains incomplete. Explicit -WhatIf is required. The
        command discovers existing IIS log roots, skips reparse points before traversal,
        and previews old .log files using one inclusive UTC cutoff. Candidate discovery
        is experimental and is not a validated deletion allowlist. No deletion command
        or generic removal helper is called.
    .PARAMETER Days
        Preview .log files whose LastWriteTimeUtc is at or before one UTC cutoff, Days
        days ago. The default is 60 days.
    .PARAMETER PassThru
        Return a TheCleaners.CleanupResult preview summary for each successfully
        enumerated existing IIS log root. CandidatePaths contains the discovered files.
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

    # Reject before module, registry, or filesystem discovery. Do not silently force WhatIf.
    if (-not $PSBoundParameters.ContainsKey('WhatIf') -or -not $PSBoundParameters['WhatIf']) {
        $Exception = [System.NotSupportedException]::new('IIS cleanup is preview-only. Run Clear-OldIISLog -WhatIf. Removal is not available in this version.')
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new($Exception, 'IISCleanupPreviewOnly', [System.Management.Automation.ErrorCategory]::NotImplemented, $null)
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw [System.PlatformNotSupportedException]::new('IIS log discovery requires Windows.')
    }
    Write-Warning -Message 'IIS preview only: no files will be removed. Candidate discovery is experimental, not a deletion allowlist.'

    $CutoffUtc = (Get-Date).ToUniversalTime().AddDays(-$Days)
    $Roots = [System.Collections.Generic.List[object]]::new()
    $SeenRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $WebAdministrationModule = Get-Module -Name 'WebAdministration' -ListAvailable | Select-Object -First 1

    if ($null -ne $WebAdministrationModule) {
        Import-Module -Name 'WebAdministration' -ErrorAction Stop
        foreach ($Site in @(WebAdministration\Get-Website -ErrorAction Stop)) {
            $ConfiguredRoot = [Environment]::ExpandEnvironmentVariables([string]$Site.LogFile.Directory)
            if ([string]::IsNullOrWhiteSpace($ConfiguredRoot)) {
                Write-Verbose -Message "IIS site '$($Site.Name)' has no log directory."
                continue
            }
            $RootPath = Join-Path -Path $ConfiguredRoot -ChildPath ('W3SVC{0}' -f $Site.Id)
            if ($SeenRoots.Add($RootPath)) {
                $Roots.Add([pscustomobject]@{
                        Path        = $RootPath
                        DisplayName = [string]$Site.Name
                        Source      = 'WebAdministration'
                    })
            }
        }
    } else {
        if (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
            $DefaultRoot = Join-Path -Path $env:SystemDrive -ChildPath 'inetpub/logs/LogFiles'
            if ($SeenRoots.Add($DefaultRoot)) {
                $Roots.Add([pscustomobject]@{
                        Path        = $DefaultRoot
                        DisplayName = 'Default IIS log root'
                        Source      = 'DefaultPath'
                    })
            }
        }
        try {
            $RegistryRoot = Get-ItemProperty -LiteralPath 'HKLM:\System\CurrentControlSet\Services\W3SVC\Parameters' -Name 'LogDir' -ErrorAction Stop |
                Select-Object -ExpandProperty LogDir
            $RegistryRoot = [Environment]::ExpandEnvironmentVariables([string]$RegistryRoot)
            if (-not [string]::IsNullOrWhiteSpace($RegistryRoot) -and $SeenRoots.Add($RegistryRoot)) {
                $Roots.Add([pscustomobject]@{
                        Path        = $RegistryRoot
                        DisplayName = 'Registry IIS log root'
                        Source      = 'Registry'
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
                # Access and provider failures make discovery incomplete. Surface them and honor -ErrorAction Stop.
                $PSCmdlet.WriteError($_)
            }
        }
    }

    foreach ($RootDefinition in $Roots) {
        if (-not (Test-Path -LiteralPath $RootDefinition.Path -PathType Container)) {
            Write-Verbose -Message "IIS log root not present as a directory: $($RootDefinition.Path)"
            continue
        }
        $OldFiles = @()
        try {
            $LogRoot = Resolve-TheCleanersFileSystemPath -LiteralPath $RootDefinition.Path
            if ($LogRoot -isnot [System.IO.DirectoryInfo]) {
                throw [System.IO.InvalidDataException]::new("IIS log root is not a directory: '$($RootDefinition.Path)'.")
            }
            $Pending = [System.Collections.Generic.Stack[string]]::new()
            $Pending.Push($LogRoot.FullName)
            $Candidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            while ($Pending.Count -gt 0) {
                $DirectoryPath = $Pending.Pop()
                if ($DirectoryPath -ne $LogRoot.FullName) {
                    $Directory = Resolve-TheCleanersFileSystemPath -LiteralPath $DirectoryPath -RootPath $LogRoot.FullName
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
            $null = $PSCmdlet.ShouldProcess($File.FullName, 'Preview candidate only; IIS removal is unavailable')
        }
        if ($PassThru) {
            [pscustomobject]@{
                PSTypeName              = 'TheCleaners.CleanupResult'
                Command                 = 'Clear-OldIISLog'
                RootPath                = $LogRoot.FullName
                CutoffUtc               = $CutoffUtc
                FileCandidateCount      = $OldFiles.Count
                FilesRemoved            = 0
                FileFailureCount        = 0
                FilesSkipped            = 0
                DirectoryCandidateCount = 0
                DirectoriesRemoved      = 0
                DirectoryFailureCount   = 0
                DirectoriesSkipped      = 0
                BytesReclaimed          = [Int64]0
                Status                  = 'WhatIf'
                DiscoveryStatus         = 'Experimental'
                DiscoverySource         = $RootDefinition.Source
                DisplayName             = $RootDefinition.DisplayName
                CandidatePaths          = @($OldFiles | ForEach-Object { $_.FullName })
            }
        }
    }
}

