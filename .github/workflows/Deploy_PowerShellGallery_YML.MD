# WORKFLOW STILL IN DEVELOPMENT
name: Release
on:
  workflow_dispatch:
    inputs:
      ReleaseHeader:
        description: The header to be added to the release.
        required: false
jobs:
  Release:
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: pwsh
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Set Variables
        run: |
          "BARE_REPOSITORY=$($env:GITHUB_REPOSITORY.split("/")[1])" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
          $ModuleManifest = Get-ChildItem -Path $env:GITHUB_WORKSPACE -Include *.psm1 -Recurse
          "MODULE_PATH=$($ModuleManifest.FullName)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

      - name: Compress module for GitHub release
        id: compress
        run: |
          $CopySourcePath = Join-Path $env:GITHUB_WORKSPACE "src" "*"
          $CopyDestPath = Join-Path $env:GITHUB_WORKSPACE "out"
          Copy-Item -Path $CopySourcePath -Destination $CopyDestPath -Recurse
          $ZipSourcePath = Join-Path $CopyDestPath "*"
          $ZipDestPath = Join-Path $env:GITHUB_WORKSPACE "out" "$env:BARE_REPOSITORY-v$env:GITVERSION_SEMVER.zip"
          Compress-Archive -Path $ZipSourcePath -DestinationPath $ZipDestPath
          "ZipPath=$ZipDestPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append

      - name: Publish Module to Gallery
        uses: natescherer/publish-powershell-action@v1
        with:
          token: ${{ secrets.POWERSHELLGALLERY_THECLEANERS }}
          target: gallery
          path: out

      - name: Publish-Module
        id: publish
        run: |
          Publish-Module -Path ./src/Artifacts/ -NuGetApiKey ${{ secrets.POWERSHELLGALLERY_THECLEANERS }}
