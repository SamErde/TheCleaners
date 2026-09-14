BeforeDiscovery {
    $ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners/TheCleaners.psd1'
    $ManifestData = Import-PowerShellDataFile -Path $ManifestPath
    $FunctionCases = @($ManifestData.FunctionsToExport | ForEach-Object { @{ CommandName = $_ } })
}

BeforeAll {
    $ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners/TheCleaners.psd1'
    $ManifestData = Import-PowerShellDataFile -Path $ManifestPath
    $PreviousModule = Get-Module -Name TheCleaners
    $Module = Import-Module -Name $ManifestPath -Force -PassThru -ErrorAction Stop
}

AfterAll {
    if ($null -ne $PreviousModule) {
        # Preserve a module loaded by the build before Pester; help generation follows these tests.
        $PreviousManifestPath = Join-Path -Path $PreviousModule.ModuleBase -ChildPath 'TheCleaners.psd1'
        Import-Module -Name $PreviousManifestPath -Global -Force -ErrorAction Stop
    } else {
        Remove-Module -Name TheCleaners -Force -ErrorAction SilentlyContinue
    }
}

Describe 'TheCleaners public API' -Tag Unit {
    It 'exports exactly the functions in the manifest' {
        @(Compare-Object -ReferenceObject @($ManifestData.FunctionsToExport) -DifferenceObject @($Module.ExportedFunctions.Keys)) | Should -HaveCount 0
    }

    It 'exports exactly the compatibility aliases in the manifest' {
        @(Compare-Object -ReferenceObject @($ManifestData.AliasesToExport) -DifferenceObject @($Module.ExportedAliases.Keys)) | Should -HaveCount 0
    }

    It 'retains Start-Cleaning as an alias, not a second public function' {
        $Module.ExportedAliases['Start-Cleaning'].Definition | Should -Be 'Get-TheCleaners'
        $Module.ExportedFunctions.ContainsKey('Start-Cleaning') | Should -BeFalse
    }

    It 'does not expose the logo helper' {
        $Module.ExportedFunctions.ContainsKey('Show-TheCleanersLogo') | Should -BeFalse
    }

    It 'has no import-time scripts or exported variables' {
        $ManifestData.ScriptsToProcess | Should -BeNullOrEmpty
        @($Module.ExportedVariables.Keys).Count | Should -Be 0
    }

    It 'returns typed inventory without claiming prerelease commands are stable' {
        $Inventory = @(Get-TheCleaners -NoLogo)
        $Inventory.Count | Should -Be $ManifestData.FunctionsToExport.Count
        foreach ($Item in $Inventory) {
            $Item.PSObject.TypeNames | Should -Contain 'TheCleaners.CommandInfo'
            $Item.Maturity | Should -Not -Be 'Stable'
        }
        foreach ($CommandName in @('Clear-OldIISLog', 'Clear-OldExchangeLog')) {
            $PreviewCommand = $Inventory | Where-Object Name -EQ $CommandName
            $PreviewCommand.Maturity | Should -Be 'PreviewOnly'
            $PreviewCommand.RemovalEnabled | Should -BeFalse
        }
    }

    It 'keeps the IIS and Exchange locks through their legacy aliases' {
        { TheCleaners\Clean-IISLog -Confirm:$false } | Should -Throw '*preview-only*'
        { TheCleaners\Clean-ExchangeLog -Confirm:$false } | Should -Throw '*preview-only*'
    }

    It '<CommandName> has synopsis, description, and examples' -ForEach $FunctionCases {
        $Help = Get-Help -Name ('TheCleaners\' + $CommandName) -Full
        $Help.Synopsis | Should -Not -BeNullOrEmpty
        $Help.Description.Text | Should -Not -BeNullOrEmpty
        $Help.Examples.Example | Should -Not -BeNullOrEmpty
    }
}
