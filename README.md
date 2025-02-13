<!-- markdownlint-disable first-line-heading -->
<!-- markdownlint-disable blanks-around-headings -->
<!-- markdownlint-disable no-inline-html -->
<!-- markdownlint-disable MD024 -->
# The Cleaners

<!-- badges-start -->
[![GitHub stars](https://img.shields.io/github/stars/samerde/TheCleaners?cacheSeconds=3600)](https://github.com/samerde/TheCleaners/stargazers/)
![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/TheCleaners?include_prereleases)
![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/TheCleaners)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
[![GitHub contributors](https://img.shields.io/github/contributors/samerde/TheCleaners.svg)](https://github.com/samerde/TheCleaners/graphs/contributors/)

![GitHub top language](https://img.shields.io/github/languages/top/SamErde/TheCleaners)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/ae92f0d929de494690e712b68fb3b52c)](https://app.codacy.com/gh/SamErde/TheCleaners/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/SamErde/TheCleaners/.github%2Fworkflows%2FBuild%20Module.yml)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/SamErde/TheCleaners/.github%2Fworkflows%2FDeploy%20MkDocs.yml?label=MkDocs)
<!-- badges-end -->

<img src="https://raw.githubusercontent.com/SamErde/TheCleaners/main/media/TheCleaners-CodeHoodieNoBG.png" alt="A logo for The Cleaners that shows an illustration of a 'hacker' wearing a hoodie and holding a box of cleaning supplies. There is a PowerShell logo on the box. Where the hacker's face should be, there is just a black console with code on it." width="400" />

## Synopsis

A module to help automate the cleanup of old log files and temp files on your systems.

## Description

The Cleaners do the dirty work in your servers for you. We take care of temp files, IIS logs, Exchange Server logs, and more!

## Why

- For all those hours spent manually clearing old IIS logs, Exchange logs, and temp files when a server disk gets low on space.
- For those teammates who get woken up at night while on call because a disk hit 90% full.
- For the fun of writing something useful in PowerShell that will hopefully make somebody's day easier!

## Getting Started

### Prerequisites

PowerShell or Windows PowerShell 5.1

There are no other strict dependencies, but the following can make things a little easier:

- IIS: WebManagement Module
- Exchange: Exchange Management Tools

### Installation

```powershell
# How to install TheCleaners
Install-Module -Name TheCleaners -AllowPrerelease
```

### Quick Start

#### Example1

```powershell
# See what jobs TheCleaners can do for you.
Start-Cleaning
```

These docs can also be found at [TheCleaners.ReadTheDocs.io/](https://thecleaners.readthedocs.io/).
