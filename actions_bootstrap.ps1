# Bootstrap dependencies

# https://docs.microsoft.com/powershell/module/packagemanagement/get-packageprovider
Get-PackageProvider -Name Nuget -ForceBootstrap | Out-Null

# List of PowerShell Modules required for the build
$modulesToInstall = New-Object System.Collections.Generic.List[object]
# https://github.com/pester/Pester
[void]$modulesToInstall.Add(([PSCustomObject]@{
            ModuleName    = 'Pester'
            ModuleVersion = '5.7.1'
        }))
# https://github.com/nightroman/Invoke-Build
[void]$modulesToInstall.Add(([PSCustomObject]@{
            ModuleName    = 'InvokeBuild'
            ModuleVersion = '5.11.3'
        }))
# https://github.com/PowerShell/PSScriptAnalyzer
[void]$modulesToInstall.Add(([PSCustomObject]@{
            ModuleName    = 'PSScriptAnalyzer'
            ModuleVersion = '1.22.0'
        }))
# https://github.com/PowerShell/platyPS
# Pin the current supported release used by the strict help-generation gate.
[void]$modulesToInstall.Add(([PSCustomObject]@{
            ModuleName    = 'platyPS'
            ModuleVersion = '0.14.2'
        }))

function Resolve-ExactModuleManifest {
    param (
        [Parameter(Mandatory)]
        [string]
        $ModuleName,

        [Parameter(Mandatory)]
        [string]
        $ModuleVersion
    )

    $ModuleRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($Root in @($env:PSModulePath -split [System.IO.Path]::PathSeparator)) {
        if (-not [string]::IsNullOrWhiteSpace($Root) -and -not $ModuleRoots.Contains($Root)) {
            $ModuleRoots.Add($Root)
        }
    }
    $Documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    foreach ($RelativeRoot in @('PowerShell\Modules', 'WindowsPowerShell\Modules')) {
        $DocumentsRoot = Join-Path -Path $Documents -ChildPath $RelativeRoot
        if (-not $ModuleRoots.Contains($DocumentsRoot)) {
            $ModuleRoots.Add($DocumentsRoot)
        }
    }

    foreach ($Root in $ModuleRoots) {
        $Candidate = Join-Path -Path $Root -ChildPath (Join-Path -Path $ModuleName -ChildPath (Join-Path -Path $ModuleVersion -ChildPath "$ModuleName.psd1"))
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $Candidate).Path
        }
    }

    return $null
}

'Installing PowerShell Modules'
foreach ($module in $modulesToInstall) {
    $installSplat = @{
        Name               = $module.ModuleName
        RequiredVersion    = $module.ModuleVersion
        Repository         = 'PSGallery'
        Scope              = 'CurrentUser'
        Force              = $true
        ErrorAction        = 'Stop'
    }
    try {
        $isWindowsPowerShell = $PSVersionTable.PSEdition -eq 'Desktop'
        $isWindowsHost = $isWindowsPowerShell -or ($PSVersionTable.PSVersion.Major -ge 6 -and $IsWindows)
        if ($module.ModuleName -eq 'Pester' -and $isWindowsHost) {
            # Pester 5.7.1 has a known publisher certificate mismatch on Windows.
            # Keep the bypass scoped to this one dependency until the pinned version changes.
            Install-Module @installSplat -SkipPublisherCheck
        } else {
            Install-Module @installSplat
        }
        $ExactManifestPath = Resolve-ExactModuleManifest -ModuleName $module.ModuleName -ModuleVersion $module.ModuleVersion
        if ([string]::IsNullOrWhiteSpace($ExactManifestPath)) {
            throw "The exact installed manifest was not found for $($module.ModuleName) $($module.ModuleVersion)."
        }
        $InstalledManifest = Test-ModuleManifest -Path $ExactManifestPath -ErrorAction Stop
        if ([string]$InstalledManifest.Version -ne [string]$module.ModuleVersion) {
            throw "The installed manifest version '$($InstalledManifest.Version)' does not match '$($module.ModuleVersion)'."
        }
        Import-Module -Name $ExactManifestPath -Force -ErrorAction Stop
        $LoadedModule = Get-Module -Name $module.ModuleName | Sort-Object Version -Descending | Select-Object -First 1
        if ($null -eq $LoadedModule -or [string]$LoadedModule.Version -ne [string]$module.ModuleVersion) {
            throw "The loaded module version did not match '$($module.ModuleVersion)' for $($module.ModuleName)."
        }
        '  - Successfully installed and loaded {0} {1}' -f $module.ModuleName, $module.ModuleVersion
    } catch {
        $message = 'Failed to install {0}' -f $module.ModuleName
        "  - $message"
        throw
    }
}
