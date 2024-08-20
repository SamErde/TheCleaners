# The Cleaners

## Synopsis

A module to help automate the cleanup of old log files and temp files on your systems.

## Description

The Cleaners do the dirty work in your servers for you. We take care of temp files, IIS logs, Exchange Server logs, and more!

## Why

- For all those hours spent manually clearing old IIS logs, Exchange logs, and temp files when a server disk gets low on space.  
- For those teammates who get woken up at night while on call because a disk hit 90% full.  
- For the fun of writing something useful in PowerShell that will hopefully make somebody's day easier!

## Getting Started

Note: These docs can also be found at [TheCleaners.ReadTheDocs.io/](https://thecleaners.readthedocs.io/)!

### Prerequisites

<!-- list any prerequisites -->
- PowerShell or Windows PowerShell 5.1

### Installation

```powershell
# How to install TheCleaners
Install-Module -Name 'TheCleaners' -Scope CurrentUser

```

### Quick start

#### Example1

```powershell
Start-Cleaning

```

## Author

Sam Erde
Twitter: [@SamErde](https://twitter.com/SamErde)

