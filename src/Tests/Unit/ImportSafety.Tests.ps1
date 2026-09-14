BeforeAll {
    $ManifestPath = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners/TheCleaners.psd1')).Path
    $PowerShellExecutable = (Get-Process -Id $PID).Path
    $ProbePath = Join-Path -Path $TestDrive -ChildPath 'Test-SourceImport.ps1'
    @'
param([string]$ManifestPath)
$ErrorActionPreference = 'Stop'
$BeforeLocation = (Get-Location).Path
$Output = @(Import-Module -Name $ManifestPath -Force *>&1)
if ($Output.Count -ne 0) { throw 'Source import wrote output.' }
if ((Get-Location).Path -ne $BeforeLocation) { throw 'Source import changed location.' }
if (Get-Command Invoke-TheCleaners -ErrorAction SilentlyContinue) { throw 'Import leaked the legacy initializer.' }
$Module = Get-Module -Name TheCleaners
if ($Module.ExportedVariables.Count -ne 0) { throw 'Import exported variables.' }
$Inventory = @(TheCleaners\Get-TheCleaners -NoLogo)
if ($Inventory.Count -ne 6) { throw 'Invalid command inventory.' }
$AliasInventory = @(TheCleaners\Start-Cleaning -NoLogo)
if ($AliasInventory.Count -ne $Inventory.Count) { throw 'Legacy alias differs from Get-TheCleaners.' }
Remove-Module -Name TheCleaners -Force
$ReloadOutput = @(Import-Module -Name $ManifestPath -Force *>&1)
if ($ReloadOutput.Count -ne 0) { throw 'Source reimport wrote output.' }
'@ | Set-Content -LiteralPath $ProbePath -Encoding UTF8
}

Describe 'Source module import safety' -Tag Unit {
    It 'imports quietly and preserves the compatibility alias in a fresh process' {
        $ProbeOutput = & $PowerShellExecutable -NoLogo -NoProfile -NonInteractive -File $ProbePath -ManifestPath $ManifestPath 2>&1
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne 0) {
            throw ($ProbeOutput | Out-String)
        }
        $ExitCode | Should -Be 0
    }
}

