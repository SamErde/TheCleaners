BeforeAll {
    $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../..')).Path
    $RehearsalScript = Join-Path -Path $RepositoryRoot -ChildPath '.github/scripts/Invoke-LocalPublicationRehearsal.ps1'

    function Invoke-GitFixtureCommand {
        <#
        .SYNOPSIS
            Run Git in an isolated fixture repository and fail on command errors.
        #>
        param (
            [Parameter(Mandatory)]
            [string]
            $Root,

            [Parameter(Mandatory)]
            [string[]]
            $Arguments
        )

        $DisabledHooksPath = Join-Path -Path $Root -ChildPath '.git-hooks-disabled'
        if (-not (Test-Path -LiteralPath $DisabledHooksPath -PathType Container)) {
            $null = New-Item -Path $DisabledHooksPath -ItemType Directory -Force
        }
        $Output = @(& git -C $Root -c 'commit.gpgsign=false' -c ("core.hooksPath=$DisabledHooksPath") @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Fixture Git command failed: git $($Arguments -join ' ')`n$($Output | Out-String)"
        }
        $Output
    }

    function Initialize-LocalPublicationSourceFixture {
        <#
        .SYNOPSIS
            Create a minimal committed module repository and matching artifact identity.
        #>
        param (
            [Parameter(Mandatory)]
            [string]
            $Root,

            [Parameter()]
            [switch]
            $IgnoreExtraFile
        )

        $ScriptDirectory = Join-Path -Path $Root -ChildPath '.github/scripts'
        $SourceDirectory = Join-Path -Path $Root -ChildPath 'src/TheCleaners'
        $ArtifactDirectory = Join-Path -Path $Root -ChildPath 'src/Artifacts'
        $ArchiveDirectory = Join-Path -Path $Root -ChildPath 'src/Archive'
        $null = New-Item -Path $ScriptDirectory -ItemType Directory -Force
        $null = New-Item -Path $SourceDirectory -ItemType Directory -Force
        $null = New-Item -Path $ArtifactDirectory -ItemType Directory -Force
        $null = New-Item -Path $ArchiveDirectory -ItemType Directory -Force
        Copy-Item -LiteralPath $RehearsalScript -Destination $ScriptDirectory -Force

        $Manifest = @'
@{
    RootModule = 'TheCleaners.psm1'
    ModuleVersion = '0.0.15'
    GUID = '96512386-bbd2-4e95-badd-5d175310bace'
    Author = 'Fixture'
    Description = 'Fixture module'
    FunctionsToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Prerelease = 'beta'
        }
    }
}
'@
        $Manifest | Set-Content -LiteralPath (Join-Path -Path $SourceDirectory -ChildPath 'TheCleaners.psd1') -Encoding UTF8
        '' | Set-Content -LiteralPath (Join-Path -Path $SourceDirectory -ChildPath 'TheCleaners.psm1') -Encoding UTF8
        if ($IgnoreExtraFile) {
            '/src/TheCleaners/ignored.payload' | Set-Content -LiteralPath (Join-Path -Path $Root -ChildPath '.gitignore') -Encoding ASCII
        }

        $null = Invoke-GitFixtureCommand -Root $Root -Arguments @('init', '--quiet')
        $null = Invoke-GitFixtureCommand -Root $Root -Arguments @('config', 'user.name', 'TheCleaners Fixture')
        $null = Invoke-GitFixtureCommand -Root $Root -Arguments @('config', 'user.email', 'fixture@example.invalid')
        $null = Invoke-GitFixtureCommand -Root $Root -Arguments @('add', '.github/scripts/Invoke-LocalPublicationRehearsal.ps1', 'src/TheCleaners')
        if ($IgnoreExtraFile) {
            $null = Invoke-GitFixtureCommand -Root $Root -Arguments @('add', '.gitignore')
        }
        $null = Invoke-GitFixtureCommand -Root $Root -Arguments @('commit', '--quiet', '-m', 'fixture')
        $Commit = [string](Invoke-GitFixtureCommand -Root $Root -Arguments @('rev-parse', 'HEAD') | Select-Object -First 1)
        $Commit = $Commit.Trim()

        Copy-Item -LiteralPath (Join-Path -Path $SourceDirectory -ChildPath 'TheCleaners.psd1') -Destination $ArtifactDirectory -Force
        Copy-Item -LiteralPath (Join-Path -Path $SourceDirectory -ChildPath 'TheCleaners.psm1') -Destination $ArtifactDirectory -Force
        [ordered]@{
            ModuleName = 'TheCleaners'
            ModuleVersion = '0.0.15'
            Commit = $Commit
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $ArchiveDirectory -ChildPath 'TheCleaners_0.0.15.manifest.json') -Encoding UTF8

        $ExtraName = if ($IgnoreExtraFile) { 'ignored.payload' } else { 'ordinary.payload' }
        'untracked payload' | Set-Content -LiteralPath (Join-Path -Path $SourceDirectory -ChildPath $ExtraName) -Encoding UTF8

        [pscustomobject]@{
            ScriptPath = Join-Path -Path $ScriptDirectory -ChildPath 'Invoke-LocalPublicationRehearsal.ps1'
            ArtifactPath = $ArtifactDirectory
            ArchiveDirectory = $ArchiveDirectory
            ExtraRelativePath = 'src/TheCleaners/{0}' -f $ExtraName
            OutputPath = Join-Path -Path $Root -ChildPath 'Rehearsal.json'
        }
    }
}

Describe 'Local publication source identity' -Tag Unit {
    BeforeEach {
        Mock Register-PSRepository { throw 'Repository registration must not be reached.' }
    }

    It 'refuses an ordinary untracked module source file before repository registration' {
        $Fixture = Initialize-LocalPublicationSourceFixture -Root (Join-Path -Path $TestDrive -ChildPath 'Ordinary')
        $Listed = @(Invoke-GitFixtureCommand -Root (Join-Path -Path $TestDrive -ChildPath 'Ordinary') -Arguments @('ls-files', '--others', '--', 'src/TheCleaners'))
        $Listed | Should -Contain $Fixture.ExtraRelativePath

        $Parameters = @{
            ArtifactPath = $Fixture.ArtifactPath
            ArchiveDirectory = $Fixture.ArchiveDirectory
            OutputPath = $Fixture.OutputPath
        }
        { & $Fixture.ScriptPath @Parameters } | Should -Throw '*refuses untracked module source files*ordinary.payload*'
        Should -Invoke Register-PSRepository -Times 0 -Exactly
    }

    It 'refuses an ignored untracked module source file before repository registration' {
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath 'Ignored'
        $Fixture = Initialize-LocalPublicationSourceFixture -Root $FixtureRoot -IgnoreExtraFile
        $DefaultStatus = @(Invoke-GitFixtureCommand -Root $FixtureRoot -Arguments @('status', '--short', '--untracked-files=all'))
        $DefaultStatus -join "`n" | Should -Not -Match 'ignored\.payload'
        $Listed = @(Invoke-GitFixtureCommand -Root $FixtureRoot -Arguments @('ls-files', '--others', '--', 'src/TheCleaners'))
        $Listed | Should -Contain $Fixture.ExtraRelativePath

        $Parameters = @{
            ArtifactPath = $Fixture.ArtifactPath
            ArchiveDirectory = $Fixture.ArchiveDirectory
            OutputPath = $Fixture.OutputPath
        }
        { & $Fixture.ScriptPath @Parameters } | Should -Throw '*refuses untracked module source files*ignored.payload*'
        Should -Invoke Register-PSRepository -Times 0 -Exactly
    }
}
