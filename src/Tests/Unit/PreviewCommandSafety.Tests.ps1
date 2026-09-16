BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    foreach ($RelativePath in @(
        'Private/ResultContracts.ps1'
        'Private/Initialize-TheCleanersNativeFileInterop.ps1'
        'Private/Get-TheCleanersWindowsTempRoot.ps1'
        'Private/Get-TheCleanersTempPlan.ps1'
        'Private/Resolve-TheCleanersFileSystemPath.ps1'
        'Private/Test-TheCleanersIisLogFileName.ps1'
        'Private/Test-TheCleanersIisProtectedPath.ps1'
        'Private/Test-TheCleanersExchangeLogFileName.ps1'
        'Private/Get-TheCleanersExchangeProtectedPaths.ps1'
        'Public/Clear-OldIISLog.ps1'
        'Public/Clear-OldExchangeLog.ps1'
    )) {
        . (Join-Path -Path $ModuleRoot -ChildPath $RelativePath)
    }
}

Describe 'Exchange preview root validation' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $ExchangeRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $LogRoot = Join-Path -Path $ExchangeRoot -ChildPath 'Logging'
        $null = New-Item -Path $LogRoot -ItemType Directory -Force
        Mock Get-ItemProperty { [pscustomobject]@{ MsiInstallPath = $ExchangeRoot } }
    }

    It 'reports an unavailable product when every expected log root is unusable' {
        [System.IO.Directory]::Delete($LogRoot)
        $RootFile = New-Item -Path $LogRoot -ItemType File

        $Result = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

        $Result | Should -HaveCount 1
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].ErrorIds | Should -Contain 'ExchangeDiscoveryUnavailable'
        $RootFile.FullName | Should -Exist
    }

    It 'rejects an installation path that is not a directory' {
        $InstallFile = New-Item -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)) -ItemType File
        Mock Get-ItemProperty { [pscustomobject]@{ MsiInstallPath = $InstallFile.FullName } }

        { Clear-OldExchangeLog -WhatIf -WarningAction SilentlyContinue } | Should -Throw '*not a directory*'
    }

    It 'returns a failed result when installation-root validation fails' {
        $InstallFile = New-Item -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)) -ItemType File
        Mock Get-ItemProperty { [pscustomobject]@{ MsiInstallPath = $InstallFile.FullName } }

        $Result = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Continue -ErrorVariable RootError)

        $Result | Should -HaveCount 1
        $Result[0].RootPath | Should -Be $InstallFile.FullName
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].DirectoryCandidateCount | Should -BeNullOrEmpty
        $Result[0].DiscoveryErrorCount | Should -Be 1
        $Result[0].ErrorIds | Should -Contain 'ExchangeInstallRootValidationFailed'
        $RootError | Should -Not -BeNullOrEmpty
        { Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw '*not a directory*'
    }

    It 'returns a failed result when Exchange protection discovery fails' {
        Mock Get-TheCleanersExchangeProtectedPaths { throw [System.UnauthorizedAccessException]::new('Fixture Exchange protection access denied.') }

        $Result = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Continue -ErrorVariable ProtectionError)

        $Result | Should -HaveCount 1
        $Result[0].RootPath | Should -Be $ExchangeRoot
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].DirectoryCandidateCount | Should -BeNullOrEmpty
        $Result[0].DiscoveryErrorCount | Should -Be 1
        $Result[0].ErrorIds | Should -Contain 'ExchangeProtectedPathDiscoveryFailed'
        $ProtectionError | Should -Not -BeNullOrEmpty
        { Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw '*protection access denied*'
    }

    It 'returns a failed result when Exchange registry discovery fails' {
        $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup'
        Mock Get-ItemProperty { throw [System.UnauthorizedAccessException]::new('Fixture Exchange registry access denied.') }

        $Result = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Continue -ErrorVariable RegistryError)

        $Result | Should -HaveCount 1
        $Result[0].RootPath | Should -Be $RegistryPath
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].DirectoryCandidateCount | Should -BeNullOrEmpty
        $Result[0].DiscoveryErrorCount | Should -Be 1
        $Result[0].ErrorIds | Should -Contain 'ExchangeRegistryDiscoveryFailed'
        $RegistryError | Should -Not -BeNullOrEmpty
    }

    It 'does not expose a removal-bypass parameter' {
        $CommandParameters = (Get-Command -Name Clear-OldExchangeLog -CommandType Function).Parameters
        foreach ($ParameterName in @('Force', 'AllowRemoval', 'EnableRemoval')) {
            $CommandParameters.ContainsKey($ParameterName) | Should -BeFalse
        }
    }
}

