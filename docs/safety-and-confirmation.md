# Safety and confirmation

This branch is prerelease work. No command is newly certified production-ready by the 1.0 plan. Use isolated test systems until the applicable acceptance gates pass.

## Temporary files

`Clear-CurrentUserTemp` uses `[System.IO.Path]::GetTempPath()` on Windows. `Clear-WindowsTemp` uses `SystemRoot\Temp`. Both remove files whose `LastWriteTimeUtc` is **at or before** one cutoff captured for the invocation. The default is 30 days; filename extension does not restrict temporary-file candidates.

The functions discover candidates before deletion, skip reparse points before traversing directories, and validate literal paths. Immediately before removal, they recheck ancestry, item type, and last-write time. Path-based validation is not an atomic defense against a hostile process concurrently replacing paths. Stronger OS-root/elevation preflight and additional concurrent-change cases remain in the release plan.

By default, no directories are removed. `-RemoveEmptyDirectory` permits only directories emptied by this invocation and now-empty ancestors. It does not authorize the cleanup root, an unrelated pre-existing empty branch, or a directory containing a retained file. Pruning is deepest-first. Empty directories are deleted using a non-recursive API inside the owning command's approved `ShouldProcess` branch; a file appearing after the emptiness check causes deletion to fail, not become recursive.

```powershell
Clear-CurrentUserTemp -Days 30 -RemoveEmptyDirectory -WhatIf -PassThru -Verbose
Clear-WindowsTemp -Days 60 -WhatIf -PassThru
```

`-WhatIf` reports the batch proposal and returns zero removals. `-Verbose` identifies candidate paths. `-Confirm` asks for approval of the discovered file/directory plan at the root. `-Confirm:$false` suppresses that confirmation, not errors or safety checks. These commands do not currently need a separate `ShouldContinue` or `-Force` switch.

An enumeration failure reports an error, makes no deletions, and returns `Status = DiscoveryFailed` with unknown candidate counts under `-PassThru`. Individual removal failures use the error stream and continue by default; `-ErrorAction Stop` terminates. System-owned files generally require an elevated session. A dedicated elevation preflight is still tracked, not yet implemented.

## Result summaries

`-PassThru` returns `TheCleaners.CleanupResult` objects. Temp results include `Command`, `RootPath`, `CutoffUtc`, `FileCandidateCount`, `FilesRemoved`, `FileFailureCount`, `FilesSkipped`, `DirectoryCandidateCount`, `DirectoriesRemoved`, `DirectoryFailureCount`, `DirectoriesSkipped`, `BytesReclaimed`, and `Status`.

Statuses are `NoCandidates`, `WhatIf`, `Declined`, `DiscoveryFailed`, `Completed`, `CompletedWithSkips`, or `PartialFailure`. An empty candidate set is `NoCandidates`, including in a WhatIf invocation. `BytesReclaimed` sums logical file lengths for successful removals; compressed files, hard links, and filesystem behavior mean it is not a measured physical free-space delta. Without `-PassThru`, normal success does not return a summary object.

## Exchange preview

```powershell
Clear-OldExchangeLog -Days 60 -WhatIf -PassThru
```

Exchange has **no deletion implementation** in this work. Explicit `-WhatIf` is mandatory. Omission, `-WhatIf:$false`, or an ambient preference without the explicit switch fails before registry discovery. Neither `-Confirm:$false` nor the legacy alias bypasses the lock. `-Force`, `-EnableRemoval`, and `-AllowRemoval` are not supported.

Preview reads the Exchange v15 installation registry location and scans existing `Logging`, `Bin\Search\Ceres\Diagnostics\ETLTraces`, `Bin\Search\Ceres\Diagnostics\Logs`, and `TransportRoles\Logs\MessageTracking` roots for old `.log` files. This intentionally retains the initial limited discovery scope. It does **not** claim to cover ETL file types or prove that all candidates are safe to delete. Product-specific patterns and protected-location validation remain open. The preview never calls IIS cleanup.

With `-PassThru`, Exchange returns one summary per successfully enumerated existing root, with `DiscoveryStatus = Experimental`, `Status = WhatIf`, `CandidatePaths`, and zero removal/byte counts. Missing roots are noted in verbose output; enumeration failures produce errors rather than successful empty summaries. A later minor release may introduce per-invocation authorization after lab validation; there is no one-time persistent activation.

## Other commands

IIS remains prerelease and still requires its planned path/format hardening. `Get-StaleUserProfile` does not delete profiles. `Get-TheCleaners` lists maturity metadata and never starts cleanup. Module import itself is quiet.
