BeforeAll {
    $ModuleRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\TheCleaners')).Path
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private\Remove-OldFiles.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public\Clear-CurrentUserTemp.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public\Clear-WindowsTemp.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public\Clear-OldIISLog.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public\Clear-OldExchangeLog.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public\Get-StaleUserProfile.ps1')
}

Describe 'Remove-OldFiles' -Tag Unit {
    BeforeEach {
        $TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().Guid)
        New-Item -Path $TestRoot -ItemType Directory -Force | Out-Null
        $OldFile = New-Item -Path (Join-Path -Path $TestRoot -ChildPath 'old.log') -ItemType File
        $NewFile = New-Item -Path (Join-Path -Path $TestRoot -ChildPath 'new.log') -ItemType File
        $OldFile.LastWriteTime = (Get-Date).AddDays(-31)
        $NewFile.LastWriteTime = Get-Date
    }

    AfterEach {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'removes files older than the retention window by LastWriteTime' {
        Remove-OldFiles -Path $TestRoot -Days 30 -Confirm:$false

        $OldFile.FullName | Should -Not -Exist
        $NewFile.FullName | Should -Exist
    }

    It 'does not remove matching files when WhatIf is used' {
        Remove-OldFiles -Path $TestRoot -Days 30 -WhatIf

        $OldFile.FullName | Should -Exist
        $NewFile.FullName | Should -Exist
    }
}

Describe 'Clear-WindowsTemp' -Tag Unit {
    BeforeEach {
        $PreviousSystemRoot = $env:SystemRoot
        $TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().Guid)
        $WindowsTempPath = Join-Path -Path $TestRoot -ChildPath 'Temp'
        New-Item -Path $WindowsTempPath -ItemType Directory -Force | Out-Null
        $OldFile = New-Item -Path (Join-Path -Path $WindowsTempPath -ChildPath 'old.tmp') -ItemType File
        $NewFile = New-Item -Path (Join-Path -Path $WindowsTempPath -ChildPath 'new.tmp') -ItemType File
        $OldDirectory = New-Item -Path (Join-Path -Path $WindowsTempPath -ChildPath 'old-dir') -ItemType Directory
        $NewChildFile = New-Item -Path (Join-Path -Path $OldDirectory.FullName -ChildPath 'new-child.tmp') -ItemType File
        $OldFile.LastWriteTime = (Get-Date).AddDays(-31)
        $NewFile.LastWriteTime = Get-Date
        $NewChildFile.LastWriteTime = Get-Date
        $OldDirectory.LastWriteTime = (Get-Date).AddDays(-31)
        $env:SystemRoot = $TestRoot
    }

    AfterEach {
        $env:SystemRoot = $PreviousSystemRoot
        Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'removes only old system temp items' {
        Clear-WindowsTemp -Days 30 -Confirm:$false | Out-Null

        $OldFile.FullName | Should -Not -Exist
        $NewFile.FullName | Should -Exist
    }

    It 'does not recursively delete old directories containing newer files' {
        Clear-WindowsTemp -Days 30 -Confirm:$false | Out-Null

        $OldDirectory.FullName | Should -Exist
        $NewChildFile.FullName | Should -Exist
    }

    It 'does not remove matching system temp items when WhatIf is used' {
        Clear-WindowsTemp -Days 30 -WhatIf

        $OldFile.FullName | Should -Exist
        $NewFile.FullName | Should -Exist
    }

    It 'writes a clear error when SystemRoot is missing' {
        $env:SystemRoot = ''

        $ErrorRecord = Clear-WindowsTemp -Days 30 -ErrorAction SilentlyContinue -ErrorVariable WindowsTempError 2>$null

        $ErrorRecord | Should -BeNullOrEmpty
        $WindowsTempError.Exception.Message | Should -Be 'Clear-WindowsTemp requires the SystemRoot environment variable to locate the system temp folder.'
    }
}

