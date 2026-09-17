# Changelog

## Unreleased - 1.0 preparation

Following the `0.0.15-beta` prerelease, Windows client/server, IIS, Exchange, profile, and final 1.0 acceptance remain open. Lab validation is deferred future work and is not underway.

## 0.0.15-beta - 2026-09-17

Version `0.0.15-beta` was published from exact source `345f06c861b6d4074e5896e0b27a19f869dfa7e3` under tag `v0.0.15-beta`. The [release notes and history reconciliation](docs/releases/0.0.15-beta.md) map the changes below to that prerelease. The old unpublished `0.0.11-alpha` GitHub draft remains historical metadata and was not reused.

### Added

- Documentation verification and delivery: source/run-bound content manifests, restricted HTTP transport, isolated regressions, one-build deployment and bounded public verification. PR #37 merged the delivery path, and its merge run verified all 71 retained files plus representative navigation at the title-case canonical URL. Lab validation is deferred future work, not underway.
- TC-003/004 disposable Windows acceptance matrix, operator prerequisites, and versioned evidence schema separating implemented fixtures from unexecuted lab acceptance. Harden the isolated ACL harness with canonical-parent/reparse checks, retained identity handles, preview/removal inventory reconciliation, fresh source-module import, required OS metadata, source/candidate evidence, explicit failure residue, and post-recovery reporting; remove recursive ACL reset/deletion and retain the fixture for inspection.
- Bounded TC-008 review of all 307 baseline uncovered commands, with a source-line disposition inventory and 30 focused temp, profile, and IIS/Exchange preview regression cases. No runtime behavior or product-acceptance status changes.
- Opt-in `-RemoveEmptyDirectory` for both temp cleaners, limited to directories emptied by the invocation and their ancestors.
- Typed temp-cleanup summaries, planned directory counts under WhatIf, UTC retention boundaries, literal-path checks, and reparse-point exclusion before traversal.
- Explicit IIS and Exchange preview guards, experimental preview summaries, and no-deletion regression checks.
- Typed `Get-TheCleaners` command inventory with `-NoLogo` for automation.
- Windows PowerShell 5.1 parser/unit CI and fresh-process source/package import probes.
- A versioned 1.0 implementation ledger and contributor/agent safety instructions.
- Fresh-process IIS dependency-lifetime tests for initially loaded/unloaded modules on discovery success/failure, using a fixture module rather than a live IIS installation.
- IIS site and registry deduplication regressions covering dot segments, trailing separators, alternate separators, and distinct custom roots.
- Fully qualified Windows filesystem path validation that rejects drive-relative, root-relative, provider, device, and unsupported extended-length forms before resolution.

### Changed

- Prioritize non-lab documentation/delivery readiness and an optional approved prerelease; Windows, IIS, Exchange, and profile lab validation is deferred future work, not underway. Require succinct Completed / Remaining summaries in every successor prompt.
- Use the working title-case `https://day3bits.com/TheCleaners/` URL consistently in configuration, manifest, source help, and documentation. Track support for both URL cases in Zensical issue #26.
- Configure the GitHub `powershell-gallery` environment with SamErde review, disabled administrator bypass and `v*` tag restrictions. Update the publishing workflow to use the dedicated `PSGALLERY_PUBLISH_API_KEY` environment secret, fail clearly when absent, and stop passing repository secrets to the build matrix. The protected `0.0.15-beta` run exercised the environment approval and credential through the exact-artifact publisher.
- Add a closed local-rehearsal publisher mode that uses an existing local filesystem repository and an internal placeholder key. Preserve the exact-artifact guards shared with the fixed PSGallery production path and require an explicit valid source commit in both modes.
- Bind publication to the maintainer-approved archive digest and verify the published version's installed payload, metadata, import, help, aliases and preview locks on fresh supported-runtime runners.
- Build documentation once, retain a source-bound manifest, deploy that exact output and verify every public file's bytes and representative navigation with bounded propagation retries.

