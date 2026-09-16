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

The command discovers existing IIS log roots, skips reparse points before traversal, and previews files matching the format-specific allowlist using one inclusive UTC cutoff. Validated roots are normalized and deduplicated before enumeration. A WebAdministration dependency imported for discovery is removed afterward, including when discovery fails; an already loaded dependency is preserved. Candidate discovery is experimental and is not a validated deletion allowlist. This version contains no deletion command and no generic deletion wrapper.

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

Preview candidates and return one summary for each existing root. A root that fails
validation or enumeration is returned as `Status = DiscoveryFailed` with null
candidate counts when `-PassThru` is used.

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

When WebAdministration is available, site-specific web roots and FTP roots are discovered separately from IIS configuration. Otherwise, the command considers the default and registry-configured W3SVC roots, but it fails closed unless the logging format and local-time rollover metadata are available. Missing roots are skipped; roots that fail validation, metadata checks, or enumeration are reported through the error stream and, with `-PassThru`, as `DiscoveryFailed` summaries with null candidate counts. Environment variables are expanded. Existing roots pass path and reparse-point validation, are normalized to absolute paths without trailing separators, and are deduplicated case-insensitively before traversal. Equivalent `..`, separator, and trailing-separator spellings produce one summary; distinct roots remain separate.

A dependency already loaded by the caller is not unloaded. A dependency loaded solely for this discovery is removed on success or failure. This restores the dependency's module/command registration, not every process-level effect of loading a Windows component; it is not a claim that loaded assemblies are unloaded. Caller WhatIf and Confirm preferences are preserved.

An absent optional registry setting is normal. Registry access or provider failures are reported through the error stream and honor `-ErrorAction Stop`; any summaries returned with continuing error handling describe only roots that were successfully discovered and enumerated, not a complete inventory.

The source allowlist accepts only built-in W3C, IIS, and NCSA filename families for the configured service/format and rollover metadata. W3C matching covers calendar-valid monthly, daily, and hourly names, bounded sequence suffixes, and the documented `extendNN.log` size-rollover family; custom or unknown formats fail closed. This allowlist is still preview discovery evidence, not a validated deletion contract. Do not pipe preview candidates into a separate deletion command as a substitute for IIS product/build and server acceptance.
