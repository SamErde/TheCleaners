<#
.SYNOPSIS
    Install an exact PowerShell Core release for the Windows CI job.
.DESCRIPTION
    Download the official x64 ZIP and its release hash list, verify the ZIP
    before extraction, and add the isolated installation directory to the
    remaining steps in the current GitHub Actions job.
.PARAMETER Version
    Exact PowerShell Core version to install, such as 7.6.6.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]
    $Version
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'The exact PowerShell CI installer requires a 64-bit Windows runner.'
}
if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'RUNNER_TEMP is required for the isolated PowerShell installation.'
}
if ([string]::IsNullOrWhiteSpace($env:GITHUB_PATH)) {
    throw 'GITHUB_PATH is required to expose the exact PowerShell installation.'
}

$RunId = if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) { [guid]::NewGuid().Guid } else { $env:GITHUB_RUN_ID }
$RunAttempt = if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ATTEMPT)) { '1' } else { $env:GITHUB_RUN_ATTEMPT }
$DownloadRoot = Join-Path -Path $env:RUNNER_TEMP -ChildPath ('TheCleaners-PowerShell-{0}-{1}-{2}' -f $Version, $RunId, $RunAttempt)
$InstallRoot = Join-Path -Path $DownloadRoot -ChildPath 'pwsh'
$ZipFileName = 'PowerShell-{0}-win-x64.zip' -f $Version
$ZipPath = Join-Path -Path $DownloadRoot -ChildPath $ZipFileName
$HashPath = Join-Path -Path $DownloadRoot -ChildPath 'hashes.sha256'
$ReleaseBaseUri = 'https://github.com/PowerShell/PowerShell/releases/download/v{0}' -f $Version
$Headers = @{ 'User-Agent' = 'TheCleaners-CI' }

$null = New-Item -Path $DownloadRoot -ItemType Directory -Force
Invoke-WebRequest -UseBasicParsing -Uri ($ReleaseBaseUri + '/hashes.sha256') -Headers $Headers -OutFile $HashPath -ErrorAction Stop
Invoke-WebRequest -UseBasicParsing -Uri ($ReleaseBaseUri + '/' + $ZipFileName) -Headers $Headers -OutFile $ZipPath -ErrorAction Stop

$HashBytes = [System.IO.File]::ReadAllBytes($HashPath)
$HashText = if ($HashBytes.Length -ge 2 -and $HashBytes[0] -eq 0xff -and $HashBytes[1] -eq 0xfe) {
    [System.Text.Encoding]::Unicode.GetString($HashBytes)
} else {
    [System.Text.Encoding]::UTF8.GetString($HashBytes)
}
$HashPattern = '^(?<Hash>[0-9A-Fa-f]{64})\s+\*?' + [regex]::Escape($ZipFileName) + '\s*$'
$ExpectedHash = $null
foreach ($Line in ($HashText -split '\r?\n')) {
    if ($Line -match $HashPattern) {
        $ExpectedHash = $Matches['Hash'].ToLowerInvariant()
        break
    }
}
if ([string]::IsNullOrWhiteSpace($ExpectedHash)) {
    throw "The official PowerShell release hash list did not contain '$ZipFileName'."
}

$ActualHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
if ($ActualHash -ne $ExpectedHash) {
    throw "The downloaded PowerShell $Version archive hash '$ActualHash' did not match the official release hash '$ExpectedHash'."
}

$null = New-Item -Path $InstallRoot -ItemType Directory -Force
Expand-Archive -LiteralPath $ZipPath -DestinationPath $InstallRoot -Force
$PowerShellPath = Join-Path -Path $InstallRoot -ChildPath 'pwsh.exe'
if (-not (Test-Path -LiteralPath $PowerShellPath -PathType Leaf)) {
    throw "The PowerShell $Version archive did not contain pwsh.exe."
}
$InstalledVersion = (& $PowerShellPath -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()').Trim()
if ($InstalledVersion -ne $Version) {
    throw "The installed PowerShell version '$InstalledVersion' did not match '$Version'."
}

Add-Content -LiteralPath $env:GITHUB_PATH -Value $InstallRoot -Encoding utf8
Write-Output "Installed and verified PowerShell $Version from $ZipFileName ($ActualHash)."
