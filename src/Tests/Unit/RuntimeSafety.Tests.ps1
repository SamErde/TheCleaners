BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    $ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'TheCleaners.psd1'
    $PowerShellExecutable = (Get-Process -Id $PID).Path
    foreach ($RelativePath in @(
        'Private/ResultContracts.ps1'
        'Private/Initialize-TheCleanersNativeFileInterop.ps1'
        'Private/Get-TheCleanersWindowsTempRoot.ps1'
        'Private/Get-TheCleanersTempPlan.ps1'
        'Private/Resolve-TheCleanersFileSystemPath.ps1'
        'Public/Clear-CurrentUserTemp.ps1'
        'Public/Clear-WindowsTemp.ps1'
    )) {
        . (Join-Path -Path $ModuleRoot -ChildPath $RelativePath)
    }

    function Invoke-TheCleanersInteractiveConfirmProbe {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [string]
            $ManifestPath,

            [Parameter(Mandatory)]
            [string]
            $FixtureRoot,

            [Parameter(Mandatory)]
            [ValidateSet('Clear-CurrentUserTemp', 'Clear-WindowsTemp')]
            [string]
            $CommandName,

            [Parameter(Mandatory)]
            [ValidateSet('Approved', 'Declined')]
            [string]
            $ExpectedOutcome,

            [Parameter(Mandatory)]
            [ValidateSet('Y', 'N')]
            [string]
            $Response
        )

        $ProbeScript = @'
$ErrorActionPreference = 'Stop'
$FixtureRoot = $env:THECLEANERS_CONFIRM_FIXTURE
$env:TEMP = $FixtureRoot
$env:TMP = $FixtureRoot
$OldFile = New-Item -Path (Join-Path -Path $FixtureRoot -ChildPath 'old.tmp') -ItemType File
[System.IO.File]::SetLastWriteTimeUtc($OldFile.FullName, [DateTime]::UtcNow.AddDays(-31))
if ($env:THECLEANERS_CONFIRM_COMMAND -eq 'Clear-WindowsTemp') {
    $ModuleRoot = Split-Path -Path $env:THECLEANERS_CONFIRM_MANIFEST -Parent
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/ResultContracts.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Initialize-TheCleanersNativeFileInterop.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Resolve-TheCleanersFileSystemPath.ps1')
    . (Join-Path -Path $ModuleRoot -ChildPath 'Private/Get-TheCleanersTempPlan.ps1')
    function Get-TheCleanersWindowsTempRoot {
        Get-Item -Path $FixtureRoot -Force -ErrorAction Stop
    }
    . (Join-Path -Path $ModuleRoot -ChildPath 'Public/Clear-WindowsTemp.ps1')
} else {
    Import-Module -Name $env:THECLEANERS_CONFIRM_MANIFEST -Force
}
$Result = & $env:THECLEANERS_CONFIRM_COMMAND -Days 30 -Confirm -PassThru -ErrorAction Stop
if ($env:THECLEANERS_CONFIRM_EXPECTED -eq 'Approved') {
    if ($Result.Status -ne 'Completed' -or $Result.FilesRemoved -ne 1 -or [System.IO.File]::Exists($OldFile.FullName)) {
        throw 'The approval response did not complete the expected fixture removal.'
    }
} elseif ($Result.Status -ne 'Declined' -or $Result.FilesRemoved -ne 0 -or -not [System.IO.File]::Exists($OldFile.FullName)) {
    throw 'The decline response did not preserve the fixture.'
}
'CONFIRM_INTERACTIVE_OK'
'@
        $EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ProbeScript))
        $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $StartInfo.FileName = $PowerShellExecutable
        $StartInfo.Arguments = "-NoLogo -NoProfile -EncodedCommand $EncodedCommand"
        $StartInfo.UseShellExecute = $false
        $StartInfo.CreateNoWindow = $true
        $StartInfo.RedirectStandardInput = $true
        $StartInfo.RedirectStandardOutput = $true
        $StartInfo.RedirectStandardError = $true
        $StartInfo.EnvironmentVariables['THECLEANERS_CONFIRM_MANIFEST'] = $ManifestPath
        $StartInfo.EnvironmentVariables['THECLEANERS_CONFIRM_FIXTURE'] = $FixtureRoot
        $StartInfo.EnvironmentVariables['THECLEANERS_CONFIRM_EXPECTED'] = $ExpectedOutcome
        $StartInfo.EnvironmentVariables['THECLEANERS_CONFIRM_COMMAND'] = $CommandName

        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $StartInfo
        try {
            $null = $Process.Start()
            $OutputTask = $Process.StandardOutput.ReadToEndAsync()
            $ErrorTask = $Process.StandardError.ReadToEndAsync()
            $Process.StandardInput.WriteLine($Response)
            $Process.StandardInput.Close()
            if (-not $Process.WaitForExit(30000)) {
                $Process.Kill()
                $Process.WaitForExit()
                throw "The interactive confirmation probe did not finish for '$ExpectedOutcome'."
            }
            [pscustomobject]@{
                ExitCode = $Process.ExitCode
                Output   = $OutputTask.Result
                Error    = $ErrorTask.Result
            }
        } finally {
            $Process.Dispose()
        }
    }
}

