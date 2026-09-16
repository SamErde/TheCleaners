# Documentation deployment gate

The canonical documentation URL is `https://day3bits.com/thecleaners/`, including the lowercase path. The MkDocs workflow must build with `--strict` before deployment and must retain the generated `index.html` and sitemap. A deployment acceptance record must verify:

1. `https://day3bits.com/thecleaners/` returns the current site and preserves the lowercase path.
2. Function pages, the support matrix, command contracts, migration guide, and release ledger are reachable from navigation.
3. Older casing and legacy documentation hosts redirect to the canonical lowercase path without introducing a competing custom-domain configuration.
4. The generated site contains no unresolved help-template markers or broken internal navigation links.

The workflow performs the build-time strict checks. Redirect, DNS, and deployed-host checks require the deployment environment and remain release evidence; they are not claimed by a local build.

## Current verified state

For merged commit `037c27a81234361620a633f68a33bfb370f0a03e`, [GitHub Actions run 35129434855](https://github.com/SamErde/TheCleaners/actions/runs/35129434855) completed `mkdocs build --strict --site-dir site`, checked `site/index.html` and `site/sitemap.xml`, and pushed the generated site to `gh-pages`. A successful deployment job does not prove the custom-domain path is canonical.

The live check on September 16, 2026 found:

| Request | Result |
| --- | --- |
| `https://day3bits.com/thecleaners/` | HTTP 404. |
| `https://day3bits.com/TheCleaners/` | HTTP 200 with the deployed MkDocs site. |
| `https://day3bits.com/TheCleaners` | HTTP 301 to `/TheCleaners/`. |

The lowercase deployment/redirect correction requires the site owner. This repository sweep did not change external deployment configuration and does not claim the canonical path is fixed.
