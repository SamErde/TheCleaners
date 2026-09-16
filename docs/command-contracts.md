# 1.0 command contracts

The release plan is the authority for maturity. Exported does not mean stable. Every cleanup summary uses the `TheCleaners.CleanupResult` contract version `1.0`; `Get-StaleUserProfile` uses its separate `TheCleaners.StaleUserProfile` contract.

## Cleanup result

`-PassThru` returns these fields for temp, IIS-preview, and Exchange-preview commands:

| Field | Meaning |
| --- | --- |
| `Command`, `ContractVersion` | Command name and result contract version. |
| `RootPath`, `CutoffUtc` | Validated root and the inclusive UTC retention boundary. |
| `DiscoveryStatus`, `DiscoverySource`, `ProductVersion` | Whether discovery is validated, experimental, or failed, and how it was obtained. |
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
| `IISCleanupPreviewOnly`, `IISWindowsRequired`, `IISRegistryDiscoveryFailed`, `IISFtpDiscoveryFailed`, `IISProtectedRoot`, `IISDiscoveryFailed`, `IISDiscoveryUnavailable` | IIS preview and discovery gates. |
| `ExchangeCleanupPreviewOnly`, `ExchangeWindowsRequired`, `ExchangeRegistryDiscoveryFailed`, `ExchangeInstallRootValidationFailed`, `ExchangeProtectedPathDiscoveryFailed`, `ExchangeDiscoveryFailed`, `ExchangeDiscoveryUnavailable` | Exchange preview and discovery gates. |
| `ProfileWindowsRequired`, `ProfileQueryFailed`, `ProfileSizeUnavailable` | Stale-profile discovery and optional-size gates. |

Discovery failure is never represented as an empty successful result. Under continuing error handling, a partial result is explicitly marked `DiscoveryFailed`; with `-ErrorAction Stop`, the stable error record terminates the command.

## Mutation contract

The temp commands own their mutations. They discover under an approved root, capture native volume/file identities, and reopen each candidate with a Windows handle requesting `DELETE` without `FILE_READ_DATA`. The same handle is identity-checked and marked for deletion; the PowerShell provider is not used to delete candidates. Directory pruning is non-recursive, opt-in through `-RemoveEmptyDirectory`, deepest-first, and limited to directories emptied by that invocation. Reparse points, roots, unrelated branches, hard-link targets, replacements, and paths outside the root are preserved.

The implementation follows the safety intent tracked in [issue #28](https://github.com/SamErde/TheCleaners/issues/28) and [issue #29](https://github.com/SamErde/TheCleaners/issues/29). NTFS and ReFS acceptance still requires a disposable Windows lab with recorded filesystem and runtime evidence.

## Preview contract

IIS and Exchange require an explicit `-WhatIf` before discovery. They have no deletion implementation, no removal bypass, and no persistent activation. A successful preview uses `DiscoveryStatus = Experimental`, `Status = WhatIf`, and zero mutation counts. A registry, root, protection, provider, or traversal failure uses `DiscoveryStatus = Failed`, `Status = DiscoveryFailed`, null candidate totals, and stable `ErrorIds`; it is never represented as an empty successful preview. A later Exchange minor release may revisit a per-invocation opt-in only after the product-specific gates pass.
