<#
.SYNOPSIS
    Publish TheCleaners to the PowerShell Gallery.

.DESCRIPTION
    Publishes the module from the source module path to the PowerShell Gallery
    using an API key supplied by the workflow environment.

.PARAMETER PSGalleryApiKey
    The PowerShell Gallery API key used by Publish-Module.

.EXAMPLE
    ./.github/workflows/publish.ps1 -PSGalleryApiKey $env:PSGALLERY_API_KEY
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $PSGalleryApiKey
)

$ErrorActionPreference = 'Stop'
$ModulePath = './src/TheCleaners'

Publish-Module -Path $ModulePath -NuGetApiKey $PSGalleryApiKey -ErrorAction Stop
