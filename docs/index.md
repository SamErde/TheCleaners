# The Cleaners

Windows maintenance commands with explicit safety controls. PR #31 is merged, but this remains unreleased 1.0 preparation work rather than a production-ready release. The source manifest is `0.0.15-beta`; the PowerShell Gallery still serves `0.0.13-alpha`.

Windows PowerShell 5.1 is the minimum; the target policy also includes Microsoft-supported PowerShell 7 releases on Windows. See [support and validation](support-matrix.md).

```powershell
Get-TheCleaners -NoLogo
Clear-CurrentUserTemp -Days 30 -WhatIf -PassThru
Clear-WindowsTemp -Days 30 -RemoveEmptyDirectory -WhatIf -PassThru
Clear-OldIISLog -Days 60 -WhatIf -PassThru
Clear-OldExchangeLog -Days 60 -WhatIf -PassThru
```

The temp cleaners preserve directories unless `-RemoveEmptyDirectory` is supplied. IIS and Exchange are structurally preview-only; their candidate lists are experimental and deletion is unavailable. Module import is quiet, and `Start-Cleaning` remains an alias for [Get-TheCleaners](Get-TheCleaners.md).

Read [safety and confirmation](safety-and-confirmation.md), [migration notes](migration-to-1.0.md), and the [1.0 implementation ledger](release-plan-1.0.md) before using this development version. The ledger distinguishes merged implementation, exact-commit CI evidence, product/lab acceptance, and release authorization. The [repository README](https://github.com/SamErde/TheCleaners#readme) distinguishes the published Gallery prerelease from a source checkout.

Canonical documentation: <https://day3bits.com/TheCleaners/>. The [Zensical migration](https://github.com/SamErde/TheCleaners/issues/26) remains a separate follow-up.
