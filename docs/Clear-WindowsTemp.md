# Clear-WindowsTemp

## Synopsis

Remove old files from `SystemRoot\Temp` on Windows. This command remains prerelease.

## Syntax

```powershell
Clear-WindowsTemp [-Days <Int16>] [-RemoveEmptyDirectory] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Behavior

Select files of any extension whose `LastWriteTimeUtc` is at or before one UTC cutoff. `-Days` defaults to 30 and accepts positive Int16 values. Reparse points are excluded before traversal. Literal paths, ancestry, type, identity, and timestamps are revalidated before removal. The native deletion handle requests `DELETE` and `FILE_READ_ATTRIBUTES` without file-content read access and without sharing writes, so the final timestamp is read from the opened object and an active writer is not removed after the timestamp check. The Windows temp root is derived from the Windows special-folder API with a SystemRoot fallback, not from an environment variable alone. Run elevated for system-owned files; actual OS-root acceptance remains a 1.0 gate.

Without `-RemoveEmptyDirectory`, directories remain untouched. With it, only prune directories emptied by the current invocation and their now-empty ancestors, deepest-first. Never remove the root or unrelated pre-existing empty branches. A retained file prevents pruning its directory.

`-WhatIf` makes no filesystem changes and reports the proposed batch. `-Verbose` lists candidate paths. `-Confirm` prompts for approval of the discovered file/directory plan at the root and lets the caller accept or decline it. ConfirmImpact is Medium. No Force or separate ShouldContinue prompt is implemented.

## Examples

```powershell
Clear-WindowsTemp -Days 60 -WhatIf -PassThru
Clear-WindowsTemp -Days 30 -RemoveEmptyDirectory -WhatIf -Verbose -PassThru
Clear-WindowsTemp -Days 30 -RemoveEmptyDirectory -Confirm
```

## Output and failures

With `-PassThru`, return `TheCleaners.CleanupResult`; see [command contracts](command-contracts.md) for all fields, statuses, and stable error IDs. Enumeration failure aborts without deletion and reports unknown candidate counts. Individual deletion failures use the error stream, continue by default, and respect `-ErrorAction Stop`. Bytes are logical file lengths, not a measured physical free-space change.

The alias `Clean-WindowsTemp` remains available. Windows PowerShell 5.1 is the minimum. See the [release plan](release-plan-1.0.md) for outstanding acceptance work.
