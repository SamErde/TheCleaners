# TheCleaners contributor and agent contract

Read `docs/release-plan-1.0.md` before changing behavior. It is the implementation ledger, not a claim that every feature is finished. Follow `.github/copilot-instructions.md` for PowerShell style: approved verbs, PascalCase, OTBS, help, explicit error handling, and tests.

## Safety invariants

- Windows PowerShell 5.1 is the minimum. Support Microsoft-supported PowerShell 7 releases on Windows; do not introduce newer syntax into runtime code.
- Never run a cleaner against real user, Windows, IIS, or Exchange data during development. Use isolated fixture paths or mocks. Server acceptance requires a disposable lab and recorded evidence.
- IIS and Exchange are structurally preview-only until their product-specific gates pass. Require explicit `-WhatIf` before discovery. No deletion command, native deletion call, generic deletion helper, force flag, preference override, or persistent activation is permitted in either preview implementation.
- The tentative later-minor Exchange `-AllowRemoval` design is per invocation, not an activation setting. Do not add it in the 1.0 work or describe it as a finalized permanent contract.
- Public cleanup commands own mutations. The legacy `Remove-OldFiles` wrapper and its tests are retired; never reintroduce a generic mutation layer or add new callers to that retired contract.
- Temp directory removal requires `-RemoveEmptyDirectory`. Only prune directories emptied by that invocation and their now-empty ancestors. Preserve roots, unrelated empty branches, recent files, and reparse points.
- Temp candidate deletion must be file-specific and bound to an opened file object. Do not reintroduce provider `Remove-Item` for candidate files; a missing candidate must be skipped, and a directory substitution must never be deleted or counted as a successful file removal.
- Every mutation must be covered by the owning command's `ShouldProcess` decision. Never weaken WhatIf/Confirm tests to make a refactor pass.
- Discovery failure is not an empty successful result. Report failures through PowerShell's error stream and honor `-ErrorAction Stop`.
- Module import must be quiet, deterministic, and free of caller-scope initialization.
- Do not mark commands stable, merge a release, create a release tag, or publish to the Gallery without the applicable gates and maintainer approval.

## Work ownership and parallelism

Parallelize only independent work with separate branches/worktrees and explicit file ownership. One integrator owns the loader, manifest, shared path helper, build/publish scripts, and current shared test files. IIS and Exchange contributors should add their own test files rather than editing the shared suite concurrently. Documentation navigation and generated references are integrated after command signatures settle. Run read-only analyses independently; serialize writes to a shared branch.

## Closing work

For each packet, update its status, relevant help/docs, changelog, tests, and evidence links in the same PR. Use `implemented in draft`, `validated`, and `merged` distinctly. Do not mark a checkbox complete solely because code was generated or a workflow file exists. Record runtime version, tested commit, test totals/failures/skips, and lab limitations. Keep Zensical migration in issue #26.

Canonical documentation URL: `https://day3bits.com/TheCleaners/`.
