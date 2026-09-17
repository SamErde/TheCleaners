<#
.SYNOPSIS
    Verify a repository-installed TheCleaners module against its tested artifact manifest.
.DESCRIPTION
    Compares every installed payload file with the exact build content manifest,
    permits only PowerShellGet's root PSGetModuleInfo.xml metadata file, and checks
    quiet imports, exports, aliases, help, inventory, and the IIS/Exchange preview
    locks. This verifies payload identity; it does not establish package-signature
    trust or any product/lab acceptance.
.PARAMETER ModulePath
    Installed version directory containing TheCleaners.psd1.
.PARAMETER ModuleSearchRoot
    Isolated PSModulePath root containing the TheCleaners module directory.
.PARAMETER ArchiveManifestPath
    Exact build content manifest associated with the published artifact.
.PARAMETER ExpectedCommit
    Forty-character Git commit recorded by the build content manifest.
.PARAMETER ExpectedTag
    Synthetic or real release tag whose base version and prerelease label must match.
.PARAMETER RepositoryName
    Repository used to acquire the installed module, recorded as evidence.
.PARAMETER OutputPath
    Optional JSON evidence path.
.EXAMPLE
    ./Test-RepositoryModule.ps1 -ModulePath $SavedModule -ModuleSearchRoot $SaveRoot -ArchiveManifestPath $Manifest -ExpectedCommit $Commit -ExpectedTag v0.0.15-beta -RepositoryName $Repository
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ModulePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ModuleSearchRoot,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ArchiveManifestPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string]
    $ExpectedCommit,

    [Parameter(Mandatory)]
    [ValidatePattern('^v\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$')]
    [string]
    $ExpectedTag,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $RepositoryName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $OutputPath
)

$ErrorActionPreference = 'Stop'

function Write-RepositoryEvidence {
    <#
    .SYNOPSIS
        Write deterministic UTF-8 JSON evidence.
    #>
    param (
        [Parameter(Mandatory)]
        [psobject]
        $InputObject,

        [Parameter(Mandatory)]
        [string]
        $Path
    )

    $ResolvedOutputPath = [System.IO.Path]::GetFullPath($Path)
    $OutputDirectory = [System.IO.Path]::GetDirectoryName($ResolvedOutputPath)
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force -ErrorAction Stop
    }
    $Json = $InputObject | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($ResolvedOutputPath, $Json, [System.Text.UTF8Encoding]::new($false))
}