Describe 'Clear-CurrentUserTemp' -Tag Unit {
    BeforeEach {
        $PreviousTemp = $env:TEMP
        $TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().Guid)
        $NestedDirectory = Join-Path -Path $TestRoot -ChildPath 'empty\child'
        New-Item -Path $NestedDirectory -ItemType Directory -Force | Out-Null
        $OldFile = New-Item -Path (Join-Path -Path $NestedDirectory -ChildPath 'old.tmp') -ItemType File
        $OldFile.LastWriteTime = (Get-Date).AddDays(-31)
        $env:TEMP = $TestRoot
    }

    AfterEach {
        $env:TEMP = $PreviousTemp
        Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'removes empty directories after removing old files' -Skip:$IsLinux {
        Clear-CurrentUserTemp -Days 30 -TimeOut 5 -Confirm:$false | Out-Null

        (Join-Path -Path $TestRoot -ChildPath 'empty') | Should -Not -Exist
    }
}

Describe 'Get-StaleUserProfile' -Tag Unit {
    BeforeEach {
        $OldDate = (Get-Date).AddDays(-91)
        $RecentDate = Get-Date
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{
                    LocalPath   = 'C:\Users\StaleUser'
                    SID         = 'S-1-5-21-1000'
                    LastUseTime = $OldDate
                    Special     = $false
                    Loaded      = $false
                }
                [pscustomobject]@{
                    LocalPath   = 'C:\Users\RecentUser'
                    SID         = 'S-1-5-21-1001'
                    LastUseTime = $RecentDate
                    Special     = $false
                    Loaded      = $false
                }
                [pscustomobject]@{
                    LocalPath   = 'C:\Users\LoadedUser'
                    SID         = 'S-1-5-21-1002'
                    LastUseTime = $OldDate
                    Special     = $false
                    Loaded      = $true
                }
            )
        }
    }

    It 'rejects non-positive retention days' {
        { Get-StaleUserProfile -Days 0 } | Should -Throw
    }

    It 'returns only old unloaded non-special profiles' -Skip:(-not ($PSVersionTable.PSEdition -eq 'Desktop' -or ($PSVersionTable.PSVersion.Major -ge 6 -and $IsWindows))) {
        $Result = Get-StaleUserProfile -Days 90

        $Result | Should -HaveCount 1
        $Result.LocalPath | Should -Be 'C:\Users\StaleUser'
        Should -Invoke Get-CimInstance -Exactly 1
    }
}

Describe 'Clear-OldExchangeLog' -Tag Unit {
    BeforeEach {
        $TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().Guid)
        $ExchangeLoggingPath = Join-Path -Path $TestRoot -ChildPath 'Logging'
        New-Item -Path $ExchangeLoggingPath -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $TestRoot -ChildPath 'Bin\Search\Ceres\Diagnostics\ETLTraces') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $TestRoot -ChildPath 'Bin\Search\Ceres\Diagnostics\Logs') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $TestRoot -ChildPath 'TransportRoles\Logs\MessageTracking') -ItemType Directory -Force | Out-Null
        $OldLog = New-Item -Path (Join-Path -Path $ExchangeLoggingPath -ChildPath 'old.log') -ItemType File
        $NewLog = New-Item -Path (Join-Path -Path $ExchangeLoggingPath -ChildPath 'new.log') -ItemType File
        $IgnoredFile = New-Item -Path (Join-Path -Path $ExchangeLoggingPath -ChildPath 'old.txt') -ItemType File
        $OldLog.LastWriteTime = (Get-Date).AddDays(-31)
        $IgnoredFile.LastWriteTime = (Get-Date).AddDays(-31)
        $NewLog.LastWriteTime = Get-Date

        Mock Get-ItemProperty {
            [pscustomobject]@{
                MsiInstallPath = $TestRoot
            }
        }
        Mock Clear-OldIISLog {}
    }

    AfterEach {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'calls the existing IIS cleanup command' {
        Clear-OldExchangeLog -Days 30 -WhatIf

        Should -Invoke Clear-OldIISLog -Exactly 1 -ParameterFilter { $Days -eq 30 }
    }

    It 'removes only old Exchange log files' {
        Clear-OldExchangeLog -Days 30 -Confirm:$false

        $OldLog.FullName | Should -Not -Exist
        $NewLog.FullName | Should -Exist
        $IgnoredFile.FullName | Should -Exist
    }
}

