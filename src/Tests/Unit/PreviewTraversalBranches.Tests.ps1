BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $PreviewCases = @(
        @{ CommandName = 'Clear-OldExchangeLog'; LogName = 'old.log'; ChildName = 'Nested' }
        @{ CommandName = 'Clear-OldIISLog'; LogName = 'u_ex240101.log'; ChildName = 'W3SVC1' }
    )
}

BeforeAll {
    $ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners'
    foreach ($RelativePath in @(
        'Private/ResultContracts.ps1'
        'Private/Resolve-TheCleanersFileSystemPath.ps1'
        'Private/Test-TheCleanersExchangeLogFileName.ps1'
        'Private/Get-TheCleanersExchangeProtectedPaths.ps1'
        'Private/Test-TheCleanersIisLogFileName.ps1'
        'Private/Test-TheCleanersIisProtectedPath.ps1'
        'Public/Clear-OldExchangeLog.ps1'
        'Public/Clear-OldIISLog.ps1'
    )) {
        . (Join-Path -Path $ModuleRoot -ChildPath $RelativePath)
    }
}

Describe 'Preview traversal boundaries: <CommandName>' -ForEach $PreviewCases -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousSystemDrive = $env:SystemDrive
        $env:SystemDrive = ''
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $InstallRoot = Join-Path -Path $FixtureRoot -ChildPath 'Product'
        $LogRoot = Join-Path -Path $InstallRoot -ChildPath 'Logging'
        $ChildRoot = Join-Path -Path $LogRoot -ChildPath $ChildName
        $OutsideRoot = Join-Path -Path $FixtureRoot -ChildPath 'Outside'
        $null = New-Item -Path $ChildRoot, $OutsideRoot -ItemType Directory -Force
        $CandidatePath = Join-Path -Path $ChildRoot -ChildPath $LogName
        $OutsidePath = Join-Path -Path $OutsideRoot -ChildPath $LogName
        foreach ($Path in @($CandidatePath, $OutsidePath)) {
            [System.IO.File]::WriteAllText($Path, 'preserved')
            [System.IO.File]::SetLastWriteTimeUtc($Path, [DateTime]::UtcNow.AddDays(-61))
        }
        Mock Get-ItemProperty {
            [pscustomobject]@{ MsiInstallPath = $InstallRoot; LogDir = $LogRoot; LogFormat = 'W3C'; LocalTimeRollover = $false }
        }
        Mock Get-Module { $null } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
        Mock Get-TheCleanersExchangeProtectedPaths { [pscustomobject]@{ Status = 'Validated'; Paths = @() } }
    }

    AfterEach {
        $env:SystemDrive = $PreviousSystemDrive
    }

    It 'previews nested allowlisted files without following a junction' {
        $LinkPath = Join-Path -Path $LogRoot -ChildPath 'OutsideLink'
        $null = New-Item -Path $LinkPath -ItemType Junction -Target $OutsideRoot

        $Results = @(& $CommandName -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop)

        $Results | Should -HaveCount 1
        $Results[0].CandidatePaths | Should -HaveCount 1
        $Results[0].CandidatePaths | Should -Contain $CandidatePath
        $Results[0].FileCandidateCount | Should -Be 1
        $Results[0].FilesRemoved | Should -Be 0
        $Results[0].Status | Should -Be 'WhatIf'
        [System.IO.File]::ReadAllText($CandidatePath) | Should -Be 'preserved'
        [System.IO.File]::ReadAllText($OutsidePath) | Should -Be 'preserved'
        $LinkPath | Should -Exist
    }

    It 'discards partial candidates when nested enumeration fails' {
        $TopLevelPath = Join-Path -Path $LogRoot -ChildPath $LogName
        [System.IO.File]::WriteAllText($TopLevelPath, 'preserved')
        [System.IO.File]::SetLastWriteTimeUtc($TopLevelPath, [DateTime]::UtcNow.AddDays(-61))
        Mock Get-ChildItem { throw [System.UnauthorizedAccessException]::new('Fixture nested preview denial.') } -ParameterFilter { $LiteralPath -eq $ChildRoot }

        $Results = @(& $CommandName -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Failure)

        $Results | Should -HaveCount 1
        $Results[0].Status | Should -Be 'DiscoveryFailed'
        $Results[0].FileCandidateCount | Should -BeNullOrEmpty
        $Results[0].CandidatePaths | Should -HaveCount 0
        $ExpectedError = if ($CommandName -eq 'Clear-OldExchangeLog') { 'ExchangeDiscoveryFailed' } else { 'IISDiscoveryFailed' }
        $Results[0].ErrorIds | Should -Contain $ExpectedError
        @($Failure | Where-Object { $_.FullyQualifiedErrorId -like "$ExpectedError,*" }) | Should -HaveCount 1
        { & $CommandName -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw -ErrorId "$ExpectedError,*"
        [System.IO.File]::ReadAllText($TopLevelPath) | Should -Be 'preserved'
        [System.IO.File]::ReadAllText($CandidatePath) | Should -Be 'preserved'
    }
}

Describe 'Exchange missing metadata branches' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'fails before filesystem discovery when the installation value is blank' {
        Mock Get-ItemProperty { [pscustomobject]@{ MsiInstallPath = ' ' } }
        Mock Resolve-TheCleanersFileSystemPath { throw 'Filesystem discovery must not start.' }

        $Result = Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Failure

        $Result.Status | Should -Be 'DiscoveryFailed'
        $Result.FileCandidateCount | Should -BeNullOrEmpty
        $Result.ErrorIds | Should -Contain 'ExchangeRegistryDiscoveryFailed'
        @($Failure | Where-Object FullyQualifiedErrorId -Like 'ExchangeRegistryDiscoveryFailed,*') | Should -HaveCount 1
        { Clear-OldExchangeLog -WhatIf -WarningAction SilentlyContinue } | Should -Throw -ErrorId 'ExchangeRegistryDiscoveryFailed,*'
        Should -Invoke Resolve-TheCleanersFileSystemPath -Exactly 0
    }

    It 'terminates on failed protection discovery even without PassThru' {
        $InstallRoot = New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'Install') -ItemType Directory
        Mock Get-ItemProperty { [pscustomobject]@{ MsiInstallPath = $InstallRoot.FullName } }
        Mock Get-TheCleanersExchangeProtectedPaths { throw [System.UnauthorizedAccessException]::new('Fixture protection denial.') }
        Mock Get-ChildItem { throw 'Log discovery must not start.' }

        { Clear-OldExchangeLog -WhatIf -WarningAction SilentlyContinue } | Should -Throw -ErrorId 'ExchangeProtectedPathDiscoveryFailed,*'

        Should -Invoke Get-ChildItem -Exactly 0
    }
}

