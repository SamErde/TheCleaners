BeforeAll {
    $PackageRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../Artifacts')).Path
    $PackageManifest = Join-Path -Path $PackageRoot -ChildPath 'TheCleaners.psd1'
    $PackageData = Import-PowerShellDataFile -Path $PackageManifest
    $PowerShellExecutable = (Get-Process -Id $PID).Path
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

    It 'passes quiet import, packaged-help, aliases, and preview-lock checks in a fresh process' {
        $ProbeOutput = & $PowerShellExecutable -NoLogo -NoProfile -NonInteractive -File $ProbePath -ManifestPath $PackageManifest 2>&1
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne 0) {
            throw ($ProbeOutput | Out-String)
        }
        $ExitCode | Should -Be 0
    }
}
