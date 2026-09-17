# Documentation deployment gate

The canonical documentation URL is `https://day3bits.com/TheCleaners/`, including the title-case path. Configuration, source help, the manifest, generated references, and canonical links must use that casing. Support for the lowercase path remains deferred to [Zensical migration issue #26](https://github.com/SamErde/TheCleaners/issues/26).

A documentation deployment is accepted only when the workflow proves all of the following for one source commit:

1. MkDocs completes one strict build.
2. The retained site manifest records every built file's relative path, byte count, and SHA-256 digest, plus a digest for the complete file set and the source repository, commit, ref, workflow run, and attempt.
3. The deployment consumes the retained site artifact and verifies it locally against that manifest before publishing.
4. The `gh-pages` publisher copies that directory without asking MkDocs to build again. The only branch control file added by the publisher is the empty `.nojekyll` file.
5. Every public file returned by `https://day3bits.com/TheCleaners/` has the recorded byte count and SHA-256 digest. Directory index files are requested through their public trailing-slash routes.
6. The home page retains its title-case canonical declaration and links to representative function, contract, support, migration, and release-plan pages.

A local build, a `gh-pages` push, an HTTP 200 response, or a green Pages deployment does not establish this complete chain by itself.

## Workflow contract

The `Deploy MkDocs to GitHub Pages` workflow has three jobs with separate permissions:

| Job | Repository permission | Responsibility |
| --- | --- | --- |
| `build` | `contents: read` | Test the delivery helpers, build once with `python -m mkdocs build --strict --site-dir site`, create the byte manifest, and retain the site plus manifest for 90 days. |
| `deploy` | `contents: write` | Download and recheck the retained site, then use pinned `ghp-import` 2.1.0 to commit and push those files to the existing `gh-pages` branch. This is the only job with write access. |
| `verify` | `contents: read` | Download the same manifest, compare every deployed file with bounded retries, validate representative navigation, and retain the result for 90 days. |

The workflow uses the repository-scoped `GITHUB_TOKEN` through the checked-out remote. It does not require a separate deployment secret and does not change the repository's existing GitHub Pages hosting source. All third-party actions are pinned to full commit SHAs.

The site artifact is named `mkdocs-site-<source-commit>`. It contains the complete `site` directory and `deployment-evidence/site-manifest.json`. The later `mkdocs-deployment-verification-<source-commit>` artifact contains that manifest and `deployment-report.json`. The report records the source identity, content-tree digest, `gh-pages` commit, canonical URL, required navigation routes, number of attempts used, and final pass or failure.

## Propagation and failure behavior

GitHub Pages and its cache can briefly serve the preceding deployment after the branch push. The verifier therefore retries only files that have not matched. Each request asks for identity encoding and carries the source commit and attempt number as cache-busting query parameters. The production workflow permits six attempts with delays of 5, 10, 20, 30, and 30 seconds.

Verification fails closed when any file remains missing, redirects to a differently cased path, has the wrong length or SHA-256 digest, or returns an unexpected status. It also fails when the exact home page omits its canonical path or any required navigation link. A stale deployment can pass only after every recorded file matches the retained build. The workflow does not update release-plan status automatically; merge-commit workflow evidence must be reviewed and recorded separately.

Representative navigation covers:

- `Get-TheCleaners/`
- `support-matrix/`
- `command-contracts/`
- `migration-to-1.0/`
- `release-plan-1.0/`

The byte comparison includes every other generated page and asset as well. The navigation list is a focused structural check, not a limit on byte verification.

## Local validation

The helper tests use only Python's standard library, isolated temporary directories, and a local HTTP server. They cover exact binary content, downloaded-tree verification, duplicate and symbolic-link rejection, retry after stale content, permanent wrong-byte failure, and missing navigation.

From the repository root, run:

```powershell
python -m unittest discover -s .github/scripts -p 'test_documentation_delivery.py' -v
python -m mkdocs build --strict --site-dir site
python .github/scripts/build_documentation_manifest.py create --site-dir site --output deployment-evidence/site-manifest.json --source-repository 'SamErde/TheCleaners' --source-commit (git rev-parse HEAD) --source-ref (git symbolic-ref -q HEAD)
python .github/scripts/build_documentation_manifest.py verify --site-dir site --manifest deployment-evidence/site-manifest.json
```

Do not run the live verifier against a newly changed source tree before that exact tree has been deployed. It is designed to reject the current site as stale.

## Current verified state

The September 17, 2026 live check found title-case `/TheCleaners/` HTTP 200 and lowercase `/thecleaners/` HTTP 404. GitHub Pages reports the title-case site URL. The maintainer selected that working path as canonical, superseding the earlier lowercase-hosting requirement. This does not prove the deployed bytes match this branch.

For merged commit `037c27a81234361620a633f68a33bfb370f0a03e`, [GitHub Actions run 35129434855](https://github.com/SamErde/TheCleaners/actions/runs/35129434855) completed `mkdocs build --strict --site-dir site` and checked `site/index.html` and `site/sitemap.xml`. Its later `mkdocs gh-deploy --strict --force` command performed a second strict build and pushed `gh-pages` commit `2ea8bf4`; that historical workflow did not establish byte identity between the checked `site` directory and deployed output.

The historical live check on September 16, 2026 found:

| Request | Result |
| --- | --- |
| `https://day3bits.com/thecleaners/` | HTTP 404. |
| `https://day3bits.com/TheCleaners/` | HTTP 200 with the deployed MkDocs site. |
| `https://day3bits.com/TheCleaners` | HTTP 301 to `/TheCleaners/`. |

No live deployment or external hosting change was performed while implementing this workflow. Exact deployed-byte and navigation evidence remains open until the workflow runs for the merged commit and its retained artifacts are reviewed.
