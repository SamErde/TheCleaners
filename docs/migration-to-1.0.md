# Migrating prerelease scripts toward 1.0

PR #31 merged the stabilization implementation into `main`, but this is not a published 1.0 release. The source manifest is `0.0.15-beta`; the Gallery still serves `0.0.13-alpha`. A merge does not update the Gallery automatically or satisfy product/lab acceptance.

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

The retention boundary remains inclusive but is now evaluated using UTC last-write times and a single cutoff. Candidate deletion uses a same-handle native `DELETE` operation without `FILE_READ_DATA` instead of provider `Remove-Item`; a missing candidate is skipped, and a directory or different identity substituted at the same path is preserved. Locked/access-denied removals produce stable error IDs on the error stream; review automation that relies on error-stream behavior. `-ErrorAction Stop` is honored. `-PassThru` returns the shared result contract, with preview counts distinct from successful removals.

Temp roots and literal paths must be fully qualified Windows filesystem paths. Drive-relative, root-relative, provider-qualified, and device paths are rejected before resolution. Supported extended-length drive and UNC forms are accepted when the Windows provider and long-path policy can resolve them; otherwise discovery fails closed.

## IIS

Existing destructive IIS invocations now stop with a terminating `IISCleanupPreviewOnly` error. Use explicit preview mode while the IIS-specific path and file-format contract is completed:

```powershell
Clear-OldIISLog -Days 60 -WhatIf -PassThru
```

`Clean-IISLog` has the same guard. No removal flag exists, and IIS no longer invokes a generic deletion helper. The old private wrapper has been retired; the format-specific candidate filter remains experimental and must not be piped into a separate deletion command.

## Exchange

Existing destructive Exchange invocations now stop with a terminating `ExchangeCleanupPreviewOnly` error. Rerun only as an explicit preview:

```powershell
Clear-OldExchangeLog -Days 60 -WhatIf -PassThru
```

No removal or persistent activation is available. `Clean-ExchangeLog` has the same guard. Exchange no longer invokes IIS cleanup. Preview candidates are experimental and must not be piped into deletion as a substitute for the missing validated cleanup implementation.

## Documentation

The intended canonical URL is [day3bits.com/thecleaners](https://day3bits.com/thecleaners/). The old Start-Cleaning documentation page is retained as a compatibility pointer. The exact PR #31 deployment workflow succeeded, but the lowercase path still returns HTTP 404 while `/TheCleaners/` returns HTTP 200; that site-owner correction remains open. Zensical migration remains a separate follow-up in issue #26.
