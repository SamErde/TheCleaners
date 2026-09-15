BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/ResultContracts.ps1')
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
            )
        }
    }

    It 'returns typed stable fields and excludes unknown/default/loaded profiles by default' {
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

    It 'does not write host presentation output or depend on orphaned SID helpers' {
        $FunctionPath = Join-Path -Path $ModuleRoot -ChildPath 'Public/Get-StaleUserProfile.ps1'
        [System.IO.File]::ReadAllText($FunctionPath) | Should -Not -Match 'Out-Host'
        (Test-Path -LiteralPath (Join-Path -Path $ModuleRoot -ChildPath 'Private/Convert-SIDtoSamAccountName.ps1')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path -Path $ModuleRoot -ChildPath 'Private/Convert-SamAccountNameToSID.ps1')) | Should -BeFalse
    }
}
