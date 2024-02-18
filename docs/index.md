# TheCleaners

## Synopsis

A module to help automate the cleanup of old log file and temp files on your systems.

## Description

This module includes a number of functions to help automate the cleanup of IIS logs, Exchange Server logs, temp files,
and old profiles from your systems.

## Why

This module exists because there is no great "out of the box" way to keep IIS and Exchange logs, temp files, and old
profiles under control. As a systems administrator, I have spent far too many hours responding to low disk alerts and
manually cleaning up these locations. The Cleaners will come in and clean up all of those loose ends for you!

## Getting Started

### Prerequisites

The WebAdministration PowerShell module is ideally present on any systems that you want to clear up IIS log files.
Without it, we can only make our best guess as to the location of the IIS log files based on their default location.

### Installation

Download the contents of the /src/TheCleaners folder from this repository. Open PowerShell run:

```powershell
Set-Location -Path <FOLDER CONTAINING THESE FILES>
Import-Module .\TheCleaners.psd1
Clear-OldIISLogs.ps1
```

This will soon be packaged as a module that can be downloaded from the PowerShell Gallery!

```powershell
# Install-Module TheCleaners

```

### Quick start

#### Example1

```powershell
Clear-OldIISLogs
```

## Author

Sam Erde
[@SamErde on Twitter/X](https://twitter.com/SamErde)
[@SamErde on Linktree](https://linktr.ee/SamErde)
