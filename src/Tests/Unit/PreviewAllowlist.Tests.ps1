BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Resolve-TheCleanersFileSystemPath.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Test-TheCleanersIisLogFileName.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Test-TheCleanersIisProtectedPath.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Test-TheCleanersExchangeLogFileName.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Get-TheCleanersExchangeProtectedPaths.ps1')
}

Describe 'IIS format and protected-path allowlists' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'accepts only the W3C W3SVC rollover name' {
        Test-TheCleanersIisLogFileName -Name 'u_ex240101.log' -Format 'W3C' -Service 'W3SVC' | Should -BeTrue
        Test-TheCleanersIisLogFileName -Name 'old.log' -Format 'W3C' -Service 'W3SVC' | Should -BeFalse
        Test-TheCleanersIisLogFileName -Name 'u_ft240101.log' -Format 'W3C' -Service 'W3SVC' | Should -BeFalse
    }

    It 'separates FTP, IIS, NCSA, and custom formats' {
        Test-TheCleanersIisLogFileName -Name 'u_ex240101.log' -Format 'W3C' -Service 'MSFTPSVC' | Should -BeTrue
        Test-TheCleanersIisLogFileName -Name 'u_ex240101.log' -Format 'W3C' -Service 'FTPSVC' | Should -BeTrue
        Test-TheCleanersIisLogFileName -Name 'u_ft240101.log' -Format 'W3C' -Service 'FTPSVC' | Should -BeFalse
        Test-TheCleanersIisLogFileName -Name 'inetsv01.log' -Format 'IIS' | Should -BeTrue
        Test-TheCleanersIisLogFileName -Name 'ncsa01.log' -Format 'NCSA' | Should -BeTrue
        Test-TheCleanersIisLogFileName -Name 'u_ex240101.log' -Format 'Custom' | Should -BeFalse
    }

    It 'maps the IIS numeric logging enum and rejects non-rollover digit lengths' {
        Test-TheCleanersIisLogFileName -Name 'inetsv01.log' -Format '0' | Should -BeTrue
        Test-TheCleanersIisLogFileName -Name 'ncsa01.log' -Format '1' | Should -BeTrue
        Test-TheCleanersIisLogFileName -Name 'u_ex240101.log' -Format '2' -Service 'W3SVC' | Should -BeTrue
        Test-TheCleanersIisLogFileName -Name 'u_ex240101.log' -Format '0' -Service 'W3SVC' | Should -BeFalse
        Test-TheCleanersIisLogFileName -Name 'ncsa01.log' -Format '3' | Should -BeFalse
        Test-TheCleanersIisLogFileName -Name 'inetsv010.log' -Format 'IIS' | Should -BeFalse
        Test-TheCleanersIisLogFileName -Name 'u_ex2401010.log' -Format 'W3C' -Service 'W3SVC' | Should -BeFalse
    }

    It 'protects IIS executable, configuration, and history paths' {
        $WindowsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
        $Protected = Join-Path -Path $WindowsRoot -ChildPath 'System32/inetsrv/config'
        $Outside = Join-Path -Path $TestDrive -ChildPath 'logs'

        Test-TheCleanersIisProtectedPath -Path $Protected | Should -BeTrue
        Test-TheCleanersIisProtectedPath -Path (Join-Path -Path $Protected -ChildPath 'applicationHost.config') | Should -BeTrue
        Test-TheCleanersIisProtectedPath -Path (Join-Path -Path $WindowsRoot -ChildPath 'System32') | Should -BeTrue
        Test-TheCleanersIisProtectedPath -Path $Outside | Should -BeFalse
    }
}

