# Issue #28 directory-identity closure

## Scope and result

This packet closes the remaining deterministic fixture gap in [issue #28](https://github.com/SamErde/TheCleaners/issues/28). The runtime already retains native Windows directory handles through candidate mutation and compares volume/file identity before non-recursive pruning. No runtime defect was found, so this packet adds a dedicated public-command regression suite without changing production behavior.

The local evidence applies to base commit `af330858b41335366476f0b845e3f73a3c1497d1` plus the uncommitted changes in `src/Tests/Unit/TempDirectoryIdentity.Tests.ps1` and this document. It does not claim an exact candidate commit. Exact-head CI and post-merge evidence remain separate checks.

## Deterministic fixture design

Every test redirects the current-user and Windows temp roots to a unique Pester fixture. `Clear-WindowsTemp` uses a controlled root resolver mock; the original environment is restored after each case. No cleaner targets actual user, Windows, IIS, Exchange, or other product data.

The replacement regressions distinguish two safety layers:

1. The production-reachable test deletes the old candidate, then attempts to move the touched directory aside and install a staged empty or populated replacement at the same path. The retained DELETE-capable handle denies the move, so the replacement cannot occur while the plan remains active. The staged directory and any new file remain intact outside the cleanup root.
2. The defensive identity test uses an explicitly labeled isolated fault injection at the same pre-prune boundary. It releases only the touched directory's retained handle, moves the now-empty original to a displaced path, and installs a real empty or populated directory at the original path. The displaced original stays alive to prevent file-ID reuse. The command opens the replacement, observes that its native volume/file identity differs from the planned identity, skips it and its ancestor, and reports no directory-removal failure.

The second case demonstrates defense in depth when the primary handle barrier is unavailable. It is not a claim that production planning normally releases that handle or permits the physical replacement.

## Acceptance mapping

| Issue #28 criterion | Deterministic evidence |
| --- | --- |
| Preserve a touched directory removed and recreated at the same path before pruning | For both public commands, the intact production plan blocks the replacement attempt. The isolated fallback fixture then performs the replacement, verifies different native identities, and preserves the replacement and its ancestor. |
| Verify both temp commands | Every case is parameterized across `Clear-CurrentUserTemp` and `Clear-WindowsTemp`. |
| Cover recreated directories with and without new contents | The fallback fixture installs one empty replacement and one replacement containing `new.tmp` for each command; all four replacements remain. The primary handle test also stages and attempts both payloads. |
| Preserve normal deepest-first pruning | Each command removes an old file, its child directory, and its parent in that order-sensitive plan, with two directory candidates and two removals. |
| Preserve root, unrelated empty branches, recent files, and reparse points | The end-to-end boundary case retains the fixture root, an unrelated empty directory, a recent-file branch, a junction, and the junction target outside the cleanup root. |
| Avoid path/timestamp-only identity proof | Tests use `FILE_ID_INFO` identities from the native interop. The fallback fixture records unequal original and replacement identities while confirming the displaced original retains its planned identity. |
| Keep `ShouldProcess` and error behavior | `-WhatIf` reports candidates and performs no mutation; mutation cases use explicit `-Confirm:$false`; a locked candidate with `-ErrorAction Stop` terminates with `TempFileRemovalFailed` and preserves directory ancestry. |
| Validate supported local runtime boundaries | The dedicated 14-test suite passed under PowerShell 7.6.6 and Windows PowerShell 5.1.26100.9444 with Pester 5.7.1. |

## Validation evidence

Validation ran on Microsoft Windows NT 10.0.26200.0 using isolated NTFS fixtures. Native interop was initialized before Pester under Windows PowerShell 5.1, matching the hosted workflow's runspace requirement.

| Runtime | Pester | Result | Counts | Machine-readable report |
| --- | --- | --- | --- | --- |
| PowerShell 7.6.6 Core | 5.7.1 | Passed | 14 passed, 0 failed, 0 skipped, 0 not run | `%TEMP%\TheCleaners-issue28-evidence\pester-ps766.xml` |
| Windows PowerShell 5.1.26100.9444 Desktop | 5.7.1 | Passed | 14 passed, 0 failed, 0 skipped, 0 not run | `%TEMP%\TheCleaners-issue28-evidence\pester-ps51.xml` |

Both PowerShell parsers accepted the dedicated test file. `git diff --cached --check` passed after staging both owned files; exact-head checks must be repeated after the packet is committed or rebased.

## Limitations

After integration on issue #30's merge, exact clean commit `171b4cc558b875f72ffedd68aa051d6aeac6e43e` passed **18/18** tests (14 new cases and four documentation contracts) on PowerShell **7.6.6** and Windows PowerShell **5.1.26100.9444**, with Pester **5.7.1** on Windows **10.0.26200.0**. Both runs had zero failures/skips/not-run; strict Zensical **0.0.62** and the full PR-range whitespace check passed. This is local committed evidence; the PR's exact final-head hosted reports and post-merge results are verified separately.

This is deterministic local NTFS fixture evidence, not Windows client/server, ReFS, real-system-root, elevated/non-elevated, hostile-filter, or product lab acceptance. Issue #28 does not require ReFS validation, and the production help already states that the checks cannot provide an atomic defense when a filesystem or filter does not provide stable file IDs. Deferred lab gates and final 1.0 acceptance remain open.
