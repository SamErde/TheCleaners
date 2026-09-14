# Migrating prerelease scripts toward 1.0

These changes are in PR #27, not a published 1.0 release. The Gallery version is not automatically updated when a PR is opened or merged.

## Command inventory

Use `Get-TheCleaners` instead of `Start-Cleaning`. The old name remains a deprecated alias through 1.x. Use `Get-TheCleaners -NoLogo` for pipelines. Output is now typed command metadata with `Name`, `Maturity`, `RemovalEnabled`, and `SupportsWhatIf`, rather than a presentation-only property. No command is labeled stable yet; IIS and Exchange are reported as `PreviewOnly` with removal disabled.

The private logo helper is `Show-TheCleanersLogo`; private functions are not a supported public API. Import no longer prints a welcome message or creates `Invoke-TheCleaners` in the caller's environment.

## Temporary directories

`Clear-CurrentUserTemp` no longer removes empty directories by default. Both temp commands now support `-RemoveEmptyDirectory`. It only prunes directories emptied by the current cleanup and their now-empty ancestors; unrelated pre-existing empty branches remain.

The obsolete `-TimeOut` parameter is removed. A bounded deepest-first pass replaces the repeated directory-removal loop. Update scripts that supplied `-TimeOut`; do not silently assume the old parameter still applies.

```powershell
Clear-CurrentUserTemp -Days 30 -RemoveEmptyDirectory -WhatIf -PassThru
Clear-WindowsTemp -Days 30 -RemoveEmptyDirectory -WhatIf -PassThru
```

The retention boundary remains inclusive but is now evaluated using UTC last-write times and a single cutoff. Candidate deletion uses a file-handle-specific `DeleteOnClose` operation instead of provider `Remove-Item`; a missing candidate is skipped, and a directory substituted at the same path is preserved. Locked/access-denied removals produce errors, not warnings; review automation that relies on error-stream behavior. `-ErrorAction Stop` is honored. `-PassThru` returns counters and status, with preview counts distinct from successful removals.

Temp roots and literal paths must be fully qualified Windows filesystem paths. Drive-relative, root-relative, provider-qualified, device, and unsupported extended-length forms are rejected before resolution.

## IIS

Existing destructive IIS invocations now stop with a terminating `IISCleanupPreviewOnly` error. Use explicit preview mode while the IIS-specific path and file-format contract is completed:

```powershell
Clear-OldIISLog -Days 60 -WhatIf -PassThru
```

`Clean-IISLog` has the same guard. No removal flag exists, and IIS no longer invokes the legacy private `Remove-OldFiles` helper. The helper remains internal technical debt until its focused removal; the current `.log` candidate filter is experimental and must not be piped into a separate deletion command.

## Exchange

Existing destructive Exchange invocations now stop with a terminating `ExchangeCleanupPreviewOnly` error. Rerun only as an explicit preview:

```powershell
Clear-OldExchangeLog -Days 60 -WhatIf -PassThru
```

No removal or persistent activation is available. `Clean-ExchangeLog` has the same guard. Exchange no longer invokes IIS cleanup. Preview candidates are experimental and must not be piped into deletion as a substitute for the missing validated cleanup implementation.

## Documentation

The canonical URL is [day3bits.com/thecleaners](https://day3bits.com/thecleaners/). The old Start-Cleaning documentation page is retained as a compatibility pointer. Deployment and redirects from older hosts/casing still need verification. Zensical migration remains a separate follow-up in issue #26.
