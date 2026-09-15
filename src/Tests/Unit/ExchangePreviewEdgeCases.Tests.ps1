BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners'
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/ResultContracts.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Resolve-TheCleanersFileSystemPath.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Test-TheCleanersExchangeLogFileName.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Get-TheCleanersExchangeProtectedPaths.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public/Clear-OldExchangeLog.ps1')
}

Describe 'Exchange preview result edge cases' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $ExchangeRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $LogRoot = Join-Path -Path $ExchangeRoot -ChildPath 'Logging'
        $null = New-Item -Path $LogRoot -ItemType Directory -Force
        Mock Get-ItemProperty { [pscustomobject]@{ MsiInstallPath = $ExchangeRoot } }
        Mock Remove-Item { throw 'Exchange preview must not remove anything.' }
    }

    It 'returns an empty array rather than a null path when no candidates exist' {
        $Result = Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue
        $Result.FileCandidateCount | Should -Be 0
        $Result.CandidatePaths.Count | Should -Be 0
        $Result.FilesRemoved | Should -Be 0
        Should -Invoke Remove-Item -Exactly 0
    }

    It 'does not emit success-stream objects without PassThru' {
        $Result = @(Clear-OldExchangeLog -WhatIf -WarningAction SilentlyContinue)
        $Result | Should -HaveCount 0
        Should -Invoke Remove-Item -Exactly 0
    }

    It 'keeps preview-only behavior when confirmation is disabled' {
        $File = New-Item -Path (Join-Path -Path $LogRoot -ChildPath 'old.log') -ItemType File
        $File.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $Result = Clear-OldExchangeLog -WhatIf -Confirm:$false -PassThru -WarningAction SilentlyContinue
        $Result.FileCandidateCount | Should -Be 1
        $Result.FilesRemoved | Should -Be 0
        $File.FullName | Should -Exist
        Should -Invoke Remove-Item -Exactly 0
    }

    It 'returns a failed result with unknown totals when one root cannot be enumerated' {
        $MessageTrackingRoot = Join-Path -Path $ExchangeRoot -ChildPath 'TransportRoles/Logs/MessageTracking'
        $null = New-Item -Path $MessageTrackingRoot -ItemType Directory -Force
        Mock Get-ChildItem {
            if ([System.IO.Path]::GetFullPath($LiteralPath) -eq [System.IO.Path]::GetFullPath($MessageTrackingRoot)) {
                throw [System.UnauthorizedAccessException]::new('Fixture Exchange root denial.')
            }
            [System.IO.DirectoryInfo]::new($LiteralPath).GetFileSystemInfos()
        }

        $Results = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

        $Results | Should -HaveCount 2
        $Successful = $Results | Where-Object RootPath -EQ ([System.IO.Path]::GetFullPath($LogRoot))
        $Failed = $Results | Where-Object RootPath -EQ ([System.IO.Path]::GetFullPath($MessageTrackingRoot))
        $Successful.Status | Should -Be 'WhatIf'
        $Successful.FileCandidateCount | Should -Be 0
        $Failed.DiscoveryStatus | Should -Be 'Failed'
        $Failed.Status | Should -Be 'DiscoveryFailed'
        $Failed.FileCandidateCount | Should -BeNullOrEmpty
        $Failed.CandidatePaths | Should -BeNullOrEmpty
        $Failed.ErrorIds | Should -Contain 'ExchangeDiscoveryFailed'
    }

    It 'returns a failed result when an existing root fails before normalization' {
        $OutsideRoot = Join-Path -Path $TestDrive -ChildPath 'ExchangeOutsideRoot'
        $null = New-Item -Path $OutsideRoot -ItemType Directory -Force
        [System.IO.Directory]::Delete($LogRoot, $true)
        $null = New-Item -Path $LogRoot -ItemType Junction -Target $OutsideRoot -Force

        $Results = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

        $Failed = $Results | Where-Object RootPath -EQ ([System.IO.Path]::GetFullPath($LogRoot))
        $Failed | Should -Not -BeNullOrEmpty
        $Failed.DiscoveryStatus | Should -Be 'Failed'
        $Failed.Status | Should -Be 'DiscoveryFailed'
        $Failed.FileCandidateCount | Should -BeNullOrEmpty
        $Failed.DirectoryCandidateCount | Should -BeNullOrEmpty
        $Failed.ErrorIds | Should -Contain 'ExchangeDiscoveryFailed'
    }

    It 'returns a failed result when an existing root cannot be probed' {
        Mock Test-Path {
            throw [System.UnauthorizedAccessException]::new('Fixture Exchange root probe denial.')
        } -ParameterFilter { $LiteralPath -eq $LogRoot }

        $Results = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DiscoveryError)

        $Results | Should -HaveCount 1
        $Results[0].RootPath | Should -Be ([System.IO.Path]::GetFullPath($LogRoot))
        $Results[0].DiscoveryStatus | Should -Be 'Failed'
        $Results[0].Status | Should -Be 'DiscoveryFailed'
        $Results[0].FileCandidateCount | Should -BeNullOrEmpty
        $Results[0].ErrorIds | Should -Contain 'ExchangeDiscoveryFailed'
        $DiscoveryError | Should -Not -BeNullOrEmpty
    }

    It 'fails closed when a protected path is nested below a proposed log root' {
        $NestedProtectedPath = Join-Path -Path $LogRoot -ChildPath 'Database'
        $null = New-Item -Path $NestedProtectedPath -ItemType Directory -Force
        $DatabaseFilePath = Join-Path -Path $NestedProtectedPath -ChildPath 'Mailbox.edb'
        $ExistingGetMailboxDatabase = Get-Item -LiteralPath 'Function:\global:Get-MailboxDatabase' -ErrorAction SilentlyContinue
        function global:Get-MailboxDatabase { }
        Mock Get-Command { [pscustomobject]@{ Name = 'Get-MailboxDatabase' } } -ParameterFilter { $Name -eq 'Get-MailboxDatabase' }
        Mock Get-MailboxDatabase {
            [pscustomobject]@{
                EdbFilePath   = $DatabaseFilePath
                LogFolderPath = $NestedProtectedPath
            }
        }

        try {
            $Results = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
        } finally {
            $ExecutionContext.InvokeProvider.Item.Remove('Function:\global:Get-MailboxDatabase', $false)
            if ($null -ne $ExistingGetMailboxDatabase) {
                Set-Item -LiteralPath 'Function:\global:Get-MailboxDatabase' -Value $ExistingGetMailboxDatabase.ScriptBlock -Force
            }
        }

        $Failed = $Results | Where-Object RootPath -EQ ([System.IO.Path]::GetFullPath($LogRoot))
        $Failed | Should -Not -BeNullOrEmpty
        $Failed.DiscoveryStatus | Should -Be 'Failed'
        $Failed.Status | Should -Be 'DiscoveryFailed'
        $Failed.ProtectionStatus | Should -Be 'Validated'
        $Failed.ProtectionPaths | Should -Contain ([System.IO.Path]::GetFullPath($NestedProtectedPath))
        $Failed.FileCandidateCount | Should -BeNullOrEmpty
        $Failed.ErrorIds | Should -Contain 'ExchangeDiscoveryFailed'
    }

    It 'reports an unavailable product when no configured log root exists' {
        [System.IO.Directory]::Delete($LogRoot, $true)

        $Results = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DiscoveryError)

        $Results | Should -HaveCount 1
        $Results[0].RootPath | Should -Be ([System.IO.Path]::GetFullPath($ExchangeRoot))
        $Results[0].DiscoveryStatus | Should -Be 'Failed'
        $Results[0].Status | Should -Be 'DiscoveryFailed'
        $Results[0].FileCandidateCount | Should -BeNullOrEmpty
        $Results[0].DirectoryCandidateCount | Should -BeNullOrEmpty
        $Results[0].CandidatePaths | Should -BeNullOrEmpty
        $Results[0].ErrorIds | Should -Contain 'ExchangeDiscoveryUnavailable'
        $DiscoveryError | Should -Not -BeNullOrEmpty
    }
}

