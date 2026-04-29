BeforeAll {
    $ModuleRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\TheCleaners')).Path
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private\Remove-OldFiles.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public\Clear-CurrentUserTemp.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public\Clear-OldIISLog.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public\Clear-OldExchangeLog.ps1')
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

