# Contributing

Thanks for your interest in contributing to **The Cleaners**.

Whether it's a bug report, new feature, correction, or additional documentation, your feedback and contributions are appreciated.

Please read through this document before submitting any issues or pull requests to ensure all the necessary information is provided to effectively respond to your bug report or contribution.

Before changing behavior, read `AGENTS.md` and `docs/release-plan-1.0.md`. The release plan is the implementation ledger; a generated command or workflow is not release evidence by itself.

Please note there is a code of conduct, please follow it in all your interactions with the project.

## Contributing via Pull Requests

Please contribute pull requests against the `main` branch of this repository. If you're not sure how, feel free to reach out and ask!

Keep changes narrowly scoped to one release-plan packet when possible. Include the packet ID, exact tested commit, runtime and OS versions, test totals/failures/skips, and links to machine-readable reports. Use isolated fixtures or mocks for cleanup development; never run a cleaner against real user, Windows, IIS, or Exchange data. IIS and Exchange remain preview-only until their product-specific gates pass.

For filesystem mutation changes, demonstrate `-WhatIf`/`-Confirm`, root containment, reparse-point handling, identity/race behavior, and `-ErrorAction Stop`. Do not add provider deletion for temp candidates, a generic deletion wrapper, a force or preference override, or a persistent activation switch.

For documentation-only changes, install `docs/requirements.txt`, run `python .github/scripts/validate_documentation_configuration.py`, `zensical build --strict --clean`, the documentation/help/drift tests, and `git diff --check`. Use `zensical serve` for a local preview. Generated help must come from source comment-based help; do not hand-edit packaged external help. Do not copy test counts, hashes, CI links, product/build results, or deployment claims from an earlier commit. A successful workflow or mocked fixture is not IIS, Exchange, Windows-product, or release acceptance.

## Code of Conduct

This project has a [Code of Conduct](CODE_OF_CONDUCT.md).

## Licensing

See the [LICENSE](../LICENSE) file for our project's licensing.

## TC-008 runtime and package evidence

Check Microsoft's current support lifecycle and release tags before refreshing pinned runtimes. The candidate matrix is PS7 7.4.20, 7.5.11 and 7.6.6 plus Windows PowerShell 5.1. PS7 lanes test their own exact artifacts; PS5.1 downloads the selected canonical 7.6.6 package without rebuilding. Preserve hidden files during upload and staging.

Use the stored-ZIP contract in [packaging](../docs/packaging.md). Report repeated and cross-runtime archive hashes, content manifests, exact commit/runtime identity, test counts and coverage. A PR-head run validates that candidate only. After merge, verify the new main SHA and its own hosted runs before closing ledger subgates. Runtime/package evidence does not close product labs, publication, metadata, hosting or maintainer release acceptance.
