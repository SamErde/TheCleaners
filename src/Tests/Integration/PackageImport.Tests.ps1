BeforeAll {
    $PackageRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../Artifacts')).Path
    $PackageManifest = Join-Path -Path $PackageRoot -ChildPath 'TheCleaners.psd1'
    $PackageData = Import-PowerShellDataFile -Path $PackageManifest
    $ArchiveRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../Archive')).Path
    $ArchiveManifestPath = Join-Path -Path $ArchiveRoot -ChildPath ('TheCleaners_{0}.manifest.json' -f $PackageData.ModuleVersion)
    $ArchiveManifest = Get-Content -LiteralPath $ArchiveManifestPath -Raw | ConvertFrom-Json
    $ArchivePath = Join-Path -Path $ArchiveRoot -ChildPath $ArchiveManifest.Archive
    $ProbeHosts = [System.Collections.Generic.List[string]]::new()
    $CurrentHostPath = (Get-Process -Id $PID).Path
    $ProbeHosts.Add($CurrentHostPath)
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        $WindowsPowerShell = Join-Path -Path $env:SystemRoot -ChildPath 'System32/WindowsPowerShell/v1.0/powershell.exe'
        if ((Test-Path -LiteralPath $WindowsPowerShell -PathType Leaf) -and $WindowsPowerShell -ne $CurrentHostPath) {
            $ProbeHosts.Add($WindowsPowerShell)
        }
    }
    $ProbePath = Join-Path -Path $TestDrive -ChildPath 'Test-PackageImport.ps1'
    @'
