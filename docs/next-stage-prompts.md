# Next-stage prompt

## Next: complete issue #26 review and deployment acceptance

**Completed:** Non-lab delivery and protected `0.0.15-beta` publication are verified. The Zensical 0.0.62 migration is implemented and locally validated with classic navigation, generated references, strict link checks, and the existing single-build exact-byte deployment controls.

**Remaining:** Review and merge issue #26, verify its exact deployed bytes, and resolve the hosting-level lowercase route. Narrow deterministic fixture/contract criteria in [#28](https://github.com/SamErde/TheCleaners/issues/28), [#29](https://github.com/SamErde/TheCleaners/issues/29), and [#30](https://github.com/SamErde/TheCleaners/issues/30) remain unexecuted; product labs stay paused.

Recommended model: GPT-5.6 Sol (`gpt-5.6-sol`), reasoning effort high. Use a different model for independent review when practical; escalate to Astra only for a concrete unresolved deployment or URL-routing risk.

Continue TheCleaners from `docs/release-plan-1.0.md`. Read `AGENTS.md`, `.github/copilot-instructions.md`, the complete release plan, issue #26, and `docs/deployment-validation.md`. Verify repository identity, the exact candidate head, worktrees, uncommitted changes, and current pull-request state before writing.

Review the migration without changing runtime/package behavior or the published `0.0.15-beta` tag and source. Confirm that `zensical.toml` preserves the documented navigation and classic presentation, Zensical 0.0.62 is the only direct documentation dependency, strict validation passes, generated command references remain readable, and Read the Docs plus GitHub Pages use the supported build interface.

Preserve the delivery chain: one strict clean build into configured `site_dir`, add `.nojekyll`, create and retain the source/run-bound manifest, recheck the downloaded site, copy the exact checked bytes to `gh-pages`, and verify every public file plus representative navigation with bounded whole-attempt retries. Do not replace the existing hosting backend or weaken permissions, immutable action pins, manifest checks, or fail-closed behavior.

Resolve all material review threads and require green exact-head checks. After merge, verify the exact merged-source build and retained artifacts before claiming deployment acceptance. Test `https://day3bits.com/TheCleaners/` and representative deep links. Lowercase `/thecleaners/` currently resolves at the account-site host before the project site and cannot be fixed by Zensical's docs-relative redirect maps. Do not emit case-only alias directory pairs on Windows. Evaluate the separately owned account-root redirect as a companion hosting change, preserving suffixes and the title-case canonical URL without loops.

Treat the prior MkDocs deployment for source `345f06c861b6d4074e5896e0b27a19f869dfa7e3` as historical evidence only. A local build or PR-head run does not prove the migrated public site. Record exact source, workflow run and attempt, artifact-wrapper digests, file count/bytes/tree hash, `gh-pages` commit, navigation results, URL-case results, and browser observations for the merged deployment.

Lab validation remains deferred future work and is not underway. Do not provision a host or begin TC-003 through TC-007 automatically. Keep IIS and Exchange structurally preview-only and preserve final TC-001/008/009 product and 1.0 acceptance as open gates.

Save the next copy-ready prompt without executing it automatically. Begin it with concise **Completed / Remaining** paragraphs refreshed from the ledger. After issue #26 and its hosting follow-up are resolved, refresh the open-issue audit and select one bounded #28/#29/#30 deterministic regression/contract packet. Product labs still require new maintainer direction and approved disposable hosts.
