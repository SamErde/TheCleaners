# 1.0 command contracts

The release plan is the authority for maturity. Exported does not mean stable. Every cleanup summary uses the `TheCleaners.CleanupResult` contract version `1.0`; `Get-StaleUserProfile` uses its separate `TheCleaners.StaleUserProfile` contract.

## Cleanup result

`-PassThru` returns these fields for temp, IIS-preview, and Exchange-preview commands:

| Field | Meaning |
| --- | --- |
| `Command`, `ContractVersion` | Command name and result contract version. |
| `RootPath`, `CutoffUtc` | Validated root and the inclusive UTC retention boundary. |
| `DiscoveryStatus`, `DiscoverySource`, `DisplayName`, `ProductVersion` | Whether discovery is validated, experimental, or failed; how it was obtained; and product/root display metadata when available. |
| `ProtectionStatus`, `ProtectionPathCount`, `ProtectionPaths` | Protected-path validation state, count, and exact paths used by product-specific preview validation. |
| `PrivilegeStatus` | Informational Windows elevation state; it never grants access. |
| `CandidatePaths` | File paths discovered in the proposal. |
| `FileCandidateCount`, `DirectoryCandidateCount` | Discovery totals. They are null when discovery failed. |
| `FilesRemoved`, `DirectoriesRemoved` | Successful mutations only. Preview counts are not removals. |
| `FileFailureCount`, `DirectoryFailureCount`, `FilesSkipped`, `DirectoriesSkipped` | Reconciled mutation outcomes. |
| `BytesReclaimed` | Logical lengths of files successfully removed, not physical free-space measurement. |
| `DiscoveryErrorCount`, `ErrorIds` | Structured failure count and stable TheCleaners error IDs. |
| `Status` | `NoCandidates`, `WhatIf`, `Declined`, `Completed`, `CompletedWithSkips`, `PartialFailure`, or `DiscoveryFailed`. |

An error ID is stable across PowerShell editions. The error record's exception and category retain the operating-system detail. Current IDs include:

| ID | Applies to |
| --- | --- |
| `TempWindowsRequired`, `TempRootValidationFailed`, `TempDiscoveryFailed`, `TempRootChanged` | Temp root and discovery gates. |
| `TempFileRemovalFailed`, `TempDirectoryRemovalFailed` | Per-object temp mutation failures. |
| `IISCleanupPreviewOnly`, `IISWindowsRequired`, `IISRegistryDiscoveryFailed`, `IISFtpDiscoveryFailed`, `IISLogFormatUnavailable`, `IISLocalTimeRolloverUnavailable`, `IISServiceMetadataUnavailable`, `IISProtectedRoot`, `IISDiscoveryFailed`, `IISDiscoveryUnavailable` | IIS preview, metadata, and discovery gates. |
| `ExchangeCleanupPreviewOnly`, `ExchangeWindowsRequired`, `ExchangeRegistryDiscoveryFailed`, `ExchangeInstallRootValidationFailed`, `ExchangeProtectedPathDiscoveryFailed`, `ExchangeDiscoveryFailed`, `ExchangeDiscoveryUnavailable` | Exchange preview and discovery gates. |
| `ProfileWindowsRequired`, `ProfileQueryFailed`, `ProfileSizeUnavailable` | Stale-profile discovery and optional-size gates. |

Discovery failure is never represented as an empty successful result. Under continuing error handling, a partial result is explicitly marked `DiscoveryFailed`; with `-ErrorAction Stop`, the stable error record terminates the command.

## Stale-profile result

`Get-StaleUserProfile` is read-only and returns `TheCleaners.StaleUserProfile` objects with these fields:

| Field | Meaning |
| --- | --- |
| `ContractVersion` | Result schema version `1.0`. |
| `SID`, `Account`, `AccountResolutionStatus` | Profile SID, best-effort translated account, and `Resolved`/`Unresolved` state. |
| `LocalPath`, `PathExists` | Profile path and whether it currently exists as a directory. |
| `LastUseTime`, `LastUseTimeUtc`, `DateStatus` | Local/UTC last-use values and `Known`/`Unknown` state. |
| `AgeDays`, `IsStale` | Whole-day age for known dates and the inclusive cutoff result. Unknown dates are never marked stale. |
| `Loaded`, `Special`, `IsDefault`, `IsSystem`, `IsService` | Inventory and exclusion metadata. Loaded, special, default, system, service, virtual-service, and IIS application-pool profiles are not returned. |
| `SizeBytes`, `SizeStatus` | Optional logical size and `NotRequested`, `Available`, or `Unavailable` state. Size failure is explicit and never enables deletion. |

## Mutation contract

The temp commands own their mutations. They discover under an approved root, capture native volume/file identities, and reopen each candidate with a Windows handle requesting `DELETE` and `FILE_READ_ATTRIBUTES`, without `FILE_READ_DATA`. The same handle is identity-checked and marked for deletion; the PowerShell provider is not used to delete candidates. Directory pruning is non-recursive, opt-in through `-RemoveEmptyDirectory`, deepest-first, and limited to directories emptied by that invocation. Reparse points, roots, unrelated branches, hard-link targets, replacements, and paths outside the root are preserved.

Retention and removed-byte accounting use the current metadata observed from the deletion handle. Discovery establishes identity and candidacy, not an immutable content snapshot. A same-object file may be removed after a content/length change if its observed last-write time still meets the cutoff. Read-only sharing blocks data writers and renames but does not block every attribute-only timestamp update; metadata validation and disposition are not atomic. The [issue #30 contract and fixtures](issue-30-retention-handle.md) define these limits.

The implementation follows the safety intent tracked in [issue #28](https://github.com/SamErde/TheCleaners/issues/28) and [issue #29](https://github.com/SamErde/TheCleaners/issues/29). Broader NTFS/ReFS and Windows client/server acceptance still requires disposable Windows environments with recorded filesystem and runtime evidence; deterministic issue fixtures do not replace those gates.

## Preview contract

IIS and Exchange require an explicit `-WhatIf` before discovery. They have no deletion implementation, no removal bypass, and no persistent activation. A successful preview uses `DiscoveryStatus = Experimental`, `Status = WhatIf`, and zero mutation counts. A registry, root, protection, provider, or traversal failure uses `DiscoveryStatus = Failed`, `Status = DiscoveryFailed`, null candidate totals, and stable `ErrorIds`; it is never represented as an empty successful preview. A later Exchange minor release may revisit a per-invocation opt-in only after the product-specific gates pass.
