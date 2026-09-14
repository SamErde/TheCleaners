# Load only reviewed files, in a deterministic order. Import must have no host or caller-scope side effects.
$PrivateScripts = @(
    'Private/Convert-SIDtoSamAccountName.ps1'
    'Private/Convert-SamAccountNameToSID.ps1'
    'Private/Remove-OldFiles.ps1'
    'Private/Resolve-TheCleanersFileSystemPath.ps1'
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
foreach ($RelativePath in @($PrivateScripts + $PublicScripts)) {
    . (Join-Path -Path $PSScriptRoot -ChildPath $RelativePath)
}

# The manifest is the single export contract, including compatibility aliases.
$Manifest = Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath 'TheCleaners.psd1')
Export-ModuleMember -Function $Manifest.FunctionsToExport -Alias $Manifest.AliasesToExport