$ResolvedModulePath = (Resolve-Path -LiteralPath $ModulePath -ErrorAction Stop).Path.TrimEnd([char[]]@('\', '/'))
$ResolvedModuleSearchRoot = (Resolve-Path -LiteralPath $ModuleSearchRoot -ErrorAction Stop).Path.TrimEnd([char[]]@('\', '/'))
$ResolvedArchiveManifestPath = (Resolve-Path -LiteralPath $ArchiveManifestPath -ErrorAction Stop).Path
if ($ResolvedModulePath -notlike ($ResolvedModuleSearchRoot + '\*')) {
    throw 'The installed module path must be beneath the isolated module search root.'
}

$ArchiveManifest = Get-Content -LiteralPath $ResolvedArchiveManifestPath -Raw | ConvertFrom-Json
if ($ArchiveManifest.ModuleName -ne 'TheCleaners') {
    throw 'The archive manifest does not describe TheCleaners.'
}
if ([string]$ArchiveManifest.Commit -ne $ExpectedCommit) {
    throw 'The archive manifest commit does not match the expected commit.'
}
if ($ExpectedTag -notmatch '^v(?<Version>\d+\.\d+\.\d+)(-(?<Prerelease>[A-Za-z0-9.-]+))?$') {
    throw 'The expected tag is invalid.'
}
$ExpectedVersion = [string]$Matches.Version
$ExpectedPrerelease = [string]$Matches.Prerelease
if ([string]$ArchiveManifest.ModuleVersion -ne $ExpectedVersion) {
    throw 'The archive manifest version does not match the expected tag.'
}

$InstalledManifestPath = Join-Path -Path $ResolvedModulePath -ChildPath 'TheCleaners.psd1'
$InstalledManifest = Test-ModuleManifest -Path $InstalledManifestPath -ErrorAction Stop
$InstalledPrerelease = [string]$InstalledManifest.PrivateData.PSData.Prerelease
if ($InstalledManifest.Name -ne 'TheCleaners' -or [string]$InstalledManifest.Version -ne $ExpectedVersion) {
    throw 'The installed module name or base version does not match the expected tag.'
}
if ($InstalledPrerelease -ne $ExpectedPrerelease) {
    throw 'The installed module prerelease label does not match the expected tag.'
}

$ExpectedPayloadFiles = @($ArchiveManifest.Files | ForEach-Object { [string]$_.Path } | Sort-Object)
if ($ExpectedPayloadFiles.Count -eq 0) {
    throw 'The archive manifest contains no payload files.'
}
$ActualFiles = @(Get-ChildItem -LiteralPath $ResolvedModulePath -File -Recurse -Force)
$ActualRelativeFiles = @($ActualFiles | ForEach-Object {
        $_.FullName.Substring($ResolvedModulePath.Length + 1).Replace('\', '/')
    } | Sort-Object)
$MetadataRelativePath = 'PSGetModuleInfo.xml'
$ExpectedInstalledFiles = @($ExpectedPayloadFiles + $MetadataRelativePath | Sort-Object)
$FileDifferences = @(Compare-Object -ReferenceObject $ExpectedInstalledFiles -DifferenceObject $ActualRelativeFiles)
if ($FileDifferences.Count -gt 0) {
    throw 'The repository-installed file set differs from the tested payload plus PSGetModuleInfo.xml.'
}

$MetadataPath = Join-Path -Path $ResolvedModulePath -ChildPath $MetadataRelativePath
try {
    $null = [xml](Get-Content -LiteralPath $MetadataPath -Raw -ErrorAction Stop)
} catch {
    throw "PSGetModuleInfo.xml is missing or invalid XML: $($_.Exception.Message)"
}

foreach ($FileRecord in @($ArchiveManifest.Files)) {
    $RelativePath = [string]$FileRecord.Path
    $InstalledFile = Join-Path -Path $ResolvedModulePath -ChildPath ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $InstalledFile -PathType Leaf)) {
        throw "The repository-installed module is missing a tested payload file: $RelativePath"
    }
    $File = Get-Item -LiteralPath $InstalledFile -Force -ErrorAction Stop
    if ([int64]$File.Length -ne [int64]$FileRecord.Length) {
        throw "Repository-installed file length mismatch: $RelativePath"
    }
    $Hash = (Get-FileHash -LiteralPath $InstalledFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Hash -ne [string]$FileRecord.SHA256) {
        throw "Repository-installed file digest mismatch: $RelativePath"
    }
}

$OriginalLocation = (Get-Location).Path
$OriginalModulePath = $env:PSModulePath
$ExistingModules = @(Get-Module -Name TheCleaners)
$Checks = [ordered]@{
    ExactPathImport = $false
    ModuleNameImport = $false
    Exports = $false
    Help = $false
    PreviewLocks = $false
}
try {
    if ($ExistingModules.Count -gt 0) {
        Remove-Module -Name TheCleaners -Force -ErrorAction Stop
    }

    $ImportOutput = @(Import-Module -Name $InstalledManifestPath -Force *>&1)
    if ($ImportOutput.Count -ne 0) {
        throw 'Exact-path import wrote output.'
    }
    if ((Get-Location).Path -ne $OriginalLocation) {
        throw 'Exact-path import changed the current location.'
    }
    $Module = Get-Module -Name TheCleaners
    if ($null -eq $Module -or [System.IO.Path]::GetFullPath($Module.ModuleBase) -ne [System.IO.Path]::GetFullPath($ResolvedModulePath)) {
        throw 'Exact-path import loaded a different module copy.'
    }
    $Checks.ExactPathImport = $true

    $ExpectedFunctions = @($InstalledManifest.ExportedFunctions.Keys | Sort-Object)
    $ActualFunctions = @($Module.ExportedFunctions.Keys | Sort-Object)
    $ExpectedAliases = @($InstalledManifest.ExportedAliases.Keys | Sort-Object)
    $ActualAliases = @($Module.ExportedAliases.Keys | Sort-Object)
    if (@(Compare-Object -ReferenceObject $ExpectedFunctions -DifferenceObject $ActualFunctions).Count -gt 0) {
        throw 'The installed module function exports differ from its manifest.'
    }
    if (@(Compare-Object -ReferenceObject $ExpectedAliases -DifferenceObject $ActualAliases).Count -gt 0) {
        throw 'The installed module alias exports differ from its manifest.'
    }
    if ($Module.ExportedAliases['Start-Cleaning'].Definition -ne 'Get-TheCleaners') {
        throw 'The installed module does not preserve the Start-Cleaning compatibility alias.'
    }
    if (Get-Command -Name Invoke-TheCleaners -ErrorAction SilentlyContinue) {
        throw 'The installed module leaked the retired Invoke-TheCleaners command.'
    }
    $Inventory = @(TheCleaners\Get-TheCleaners -NoLogo)
    if ($Inventory.Count -ne 6) {
        throw 'The installed module returned an unexpected command inventory.'
    }
    $InventoryNames = @($Inventory | ForEach-Object { [string]$_.Name } | Sort-Object)
    if (@(Compare-Object -ReferenceObject $ExpectedFunctions -DifferenceObject $InventoryNames).Count -gt 0) {
        throw 'The installed module inventory differs from its function exports.'
    }
    $Checks.Exports = $true

    foreach ($FunctionName in $ExpectedFunctions) {
        $Help = Get-Help -Name ('TheCleaners\' + $FunctionName) -Full
        if (-not $Help.Synopsis -or -not $Help.Description -or -not $Help.Examples) {
            throw "The installed module has incomplete help for $FunctionName."
        }
    }
    $Checks.Help = $true

    foreach ($PreviewCommand in @(
            @{ Name = 'Clear-OldIISLog'; ErrorId = 'IISCleanupPreviewOnly' }
            @{ Name = 'Clear-OldExchangeLog'; ErrorId = 'ExchangeCleanupPreviewOnly' }
        )) {
        $WasBlocked = $false
        try {
            & ('TheCleaners\' + $PreviewCommand.Name) -Confirm:$false -ErrorAction Stop
        } catch {
            if ($_.FullyQualifiedErrorId -notlike ($PreviewCommand.ErrorId + '*')) {
                throw
            }
            $WasBlocked = $true
        }
        if (-not $WasBlocked) {
            throw "$($PreviewCommand.Name) did not retain its no-WhatIf preview lock."
        }
        $InventoryItem = $Inventory | Where-Object Name -EQ $PreviewCommand.Name
        if ($InventoryItem.Maturity -ne 'PreviewOnly' -or $InventoryItem.RemovalEnabled) {
            throw "$($PreviewCommand.Name) reported invalid preview metadata."
        }
    }
    $Checks.PreviewLocks = $true

    Remove-Module -Name TheCleaners -Force -ErrorAction Stop
    $env:PSModulePath = $ResolvedModuleSearchRoot + [System.IO.Path]::PathSeparator + (Join-Path -Path $PSHOME -ChildPath 'Modules')
    $NameImportOutput = @(Import-Module -Name TheCleaners -RequiredVersion ([version]$ExpectedVersion) -Force *>&1)
    if ($NameImportOutput.Count -ne 0) {
        throw 'Module-name import wrote output.'
    }
    if ((Get-Location).Path -ne $OriginalLocation) {
        throw 'Module-name import changed the current location.'
    }
    $NameImportedModule = Get-Module -Name TheCleaners
    if ($null -eq $NameImportedModule -or [System.IO.Path]::GetFullPath($NameImportedModule.ModuleBase) -ne [System.IO.Path]::GetFullPath($ResolvedModulePath)) {
        throw 'Module-name import loaded a different module copy.'
    }
    $Checks.ModuleNameImport = $true
} finally {
    Remove-Module -Name TheCleaners -Force -ErrorAction SilentlyContinue
    $env:PSModulePath = $OriginalModulePath
    Set-Location -LiteralPath $OriginalLocation
    foreach ($ExistingModule in $ExistingModules) {
        Import-Module -Name $ExistingModule.Path -Force -ErrorAction SilentlyContinue
    }
}

$Evidence = [ordered]@{
    SchemaVersion = 1
    Status = 'Passed'
    Commit = $ExpectedCommit.ToLowerInvariant()
    Tag = $ExpectedTag
    ModuleName = 'TheCleaners'
    ModuleVersion = $ExpectedVersion
    Prerelease = $ExpectedPrerelease
    Repository = $RepositoryName
    Runtime = [ordered]@{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        PSEdition = $PSVersionTable.PSEdition
        OS = [Environment]::OSVersion.VersionString
    }
    Payload = [ordered]@{
        ManifestFileCount = $ExpectedPayloadFiles.Count
        InstalledFileCount = $ActualRelativeFiles.Count
        RepositoryMetadata = $MetadataRelativePath
        HashAlgorithm = 'SHA256'
    }
    Checks = $Checks
    Boundary = 'Payload hash and runtime behavior verification only; package-signature trust and product acceptance are not established.'
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-RepositoryEvidence -InputObject $Evidence -Path $OutputPath
}
[pscustomobject]$Evidence
