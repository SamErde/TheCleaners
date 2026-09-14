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
        'Public/Get-StaleUserProfile.ps1'
    )) {
        . (Join-Path -Path $ModuleRoot -ChildPath $RelativePath)
    }
}

Describe 'Temp safety: <CommandName>' -ForEach $TempCases -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        $PreviousSystemRoot = $env:SystemRoot
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $FakeWindows = Join-Path -Path $FixtureRoot -ChildPath 'Windows'
        $TempRoot = Join-Path -Path $FakeWindows -ChildPath 'Temp'
        $NestedPath = Join-Path -Path $TempRoot -ChildPath 'Touched/Child'
        $UnrelatedPath = Join-Path -Path $TempRoot -ChildPath 'UnrelatedEmpty'
        $null = New-Item -Path $NestedPath -ItemType Directory -Force
        $null = New-Item -Path $UnrelatedPath -ItemType Directory
        $OldFile = New-Item -Path (Join-Path -Path $NestedPath -ChildPath 'old.tmp') -ItemType File
        [System.IO.File]::WriteAllBytes($OldFile.FullName, [byte[]](1, 2, 3))
        $NewFile = New-Item -Path (Join-Path -Path $TempRoot -ChildPath 'recent.tmp') -ItemType File
        $Now = [DateTime]::UtcNow
        $OldFile.LastWriteTimeUtc = $Now.AddDays(-31)
        $NewFile.LastWriteTimeUtc = $Now
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

    It 'preserves directories by default while deleting only old files' {
        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru
        $OldFile.FullName | Should -Not -Exist
        $NewFile.FullName | Should -Exist
        $NestedPath | Should -Exist
        $TempRoot | Should -Exist
        $Result.DirectoryCandidateCount | Should -Be 0
        $Result.DirectoriesRemoved | Should -Be 0
        $Result.FilesRemoved | Should -Be 1
        $Result.BytesReclaimed | Should -Be 3
    }

    It 'prunes only directories emptied by this cleanup, deepest-first' {
        $Result = & $CommandName -Days 30 -RemoveEmptyDirectory -Confirm:$false -PassThru
        $NestedPath | Should -Not -Exist
        (Split-Path -Path $NestedPath -Parent) | Should -Not -Exist
        $UnrelatedPath | Should -Exist
        $TempRoot | Should -Exist
        $Result.DirectoryCandidateCount | Should -Be 2
        $Result.DirectoriesRemoved | Should -Be 2
        $Result.Status | Should -Be 'Completed'
    }

    It 'does not remove directories containing recent files' {
        $RecentChild = New-Item -Path (Join-Path -Path $NestedPath -ChildPath 'recent-child.tmp') -ItemType File
        $RecentChild.LastWriteTimeUtc = $Now
        $Result = & $CommandName -Days 30 -RemoveEmptyDirectory -Confirm:$false -PassThru
        $RecentChild.FullName | Should -Exist
        $NestedPath | Should -Exist
        $Result.DirectoriesRemoved | Should -Be 0
    }

    It 'does not absorb an unrelated pre-existing empty sibling into its directory plan' {
        $EmptySibling = Join-Path -Path (Split-Path -Path $NestedPath -Parent) -ChildPath 'LeaveMe'
        $null = New-Item -Path $EmptySibling -ItemType Directory
        $Result = & $CommandName -Days 30 -RemoveEmptyDirectory -Confirm:$false -PassThru
        $NestedPath | Should -Not -Exist
        $EmptySibling | Should -Exist
        $Result.DirectoriesRemoved | Should -Be 1
    }

    It 'previews both file and directory counts without modifying the filesystem' {
        Mock Remove-Item { throw 'Unexpected deletion in WhatIf.' }
        $Result = & $CommandName -Days 30 -RemoveEmptyDirectory -WhatIf -PassThru
        $OldFile.FullName | Should -Exist
        $NestedPath | Should -Exist
        $UnrelatedPath | Should -Exist
        $Result.FileCandidateCount | Should -Be 1
        $Result.DirectoryCandidateCount | Should -Be 2
        $Result.FilesRemoved | Should -Be 0
        $Result.DirectoriesRemoved | Should -Be 0
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'WhatIf'
        Should -Invoke Remove-Item -Exactly 0
    }

    It 'honors an explicitly false directory switch' {
        & $CommandName -Days 30 -RemoveEmptyDirectory:$false -Confirm:$false
        $OldFile.FullName | Should -Not -Exist
        $NestedPath | Should -Exist
    }

    It 'does not prune pre-existing empty directories when there are no eligible files' {
        $OldFile.LastWriteTimeUtc = $Now
        $Result = & $CommandName -Days 30 -RemoveEmptyDirectory -Confirm:$false -PassThru
        $Result.Status | Should -Be 'NoCandidates'
        $UnrelatedPath | Should -Exist
    }

    It 'uses an inclusive UTC retention boundary' {
        $OldFile.LastWriteTimeUtc = $Now.AddDays(-30)
        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru
        $Result.FilesRemoved | Should -Be 1
        $Result.CutoffUtc | Should -Be $Now.AddDays(-30)
        $Result.CutoffUtc.Kind | Should -Be ([DateTimeKind]::Utc)
    }

    It 'does not interpret wildcard characters in a filename' {
        $LiteralFile = Join-Path -Path $NestedPath -ChildPath '[literal].tmp'
        [System.IO.File]::WriteAllText($LiteralFile, 'literal')
        [System.IO.File]::SetLastWriteTimeUtc($LiteralFile, $Now.AddDays(-31))
        & $CommandName -Days 30 -Confirm:$false
        [System.IO.File]::Exists($LiteralFile) | Should -BeFalse
        $NewFile.FullName | Should -Exist
    }

    It 'reports deletion failure without claiming reclaimed bytes or removing its parents' {
        $FileLock = [System.IO.File]::Open($OldFile.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $Result = & $CommandName -Days 30 -RemoveEmptyDirectory -Confirm:$false -PassThru -ErrorAction SilentlyContinue -ErrorVariable CleanupErrors
            $CleanupErrors | Should -Not -BeNullOrEmpty
            $Result.FileFailureCount | Should -Be 1
            $Result.FilesRemoved | Should -Be 0
            $Result.BytesReclaimed | Should -Be 0
            $Result.Status | Should -Be 'PartialFailure'
            $NestedPath | Should -Exist
        } finally {
            $FileLock.Dispose()
        }
    }

    It 'honors ErrorAction Stop rather than swallowing deletion errors' {
        $FileLock = [System.IO.File]::Open($OldFile.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            { & $CommandName -Days 30 -Confirm:$false -ErrorAction Stop } | Should -Throw
            $OldFile.FullName | Should -Exist
        } finally {
            $FileLock.Dispose()
        }
    }

    It 'fails closed on enumeration failure and marks candidate totals unknown' {
        Mock Get-ChildItem { throw [System.UnauthorizedAccessException]::new('Fixture enumeration denied.') }
        Mock Remove-Item { throw 'Deletion must not follow incomplete discovery.' }
        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru -ErrorAction SilentlyContinue
        $Result.Status | Should -Be 'DiscoveryFailed'
        $Result.FileCandidateCount | Should -BeNullOrEmpty
        $Result.DirectoryCandidateCount | Should -BeNullOrEmpty
        $OldFile.FullName | Should -Exist
        Should -Invoke Remove-Item -Exactly 0
    }

    It 'skips a junction before traversing it' {
        $Outside = Join-Path -Path $FixtureRoot -ChildPath 'Outside'
        $null = New-Item -Path $Outside -ItemType Directory
        $OutsideFile = New-Item -Path (Join-Path -Path $Outside -ChildPath 'outside.tmp') -ItemType File
        $OutsideFile.LastWriteTimeUtc = $Now.AddDays(-31)
        $Junction = Join-Path -Path $TempRoot -ChildPath 'DoNotFollow'
        $null = New-Item -Path $Junction -ItemType Junction -Target $Outside
        try {
            & $CommandName -Days 30 -RemoveEmptyDirectory -Confirm:$false
            $OutsideFile.FullName | Should -Exist
            (Get-Item -LiteralPath $Junction).Attributes -band [System.IO.FileAttributes]::ReparsePoint | Should -Not -Be 0
        } finally {
            [System.IO.Directory]::Delete($Junction)
        }
    }

    It 'rejects non-positive retention days' {
        { & $CommandName -Days 0 -WhatIf } | Should -Throw
    }
}

