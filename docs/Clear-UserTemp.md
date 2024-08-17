---
external help file: TheCleaners-help.xml
Module Name: TheCleaners
online version:
schema: 2.0.0
---

# Clear-UserTemp

## SYNOPSIS
Clean old temp files from user profiles.

## SYNTAX

```
Clear-UserTemp [[-Days] <Int16>] [<CommonParameters>]
```

## DESCRIPTION
Remove temp files older than 60 days from users' local temp folder.

## EXAMPLES

### EXAMPLE 1
```
Clear-UserTemp -Days 30
```

## PARAMETERS

### -Days
How many days worth of temp files to keep.
This can help avoid getting errors when trying to delete temp files that are still in use.

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
