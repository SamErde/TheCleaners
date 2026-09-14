# TheCleaners 1.0 implementation plan

Updated September 13, 2026. Approved direction from the maintainer; implementation began in [draft PR #27](https://github.com/SamErde/TheCleaners/pull/27).

## Status conventions

**Open** means work has not been completed. **Implemented in draft** means code exists but is not merged or release-accepted. **Validated** requires passing checks for the referenced commit. **Merged** still does not mean the product acceptance or release gates have passed.

The manifest stays on the current prerelease version during this first packet. No command is advertised as stable merely because it is exported. The plan is milestone/gate-driven, not a promised calendar deadline.

## Accepted decisions

- Windows only. Minimum Windows PowerShell 5.1; include Microsoft-supported PowerShell 7 releases on Windows. Before RC, CI must cover 5.1, supported 7 LTS, and supported current stable when distinct. Do not promise all historical or future 7.x versions.
- Add `-RemoveEmptyDirectory` to `Clear-CurrentUserTemp` and `Clear-WindowsTemp`. Without it, directories are untouched. With it, prune only directories emptied by this invocation and their now-empty ancestors, deepest-first. Preserve cleanup roots, unrelated pre-existing empty branches, reparse points, and paths outside the approved root.
- Rename private `Show-TCLogo` to `Show-TheCleanersLogo`; rename public `Start-Cleaning` to `Get-TheCleaners`. Retain `Start-Cleaning` as a deprecated alias through 1.x.
- Canonical documentation is `https://day3bits.com/thecleaners/`. Keep the source repository as the manifest's `ProjectUri`. Do not use a documentation URL as an Updatable Help endpoint unless the required HelpInfo artifacts actually exist.
- Keep Exchange discoverable in 1.0, but structurally incapable of deletion. Require explicit `-WhatIf`, fail before discovery when it is absent/false, and do not silently force a preference or run IIS cleanup.
- A later minor release may add a per-invocation `-AllowRemoval` switch after Exchange acceptance. This is **provisional**: the maintainer accepted it for now, not as an irreversible permanent design. There is no persistent unlock and no removal flag in the 1.0 implementation.
- IIS may ship as stable only after its gates pass; otherwise make it structurally preview-only rather than delaying ready commands.
- Zensical migration is [issue #26](https://github.com/SamErde/TheCleaners/issues/26), outside the 1.0 critical path unless the documentation stack blocks publication.

## Release sequence

| Milestone | Entry/exit criteria |
| --- | --- |
| 1.0 preview | Implement the new safety boundaries, naming, output contracts, quiet imports, and repeatable tests; permit necessary API corrections. |
| 1.0 beta | Temp cleaners and non-destructive commands pass behavior tests; freeze most signatures; IIS lab validation underway; Exchange remains preview-only. |
| 1.0 RC | Every stable command has evidence for its supported configurations; incomplete IIS is preview-locked; exact packaged module passes all required runtimes, help, and installation checks. Accept only defect, safety, documentation, and packaging corrections. |
| 1.0 stable | Publish the tested artifact with aligned version/tag/metadata and a successful clean-install check. No feature can become destructive merely by changing a maturity label. |
| Later Exchange minor | First release an Exchange-enabled prerelease; validate paths, file patterns, custom drives, locks, access failures, protected database/transaction-log locations, and post-cleanup service health. Reconfirm the provisional per-invocation opt-in before activation. |

## Work packets

| ID | Work | Current state |
| --- | --- | --- |
| TC-001 | Behavioral contracts, support matrix, maturity policy, migration notes, and release ledger | Partially implemented in draft #27; exact Windows/IIS/Exchange product matrix and remaining command contracts open. |
| TC-002 | Naming, compatibility aliases, deterministic loader, quiet import, removal of initialization scaffolding | Implemented in draft #27; source and packaged import tests added. |
| TC-003 | Public mutation ownership, shared result/error contracts, UTC semantics, path safety, removal of generic deletion wrapper | Partially implemented in draft #27 for temp and Exchange preview; IIS still depends on `Remove-OldFiles`. |
| TC-004 | Temp cleaners, opt-in directory pruning, WhatIf/Confirm, locked-file/race handling, privilege/root preflight | Main behavior implemented in draft #27; remaining adversarial/concurrent cases, actual OS-root verification, elevation preflight, and Windows acceptance open. |
| TC-005 | IIS path discovery, environment expansion, per-format allowlist, deduplication, inline deletion, and server validation | Open. Remove `Remove-OldFiles` and its legacy tests only in this packet once its last caller is updated. |
| TC-006 | Exchange preview guard, experimental discovery, validated per-directory patterns, protected locations, and lab fixtures | Guard and IIS decoupling implemented in draft #27. Current .log-only discovery is experimental, not a validated deletion allowlist. ETL and product-version validation remain open. |
| TC-007 | Typed stale-profile output, unknown LastUseTime, optional size, SID resolution, and command inventory | Inventory implemented in draft #27. Profile refactor and unused SID-helper disposition open. |
| TC-008 | One source-layout package, exact-artifact tests/publication, reproducible build, complete runtime matrix, and CI gates | 5.1 unit/parser job and fresh-process package tests added in draft #27. Legacy merged build and source-directory publisher remain; do not publish them as 1.0. |
| TC-009 | Complete help/docs, canonical deployment verification, changelog/history, contributor/security policy, RC and release checks | Initial docs/ledger in draft #27; full generation drift gate, strict site validation, deployment/redirect checks, and release work open. |

### TC-003/004 completion checklist

- [ ] Standardize documented result fields and stable error IDs/categories across every applicable command.
- [ ] Remove all generic private deletion wrappers after migrating IIS; retain only justified read-only helpers.
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
- [ ] Keep Exchange deletion absent throughout 1.0, including legacy aliases and all parameter combinations.
- [ ] Capture lab candidate lists, before/after counts, and service health for any command enabled for removal.

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

Draft #27 adds parameterized filesystem tests for both temp commands, inclusive cutoff, literal names, junction exclusion, directory scope, WhatIf, partial failure, ErrorAction Stop, and failed enumeration. It adds Exchange no-mutation/guard tests, export/help/alias tests, source import checks, and a fresh-process built-package probe.

Adding tests is not evidence that they passed. Record CI run URLs, exact commit/runtime versions, counts, failures, and skips in the PR before changing a packet to validated. Windows/Exchange lab acceptance is not replaced by CI with mocked fixtures. The editing session has no local PowerShell runtime; do not claim local Pester execution.

## Parallel work boundaries

One integrator owns shared exports, loader, path helper, shared tests, and build/publishing files. IIS, Exchange, profile, and documentation work may proceed on separate branches with separate test files after interfaces are agreed. Merge serially, rebase, and rerun all cross-cutting tests. Do not run destructive acceptance tests concurrently against the same fixture or machine.

## Out of scope for 1.0

Profile deletion, arbitrary-path or remote cleanup, scheduling installation, automatic all-service orchestration, Linux/macOS support, additional cleanup targets, and complex UI. These should not displace safety or packaging validation.
