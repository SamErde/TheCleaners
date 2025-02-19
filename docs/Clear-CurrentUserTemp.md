---
external help file: TheCleaners-help.xml
Module Name: TheCleaners
online version:
schema: 2.0.0
---

# Clear-CurrentUserTemp

## SYNOPSIS
Clean old temp files from user profiles.

## SYNTAX

```
Clear-CurrentUserTemp [[-Days] <Int16>] [[-TimeOut] <Int16>] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Remove temp files older than a given number of days from the user's local temp folder.

## EXAMPLES

### EXAMPLE 1
```
Clear-CurrentUserTemp -Days 30
```

### EXAMPLE 2
```
Clean-CurrentUserTemp -Days 21 -TimeOut 30
```

## PARAMETERS

### -Days
Remove temp files that are $Days days old or older.
The default is 30.

```yaml
Type: Int16
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: 30
Accept pipeline input: False
Accept wildcard characters: False
```

### -TimeOut
A time limit (seconds) for the looping operation that removes empty directories.
The default is 30.

```yaml
Type: Int16
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: 30
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

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
Prompts you for confirmation before running the cmdlet.

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
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable, -Verbose, -WarningAction, -WarningVariable, and -ProgressAction. 
For more information, see about_CommonParameters (http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

## RELATED LINKS
