# TC-008 uncovered-command risk review

Reviewed September 17, 2026 against `3cb0293487c6f08e7fdea6bff30e29cf1169d766` (PR #34 merge). The bounded source review is complete; no runtime defect was confirmed and no runtime, API, package, workflow, or release-metadata change is made. The added regressions require their own exact-head and post-merge validation. This review does not close product, publication, or maintainer acceptance gates.

## Evidence and method

The source is the machine-readable `CodeCoverage.xml` from all three `pester-results-pwsh-*` artifacts in [post-merge build 35168283878](https://github.com/SamErde/TheCleaners/actions/runs/35168283878). Each lane reports `1,551/1,858` commands executed (`83.48%`), leaving 307 missed commands. The missed source/line/instruction tuples are identical across 7.4.20, 7.5.11, and 7.6.6. The 7.6.6 report SHA-256 is `e214ab0fe2179bb3978cbd4f801abc4e4959b03b6d84639b4f3047a49edf4ecd`.

The [baseline inventory](evidence/tc008-baseline-uncovered.csv) retains all 254 source lines containing those 307 missed instructions, including partially covered lines. Every row names the immutable source commit, path, line, missed/covered instructions on that line, risk, disposition, and rationale. Counts below sum missed instructions, not rows. Source line numbers always refer to that baseline; they are not recalculated against later commits.

Coverage measures instrumented PowerShell commands, not branch completeness. Native C# compiled from a here-string, isolated IIS runspaces, and child-process import/confirmation probes are not independently measured by this parent report. A missed line that has an explicit existing regression is recorded as such rather than presumed untested. These labels describe the review disposition, not a promise that every instruction in a group will become covered.

| Disposition | Missed commands | Decision |
| --- | ---: | --- |
| New focused regressions | 70 | Exercise observable preservation, failure, reconciliation, and handle-lifetime contracts. |
| New subprocess regressions | 13 | Extend real fixture-module FTP discovery; parent coverage still cannot measure child execution. |
| Existing subprocess coverage | 67 | Retain fresh-process confirmation and IIS dependency/discovery tests. |
| Existing contract coverage | 27 | Adjacent failure variants or explicit tests already establish the public contract; avoid tests of only error wording or internal bookkeeping. |
| Defensive guards needing lab variants | 70 | Native identity/sharing races or abandonment cases need controlled concurrency, kernel, filesystem, or product evidence. |
| Platform/product lab dependent | 33 | Actual OS roots, token states, provider/UNC behavior, and unsupported-host guards. |
| Defensive-only under current callers | 27 | Upstream validation or production plan construction excludes the input; do not fabricate unsafe impossible plans to increase coverage. |
| Total | 307 | Every baseline missed instruction is assigned. |

## Highest-risk decisions and new regressions

All development mutations stay in Pester `TestDrive` fixtures. Registry, product, profile inventory, and root discovery inputs are mocked. No cleaner is pointed at real temp, profile, IIS, or Exchange data.

| Area | Risk and disposition | Regression evidence |
| --- | --- | --- |
| Root identity after planning | An unexpected identity must abort before deletion and release retained handles, including on terminating errors. A different real fixture identity is injected into the completed plan; this does not claim to reproduce a physical root replacement while handles are held. | `TempFailureBranches.Tests.ps1`: continuing/Stop cases for both public temp commands. |
| Candidate identity and recency | A file replaced or made recent after real planning must survive. Moving the original file aside prevents file-ID reuse from weakening the replacement fixture. The old sibling is removed; both ancestors remain. | `TempFailureBranches.Tests.ps1`: recent/replacement cases for both commands; counts, bytes, content, and closed handles asserted. |
| Pruning failure | An access or I/O error after file removal must preserve directories, disqualify ancestors, report a stable category/target, and release handles on Stop. | `TempFailureBranches.Tests.ps1`: access, I/O, and Stop cases for both commands. |
| Queued child identity failure | Failed child identity capture must invalidate discovery rather than return a partial usable plan. A post-failure ancestor rename verifies handle release. | `TempFailureBranches.Tests.ps1`: both commands; unknown totals, stable error, preserved files, and the specific queued-identity error asserted. |
| Profile discovery and uncertainty | CIM failure must use the error stream and honor Stop. Invalid dates stay unknown, unresolved SIDs remain visible, and a file at a profile path cannot be reported as a valid size. | `ProfileFailureBranches.Tests.ps1`: three regressions with both continuing and terminating error assertions. |
| Nested preview traversal | Nested allowlisted files must be found without following junctions. Failure after partial discovery must discard candidate totals, preserve data, and honor Stop. | `PreviewTraversalBranches.Tests.ps1`: nested/junction and nested-failure cases for both preview commands. |
| Exchange metadata | Blank installation metadata must stop before filesystem discovery. Failed protection discovery must terminate even without PassThru. | `PreviewTraversalBranches.Tests.ps1`: two metadata regressions. |
| FTP metadata isolation | Missing/invalid numeric ID, missing configuration, missing format, or missing rollover metadata must produce a separate failed FTP result while valid web preview survives. Dependency registrations and caller preferences must be restored. | Five `FtpMetadata*` scenarios in `IISDiscoverySafety.Tests.ps1`; fixture WebAdministration module in a fresh process. |

These are 30 additional test cases: 16 temp, three profile, six preview traversal/metadata, and five FTP subprocess cases. Existing WhatIf, interactive confirmation, locked-file, hard-link, reparse, prefix-confusable path, import, API/help/drift, and exact-artifact tests remain intact.

## Non-findings and limits

- **No generic mutation fix:** public temp commands still own ShouldProcess and native same-handle deletion. Existing retired-wrapper and preview structural tests continue to enforce those boundaries.
- **Missing planned-directory handles:** the production planner requires retained handles before returning a pruning plan. Its fallback deletion branch is defensive; constructing an impossible plan solely to execute it would not improve the supported contract.
- **Protected Exchange descendants:** the whole log root is rejected when it overlaps a protected path. The later per-file protected-path check is additional defense, not evidence that nested protection is absent.
- **IIS metadata and duplicate roots:** existing fixture-module and registry tests cover equivalent paths, known metadata fallback, independent FTP failures, and unavailable formats. Some parent-report misses are subprocess artifacts. Product-specific combinations and complete candidate lists still require TC-005 labs; this review does not certify every site/format configuration.
- **Native identity and post-delete checks:** stable handles block ordinary rename/replacement; conservative post-delete existence checks avoid claiming successful removal while a path remains. Delete-pending handles, hostile timing, reparse changes, ReFS, and kernel-level failure variants remain TC-003/004 acceptance work. Coverage does not measure the native helper's C# branches.
- **Profile sizing:** existing fixtures exercise reparse ancestry and retained-directory identity. Complete fallback ACL/token combinations, concurrent native attribute changes, and Windows client/server sizing remain TC-007 acceptance work.
- **Defensive inputs:** blank path/provider and malformed private suffix inputs are rejected by upstream parameter/filename validation. Unsupported OS guards are outside the Windows support contract. No real machine roots or registry settings were changed to execute a fallback.
- **Import and artifacts:** all missed instructions in this baseline are in runtime functions; loader/package and build correctness also rely on separate import, integration, deterministic archive, and Python comparator checks. Parent runtime coverage is not their acceptance measure.

The review of the baseline gaps is complete without pursuing 100% coverage. Windows client/server, elevated/non-elevated, real-root, ReFS, adversarial/concurrency, IIS, Exchange, and profile product acceptance remain open. TC-008 still requires protected publication, published-version clean installation, and maintainer release acceptance. TC-009 retains canonical lowercase hosting, deployed-byte verification, final metadata/history, published installation, and authorization. See the [release ledger](release-plan-1.0.md) for all remaining gates. Zensical stays in issue #26.
