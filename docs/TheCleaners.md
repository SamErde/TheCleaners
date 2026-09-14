---
Module Name: TheCleaners
Module Guid: 96512386-bbd2-4e95-badd-5d175310bace
Download Help Link: NA
Help Version: 0.0.15
Locale: en-US
---

# TheCleaners Module

## Description

TheCleaners provides Windows temporary-file maintenance, read-only IIS and Exchange log previews, and stale-profile discovery. This is unreleased 1.0 preparation work; consult each command's maturity metadata and support gates.

## TheCleaners commands

### [Clear-CurrentUserTemp](Clear-CurrentUserTemp.md)

Remove old files from the current user's Windows temporary directory. Empty-directory pruning is opt-in.

### [Clear-OldExchangeLog](Clear-OldExchangeLog.md)

Preview experimental Exchange log candidates. Explicit `-WhatIf` is required, and removal is unavailable.

### [Clear-OldIISLog](Clear-OldIISLog.md)

Preview experimental IIS log candidates. Explicit `-WhatIf` is required, and removal is unavailable.

### [Clear-WindowsTemp](Clear-WindowsTemp.md)

Remove old files from the Windows temporary directory. Empty-directory pruning is opt-in.

### [Get-StaleUserProfile](Get-StaleUserProfile.md)

Find old, unloaded Windows user profiles without deleting them.

### [Get-TheCleaners](Get-TheCleaners.md)

Return typed command and maturity metadata. `Start-Cleaning` remains a deprecated compatibility alias through 1.x.
