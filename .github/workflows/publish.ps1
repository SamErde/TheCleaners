param  (
    [string] $PSGalleryApiKey
)

$ErrorActionPreference = 'stop'
$ModulePath = './src/TheCleaners'

Publish-Module -Path $ModulePath -NuGetApiKey $PSGalleryApiKey
