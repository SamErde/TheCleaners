#-------------------------------------------------------------------------
BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ModuleName = 'TheCleaners'
    $PathToManifest = [System.IO.Path]::Combine('..', '..', $ModuleName, "$ModuleName.psd1")
    if (Get-Module -Name $ModuleName -ErrorAction 'SilentlyContinue') {
        Remove-Module -Name $ModuleName -Force
    }
    Import-Module $PathToManifest -Force
    $manifestContent = Test-ModuleManifest -Path $PathToManifest
    # Limit the runtime query to functions so it matches the manifest's ExportedFunctions collection.
    $moduleExported = Get-Command -Module $ModuleName -CommandType Function | Select-Object -ExpandProperty Name
    $manifestExported = ($manifestContent.ExportedFunctions).Keys
}

Describe $ModuleName {

    Context 'Exported Commands' -Fixture {

        Context 'Number of commands' -Fixture {
            It -Name 'Exports the same number of public functions as what is listed in the Module Manifest' -Test {
                $manifestExported.Count | Should -BeExactly $moduleExported.Count
            }
        }

        Context 'Explicitly exported commands' {
            It -Name 'Includes <_> in the Module Manifest ExportedFunctions' -ForEach $moduleExported -Test {
                $manifestExported | Should -Contain $_
            }
        }
    }

    Context 'Command Help' {
        It -Name '<_> includes complete help' -ForEach $moduleExported -Test {
            $help = Get-Help -Name $_ -Full

            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.description.Text | Should -Not -BeNullOrEmpty
            $help.examples.example | Should -Not -BeNullOrEmpty
        }
    }
}

