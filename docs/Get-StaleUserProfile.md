---
external help file: TheCleaners-help.xml
Module Name: TheCleaners
online version:
schema: 2.0.0
---

# Get-StaleUserProfile

## SYNOPSIS
Return typed, read-only information about stale Windows user profiles.

## SYNTAX

```
Get-StaleUserProfile [[-Days] <Int16>] [-IncludeSize] [-IncludeUnknownLastUseTime] [<CommonParameters>]
```

## DESCRIPTION
Queries `Win32_UserProfile` and returns one `TheCleaners.StaleUserProfile` object per
eligible profile. Special, loaded, default, built-in service, virtual service, and
IIS application-pool profiles are excluded.
The command never deletes profiles or writes presentation output to the host.
Unknown or invalid `LastUseTime` values are not classified as stale unless
`-IncludeUnknownLastUseTime` is specified. SID translation is best effort. Optional
size enumeration rejects reparse points anywhere in the profile path ancestry
and retains identity-checked handles for profile ancestors through the size operation.
Each queued child directory carries its discovery-time identity and is opened and
revalidated when traversed; where the current token permits it, the active
directory uses a native handle with delete and read-attribute access without
delete sharing while it is enumerated. Ancestors fall back to identity-only
handles when DELETE access is unavailable, so replacement or rename is detected
and sizing fails closed.

## EXAMPLES

### EXAMPLE 1
```
$StaleUserProfile = Get-StaleUserProfile -Days 90
```

Returns typed stale-profile objects without changing profile state.

### EXAMPLE 2
```powershell
Get-StaleUserProfile -Days 90 -IncludeSize -IncludeUnknownLastUseTime
```

Includes optional logical-size enumeration and profiles whose last-use date is
unknown. Size failures remain explicit as `SizeStatus = Unavailable` and use the
`ProfileSizeUnavailable` error identifier.

## PARAMETERS

### -Days
Number of days to consider a profile stale.
The default is 90.

```yaml
Type: Int16
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: 90
Accept pipeline input: False
Accept wildcard characters: False
```

### -IncludeSize
Recursively calculate logical file size for returned profiles. Reparse points are
not followed. The legacy `-ShowSummary` name remains an alias for this switch.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: ShowSummary

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -IncludeUnknownLastUseTime
Include eligible profiles whose `LastUseTime` is missing or invalid. These objects
have `IsStale = False` and `DateStatus = Unknown`.

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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable, -Verbose, -WarningAction, -WarningVariable, and -ProgressAction. 
For more information, see about_CommonParameters (http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

`TheCleaners.StaleUserProfile` objects with `ContractVersion = 1.0`.

## NOTES
The command is inventory-only. It does not provide a profile-removal operation.

## RELATED LINKS
