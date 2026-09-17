BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

Describe 'Disposable ACL harness boundaries and evidence' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeAll {
        $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
        $Harness = Join-Path $RepositoryRoot 'lab/Invoke-TheCleanersAclFixture.ps1'
    }

    BeforeEach {
        $FixtureParent = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $null = New-Item -Path $FixtureParent -ItemType Directory
        $OriginalTemp = $env:TEMP
        $OriginalTmp = $env:TMP
        # The host/filesystem matrix belongs to lab acceptance, not these guards.
        Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Fixture OS'; Version = '10.0'; BuildNumber = 'fixture' } }
        Mock Get-Volume { [pscustomobject]@{ FileSystem = 'NTFS' } }
    }

    AfterEach {
        $env:TEMP = $OriginalTemp
        $env:TMP = $OriginalTmp
    }

    It 'declines under WhatIf before fixture creation or process changes' {
        $BeforeModules = @(Get-Module TheCleaners | ForEach-Object Path)
        $Result = & $Harness -FixtureParent $FixtureParent -WhatIf
        $Result | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $FixtureParent -Force) | Should -HaveCount 0
        $env:TEMP | Should -BeExactly $OriginalTemp
        $env:TMP | Should -BeExactly $OriginalTmp
        @(Get-Module TheCleaners | ForEach-Object Path) | Should -Be $BeforeModules
        Should -Invoke Get-CimInstance -Times 0 -Exactly
    }

    It 'rejects an existing directory outside canonical user temp' {
        { & $Harness -FixtureParent $RepositoryRoot -Confirm:$false } | Should -Throw '*canonical user temp*'
        Should -Invoke Get-CimInstance -Times 0 -Exactly
    }

    It 'rejects a file as the parent' {
        $File = Join-Path $FixtureParent 'not-a-directory'
        Set-Content -LiteralPath $File -Value 'preserve'
        { & $Harness -FixtureParent $File -Confirm:$false } | Should -Throw '*ordinary directories*'
        Get-Content -LiteralPath $File | Should -Be 'preserve'
    }

    It 'rejects a junction ancestor without touching its destination' {
        $Destination = Join-Path $FixtureParent 'destination'
        $Link = Join-Path $FixtureParent 'link'
        $null = New-Item -Path $Destination -ItemType Directory
        $null = New-Item -Path $Link -ItemType Junction -Target $Destination
        try {
            { & $Harness -FixtureParent $Link -Confirm:$false } | Should -Throw '*ordinary directories*'
            @(Get-ChildItem -LiteralPath $Destination -Force) | Should -HaveCount 0
        } finally {
            # Delete only the test-created junction itself, never recurse.
            [IO.Directory]::Delete($Link)
        }
    }

    It 'records identities, WhatIf preservation and completed recovery before reporting success' {
        $Evidence = & $Harness -FixtureParent $FixtureParent -Confirm:$false | ConvertFrom-Json
        $Evidence.RunFailure | Should -BeNullOrEmpty
        $Evidence.FixturePassed | Should -BeTrue
        $Evidence.SchemaVersion | Should -Be 1
        $Evidence.Scope | Should -Be 'IsolatedFixture'
        $Evidence.Commit | Should -Match '^[0-9a-f]{40}$'
        $Evidence.RootIdentity | Should -Not -BeNullOrEmpty
        @($Evidence.BeforeIdentities) | Should -HaveCount 2
        @($Evidence.BeforeIdentities | Where-Object { $_.Identity -and $_.Length -eq 3 }) | Should -HaveCount 2
        @($Evidence.AfterIdentities) | Should -HaveCount 0
        $Evidence.PreviewPreserved | Should -BeTrue
        $Evidence.PreviewInventoryMatches | Should -BeTrue
        @($Evidence.BeforeIdentities | Where-Object { $_.ContentEvidence -eq 'Hashed' -and $_.SHA256 -match '^[0-9A-F]{64}$' }) | Should -HaveCount 1
        $Evidence.PreviewResult.Status | Should -Be 'WhatIf'
        $Evidence.Result.FilesRemoved | Should -Be 2
        $Evidence.Result.BytesReclaimed | Should -Be 6
        $Evidence.ErrorCount | Should -Be 0
        $Evidence.Recovery.Policy | Should -Be 'RetainFixtureForInspection'
        $Evidence.Recovery.EnvironmentRestored | Should -BeTrue
        $Evidence.Recovery.HandlesClosed | Should -BeTrue
        $Evidence.Recovery.RootReopenVerified | Should -BeTrue
        $Evidence.Recovery.RootReopenError | Should -BeNullOrEmpty
        $Evidence.Recovery.HandleCount | Should -BeGreaterThan 1
        $Evidence.Recovery.RecursiveRecoveryAttempted | Should -BeFalse
        $Evidence.Recovery.InventoryError | Should -BeNullOrEmpty
        @($Evidence.Recovery.RemainingEntries) | Should -HaveCount 0
        $Evidence.Acceptance | Should -Be (-not $Evidence.WorkingTreeDirty)
        $Evidence.FixtureRoot | Should -Exist
        $env:TEMP | Should -BeExactly $OriginalTemp
        $env:TMP | Should -BeExactly $OriginalTmp
        # An exclusive rename after return detects leaked ancestry/root handles.
        $Renamed = $FixtureParent + '-released'
        [IO.Directory]::Move($FixtureParent, $Renamed)
        [IO.Directory]::Move($Renamed, $FixtureParent)
    }

    It 'retains failure residue and restores state without recursive ACL reset or removal' {
        Mock Get-CimInstance { throw 'Injected host-evidence failure' }
        $Evidence = & $Harness -FixtureParent $FixtureParent -Confirm:$false | ConvertFrom-Json
        $Evidence.Acceptance | Should -BeFalse
        $Evidence.RunFailure.Message | Should -Match 'Injected host-evidence failure'
        $Evidence.Recovery.EnvironmentRestored | Should -BeTrue
        $Evidence.Recovery.HandlesClosed | Should -BeTrue
        @($Evidence.Recovery.RemainingEntries) | Should -HaveCount 2
        $DeniedPath = Join-Path $Evidence.FixtureRoot 'old-delete-without-read.tmp'
        { Get-Content -LiteralPath $DeniedPath -ErrorAction Stop } | Should -Throw
        $Evidence.Recovery.RecursiveRecoveryAttempted | Should -BeFalse
        $Renamed = $FixtureParent + '-released'
        [IO.Directory]::Move($FixtureParent, $Renamed)
        [IO.Directory]::Move($Renamed, $FixtureParent)
    }

    It 'fails before cleanup when the filesystem cannot be established' {
        Mock Get-Volume { throw 'Injected volume probe failure' }
        $Evidence = & $Harness -FixtureParent $FixtureParent -Confirm:$false | ConvertFrom-Json
        $Evidence.Acceptance | Should -BeFalse
        $Evidence.RunFailure.Message | Should -Match 'volume must be identified'
        @($Evidence.Recovery.RemainingEntries) | Should -HaveCount 2
        $Evidence.Recovery.HandlesClosed | Should -BeTrue
    }

    It 'rejects acceptance when an independent root handle prevents the post-disposal reopen' {
        $Leak = [pscustomobject]@{ Handle = $null }
        Mock Get-CimInstance {
            $RootPath = (Get-ChildItem -LiteralPath $FixtureParent -Directory | Select-Object -First 1).FullName
            $Leak.Handle = [TheCleaners.NativeFileInterop]::OpenForIdentityInspection($RootPath)
            [pscustomobject]@{ Caption = 'Fixture OS'; Version = '10.0'; BuildNumber = 'fixture' }
        }
        try {
            $Evidence = & $Harness -FixtureParent $FixtureParent -Confirm:$false | ConvertFrom-Json
            $Evidence.FixturePassed | Should -BeTrue
            $Evidence.Acceptance | Should -BeFalse
            $Evidence.Recovery.HandlesClosed | Should -BeTrue
            $Evidence.Recovery.RootReopenVerified | Should -BeFalse
            $Evidence.Recovery.RootReopenError.NativeErrorCode | Should -Be 32
            $Evidence.Recovery.ProbeHandleClosed | Should -BeTrue
        } finally {
            if ($null -ne $Leak.Handle) { $Leak.Handle.Dispose() }
        }
    }

    It 'refuses a false preview <Fault> and preserves both candidates' -TestCases @(
        @{ Fault = 'count'; Count = 0; Paths = @() }
        @{ Fault = 'inventory'; Count = 2; Paths = @('C:\wrong-a.tmp', 'C:\wrong-b.tmp') }
    ) {
        param($Fault, $Count, $Paths)
        $PreviewFault = [pscustomobject]@{ Name = $Fault; Count = $Count; Paths = $Paths }
        $Module = Import-Module (Join-Path $RepositoryRoot 'src/TheCleaners/TheCleaners.psd1') -PassThru
        Mock Clear-CurrentUserTemp { [pscustomobject]@{ Status = 'WhatIf'; FileCandidateCount = $PreviewFault.Count; CandidatePaths = $PreviewFault.Paths; FilesRemoved = 0; BytesReclaimed = 0 } } -ModuleName TheCleaners
        $Evidence = & $Harness -FixtureParent $FixtureParent -Confirm:$false | ConvertFrom-Json
        $Evidence.Acceptance | Should -BeFalse
        $Evidence.RunFailure.Message | Should -Match 'WhatIf inventory'
        @($Evidence.Recovery.RemainingEntries) | Should -HaveCount 2
        $Evidence.Recovery.EnvironmentRestored | Should -BeTrue
        $Evidence.Recovery.RootReopenVerified | Should -BeTrue
        Should -Invoke Clear-CurrentUserTemp -ModuleName TheCleaners -Times 1 -Exactly -ParameterFilter { $WhatIf }
        Should -Invoke Clear-CurrentUserTemp -ModuleName TheCleaners -Times 0 -Exactly -ParameterFilter { -not $WhatIf }
    }

    It 'parses the harness and keeps destructive recovery absent' {
        $Tokens = $null
        $ParseErrors = $null
        $Ast = [Management.Automation.Language.Parser]::ParseFile($Harness, [ref]$Tokens, [ref]$ParseErrors)
        $ParseErrors | Should -BeNullOrEmpty
        $Commands = $Ast.FindAll({ param($Node) $Node -is [Management.Automation.Language.CommandAst] }, $true)
        @($Commands | Where-Object { $_.GetCommandName() -in @('Remove-Item', 'icacls.exe', 'Clear-WindowsTemp', 'Clear-OldIISLog', 'Clear-OldExchangeLog') }) | Should -HaveCount 0
    }
}
