BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $ModuleStateCases = @(
        @{ Scenario = 'NewSuccess' }
        @{ Scenario = 'NewFailure' }
        @{ Scenario = 'ExistingSuccess' }
        @{ Scenario = 'ExistingFailure' }
        @{ Scenario = 'FtpSuccess' }
        @{ Scenario = 'WebFormatUnknown' }
    )
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    $ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'TheCleaners.psd1'
    $PowerShellExecutable = (Get-Process -Id $PID).Path
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/ResultContracts.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Resolve-TheCleanersFileSystemPath.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Test-TheCleanersIisLogFileName.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Test-TheCleanersIisProtectedPath.ps1')
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

function Get-WebConfiguration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Filter,

        [Parameter(Mandatory)]
        [string]
        $PSPath
    )

    $Fixture = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Sites.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    $SiteName = [regex]::Match($Filter, "site\[@name='(?<Name>[^']+)'\]").Groups['Name'].Value
    $Site = @($Fixture.Sites | Where-Object { [string]$_.Name -eq $SiteName }) | Select-Object -First 1
    if ($null -eq $Site -or $null -eq $Site.FtpServer) {
        return
    }
    if ($Site.FtpServer.ConfigurationFailure) {
        throw 'Fixture FTP configuration query failed.'
    }
    [pscustomobject]@{
        Directory         = $Site.FtpServer.LogFile.Directory
        LogFormat         = $Site.FtpServer.LogFile.LogFormat
        LocalTimeRollover = $Site.FtpServer.LogFile.LocalTimeRollover
    }
}

