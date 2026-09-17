# Documentation deployment gate

The canonical documentation URL is `https://day3bits.com/TheCleaners/`, matching the maintainer's September 17 title-case decision and MkDocs configuration. The MkDocs workflow must build with `--strict` before deployment and must retain the generated `index.html` and sitemap. A deployment acceptance record must verify:

1. `https://day3bits.com/TheCleaners/` returns the current site and preserves the title-case path.
2. Function pages, the support matrix, command contracts, migration guide, and release ledger are reachable from navigation.
3. The generated pages declare the title-case canonical URL. Support for both URL cases belongs to [Zensical issue #26](https://github.com/SamErde/TheCleaners/issues/26) and remains outside this delivery gate.
4. The generated site contains no unresolved help-template markers or broken internal navigation links.

The workflow performs the build-time strict checks. Redirect, DNS, and deployed-host checks require the deployment environment and remain release evidence; they are not claimed by a local build.

## Historical evidence from September 16

For merged commit `037c27a81234361620a633f68a33bfb370f0a03e`, [GitHub Actions run 35129434855](https://github.com/SamErde/TheCleaners/actions/runs/35129434855) completed `mkdocs build --strict --site-dir site` and checked `site/index.html` and `site/sitemap.xml`. Its later `mkdocs gh-deploy --strict --force` command performed a second strict build and pushed `gh-pages` commit `2ea8bf4`; the workflow does not establish byte identity between the separately checked `site` directory and the deployed output. A successful deployment job also does not prove the custom-domain path is canonical.

The live check on September 16, 2026 found:

| Request | Result |
| --- | --- |
| `https://day3bits.com/thecleaners/` | HTTP 404. |
| `https://day3bits.com/TheCleaners/` | HTTP 200 with the deployed MkDocs site. |
| `https://day3bits.com/TheCleaners` | HTTP 301 to `/TheCleaners/`. |

At that historical checkpoint, the plan still required lowercase hosting. The maintainer's September 17 title-case decision supersedes that requirement; the observations remain evidence for their original commit. Exact deployed-byte verification remains open.

## Manifest foundation for exact-build verification

The content-manifest helper records each built file's relative path, byte length and SHA-256, plus the source commit and workflow run. Keep its output outside the site directory. For example, after a strict build:

```powershell
python .github/scripts/build_documentation_manifest.py create --site-dir site --output deployment-evidence/site-manifest.json --source-repository SamErde/TheCleaners --source-commit (git rev-parse HEAD)
python .github/scripts/build_documentation_manifest.py verify --site-dir site --manifest deployment-evidence/site-manifest.json
```

Creation rejects symbolic links and unsafe paths. Verification rejects changed, missing or additional files, including hidden files. The helper and isolated regression tests prepare the one-build deployment work in [PR #37](https://github.com/SamErde/TheCleaners/pull/37); they do not establish deployed-byte or navigation acceptance. PR #37 also applies the maintainer's title-case canonical URL decision. Historical URL observations above remain observations of their original commit.

The companion `documentation_http.py` helper accepts HTTPS, with HTTP permitted only for test servers at `127.0.0.1` or `localhost`. It uses explicit HTTP connections, bounds response reads and returns redirects without following them. The deployment verifier in PR #37 checks status, size and digest before accepting a response.
