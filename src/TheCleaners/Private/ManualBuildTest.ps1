$FunctionsToExport = @(
    'Clear-OldExchangeLogs',
    'Clear-OldIISLogs',
    'Clear-UserTemp',
    'Clear-WindowsTemp',
    'Get-StaleUserProfile',
    'Start-Cleaning'
)

$ModuleName = 'TheCleaners'
$BuildRoot = $PWD
$ArtifactsPath = Join-Path -Path $BuildRoot -ChildPath 'Artifacts'
$ModulePage = "$ArtifactsPath\docs\$($ModuleName).md"
$ModuleVersion = '0.0.5'

$markdownParams = @{
    Module         = $ModuleName
    OutputFolder   = "$ArtifactsPath\docs\"
    Force          = $true
    WithModulePage = $true
    Locale         = 'en-US'
    FwLink         = "NA"
    HelpVersion    = $ModuleVersion
}

Write-Build Gray '           Generating markdown files...'
New-MarkdownHelp @markdownParams -Verbose
Write-Build Gray '           ...Markdown generation completed.'

Write-Build Gray '           Replacing markdown elements...'
# Replace multi-line EXAMPLES
$OutputDir = "$script:ArtifactsPath\docs\"
$OutputDir | Get-ChildItem -File | ForEach-Object {
    # fix formatting in multiline examples
    $content = Get-Content $_.FullName -Raw
    $newContent = $content -replace '(## EXAMPLE [^`]+?```\r\n[^`\r\n]+?\r\n)(```\r\n\r\n)([^#]+?\r\n)(\r\n)([^#]+)(#)', '$1$3$2$4$5$6'
    if ($newContent -ne $content) {
        Set-Content -Path $_.FullName -Value $newContent -Force
    }
}
# Replace each missing element we need for a proper generic module page .md file
$ModulePageFileContent = Get-Content -Raw $ModulePage
$ModulePageFileContent = $ModulePageFileContent -replace '{{Manually Enter Description Here}}', $script:ModuleDescription
$FunctionsToExport | ForEach-Object {
    Write-Build DarkGray "             Updating definition for the following function: $($_)"
    $TextToReplace = "{{Manually Enter $($_) Description Here}}"
    $ReplacementText = (Get-Help -Detailed $_).Synopsis
    $ModulePageFileContent = $ModulePageFileContent -replace $TextToReplace, $ReplacementText
}

#Updated encoding parameter to resolve error
$ModulePageFileContent | Out-File $ModulePage -Force -Encoding ([System.Text.Encoding]::UTF8)
Write-Build Gray '           ...Markdown replacements complete.'
