---
external help file: TheCleaners-help.xml
Module Name: TheCleaners
online version:
schema: 2.0.0
---

# Clear-OldIISLog

## SYNOPSIS
A script to clean out old IIS log files.

## SYNTAX

```
Clear-OldIISLog [[-Days] <Int16>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
This script will clean out IIS log files older than x days.

## EXAMPLES

### EXAMPLE 1
```
Clear-OldIISLog -Days 60
```

Removes all IIS log files that are older than 60 days.

## PARAMETERS

### -Days
The number of days to keep log files.
The default is 60 days.

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
If the WebAdministration module is available, it will use that to check the specific log file locations for
each web site.
Otherwise, it checks the assumed default log folder location and the registry for the IIS
log file location.

To Do: Add a summary of which blocks were run and possibly a count of log files removed.

## RELATED LINKS
