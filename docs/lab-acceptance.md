# Windows lab acceptance

These checks are a protocol for a disposable Windows client/server lab. They are not proof of acceptance and must not be run against a user's real temp directory, IIS installation, Exchange installation, or production data. Record the exact commit, OS build, filesystem type, PowerShell version, elevation state, command line, before/after listing, result object, error stream, and service-health output.

## Temp cleaners

| Fixture | Expected result |
| --- | --- |
| Old and recent legal filenames that exercise literal allowlist metacharacters, such as `[literal].tmp` | Only old files at or before one UTC cutoff are proposed/removed; recent files remain, and names are treated literally rather than as provider wildcards. |
| Candidate replaced by a directory or a different file identity | Candidate is skipped; the replacement is never deleted or counted as a file removal. |
| Candidate disappears, is locked, or denies the requested operation | It is skipped or reports `TempFileRemovalFailed`; no reclaimed bytes are claimed. |
| Hard link with a name outside the approved root | Only the approved name is removed; the outside hard link remains. Logical bytes are reported, not physical free space. |
| Junction, symbolic link, or other reparse point under the root | The reparse point is not traversed or removed. |
| Empty directory created before the run versus emptied by the run | Pre-existing unrelated empty branches remain; only identity-checked directories emptied by the invocation may be removed. |
| Directory path recreated between discovery and pruning | The new directory identity remains; the old plan cannot remove it. |
| Root, prefix-confusable sibling, root-relative, device, and extended-length paths | Root containment is strict; unsupported/device forms fail closed. Extended-length forms are accepted only when the Windows provider and long-path policy can resolve them. |
| ACL fixture that denies file-content read but grants the required delete operation | The native handle path is exercised without `FILE_READ_DATA`; the ACL and exact access mask are recorded. |
| Non-elevated and elevated sessions | `PrivilegeStatus` is recorded; access failures remain explicit and elevation is never inferred from an environment variable. |
| NTFS and ReFS | Record filesystem type and `FILE_ID_INFO` behavior. A lab result is required before claiming cross-filesystem acceptance. |

Run `-WhatIf` first and verify that files, directories, preferences, registry, processes, and module state are unchanged. Then run a fixture-only removal with `-Confirm:$false` after reviewing the candidate list. Do not substitute the real system temp root for a fixture.

Use the repository ACL harness only with an already-created disposable parent:

```powershell
.\lab\Invoke-TheCleanersAclFixture.ps1 -FixtureParent C:\Disposable\TheCleanersLab -Confirm:$false
```

The exact PR #31 hosted PS5.1 run used its isolated runner temp child and recorded two candidates (`old-readable.tmp` and `old-delete-without-read.tmp`), `2 -> 0`, `FilesRemoved = 2`, `BytesReclaimed = 6`, no failures/skips/error IDs, NTFS, elevation, and `Acceptance = true`. That fixture is not complete Windows client/server, broader elevated/non-elevated, ReFS, or real system-root acceptance.

## IIS and Exchange preview gates

Until the release-plan gates pass, these commands remain structurally preview-only. Lab work may validate discovery and service health, but must not add a deletion call or treat a preview candidate list as authorization.

| Product | Required evidence before any later removal design |
| --- | --- |
| IIS | WebAdministration availability/missing-product behavior; Web/FTP/custom format allowlists; expanded and deduplicated default/custom roots; protected `inetsrv`/configuration/history paths; before/after candidate inventory; IIS service health. |
| Exchange | Exact v15 product/build and supported path matrix; MessageTracking/ETL/diagnostic patterns; mailbox database and transaction-log exclusions including custom paths; before/after candidate inventory; Exchange service health. |

No 1.0 release gate is satisfied by mocked fixtures alone. Attach the lab evidence to the packet/PR and keep the preview lock until a maintainer approves the product-specific transition.

Run the read-only product probe only in a disposable product lab after recording the exact commit and product build:

```powershell
.\lab\Invoke-TheCleanersProductPreviewLab.ps1 -Confirm:$false
```

The exact merged commit has no IIS or Exchange product/build lab record. Do not copy the earlier workstation absence probe forward as acceptance or exact-commit evidence.
