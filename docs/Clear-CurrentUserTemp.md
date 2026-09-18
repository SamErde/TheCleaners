# Clear-CurrentUserTemp

## Synopsis

Remove old files from the current user's Windows temporary directory. This command remains prerelease.

## Syntax

```powershell
Clear-CurrentUserTemp [-Days <Int16>] [-RemoveEmptyDirectory] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Behavior

Resolve the temporary directory using `[System.IO.Path]::GetTempPath()` on Windows. Select files of any extension whose `LastWriteTimeUtc` is at or before one UTC cutoff. `-Days` defaults to 30 and accepts positive Int16 values. Reparse points are excluded before traversal. Literal paths, ancestry, type, identity, and timestamps are revalidated before removal. The native deletion handle requests `DELETE` and `FILE_READ_ATTRIBUTES` without file-content read access and without sharing writes or deletes, so the final timestamp is read from the opened object and an ordinary content/data writer or rename cannot move the candidate after validation.

Retention and byte totals use metadata observed from the deletion handle. The same object can remain eligible after a content change if its observed timestamp is still old. Read-only sharing blocks data writers and renames, but attribute-only timestamp changes can still occur after the observation; the retention check and deletion are not atomic. See the [full retention contract and regression evidence](issue-30-retention-handle.md).

Without `-RemoveEmptyDirectory`, directories remain untouched. With it, only prune directories emptied by the current invocation and their now-empty ancestors. Never remove the root or unrelated pre-existing empty branches. Recent files prevent their containing directories from being removed. The previous `-TimeOut` parameter is removed; pruning is a single deepest-first pass.

`-WhatIf` makes no filesystem changes and reports the proposed batch. `-Verbose` lists candidate paths. `-Confirm` prompts for approval of the discovered file/directory plan once at the root and lets the caller accept or decline it. No Force or separate ShouldContinue prompt is implemented.

## Examples

```powershell
Clear-CurrentUserTemp -Days 30 -WhatIf -PassThru
Clear-CurrentUserTemp -Days 30 -RemoveEmptyDirectory -WhatIf -Verbose -PassThru
Clear-CurrentUserTemp -Days 30 -RemoveEmptyDirectory -Confirm
```

## Output and failures

Normal success is quiet unless `-PassThru` is requested. It returns `TheCleaners.CleanupResult`; see [command contracts](command-contracts.md) for all fields, statuses, and stable error IDs. Preview counts never count as successful removals. Enumeration failure aborts without deletion and reports unknown candidate counts. Individual deletion errors continue by default and respect `-ErrorAction Stop`.

The alias `Clean-CurrentUserTemp` remains available. Windows only; Windows PowerShell 5.1 is the minimum. The remaining client/server, elevation, and filesystem acceptance gates are tracked in the [release plan](release-plan-1.0.md).
