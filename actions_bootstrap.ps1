# Bootstrap dependencies

# https://docs.microsoft.com/powershell/module/packagemanagement/get-packageprovider
Get-PackageProvider -Name Nuget -ForceBootstrap | Out-Null

# List of PowerShell Modules required for the build
$modulesToInstall = New-Object System.Collections.Generic.List[object]
# https://github.com/pester/Pester
[void]$modulesToInstall.Add(([PSCustomObject]@{
            ModuleName    = 'Pester'
            ModuleVersion = '5.6.1'
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
# older version used due to: https://github.com/PowerShell/platyPS/issues/457
[void]$modulesToInstall.Add(([PSCustomObject]@{
            ModuleName    = 'platyPS'
            ModuleVersion = '0.12.0'
        }))

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
            # Pester 5.6.1 has a known publisher certificate mismatch on Windows.
            # Keep the bypass scoped to this one dependency until the pinned version changes.
            Install-Module @installSplat -SkipPublisherCheck
        } else {
            Install-Module @installSplat
        }
        Import-Module -Name $module.ModuleName -ErrorAction Stop
        '  - Successfully installed {0}' -f $module.ModuleName
    } catch {
        $message = 'Failed to install {0}' -f $module.ModuleName
        "  - $message"
        throw
    }
}
