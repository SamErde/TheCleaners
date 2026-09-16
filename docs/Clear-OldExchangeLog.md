# Clear-OldExchangeLog (preview-only)

## Synopsis

Preview experimental old Exchange log candidates. **Deletion is unavailable.**

## Syntax

```powershell
Clear-OldExchangeLog [-Days <Int16>] -WhatIf [-PassThru] [<CommonParameters>]
```

`-Days` defaults to 60 and accepts positive Int16 values. Explicit `-WhatIf` is required; omission or `-WhatIf:$false` throws a terminating `ExchangeCleanupPreviewOnly` error before registry access. An ambient WhatIfPreference alone is not sufficient. The common `-Confirm` parameter does not bypass the guard. No `-Force`, `-EnableRemoval`, `-AllowRemoval`, or persistent activation exists in this version.

## Experimental discovery scope

Read `MsiInstallPath` from the Exchange v15 setup registry key. Scan existing `Logging`, `Bin\Search\Ceres\Diagnostics\ETLTraces`, `Bin\Search\Ceres\Diagnostics\Logs`, and `TransportRoles\Logs\MessageTracking` roots with product-specific filename allowlists at or before the inclusive UTC cutoff. Skip reparse points, validate paths, and exclude mailbox database and transaction-log paths returned by Exchange management discovery. If all fixed roots are absent, discovery reports `ExchangeDiscoveryUnavailable` and `-PassThru` returns a failed result; an individual missing root is verbose-only when another approved root is available. Do not invoke IIS cleanup.

This limited preview is not a validated deletion allowlist. The supported Exchange version/build matrix and disposable-lab service-health evidence remain open. Do not use its output to implement an external deletion bypass.

## Examples

```powershell
Clear-OldExchangeLog -Days 60 -WhatIf
Clear-OldExchangeLog -Days 30 -WhatIf -PassThru
```

## Output and failures

`-PassThru` returns a `TheCleaners.CleanupResult` preview for each successfully enumerated existing root. `CandidatePaths` contains discovered paths; `DiscoveryStatus` is `Experimental`; `Status` is `WhatIf`; all removal and reclaimed-byte counts are zero. Missing roots are reported through verbose output when another approved root is available. If all fixed roots are absent, discovery reports `ExchangeDiscoveryUnavailable` and returns a failed result with null candidate counts. Registry failures stop discovery; enumeration failures use the error stream and do not emit a successful empty summary. The alias `Clean-ExchangeLog` has the same safety boundary.

Any later removal capability belongs in a minor release after lab validation and a confirmed per-invocation authorization design. See [the 1.0 plan](release-plan-1.0.md).
