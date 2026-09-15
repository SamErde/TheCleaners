BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    foreach ($RelativePath in @(
        'Private/ResultContracts.ps1'
        'Private/Initialize-TheCleanersNativeFileInterop.ps1'
        'Private/Get-TheCleanersTempPlan.ps1'
        'Private/Resolve-TheCleanersFileSystemPath.ps1'
        'Private/Test-TheCleanersIisLogFileName.ps1'
        'Private/Test-TheCleanersIisProtectedPath.ps1'
        'Private/Test-TheCleanersExchangeLogFileName.ps1'
        'Private/Get-TheCleanersExchangeProtectedPaths.ps1'
        'Private/Show-TheCleanersLogo.ps1'
        'Public/Get-StaleUserProfile.ps1'
    )) {
        . (Join-Path -Path $ModuleRoot -ChildPath $RelativePath)
    }
}

Describe 'Fail-closed branch contracts' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'rejects unsupported IIS and Exchange filename families and protected roots' {
        Test-TheCleanersIisLogFileName -Name 'u_ex240101.log' -Format 'W3C' -Service 'UnknownService' | Should -BeFalse
        Test-TheCleanersIisLogFileName -Name 'u_ex240101.log' -Format 'Custom' | Should -BeFalse
        Test-TheCleanersIisLogFileName -Name 'u_ex240101.log' -Format '0' | Should -BeTrue
        Test-TheCleanersIisLogFileName -Name 'inetsv01.log' -Format '1' | Should -BeTrue
        Test-TheCleanersIisLogFileName -Name 'ncsa01.log' -Format '2' | Should -BeTrue
        Test-TheCleanersExchangeLogFileName -Name 'old.log' -RelativeRoot 'UnknownRoot' | Should -BeFalse
        Test-TheCleanersIisProtectedPath -Path (Join-Path -Path $TestDrive -ChildPath 'ordinary-logs') | Should -BeFalse
    }

    It 'fails closed when Exchange returns a path object without a PathName' {
        $InstallRoot = New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'ExchangeRoot') -ItemType Directory -Force
        function global:Get-MailboxDatabase { }
        Mock Get-Command { [pscustomobject]@{ Name = 'Get-MailboxDatabase' } } -ParameterFilter { $Name -eq 'Get-MailboxDatabase' }
        Mock Get-MailboxDatabase {
            [pscustomobject]@{
                EdbFilePath   = [pscustomobject]@{ Unexpected = 'not-a-path' }
                LogFolderPath = $null
            }
        }

        try {
            { Get-TheCleanersExchangeProtectedPaths -InstallRoot $InstallRoot } | Should -Throw '*non-qualified protected path*'
        } finally {
            Remove-Item -LiteralPath 'Function:\global:Get-MailboxDatabase' -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed when identity capture fails during discovery' {
        $RootPath = Join-Path -Path $TestDrive -ChildPath 'IdentityFailureRoot'
        $ChildPath = Join-Path -Path $RootPath -ChildPath 'Child'
        $GrandchildPath = Join-Path -Path $ChildPath -ChildPath 'Grandchild'
        $null = New-Item -Path $GrandchildPath -ItemType Directory -Force
        $FilePath = Join-Path -Path $GrandchildPath -ChildPath 'old.tmp'
        $null = New-Item -Path $FilePath -ItemType File -Force
        [System.IO.File]::SetLastWriteTimeUtc($FilePath, [DateTime]::UtcNow.AddDays(-31))
        $Root = Resolve-TheCleanersFileSystemPath -LiteralPath $RootPath
        $RootIdentity = Get-TheCleanersFileIdentity -LiteralPath $RootPath -Directory

        Mock Get-TheCleanersFileIdentity {
            if ($LiteralPath -eq $RootPath) {
                return $RootIdentity
            }
            throw [System.UnauthorizedAccessException]::new('Identity fixture denial.')
        }

        { Get-TheCleanersTempPlan -Root $Root -CutoffUtc ([DateTime]::UtcNow.AddDays(-30)) -RemoveEmptyDirectory -CaptureIdentity -Verbose 4> $null } | Should -Throw '*identity required for safe mutation*'
    }

    It 'fails closed when a parent identity cannot be captured for directory pruning' {
        $RootPath = Join-Path -Path $TestDrive -ChildPath 'ParentIdentityFailureRoot'
        $ChildPath = Join-Path -Path $RootPath -ChildPath 'Child'
        $null = New-Item -Path $ChildPath -ItemType Directory -Force
        $FilePath = Join-Path -Path $ChildPath -ChildPath 'old.tmp'
        $null = New-Item -Path $FilePath -ItemType File -Force
        [System.IO.File]::SetLastWriteTimeUtc($FilePath, [DateTime]::UtcNow.AddDays(-31))
        $Root = Resolve-TheCleanersFileSystemPath -LiteralPath $RootPath
        $RootIdentity = Get-TheCleanersFileIdentity -LiteralPath $RootPath -Directory
        $CandidateIdentity = Get-TheCleanersFileIdentity -LiteralPath $FilePath

        Mock Get-TheCleanersFileIdentity {
            if ($LiteralPath -eq $RootPath) {
                return $RootIdentity
            }
            if ($LiteralPath -eq $FilePath) {
                return $CandidateIdentity
            }
            throw [System.UnauthorizedAccessException]::new('Parent identity fixture denial.')
        }

        { Get-TheCleanersTempPlan -Root $Root -CutoffUtc ([DateTime]::UtcNow.AddDays(-30)) -RemoveEmptyDirectory -CaptureIdentity } | Should -Throw '*parent identity required for safe directory pruning*'
    }

    It 'skips a candidate that disappears during identity capture' {
        $RootPath = Join-Path -Path $TestDrive -ChildPath 'DisappearingIdentityRoot'
        $null = New-Item -Path $RootPath -ItemType Directory -Force
        $FilePath = Join-Path -Path $RootPath -ChildPath 'old.tmp'
        $null = New-Item -Path $FilePath -ItemType File -Force
        [System.IO.File]::SetLastWriteTimeUtc($FilePath, [DateTime]::UtcNow.AddDays(-31))
        $Root = Resolve-TheCleanersFileSystemPath -LiteralPath $RootPath
        $RootIdentity = Get-TheCleanersFileIdentity -LiteralPath $RootPath -Directory

        Mock Get-TheCleanersFileIdentity {
            if ($LiteralPath -eq $RootPath) {
                return $RootIdentity
            }
            throw [System.Management.Automation.ItemNotFoundException]::new('Candidate disappeared.')
        }

        $Plan = Get-TheCleanersTempPlan -Root $Root -CutoffUtc ([DateTime]::UtcNow.AddDays(-30)) -CaptureIdentity -Verbose 4> $null

        $Plan.Files | Should -BeNullOrEmpty
    }

    It 'rejects a reparse-point cleanup root before planning' {
        $OutsidePath = Join-Path -Path $TestDrive -ChildPath 'OutsideRoot'
        $LinkPath = Join-Path -Path $TestDrive -ChildPath 'ReparseRoot'
        $null = New-Item -Path $OutsidePath -ItemType Directory -Force
        $null = New-Item -Path $LinkPath -ItemType Junction -Target $OutsidePath -Force
        $Root = Get-Item -LiteralPath $LinkPath -Force

        { Get-TheCleanersTempPlan -Root $Root -CutoffUtc ([DateTime]::UtcNow.AddDays(-30)) -CaptureIdentity } | Should -Throw '*reparse point*'
    }

    It 'rejects a reparse point while validating a descendant path' {
        $OutsidePath = Join-Path -Path $TestDrive -ChildPath 'OutsidePath'
        $LinkPath = Join-Path -Path $TestDrive -ChildPath 'ReparsePath'
        $null = New-Item -Path $OutsidePath -ItemType Directory -Force
        $null = New-Item -Path $LinkPath -ItemType Junction -Target $OutsidePath -Force

        { Resolve-TheCleanersFileSystemPath -LiteralPath $LinkPath } | Should -Throw '*reparse point*'
    }

    It 'normalizes extended UNC paths for comparison' {
        Convert-TheCleanersPathForComparison -Path '\\?\UNC\server\share\folder' | Should -Be '\\server\share\folder'
    }

    It 'normalizes an extended-length path without a legacy MAX_PATH call' {
        $Segments = @()
        for ($Index = 0; $Index -lt 24; $Index++) {
            $Segments += ('segment{0:D2}abcdefgh' -f $Index)
        }
        $ExtendedPath = '\\?\C:\' + ($Segments -join '\')

        $ComparablePath = Convert-TheCleanersPathForComparison -Path $ExtendedPath

        $ComparablePath | Should -Be ('C:\' + ($Segments -join '\'))
        Convert-TheCleanersPathForComparison -Path '\\?\C:\segment00abcdefgh\segment01abcdefgh\..\segment02abcdefgh' | Should -Be 'C:\segment00abcdefgh\segment02abcdefgh'
    }

    It 'covers string profile timestamps, unresolved SIDs, nested size, and reparse skipping' {
        $Now = [DateTime]::UtcNow
        $ProfilePath = Join-Path -Path $TestDrive -ChildPath 'StringDateProfile'
        $NestedPath = Join-Path -Path $ProfilePath -ChildPath 'Nested'
        $OutsidePath = Join-Path -Path $TestDrive -ChildPath 'ProfileOutside'
        $null = New-Item -Path $NestedPath -ItemType Directory -Force
        $null = New-Item -Path $OutsidePath -ItemType Directory -Force
        $SizeFile = Join-Path -Path $NestedPath -ChildPath 'profile.bin'
        $OutsideFile = Join-Path -Path $OutsidePath -ChildPath 'outside.bin'
        [System.IO.File]::WriteAllBytes($SizeFile, [byte[]](1, 2, 3, 4))
        [System.IO.File]::WriteAllBytes($OutsideFile, [byte[]](5, 6, 7, 8, 9))
        $null = New-Item -Path (Join-Path -Path $ProfilePath -ChildPath 'LinkedOutside') -ItemType Junction -Target $OutsidePath -Force
        $DmtfTime = [System.Management.ManagementDateTimeConverter]::ToDmtfDateTime($Now.AddDays(-91))

        Mock Get-Date { $Now }
        Mock Get-CimInstance {
            [pscustomobject]@{
                LocalPath   = $ProfilePath
                SID         = 'not-a-valid-sid'
                LastUseTime = $DmtfTime
                Special     = $false
                Loaded      = $false
            }
        }

        $Result = Get-StaleUserProfile -Days 90 -IncludeSize

        $Result.DateStatus | Should -Be 'Known'
        $Result.AccountResolutionStatus | Should -Be 'Unresolved'
        $Result.SizeStatus | Should -Be 'Available'
        $Result.SizeBytes | Should -Be 4
    }

    It 'handles malformed profile timestamps and a resolvable current-user SID' {
        $Now = [DateTime]::UtcNow
        $ProfilePath = Join-Path -Path $TestDrive -ChildPath 'MalformedDateProfile'
        $null = New-Item -Path $ProfilePath -ItemType Directory -Force
        $CurrentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        Mock Get-Date { $Now }
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{
                    LocalPath   = $ProfilePath
                    SID         = $CurrentSid
                    LastUseTime = 'not-a-dmtf-time'
                    Special     = $false
                    Loaded      = $false
                }
                [pscustomobject]@{
                    LocalPath   = $ProfilePath
                    SID         = $CurrentSid
                    LastUseTime = $Now.AddDays(-91)
                    Special     = $false
                    Loaded      = $false
                }
            )
        }

        $Result = @(Get-StaleUserProfile -Days 90 -IncludeUnknownLastUseTime)

        $Result | Should -HaveCount 2
        ($Result | Where-Object DateStatus -EQ 'Unknown').AccountResolutionStatus | Should -Be 'Resolved'
        ($Result | Where-Object DateStatus -EQ 'Known').AccountResolutionStatus | Should -Be 'Resolved'
    }

    It 'reports an unavailable profile size when traversal fails' {
        $Now = [DateTime]::UtcNow
        $ProfilePath = Join-Path -Path $TestDrive -ChildPath 'UnavailableSizeProfile'
        $null = New-Item -Path $ProfilePath -ItemType Directory -Force
        Mock Get-Date { $Now }
        Mock Get-CimInstance {
            [pscustomobject]@{
                LocalPath   = $ProfilePath
                SID         = 'not-a-valid-sid'
                LastUseTime = $Now.AddDays(-91)
                Special     = $false
                Loaded      = $false
            }
        }
        Mock Get-ChildItem { throw [System.UnauthorizedAccessException]::new('Size fixture denial.') }

        $Result = Get-StaleUserProfile -Days 90 -IncludeSize -ErrorAction SilentlyContinue -ErrorVariable SizeError

        $Result.SizeStatus | Should -Be 'Unavailable'
        $Result.SizeBytes | Should -BeNullOrEmpty
        @($SizeError | Where-Object { $_.FullyQualifiedErrorId -match '^ProfileSizeUnavailable' }) | Should -Not -BeNullOrEmpty
    }

    It 'renders the explicit logo path without affecting import output' {
        Show-TheCleanersLogo -Plain | Should -Match 'v'
        Show-TheCleanersLogo | Out-Null
    }

    It 'covers the public inventory logo and dedication paths' {
        $ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'TheCleaners.psd1'
        Import-Module -Name $ManifestPath -Force
        $Inventory = @(Get-TheCleaners -Dedication)
        $Inventory | Should -HaveCount 6
        Remove-Module -Name TheCleaners -Force
    }
}
