BeforeAll {
    # Do not change the build's current directory: Pester writes its reports after tests finish.
    $ModuleName = 'TheCleaners'
    $ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners'
    $PathToManifest = Join-Path -Path $ModuleRoot -ChildPath 'TheCleaners.psd1'
    $PathToModule = Join-Path -Path $ModuleRoot -ChildPath 'TheCleaners.psm1'
    $ManifestInfo = Test-ModuleManifest -Path $PathToManifest -ErrorAction Stop
}

Describe 'Module Tests' -Tag Unit {
    It 'passes Test-ModuleManifest' {
        { Test-ModuleManifest -Path $PathToManifest -ErrorAction Stop } | Should -Not -Throw
    }

    It 'has an existing root module' {
        $PathToModule | Should -Exist
    }

    It 'references TheCleaners.psm1 in the manifest' {
        $PathToManifest | Should -FileContentMatchExactly 'TheCleaners.psm1'
    }

    It 'has the expected module name' {
        $ManifestInfo.Name | Should -BeExactly $ModuleName
    }

    It 'has a description' {
        $ManifestInfo.Description | Should -Not -BeNullOrEmpty
    }

    It 'has an author' {
        $ManifestInfo.Author | Should -Not -BeNullOrEmpty
    }

    It 'has a valid version' {
        $ManifestInfo.Version -as [Version] | Should -Not -BeNullOrEmpty
    }

    It 'has a valid guid' {
        { [guid]::Parse($ManifestInfo.Guid) } | Should -Not -Throw
    }

    It 'has no spaces in its tags' {
        foreach ($Tag in $ManifestInfo.Tags) {
            $Tag | Should -Not -Match '\s'
        }
    }

    It 'has a project URI' {
        $ManifestInfo.ProjectUri | Should -Not -BeNullOrEmpty
    }
}

