# Publishing controls and prerelease readiness

Use the `powershell-gallery` GitHub environment for publication. GitHub environments support required approval, deployment branch/tag restrictions, and gated access to environment secrets. These controls suit an irreversible package upload; a workflow's environment name alone does not configure them. See [GitHub's environment guidance](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments).

## Verified configuration

On September 17, 2026, the maintainer authorized resolving the missing environment. Live REST reads after configuration confirmed:

| Control | State |
| --- | --- |
| Environment | `powershell-gallery` exists in `SamErde/TheCleaners`. |
| Required reviewer | `SamErde`. Approval must be given by the maintainer for the concrete release. |
| Self-review | Permitted, so the sole configured maintainer can approve a manually initiated release. This is not a second-person approval policy. |
| Deployment refs | Custom policies with one tag rule, `v*`, and no branch rule. The publisher additionally checks the full version/tag/prerelease match. |
| Publishing credential | `PSGALLERY_PUBLISH_API_KEY`, to be configured only as an environment secret. It was not present at this verification. |
| Build access | The reusable build matrix does not inherit repository secrets. Only the publishing step maps the dedicated secret into its process environment. |
| Execution evidence | Publication and an actual environment approval have not been exercised. Configuration readback alone does not prove those gates. |

The repository changes accompanying this record wire the dedicated secret and a clear missing-key failure into `Publish.yml`. Until those changes merge, `main` still references the older repository secret name. Do not dispatch publication from that older workflow. Reverify environment settings and the selected tag's workflow before any publication; repository settings can change independently of Git commits.

## Credential provisioning

Before publication, the maintainer must add a valid, appropriately scoped Gallery publishing key under **Settings → Environments → powershell-gallery → Environment secrets**, using the exact name `PSGALLERY_PUBLISH_API_KEY`. Do not put that name at repository or organization scope, and never paste the key into issues, logs, prompts, or source files. The workflow stops when the key is absent.

Existing repository secret names `POWERSHELLGALLERY_KEY` and `POWERSHELLGALLERY_THECLEANERS` were observed, but their values and validity were not inspected. GitHub does not return stored secret values. Provision the environment key through the settings UI or secure local input; do not attempt to retrieve an existing secret through workflow output. Review remaining consumers and retire obsolete repository credentials as part of credential setup. Their retirement is not claimed by this planning update.

## Non-lab release sequence

1. Reconcile published versions and release history; prepare an unused prerelease version and matching manifest, proposed tag, and release notes. State that lab validation is deferred future work, not underway. Keep IIS and Exchange structurally preview-only.
2. Rehearse package verification and publish/install against an isolated local feed. Verify rejection of missing credentials, non-tag refs, mismatched versions/commits, duplicate versions, and altered artifact contents. Avoid real Gallery uploads during rehearsal. Microsoft recommends [testing publication with a local repository](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines).
3. Run the required supported Windows PowerShell matrix against the exact candidate. Retain artifact content manifests, hashes, reports, runtime versions, and the tested commit. Source-help URL changes affect packaged bytes; do not reuse old archive hashes for a new candidate.
4. Present the concrete version, commit, tested artifact, release notes and unresolved lab limits for maintainer approval. This plan is not permission to create a tag or publish.
5. After approval, create the agreed matching release tag and manually dispatch the publishing workflow for that tag. The full release matrix must pass before the environment-gated job can publish its exact tested artifact. Never bypass environment review or other applicable protection.
6. Install the exact published Gallery version in fresh Windows CI environments across the supported runtimes. Verify the module payload against the tested content manifest, accounting explicitly for Gallery-added packaging metadata; also verify quiet import, exports, aliases, help and preview locks without live cleanup. Retain version/commit-bound reports and mark only that prerelease's publication/install gates validated.

Final 1.0 acceptance still requires its applicable product gates, maintainer approval, final metadata and fresh publication/install evidence. Local-feed rehearsal and prerelease delivery do not establish Windows, IIS, Exchange or profile lab acceptance. See the [release plan](release-plan-1.0.md) and [next-stage prompts](next-stage-prompts.md).
