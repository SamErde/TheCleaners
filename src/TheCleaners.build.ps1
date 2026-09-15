<#
.SYNOPSIS
    Build, test, document, and package TheCleaners without merging source files.
.DESCRIPTION
    The module artifact preserves the reviewed source layout. The build creates
    help and reports outside the package, copies the module source into an
    isolated artifact directory, runs the artifact integration probe, and then
    creates one deterministic archive plus a manifest and SHA-256 sidecar.
.EXAMPLE
    Invoke-Build -File .\src\TheCleaners.build.ps1
.EXAMPLE
    Invoke-Build -File .\src\TheCleaners.build.ps1 -Task TestLocal
#>

#Include: Settings
$ModuleName = [regex]::Match((Get-Item $BuildFile).Name, '^(.*)\.build\.ps1$').Groups[1].Value
. (Join-Path -Path $BuildRoot -ChildPath "$ModuleName.Settings.ps1")

function Get-BuildCommitId {
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_SHA)) {
        return $env:GITHUB_SHA
    }

    try {
        $Commit = (& git -C $BuildRoot rev-parse HEAD 2>$null | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($Commit)) {
            return $Commit.Trim()
        }
    } catch {
        return 'unavailable'
    }

    'unavailable'
}

function Get-RelativeArtifactPath {
    param (
        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $Root
    )

    $Path.Substring($Root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
}

function Assert-TestResultPassed {
    param (
        [Parameter(Mandatory)]
        [psobject]
        $Result,

        [Parameter(Mandatory)]
        [string]
        $ReportPath,

        [Parameter(Mandatory)]
        [string]
        $TestKind
    )

    $Skipped = if ($null -eq $Result.SkippedCount) { 0 } else { [int]$Result.SkippedCount }
    $NotRun = if ($null -eq $Result.NotRunCount) { 0 } else { [int]$Result.NotRunCount }
    $Failures = if ($null -eq $Result.FailedCount) { 0 } else { [int]$Result.FailedCount }
    if ([int]$Result.TotalCount -eq 0 -or $Result.Result -ne 'Passed' -or $Failures -ne 0 -or $Skipped -ne 0 -or $NotRun -ne 0) {
        throw "$TestKind gate failed. Total=$($Result.TotalCount); Failed=$Failures; Skipped=$Skipped; NotRun=$NotRun; Result=$($Result.Result); Report=$ReportPath"
    }
}

function Write-TestSummary {
    param (
        [Parameter(Mandatory)]
        [psobject]
        $Result,

        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $TestKind,

        [Parameter()]
        [Nullable[double]]
        $CoveragePercent
    )

    $Skipped = if ($null -eq $Result.SkippedCount) { 0 } else { [int]$Result.SkippedCount }
    $NotRun = if ($null -eq $Result.NotRunCount) { 0 } else { [int]$Result.NotRunCount }
    $Summary = [ordered]@{
        TestKind        = $TestKind
        Result          = [string]$Result.Result
        TotalCount      = [int]$Result.TotalCount
        PassedCount     = [int]$Result.PassedCount
        FailedCount     = [int]$Result.FailedCount
        SkippedCount    = $Skipped
        NotRunCount     = $NotRun
        Runtime         = [ordered]@{
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            PSEdition         = $PSVersionTable.PSEdition
            OS                = [Environment]::OSVersion.VersionString
        }
        Commit          = Get-BuildCommitId
        CoveragePercent = $CoveragePercent
        GeneratedUtc    = [DateTime]::UtcNow.ToString('o')
    }
    $Summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-DeterministicZipArchive {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]
        $SourcePath,

        [Parameter(Mandatory)]
        [string]
        $DestinationPath
    )

    if (-not $PSCmdlet.ShouldProcess($DestinationPath, 'Create deterministic archive')) {
        return
    }

    if ($PSEdition -eq 'Desktop') {
        Add-Type -AssemblyName 'System.IO.Compression'
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
    }

    $ArchiveStream = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $Archive = $null
    try {
        $Archive = [System.IO.Compression.ZipArchive]::new($ArchiveStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        $Epoch = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $Files = @(Get-ChildItem -LiteralPath $SourcePath -File -Recurse -Force | Sort-Object FullName)
        foreach ($File in $Files) {
            $RelativePath = Get-RelativeArtifactPath -Path $File.FullName -Root $SourcePath
            $Entry = $Archive.CreateEntry($RelativePath, [System.IO.Compression.CompressionLevel]::Optimal)
            $Entry.LastWriteTime = $Epoch
            $InputStream = [System.IO.File]::OpenRead($File.FullName)
            $OutputStream = $null
            try {
                $OutputStream = $Entry.Open()
                $InputStream.CopyTo($OutputStream)
            } finally {
                if ($null -ne $OutputStream) {
                    $OutputStream.Dispose()
                }
                $InputStream.Dispose()
            }
        }
    } finally {
        if ($null -ne $Archive) {
            $Archive.Dispose()
        }
        $ArchiveStream.Dispose()
    }
}

function Test-ManifestBool {
    param (
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    Test-ModuleManifest -Path $Path -ErrorAction SilentlyContinue | Out-Null
    $?
}

$DefaultJobs = @(
    'Clean'
    'ValidateRequirements'
    'TestModuleManifest'
    'ImportModuleManifest'
    'Analyze'
    'AnalyzeTests'
    'FormattingCheck'
    'Test'
    'CreateHelpStart'
    'CreateMarkdownHelp'
    'CreateExternalHelp'
    'Build'
    'Archive'
    'IntegrationTest'
)
Add-BuildTask -Name . -Jobs $DefaultJobs
Add-BuildTask TestLocal -Jobs @('Clean', 'ValidateRequirements', 'TestModuleManifest', 'ImportModuleManifest', 'Analyze', 'AnalyzeTests', 'FormattingCheck', 'Test')
Add-BuildTask HelpLocal -Jobs @('Clean', 'ValidateRequirements', 'TestModuleManifest', 'ImportModuleManifest', 'CreateHelpStart', 'CreateMarkdownHelp', 'CreateExternalHelp')
Add-BuildTask BuildNoIntegration -Jobs @('Clean', 'ValidateRequirements', 'TestModuleManifest', 'ImportModuleManifest', 'Analyze', 'AnalyzeTests', 'FormattingCheck', 'Test', 'CreateHelpStart', 'CreateMarkdownHelp', 'CreateExternalHelp', 'Build', 'Archive')

Enter-Build {
    $script:ModuleName = [regex]::Match((Get-Item $BuildFile).Name, '^(.*)\.build\.ps1$').Groups[1].Value
    $script:ModuleSourcePath = Join-Path -Path $BuildRoot -ChildPath $script:ModuleName
    $script:ModuleManifestFile = Join-Path -Path $script:ModuleSourcePath -ChildPath "$($script:ModuleName).psd1"
    $script:ManifestInfo = Import-PowerShellDataFile -Path $script:ModuleManifestFile
    $script:ModuleVersion = [string]$script:ManifestInfo.ModuleVersion
    $script:FunctionsToExport = $script:ManifestInfo.FunctionsToExport

    $script:TestsPath = Join-Path -Path $BuildRoot -ChildPath 'Tests'
    $script:UnitTestsPath = Join-Path -Path $script:TestsPath -ChildPath 'Unit'
    $script:IntegrationTestsPath = Join-Path -Path $script:TestsPath -ChildPath 'Integration'
    $script:ArtifactsPath = Join-Path -Path $BuildRoot -ChildPath 'Artifacts'
    $script:ArchivePath = Join-Path -Path $BuildRoot -ChildPath 'Archive'
    $script:ReportsPath = Join-Path -Path $BuildRoot -ChildPath 'Reports'
    $script:GeneratedHelpPath = Join-Path -Path $BuildRoot -ChildPath 'GeneratedHelp'
    $script:coverageThreshold = 80

    [version]$script:MinPesterVersion = '5.7.1'
    [version]$script:MaxPesterVersion = '5.99.99'
    $script:testOutputFormat = 'NUnitXml'
}

Set-BuildHeader {
    param ($Path)
    Write-Build DarkMagenta ('=' * 79)
    Write-Build DarkGray "Task $Path : $(Get-BuildSynopsis $Task)"
    Write-Build DarkGray "At $($Task.InvocationInfo.ScriptName):$($Task.InvocationInfo.ScriptLineNumber)"
    Write-Build Yellow "Manifest File: $script:ModuleManifestFile"
    Write-Build Yellow "Manifest Version: $script:ModuleVersion"
}

Set-BuildFooter {
    param ($Path)
    Write-Build DarkGray "Done $Path, $($Task.Elapsed)"
}

Add-BuildTask ValidateRequirements {
    Write-Build White "      Verifying at least PowerShell $script:requiredPSVersion..."
    Assert-Build ($PSVersionTable.PSVersion -ge $script:requiredPSVersion) "At least PowerShell $script:requiredPSVersion is required for this build."
    Write-Build Green '      ...Verification Complete!'
}

Add-BuildTask TestModuleManifest -Before ImportModuleManifest {
    Assert-Build (Test-Path -LiteralPath $script:ModuleManifestFile -PathType Leaf) 'Unable to locate the module manifest file.'
    Assert-Build (Test-ManifestBool -Path $script:ModuleManifestFile) 'Module manifest verification failed.'
}

Add-BuildTask ImportModuleManifest {
    try {
        $null = Import-Module -Name $script:ModuleManifestFile -Force -ErrorAction Stop
    } catch {
        throw "Unable to load the project module: $($_.Exception.Message)"
    }
}

Add-BuildTask Clean {
    foreach ($Path in @($script:ArtifactsPath, $script:ArchivePath, $script:ReportsPath, $script:GeneratedHelpPath)) {
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
        $null = New-Item -Path $Path -ItemType Directory -Force
    }
}

Add-BuildTask Analyze {
    $Params = @{
        Path    = $script:ModuleSourcePath
        Setting = (Join-Path -Path $BuildRoot -ChildPath 'PSScriptAnalyzerSettings.psd1')
        Recurse = $true
        Verbose = $false
    }
    $Findings = @(Invoke-ScriptAnalyzer @Params)
    if ($Findings.Count -gt 0) {
        $Findings | Format-Table
        throw 'PSScriptAnalyzer reported errors or warnings in module source.'
    }
}

Add-BuildTask AnalyzeTests -After Analyze {
    if (Test-Path -LiteralPath $script:TestsPath) {
        $Params = @{
            Path        = $script:TestsPath
            Setting     = (Join-Path -Path $BuildRoot -ChildPath 'PSScriptAnalyzerSettings.psd1')
            ExcludeRule = @('PSUseDeclaredVarsMoreThanAssignments', 'PSUseSingularNouns', 'PSUseToExportFieldsInManifest')
            Recurse     = $true
            Verbose     = $false
        }
        $Findings = @(Invoke-ScriptAnalyzer @Params)
        if ($Findings.Count -gt 0) {
            $Findings | Format-Table
            throw 'PSScriptAnalyzer reported errors or warnings in test source.'
        }
    }
}

Add-BuildTask FormattingCheck {
    $Params = @{
        Setting     = 'CodeFormattingOTBS'
        ExcludeRule = 'PSUseConsistentWhitespace'
        Recurse     = $true
        Verbose     = $false
    }
    $Findings = @(Get-ChildItem -LiteralPath $script:ModuleSourcePath -File -Recurse -Exclude '*.psd1' | Invoke-ScriptAnalyzer @Params)
    if ($Findings.Count -gt 0) {
        $Findings | Format-Table
        throw 'Module source does not meet the required OTBS formatting rules.'
    }
}

Add-BuildTask Test {
    $LoadedPester = Get-Module -Name Pester
    if ($null -eq $LoadedPester) {
        Import-Module -Name Pester -MinimumVersion $script:MinPesterVersion -MaximumVersion $script:MaxPesterVersion -ErrorAction Stop
    } elseif ($LoadedPester.Version -lt $script:MinPesterVersion -or $LoadedPester.Version -gt $script:MaxPesterVersion) {
        throw "Loaded Pester version '$($LoadedPester.Version)' is outside the supported build range."
    }
    if ($PSEdition -eq 'Desktop') {
        . (Join-Path -Path $script:ModuleSourcePath -ChildPath 'Private/Initialize-TheCleanersNativeFileInterop.ps1')
        Initialize-TheCleanersNativeFileInterop
    }
    $Configuration = New-PesterConfiguration
    $Configuration.Run.Path = $script:UnitTestsPath
    $Configuration.Run.PassThru = $true
    $Configuration.Run.Exit = $false
    $Configuration.CodeCoverage.Enabled = $true
    $Configuration.CodeCoverage.Path = @(
        (Join-Path -Path $script:ModuleSourcePath -ChildPath '*.ps1')
        (Join-Path -Path $script:ModuleSourcePath -ChildPath '*\*.ps1')
    )
    $Configuration.CodeCoverage.CoveragePercentTarget = $script:coverageThreshold
    $Configuration.CodeCoverage.OutputPath = Join-Path -Path $script:ReportsPath -ChildPath 'CodeCoverage.xml'
    $Configuration.CodeCoverage.OutputFormat = 'JaCoCo'
    $Configuration.TestResult.Enabled = $true
    $Configuration.TestResult.OutputPath = Join-Path -Path $script:ReportsPath -ChildPath 'PesterTests.xml'
    $Configuration.TestResult.OutputFormat = $script:testOutputFormat
    $Configuration.Output.Verbosity = 'Detailed'

    try {
        $Result = Invoke-Pester -Configuration $Configuration
    } catch {
        throw "Unit test or code-coverage execution failed before a result was produced: $($_.Exception.Message)"
    }
    $CoveragePercent = $null
    if ($Result.CodeCoverage.CommandsAnalyzedCount -gt 0) {
        $CoveragePercent = [math]::Round(($Result.CodeCoverage.CommandsExecutedCount / $Result.CodeCoverage.CommandsAnalyzedCount) * 100, 2)
    }
    Write-TestSummary -Result $Result -Path (Join-Path -Path $script:ReportsPath -ChildPath 'UnitTestSummary.json') -TestKind 'Unit' -CoveragePercent $CoveragePercent
    Assert-TestResultPassed -Result $Result -ReportPath (Join-Path -Path $script:ReportsPath -ChildPath 'PesterTests.xml') -TestKind 'Unit'
    if ($null -eq $CoveragePercent -or $CoveragePercent -lt $script:coverageThreshold) {
        throw "Coverage gate failed. Required=$script:coverageThreshold%; Actual=$CoveragePercent%."
    }
}

Add-BuildTask CreateHelpStart {
    Import-Module -Name platyPS -RequiredVersion 0.14.2 -ErrorAction Stop
}

Add-BuildTask CreateMarkdownHelp -After CreateHelpStart {
    Import-Module -Name $script:ModuleManifestFile -Force -ErrorAction Stop
    $Params = @{
        Module         = $script:ModuleName
        OutputFolder   = $script:GeneratedHelpPath
        Force          = $true
        WithModulePage = $true
        Locale         = 'en-US'
        FwLink         = 'NA'
        HelpVersion    = $script:ModuleVersion
    }
    $null = New-MarkdownHelp @Params
    $GeneratedFiles = @(Get-ChildItem -LiteralPath $script:GeneratedHelpPath -File -Filter '*.md')
    if ($GeneratedFiles.Count -eq 0) {
        throw 'Help generation produced no markdown files.'
    }
    $MarkdownRepairPath = Join-Path -Path $BuildRoot -ChildPath 'MarkdownRepair.ps1'
    if (Test-Path -LiteralPath $MarkdownRepairPath -PathType Leaf) {
        . $MarkdownRepairPath
        foreach ($GeneratedFile in $GeneratedFiles) {
            Repair-PlatyPSMarkdown -Path $GeneratedFile.FullName
        }
    }
    $ModulePagePath = Join-Path -Path $script:GeneratedHelpPath -ChildPath "$($script:ModuleName).md"
    $ModulePage = Get-Content -LiteralPath $ModulePagePath -Raw
    $DescriptionMarker = '{{ Fill in the Description }}'
    $MarkerIndex = $ModulePage.IndexOf($DescriptionMarker, [System.StringComparison]::Ordinal)
    if ($MarkerIndex -lt 0) {
        throw 'The generated module help page has no module description marker.'
    }
    $ModulePage = $ModulePage.Substring(0, $MarkerIndex) + [string]$script:ManifestInfo.Description + $ModulePage.Substring($MarkerIndex + $DescriptionMarker.Length)
    foreach ($FunctionName in @($script:FunctionsToExport)) {
        $Synopsis = (Get-Help -Name $FunctionName -Full).Synopsis
        $MarkerIndex = $ModulePage.IndexOf($DescriptionMarker, [System.StringComparison]::Ordinal)
        if ($MarkerIndex -lt 0) {
            throw "The generated module help page is missing the description marker for '$FunctionName'."
        }
        $ModulePage = $ModulePage.Substring(0, $MarkerIndex) + [string]$Synopsis + $ModulePage.Substring($MarkerIndex + $DescriptionMarker.Length)
    }
    Set-Content -LiteralPath $ModulePagePath -Value $ModulePage -Encoding UTF8
    $Missing = @(Select-String -Path $GeneratedFiles.FullName -Pattern '({{.*}})' -ErrorAction SilentlyContinue)
    if ($Missing.Count -gt 0) {
        throw "Generated help contains unresolved template markers: $($Missing -join '; ')"
    }
}

Add-BuildTask CreateExternalHelp -After CreateMarkdownHelp {
    $HelpPath = Join-Path -Path $script:ArtifactsPath -ChildPath 'en-US'
    $null = New-Item -Path $HelpPath -ItemType Directory -Force
    $null = New-ExternalHelp -Path $script:GeneratedHelpPath -OutputPath $HelpPath -Force
    $HelpFile = Join-Path -Path $HelpPath -ChildPath "$($script:ModuleName)-help.xml"
    if (-not (Test-Path -LiteralPath $HelpFile -PathType Leaf)) {
        throw "External help was not generated: $HelpFile"
    }
}

Add-BuildTask AssetCopy -Before Build {
    $SourceItems = @(Get-ChildItem -LiteralPath $script:ModuleSourcePath -Force)
    foreach ($SourceItem in $SourceItems) {
        Copy-Item -LiteralPath $SourceItem.FullName -Destination $script:ArtifactsPath -Recurse -Force -ErrorAction Stop
    }
}

Add-BuildTask Build -After CreateExternalHelp {
    $RequiredPackagePaths = @(
        (Join-Path -Path $script:ArtifactsPath -ChildPath "$($script:ModuleName).psd1")
        (Join-Path -Path $script:ArtifactsPath -ChildPath "$($script:ModuleName).psm1")
        (Join-Path -Path $script:ArtifactsPath -ChildPath 'Private')
        (Join-Path -Path $script:ArtifactsPath -ChildPath 'Public')
        (Join-Path -Path $script:ArtifactsPath -ChildPath 'en-US')
    )
    foreach ($RequiredPath in $RequiredPackagePaths) {
        if (-not (Test-Path -LiteralPath $RequiredPath)) {
            throw "Source-layout package is missing: $RequiredPath"
        }
    }
    if (Test-Path -LiteralPath (Join-Path -Path $script:ArtifactsPath -ChildPath 'Invoke-TheCleaners.ps1')) {
        throw 'Legacy merged loader was copied into the package.'
    }

    $ExternalHelp = "<#{0}.EXTERNALHELP {1}-help.xml{0}#>" -f [Environment]::NewLine, $script:ModuleName
    foreach ($PublicFile in @(Get-ChildItem -LiteralPath (Join-Path -Path $script:ArtifactsPath -ChildPath 'Public') -Filter '*.ps1' -File)) {
        $Content = Get-Content -LiteralPath $PublicFile.FullName -Raw
        $Updated = $Content -replace '(?ms)\<\#.*?\.SYNOPSIS.*?#\>', $ExternalHelp
        Set-Content -LiteralPath $PublicFile.FullName -Value $Updated -Encoding UTF8
    }
}

Add-BuildTask IntegrationTest {
    if (-not (Test-Path -LiteralPath $script:IntegrationTestsPath)) {
        throw 'Integration test directory is required for the package gate.'
    }
    $LoadedPester = Get-Module -Name Pester
    if ($null -eq $LoadedPester) {
        Import-Module -Name Pester -MinimumVersion $script:MinPesterVersion -MaximumVersion $script:MaxPesterVersion -ErrorAction Stop
    } elseif ($LoadedPester.Version -lt $script:MinPesterVersion -or $LoadedPester.Version -gt $script:MaxPesterVersion) {
        throw "Loaded Pester version '$($LoadedPester.Version)' is outside the supported build range."
    }
    $Configuration = New-PesterConfiguration
    $Configuration.Run.Path = $script:IntegrationTestsPath
    $Configuration.Run.PassThru = $true
    $Configuration.Run.Exit = $false
    $Configuration.TestResult.Enabled = $true
    $Configuration.TestResult.OutputPath = Join-Path -Path $script:ReportsPath -ChildPath 'IntegrationTests.xml'
    $Configuration.TestResult.OutputFormat = $script:testOutputFormat
    $Configuration.Output.Verbosity = 'Detailed'
    $Result = Invoke-Pester -Configuration $Configuration
    Write-TestSummary -Result $Result -Path (Join-Path -Path $script:ReportsPath -ChildPath 'IntegrationTestSummary.json') -TestKind 'Integration'
    Assert-TestResultPassed -Result $Result -ReportPath (Join-Path -Path $script:ReportsPath -ChildPath 'IntegrationTests.xml') -TestKind 'Integration'
}

Add-BuildTask Archive {
    $ZipName = '{0}_{1}.zip' -f $script:ModuleName, $script:ModuleVersion
    $ZipPath = Join-Path -Path $script:ArchivePath -ChildPath $ZipName
    if (Test-Path -LiteralPath $ZipPath) {
        throw "Refusing to overwrite an existing archive: $ZipPath"
    }
    New-DeterministicZipArchive -SourcePath $script:ArtifactsPath -DestinationPath $ZipPath

    $FileRecords = @()
    foreach ($File in @(Get-ChildItem -LiteralPath $script:ArtifactsPath -File -Recurse -Force | Sort-Object FullName)) {
        $FileRecords += [ordered]@{
            Path   = Get-RelativeArtifactPath -Path $File.FullName -Root $script:ArtifactsPath
            Length = $File.Length
            SHA256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $ManifestPath = Join-Path -Path $script:ArchivePath -ChildPath ('{0}_{1}.manifest.json' -f $script:ModuleName, $script:ModuleVersion)
    [ordered]@{
        ModuleName    = $script:ModuleName
        ModuleVersion = $script:ModuleVersion
        Commit        = Get-BuildCommitId
        Runtime       = [ordered]@{
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            PSEdition          = $PSVersionTable.PSEdition
        }
        Archive       = $ZipName
        ArchiveSHA256 = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Files         = $FileRecords
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
    $HashPath = "$ZipPath.sha256"
    $ArchiveHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$ArchiveHash *$ZipName" | Set-Content -LiteralPath $HashPath -Encoding ASCII
}
