# Pull Request

## Type of Change

- [ ] 📖 Documentation
- [ ] 🪲 Fix
- [ ] 🩹 Patch
- [ ] ⚠️ Security Fix
- [ ] 🚀 Feature
- [ ] 💥 Breaking Change

## Issue
<!-- If this PR resolves an issue, enter the issue number here. -->

## Release-plan packet
<!-- Add the TC-### packet(s), or explain why this is documentation/maintenance work. -->

## Description
<!-- Please include a clear description of what your pull request does. Remember to only include one change (or group of tightly related changes) per pull request to make review and testing easier. -->

## Checklist

- [ ] 🕵️ I have reviewed my code for errors and tested it.
- [ ] 🚩 My pull request does not contain multiple types of changes.
- [ ] 📄 By submitting this pull request, I confirm that my contribution is made under the terms of the project's associated license.
- [ ] I read `AGENTS.md` and the applicable section of `docs/release-plan-1.0.md`.
- [ ] I recorded the exact commit, runtime/OS, test totals, failures, skips, and report paths or links.
- [ ] I did not copy CI, lab, package hash, clean-install, or deployment evidence from a different commit.
- [ ] Cleanup tests use isolated fixtures or mocks; no live user, Windows, IIS, or Exchange data was touched.
- [ ] If behavior changed, I covered WhatIf/Confirm, error handling, path containment, and relevant reparse/identity/race cases.
- [ ] I did not create a release tag, publish to the Gallery, or enable IIS/Exchange deletion.
