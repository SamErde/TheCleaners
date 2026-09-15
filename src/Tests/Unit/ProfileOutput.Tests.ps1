BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/ResultContracts.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Initialize-TheCleanersNativeFileInterop.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public/Get-StaleUserProfile.ps1')
}

Describe 'Typed stale-profile output' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $Now = [DateTime]::UtcNow
        $OldProfilePath = Join-Path -Path $TestDrive -ChildPath 'OldUser'
        $UnknownProfilePath = Join-Path -Path $TestDrive -ChildPath 'UnknownUser'
        $DefaultProfilePath = Join-Path -Path $TestDrive -ChildPath 'Default'
        $null = New-Item -Path $OldProfilePath -ItemType Directory -Force
        $null = New-Item -Path $UnknownProfilePath -ItemType Directory -Force
        $null = New-Item -Path $DefaultProfilePath -ItemType Directory -Force
        $SizeFilePath = Join-Path -Path $OldProfilePath -ChildPath 'profile.bin'
        $null = New-Item -Path $SizeFilePath -ItemType File -Force
        [System.IO.File]::WriteAllBytes($SizeFilePath, [byte[]](1, 2, 3))

        Mock Get-Date { $Now }
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{
                    LocalPath  = $OldProfilePath
                    SID        = 'S-1-5-21-1000'
                    LastUseTime = $Now.AddDays(-91)
                    Special    = $false
                    Loaded     = $false
                }
                [pscustomobject]@{
                    LocalPath  = $UnknownProfilePath
                    SID        = 'S-1-5-21-1001'
                    LastUseTime = $null
                    Special    = $false
                    Loaded     = $false
                }
                [pscustomobject]@{
                    LocalPath  = $DefaultProfilePath
                    SID        = 'S-1-5-21-1002'
                    LastUseTime = $Now.AddDays(-91)
                    Special    = $false
                    Loaded     = $false
                }
                [pscustomobject]@{
                    LocalPath  = (Join-Path -Path $TestDrive -ChildPath 'LoadedUser')
                    SID        = 'S-1-5-21-1003'
                    LastUseTime = $Now.AddDays(-91)
                    Special    = $false
                    Loaded     = $true
                }
                [pscustomobject]@{
                    LocalPath  = (Join-Path -Path $TestDrive -ChildPath 'VirtualService')
                    SID        = 'S-1-5-80-0-0-0-0-12345'
                    LastUseTime = $Now.AddDays(-91)
                    Special    = $false
                    Loaded     = $false
                }
                [pscustomobject]@{
                    LocalPath  = (Join-Path -Path $TestDrive -ChildPath 'IISAppPool')
                    SID        = 'S-1-5-82-0-0-0-0-54321'
                    LastUseTime = $Now.AddDays(-91)
                    Special    = $false
                    Loaded     = $false
                }
            )
        }
    }

    It 'returns typed stable fields and excludes unknown/default/loaded/service profiles by default' {
        $Result = Get-StaleUserProfile -Days 90

        $Result | Should -HaveCount 1
        $Result.PSTypeNames | Should -Contain 'TheCleaners.StaleUserProfile'
        $Result.ContractVersion | Should -Be '1.0'
        $Result.LocalPath | Should -Be $OldProfilePath
        $Result.DateStatus | Should -Be 'Known'
        $Result.IsStale | Should -BeTrue
        $Result.AccountResolutionStatus | Should -BeIn @('Resolved', 'Unresolved')
        $Result.SizeStatus | Should -Be 'NotRequested'
        $Result.PSObject.Properties.Name | Should -Contain 'IsSystem'
    }

    It 'can include an unknown LastUseTime without misclassifying it as stale' {
        $Result = @(Get-StaleUserProfile -Days 90 -IncludeUnknownLastUseTime)

        $Result | Should -HaveCount 2
        $Unknown = $Result | Where-Object LocalPath -EQ $UnknownProfilePath
        $Unknown.DateStatus | Should -Be 'Unknown'
        $Unknown.LastUseTimeUtc | Should -BeNullOrEmpty
        $Unknown.IsStale | Should -BeFalse
    }

    It 'reports optional logical size without following reparse points' {
        $Result = Get-StaleUserProfile -Days 90 -IncludeSize

        $Result.SizeStatus | Should -Be 'Available'
        $Result.SizeBytes | Should -Be 3
    }

    It 'does not size a reparse-point profile root' {
        $OutsidePath = Join-Path -Path $TestDrive -ChildPath 'OutsideProfileRoot'
        $ReparseProfilePath = Join-Path -Path $TestDrive -ChildPath 'ReparseProfileRoot'
        $null = New-Item -Path $OutsidePath -ItemType Directory -Force
        $null = New-Item -Path $ReparseProfilePath -ItemType Junction -Target $OutsidePath -Force
        Mock Get-CimInstance {
            [pscustomobject]@{
                LocalPath   = $ReparseProfilePath
                SID         = 'S-1-5-21-1004'
                LastUseTime = (Get-Date).AddDays(-91)
                Special     = $false
                Loaded      = $false
            }
        }

        $Result = Get-StaleUserProfile -Days 90 -IncludeSize -ErrorAction SilentlyContinue -ErrorVariable SizeError

        $Result.SizeStatus | Should -Be 'Unavailable'
        $Result.SizeBytes | Should -BeNullOrEmpty
        @($SizeError | Where-Object { $_.FullyQualifiedErrorId -match '^ProfileSizeUnavailable' }) | Should -Not -BeNullOrEmpty
    }

    It 'does not size a profile below a reparse-point ancestor' {
        $OutsideParent = Join-Path -Path $TestDrive -ChildPath 'OutsideProfileParent'
        $ReparseParent = Join-Path -Path $TestDrive -ChildPath 'ReparseProfileParent'
        $ProfileThroughLink = Join-Path -Path $ReparseParent -ChildPath 'NestedProfile'
        $null = New-Item -Path (Join-Path -Path $OutsideParent -ChildPath 'NestedProfile') -ItemType Directory -Force
        $null = New-Item -Path $ReparseParent -ItemType Junction -Target $OutsideParent -Force
        Mock Get-CimInstance {
            [pscustomobject]@{
                LocalPath   = $ProfileThroughLink
                SID         = 'S-1-5-21-1005'
                LastUseTime = (Get-Date).AddDays(-91)
                Special     = $false
                Loaded      = $false
            }
        }

        $Result = Get-StaleUserProfile -Days 90 -IncludeSize -ErrorAction SilentlyContinue -ErrorVariable SizeError

        $Result.SizeStatus | Should -Be 'Unavailable'
        $Result.SizeBytes | Should -BeNullOrEmpty
        @($SizeError | Where-Object { $_.FullyQualifiedErrorId -match '^ProfileSizeUnavailable' }) | Should -Not -BeNullOrEmpty
    }

    It 'fails closed when a queued directory becomes a reparse point before traversal' {
        $QueuedDirectoryPath = Join-Path -Path $OldProfilePath -ChildPath 'QueuedDirectory'
        $OutsidePath = Join-Path -Path $TestDrive -ChildPath 'ReplacementTarget'
        $null = New-Item -Path $QueuedDirectoryPath -ItemType Directory -Force
        $null = New-Item -Path $OutsidePath -ItemType Directory -Force
        $null = New-Item -Path (Join-Path -Path $OutsidePath -ChildPath 'outside.bin') -ItemType File -Force
        Mock Get-CimInstance {
            [pscustomobject]@{
                LocalPath   = $OldProfilePath
                SID         = 'S-1-5-21-1006'
                LastUseTime = (Get-Date).AddDays(-91)
                Special     = $false
                Loaded      = $false
            }
        }
        Mock Get-ChildItem {
            [System.IO.Directory]::Delete($QueuedDirectoryPath)
            $null = Microsoft.PowerShell.Management\New-Item -Path $QueuedDirectoryPath -ItemType Junction -Target $OutsidePath -Force
            return @([pscustomobject]@{
                    FullName      = $QueuedDirectoryPath
                    Name          = 'QueuedDirectory'
                    PSIsContainer = $true
                    Attributes    = [System.IO.FileAttributes]::Directory
                })
        }

        $Result = Get-StaleUserProfile -Days 90 -IncludeSize -ErrorAction SilentlyContinue -ErrorVariable SizeError

        Should -Invoke Get-ChildItem -Exactly 1
        $Replacement = Get-Item -LiteralPath $QueuedDirectoryPath -Force
        (($Replacement.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) | Should -BeTrue
        $Result.SizeStatus | Should -Be 'Unavailable'
        $Result.SizeBytes | Should -BeNullOrEmpty
        @($SizeError | Where-Object { $_.FullyQualifiedErrorId -match '^ProfileSizeUnavailable' }) | Should -Not -BeNullOrEmpty
    }

    It 'holds the directory identity while enumerating' {
        $ReplacementPath = Join-Path -Path $TestDrive -ChildPath 'ProfileReplacement'
        Mock Get-CimInstance {
            [pscustomobject]@{
                LocalPath   = $OldProfilePath
                SID         = 'S-1-5-21-1007'
                LastUseTime = (Get-Date).AddDays(-91)
                Special     = $false
                Loaded      = $false
            }
        }
        $script:MoveBlocked = $false
        Mock Get-ChildItem {
            try {
                [System.IO.Directory]::Move($OldProfilePath, $ReplacementPath)
            } catch {
                $script:MoveBlocked = $true
            }
            return @()
        }

        $Result = Get-StaleUserProfile -Days 90 -IncludeSize -ErrorAction SilentlyContinue

        $script:MoveBlocked | Should -BeTrue
        $Result.SizeStatus | Should -Be 'Available'
        $Result.SizeBytes | Should -Be 0
    }

    It 'holds profile ancestors while traversing queued directories' {
        $QueuedDirectoryPath = Join-Path -Path $OldProfilePath -ChildPath 'QueuedSizeDirectory'
        $ReplacementPath = Join-Path -Path $TestDrive -ChildPath 'ProfileQueuedReplacement'
        $null = New-Item -Path $QueuedDirectoryPath -ItemType Directory -Force
        Mock Get-CimInstance {
            [pscustomobject]@{
                LocalPath   = $OldProfilePath
                SID         = 'S-1-5-21-1008'
                LastUseTime = (Get-Date).AddDays(-91)
                Special     = $false
                Loaded      = $false
            }
        }
        $script:MoveBlocked = $false
        Mock Get-ChildItem {
            if ($LiteralPath -eq $OldProfilePath) {
                return @([pscustomobject]@{
                        FullName      = $QueuedDirectoryPath
                        Name          = 'QueuedSizeDirectory'
                        PSIsContainer = $true
                        Attributes    = [System.IO.FileAttributes]::Directory
                    })
            }
            if ($LiteralPath -eq $QueuedDirectoryPath) {
                try {
                    [System.IO.Directory]::Move($OldProfilePath, $ReplacementPath)
                } catch {
                    $script:MoveBlocked = $true
                }
                return @()
            }
            throw "Unexpected profile traversal path: $LiteralPath"
        }

        $Result = Get-StaleUserProfile -Days 90 -IncludeSize -ErrorAction SilentlyContinue

        $script:MoveBlocked | Should -BeTrue
        $Result.SizeStatus | Should -Be 'Available'
        $Result.SizeBytes | Should -Be 0
    }

    It 'does not write host presentation output or depend on orphaned SID helpers' {
        $FunctionPath = Join-Path -Path $ModuleRoot -ChildPath 'Public/Get-StaleUserProfile.ps1'
        [System.IO.File]::ReadAllText($FunctionPath) | Should -Not -Match 'Out-Host'
        (Test-Path -LiteralPath (Join-Path -Path $ModuleRoot -ChildPath 'Private/Convert-SIDtoSamAccountName.ps1')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path -Path $ModuleRoot -ChildPath 'Private/Convert-SamAccountNameToSID.ps1')) | Should -BeFalse
    }
}