- TC-008 merged implementation: add current PowerShell 7.4.20 and 7.5.11 hosted lanes; preserve 7.6.6 and canonical-artifact PS5.1 testing.
- Replace runtime-dependent ZIP compression with stored entries, ordinal ordering, UTF-8 names and fixed metadata; require repeated and cross-runtime byte equality, exact commit identity, complete extracted file verification and hidden-file uploads.
- Pin download-artifact v8.0.1 to its immutable Node 24 commit; add strict documentation validation to the PR/reusable build gate.

- Renamed `Start-Cleaning` to `Get-TheCleaners`; retained `Start-Cleaning` as a deprecated alias through 1.x.
- Renamed private `Show-TCLogo` to `Show-TheCleanersLogo`.
- Made module loading explicit and import quiet.
- Standardized the canonical documentation URL to `https://day3bits.com/TheCleaners/`.
- Temp failures now use the error stream; unknown discovery totals are not reported as zero candidates.
- Temp file removal now uses a same-handle native operation requesting `DELETE` and `FILE_READ_ATTRIBUTES`, without `FILE_READ_DATA`. Missing candidates and identity substitutions are skipped, and a directory substituted at a candidate path cannot be removed or counted as a file deletion.
- IIS now requires explicit `-WhatIf`, reports `PreviewOnly`, and cannot remove files until its product-specific gates pass. The generic deletion wrapper has been retired.
- IIS validates and normalizes all discovered roots at one boundary before deduplication and traversal; equivalent site, default, and registry paths no longer produce duplicate previews.
- IIS unloads a WebAdministration dependency introduced for discovery in a `finally` block, while preserving a dependency that was already loaded. Cleanup does not enable file removal or change caller confirmation preferences.
- Changed workflow actions use immutable SHAs, and missing required artifacts are fatal.

### Removed

- Automatic empty-directory pruning without an explicit switch.
- The obsolete current-user `-TimeOut` parameter and looping directory cleanup.
- IIS and Exchange deletion paths, and Exchange's implicit IIS cleanup.
- Import-time initializer, `ScriptsToProcess`, unused import scaffold, and invalid Updatable Help URI.

### Verification status

PR #33 merged at `fdadbee08f854b1af6fdc7654ae4532ebbf605df`. Exact-commit hosted PowerShell 7.4.20, 7.5.11, 7.6.6, Windows PowerShell 5.1, package/import, repeated and cross-runtime archive, PSScriptAnalyzer, and strict MkDocs evidence is recorded in `docs/release-plan-1.0.md`. This closes the runtime-matrix and bounded PS7 Windows archive-reproducibility subgates only; it does not validate TC-008 as a whole or accept a release.

PR #37 merged at `345f06c861b6d4074e5896e0b27a19f869dfa7e3`. Its exact documentation run verified 71 retained files, the complete public Git tree and five representative routes. The merge build and analyzer passed; retained evidence verified the supported runtime matrix, archive equality and isolated local-feed publication rehearsal for `0.0.15-beta`.

Protected publication run [35268852573](https://github.com/SamErde/TheCleaners/actions/runs/35268852573) verified the approved 19-file, 224,050-byte archive with SHA-256 `1c8e061278e68c2e1537186709f79606735c6dda2e48b5cf65a4a877699e3383`, published Gallery version `0.0.15-beta`, and passed fresh installed-package verification on Windows PowerShell 5.1 and PowerShell 7.4.20, 7.5.11, and 7.6.6. Independent verification passed all checks across 11 jobs, 15 retained artifact wrappers and four installed-package reports. The matching [GitHub prerelease](https://github.com/SamErde/TheCleaners/releases/tag/v0.0.15-beta) targets the same tag and source; its archive, manifest and sidecar assets were downloaded and matched byte-for-byte.

### Still pending

Windows client/server, broader elevated/non-elevated, real-system-root, ReFS and adversarial/concurrency acceptance; IIS and Exchange product/build preview labs; and Windows profile-inventory acceptance are deferred future work, not underway. Final 1.0 release acceptance remains open. The bounded baseline uncovered-command review merged in PR #35; its remaining native/platform/product cases remain lab gates. The published beta does not close them. Zensical migration and support for both URL cases are tracked separately in issue #26.
