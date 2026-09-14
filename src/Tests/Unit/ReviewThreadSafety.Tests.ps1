BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $TempCases = @(
        @{ CommandName = 'Clear-CurrentUserTemp' }
        @{ CommandName = 'Clear-WindowsTemp' }
    )
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    foreach ($RelativePath in @(
        'Private/Resolve-TheCleanersFileSystemPath.ps1'
        'Private/Remove-OldFiles.ps1'
        'Public/Clear-CurrentUserTemp.ps1'
        'Public/Clear-WindowsTemp.ps1'
        'Public/Clear-OldIISLog.ps1'
        'Public/Clear-OldExchangeLog.ps1'
    )) {
        . (Join-Path -Path $ModuleRoot -ChildPath $RelativePath)
    }
}

Describe 'Temp candidate type-swap protection: <CommandName>' -ForEach $TempCases -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        $PreviousSystemRoot = $env:SystemRoot
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $FakeWindows = Join-Path -Path $FixtureRoot -ChildPath 'Windows'
        $TempRoot = Join-Path -Path $FakeWindows -ChildPath 'Temp'
        $null = New-Item -Path $TempRoot -ItemType Directory -Force
        $Candidate = New-Item -Path (Join-Path -Path $TempRoot -ChildPath 'candidate.tmp') -ItemType File
        $Now = [DateTime]::UtcNow
        $Candidate.LastWriteTimeUtc = $Now.AddDays(-31)
        $env:TEMP = $TempRoot
        $env:TMP = $TempRoot
        $env:SystemRoot = $FakeWindows
        Mock Get-Date { $Now }
    }

    AfterEach {
        $env:TEMP = $PreviousTemp
        $env:TMP = $PreviousTmp
        $env:SystemRoot = $PreviousSystemRoot
    }

    It 'does not delete or count a directory that replaces a discovered file' {
        $OriginalResolver = (Get-Command -Name Resolve-TheCleanersFileSystemPath -CommandType Function).ScriptBlock
        $State = @{ Changed = $false }
        Mock Resolve-TheCleanersFileSystemPath {
            param($LiteralPath, $RootPath)
            $ResolveParameters = @{ LiteralPath = $LiteralPath }
            if (-not [string]::IsNullOrWhiteSpace($RootPath)) {
                $ResolveParameters.RootPath = $RootPath
            }
            $ResolvedItem = & $OriginalResolver @ResolveParameters
            if (-not $State.Changed -and $LiteralPath -eq $Candidate.FullName -and -not [string]::IsNullOrWhiteSpace($RootPath)) {
                [System.IO.File]::Delete($Candidate.FullName)
                $null = New-Item -Path $Candidate.FullName -ItemType Directory
                $State.Changed = $true
            }
            $ResolvedItem
        }

        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru

        [System.IO.Directory]::Exists($Candidate.FullName) | Should -BeTrue
        $Result.FilesRemoved | Should -Be 0
        $Result.FilesSkipped | Should -Be 1
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
    }

    It 'uses a file-bound DeleteOnClose handle instead of provider removal' {
        $Tokens = $null
        $ParseErrors = $null
        $FunctionPath = Join-Path -Path $ModuleRoot -ChildPath ("Public/{0}.ps1" -f $CommandName)
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($FunctionPath, [ref]$Tokens, [ref]$ParseErrors)
        $ParseErrors | Should -BeNullOrEmpty
        @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Remove-Item'
                }, $true)) | Should -HaveCount 0
        $FunctionText = [System.IO.File]::ReadAllText($FunctionPath)
        $FunctionText | Should -Match '\[System\.IO\.FileOptions\]::DeleteOnClose'
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
}

Describe 'IIS structural preview lock' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousSystemDrive = $env:SystemDrive
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $IISRoot = Join-Path -Path $FixtureRoot -ChildPath 'inetpub/logs/LogFiles'
        $null = New-Item -Path $IISRoot -ItemType Directory -Force
        $OldLog = New-Item -Path (Join-Path -Path $IISRoot -ChildPath 'old.log') -ItemType File
        $OldLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $env:SystemDrive = $FixtureRoot
        Mock Get-Module { $null } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
        Mock Get-ItemProperty { throw 'Fixture registry path is unavailable.' }
        Mock Remove-OldFiles { throw 'IIS preview must not invoke the legacy removal helper.' }
    }

    AfterEach {
        $env:SystemDrive = $PreviousSystemDrive
    }

    It 'rejects omission of WhatIf before discovery' {
        { Clear-OldIISLog -Confirm:$false } | Should -Throw '*preview-only*'
        Should -Invoke Get-Module -Exactly 0 -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
        Should -Invoke Get-ItemProperty -Exactly 0
        Should -Invoke Remove-OldFiles -Exactly 0
    }

    It 'previews candidates without invoking the removal helper' {
        $Result = Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue

        $Result | Should -HaveCount 1
        $Result.FileCandidateCount | Should -Be 1
        $Result.CandidatePaths | Should -Contain $OldLog.FullName
        $Result.FilesRemoved | Should -Be 0
        $OldLog.FullName | Should -Exist
        Should -Invoke Remove-OldFiles -Exactly 0
    }

    It 'contains no deletion command or generic removal-helper call' {
        $Tokens = $null
        $ParseErrors = $null
        $FunctionPath = Join-Path -Path $ModuleRoot -ChildPath 'Public/Clear-OldIISLog.ps1'
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($FunctionPath, [ref]$Tokens, [ref]$ParseErrors)
        $ParseErrors | Should -BeNullOrEmpty
        $Forbidden = $Ast.FindAll({
                param($Node)
                ($Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -in @('Remove-Item', 'Remove-OldFiles', 'Invoke-Expression', 'Start-Process')) -or
                ($Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $Node.Member.Value -eq 'Delete')
            }, $true)
        @($Forbidden) | Should -HaveCount 0
    }
}
