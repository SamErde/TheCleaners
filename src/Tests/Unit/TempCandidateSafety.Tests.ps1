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
        Mock Get-TheCleanersWindowsTempRoot { Resolve-TheCleanersFileSystemPath -LiteralPath $TempRoot }
        Mock Get-Date { $Now }
    }

    AfterEach {
        $env:TEMP = $PreviousTemp
        $env:TMP = $PreviousTmp
        $env:SystemRoot = $PreviousSystemRoot
    }

    It 'does not delete or count a directory that replaces a discovered file' {
        Mock Get-TheCleanersTempPlan {
            param($Root, $CutoffUtc)
            $RootPath = $Root.FullName.TrimEnd([char[]]@('\', '/'))
            $RootIdentity = Get-TheCleanersFileIdentity -LiteralPath $RootPath -Directory
            $CandidateIdentity = Get-TheCleanersFileIdentity -LiteralPath $Candidate.FullName
            [System.IO.File]::Delete($Candidate.FullName)
            $null = New-Item -Path $Candidate.FullName -ItemType Directory
            [pscustomobject]@{
                RootPath     = $RootPath
                RootIdentity = $RootIdentity
                CutoffUtc    = $CutoffUtc
                Files        = @([pscustomobject]@{ Path = $Candidate.FullName; Identity = $CandidateIdentity; LastWriteTimeUtc = $Now.AddDays(-31); ParentPath = $RootPath; ParentIdentity = $null })
                Directories  = @()
            }
        }

        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru

        [System.IO.Directory]::Exists($Candidate.FullName) | Should -BeTrue
        $Result.FilesRemoved | Should -Be 0
        $Result.FilesSkipped | Should -Be 1
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
    }

    It 'fails closed when discovery cannot capture a candidate identity' {
        Mock Get-TheCleanersTempPlan {
            param($Root, $CutoffUtc)
            $RootPath = $Root.FullName.TrimEnd([char[]]@('\', '/'))
            [pscustomobject]@{
                RootPath     = $RootPath
                RootIdentity = Get-TheCleanersFileIdentity -LiteralPath $RootPath -Directory
                CutoffUtc    = $CutoffUtc
                Files        = @([pscustomobject]@{
                        Path             = $Candidate.FullName
                        Identity         = $null
                        LastWriteTimeUtc = $Now.AddDays(-31)
                        ParentPath       = $RootPath
                        ParentIdentity   = $null
                    })
                Directories  = @()
            }
        }

        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru

        $Candidate.FullName | Should -Exist
        $Result.FileCandidateCount | Should -Be 1
        $Result.FilesRemoved | Should -Be 0
        $Result.FilesSkipped | Should -Be 1
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
    }

    It 'reconciles a discovered candidate that disappears before deletion' {
        Mock Get-TheCleanersTempPlan {
            param($Root, $CutoffUtc)
            $RootPath = $Root.FullName.TrimEnd([char[]]@('\', '/'))
            $RootIdentity = Get-TheCleanersFileIdentity -LiteralPath $RootPath -Directory
            $CandidateIdentity = Get-TheCleanersFileIdentity -LiteralPath $Candidate.FullName
            [System.IO.File]::Delete($Candidate.FullName)
            [pscustomobject]@{
                RootPath     = $RootPath
                RootIdentity = $RootIdentity
                CutoffUtc    = $CutoffUtc
                Files        = @([pscustomobject]@{ Path = $Candidate.FullName; Identity = $CandidateIdentity; LastWriteTimeUtc = $Now.AddDays(-31); ParentPath = $RootPath; ParentIdentity = $null })
                Directories  = @()
            }
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

    It 'uses a native same-handle deletion primitive instead of provider removal' {
        $Tokens = $null
        $ParseErrors = $null
        $FunctionPath = Join-Path -Path $ModuleRoot -ChildPath ("Public/{0}.ps1" -f $CommandName)
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($FunctionPath, [ref]$Tokens, [ref]$ParseErrors)
        $ParseErrors | Should -BeNullOrEmpty
        @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Remove-Item'
                }, $true)) | Should -HaveCount 0
        [System.IO.File]::ReadAllText($FunctionPath) | Should -Match 'NativeFileInterop.*OpenForDeletion'
        [System.IO.File]::ReadAllText($FunctionPath) | Should -Match 'NativeFileInterop.*MarkForDeletion'
    }
}
