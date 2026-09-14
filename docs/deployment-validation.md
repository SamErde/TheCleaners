# Documentation deployment gate

The canonical documentation URL is `https://day3bits.com/thecleaners/`, including the lowercase path. The MkDocs workflow must build with `--strict` before deployment and must retain the generated `index.html` and sitemap. A deployment acceptance record must verify:

1. `https://day3bits.com/thecleaners/` returns the current site and preserves the lowercase path.
2. Function pages, the support matrix, command contracts, migration guide, and release ledger are reachable from navigation.
3. Older casing and legacy documentation hosts redirect to the canonical lowercase path without introducing a competing custom-domain configuration.
4. The generated site contains no unresolved help-template markers or broken internal navigation links.

The workflow performs the build-time strict checks. Redirect, DNS, and deployed-host checks require the deployment environment and remain release evidence; they are not claimed by a local build.
