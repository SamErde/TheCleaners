# Changelog

## Unreleased - 1.0 preparation

This entry describes draft work, not a released 1.0 package. Historical changes preceding this work still need reconciliation against the repository and Gallery history.

### Added

- Opt-in `-RemoveEmptyDirectory` for both temp cleaners, limited to directories emptied by the invocation and their ancestors.
- Typed temp-cleanup summaries, planned directory counts under WhatIf, UTC retention boundaries, literal-path checks, and reparse-point exclusion before traversal.
- Explicit Exchange preview guard, experimental preview summaries, and no-deletion regression checks.
- Typed `Get-TheCleaners` command inventory with `-NoLogo` for automation.
- Windows PowerShell 5.1 parser/unit CI and fresh-process source/package import probes.
- A versioned 1.0 implementation ledger and contributor/agent safety instructions.

### Changed

- Renamed `Start-Cleaning` to `Get-TheCleaners`; retained `Start-Cleaning` as a deprecated alias through 1.x.
- Renamed private `Show-TCLogo` to `Show-TheCleanersLogo`.
- Made module loading explicit and import quiet.
- Standardized the canonical documentation URL to `https://day3bits.com/thecleaners/`.
- Temp failures now use the error stream; unknown discovery totals are not reported as zero candidates.
- Changed workflow actions use immutable SHAs, and missing required artifacts are fatal.

### Removed

- Automatic empty-directory pruning without an explicit switch.
- The obsolete current-user `-TimeOut` parameter and looping directory cleanup.
- Exchange deletion code and implicit IIS cleanup.
- Import-time initializer, `ScriptsToProcess`, unused import scaffold, and invalid Updatable Help URI.

### Still pending

IIS hardening and its generic-helper removal, profile refactor, full product/runtime acceptance, source-layout package and exact-artifact publication, documentation-generation drift validation, and release authorization. See `docs/release-plan-1.0.md`. Zensical migration is tracked separately in issue #26.
