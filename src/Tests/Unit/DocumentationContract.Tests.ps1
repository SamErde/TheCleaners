BeforeAll {
    $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../..')).Path
    $ModuleRoot = Join-Path -Path $RepositoryRoot -ChildPath 'src/TheCleaners'
    $ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'TheCleaners.psd1'
    $Manifest = Import-PowerShellDataFile -Path $ManifestPath
}

Describe 'Documentation and release-contract drift' -Tag Unit {
    It 'has a reference page for every exported function' {
        foreach ($FunctionName in @($Manifest.FunctionsToExport)) {
            $DocumentationPath = Join-Path -Path $RepositoryRoot -ChildPath ('docs/{0}.md' -f $FunctionName)
            $DocumentationPath | Should -Exist
        }
    }

    It 'keeps source help complete and linked to the canonical site' {
        foreach ($FunctionName in @($Manifest.FunctionsToExport)) {
            $FunctionPath = Join-Path -Path $ModuleRoot -ChildPath ('Public/{0}.ps1' -f $FunctionName)
            $Source = Get-Content -LiteralPath $FunctionPath -Raw
            $Source | Should -Match '\.SYNOPSIS'
            $Source | Should -Match '\.EXAMPLE'
            $Source | Should -Match 'https://day3bits\.com/thecleaners/'
        }
    }

    It 'does not retain retired deletion terminology in user documentation' {
        $DocumentationFiles = @(Get-ChildItem -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath 'docs') -Filter '*.md' -File)
        $DocumentationText = $DocumentationFiles | Get-Content -Raw
        $DocumentationText -join [Environment]::NewLine | Should -Not -Match 'Remove-OldFiles'
        $DocumentationText -join [Environment]::NewLine | Should -Not -Match 'DeleteOnClose'
    }

    It 'includes the contract, lab, and deployment gate in the site navigation' {
        $MkDocs = Get-Content -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath 'mkdocs.yml') -Raw
        foreach ($PageName in @('command-contracts.md', 'lab-acceptance.md', 'deployment-validation.md')) {
            $MkDocs | Should -Match ([regex]::Escape($PageName))
            (Join-Path -Path $RepositoryRoot -ChildPath ('docs/{0}' -f $PageName)) | Should -Exist
        }
        $MkDocs | Should -Match 'https://day3bits\.com/thecleaners/'
    }
}
