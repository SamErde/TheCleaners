BeforeAll {
    $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../..')).Path
    $SourceModulePath = Join-Path -Path $RepositoryRoot -ChildPath 'src/TheCleaners'
    $FixtureCommit = 'a' * 40
    $FixtureTag = 'v0.0.15-beta'

    function Initialize-RepositoryModuleCheckerFixture {
        <#
        .SYNOPSIS
            Create an isolated installed-module and content-manifest fixture.
        #>
        param (
            [Parameter(Mandatory)]
            [string]
            $Root
        )

        $ModuleSearchRoot = Join-Path -Path $Root -ChildPath 'Modules'
        $ModulePath = Join-Path -Path $ModuleSearchRoot -ChildPath 'TheCleaners/0.0.15'
        $null = New-Item -Path $ModulePath -ItemType Directory -Force
        foreach ($Item in @(Get-ChildItem -LiteralPath $SourceModulePath -Force)) {
            Copy-Item -LiteralPath $Item.FullName -Destination $ModulePath -Recurse -Force
        }

        $FileRecords = @()
        foreach ($File in @(Get-ChildItem -LiteralPath $ModulePath -File -Recurse -Force | Sort-Object FullName)) {
            $FileRecords += [ordered]@{
                Path = $File.FullName.Substring($ModulePath.Length + 1).Replace('\', '/')
                Length = $File.Length
                SHA256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
        $ArchiveManifestPath = Join-Path -Path $Root -ChildPath 'TheCleaners_0.0.15.manifest.json'
        [ordered]@{
            ModuleName = 'TheCleaners'
            ModuleVersion = '0.0.15'
            Commit = $FixtureCommit
            Files = $FileRecords
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ArchiveManifestPath -Encoding UTF8
        '<Objs />' | Set-Content -LiteralPath (Join-Path -Path $ModulePath -ChildPath 'PSGetModuleInfo.xml') -Encoding UTF8

        [pscustomobject]@{
            ModulePath = $ModulePath
            ModuleSearchRoot = $ModuleSearchRoot
            ArchiveManifestPath = $ArchiveManifestPath
            CheckerPath = Join-Path -Path $RepositoryRoot -ChildPath '.github/scripts/Test-RepositoryModule.ps1'
        }
    }

    function Get-CheckerParameter {
        <#
        .SYNOPSIS
            Return the common installed-module checker parameters for a fixture.
        #>
        param (
            [Parameter(Mandatory)]
            [psobject]
            $Fixture
        )

        @{
            ModulePath = $Fixture.ModulePath
            ModuleSearchRoot = $Fixture.ModuleSearchRoot
            ArchiveManifestPath = $Fixture.ArchiveManifestPath
            ExpectedCommit = $FixtureCommit
            ExpectedTag = $FixtureTag
            RepositoryName = 'FixtureRepository'
        }
    }
}

Describe 'Repository-installed module payload checker' -Tag Unit {
    It 'rejects an altered same-length payload file' {
        $Fixture = Initialize-RepositoryModuleCheckerFixture -Root (Join-Path -Path $TestDrive -ChildPath 'AlteredPayload')
        $PayloadPath = Join-Path -Path $Fixture.ModulePath -ChildPath 'Public/Get-TheCleaners.ps1'
        $Bytes = [System.IO.File]::ReadAllBytes($PayloadPath)
        $Bytes[0] = $Bytes[0] -bxor 1
        [System.IO.File]::WriteAllBytes($PayloadPath, $Bytes)

        $Parameters = Get-CheckerParameter -Fixture $Fixture
        { & $Fixture.CheckerPath @Parameters } | Should -Throw '*digest mismatch*'
    }

    It 'rejects an unexpected installed file' {
        $Fixture = Initialize-RepositoryModuleCheckerFixture -Root (Join-Path -Path $TestDrive -ChildPath 'UnexpectedFile')
        'unexpected' | Set-Content -LiteralPath (Join-Path -Path $Fixture.ModulePath -ChildPath 'unexpected.txt')

        $Parameters = Get-CheckerParameter -Fixture $Fixture
        { & $Fixture.CheckerPath @Parameters } | Should -Throw '*installed file set differs*'
    }

    It 'rejects a nested PSGetModuleInfo.xml as an additional metadata file' {
        $Fixture = Initialize-RepositoryModuleCheckerFixture -Root (Join-Path -Path $TestDrive -ChildPath 'NestedMetadata')
        $NestedPath = Join-Path -Path $Fixture.ModulePath -ChildPath 'Nested/PSGetModuleInfo.xml'
        $null = New-Item -Path ([System.IO.Path]::GetDirectoryName($NestedPath)) -ItemType Directory -Force
        '<Objs />' | Set-Content -LiteralPath $NestedPath

        $Parameters = Get-CheckerParameter -Fixture $Fixture
        { & $Fixture.CheckerPath @Parameters } | Should -Throw '*installed file set differs*'
    }

    It 'rejects a tag whose base version differs from the artifact manifest' {
        $Fixture = Initialize-RepositoryModuleCheckerFixture -Root (Join-Path -Path $TestDrive -ChildPath 'WrongTag')
        $Parameters = Get-CheckerParameter -Fixture $Fixture
        $Parameters.ExpectedTag = 'v0.0.16-beta'

        { & $Fixture.CheckerPath @Parameters } | Should -Throw '*archive manifest version does not match*'
    }

    It 'rejects a commit that differs from the artifact manifest' {
        $Fixture = Initialize-RepositoryModuleCheckerFixture -Root (Join-Path -Path $TestDrive -ChildPath 'WrongCommit')
        $Parameters = Get-CheckerParameter -Fixture $Fixture
        $Parameters.ExpectedCommit = 'b' * 40

        { & $Fixture.CheckerPath @Parameters } | Should -Throw '*archive manifest commit does not match*'
    }
}
