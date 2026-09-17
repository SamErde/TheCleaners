# The Cleaners

Windows maintenance commands with explicit safety controls. The published `0.0.15-beta` package is a prerelease rather than a production-ready 1.0 release. The repository continues 1.0 preparation from that package's exact source.

The [0.0.15-beta release](releases/0.0.15-beta.md) passed exact source/artifact, protected publication, and fresh Gallery-install validation. Windows, IIS, Exchange, and profile lab validation is deferred future work, not underway.

```powershell
Install-Module -Name TheCleaners -RequiredVersion '0.0.15-beta' -AllowPrerelease
```

Windows PowerShell 5.1 is the minimum; the target policy also includes Microsoft-supported PowerShell 7 releases on Windows. See [support and validation](support-matrix.md).

```powershell
Get-TheCleaners -NoLogo
Clear-CurrentUserTemp -Days 30 -WhatIf -PassThru
Clear-WindowsTemp -Days 30 -RemoveEmptyDirectory -WhatIf -PassThru
Clear-OldIISLog -Days 60 -WhatIf -PassThru
Clear-OldExchangeLog -Days 60 -WhatIf -PassThru
```

The temp cleaners preserve directories unless `-RemoveEmptyDirectory` is supplied. IIS and Exchange are structurally preview-only; their candidate lists are experimental and deletion is unavailable. Module import is quiet, and `Start-Cleaning` remains an alias for [Get-TheCleaners](Get-TheCleaners.md).

Read [safety and confirmation](safety-and-confirmation.md), [migration notes](migration-to-1.0.md), and the [1.0 implementation ledger](release-plan-1.0.md) before using this prerelease. The ledger distinguishes prerelease evidence from product/lab and final 1.0 acceptance. The [repository README](https://github.com/SamErde/TheCleaners#readme) distinguishes the published Gallery prerelease from a source checkout.

Canonical documentation: <https://day3bits.com/TheCleaners/>. The [Zensical migration](https://github.com/SamErde/TheCleaners/issues/26) remains a separate follow-up.
