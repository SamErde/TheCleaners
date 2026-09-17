# Next-stage prompt

The non-lab delivery sequence is complete. Lab validation remains deferred future work and is not underway. Use this prompt only after the maintainer explicitly resumes labs and identifies approved disposable hosts and scenarios.

## Next: resume deferred product labs when directed

**Completed:** Non-lab delivery readiness, exact documentation deployment, supported runtime/archive validation, protected `0.0.15-beta` publication from source `345f06c861b6d4074e5896e0b27a19f869dfa7e3`, and fresh Gallery-install verification across Windows PowerShell 5.1 and supported PowerShell 7 releases.

**Remaining:** Deferred TC-003/004 Windows acceptance, TC-005 IIS preview labs, TC-006 Exchange preview labs, TC-007 profile acceptance, and final TC-001/008/009 product and 1.0 release acceptance. Labs require new maintainer direction and approved disposable hosts.

Recommended model: GPT-5.6 Sol (`gpt-5.6-sol`), reasoning effort high. Use Luna at medium effort for bounded host/evidence inventory and Sol at medium or high effort for isolated implementation and review. Escalate to Astra only for concrete unresolved safety risk or complexity.

Continue TheCleaners from `docs/release-plan-1.0.md` only after the maintainer explicitly resumes deferred lab work. Read `AGENTS.md`, `.github/copilot-instructions.md`, the complete release plan, `docs/lab-acceptance.md`, and the retained non-lab completion and publication evidence before editing. Verify repository identity, current main, worktrees, uncommitted changes, the requested lab packet, named disposable hosts, snapshot/reset prerequisites, and exact source under test.

Treat `0.0.15-beta` as prerelease/process evidence only. Its protected publication run is [35268852573](https://github.com/SamErde/TheCleaners/actions/runs/35268852573); the exact published source remains `345f06c861b6d4074e5896e0b27a19f869dfa7e3`, tag `v0.0.15-beta`, and approved archive SHA-256 `1c8e061278e68c2e1537186709f79606735c6dda2e48b5cf65a4a877699e3383`. Refresh external state and retained evidence rather than inferring product acceptance from package installation.

Resume only the bounded lab packet the maintainer names. The retained order is TC-003/004 Windows client/server, token, filesystem, actual-root and concurrency acceptance; TC-005 disposable IIS preview validation; TC-006 disposable Exchange preview validation; and TC-007 profile inventory/sizing acceptance. Do not provision a host or begin another packet automatically.

Never run a cleaner against real user, Windows, IIS, or Exchange data. Use approved disposable hosts with verified snapshot/reset and bounded roots. Keep IIS and Exchange structurally preview-only: explicit `-WhatIf` is required before discovery, and no deletion call, generic helper, force/bypass flag, preference override, persistent activation, or 1.0 Exchange `-AllowRemoval` is permitted. Stop on unknown state and preserve evidence for recovery.

For each authorized case, record exact source, OS/product/runtime build, elevation/token, filesystem, roots and identities, complete before/after inventories, expected and actual results, errors, service health, evidence hashes, cleanup outcome, and snapshot recovery. A harness `Acceptance=true` validates only that isolated case. Do not generalize fixture, package, or one-host results into product or final release acceptance.

Use a focused branch/worktree with explicit ownership. Run the applicable exact-source checks, keep machine-readable evidence, and distinguish candidate, PR-head, merged-commit, and lab-host identities. Carry reviewable work through the repository's normal commit, PR, review-thread, exact-head merge, and post-merge verification lifecycle without bypassing protection.

Save the next copy-ready prompt without executing it automatically. Begin it with concise **Completed / Remaining** paragraphs refreshed from the ledger, include the next bounded objective and prerequisites, and preserve this successor rule. Final 1.0 requires its own complete product, artifact, metadata, approval, publication, and installed-package evidence; the beta does not close those gates.
