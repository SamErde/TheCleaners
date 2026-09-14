BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $ModuleStateCases = @(
        @{ Scenario = 'NewSuccess' }
        @{ Scenario = 'NewFailure' }
        @{ Scenario = 'ExistingSuccess' }
        @{ Scenario = 'ExistingFailure' }
    )
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    $ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'TheCleaners.psd1'
    $PowerShellExecutable = (Get-Process -Id $PID).Path
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Resolve-TheCleanersFileSystemPath.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public/Clear-OldIISLog.ps1')

    # A fixture module exercises actual import/removal without installing or querying IIS.
    $FixtureModuleContent = @'
function Get-Website {
    [CmdletBinding()]
    param ()

    $Fixture = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Sites.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($Fixture.FailDiscovery) {
        throw 'Fixture website discovery failed.'
    }
    $Fixture.Sites
}

Export-ModuleMember -Function Get-Website
'@
    $ProbeContent = @'
param (
    [string]$ManifestPath,
    [string]$ModuleSearchRoot,
    [string]$LogRoot,
    [string]$Scenario
)

# Emit plain diagnostics on stdout so a failing child process is still reportable
# under Windows PowerShell native stderr handling and in Pester NUnit XML.
trap {
    [Console]::Out.WriteLine(('IIS_DISCOVERY_ERROR: {0}' -f $_.Exception.Message))
    exit 1
}
$ErrorActionPreference = 'Stop'
$env:PSModulePath = $ModuleSearchRoot + [System.IO.Path]::PathSeparator + (Join-Path -Path $PSHOME -ChildPath 'Modules')
Import-Module -Name $ManifestPath -ErrorAction Stop
$InitiallyLoaded = $Scenario.StartsWith('Existing')
if ($InitiallyLoaded) {
    Import-Module -Name 'WebAdministration' -Global -ErrorAction Stop
}
$Before = @(Get-Module -Name 'WebAdministration' -All)
$PreviousWhatIfPreference = $WhatIfPreference
$PreviousConfirmPreference = $ConfirmPreference
$ObservedError = $null
$Results = @()
try {
    $Results = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop)
} catch {
    $ObservedError = $_.Exception.Message
}
$After = @(Get-Module -Name 'WebAdministration' -All)
# Inspect the fixture's exported function directly. Exact-name Get-Command lookup
# can discover/auto-import an available module, invalidating a module-lifetime probe.
$WebsiteFunctionPresent = Test-Path -LiteralPath 'Function:\Get-Website'
if ($InitiallyLoaded) {
    if ($Before.Count -ne 1 -or $After.Count -ne 1 -or -not [object]::ReferenceEquals($Before[0], $After[0])) {
        throw 'The preview did not preserve the existing dependency module instance.'
    }
    if (-not $WebsiteFunctionPresent) {
        throw 'The preview removed a command from the existing dependency.'
    }
} else {
    if ($Before.Count -ne 0 -or $After.Count -ne 0) {
        throw 'The preview left a newly imported dependency loaded.'
    }
    if ($WebsiteFunctionPresent) {
        throw 'The preview leaked an imported command into the caller session.'
    }
}
if (@(Get-Module -Name 'WebAdministration' -All).Count -ne $Before.Count) {
    throw 'Verification unexpectedly changed the dependency module state.'
}
if ($WhatIfPreference -ne $PreviousWhatIfPreference -or $ConfirmPreference -ne $PreviousConfirmPreference) {
    throw 'The preview changed caller confirmation preferences.'
}
if ($Scenario.EndsWith('Failure')) {
    if ($ObservedError -notlike '*Fixture website discovery failed*' -or $Results.Count -ne 0) {
        throw 'Discovery failure was swallowed or returned a successful preview.'
    }
} else {
    if ($null -ne $ObservedError) {
        throw $ObservedError
    }
    $ExpectedRoot = [System.IO.Path]::GetFullPath($LogRoot).TrimEnd([char[]]@('\', '/'))
    if ($Results.Count -ne 1 -or $Results[0].RootPath -ne $ExpectedRoot) {
        throw 'Equivalent site roots were not normalized into one preview.'
    }
    if ($Results[0].FileCandidateCount -ne 1 -or $Results[0].CandidatePaths.Count -ne 1 -or $Results[0].FilesRemoved -ne 0) {
        throw 'The preview duplicated candidates or claimed file removal.'
    }
}
if (-not [System.IO.File]::Exists((Join-Path -Path $LogRoot -ChildPath 'old.log'))) {
    throw 'The preview removed a fixture log.'
}
'IIS_DISCOVERY_OK'
'@
}

Describe 'IIS dependency state and site-root deduplication: <Scenario>' -ForEach $ModuleStateCases -Skip:(-not $WindowsHost) -Tag Unit {
    It 'restores dependency state in a fresh process without touching existing modules' {
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $ModuleSearchRoot = Join-Path -Path $FixtureRoot -ChildPath 'Modules'
        $DependencyRoot = Join-Path -Path $ModuleSearchRoot -ChildPath 'WebAdministration'
        $LogBase = Join-Path -Path $FixtureRoot -ChildPath 'LogFiles'
        $LogRoot = Join-Path -Path $LogBase -ChildPath 'W3SVC1'
        $null = New-Item -Path $DependencyRoot -ItemType Directory -Force
        $null = New-Item -Path $LogRoot -ItemType Directory -Force
        $OldLog = New-Item -Path (Join-Path -Path $LogRoot -ChildPath 'old.log') -ItemType File
        $OldLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $Sites = @(
            @{ Name = 'Normal spelling'; Id = 1; LogFile = @{ Directory = $LogBase } }
            @{ Name = 'Dot segment spelling'; Id = 1; LogFile = @{ Directory = $LogBase + '\..\LogFiles\' } }
            @{ Name = 'Alternate separators'; Id = 1; LogFile = @{ Directory = $LogBase.Replace('\', '/') + '/' } }
        )
        $Fixture = @{ FailDiscovery = $Scenario.EndsWith('Failure'); Sites = $Sites }
        $Fixture | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path -Path $DependencyRoot -ChildPath 'Sites.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path -Path $DependencyRoot -ChildPath 'WebAdministration.psm1') -Value $FixtureModuleContent -Encoding UTF8
        $ProbePath = Join-Path -Path $FixtureRoot -ChildPath 'Probe.ps1'
        Set-Content -LiteralPath $ProbePath -Value $ProbeContent -Encoding UTF8

        $ProbeOutput = & $PowerShellExecutable -NoLogo -NoProfile -NonInteractive -File $ProbePath -ManifestPath $ManifestPath -ModuleSearchRoot $ModuleSearchRoot -LogRoot $LogRoot -Scenario $Scenario 2>&1
        $ProbeExitCode = $LASTEXITCODE
        $Diagnostic = [regex]::Replace(($ProbeOutput -join [Environment]::NewLine), '\x1B\[[0-?]*[ -/]*[@-~]', '')

        $ProbeExitCode | Should -Be 0 -Because $Diagnostic
        $ProbeOutput | Should -Contain 'IIS_DISCOVERY_OK'
    }
}

Describe 'IIS registry-root deduplication' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousSystemDrive = $env:SystemDrive
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $IISRoot = Join-Path -Path $FixtureRoot -ChildPath 'inetpub/logs/LogFiles'
        $null = New-Item -Path $IISRoot -ItemType Directory -Force
        $OldLog = New-Item -Path (Join-Path -Path $IISRoot -ChildPath 'old.log') -ItemType File
        $OldLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $env:SystemDrive = $FixtureRoot
        Mock Get-Module { $null } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
    }

    AfterEach {
        $env:SystemDrive = $PreviousSystemDrive
    }

    It 'combines default and registry roots with equivalent spelling <Suffix>' -ForEach @(
        @{ Suffix = '\..\LogFiles\' }
        @{ Suffix = '/../LogFiles/' }
        @{ Suffix = '\' }
    ) {
        $RegistrySpelling = $IISRoot + $Suffix
        Mock Get-ItemProperty { [pscustomobject]@{ LogDir = $RegistrySpelling } }

        $Results = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop)

        $Results | Should -HaveCount 1
        $Results[0].RootPath | Should -Be ([System.IO.Path]::GetFullPath($IISRoot))
        $Results[0].FileCandidateCount | Should -Be 1
        $Results[0].CandidatePaths | Should -HaveCount 1
        $Results[0].CandidatePaths | Should -Contain $OldLog.FullName
        $OldLog.FullName | Should -Exist
    }

    It 'does not collapse distinct custom and default roots' {
        $CustomRoot = Join-Path -Path $FixtureRoot -ChildPath 'CustomLogs'
        $null = New-Item -Path $CustomRoot -ItemType Directory
        Mock Get-ItemProperty { [pscustomobject]@{ LogDir = $CustomRoot } }

        $Results = @(Clear-OldIISLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop)

        $Results | Should -HaveCount 2
        $Results.RootPath | Should -Contain ([System.IO.Path]::GetFullPath($IISRoot))
        $Results.RootPath | Should -Contain ([System.IO.Path]::GetFullPath($CustomRoot))
        $OldLog.FullName | Should -Exist
    }
}

