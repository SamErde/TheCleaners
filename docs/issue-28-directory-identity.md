# Issue #28 directory-identity closure

## Scope and result

This packet closes the remaining deterministic fixture gap in [issue #28](https://github.com/SamErde/TheCleaners/issues/28). The runtime already retains native Windows directory handles through candidate mutation and compares volume/file identity before non-recursive pruning. No runtime defect was found, so this packet adds a dedicated public-command regression suite without changing production behavior.

The initial implementation checkpoint used base commit `af330858b41335366476f0b845e3f73a3c1497d1` plus uncommitted test/documentation changes. It is retained below as historical evidence. The clean metadata-correction checkpoint records local committed fixture validation; final-head hosted CI across all supported runtimes and post-merge evidence remain separate checks.

## Deterministic fixture design

Every test redirects the current-user and Windows temp roots to a unique Pester fixture. `Clear-WindowsTemp` uses a controlled root resolver mock; the original environment is restored after each case. No cleaner targets actual user, Windows, IIS, Exchange, or other product data.

The replacement regressions distinguish two safety layers:

1. The production-reachable test deletes the old candidate, then attempts to move the touched directory aside and install a staged empty or populated replacement at the same path. The fixture requires the first move to throw native sharing violation 32; only a successful first move permits the staged replacement attempt. The retained DELETE-capable handle denies the move, so the replacement cannot occur while the plan remains active. The staged directory and any new file remain intact outside the cleanup root.
2. The defensive identity test uses an explicitly labeled isolated fault injection at the same pre-prune boundary. It releases only the touched directory's retained handle, moves the now-empty original to a displaced path, and installs a real empty or populated directory at the original path. The displaced original stays alive to prevent file-ID reuse. Before reading the replacement identity, the fixture sets its creation time, last-write time, and attributes to the values captured for the planned original and asserts those mutable fields match. The command still observes that the native volume/file identity differs, skips the replacement and its ancestor, and reports no directory-removal failure.

The second case demonstrates defense in depth when the primary handle barrier is unavailable. It is not a claim that production planning normally releases that handle or permits the physical replacement.

## Acceptance mapping

| Issue #28 criterion | Deterministic evidence |
| --- | --- |
| Preserve a touched directory removed and recreated at the same path before pruning | For both public commands, the intact production plan blocks the replacement attempt. The isolated fallback fixture then performs the replacement, verifies different native identities, and preserves the replacement and its ancestor. |
| Verify both temp commands | Every case is parameterized across `Clear-CurrentUserTemp` and `Clear-WindowsTemp`. |
| Cover recreated directories with and without new contents | The fallback fixture installs one empty replacement and one replacement containing `new.tmp` for each command; all four replacements remain. The primary handle test also stages and attempts both payloads. |
| Preserve normal deepest-first pruning | Each command removes an old file, its child directory, and its parent in that order-sensitive plan, with two directory candidates and two removals. |
| Preserve root, unrelated empty branches, recent files, and reparse points | The end-to-end boundary case retains the fixture root, an unrelated empty directory, a recent-file branch, a junction, and the junction target outside the cleanup root. |
| Avoid path/timestamp-only identity proof | Tests use `FILE_ID_INFO` identities from the native interop. The fallback fixture explicitly matches creation time, last-write time, and attributes, then records unequal original and replacement identities while confirming the displaced original retains its planned identity. |
| Keep `ShouldProcess` and error behavior | `-WhatIf` reports candidates and performs no mutation; mutation cases use explicit `-Confirm:$false`; a locked candidate with `-ErrorAction Stop` terminates with `TempFileRemovalFailed` and preserves directory ancestry. |
| Validate the supported runtime matrix | Local coverage passed on PowerShell 7.6.6 and Windows PowerShell 5.1.26100.9444 with Pester 5.7.1. Full-matrix acceptance remains pending inspection of exact final-head hosted results, including PowerShell 7.4.20 and 7.5.11. |

## Validation evidence

Local fixture runs used Windows **10.0.26200.0**, PowerShell **7.6.6** and Windows PowerShell **5.1.26100.9444**, with pinned Pester **5.7.1**. Native interop was initialized before Pester under Windows PowerShell 5.1, matching the hosted workflow's runspace requirement. Each result below belongs only to its stated checkpoint; an older run does not validate a later correction.

| Checkpoint | Result on each local runtime | Scope |
| --- | --- | --- |
| Initial base `af330858b41335366476f0b845e3f73a3c1497d1` plus uncommitted implementation | 14 passed, zero failed/skipped/not-run | Historical initial fixture suite. Reports: `%TEMP%\TheCleaners-issue28-evidence\pester-ps766.xml` and `pester-ps51.xml`. |
| Clean integration `171b4cc558b875f72ffedd68aa051d6aeac6e43e` | 18/18 passed, zero failed/skipped/not-run | Original 14 fixtures plus four documentation contracts; predates the metadata-matching refinement. Strict Zensical 0.0.62 and PR-range whitespace checks also passed. |
| Review base `581907e7d83c283de423c0f36d02b735c7153876` plus uncommitted refinement | 14 passed, zero failed/skipped/not-run | Historical first run with matching replacement metadata; reports `pester-review-followup-ps766.xml` and `pester-review-followup-ps51.xml` in the same temporary evidence directory. |
| Clean correction `2372a218d04354df100c2d9188bc30c419764151` | 18/18 passed, zero failed/skipped/not-run | Includes the metadata-matching assertions and four documentation contracts. Retained reports: `issue28-final2372-ps7.json/.xml` and `issue28-final2372-ps51.json/.xml`. Test-file SHA-256: `d6f2c31c5625cec86cabee0fb5d9f856a40ed2f43ff3e479dbe326a2a8f8a6fa`. Strict Zensical 0.0.62 passed. |

The clean correction's hosted build failed test-source analysis because two display-only `Article` parameters were unused; it did not pass the full build. Commit `da99d4ebdd0e8c76cba332eb506e06d2eda43691` removed those unused parameters and simplified the test descriptions without changing fixture logic. Its PowerShell parsers and PR-range whitespace check passed. Final-head hosted runtime reports, artifact inspection and post-merge results remain separate gates and are recorded in the PR and release ledger when verified.

## Limitations
This is deterministic local NTFS fixture evidence, not Windows client/server, ReFS, real-system-root, elevated/non-elevated, hostile-filter, or product lab acceptance. Issue #28 does not require ReFS validation, and the production help already states that the checks cannot provide an atomic defense when a filesystem or filter does not provide stable file IDs. Deferred lab gates and final 1.0 acceptance remain open.
