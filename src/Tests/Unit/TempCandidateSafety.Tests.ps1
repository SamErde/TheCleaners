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
        'Public/Clear-CurrentUserTemp.ps1'
        'Public/Clear-WindowsTemp.ps1'
    )) {
        . (Join-Path -Path $ModuleRoot -ChildPath $RelativePath)
    }
}

Describe 'Temp candidate safety: <CommandName>' -ForEach $TempCases -Skip:(-not $WindowsHost) -Tag Unit {
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
        $OriginalResolver = (Get-Command -Name Resolve-TheCleanersFileSystemPath -CommandType Function).ScriptBlock
    }

    AfterEach {
        $env:TEMP = $PreviousTemp
        $env:TMP = $PreviousTmp
        $env:SystemRoot = $PreviousSystemRoot
    }

    It 'does not delete or count a directory that replaces a discovered file' {
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

    It 'reconciles a discovered candidate that disappears before deletion' {
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
                $State.Changed = $true
            }
            $ResolvedItem
        }

        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru

        $Candidate.FullName | Should -Not -Exist
        $Result.FilesRemoved | Should -Be 0
        $Result.FilesSkipped | Should -Be 1
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
    }

    It 'converts a local Get-Date result to a UTC retention cutoff' {
        Mock Get-Date { $Now.ToLocalTime() }

        $Result = & $CommandName -Days 30 -WhatIf -PassThru

        $Result.CutoffUtc | Should -Be $Now.AddDays(-30)
        $Result.CutoffUtc.Kind | Should -Be ([DateTimeKind]::Utc)
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
        [System.IO.File]::ReadAllText($FunctionPath) | Should -Match '\[System\.IO\.FileOptions\]::DeleteOnClose'
    }
}
