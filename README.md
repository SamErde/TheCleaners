# The Cleaners

<!-- badges-start -->
[![GitHub stars](https://img.shields.io/github/stars/samerde/TheCleaners?cacheSeconds=3600)](https://github.com/samerde/TheCleaners/stargazers/)
![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/TheCleaners?include_prereleases)
![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/TheCleaners)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](https://makeapullrequest.com)
[![GitHub contributors](https://img.shields.io/github/contributors/samerde/TheCleaners.svg)](https://github.com/samerde/TheCleaners/graphs/contributors/)

![GitHub top language](https://img.shields.io/github/languages/top/SamErde/TheCleaners)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/ae92f0d929de494690e712b68fb3b52c)](https://app.codacy.com/gh/SamErde/TheCleaners/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/SamErde/TheCleaners/.github%2Fworkflows%2FBuild%20Module.yml)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/SamErde/TheCleaners/.github%2Fworkflows%2FDeploy%20MkDocs.yml?label=MkDocs)
<!-- badges-end -->

<img src="https://raw.githubusercontent.com/SamErde/TheCleaners/main/media/TheCleaners-CodeHoodieNoBG.png" alt="The Cleaners logo on a code hoodie" width="400" />

## Purpose

A PowerShell module for Windows temporary-file maintenance, IIS and Exchange log discovery, and stale-profile discovery. IIS and Exchange are **preview-only**, with no deletion implementation in the 1.0 preparation work.

**The published `0.0.15-beta` package is a prerelease, not a production-ready 1.0 release.** This branch continues 1.0 preparation and may contain documentation changes made after the packaged source. Follow the [implementation ledger](docs/release-plan-1.0.md) and [migration guide](docs/migration-to-1.0.md).

## Requirements

Windows PowerShell 5.1 is the minimum. The 1.0 policy also includes Microsoft-supported PowerShell 7 releases on Windows. Linux and macOS are not supported. Product-specific Windows/IIS/Exchange acceptance remains tracked in the [support matrix](docs/support-matrix.md).

## Installation and development

Install the published `0.0.15-beta` prerelease from [PowerShell Gallery](https://www.powershellgallery.com/packages/TheCleaners/0.0.15-beta):

```powershell
Install-Module -Name TheCleaners -Repository PSGallery -RequiredVersion '0.0.15-beta' -AllowPrerelease
```

To evaluate a checked-out development branch instead, import that source explicitly in an isolated test environment:

```powershell
Import-Module -Name .\src\TheCleaners\TheCleaners.psd1 -Force
Get-TheCleaners -NoLogo
```

Import is quiet. `Start-Cleaning` remains a deprecated alias for `Get-TheCleaners`; neither command starts cleanup.

## Preview first

```powershell
Clear-CurrentUserTemp -Days 30 -WhatIf -PassThru
Clear-WindowsTemp -Days 30 -RemoveEmptyDirectory -WhatIf -PassThru
Clear-OldIISLog -Days 60 -WhatIf -PassThru
Clear-OldExchangeLog -Days 60 -WhatIf -PassThru
```

The temp cleaners leave directories untouched unless `-RemoveEmptyDirectory` is explicit. Even then, they only prune directories emptied by that invocation and their now-empty ancestors. They preserve roots, unrelated empty branches, recent files, and reparse points. Removal-enabled temp runs use standard `-Confirm` behavior; read the [safety contract](docs/safety-and-confirmation.md) before executing them.

IIS and Exchange require explicit `-WhatIf` and cannot remove anything. Their discovered candidates are experimental, not proven deletion allowlists. `-AllowRemoval` is only a provisional later-release design for Exchange, not an available parameter.
