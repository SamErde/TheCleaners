---
external help file: TheCleaners-help.xml
Module Name: TheCleaners
online version: https://day3bits.com/thecleaners/Clear-OldIISLog/
schema: 2.0.0
---

# Clear-OldIISLog

## SYNOPSIS

Preview old IIS log candidates without removing anything.

## SYNTAX

```powershell
Clear-OldIISLog [[-Days] <Int16>] [-PassThru] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION

`Clear-OldIISLog` is structurally preview-only while IIS path, file-pattern, and server acceptance work remains incomplete. Explicit `-WhatIf` is required. Calling the command without it, or with `-WhatIf:$false`, produces a terminating `IISCleanupPreviewOnly` error before module, registry, or filesystem discovery.

The command discovers existing IIS log roots, skips reparse points before traversal, and previews old `.log` files using one inclusive UTC cutoff. Candidate discovery is experimental and is not a validated deletion allowlist. This version contains no deletion command and does not call the legacy generic removal helper.

## EXAMPLES

### Example 1

```powershell
Clear-OldIISLog -Days 60 -WhatIf
```

Preview old `.log` candidates without returning summary objects.

### Example 2

```powershell
Clear-OldIISLog -Days 30 -WhatIf -PassThru
```

Preview candidates and return one summary for each successfully enumerated existing root.

## PARAMETERS

### -Days

Preview `.log` files whose `LastWriteTimeUtc` is at or before one cutoff captured `Days` days ago. The default is 60 days.

```yaml
Type: Int16
Parameter Sets: (All)
Aliases:
Required: False
Position: 1
Default value: 60
Accept pipeline input: False
Accept wildcard characters: False
```

### -PassThru

Return a `TheCleaners.CleanupResult` preview summary. `CandidatePaths` contains the discovered files. All removal and reclaimed-byte counters remain zero.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf

Required explicitly in this preview-only version. Produces normal PowerShell WhatIf output for discovered candidates. It does not enable removal.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi
Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm

Present through `SupportsShouldProcess`, but confirmation cannot enable removal in this preview-only version.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf
Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters

This cmdlet supports the common parameters. For more information, see `about_CommonParameters`.

## OUTPUTS

### TheCleaners.CleanupResult

Returned only with `-PassThru`. Results have `Status = WhatIf`, `DiscoveryStatus = Experimental`, and zero removal counts.

## NOTES

When WebAdministration is available, site-specific roots are discovered from IIS configuration. Otherwise, the command considers the default IIS log root and the registry-configured root. Missing or non-directory roots are skipped. Environment variables are expanded, and duplicate roots are suppressed before traversal.

The current `.log` filter is provisional. Do not pipe preview candidates into a separate deletion command as a substitute for the pending IIS allowlist and server acceptance work.
