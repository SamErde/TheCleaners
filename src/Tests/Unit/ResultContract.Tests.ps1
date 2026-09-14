BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/ResultContracts.ps1')
}

Describe 'Shared result and error contracts' -Tag Unit {
    It 'returns the documented cleanup fields and UTC cutoff' {
        $Cutoff = [DateTime]::SpecifyKind([DateTime]::Now.AddDays(-30), [DateTimeKind]::Local)
        $Result = Get-TheCleanersCleanupResult -Command 'Test-Command' -RootPath 'C:\Fixture\Temp' -CutoffUtc $Cutoff -CandidatePaths @('C:\Fixture\Temp\old.tmp') -Status 'WhatIf'
        $ExpectedFields = @(
            'ContractVersion'
            'Command'
            'RootPath'
            'CutoffUtc'
            'DiscoveryStatus'
            'DiscoverySource'
            'DisplayName'
            'ProtectionStatus'
            'ProtectionPathCount'
            'PrivilegeStatus'
            'ProductVersion'
            'CandidatePaths'
            'FileCandidateCount'
            'FilesRemoved'
            'FileFailureCount'
            'FilesSkipped'
            'DirectoryCandidateCount'
            'DirectoriesRemoved'
            'DirectoryFailureCount'
            'DirectoriesSkipped'
            'BytesReclaimed'
            'DiscoveryErrorCount'
            'ErrorIds'
            'Status'
        )

        foreach ($Field in $ExpectedFields) {
            $Result.PSObject.Properties.Name | Should -Contain $Field
        }
        $Result.PSTypeNames | Should -Contain 'TheCleaners.CleanupResult'
        $Result.ContractVersion | Should -Be '1.0'
        $Result.CutoffUtc.Kind | Should -Be ([DateTimeKind]::Utc)
        $Result.Status | Should -Be 'WhatIf'
        $Result.FilesRemoved | Should -Be 0
        $Result.ErrorIds | Should -BeNullOrEmpty
    }

    It 'creates a stable fully qualified error ID and category' {
        $Exception = [System.InvalidOperationException]::new('fixture failure')
        $ErrorRecord = Get-TheCleanersErrorRecord -Exception $Exception -ErrorId 'FixtureStableError' -Category ([System.Management.Automation.ErrorCategory]::PermissionDenied) -TargetObject 'fixture'

        $ErrorRecord.FullyQualifiedErrorId | Should -Match '^FixtureStableError'
        $ErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::PermissionDenied)
        $ErrorRecord.TargetObject | Should -Be 'fixture'
        $ErrorRecord.Exception | Should -Be $Exception
    }
}
