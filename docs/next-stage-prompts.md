# Next-stage prompts

These prompts replace the previously proposed immediate concurrency/lab-preparation stage. Lab validation is deferred future work, not underway. Refresh the summaries and exact identities before each use; do not execute a successor automatically.

## Next: non-lab delivery readiness

**Completed:** TC-002 loader/naming; supported runtime/archive subgates; PR #35 risk review; PR #36 harness/schema/runbook preparation; title-case canonical URL decision; live publishing environment with SamErde review and `v*` tags.

**Remaining:** integrate and validate the planning changes; exact docs deployment; environment credential setup and local publication rehearsal; prerelease metadata, approved publication and published installation. TC-003–007 labs and final TC-001/008/009 release acceptance remain deferred/open.

Recommended model: GPT-6 Astra (`gpt-6-astra`), reasoning effort xhigh.

Continue TheCleaners with the non-lab delivery sequence in `docs/release-plan-1.0.md`. Read `AGENTS.md`, `.github/copilot-instructions.md`, the complete release plan, `docs/deployment-validation.md`, and `docs/publishing.md` before editing. Verify repository identity, remote, branch, worktrees, uncommitted changes and current main. The last completed packet at prompt preparation was PR #36, merge `1af73897b4534dbffb3f0aa647b2d3dc4f7f31a5`, with [build 35227963090](https://github.com/SamErde/TheCleaners/actions/runs/35227963090). That is historical fixture/package evidence only; refresh live state rather than assuming it remains HEAD.

The planning update was prepared in `C:\Users\SamErde\Code\Public\TheCleaners-delivery-plan`, branch `codex/non-lab-release-plan`, with a completion report under `C:\Users\SamErde\Documents\Codex\2026-09-17\TheCleaners-Delivery-Plan`. Inspect its actual commit/diff and integration status. Preserve and integrate any unmerged planning changes before extending them; do not discard them or resume an unrelated prior branch. Use a focused branch/worktree with clear ownership.

Complete the first bundle as a reviewable PR: deploy the exact strict-built MkDocs output once, retain its manifest/digests, and verify deployed bytes and representative navigation at `https://day3bits.com/TheCleaners/`. Keep canonical URL declarations title-case. Lowercase compatibility belongs to Zensical issue #26; do not rename the repository, change domains, or pull that migration into this work.

Reverify `powershell-gallery` required reviewer and tag restrictions and the credential's environment-only scope. The intended workflow uses `PSGALLERY_PUBLISH_API_KEY`; it must not fall back to the older repository secrets or pass credentials to the build matrix. Credential provisioning is a maintainer action through secure GitHub settings/input. Do not read back, log, fabricate or publish credentials. Prepare and verify local-feed publication/install rehearsal and meaningful publisher refusal cases without any real Gallery upload. Keep configuration readback, local rehearsal, and actual release evidence separate.

If the first bundle is small enough to include prerelease preparation, reconcile release/Gallery history, choose an unused proposed prerelease version, and align manifest, release notes and proposed tag. An alpha/preview or beta may explicitly defer labs under the revised plan. Otherwise save preparation as the next bounded stage. Complete all reviewable preparation before requesting final approval for a concrete release. This prompt does not authorize a release tag, Gallery upload or stable maturity label.

Use isolated fixtures only. Preserve PS5.1 minimum and supported Windows PS7 compatibility, quiet imports, owning-command ShouldProcess, file-object-bound temp deletion, and pruning invariants. IIS/Exchange remain explicit-WhatIf and structurally deletion-disabled, with no force/bypass/activation path or 1.0 Exchange AllowRemoval. Do not provision labs, run actual-root cleanup, or resume Windows/IIS/Exchange/profile acceptance. Retain deferred DELETE-PENDING, ROOT-RACE, HANDLE-RECOVERY drivers and schema regression work in the backlog.

Run checks appropriate to changed files and all required repository checks. URL/help changes affect packaged inputs, so obtain fresh exact-commit package/help/import and supported runtime/archive evidence before release. Verify machine-readable totals, failures/skips/not-run, runtime/OS/commit, manifests/digests and actual artifacts; run strict MkDocs, relevant analysis and `git diff --check`. Do not call local dirty-tree results exact-commit hosted evidence or treat skipped/pending jobs as success.

Carry this bounded work through commit/push, focused PR, available reviews, evidence-based corrections/replies, and paginated GraphQL reviewThreads until zero unresolved threads. Reverify applicable checks, approvals and final head immediately before an exact-head guarded merge; do not bypass protection. Verify the merge commit's own required workflows and artifacts, safely synchronize clean main, and save a completion report with exact identities and evidence links. Keep the PR description aligned with the final scope.

Then save the next copy-ready prompt without executing it. Begin it with at most two short **Completed / Remaining** paragraphs, refreshed from the ledger; include the next objective, prerequisites, validation, safety, exact PR/merge/evidence lifecycle and this same successor rule. Explicitly carry TC-003/004 Windows acceptance, TC-005 IIS preview labs, TC-006 Exchange preview labs, TC-007 profiles, TC-001 product/release acceptance and TC-008/009 delivery/final release gates forward. If none remain, state that no successor is needed and cite the completed gates.

## Later: approved prerelease publication and verification

**Completed:** supported runtime/archive subgates, bounded risk review, lab harness preparation, title-case URL decision and publishing environment configuration. Refresh this summary with verified readiness results before use.

**Remaining:** delivery rehearsal and prerelease preparation, then concrete release approval, protected publication and published-install evidence. Labs remain future work; final 1.0 acceptance stays open.

Recommended model: GPT-6 Astra (`gpt-6-astra`), reasoning effort xhigh.

Use this prompt only after the non-lab readiness and metadata stages are verified. Read the current release plan, AGENTS.md and publishing runbook. Refresh both short summary paragraphs with actual completed/remaining items, and read the preceding completion report for the exact commit, version, proposed tag, artifact digest, reports and unresolved limits. Do not invent those values.

Prepare any remaining concrete release materials first. Publish only when the maintainer has explicitly approved that version, tag and artifact and the environment credential is securely provisioned. Existing authorization persists; do not ask again for the same approved release. Approval of a plan alone is not publication approval. Create only the approved matching tag, run the protected exact-artifact workflow, and leave environment approval to the maintainer. Do not bypass controls, rebuild outside the verified release flow or publish from source.

After publication, install the exact Gallery version on fresh Windows runners for PS5.1 and all supported PS7 lines. Check package payload identity, installed version, quiet import, help, exports, aliases and preview locks using isolated fixtures without real cleanup. Account explicitly for Gallery-added metadata. Retain machine-readable evidence and verify every claimed result against the published version and tested source/artifact.

Reconcile release notes/history and ledger status in the same bounded PR. Preserve existing work, use a focused branch/worktree, commit/push, request available reviews, and address material findings with evidence. Read paginated GraphQL reviewThreads and replies until zero unresolved threads. Verify all applicable checks, approvals and final head immediately before an exact-head guarded merge without bypass. Verify the merge commit's own required workflows and artifacts, safely synchronize clean main, and save exact PR/head/merge identities, runtime/OS/totals, artifact hashes, evidence links and remaining gates in a completion report.

The pause point is a verified prerelease and a clear lab backlog. Do not start labs automatically. Keep TC-003–007 acceptance and final TC-001/008/009 release acceptance open. Save a resumption prompt with succinct **Completed / Remaining** paragraphs, exact evidence, missing lab prerequisites and the same summary/successor requirement. Preserve safety and preview locks throughout.
