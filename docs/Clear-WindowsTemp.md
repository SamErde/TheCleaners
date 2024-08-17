---
external help file: TheCleaners-help.xml
Module Name: TheCleaners
online version:
schema: 2.0.0
---

# Clear-WindowsTemp

## SYNOPSIS
A script to clean out old Windows Temp files.

## SYNTAX

```
Clear-WindowsTemp [[-Days] <Int16>] [<CommonParameters>]
```

## DESCRIPTION
This script will clean out Windows Temp files older than x days.

## EXAMPLES

### EXAMPLE 1
```
Clear-WindowsTemp -Days 60
```

Removes all Windows Temp files that are older than 60 days.

## PARAMETERS

### -Days
The number of days to keep temp files.
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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable, -Verbose, -WarningAction, -WarningVariable, and -ProgressAction. 
For more information, see about_CommonParameters (http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES
Author:     Sam Erde
            https://twitter.com/SamErde
            https://github.com/SamErde
Modified:   2024-08-12

## RELATED LINKS
