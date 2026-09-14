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
        'Private/ResultContracts.ps1'
        'Private/Initialize-TheCleanersNativeFileInterop.ps1'
        'Private/Get-TheCleanersWindowsTempRoot.ps1'
        'Private/Get-TheCleanersTempPlan.ps1'
        'Private/Resolve-TheCleanersFileSystemPath.ps1'
        'Public/Clear-CurrentUserTemp.ps1'
        'Public/Clear-WindowsTemp.ps1'
    )) {
        . (Join-Path -Path $ModuleRoot -ChildPath $RelativePath)
    }
}

Describe 'Native identity safety' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'returns a stable native identity for the same file and reports length' {
        $File = New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'identity.bin') -ItemType File
        [System.IO.File]::WriteAllBytes($File.FullName, [byte[]](1, 2, 3, 4))

        $First = Get-TheCleanersFileIdentity -LiteralPath $File.FullName
        $Second = Get-TheCleanersFileIdentity -LiteralPath $File.FullName

        $First.Key | Should -Be $Second.Key
        $First.Equals($Second) | Should -BeTrue
        $First.Length | Should -Be 4
        $First.IsDirectory | Should -BeFalse
        $First.IsReparsePoint | Should -BeFalse
    }

    It 'does not treat a recreated directory as the original identity' {
        $DirectoryPath = Join-Path -Path $TestDrive -ChildPath 'recreated'
        $null = New-Item -Path $DirectoryPath -ItemType Directory
        $Original = Get-TheCleanersFileIdentity -LiteralPath $DirectoryPath -Directory
        [System.IO.Directory]::Delete($DirectoryPath)
        $null = New-Item -Path $DirectoryPath -ItemType Directory
        $Replacement = Get-TheCleanersFileIdentity -LiteralPath $DirectoryPath -Directory

        $Original.Equals($Replacement) | Should -BeFalse
    }

    It 'recognizes a symbolic link or junction as a reparse point without following it' {
        $OutsidePath = Join-Path -Path $TestDrive -ChildPath 'outside'
        $LinkPath = Join-Path -Path $TestDrive -ChildPath 'link'
        $null = New-Item -Path $OutsidePath -ItemType Directory
        $OutsideFile = New-Item -Path (Join-Path -Path $OutsidePath -ChildPath 'outside.txt') -ItemType File
        $CreatedLink = $false
        try {
            $null = New-Item -Path $LinkPath -ItemType SymbolicLink -Target $OutsidePath -ErrorAction Stop
            $CreatedLink = $true
        } catch {
            # Developer mode or SeCreateSymbolicLinkPrivilege is not guaranteed on
            # every supported Windows host. A junction still exercises the native
            # reparse-point identity and no-follow boundary without a skipped test.
            $null = New-Item -Path $LinkPath -ItemType Junction -Target $OutsidePath -ErrorAction Stop
        }

        $Identity = Get-TheCleanersFileIdentity -LiteralPath $LinkPath -Directory
        $Identity.IsReparsePoint | Should -BeTrue
        $OutsideFile.FullName | Should -Exist
        $IsReparsePoint = ((Get-Item -LiteralPath $LinkPath -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        ($CreatedLink -or $IsReparsePoint) | Should -BeTrue
    }
}

Describe 'Hard-link behavior: <CommandName>' -ForEach $TempCases -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        $PreviousSystemRoot = $env:SystemRoot
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $FakeWindows = Join-Path -Path $FixtureRoot -ChildPath 'Windows'
        $TempRoot = Join-Path -Path $FakeWindows -ChildPath 'Temp'
        $OutsideRoot = Join-Path -Path $FixtureRoot -ChildPath 'Outside'
        $null = New-Item -Path $TempRoot -ItemType Directory -Force
        $null = New-Item -Path $OutsideRoot -ItemType Directory -Force
        $Candidate = New-Item -Path (Join-Path -Path $TempRoot -ChildPath 'candidate.tmp') -ItemType File
        [System.IO.File]::WriteAllBytes($Candidate.FullName, [byte[]](1, 2, 3, 4, 5))
        $Candidate.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-31)
        $OutsideLink = Join-Path -Path $OutsideRoot -ChildPath 'same-file.tmp'
        $HardLinkAvailable = $false
        try {
            $HardLinkMethod = [System.IO.File].GetMethod('CreateHardLink', [Type[]]@([string], [string]))
            if ($null -ne $HardLinkMethod) {
                $null = $HardLinkMethod.Invoke($null, @($OutsideLink, $Candidate.FullName))
                $HardLinkAvailable = $true
            } else {
                & fsutil.exe hardlink create $OutsideLink $Candidate.FullName | Out-Null
                $HardLinkAvailable = $LASTEXITCODE -eq 0
            }
        } catch {
            $HardLinkAvailable = $false
        }

        $env:TEMP = $TempRoot
        $env:TMP = $TempRoot
        $env:SystemRoot = $FakeWindows
        Mock Get-TheCleanersWindowsTempRoot { Resolve-TheCleanersFileSystemPath -LiteralPath $TempRoot }
        Mock Get-Date { [DateTime]::UtcNow }
    }

    AfterEach {
        $env:TEMP = $PreviousTemp
        $env:TMP = $PreviousTmp
        $env:SystemRoot = $PreviousSystemRoot
    }

    It 'removes only the approved hard-link name and leaves the outside name' {
        if (-not $HardLinkAvailable) {
            Set-ItResult -Skipped -Because 'The disposable Windows fixture cannot create a hard link in this session.'
            return
        }

        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru

        $Candidate.FullName | Should -Not -Exist
        $OutsideLink | Should -Exist
        $Result.FilesRemoved | Should -Be 1
        $Result.BytesReclaimed | Should -Be 5
    }
}