param([string]$ManifestPath)
$ErrorActionPreference = 'Stop'
$BeforeLocation = (Get-Location).Path
$ImportOutput = @(Import-Module -Name $ManifestPath -Force *>&1)
if ($ImportOutput.Count -ne 0) { throw 'Module import wrote output.' }
if ((Get-Location).Path -ne $BeforeLocation) { throw 'Module import changed location.' }
$Module = Get-Module -Name TheCleaners
if ($null -eq $Module) { throw 'Packaged module not imported.' }
if ([System.IO.Path]::GetFullPath($Module.ModuleBase) -ne [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ManifestPath))) { throw 'Imported a different module copy.' }
if (Get-Command Invoke-TheCleaners -ErrorAction SilentlyContinue) { throw 'Import leaked Invoke-TheCleaners.' }
$Inventory = @(TheCleaners\Get-TheCleaners -NoLogo)
if ($Inventory.Count -ne 6) { throw 'Unexpected command inventory.' }
if ($Module.ExportedAliases['Start-Cleaning'].Definition -ne 'Get-TheCleaners') { throw 'Missing compatibility alias.' }
foreach ($PreviewCommand in @(
    @{ Name = 'Clear-OldIISLog'; ErrorId = 'IISCleanupPreviewOnly' }
    @{ Name = 'Clear-OldExchangeLog'; ErrorId = 'ExchangeCleanupPreviewOnly' }
)) {
    $Blocked = $false
    try { & ('TheCleaners\' + $PreviewCommand.Name) -Confirm:$false } catch {
        if ($_.FullyQualifiedErrorId -notlike ($PreviewCommand.ErrorId + '*')) { throw }
        $Blocked = $true
    }
    if (-not $Blocked) { throw "$($PreviewCommand.Name) was not blocked." }
    $InventoryItem = $Inventory | Where-Object Name -EQ $PreviewCommand.Name
    if ($InventoryItem.Maturity -ne 'PreviewOnly' -or $InventoryItem.RemovalEnabled) { throw "Incorrect preview metadata: $($PreviewCommand.Name)" }
}
foreach ($Name in $Module.ExportedFunctions.Keys) {
    $Help = Get-Help -Name ('TheCleaners\' + $Name) -Full
    if (-not $Help.Synopsis -or -not $Help.Description -or -not $Help.Examples) { throw "Incomplete packaged help: $Name" }
}
Remove-Module -Name TheCleaners -Force
$ReloadOutput = @(Import-Module -Name $ManifestPath -Force *>&1)
if ($ReloadOutput.Count -ne 0) { throw 'Module reimport wrote output.' }
'@ | Set-Content -LiteralPath $ProbePath -Encoding UTF8
}

Describe 'Built-package contract' -Tag Integration {
    It 'retains Windows PowerShell 5.1 as the manifest minimum' {
        $PackageData.PowerShellVersion | Should -Be '5.1'
    }

    It 'has no ScriptsToProcess or legacy initializer in the package' {
        $PackageData.ScriptsToProcess | Should -BeNullOrEmpty
        (Join-Path -Path $PackageRoot -ChildPath 'Invoke-TheCleaners.ps1') | Should -Not -Exist
    }

    It 'passes quiet import, packaged-help, aliases, and preview-lock checks in every available supported host' {
        foreach ($ProbeHost in $ProbeHosts) {
            $ProbeOutput = & $ProbeHost -NoLogo -NoProfile -NonInteractive -File $ProbePath -ManifestPath $PackageManifest 2>&1
            $ExitCode = $LASTEXITCODE
            if ($ExitCode -ne 0) {
                throw "Package probe failed under '$ProbeHost':`n$($ProbeOutput | Out-String)"
            }
            $ExitCode | Should -Be 0
        }
    }
}

Describe 'Exact archive clean-install contract' -Tag Integration {
    It 'matches the archive hash, extracts the tested artifact, and imports it by module name in every host' {
        $ExpectedCommit = (& git -C $PSScriptRoot rev-parse HEAD).Trim()
        $ArchiveManifest.Commit | Should -Be $ExpectedCommit
        if ($env:TC_BUILD_COMMIT) { $ArchiveManifest.Commit | Should -Be $env:TC_BUILD_COMMIT }
        if ($PSEdition -eq 'Core') {
            $ArchiveManifest.Runtime.PowerShellVersion | Should -Be $PSVersionTable.PSVersion.ToString()
        } else {
            $ArchiveManifest.Runtime.PowerShellVersion | Should -Be '7.6.6'
        }
        $ArchivePath | Should -Exist
        $ArchiveHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $ArchiveHash | Should -Be ([string]$ArchiveManifest.ArchiveSHA256)
        $SidecarPath = "$ArchivePath.sha256"
        $SidecarPath | Should -Exist
        (Get-Content -LiteralPath $SidecarPath -Raw).Trim() | Should -Be (('{0} *{1}' -f $ArchiveHash, $ArchiveManifest.Archive))

        foreach ($FileRecord in @($ArchiveManifest.Files)) {
            $ArtifactFile = Join-Path -Path $PackageRoot -ChildPath ($FileRecord.Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $ArtifactFile | Should -Exist
            (Get-FileHash -LiteralPath $ArtifactFile -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be ([string]$FileRecord.SHA256)
        }

        $ExtractionRoot = Join-Path -Path $TestDrive -ChildPath 'ArchiveExtraction'
        $ModuleSearchRoot = Join-Path -Path $TestDrive -ChildPath 'InstalledModules'
        $InstalledModuleRoot = Join-Path -Path $ModuleSearchRoot -ChildPath ('TheCleaners/{0}' -f $PackageData.ModuleVersion)
        $null = New-Item -Path $ExtractionRoot -ItemType Directory -Force
        $null = New-Item -Path $InstalledModuleRoot -ItemType Directory -Force
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ExtractionRoot -Force
        foreach ($Item in @(Get-ChildItem -LiteralPath $ExtractionRoot -Force)) {
            Copy-Item -LiteralPath $Item.FullName -Destination $InstalledModuleRoot -Recurse -Force -ErrorAction Stop
        }
        foreach ($Root in @($PackageRoot, $ExtractionRoot, $InstalledModuleRoot)) {
            $Files = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force)
            $Files.Count | Should -Be @($ArchiveManifest.Files).Count
            foreach ($Record in $ArchiveManifest.Files) {
                $File = Join-Path -Path $Root -ChildPath $Record.Path
                (Get-Item -LiteralPath $File -Force).Length | Should -Be $Record.Length
                (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $Record.SHA256
            }
        }
        # Repeat the full help/quiet-import/preview probe against the extracted ZIP.
        foreach ($ProbeHost in $ProbeHosts) {
            $Output = & $ProbeHost -NoLogo -NoProfile -NonInteractive -File $ProbePath -ManifestPath (Join-Path -Path $InstalledModuleRoot -ChildPath 'TheCleaners.psd1') 2>&1
            $LASTEXITCODE | Should -Be 0 -Because ($Output | Out-String)
        }

        $ProbePath = Join-Path -Path $TestDrive -ChildPath 'Test-CleanInstall.ps1'
        @'
param (
    [Parameter(Mandatory)]
    [string]
    $ModuleSearchRoot,

    [Parameter(Mandatory)]
    [string]
    $ExpectedModuleRoot,

    [Parameter(Mandatory)]
    [string]
    $Version
)

$ErrorActionPreference = 'Stop'
$env:PSModulePath = $ModuleSearchRoot + [System.IO.Path]::PathSeparator + (Join-Path -Path $PSHOME -ChildPath 'Modules')
Import-Module -Name TheCleaners -RequiredVersion $Version -Force
$Module = Get-Module -Name TheCleaners
if ([System.IO.Path]::GetFullPath($Module.ModuleBase) -ne [System.IO.Path]::GetFullPath($ExpectedModuleRoot)) {
    throw 'The clean-install probe imported a different module path.'
}
if (@(TheCleaners\Get-TheCleaners -NoLogo).Count -ne 6) {
    throw 'The clean-install probe returned an invalid command inventory.'
}
if ($Module.ExportedAliases['Start-Cleaning'].Definition -ne 'Get-TheCleaners') {
    throw 'The clean-install probe did not preserve the compatibility alias.'
}
'CLEAN_INSTALL_OK'
'@ | Set-Content -LiteralPath $ProbePath -Encoding UTF8

        foreach ($ProbeHost in $ProbeHosts) {
            $ProbeOutput = & $ProbeHost -NoLogo -NoProfile -NonInteractive -File $ProbePath -ModuleSearchRoot $ModuleSearchRoot -ExpectedModuleRoot $InstalledModuleRoot -Version $PackageData.ModuleVersion 2>&1
            $ExitCode = $LASTEXITCODE
            $ExitCode | Should -Be 0 -Because "Clean-install probe failed under '$ProbeHost':`n$($ProbeOutput | Out-String)"
            $ProbeOutput | Should -Contain 'CLEAN_INSTALL_OK'
        }
    }
}
