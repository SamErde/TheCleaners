BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners'
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/ResultContracts.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Initialize-TheCleanersNativeFileInterop.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public/Get-StaleUserProfile.ps1')
}

Describe 'Profile failure branches' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'reports a CIM failure instead of returning an apparently empty inventory' {
        Mock Get-CimInstance { throw [System.UnauthorizedAccessException]::new('Fixture CIM denial.') }

        $Result = @(Get-StaleUserProfile -ErrorAction SilentlyContinue -ErrorVariable Failure)

        $Result | Should -HaveCount 0
        $Reported = @($Failure | Where-Object FullyQualifiedErrorId -Like 'ProfileQueryFailed,*')
        $Reported | Should -HaveCount 1
        [string]$Reported[0].CategoryInfo.Category | Should -Be 'ReadError'
        { Get-StaleUserProfile -ErrorAction Stop } | Should -Throw -ErrorId 'ProfileQueryFailed,*'
    }

    It 'leaves an invalid date unknown and retains an unresolvable SID' {
        Mock Get-CimInstance {
            [pscustomobject]@{
                LocalPath = ''; SID = 'invalid-sid'; LastUseTime = 'invalid-date'
                Special = $false; Loaded = $false
            }
        }

        @(Get-StaleUserProfile) | Should -HaveCount 0
        $Result = Get-StaleUserProfile -IncludeUnknownLastUseTime -IncludeSize -ErrorAction Stop

        $Result.DateStatus | Should -Be 'Unknown'
        $Result.IsStale | Should -BeFalse
        $Result.LastUseTimeUtc | Should -BeNullOrEmpty
        $Result.AgeDays | Should -BeNullOrEmpty
        $Result.SID | Should -Be 'invalid-sid'
        $Result.Account | Should -BeNullOrEmpty
        $Result.AccountResolutionStatus | Should -Be 'Unresolved'
        $Result.SizeStatus | Should -Be 'Unavailable'
        $Result.SizeBytes | Should -BeNullOrEmpty
    }

    It 'reports a file substituted for a profile directory as unavailable size' {
        $ProfilePath = Join-Path -Path $TestDrive -ChildPath 'profile-file'
        [System.IO.File]::WriteAllText($ProfilePath, 'preserved')
        Mock Get-CimInstance {
            [pscustomobject]@{
                LocalPath = $ProfilePath; SID = 'invalid-sid'; LastUseTime = [DateTime]::UtcNow.AddDays(-100)
                Special = $false; Loaded = $false
            }
        }

        $Result = Get-StaleUserProfile -IncludeSize -ErrorAction SilentlyContinue -ErrorVariable Failure

        $Result.SizeStatus | Should -Be 'Unavailable'
        $Result.SizeBytes | Should -BeNullOrEmpty
        @($Failure | Where-Object FullyQualifiedErrorId -Like 'ProfileSizeUnavailable,*') | Should -HaveCount 1
        { Get-StaleUserProfile -IncludeSize -ErrorAction Stop } | Should -Throw -ErrorId 'ProfileSizeUnavailable,*'
        [System.IO.File]::ReadAllText($ProfilePath) | Should -Be 'preserved'
    }
}
