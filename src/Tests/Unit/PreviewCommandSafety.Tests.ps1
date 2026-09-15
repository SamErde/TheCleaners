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

    It 'skips an expected log root occupied by a file' {
        [System.IO.Directory]::Delete($LogRoot)
        $RootFile = New-Item -Path $LogRoot -ItemType File

        $Result = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue)

        $Result | Should -HaveCount 0
        $RootFile.FullName | Should -Exist
    }

    It 'rejects an installation path that is not a directory' {
        $InstallFile = New-Item -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)) -ItemType File
        Mock Get-ItemProperty { [pscustomobject]@{ MsiInstallPath = $InstallFile.FullName } }

        { Clear-OldExchangeLog -WhatIf -WarningAction SilentlyContinue } | Should -Throw '*not a directory*'
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

    It 'previews candidates without invoking the removal helper' {
        $Result = Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue

        $Result | Should -HaveCount 1
        $Result.FileCandidateCount | Should -Be 1
        $Result.CandidatePaths | Should -Contain $OldLog.FullName
        $Result.FilesRemoved | Should -Be 0
        $OldLog.FullName | Should -Exist
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