Describe 'Literal path validation' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'rejects the drive root as a cleanup root' {
        { Resolve-TheCleanersFileSystemPath -LiteralPath ([System.IO.Path]::GetPathRoot($TestDrive)) } | Should -Throw
    }

    It 'rejects the cleanup root itself as a deletion candidate' {
        { Resolve-TheCleanersFileSystemPath -LiteralPath $TestDrive -RootPath $TestDrive } | Should -Throw
    }

    It 'rejects a sibling with a matching string prefix' {
        $Root = New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'Root') -ItemType Directory
        $Sibling = New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'Root-Other') -ItemType Directory
        { Resolve-TheCleanersFileSystemPath -LiteralPath $Sibling.FullName -RootPath $Root.FullName } | Should -Throw
    }
}

Describe 'Exchange is structurally preview-only' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $ExchangeRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $LogPath = Join-Path -Path $ExchangeRoot -ChildPath 'Logging'
        $null = New-Item -Path $LogPath -ItemType Directory -Force
        $OldLog = New-Item -Path (Join-Path -Path $LogPath -ChildPath 'old.log') -ItemType File
        $RecentLog = New-Item -Path (Join-Path -Path $LogPath -ChildPath 'recent.log') -ItemType File
        $IgnoredFile = New-Item -Path (Join-Path -Path $LogPath -ChildPath 'old.txt') -ItemType File
        $OldLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-31)
        $IgnoredFile.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-31)
        Mock Get-ItemProperty { [pscustomobject]@{ MsiInstallPath = $ExchangeRoot } }
        Mock Clear-OldIISLog { throw 'Exchange must not invoke IIS cleanup.' }
        Mock Remove-Item { throw 'Exchange must not delete.' }
    }

    It 'rejects omission of WhatIf before reading the registry' {
        { Clear-OldExchangeLog -Confirm:$false } | Should -Throw '*preview-only*'
        Should -Invoke Get-ItemProperty -Exactly 0
        Should -Invoke Remove-Item -Exactly 0
    }

    It 'rejects explicit WhatIf false even when confirmation is disabled' {
        { Clear-OldExchangeLog -WhatIf:$false -Confirm:$false } | Should -Throw '*preview-only*'
        Should -Invoke Get-ItemProperty -Exactly 0
    }

    It 'does not treat an ambient preference as explicit activation' {
        $WhatIfPreference = $true
        { Clear-OldExchangeLog } | Should -Throw '*preview-only*'
        Should -Invoke Get-ItemProperty -Exactly 0
    }

    It 'has no Force, AllowRemoval, or EnableRemoval bypass' {
        foreach ($ParameterName in @('Force', 'AllowRemoval', 'EnableRemoval')) {
            $Parameters = @{ WhatIf = $true }
            $Parameters[$ParameterName] = $true
            { Clear-OldExchangeLog @Parameters } | Should -Throw
        }
        Should -Invoke Get-ItemProperty -Exactly 0
        Should -Invoke Remove-Item -Exactly 0
    }

    It 'returns experimental preview candidates and leaves every file intact' {
        $Result = Clear-OldExchangeLog -Days 30 -WhatIf -PassThru -WarningAction SilentlyContinue
        $Result | Should -HaveCount 1
        $Result.FileCandidateCount | Should -Be 1
        $Result.CandidatePaths | Should -Contain $OldLog.FullName
        $Result.FilesRemoved | Should -Be 0
        $Result.Status | Should -Be 'WhatIf'
        $Result.DiscoveryStatus | Should -Be 'Experimental'
        $OldLog.FullName | Should -Exist
        $RecentLog.FullName | Should -Exist
        $IgnoredFile.FullName | Should -Exist
        Should -Invoke Clear-OldIISLog -Exactly 0
        Should -Invoke Remove-Item -Exactly 0
    }

    It 'does not disguise registry failure as an empty preview' {
        Mock Get-ItemProperty { throw 'Fixture setup registry unavailable.' }
        { Clear-OldExchangeLog -WhatIf -WarningAction SilentlyContinue } | Should -Throw
        Should -Invoke Remove-Item -Exactly 0
    }

    It 'contains no deletion command, filesystem Delete call, or IIS cleanup call' {
        $Tokens = $null
        $ParseErrors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $ModuleRoot -ChildPath 'Public/Clear-OldExchangeLog.ps1'), [ref]$Tokens, [ref]$ParseErrors)
        $ParseErrors | Should -BeNullOrEmpty
        $Forbidden = $Ast.FindAll({
            param($Node)
            ($Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -in @('Remove-Item', 'Clear-OldIISLog', 'Remove-OldFiles', 'Invoke-Expression', 'Start-Process')) -or
            ($Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $Node.Member.Value -eq 'Delete')
        }, $true)
        @($Forbidden) | Should -HaveCount 0
    }
}

