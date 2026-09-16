# Changelog

## Unreleased - 1.0 preparation

This entry describes unreleased work, not a released 1.0 package. Historical changes preceding this work still need reconciliation against the repository and Gallery history.

### Added

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

- Renamed `Start-Cleaning` to `Get-TheCleaners`; retained `Start-Cleaning` as a deprecated alias through 1.x.
- Renamed private `Show-TCLogo` to `Show-TheCleanersLogo`.
- Made module loading explicit and import quiet.
- Standardized the canonical documentation URL to `https://day3bits.com/thecleaners/`.
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

PR #31 merged at `037c27a81234361620a633f68a33bfb370f0a03e`. Exact-commit hosted PowerShell 7.6.6, PowerShell 7.5.9, Windows PowerShell 5.1, package-import, PSScriptAnalyzer, and strict MkDocs workflow evidence is recorded in `docs/release-plan-1.0.md`.

### Still pending

Windows client/server, broader elevated/non-elevated, real-system-root, and ReFS acceptance; the still-supported PowerShell 7.4 line or an approved support-policy narrowing; a refresh of the 7.5 lane to Microsoft's latest supported servicing update; IIS and Exchange product/build labs; cross-runtime archive reproducibility; the lowercase documentation deployment; protected exact-artifact publication; final version/tag/metadata alignment; and maintainer release authorization remain open. The source manifest is `0.0.15-beta`, while the Gallery still serves `0.0.13-alpha`. Zensical migration is tracked separately in issue #26.
