BeforeAll {
    $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../..')).Path
    $BuildPath = Join-Path -Path $RepositoryRoot -ChildPath 'src/TheCleaners.build.ps1'
    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($BuildPath, [ref]$Tokens, [ref]$ParseErrors)
    $Definition = $Ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Get-BuildCommitId' }, $true)
    # Load only the build identity function, without registering or running build tasks.
    . ([scriptblock]::Create($Definition.Extent.Text))
    # Keep identity fixtures independent of Git installation and checkout state.
    function Invoke-GitFixture {
        <#
        .SYNOPSIS
            Provide a local Git command seam without requiring an installed executable.
        #>
        throw 'Git is unavailable in this isolated fixture.'
    }
    Set-Alias -Name git -Value Invoke-GitFixture
}

Describe 'Build commit identity' -Tag Unit {
    BeforeEach {
        $PreviousExpectedCommit = $env:TC_BUILD_COMMIT
        $env:TC_BUILD_COMMIT = $null
        $BuildRoot = $RepositoryRoot
    }

    AfterEach {
        $env:TC_BUILD_COMMIT = $PreviousExpectedCommit
    }

    It 'permits a local source archive without claiming a commit' {
        $BuildRoot = $TestDrive
        Get-BuildCommitId | Should -Be 'unavailable'
    }

    It 'permits a local build when git is unavailable' {
        Mock git { throw 'git is unavailable' }
        Get-BuildCommitId | Should -Be 'unavailable'
    }

    It 'refuses unavailable identity when CI specifies an expected commit' {
        $BuildRoot = $TestDrive
        $env:TC_BUILD_COMMIT = 'a' * 40
        { Get-BuildCommitId } | Should -Throw '*Cannot establish*'
    }

    It 'refuses a different checked-out commit in CI' {
        Mock git { 'a' * 40 }
        $env:TC_BUILD_COMMIT = '0' * 40
        { Get-BuildCommitId } | Should -Throw '*differs from expected*'
    }

    It 'records the verified checked-out commit in CI' {
        Mock git { 'a' * 40 }
        $env:TC_BUILD_COMMIT = 'a' * 40
        Get-BuildCommitId | Should -Be $env:TC_BUILD_COMMIT
    }
}