Export-ModuleMember -Function Get-Website, Get-WebConfiguration
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
if ($Scenario -in @('FtpRootFailureWithExistingWeb', 'FtpRootFailureWithNoWebRoot', 'FtpRootFailureWithValidWeb')) {
    $env:SystemDrive = ''
}
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
$DiscoveryErrorAction = if ($Scenario -in @('FtpRootFailureWithExistingWeb', 'FtpRootFailureWithNoWebRoot', 'FtpRootFailureWithValidWeb')) { 'SilentlyContinue' } else { 'Stop' }
try {
    $Results = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction $DiscoveryErrorAction)
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
} elseif ($Scenario -eq 'WebFormatUnknown') {
    $ExpectedRoot = [System.IO.Path]::GetFullPath($LogRoot).TrimEnd([char[]]@('\', '/'))
    $UnknownFormatResult = @($Results | Where-Object { $_.RootPath -eq $ExpectedRoot })
    if ($UnknownFormatResult.Count -ne 1 -or $UnknownFormatResult[0].Status -ne 'DiscoveryFailed' -or $UnknownFormatResult[0].ErrorIds -notcontains 'IISLogFormatUnavailable' -or $null -ne $UnknownFormatResult[0].FileCandidateCount) {
        throw 'A WebAdministration root without a logging format was not rejected as an unknown-format discovery failure.'
    }
} else {
    if ($null -ne $ObservedError) {
        throw $ObservedError
    }
    $ExpectedRoot = [System.IO.Path]::GetFullPath($LogRoot).TrimEnd([char[]]@('\', '/'))
    $WebResult = @($Results | Where-Object { $_.RootPath -eq $ExpectedRoot })
    if ($WebResult.Count -ne 1) {
        throw 'Equivalent site roots were not normalized into one preview.'
    }
    if ($WebResult[0].FileCandidateCount -ne 1 -or $WebResult[0].CandidatePaths.Count -ne 1 -or $WebResult[0].FilesRemoved -ne 0) {
        throw 'The preview duplicated candidates or claimed file removal.'
    }
    if ($Scenario -eq 'FtpSuccess') {
        $ExpectedFtpRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Path $ExpectedRoot -Parent) -ChildPath 'FTPSVC2')).TrimEnd([char[]]@('\', '/'))
        $FtpResult = @($Results | Where-Object { $_.RootPath -eq $ExpectedFtpRoot })
        if ($Results.Count -ne 2 -or $FtpResult.Count -ne 1 -or $FtpResult[0].FileCandidateCount -ne 1 -or $FtpResult[0].CandidatePaths.Count -ne 1 -or $FtpResult[0].FilesRemoved -ne 0) {
            throw 'FTP site logging was not discovered as a separate preview root.'
        }
        if (-not [System.IO.File]::Exists((Join-Path -Path $ExpectedFtpRoot -ChildPath 'inetsv01.log'))) {
            throw 'The preview removed a fixture FTP log.'
        }
    }
    if ($Scenario -eq 'FtpRootFailureWithValidWeb') {
        $ValidWebResult = @($Results | Where-Object { $_.RootPath -eq $ExpectedRoot })
        $FailedFtpSiteResult = @($Results | Where-Object { $_.DisplayName -eq 'FTP valid web FTP' })
        if ($ValidWebResult.Count -ne 1 -or $ValidWebResult[0].Status -ne 'WhatIf' -or $ValidWebResult[0].FileCandidateCount -ne 1 -or $FailedFtpSiteResult.Count -ne 1 -or $FailedFtpSiteResult[0].Status -ne 'DiscoveryFailed' -or $FailedFtpSiteResult[0].ErrorIds -notcontains 'IISFtpDiscoveryFailed') {
            throw 'An FTP discovery failure contaminated the valid web-root preview or lacked its own result.'
        }
    } elseif ($Scenario -eq 'FtpRootFailureWithExistingWeb') {
        $FailedFtpSiteResult = @($Results | Where-Object { $_.DisplayName -eq 'FTP failure FTP' })
        if ($FailedFtpSiteResult.Count -ne 1 -or $FailedFtpSiteResult[0].Status -ne 'DiscoveryFailed' -or $null -ne $FailedFtpSiteResult[0].FileCandidateCount -or $FailedFtpSiteResult[0].ErrorIds -notcontains 'IISFtpDiscoveryFailed' -or $FailedFtpSiteResult[0].RootPath -notlike 'IIS FTP log root unavailable*') {
            throw 'The preview omitted the failed FTP discovery for an absent web root.'
        }
    } elseif ($Scenario -eq 'FtpRootFailureWithNoWebRoot') {
        $FailedFtpSiteResult = @($Results | Where-Object { $_.DisplayName -eq 'FTP without web root FTP' })
        if ($FailedFtpSiteResult.Count -ne 1 -or $FailedFtpSiteResult[0].Status -ne 'DiscoveryFailed' -or $null -ne $FailedFtpSiteResult[0].FileCandidateCount -or $FailedFtpSiteResult[0].ErrorIds -notcontains 'IISFtpDiscoveryFailed' -or $FailedFtpSiteResult[0].RootPath -notlike 'IIS FTP log root unavailable*') {
            throw 'The preview omitted the per-FTP failure placeholder when the web root was absent.'
        }
    }
}
if (-not [System.IO.File]::Exists((Join-Path -Path $LogRoot -ChildPath 'u_ex240101.log'))) {
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
        $OldLog = New-Item -Path (Join-Path -Path $LogRoot -ChildPath 'u_ex240101.log') -ItemType File
        $OldLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $Sites = @(
            @{ Name = 'Normal spelling'; Id = 1; LogFile = @{ Directory = $LogBase; LogFormat = 'W3C' } }
            @{ Name = 'Dot segment spelling'; Id = 1; LogFile = @{ Directory = $LogBase + '\..\LogFiles\'; LogFormat = 'W3C' } }
            @{ Name = 'Alternate separators'; Id = 1; LogFile = @{ Directory = $LogBase.Replace('\', '/') + '/'; LogFormat = 'W3C' } }
        )
        if ($Scenario -eq 'WebFormatUnknown') {
            $Sites = @(
                @{ Name = 'Unknown web format'; Id = 1; LogFile = @{ Directory = $LogBase } }
            )
        }
        if ($Scenario -eq 'FtpSuccess') {
            $FtpRoot = Join-Path -Path $LogBase -ChildPath 'FTPSVC2'
            $null = New-Item -Path $FtpRoot -ItemType Directory -Force
            $FtpLog = New-Item -Path (Join-Path -Path $FtpRoot -ChildPath 'inetsv01.log') -ItemType File
            $FtpLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
            $Sites += @{ Name = 'FTP site'; Id = 2; LogFile = @{ Directory = $LogBase; LogFormat = 'W3C' }; Bindings = @(@{ Protocol = 'ftp' }); FtpServer = @{ LogFile = @{ Directory = $LogBase; LogFormat = 'IIS' } } }
        }
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
        $OldLog = New-Item -Path (Join-Path -Path $IISRoot -ChildPath 'u_ex240101.log') -ItemType File
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
        $env:SystemDrive = ''
        $RegistrySpelling = $IISRoot + $Suffix
        Mock Get-ItemProperty { [pscustomobject]@{ LogDir = $RegistrySpelling; LogFormat = 'W3C' } }

        $Results = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop)

        $Results | Should -HaveCount 1
        $Results[0].RootPath | Should -Be ([System.IO.Path]::GetFullPath($IISRoot))
        $Results[0].FileCandidateCount | Should -Be 1
        $Results[0].CandidatePaths | Should -HaveCount 1
        $Results[0].CandidatePaths | Should -Contain $OldLog.FullName
        $OldLog.FullName | Should -Exist
    }

    It 'preserves a known registry format when it duplicates an unknown default root' {
        Mock Get-ItemProperty { [pscustomobject]@{ LogDir = $IISRoot; LogFormat = 'W3C' } }

        $Results = @(Clear-OldIISLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop)

        $Results | Should -HaveCount 1
        $Results[0].Status | Should -Be 'WhatIf'
        $Results[0].FileCandidateCount | Should -Be 1
        $Results[0].ErrorIds | Should -Not -Contain 'IISLogFormatUnavailable'
    }

    It 'does not collapse distinct custom and default roots' {
        $CustomRoot = Join-Path -Path $FixtureRoot -ChildPath 'CustomLogs'
        $null = New-Item -Path $CustomRoot -ItemType Directory
        Mock Get-ItemProperty { [pscustomobject]@{ LogDir = $CustomRoot; LogFormat = 'W3C' } }

        $Results = @(Clear-OldIISLog -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop)

        $Results | Should -HaveCount 2
        $Results.RootPath | Should -Contain ([System.IO.Path]::GetFullPath($IISRoot))
        $Results.RootPath | Should -Contain ([System.IO.Path]::GetFullPath($CustomRoot))
        $OldLog.FullName | Should -Exist
    }
}

Describe 'IIS extended-length traversal' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'keeps the extended-length namespace on provider traversal paths' {
        $PreviousSystemDrive = $env:SystemDrive
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $IISRoot = Join-Path -Path $FixtureRoot -ChildPath 'inetpub/logs/LogFiles'
        $ExtendedRoot = '\\?\' + $IISRoot
        $NormalizedRoot = Convert-TheCleanersPathForComparison -Path $ExtendedRoot
        $ObservedPaths = [System.Collections.Generic.List[string]]::new()

        try {
            $env:SystemDrive = ''
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
            Mock Get-ItemProperty { [pscustomobject]@{ LogDir = $ExtendedRoot; LogFormat = 'W3C' } }
            Mock Test-TheCleanersIisProtectedPath { $false }
            Mock Test-Path { $true }
            Mock Resolve-TheCleanersFileSystemPath { [System.IO.DirectoryInfo]::new($LiteralPath) }
            Mock Get-ChildItem { $null = $ObservedPaths.Add([string]$LiteralPath) }

            $Result = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop)

            $Result | Should -HaveCount 1
            $Result[0].RootPath | Should -Be $NormalizedRoot
            $ObservedPaths | Should -Contain $ExtendedRoot
            $ObservedPaths | Should -Not -Contain $NormalizedRoot
        } finally {
            $env:SystemDrive = $PreviousSystemDrive
        }
    }
}

Describe 'IIS FTP root discovery' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'discovers an FTP site log root from its separate configuration' {
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $ModuleSearchRoot = Join-Path -Path $FixtureRoot -ChildPath 'Modules'
        $DependencyRoot = Join-Path -Path $ModuleSearchRoot -ChildPath 'WebAdministration'
        $LogBase = Join-Path -Path $FixtureRoot -ChildPath 'LogFiles'
        $FtpRoot = Join-Path -Path $LogBase -ChildPath 'FTPSVC7'
        $FtpLogPath = Join-Path -Path $FtpRoot -ChildPath 'u_ex240101.log'
        $null = New-Item -Path $DependencyRoot -ItemType Directory -Force
        $null = New-Item -Path $FtpRoot -ItemType Directory -Force
        $FtpLog = New-Item -Path $FtpLogPath -ItemType File
        $FtpLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $Sites = @(
            @{ Name = 'FTP fixture'; Id = 7; LogFile = @{ Directory = $LogBase; LogFormat = 'W3C' }; Bindings = @(@{ Protocol = 'ftp' }); FtpServer = @{ LogFile = @{ Directory = $LogBase; LogFormat = 'W3C' } } }
        )
        @{ FailDiscovery = $false; Sites = $Sites } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path -Path $DependencyRoot -ChildPath 'Sites.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path -Path $DependencyRoot -ChildPath 'WebAdministration.psm1') -Value $FixtureModuleContent -Encoding UTF8
        $PreviousPSModulePath = $env:PSModulePath
        $env:PSModulePath = $ModuleSearchRoot + [System.IO.Path]::PathSeparator + $PreviousPSModulePath

        try {
            $Results = @(Clear-OldIISLog -Days 60 -WhatIf -PassThru -WarningAction SilentlyContinue -ErrorAction Stop)
        } finally {
            Remove-Module -Name 'WebAdministration' -Force -ErrorAction SilentlyContinue
            $env:PSModulePath = $PreviousPSModulePath
        }

        $Results | Should -HaveCount 1
        $Results[0].RootPath | Should -Be ([System.IO.Path]::GetFullPath($FtpRoot))
        $Results[0].CandidatePaths | Should -Contain ([System.IO.Path]::GetFullPath($FtpLogPath))
        $Results[0].FileCandidateCount | Should -Be 1
        $FtpLogPath | Should -Exist
    }

    It 'preserves an FTP discovery failure when that site web root is absent' {
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $ModuleSearchRoot = Join-Path -Path $FixtureRoot -ChildPath 'Modules'
        $DependencyRoot = Join-Path -Path $ModuleSearchRoot -ChildPath 'WebAdministration'
        $LogBase = Join-Path -Path $FixtureRoot -ChildPath 'LogFiles'
        $ExistingWebRoot = Join-Path -Path $LogBase -ChildPath 'W3SVC9'
        $ExistingWebLogPath = Join-Path -Path $ExistingWebRoot -ChildPath 'u_ex240101.log'
        $null = New-Item -Path $DependencyRoot -ItemType Directory -Force
        $null = New-Item -Path $ExistingWebRoot -ItemType Directory -Force
        $ExistingWebLog = New-Item -Path $ExistingWebLogPath -ItemType File
        $ExistingWebLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $Sites = @(
            @{ Name = 'FTP failure'; Id = 8; LogFile = @{ Directory = $LogBase; LogFormat = 'W3C' }; Bindings = @(@{ Protocol = 'ftp' }); FtpServer = @{ LogFile = @{ Directory = $null } } }
            @{ Name = 'Existing web'; Id = 9; LogFile = @{ Directory = $LogBase; LogFormat = 'W3C' }; Bindings = @() }
        )
        @{ FailDiscovery = $false; Sites = $Sites } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path -Path $DependencyRoot -ChildPath 'Sites.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path -Path $DependencyRoot -ChildPath 'WebAdministration.psm1') -Value $FixtureModuleContent -Encoding UTF8
        $ProbePath = Join-Path -Path $FixtureRoot -ChildPath 'Probe.ps1'
        Set-Content -LiteralPath $ProbePath -Value $ProbeContent -Encoding UTF8
        $PreviousPSModulePath = $env:PSModulePath

        try {
            $env:PSModulePath = $ModuleSearchRoot + [System.IO.Path]::PathSeparator + $PreviousPSModulePath
            $ProbeOutput = & $PowerShellExecutable -NoLogo -NoProfile -NonInteractive -File $ProbePath -ManifestPath $ManifestPath -ModuleSearchRoot $ModuleSearchRoot -LogRoot $ExistingWebRoot -Scenario 'FtpRootFailureWithExistingWeb' 2>&1
            $ProbeExitCode = $LASTEXITCODE
            $Diagnostic = [regex]::Replace(($ProbeOutput -join [Environment]::NewLine), '\x1B\[[0-?]*[ -/]*[@-~]', '')
        } finally {
            Remove-Module -Name 'WebAdministration' -Force -ErrorAction SilentlyContinue
            $env:PSModulePath = $PreviousPSModulePath
        }

        $ProbeExitCode | Should -Be 0 -Because $Diagnostic
        $ProbeOutput | Should -Contain 'IIS_DISCOVERY_OK'
        $ExistingWebLogPath | Should -Exist
    }

    It 'returns a per-FTP failure placeholder when the site has no web log root' {
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $ModuleSearchRoot = Join-Path -Path $FixtureRoot -ChildPath 'Modules'
        $DependencyRoot = Join-Path -Path $ModuleSearchRoot -ChildPath 'WebAdministration'
        $LogBase = Join-Path -Path $FixtureRoot -ChildPath 'LogFiles'
        $ExistingWebRoot = Join-Path -Path $LogBase -ChildPath 'W3SVC9'
        $ExistingWebLogPath = Join-Path -Path $ExistingWebRoot -ChildPath 'u_ex240101.log'
        $null = New-Item -Path $DependencyRoot -ItemType Directory -Force
        $null = New-Item -Path $ExistingWebRoot -ItemType Directory -Force
        $ExistingWebLog = New-Item -Path $ExistingWebLogPath -ItemType File
        $ExistingWebLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $Sites = @(
            @{ Name = 'FTP without web root'; Id = 8; LogFile = @{ Directory = $null; LogFormat = 'W3C' }; Bindings = @(@{ Protocol = 'ftp' }); FtpServer = @{ LogFile = @{ Directory = $null } } }
            @{ Name = 'Existing web'; Id = 9; LogFile = @{ Directory = $LogBase; LogFormat = 'W3C' }; Bindings = @() }
        )
        @{ FailDiscovery = $false; Sites = $Sites } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path -Path $DependencyRoot -ChildPath 'Sites.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path -Path $DependencyRoot -ChildPath 'WebAdministration.psm1') -Value $FixtureModuleContent -Encoding UTF8
        $ProbePath = Join-Path -Path $FixtureRoot -ChildPath 'Probe.ps1'
        Set-Content -LiteralPath $ProbePath -Value $ProbeContent -Encoding UTF8
        $PreviousPSModulePath = $env:PSModulePath

        try {
            $env:PSModulePath = $ModuleSearchRoot + [System.IO.Path]::PathSeparator + $PreviousPSModulePath
            $ProbeOutput = & $PowerShellExecutable -NoLogo -NoProfile -NonInteractive -File $ProbePath -ManifestPath $ManifestPath -ModuleSearchRoot $ModuleSearchRoot -LogRoot $ExistingWebRoot -Scenario 'FtpRootFailureWithNoWebRoot' 2>&1
            $ProbeExitCode = $LASTEXITCODE
            $Diagnostic = [regex]::Replace(($ProbeOutput -join [Environment]::NewLine), '\x1B\[[0-?]*[ -/]*[@-~]', '')
        } finally {
            Remove-Module -Name 'WebAdministration' -Force -ErrorAction SilentlyContinue
            $env:PSModulePath = $PreviousPSModulePath
        }

        $ProbeExitCode | Should -Be 0 -Because $Diagnostic
        $ProbeOutput | Should -Contain 'IIS_DISCOVERY_OK'
        $ExistingWebLogPath | Should -Exist
    }

    It 'keeps a valid web-root preview separate from an FTP discovery failure' {
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $ModuleSearchRoot = Join-Path -Path $FixtureRoot -ChildPath 'Modules'
        $DependencyRoot = Join-Path -Path $ModuleSearchRoot -ChildPath 'WebAdministration'
        $LogBase = Join-Path -Path $FixtureRoot -ChildPath 'LogFiles'
        $WebRoot = Join-Path -Path $LogBase -ChildPath 'W3SVC8'
        $WebLogPath = Join-Path -Path $WebRoot -ChildPath 'u_ex240101.log'
        $null = New-Item -Path $DependencyRoot -ItemType Directory -Force
        $null = New-Item -Path $WebRoot -ItemType Directory -Force
        $WebLog = New-Item -Path $WebLogPath -ItemType File
        $WebLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $Sites = @(
            @{ Name = 'FTP valid web'; Id = 8; LogFile = @{ Directory = $LogBase; LogFormat = 'W3C' }; Bindings = @(@{ Protocol = 'ftp' }); FtpServer = @{ LogFile = @{ Directory = $null } } }
        )
        @{ FailDiscovery = $false; Sites = $Sites } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path -Path $DependencyRoot -ChildPath 'Sites.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path -Path $DependencyRoot -ChildPath 'WebAdministration.psm1') -Value $FixtureModuleContent -Encoding UTF8
        $ProbePath = Join-Path -Path $FixtureRoot -ChildPath 'Probe.ps1'
        Set-Content -LiteralPath $ProbePath -Value $ProbeContent -Encoding UTF8
        $PreviousPSModulePath = $env:PSModulePath

        try {
            $env:PSModulePath = $ModuleSearchRoot + [System.IO.Path]::PathSeparator + $PreviousPSModulePath
            $ProbeOutput = & $PowerShellExecutable -NoLogo -NoProfile -NonInteractive -File $ProbePath -ManifestPath $ManifestPath -ModuleSearchRoot $ModuleSearchRoot -LogRoot $WebRoot -Scenario 'FtpRootFailureWithValidWeb' 2>&1
            $ProbeExitCode = $LASTEXITCODE
            $Diagnostic = [regex]::Replace(($ProbeOutput -join [Environment]::NewLine), '\x1B\[[0-?]*[ -/]*[@-~]', '')
        } finally {
            Remove-Module -Name 'WebAdministration' -Force -ErrorAction SilentlyContinue
            $env:PSModulePath = $PreviousPSModulePath
        }

        $ProbeExitCode | Should -Be 0 -Because $Diagnostic
        $ProbeOutput | Should -Contain 'IIS_DISCOVERY_OK'
        $WebLogPath | Should -Exist
    }
}

