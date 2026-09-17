# Documentation deployment gate

The canonical documentation URL is `https://day3bits.com/TheCleaners/`, including the title-case path. Configuration, source help, the manifest, generated references, and canonical links must use that casing. The MkDocs workflow must build with `--strict` and deploy the exact checked output. A deployment acceptance record must verify:

1. `https://day3bits.com/TheCleaners/` returns the current site and preserves the title-case path.
2. Function pages, the support matrix, command contracts, migration guide, and release ledger are reachable from navigation.
3. The deployed files match the retained, checked build output for the recorded source commit; retain its manifest/digests and deployment identity.
4. The generated site contains no unresolved help-template markers, broken internal navigation links, or lowercase canonical URL declarations.

The workflow currently performs strict build-time checks but then rebuilds during `mkdocs gh-deploy`. Build-once deployment and exact deployed-byte verification remain non-lab delivery work. A local build or successful deployment job alone does not close them.

## Current verified state

The September 17, 2026 live check again found title-case `/TheCleaners/` HTTP 200 and lowercase `/thecleaners/` HTTP 404. GitHub Pages reports the title-case site URL. The maintainer selected that working path as canonical, superseding the earlier lowercase-hosting requirement. This does not prove the deployed bytes match this source revision.

For merged commit `037c27a81234361620a633f68a33bfb370f0a03e`, [GitHub Actions run 35129434855](https://github.com/SamErde/TheCleaners/actions/runs/35129434855) completed `mkdocs build --strict --site-dir site` and checked `site/index.html` and `site/sitemap.xml`. Its later `mkdocs gh-deploy --strict --force` command performed a second strict build and pushed `gh-pages` commit `2ea8bf4`; the workflow does not establish byte identity between the separately checked `site` directory and the deployed output. A successful deployment job also does not prove the custom-domain path is canonical.

The historical live check on September 16, 2026 found:

| Request | Result |
| --- | --- |
| `https://day3bits.com/thecleaners/` | HTTP 404. |
| `https://day3bits.com/TheCleaners/` | HTTP 200 with the deployed MkDocs site. |
| `https://day3bits.com/TheCleaners` | HTTP 301 to `/TheCleaners/`. |

## Future support for both URL cases

The [Zensical migration, issue #26](https://github.com/SamErde/TheCleaners/issues/26#issuecomment-5716312584), owns support for both `/TheCleaners/` and `/thecleaners/`, including the root and representative deep links, with title-case canonical URLs. Evaluate a hosting rewrite/redirect, generated alias routes, or a compatible extension and verify it end to end. A documentation plugin alone may not route a missing top-level hosting path. This migration requirement is outside the 1.0 critical path; lowercase HTTP 404 is no longer a current release blocker.
