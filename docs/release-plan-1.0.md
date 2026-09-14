# TheCleaners 1.0 implementation plan

Updated September 14, 2026. Approved direction from the maintainer; implementation is underway in [PR #27](https://github.com/SamErde/TheCleaners/pull/27).

## Status conventions

**Open** means work has not been completed. **Implemented in PR** means code exists but is not merged or release-accepted. **Validated** requires passing checks for the referenced commit. **Merged** still does not mean the product acceptance or release gates have passed.

The manifest stays on the current prerelease version during this packet. No command is advertised as stable merely because it is exported. The plan is milestone/gate-driven, not a promised calendar deadline.

## Accepted decisions

- Windows only. Minimum Windows PowerShell 5.1; include Microsoft-supported PowerShell 7 releases on Windows. Before RC, CI must cover 5.1, supported 7 LTS, and supported current stable when distinct. Do not promise all historical or future 7.x versions.
- Add `-RemoveEmptyDirectory` to `Clear-CurrentUserTemp` and `Clear-WindowsTemp`. Without it, directories are untouched. With it, prune only directories emptied by this invocation and their now-empty ancestors, deepest-first. Preserve cleanup roots, unrelated pre-existing empty branches, reparse points, and paths outside the approved root.
- Rename private `Show-TCLogo` to `Show-TheCleanersLogo`; rename public `Start-Cleaning` to `Get-TheCleaners`. Retain `Start-Cleaning` as a deprecated alias through 1.x.
- Canonical documentation is `https://day3bits.com/thecleaners/`. Keep the source repository as the manifest's `ProjectUri`. Do not use a documentation URL as an Updatable Help endpoint unless the required HelpInfo artifacts actually exist.
- Keep Exchange discoverable in 1.0, but structurally incapable of deletion. Require explicit `-WhatIf`, fail before discovery when it is absent/false, and do not silently force a preference or run IIS cleanup.
- A later minor release may add a per-invocation Exchange `-AllowRemoval` switch after acceptance. This is **provisional**: the maintainer accepted it for now, not as an irreversible permanent design. There is no persistent unlock and no removal flag in the 1.0 implementation.
- IIS may ship as stable only after its gates pass. Until then, keep it structurally preview-only rather than delaying ready commands.
- Zensical migration is [issue #26](https://github.com/SamErde/TheCleaners/issues/26), outside the 1.0 critical path unless the documentation stack blocks publication.

## Release sequence

| Milestone | Entry/exit criteria |
| --- | --- |
| 1.0 preview | Implement the new safety boundaries, naming, output contracts, quiet imports, and repeatable tests; permit necessary API corrections. |
| 1.0 beta | Temp cleaners and non-destructive commands pass behavior tests; freeze most signatures; IIS lab validation underway; IIS and Exchange remain preview-only. |
| 1.0 RC | Every stable command has evidence for its supported configurations; incomplete IIS remains preview-locked; exact packaged module passes all required runtimes, help, and installation checks. Accept only defect, safety, documentation, and packaging corrections. |
| 1.0 stable | Publish the tested artifact with aligned version/tag/metadata and a successful clean-install check. No feature can become destructive merely by changing a maturity label. |
| Later Exchange minor | First release an Exchange-enabled prerelease; validate paths, file patterns, custom drives, locks, access failures, protected database/transaction-log locations, and post-cleanup service health. Reconfirm the provisional per-invocation opt-in before activation. |

## Work packets

| ID | Work | Current state |
| --- | --- | --- |
| TC-001 | Behavioral contracts, support matrix, maturity policy, migration notes, and release ledger | Partially implemented in PR #27; exact Windows/IIS/Exchange product matrix and remaining command contracts open. |
| TC-002 | Naming, compatibility aliases, deterministic loader, quiet import, removal of initialization scaffolding | Implemented in PR #27; source and packaged import tests added. |
| TC-003 | Public mutation ownership, shared result/error contracts, UTC semantics, path safety, removal of generic deletion wrapper | Temp mutation ownership and Exchange/IIS no-deletion structures implemented in PR #27. IIS no longer calls the legacy wrapper; helper retirement and cross-command result/error standardization remain open. |
| TC-004 | Temp cleaners, opt-in directory pruning, WhatIf/Confirm, locked-file/race handling, privilege/root preflight | Main behavior and file-to-directory/missing-candidate race protections implemented in PR #27; actual OS-root verification, elevation preflight, additional adversarial cases, and Windows acceptance remain open. |
| TC-005 | IIS path discovery, environment expansion, per-format allowlist, deduplication, inline deletion, and server validation | Preview lock, read-only discovery, validated-root normalization/deduplication, and dependency registration restoration implemented in PR #27. Format allowlist, remaining path hardening, removal implementation, and server validation remain open; removal stays disabled until those gates pass. |
| TC-006 | Exchange preview guard, experimental discovery, validated per-directory patterns, protected locations, and lab fixtures | Guard, IIS decoupling, and directory-root validation implemented in PR #27. Current `.log`-only discovery is experimental, not a validated deletion allowlist. ETL and product-version validation remain open. |
| TC-007 | Typed stale-profile output, unknown LastUseTime, optional size, SID resolution, and command inventory | Inventory implemented in PR #27. Profile refactor and unused SID-helper disposition open. |
| TC-008 | One source-layout package, exact-artifact tests/publication, reproducible build, complete runtime matrix, and CI gates | 5.1 unit/parser job and fresh-process package tests added in PR #27. Legacy merged build and source-directory publisher remain; do not publish them as 1.0. |
| TC-009 | Complete help/docs, canonical deployment verification, changelog/history, contributor/security policy, RC and release checks | Initial docs/ledger in PR #27; full generation drift gate, strict site validation, deployment/redirect checks, and release work open. |

### TC-003/004 completion checklist

- [ ] Standardize documented result fields and stable error IDs/categories across every applicable command.
- [ ] Remove the now-unused generic private deletion wrapper and its legacy tests; do not add another generic mutation layer.
- [ ] Verify every discovery error fails closed and cannot be mistaken for zero candidates.
- [ ] Verify `-WhatIf` leaves files, directories, preferences, registry, processes, and module state unchanged.
- [ ] Verify `-Confirm` approval/decline and noninteractive behavior without nested prompts.
- [ ] Validate hard links, junctions, symbolic links, reparse-point ancestry, roots, prefix-confusable siblings, long paths, access failures, and files changing after discovery.
- [ ] Confirm actual system temp root and privilege handling rather than trusting an environment variable alone.
- [ ] Reconcile proposed versus removed/skipped/failed files and directories; bytes are logical lengths of successfully removed files, not a guarantee of physical free-space change.
- [ ] Complete actual Windows client/server acceptance on supported OS versions.

### TC-005/006 completion checklist

- [ ] Explicitly import or qualify IIS discovery commands; handle missing optional dependencies and uninstalled products clearly.
- [ ] Expand environment variables in all discovered roots; normalize and deduplicate roots.
- [ ] Document and test exact supported product versions, default/custom paths, file formats, and retention boundaries.
- [ ] Never treat every old file in an arbitrary logging tree as a safe log candidate.
- [ ] Prove mailbox database and transaction-log paths cannot become Exchange cleanup candidates; exclude a configured database path even if it overlaps a proposed log root.
- [x] Keep IIS and Exchange deletion absent while their current preview locks apply, including legacy aliases and all parameter combinations.
- [ ] Capture lab candidate lists, before/after counts, and service health for any command later enabled for removal.

### TC-007 completion checklist

- [ ] Keep profile discovery read-only; remove presentation-only `Out-Host` behavior.
- [ ] Introduce a stable profile object with SID/account, path, last use, age, optional size, loaded/special flags, and unknown-date status.
- [ ] Treat missing LastUseTime as unknown, not automatically stale; decide how unknown entries are exposed.
- [ ] Confirm default/public/system/service profile exclusions and size-enumeration safety.
- [ ] Remove orphaned SID helpers unless deliberately used by profile output.

### TC-008/009 completion checklist

- [ ] Replace recursive source merging with the explicit source-layout package; preserve useful stack traces and external help.
- [ ] Build once, record a content manifest/digest, test that artifact, and publish it without rebuilding or publishing `src` directly.
- [ ] Add a protected publishing environment and version/tag/prerelease checks; refuse duplicate Gallery versions.
- [ ] Add complete 5.1 plus supported 7 LTS/current package/install tests, not just source unit tests.
- [ ] Re-enable the ShouldProcess analyzer rule; justify narrowly scoped suppressions and consolidate redundant analyzer jobs.
- [ ] Meet at least 80% overall coverage and explicitly test every safety-critical branch; no zero-test or silent discovery-failure passes.
- [ ] Retain machine-readable unit and integration reports, with failed/skipped counts and exact runtime versions.
- [ ] Generate command references and external help from the source of truth; fail on drift and validate the documentation build strictly.
- [ ] Update README, migration guide, changelog, support/security policy, contributing instructions, PR template, and agent instructions.
- [ ] Review template leftovers, duplicated LICENSE, misplaced editor settings, spell-check entries, pre-commit adoption, and redundant scanners.
- [ ] Verify canonical deployment at the lowercase `/thecleaners/` path; arrange redirects from older casing/hosts without creating a conflicting custom-domain configuration.
- [ ] Attach package and hashes to the release; verify a clean install of the published version.

## Validation evidence

PR #27 adds parameterized filesystem tests for both temp commands, inclusive cutoff, literal names, junction exclusion, directory scope, WhatIf, partial failure, ErrorAction Stop, failed enumeration, a candidate replaced by a directory, and a candidate disappearing before deletion. It adds IIS and Exchange no-mutation/guard/root-type tests, export/help/alias tests, source import checks, and a fresh-process built-package probe.

The following references identify the exact regression tests behind review-thread decisions, rather than claiming coverage from implementation alone:

| Behavior | Test source |
| --- | --- |
| Local-kind clock converted to UTC for both temp commands | `src/Tests/Unit/TempCandidateSafety.Tests.ps1`: `converts a local Get-Date result to a UTC retention cutoff`; also asserts `DateTimeKind.Utc`, including on UTC-configured hosts. |
| Candidate disappears between discovery and removal | `src/Tests/Unit/TempCandidateSafety.Tests.ps1`: `reconciles a discovered candidate that disappears before deletion`, parameterized for both temp commands. |
| No Exchange removal-bypass parameters | `src/Tests/Unit/PreviewCommandSafety.Tests.ps1`: `does not expose a removal-bypass parameter`, using command metadata rather than a generic exception. |
| Optional registry absence versus access failure | `src/Tests/Unit/PreviewCommandSafety.Tests.ps1`: IIS fixture uses an absent-value exception; `reports registry access failure instead of silently omitting a configured root` checks the error stream and `-ErrorAction Stop`. |
| IIS dependency registrations restored on success/failure, existing module preserved | `src/Tests/Unit/IISDiscoverySafety.Tests.ps1`: four fresh-process fixture-module scenarios; also checks caller confirmation preferences and leaked commands. This does not claim to unload Windows assemblies. |
| Equivalent site/default/registry roots previewed once | `src/Tests/Unit/IISDiscoverySafety.Tests.ps1`: site variants, registry dot/trailing/alternate-separator cases, and a distinct-custom-root control. |

Adding tests is not evidence that they passed. Record CI run URLs, exact commit/runtime versions, counts, failures, and skips in the PR before changing a packet to validated. Windows/IIS/Exchange lab acceptance is not replaced by CI with mocked fixtures. The editing environment has no local PowerShell runtime; do not claim local Pester execution.

## Parallel work boundaries

One integrator owns shared exports, loader, path helper, shared tests, and build/publishing files. IIS, Exchange, profile, and documentation work may proceed on separate branches with separate test files after interfaces are agreed. Merge serially, rebase, and rerun all cross-cutting tests. Do not run destructive acceptance tests concurrently against the same fixture or machine.

## Out of scope for 1.0

Profile deletion, arbitrary-path or remote cleanup, scheduling installation, automatic all-service orchestration, Linux/macOS support, additional cleanup targets, and complex UI. These should not displace safety or packaging validation.