Describe 'IIS is structurally preview-only' -Tag Unit {
    It 'rejects omission of WhatIf before discovering or removing logs' {
        Mock Remove-OldFiles { throw 'IIS must not delete.' }
        { Clear-OldIISLog -Confirm:$false } | Should -Throw '*preview-only*'
        Should -Invoke Remove-OldFiles -Exactly 0
    }

    It 'does not remove logs when explicitly previewed' {
        Mock Remove-OldFiles { throw 'IIS must not delete.' }
        Clear-OldIISLog -WhatIf
        Should -Invoke Remove-OldFiles -Exactly 0
    }
}

# Keep existing coverage of legacy code until its separate refactor is completed.
Describe 'Remove-OldFiles legacy IIS dependency' -Tag Unit {
    BeforeEach {
        $TestRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $null = New-Item -Path $TestRoot -ItemType Directory
        $OldFile = New-Item -Path (Join-Path -Path $TestRoot -ChildPath 'old.log') -ItemType File
        $NewFile = New-Item -Path (Join-Path -Path $TestRoot -ChildPath 'new.log') -ItemType File
        $OldFile.LastWriteTime = (Get-Date).AddDays(-31)
    }
    It 'removes files older than the retention window' {
        Remove-OldFiles -Path $TestRoot -Days 30 -Confirm:$false
        $OldFile.FullName | Should -Not -Exist
        $NewFile.FullName | Should -Exist
    }
    It 'does not remove matching files with WhatIf' {
        Remove-OldFiles -Path $TestRoot -Days 30 -WhatIf
        $OldFile.FullName | Should -Exist
    }
}

Describe 'Get-StaleUserProfile legacy contract' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ LocalPath = 'C:\Users\StaleUser'; SID = 'S-1-5-21-1000'; LastUseTime = (Get-Date).AddDays(-91); Special = $false; Loaded = $false }
                [pscustomobject]@{ LocalPath = 'C:\Users\RecentUser'; SID = 'S-1-5-21-1001'; LastUseTime = Get-Date; Special = $false; Loaded = $false }
                [pscustomobject]@{ LocalPath = 'C:\Users\LoadedUser'; SID = 'S-1-5-21-1002'; LastUseTime = (Get-Date).AddDays(-91); Special = $false; Loaded = $true }
            )
        }
    }
    It 'rejects non-positive retention days' {
        { Get-StaleUserProfile -Days 0 } | Should -Throw
    }
    It 'returns only old unloaded non-special profiles' {
        $Result = Get-StaleUserProfile -Days 90
        $Result | Should -HaveCount 1
        $Result.LocalPath | Should -Be 'C:\Users\StaleUser'
        Should -Invoke Get-CimInstance -Exactly 1
    }
}