Describe 'Exchange filename and protected-location allowlists' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'accepts only the known Message Tracking rollover patterns' {
        Test-TheCleanersExchangeLogFileName -Name 'MSGTRK20240914-1.log' -RelativeRoot 'TransportRoles/Logs/MessageTracking' | Should -BeTrue
        Test-TheCleanersExchangeLogFileName -Name 'MSGTRKMS20240914-12.log' -RelativeRoot 'TransportRoles/Logs/MessageTracking' | Should -BeTrue
        Test-TheCleanersExchangeLogFileName -Name 'old.log' -RelativeRoot 'TransportRoles/Logs/MessageTracking' | Should -BeFalse
        Test-TheCleanersExchangeLogFileName -Name 'MSGTRK20240914.log' -RelativeRoot 'TransportRoles/Logs/MessageTracking' | Should -BeFalse
    }

    It 'separates ETL and diagnostic log extensions' {
        Test-TheCleanersExchangeLogFileName -Name 'Search_20240914.etl' -RelativeRoot 'Bin/Search/Ceres/Diagnostics/ETLTraces' | Should -BeTrue
        Test-TheCleanersExchangeLogFileName -Name 'Search_20240914.log' -RelativeRoot 'Bin/Search/Ceres/Diagnostics/ETLTraces' | Should -BeFalse
        Test-TheCleanersExchangeLogFileName -Name 'Search_20240914.log' -RelativeRoot 'Bin/Search/Ceres/Diagnostics/Logs' | Should -BeTrue
        Test-TheCleanersExchangeLogFileName -Name '.hidden.log' -RelativeRoot 'Logging' | Should -BeFalse
    }

    It 'reports unknown protection when Exchange management metadata is unavailable' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-MailboxDatabase' }
        $InstallRoot = New-Item -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)) -ItemType Directory

        $Protection = Get-TheCleanersExchangeProtectedPaths -InstallRoot $InstallRoot

        $Protection.Status | Should -Be 'Unknown'
        $Protection.Paths | Should -BeNullOrEmpty
    }

    It 'normalizes database and transaction-log paths returned by Exchange' {
        $InstallRoot = New-Item -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)) -ItemType Directory
        $DatabasePath = Join-Path -Path $TestDrive -ChildPath 'Databases/Mailbox.edb'
        $TransactionPath = Join-Path -Path $TestDrive -ChildPath 'Transactions'
        $null = New-Item -Path (Split-Path -Path $DatabasePath -Parent) -ItemType Directory -Force
        $null = New-Item -Path $TransactionPath -ItemType Directory -Force
        $ExistingGetMailboxDatabase = Get-Item -LiteralPath 'Function:\global:Get-MailboxDatabase' -ErrorAction SilentlyContinue
        function global:Get-MailboxDatabase { }
        Mock Get-Command { [pscustomobject]@{ Name = 'Get-MailboxDatabase' } } -ParameterFilter { $Name -eq 'Get-MailboxDatabase' }
        Mock Get-MailboxDatabase {
            [pscustomobject]@{
                EdbFilePath   = [pscustomobject]@{ PathName = $DatabasePath }
                LogFolderPath = $TransactionPath + '\'
            }
        }

        try {
            $Protection = Get-TheCleanersExchangeProtectedPaths -InstallRoot $InstallRoot
        } finally {
            Remove-Item -LiteralPath 'Function:\global:Get-MailboxDatabase' -Force -ErrorAction SilentlyContinue
            if ($null -ne $ExistingGetMailboxDatabase) {
                Set-Item -LiteralPath 'Function:\global:Get-MailboxDatabase' -Value $ExistingGetMailboxDatabase.ScriptBlock -Force
            }
        }

        $Protection.Status | Should -Be 'Validated'
        $Protection.Paths | Should -HaveCount 2
        $Protection.Paths | Should -Contain ([System.IO.Path]::GetFullPath($DatabasePath))
        $Protection.Paths | Should -Contain ([System.IO.Path]::GetFullPath($TransactionPath))
    }

    It 'reports unknown protection when a database omits path metadata' {
        $InstallRoot = New-Item -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)) -ItemType Directory
        $DatabasePath = Join-Path -Path $TestDrive -ChildPath 'Databases/Mailbox.edb'
        $ExistingGetMailboxDatabase = Get-Item -LiteralPath 'Function:\global:Get-MailboxDatabase' -ErrorAction SilentlyContinue
        function global:Get-MailboxDatabase { }
        Mock Get-Command { [pscustomobject]@{ Name = 'Get-MailboxDatabase' } } -ParameterFilter { $Name -eq 'Get-MailboxDatabase' }
        Mock Get-MailboxDatabase {
            [pscustomobject]@{
                EdbFilePath   = $DatabasePath
                LogFolderPath = $null
            }
        }

        try {
            $Protection = Get-TheCleanersExchangeProtectedPaths -InstallRoot $InstallRoot
        } finally {
            Remove-Item -LiteralPath 'Function:\global:Get-MailboxDatabase' -Force -ErrorAction SilentlyContinue
            if ($null -ne $ExistingGetMailboxDatabase) {
                Set-Item -LiteralPath 'Function:\global:Get-MailboxDatabase' -Value $ExistingGetMailboxDatabase.ScriptBlock -Force
            }
        }

        $Protection.Status | Should -Be 'Unknown'
        $Protection.Paths | Should -Contain ([System.IO.Path]::GetFullPath($DatabasePath))
    }
}
