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
}

