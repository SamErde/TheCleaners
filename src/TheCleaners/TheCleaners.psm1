# Load only reviewed files, in a deterministic order. Import must have no host or caller-scope side effects.
$PrivateScripts = @(
    'Private/ResultContracts.ps1'
    'Private/Initialize-TheCleanersNativeFileInterop.ps1'
    'Private/Get-TheCleanersWindowsTempRoot.ps1'
    'Private/Get-TheCleanersTempPlan.ps1'
    'Private/Resolve-TheCleanersFileSystemPath.ps1'
    'Private/Test-TheCleanersIisLogFileName.ps1'
    'Private/Test-TheCleanersIisProtectedPath.ps1'
    'Private/Test-TheCleanersExchangeLogFileName.ps1'
    'Private/Get-TheCleanersExchangeProtectedPaths.ps1'
    'Private/Show-TheCleanersLogo.ps1'
)
$PublicScripts = @(
    'Public/Clear-CurrentUserTemp.ps1'
    'Public/Clear-WindowsTemp.ps1'
    'Public/Clear-OldIISLog.ps1'
    'Public/Clear-OldExchangeLog.ps1'
    'Public/Get-StaleUserProfile.ps1'
    'Public/Get-TheCleaners.ps1'
)
$ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'TheCleaners.psd1'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "TheCleaners cannot load its module manifest: $ManifestPath"
}
$Manifest = Import-PowerShellDataFile -Path $ManifestPath

foreach ($RelativePath in @($PrivateScripts + $PublicScripts)) {
    $ScriptPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "TheCleaners cannot load a required script: $ScriptPath"
    }

    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'
        . $ScriptPath
    } catch {
        throw [System.InvalidOperationException]::new("TheCleaners failed to load '$ScriptPath': $($_.Exception.Message)", $_.Exception)
    } finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
}

$MissingFunctions = @(
    $Manifest.FunctionsToExport | Where-Object {
        -not (Test-Path -LiteralPath ('Function:\{0}' -f $_))
    }
)
if ($MissingFunctions.Count -gt 0) {
    throw "TheCleaners manifest exports functions that were not loaded: $($MissingFunctions -join ', ')"
}

# The manifest is the single export contract, including compatibility aliases.
Export-ModuleMember -Function $Manifest.FunctionsToExport -Alias $Manifest.AliasesToExport