Describe 'Windows runtime and preflight safety' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'resolves the operating-system Windows temp root without trusting a spoofed environment value' {
        $PreviousSystemRoot = $env:SystemRoot
        try {
            $env:SystemRoot = Join-Path -Path $TestDrive -ChildPath 'SpoofedWindows'
            $ExpectedRoot = Join-Path -Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) -ChildPath 'Temp'
            $Result = Get-TheCleanersWindowsTempRoot

            [System.IO.Path]::GetFullPath($Result.FullName) | Should -Be ([System.IO.Path]::GetFullPath($ExpectedRoot))
        } finally {
            $env:SystemRoot = $PreviousSystemRoot
        }
    }

    It 'reports the actual Windows token elevation state' {
        $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $Principal = [System.Security.Principal.WindowsPrincipal]::new($Identity)
        $Expected = if ($Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            'Elevated'
        } else {
            'NotElevated'
        }

        Get-TheCleanersPrivilegeStatus | Should -Be $Expected
    }

    It 'rejects broad, other-user, and UNC current-user temp roots' {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        try {
            $UnsafeRoots = @(
                (Join-Path -Path (Split-Path -Path $env:USERPROFILE -Parent) -ChildPath 'Public')
                '\\server\share\temp'
            )
            foreach ($UnsafeRoot in $UnsafeRoots) {
                $env:TEMP = $UnsafeRoot
                $env:TMP = $UnsafeRoot
                { Clear-CurrentUserTemp -Days 30 -WhatIf -Confirm:$false -ErrorAction Stop } | Should -Throw
            }
        } finally {
            $env:TEMP = $PreviousTemp
            $env:TMP = $PreviousTmp
        }
    }

    It 'returns a failed summary for a rejected current-user root under continuing errors' {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        try {
            $UnsafeRoot = Join-Path -Path (Split-Path -Path $env:USERPROFILE -Parent) -ChildPath 'Public'
            $env:TEMP = $UnsafeRoot
            $env:TMP = $UnsafeRoot

            $Result = @(Clear-CurrentUserTemp -Days 30 -WhatIf -PassThru -ErrorAction Continue -ErrorVariable RootError)

            $Result | Should -HaveCount 1
            $Result[0].Status | Should -Be 'DiscoveryFailed'
            $Result[0].DiscoveryStatus | Should -Be 'Failed'
            $Result[0].FileCandidateCount | Should -BeNullOrEmpty
            $Result[0].DirectoryCandidateCount | Should -BeNullOrEmpty
            $Result[0].ErrorIds | Should -Contain 'TempRootValidationFailed'
            $RootError | Should -Not -BeNullOrEmpty
        } finally {
            $env:TEMP = $PreviousTemp
            $env:TMP = $PreviousTmp
        }
    }

    It 'returns a failed summary for a rejected Windows temp root under continuing errors' {
        Mock Get-TheCleanersWindowsTempRoot { throw [System.UnauthorizedAccessException]::new('Fixture Windows temp root denial.') }

        $Result = @(Clear-WindowsTemp -Days 30 -WhatIf -PassThru -ErrorAction Continue -ErrorVariable RootError)

        $Result | Should -HaveCount 1
        $Result[0].Status | Should -Be 'DiscoveryFailed'
        $Result[0].DiscoveryStatus | Should -Be 'Failed'
        $Result[0].FileCandidateCount | Should -BeNullOrEmpty
        $Result[0].DirectoryCandidateCount | Should -BeNullOrEmpty
        $Result[0].ErrorIds | Should -Contain 'TempRootValidationFailed'
        $RootError | Should -Not -BeNullOrEmpty
    }

    It 'includes the actual privilege state in a fixture-only WhatIf result' {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        try {
            $FixtureRoot = Join-Path -Path $TestDrive -ChildPath 'CurrentUserTemp'
            $null = New-Item -Path $FixtureRoot -ItemType Directory -Force
            $OldFile = New-Item -Path (Join-Path -Path $FixtureRoot -ChildPath 'old.tmp') -ItemType File
            [System.IO.File]::SetLastWriteTimeUtc($OldFile.FullName, [DateTime]::UtcNow.AddDays(-31))
            $env:TEMP = $FixtureRoot
            $env:TMP = $FixtureRoot

            $Result = Clear-CurrentUserTemp -Days 30 -WhatIf -Confirm:$false -PassThru

            $Result.RootPath | Should -Be ([System.IO.Path]::GetFullPath($FixtureRoot))
            $Result.Status | Should -Be 'WhatIf'
            $Result.PrivilegeStatus | Should -Be (Get-TheCleanersPrivilegeStatus)
            $OldFile.FullName | Should -Exist
        } finally {
            $env:TEMP = $PreviousTemp
            $env:TMP = $PreviousTmp
        }
    }

    It 'keeps WhatIf state unchanged in a fresh process and does not initialize native interop' {
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath 'WhatIfState'
        $null = New-Item -Path $FixtureRoot -ItemType Directory -Force
        $ProbePath = Join-Path -Path $TestDrive -ChildPath 'WhatIfStateProbe.ps1'
        @'
param (
    [Parameter(Mandatory)]
    [string]
    $ManifestPath,

    [Parameter(Mandatory)]
    [string]
    $FixtureRoot
)

$ErrorActionPreference = 'Stop'
$env:TEMP = $FixtureRoot
$env:TMP = $FixtureRoot
$OldFile = New-Item -Path (Join-Path -Path $FixtureRoot -ChildPath 'old.tmp') -ItemType File
[System.IO.File]::SetLastWriteTimeUtc($OldFile.FullName, [DateTime]::UtcNow.AddDays(-31))
Import-Module -Name $ManifestPath -Force
$BeforeWhatIf = $WhatIfPreference
$BeforeConfirm = $ConfirmPreference
$BeforeModule = Get-Module -Name TheCleaners
if ($null -ne ([System.Management.Automation.PSTypeName]'TheCleaners.NativeFileInterop').Type) {
    throw 'The native interop type was initialized during module import.'
}
$Result = Clear-CurrentUserTemp -Days 30 -WhatIf -Confirm:$false -PassThru
if ($Result.Status -ne 'WhatIf' -or $Result.FilesRemoved -ne 0 -or $Result.BytesReclaimed -ne 0) {
    throw 'WhatIf returned an invalid mutation summary.'
}
if (-not [System.IO.File]::Exists($OldFile.FullName)) {
    throw 'WhatIf changed the fixture file.'
}
if ($WhatIfPreference -ne $BeforeWhatIf -or $ConfirmPreference -ne $BeforeConfirm) {
    throw 'WhatIf changed caller preferences.'
}
if ($null -ne ([System.Management.Automation.PSTypeName]'TheCleaners.NativeFileInterop').Type) {
    throw 'WhatIf initialized process-global native interop state.'
}
if ($BeforeModule.ExportedVariables.Count -ne (Get-Module -Name TheCleaners).ExportedVariables.Count) {
    throw 'WhatIf changed the module export state.'
}
'WHATIF_STATE_OK'
'@ | Set-Content -LiteralPath $ProbePath -Encoding UTF8

        $ProbeOutput = & $PowerShellExecutable -NoLogo -NoProfile -NonInteractive -File $ProbePath -ManifestPath $ManifestPath -FixtureRoot $FixtureRoot 2>&1
        $ProbeExitCode = $LASTEXITCODE
        $ProbeExitCode | Should -Be 0 -Because ($ProbeOutput -join [Environment]::NewLine)
        $ProbeOutput | Should -Contain 'WHATIF_STATE_OK'
    }

    It 'keeps explicit Confirm false state unchanged while deleting only the fixture' {
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath 'ConfirmState'
        $null = New-Item -Path $FixtureRoot -ItemType Directory -Force
        $ProbePath = Join-Path -Path $TestDrive -ChildPath 'ConfirmStateProbe.ps1'
        @'
param (
    [Parameter(Mandatory)]
    [string]
    $ManifestPath,

    [Parameter(Mandatory)]
    [string]
    $FixtureRoot
)

$ErrorActionPreference = 'Stop'
$env:TEMP = $FixtureRoot
$env:TMP = $FixtureRoot
$OldFile = New-Item -Path (Join-Path -Path $FixtureRoot -ChildPath 'old.tmp') -ItemType File
[System.IO.File]::SetLastWriteTimeUtc($OldFile.FullName, [DateTime]::UtcNow.AddDays(-31))
$WhatIfPreference = $false
$ConfirmPreference = 'Low'
$BeforeWhatIf = $WhatIfPreference
$BeforeConfirm = $ConfirmPreference
Import-Module -Name $ManifestPath -Force
$Result = Clear-CurrentUserTemp -Days 30 -Confirm:$false -PassThru -ErrorAction Stop
if ($Result.Status -ne 'Completed' -or $Result.FilesRemoved -ne 1) {
    throw 'Confirm false did not complete the fixture mutation.'
}
if ([System.IO.File]::Exists($OldFile.FullName)) {
    throw 'Confirm false left the fixture candidate behind.'
}
if ($WhatIfPreference -ne $BeforeWhatIf -or $ConfirmPreference -ne $BeforeConfirm) {
    throw 'Confirm false changed caller preferences.'
}
'CONFIRM_STATE_OK'
'@ | Set-Content -LiteralPath $ProbePath -Encoding UTF8

        $ProbeOutput = & $PowerShellExecutable -NoLogo -NoProfile -File $ProbePath -ManifestPath $ManifestPath -FixtureRoot $FixtureRoot 2>&1
        $ProbeExitCode = $LASTEXITCODE
        $ProbeExitCode | Should -Be 0 -Because ($ProbeOutput -join [Environment]::NewLine)
        $ProbeOutput | Should -Contain 'CONFIRM_STATE_OK'
        (Test-Path -LiteralPath (Join-Path -Path $FixtureRoot -ChildPath 'old.tmp')) | Should -BeFalse
    }

    It 'accepts and declines one explicit confirmation without nested prompts for both temp commands' {
        foreach ($CommandCase in @(
                @{ Name = 'Clear-CurrentUserTemp' }
                @{ Name = 'Clear-WindowsTemp' }
            )) {
            foreach ($Case in @(
                    @{ Name = 'Approved'; Response = 'Y' }
                    @{ Name = 'Declined'; Response = 'N' }
                )) {
                $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ('InteractiveConfirm-{0}-{1}' -f $CommandCase.Name, $Case.Name)
                $null = New-Item -Path $FixtureRoot -ItemType Directory -Force
                $Probe = Invoke-TheCleanersInteractiveConfirmProbe -ManifestPath $ManifestPath -FixtureRoot $FixtureRoot -CommandName $CommandCase.Name -ExpectedOutcome $Case.Name -Response $Case.Response
                $CombinedOutput = '{0}{1}' -f $Probe.Output, $Probe.Error

                $Probe.ExitCode | Should -Be 0 -Because $CombinedOutput
                $CombinedOutput | Should -Match 'CONFIRM_INTERACTIVE_OK'
            }
        }
    }

    It 'serializes native interop initialization across concurrent runspaces' {
        $ProbePath = Join-Path -Path $TestDrive -ChildPath 'NativeInteropConcurrencyProbe.ps1'
        @'
param (
    [Parameter(Mandatory)]
    [string]
    $InteropScriptPath
)

$ErrorActionPreference = 'Stop'
$InteropSource = [System.IO.File]::ReadAllText($InteropScriptPath)
$Pool = [RunspaceFactory]::CreateRunspacePool(1, 8)
$Pool.Open()
$Jobs = [System.Collections.Generic.List[object]]::new()
$Worker = @(
    'param ('
    '    [Parameter(Mandatory)]'
    '    [string]'
    '    $InteropSource'
    ')'
    ''
    '. ([scriptblock]::Create($InteropSource))'
    'Initialize-TheCleanersNativeFileInterop'
) -join [Environment]::NewLine
try {
    for ($Index = 0; $Index -lt 8; $Index++) {
        $PowerShell = [powershell]::Create()
        $PowerShell.RunspacePool = $Pool
        $null = $PowerShell.AddScript($Worker).AddArgument($InteropSource)
        $Jobs.Add([pscustomobject]@{
                PowerShell = $PowerShell
                Handle     = $PowerShell.BeginInvoke()
            })
    }
    foreach ($Job in $Jobs) {
        $null = $Job.PowerShell.EndInvoke($Job.Handle)
        if ($Job.PowerShell.HadErrors) {
            throw (($Job.PowerShell.Streams.Error | ForEach-Object { $_.Exception.Message }) -join '; ')
        }
    }
} finally {
    foreach ($Job in $Jobs) {
        $Job.PowerShell.Dispose()
    }
    $Pool.Dispose()
}
if ($null -eq ([System.Management.Automation.PSTypeName]'TheCleaners.NativeFileInterop').Type) {
    throw 'Concurrent initialization did not load the native interop type.'
}
'NATIVE_INTEROP_CONCURRENCY_OK'
'@ | Set-Content -LiteralPath $ProbePath -Encoding UTF8

        $ProbeOutput = & $PowerShellExecutable -NoLogo -NoProfile -NonInteractive -File $ProbePath -InteropScriptPath (Join-Path -Path $ModuleRoot -ChildPath 'Private/Initialize-TheCleanersNativeFileInterop.ps1') 2>&1
        $ProbeExitCode = $LASTEXITCODE
        $ProbeExitCode | Should -Be 0 -Because ($ProbeOutput -join [Environment]::NewLine)
        $ProbeOutput | Should -Contain 'NATIVE_INTEROP_CONCURRENCY_OK'
    }
}

