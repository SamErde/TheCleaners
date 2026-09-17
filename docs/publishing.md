# Publishing controls and prerelease evidence

Use the `powershell-gallery` GitHub environment for publication. GitHub environments support required approval, deployment branch/tag restrictions, and gated access to environment secrets. These controls suit an irreversible package upload; a workflow's environment name alone does not configure them. See [GitHub's environment guidance](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments).

## Verified configuration

On September 17, 2026, the maintainer authorized resolving the missing environment. Live REST reads after configuration confirmed:

| Control | State |
| --- | --- |
| Environment | `powershell-gallery` exists in `SamErde/TheCleaners`. |
| Required reviewer | `SamErde`. Approval must be given by the maintainer for the concrete release. |
| Self-review | Permitted, so the sole configured maintainer can approve a manually initiated release. This is not a second-person approval policy. |
| Administrator bypass | Disabled. Administrators must use the required environment approval rather than forcing a waiting deployment. |
| Deployment refs | Custom policies with one tag rule, `v*`, and no branch rule. The publisher additionally checks the full version/tag/prerelease match. |
| Publishing credential | `PSGALLERY_PUBLISH_API_KEY` is present as an environment secret, confirmed by a September 17 metadata-only read after maintainer provisioning. Its value was not inspected; successful protected run 35268852573 established its authorization for the package upload. |
| Build access | The reusable build matrix does not inherit repository secrets. Only the publishing step maps the dedicated secret into its process environment. |
| Execution evidence | Protected run [35268852573](https://github.com/SamErde/TheCleaners/actions/runs/35268852573) exercised the required environment approval, exact-artifact publisher, Gallery credential, and fresh installed-package matrix. Independent verification passed every check across 11 jobs, 15 retained artifact wrappers and four installed-package reports. |

`Publish.yml` maps only the dedicated environment secret and fails clearly when it is missing. Select a tag whose workflow uses these controls; do not dispatch a historical workflow that references the older repository secret. Reverify environment settings and the selected tag's workflow before any publication; repository settings can change independently of Git commits.

## Credential provisioning

The maintainer provisioned `PSGALLERY_PUBLISH_API_KEY` under **Settings → Environments → powershell-gallery → Environment secrets**. Keep that name only at environment scope and never paste the key into issues, logs, prompts, or source files. Metadata readback confirms presence; the successful approved publication established that the replacement key could publish this package. The workflow stops when the key is absent.

Existing repository secret names `POWERSHELLGALLERY_KEY` and `POWERSHELLGALLERY_THECLEANERS` were observed before publication, but their values and validity were not inspected. GitHub does not return stored secret values. After the environment credential published successfully and a fresh consumer check found no remaining use, both obsolete repository secret entries were removed. A metadata readback at 20:26:05 UTC on September 17, 2026 confirmed that no repository secrets remained and the dedicated environment secret was preserved. No secret value was read, and this repository cleanup does not claim revocation in any external system.

## Non-lab release sequence

1. Reconcile published versions and release history; prepare an unused prerelease version and matching manifest, proposed tag, and release notes. State that lab validation is deferred future work, not underway. Keep IIS and Exchange structurally preview-only.
2. Rehearse package verification and publish/install against an isolated local feed. Verify rejection of missing credentials, non-tag refs, mismatched versions/commits, duplicate versions, and altered artifact contents. Avoid real Gallery uploads during rehearsal. Microsoft recommends [testing publication with a local repository](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines).
3. Run the required supported Windows PowerShell matrix against the exact candidate. Retain artifact content manifests, hashes, reports, runtime versions, and the tested commit. Source-help URL changes affect packaged bytes; do not reuse old archive hashes for a new candidate.
4. Present the concrete version, commit, tested artifact, release notes and unresolved lab limits for maintainer approval. This plan is not permission to create a tag or publish.
5. After approval, create the agreed matching release tag and manually dispatch the publishing workflow for that tag with `approved_archive_sha256` set to the approved archive digest. The full release matrix must pass before the environment-gated job can publish its exact tested artifact; the upload also refuses an archive whose digest differs from the approved value. Never bypass environment review or other applicable protection.
6. Install the exact published Gallery version in fresh Windows CI environments across the supported runtimes. Verify the module payload against the tested content manifest, accounting explicitly for Gallery-added packaging metadata; also verify quiet import, exports, aliases, help and preview locks without live cleanup. Retain version/commit-bound reports and mark only that prerelease's publication/install gates validated.

## Local rehearsal and retained evidence

From a clean tracked worktree, build the exact candidate and then run:

```powershell
Invoke-Build -File ./src/TheCleaners.build.ps1
./.github/scripts/Invoke-LocalPublicationRehearsal.ps1 -ArtifactPath ./src/Artifacts -ArchiveDirectory ./src/Archive -OutputPath ./src/Reports/LocalPublicationRehearsal.json
```

The rehearsal requires the content manifest's commit to match the current checkout. It rejects tracked changes and any untracked module source file, including ignored files that the package copy would otherwise include. It creates a unique local feed and module search root, invokes the real publisher in a fresh instance of the current PowerShell runtime, saves the exact version, checks its payload and runtime contract, and verifies that a second publication is refused. Synthetic tag variables exist only inside the worker process; no Git tag or Gallery upload is created. The report records source/version/runtime identity, package digests, completed checks and cleanup outcomes. CI requires this rehearsal in the canonical PowerShell 7.6.6 build lane and retains its report with the Pester artifacts.

The shared repository-module checker accepts only the tested payload plus PowerShellGet's root `PSGetModuleInfo.xml` file. Every payload length and SHA-256 must match the tested manifest. Exact-path and module-name imports must resolve the same copy quietly, help and exports must remain intact, and IIS/Exchange must refuse calls without explicit `-WhatIf` before discovery. Local `Save-Module` acquisition exercises repository packaging; only the post-publication `Install-Module` matrix establishes real Gallery installation evidence.

PR #37's exact merge `345f06c861b6d4074e5896e0b27a19f869dfa7e3` passed [build 35257555108](https://github.com/SamErde/TheCleaners/actions/runs/35257555108). Its PowerShell 7.6.6 rehearsal published `0.0.15-beta` to an isolated local repository, acquired and verified the 19-file payload plus `PSGetModuleInfo.xml`, checked import/help/exports/aliases and preview locks, refused a duplicate version, and restored the environment and temporary repository. The tested archive was 224,050 bytes with SHA-256 `1c8e061278e68c2e1537186709f79606735c6dda2e48b5cf65a4a877699e3383`. The maintainer approved that exact source, tag and digest for publication.

The first approved attempt, [run 35266399326](https://github.com/SamErde/TheCleaners/actions/runs/35266399326), passed all six release-gate jobs and normal environment review, then failed closed when PowerShell Gallery returned HTTP 403 for the credential. The exact Gallery version still returned 404 afterward, and the installed-package jobs were skipped. The environment secret was replaced without changing the approved tag, source, or archive.

## 0.0.15-beta publication evidence

Protected run [35268852573](https://github.com/SamErde/TheCleaners/actions/runs/35268852573) checked out tag `v0.0.15-beta` at source `345f06c861b6d4074e5896e0b27a19f869dfa7e3`, reran the full supported matrix, matched the approved archive SHA-256, and published Gallery version [`0.0.15-beta`](https://www.powershellgallery.com/packages/TheCleaners/0.0.15-beta) through the reviewed environment at 20:20:11 UTC on September 17, 2026. Separate fresh Windows jobs installed the exact Gallery version on Windows PowerShell 5.1 and PowerShell 7.4.20, 7.5.11, and 7.6.6. They verified payload identity, allowed Gallery metadata, quiet import, exports, aliases, help, and IIS/Exchange preview locks without live cleanup. Independent verification passed all checks across 11 jobs, 15 retained artifact wrappers and four installed-package reports.

The matching [GitHub prerelease](https://github.com/SamErde/TheCleaners/releases/tag/v0.0.15-beta), release ID `391037563`, was published at 20:27:02 UTC. It is not a draft, resolves through tag `v0.0.15-beta` to the same source, and retains three downloaded, byte-matched assets: the 224,050-byte archive above; the 3,684-byte content manifest with SHA-256 `6454b46738291fce94eeca2d23d4092eb3f3957485ede75a81186455980dfac9`; and its 88-byte sidecar with SHA-256 `3346fccaeabaeec2eee9dcfd427fb1cd27c34ae51a3631258c0c3f0a49da8485`.

This closes publication and installed-artifact verification only for `0.0.15-beta`. Final 1.0 acceptance still requires its applicable product gates, maintainer approval, final metadata, and fresh publication/install evidence. Local-feed rehearsal and prerelease delivery do not establish Windows, IIS, Exchange, or profile lab acceptance. See the [release plan](release-plan-1.0.md) and [next-stage prompts](next-stage-prompts.md).
