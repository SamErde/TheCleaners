BeforeAll {
    $SourceModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    $PreviousModule = Get-Module -Name TheCleaners

    function Copy-TheCleanersFixture {
        param (
            [Parameter(Mandatory)]
            [string]
            $Name
        )

        $FixtureParent = Join-Path -Path $TestDrive -ChildPath $Name
        $FixtureModuleRoot = Join-Path -Path $FixtureParent -ChildPath 'TheCleaners'
        $null = New-Item -Path $FixtureModuleRoot -ItemType Directory -Force
        Copy-Item -Path (Join-Path -Path $SourceModuleRoot -ChildPath '*') -Destination $FixtureModuleRoot -Recurse -Force
        $FixtureModuleRoot
    }
}

BeforeEach {
    Remove-Module -Name TheCleaners -Force -ErrorAction SilentlyContinue
}

AfterEach {
    Remove-Module -Name TheCleaners -Force -ErrorAction SilentlyContinue
}

AfterAll {
    if ($null -ne $PreviousModule) {
        $PreviousManifestPath = Join-Path -Path $PreviousModule.ModuleBase -ChildPath 'TheCleaners.psd1'
        Import-Module -Name $PreviousManifestPath -Global -Force -ErrorAction Stop
    }
}

Describe 'TheCleaners fail-closed module loading' -Tag Unit {
    It 'fails import when a required script is missing' {
        $FixtureModuleRoot = Copy-TheCleanersFixture -Name 'MissingScript'
        Remove-Item -LiteralPath (Join-Path -Path $FixtureModuleRoot -ChildPath 'Public/Get-TheCleaners.ps1') -Force
        $ManifestPath = Join-Path -Path $FixtureModuleRoot -ChildPath 'TheCleaners.psd1'

        { Import-Module -Name $ManifestPath -Force -ErrorAction Stop } | Should -Throw '*cannot load a required script*'
    }

    It 'fails import when a dot-sourced script writes a non-terminating error' {
        $FixtureModuleRoot = Copy-TheCleanersFixture -Name 'ScriptError'
        $ScriptPath = Join-Path -Path $FixtureModuleRoot -ChildPath 'Private/Show-TheCleanersLogo.ps1'
        $ScriptText = [System.IO.File]::ReadAllText($ScriptPath)
        [System.IO.File]::WriteAllText($ScriptPath, "Write-Error 'Fixture load failure.'`r`n$ScriptText")
        $ManifestPath = Join-Path -Path $FixtureModuleRoot -ChildPath 'TheCleaners.psd1'

        { Import-Module -Name $ManifestPath -Force -ErrorAction Stop } | Should -Throw '*failed to load*Fixture load failure*'
    }

    It 'fails import when the manifest exports a function that was not loaded' {
        $FixtureModuleRoot = Copy-TheCleanersFixture -Name 'MissingExport'
        $ManifestPath = Join-Path -Path $FixtureModuleRoot -ChildPath 'TheCleaners.psd1'
        $ManifestText = [System.IO.File]::ReadAllText($ManifestPath)
        $ManifestText = $ManifestText.Replace("'Get-TheCleaners'", "'Get-TheCleaners',`r`n        'Missing-TheCleanersFunction'")
        [System.IO.File]::WriteAllText($ManifestPath, $ManifestText)

        { Import-Module -Name $ManifestPath -Force -ErrorAction Stop } | Should -Throw '*manifest exports functions that were not loaded*Missing-TheCleanersFunction*'
    }
}