Describe 'IIS structural preview lock' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousSystemDrive = $env:SystemDrive
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $IISRoot = Join-Path -Path $FixtureRoot -ChildPath 'inetpub/logs/LogFiles'
        $null = New-Item -Path $IISRoot -ItemType Directory -Force
        $OldLog = New-Item -Path (Join-Path -Path $IISRoot -ChildPath 'u_ex240101.log') -ItemType File
        $OldLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $env:SystemDrive = $FixtureRoot
        Mock Get-Module { $null } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
        Mock Get-ItemProperty { throw [System.Management.Automation.ItemNotFoundException]::new('Optional registry value is absent.') }
    }

    AfterEach {
        $env:SystemDrive = $PreviousSystemDrive
    }

    It 'rejects omission of WhatIf before discovery' {
        { Clear-OldIISLog -Confirm:$false } | Should -Throw '*preview-only*'
        Should -Invoke Get-Module -Exactly 0 -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
        Should -Invoke Get-ItemProperty -Exactly 0
    }

    It 'fails closed when WebAdministration is unavailable and the log format is unknown' {
        $Result = Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable MetadataError

        $Result | Should -HaveCount 1
        $Result.DiscoveryStatus | Should -Be 'Failed'
        $Result.Status | Should -Be 'DiscoveryFailed'
        $Result.FileCandidateCount | Should -BeNullOrEmpty
        $Result.ErrorIds | Should -Contain 'IISLogFormatUnavailable'
        $Result.FilesRemoved | Should -Be 0
        $OldLog.FullName | Should -Exist
        @($MetadataError | Where-Object { $_.FullyQualifiedErrorId -like 'IISLogFormatUnavailable,*' }) | Should -Not -BeNullOrEmpty
        { Clear-OldIISLog -Days 60 -WhatIf -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw '*unavailable*'
    }

    It 'preserves a stable metadata error ID with ErrorAction Stop' {
        $ObservedError = $null
        try {
            Clear-OldIISLog -Days 60 -WhatIf -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
        } catch {
            $ObservedError = $_
        }

        $ObservedError | Should -Not -BeNullOrEmpty
        $ObservedError.FullyQualifiedErrorId | Should -Match '^IIS(LogFormatUnavailable|LocalTimeRolloverUnavailable),'
    }

    It 'does not guess a fallback FTP format without WebAdministration' {
        $FtpRoot = Join-Path -Path $IISRoot -ChildPath 'FTPSVC7'
        $null = New-Item -Path $FtpRoot -ItemType Directory -Force
        $FtpLog = New-Item -Path (Join-Path -Path $FtpRoot -ChildPath 'u_ex240101.log') -ItemType File
        $FtpLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)

        $Result = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

        $Result | Should -HaveCount 1
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].ErrorIds | Should -Contain 'IISLogFormatUnavailable'
        $Result[0].CandidatePaths | Should -BeNullOrEmpty
        $Result[0].FilesRemoved | Should -Be 0
        $OldLog.FullName | Should -Exist
        $FtpLog.FullName | Should -Exist
    }

    It 'fails closed when fallback metadata is known only for W3SVC' {
        $FtpRoot = Join-Path -Path $IISRoot -ChildPath 'FTPSVC7'
        $null = New-Item -Path $FtpRoot -ItemType Directory -Force
        $FtpLog = New-Item -Path (Join-Path -Path $FtpRoot -ChildPath 'u_ex240101.log') -ItemType File
        $FtpLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        Mock Get-ItemProperty { [pscustomobject]@{ LogDir = $IISRoot; LogFormat = 'W3C'; LocalTimeRollover = $false } }

        $Result = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable MetadataError)

        $Result | Should -HaveCount 1
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].ErrorIds | Should -Contain 'IISServiceMetadataUnavailable'
        @($MetadataError | Where-Object { $_.FullyQualifiedErrorId -like 'IISServiceMetadataUnavailable,*' }) | Should -Not -BeNullOrEmpty
        $FtpLog.FullName | Should -Exist
        $OldLog.FullName | Should -Exist
    }

    It 'reports an invalid configured root before probing existence' {
        $PreviousSystemDrive = $env:SystemDrive
        try {
            $env:SystemDrive = ''
            Mock Get-ItemProperty { [pscustomobject]@{ LogDir = '%MISSING%\logs' } }
            Mock Test-Path { throw 'Test-Path should not be called for an invalid IIS root.' }

            $Result = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DiscoveryError)

            $Result | Should -HaveCount 1
            $Result[0].RootPath | Should -Be '%MISSING%\logs'
            $Result[0].DiscoveryStatus | Should -Be 'Failed'
            $Result[0].Status | Should -Be 'DiscoveryFailed'
            $Result[0].FileCandidateCount | Should -BeNullOrEmpty
            $Result[0].ErrorIds | Should -Contain 'IISDiscoveryFailed'
            $DiscoveryError | Should -Not -BeNullOrEmpty
            Should -Invoke Test-Path -Exactly 0
        } finally {
            $env:SystemDrive = $PreviousSystemDrive
        }
    }

    It 'returns a structured failure for a malformed root before probing protection' {
        $PreviousSystemDrive = $env:SystemDrive
        try {
            $env:SystemDrive = ''
            $BadRoot = '\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1\logs'
            Mock Get-ItemProperty { [pscustomobject]@{ LogDir = $BadRoot } }
            Mock Test-TheCleanersIisProtectedPath { throw 'Protection should not be probed for a malformed IIS root.' }

            $Result = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DiscoveryError)

            $Result | Should -HaveCount 1
            $Result[0].RootPath | Should -Be $BadRoot
            $Result[0].DiscoveryStatus | Should -Be 'Failed'
            $Result[0].Status | Should -Be 'DiscoveryFailed'
            $Result[0].FileCandidateCount | Should -BeNullOrEmpty
            $Result[0].DirectoryCandidateCount | Should -BeNullOrEmpty
            $Result[0].ErrorIds | Should -Contain 'IISDiscoveryFailed'
            $DiscoveryError | Should -Not -BeNullOrEmpty
            Should -Invoke Test-TheCleanersIisProtectedPath -Exactly 0
        } finally {
            $env:SystemDrive = $PreviousSystemDrive
        }
    }

    It 'reports registry access failure instead of silently omitting a configured root' {
        Mock Get-ItemProperty { throw [System.UnauthorizedAccessException]::new('Fixture registry access denied.') }

        $Result = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable RegistryError)

        $Result | Should -HaveCount 1
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].CandidatePaths | Should -BeNullOrEmpty
        $Result[0].ErrorIds | Should -Contain 'IISRegistryDiscoveryFailed'
        $RegistryError | Should -Not -BeNullOrEmpty
        @($RegistryError | ForEach-Object { $_.Exception.Message } | Select-Object -Unique) | Should -Contain 'Fixture registry access denied.'
        { Clear-OldIISLog -Days 60 -WhatIf -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw '*Fixture registry access denied*'
    }

    It 'returns a failed result when registry discovery fails before the default root exists' {
        [System.IO.Directory]::Delete($IISRoot, $true)
        Mock Get-ItemProperty { throw [System.UnauthorizedAccessException]::new('Fixture registry access denied before root validation.') }

        $Result = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable RegistryError)

        $Result | Should -HaveCount 1
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].DirectoryCandidateCount | Should -BeNullOrEmpty
        $Result[0].DiscoveryErrorCount | Should -Be 1
        $Result[0].ErrorIds | Should -Contain 'IISRegistryDiscoveryFailed'
        $RegistryError | Should -Not -BeNullOrEmpty
    }

    It 'returns a failed result when IIS root normalization fails' {
        Mock Resolve-TheCleanersFileSystemPath {
            throw [System.UnauthorizedAccessException]::new('Fixture IIS root normalization denial.')
        } -ParameterFilter { $LiteralPath -eq $IISRoot }

        $Result = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DiscoveryError)

        $Result | Should -HaveCount 1
        $Result[0].RootPath | Should -Be ([System.IO.Path]::GetFullPath($IISRoot))
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].ErrorIds | Should -Contain 'IISDiscoveryFailed'
        $DiscoveryError | Should -Not -BeNullOrEmpty
    }

    It 'reports an unavailable product when no IIS root can be discovered' {
        [System.IO.Directory]::Delete($IISRoot, $true)

        $Result = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DiscoveryError)

        $Result | Should -HaveCount 1
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].DirectoryCandidateCount | Should -BeNullOrEmpty
        $Result[0].DiscoveryErrorCount | Should -Be 1
        $Result[0].ErrorIds | Should -Contain 'IISDiscoveryUnavailable'
        @($DiscoveryError | Where-Object { $_.FullyQualifiedErrorId -match '^IISDiscoveryUnavailable' }) | Should -Not -BeNullOrEmpty
    }

    It 'returns a failed result for a protected IIS root' {
        Mock Test-TheCleanersIisProtectedPath { $true }

        $Result = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ProtectedError)

        $Result | Should -HaveCount 1
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].DirectoryCandidateCount | Should -BeNullOrEmpty
        $Result[0].CandidatePaths | Should -BeNullOrEmpty
        $Result[0].DiscoveryErrorCount | Should -Be 3
        $Result[0].ErrorIds | Should -Contain 'IISProtectedRoot'
        $ProtectedError | Should -Not -BeNullOrEmpty
    }

    It 'contains no deletion command or generic removal-helper call' {
        $Tokens = $null
        $ParseErrors = $null
        $FunctionPath = Join-Path -Path $ModuleRoot -ChildPath 'Public/Clear-OldIISLog.ps1'
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($FunctionPath, [ref]$Tokens, [ref]$ParseErrors)
        $ParseErrors | Should -BeNullOrEmpty
        $Forbidden = $Ast.FindAll({
                param($Node)
            ($Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -in @('Remove-Item', 'Invoke-Expression', 'Start-Process')) -or
                ($Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $Node.Member.Value -eq 'Delete')
            }, $true)
        @($Forbidden) | Should -HaveCount 0
    }
}