Describe 'Long-path and containment boundaries' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'either resolves an actual extended-length fixture or fails closed when long-path policy is disabled' {
        $LongRoot = Join-Path -Path $TestDrive -ChildPath 'LongRoot'
        $null = New-Item -Path $LongRoot -ItemType Directory -Force
        $LongDirectory = $LongRoot
        for ($Index = 0; $Index -lt 24; $Index++) {
            $LongDirectory = Join-Path -Path $LongDirectory -ChildPath ('segment{0:D2}abcdefgh' -f $Index)
        }
        $LongFile = Join-Path -Path $LongDirectory -ChildPath 'old.tmp'
        $Created = $false
        try {
            $null = New-Item -Path $LongDirectory -ItemType Directory -Force -ErrorAction Stop
            $null = New-Item -Path $LongFile -ItemType File -Force -ErrorAction Stop
            $Created = $true
        } catch {
            $Created = $false
        }

        $ExtendedPath = '\\?\' + $LongFile
        $ExtendedRoot = '\\?\' + $LongRoot
        Test-TheCleanersFullyQualifiedPath -Path $ExtendedPath | Should -BeTrue
        if ($Created) {
            Resolve-TheCleanersFileSystemPath -LiteralPath $ExtendedPath -RootPath $ExtendedRoot | Should -Not -BeNullOrEmpty
        } else {
            $Policy = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue
            if ($null -ne $Policy) {
                $Policy.LongPathsEnabled | Should -Be 0
            }
            { Resolve-TheCleanersFileSystemPath -LiteralPath $ExtendedPath } | Should -Throw
        }
    }
}
