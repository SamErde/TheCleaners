# Safety and confirmation

This branch is prerelease work. No command is newly certified production-ready by the 1.0 plan. Use isolated test systems until the applicable acceptance gates pass.

## Temporary files

`Clear-CurrentUserTemp` uses `[System.IO.Path]::GetTempPath()` on Windows. `Clear-WindowsTemp` uses `SystemRoot\Temp`. Both remove files whose `LastWriteTimeUtc` is **at or before** one cutoff captured for the invocation. The default is 30 days; filename extension does not restrict temporary-file candidates.

The functions discover candidates before deletion, skip reparse points before traversing directories, and validate literal paths. Immediately before removal, they recheck ancestry, item type, and last-write time. Candidate deletion opens the file itself with a Windows handle requesting `DELETE` and `FILE_READ_ATTRIBUTES`, without `FILE_READ_DATA`, reads the native identity and final timestamp from that handle, and marks that same handle for deletion. The PowerShell provider is not used to delete a candidate. A path that disappears is counted as skipped, and a path replaced by a directory or another identity is never removed or counted as a successful file deletion. Path checks are still not a complete defense against every hostile filesystem race, so additional concurrent-change and platform acceptance cases remain in the release plan.

Retention and logical byte counts use metadata observed from the deletion handle. A same-object content change before that observation is permitted if the observed timestamp remains old; a now-recent file is skipped. Read-only sharing blocks ordinary data writers and renames, but Windows can still permit an attribute-only timestamp update. The timestamp check and deletion are not atomic, and a later timestamp change does not revoke an earlier eligibility decision. See the [retention and deletion-handle contract](issue-30-retention-handle.md) for the tested scenarios and threat-model limits.

Cleanup roots and literal filesystem paths must use fully qualified Windows syntax: a drive-qualified path such as `C:\Temp` or a UNC path with both server and share components. Drive-relative (`C:Temp`), root-relative (`\Temp`), ordinary relative, provider-qualified, and device paths are rejected before filesystem resolution. Extended-length drive and UNC syntax is accepted by the parser and then depends on the Windows provider and long-path policy; device namespaces remain rejected.

By default, no directories are removed. `-RemoveEmptyDirectory` permits only directories emptied by this invocation and now-empty ancestors. It does not authorize the cleanup root, an unrelated pre-existing empty branch, or a directory containing a retained file. Pruning is deepest-first. Empty directories are deleted using a non-recursive API inside the owning command's approved `ShouldProcess` branch; a file appearing after the emptiness check causes deletion to fail, not become recursive.

The plan retains directory handles through pruning, preventing an ordinary rename/replacement of the touched directory while those handles remain open. Pruning also compares native volume/file identity, so a different directory at the same path is not authorized by path equality alone. The [directory-identity regression evidence](issue-28-directory-identity.md) separately records production handle-lock tests and an injected handle-loss case that verifies this defensive identity check.

```powershell
Clear-CurrentUserTemp -Days 30 -RemoveEmptyDirectory -WhatIf -PassThru -Verbose
Clear-WindowsTemp -Days 60 -WhatIf -PassThru
```

`-WhatIf` reports the batch proposal and returns zero removals. `-Verbose` identifies candidate paths. `-Confirm` asks for approval of the discovered file/directory plan at the root. `-Confirm:$false` suppresses that confirmation, not errors or safety checks. These commands do not currently need a separate `ShouldContinue` or `-Force` switch.

An enumeration failure reports an error, makes no deletions, and returns `Status = DiscoveryFailed` with unknown candidate counts under `-PassThru`. Individual removal failures use the error stream and continue by default; `-ErrorAction Stop` terminates. `PrivilegeStatus` reports whether the process is elevated, but does not grant access or predict a per-file ACL outcome. System-owned files generally require an elevated session. Actual client/server elevation acceptance remains a release gate.

## Result summaries

`-PassThru` returns `TheCleaners.CleanupResult` objects. The complete shared field list and stable error IDs are in [1.0 command contracts](command-contracts.md).

Statuses are `NoCandidates`, `WhatIf`, `Declined`, `DiscoveryFailed`, `Completed`, `CompletedWithSkips`, or `PartialFailure`. An empty candidate set is `NoCandidates`, including in a WhatIf invocation. `BytesReclaimed` sums logical file lengths for successful removals; compressed files, hard links, and filesystem behavior mean it is not a measured physical free-space delta. Without `-PassThru`, normal success does not return a summary object.

## IIS preview

```powershell
Clear-OldIISLog -Days 60 -WhatIf -PassThru
```

IIS is structurally preview-only until its root discovery, exact format allowlist, and server acceptance gates pass. Explicit `-WhatIf` is mandatory; omission, `-WhatIf:$false`, or an ambient preference without the explicit switch fails before discovery. `Clean-IISLog` has the same lock. There is no `-Force`, `-EnableRemoval`, or `-AllowRemoval` bypass.

The command discovers site roots through WebAdministration when available; otherwise, it considers the default and registry-configured roots. It requires each root to be a directory, skips reparse points, and applies format-specific filename allowlists. The discovery contract remains experimental until the product/version matrix and server lab gates pass. The command contains no deletion implementation and no generic deletion wrapper remains in the module.

With `-PassThru`, IIS returns one summary per successfully enumerated existing root, with `DiscoveryStatus = Experimental`, `Status = WhatIf`, `CandidatePaths`, and zero removal/byte counts. Missing or non-directory roots are noted in verbose output; discovery failures use the error stream rather than returning a successful empty summary.

## Exchange preview

```powershell
Clear-OldExchangeLog -Days 60 -WhatIf -PassThru
```

Exchange has **no deletion implementation** in this work. Explicit `-WhatIf` is mandatory. Omission, `-WhatIf:$false`, or an ambient preference without the explicit switch fails before registry discovery. Neither `-Confirm:$false` nor the legacy alias bypasses the lock. `-Force`, `-EnableRemoval`, and `-AllowRemoval` are not supported.

Preview reads the Exchange v15 installation registry location and scans existing `Logging`, `Bin\Search\Ceres\Diagnostics\ETLTraces`, `Bin\Search\Ceres\Diagnostics\Logs`, and `TransportRoles\Logs\MessageTracking` roots with product-specific filename allowlists. Installation and log roots must resolve to directories. Database and transaction-log paths returned by Exchange management discovery are protected. The product/version matrix and lab validation remain open. The preview never calls IIS cleanup.

With `-PassThru`, Exchange returns one summary per successfully enumerated existing root, with `DiscoveryStatus = Experimental`, `Status = WhatIf`, `CandidatePaths`, and zero removal/byte counts. Missing or non-directory roots are skipped; enumeration failures produce errors rather than successful empty summaries. A later minor release may introduce per-invocation authorization after lab validation; there is no one-time persistent activation.

## Other commands

`Get-StaleUserProfile` does not delete profiles. `Get-TheCleaners` lists maturity metadata and reports both IIS and Exchange as `PreviewOnly`. Module import itself is quiet.

When `Get-StaleUserProfile -IncludeSize` enumerates a profile, it retains identity-checked handles for the profile ancestors through the size operation. Each queued child directory carries its discovery-time identity and is opened and revalidated when it is traversed; where the current token permits it, the active directory uses a native handle with delete and read-attribute access and without delete sharing while the provider reads its children. Ancestors fall back to identity-only handles when DELETE access is unavailable, and a failed or changed identity reports `SizeStatus = Unavailable` rather than returning a partial size. The profile command remains inventory-only and never marks a handle for deletion.
