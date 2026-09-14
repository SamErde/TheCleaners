# Clear-WindowsTemp

## Synopsis

Remove old files from `SystemRoot\Temp` on Windows. This command remains prerelease.

## Syntax

```powershell
Clear-WindowsTemp [-Days <Int16>] [-RemoveEmptyDirectory] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Behavior

Select files of any extension whose `LastWriteTimeUtc` is at or before one UTC cutoff. `-Days` defaults to 30 and accepts positive Int16 values. Reparse points are excluded before traversal. Literal paths, ancestry, type, and timestamps are revalidated before removal. Missing SystemRoot is an error. Run elevated for system-owned files; a dedicated elevation and actual OS-root preflight is still tracked for 1.0.

Without `-RemoveEmptyDirectory`, directories remain untouched. With it, only prune directories emptied by the current invocation and their now-empty ancestors, deepest-first. Never remove the root or unrelated pre-existing empty branches. A retained file prevents pruning its directory.

`-WhatIf` makes no filesystem changes and reports the proposed batch. `-Verbose` lists candidate paths. `-Confirm` prompts for approval of the discovered file/directory plan at the root and lets the caller accept or decline it. ConfirmImpact is Medium. No Force or separate ShouldContinue prompt is implemented.

## Examples

```powershell
Clear-WindowsTemp -Days 60 -WhatIf -PassThru
Clear-WindowsTemp -Days 30 -RemoveEmptyDirectory -WhatIf -Verbose -PassThru
Clear-WindowsTemp -Days 30 -RemoveEmptyDirectory -Confirm
```

## Output and failures

With `-PassThru`, return `TheCleaners.CleanupResult`; see [safety and confirmation](safety-and-confirmation.md) for all fields and status values. Enumeration failure aborts without deletion and reports unknown candidate counts. Individual deletion failures use the error stream, continue by default, and respect `-ErrorAction Stop`. Bytes are logical file lengths, not a measured physical free-space change.

The alias `Clean-WindowsTemp` remains available. Windows PowerShell 5.1 is the minimum. See the [release plan](release-plan-1.0.md) for outstanding acceptance work.
