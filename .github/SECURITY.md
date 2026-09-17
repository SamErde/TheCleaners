# Security Policy

## Supported versions

The project has no stable 1.0 release. Security fixes target the maintained `main` branch and are subject to the release ledger's acceptance gates. The published `0.0.15-beta` prerelease maps to exact source commit `345f06c861b6d4074e5896e0b27a19f869dfa7e3`; Windows, IIS, Exchange, profile and final 1.0 acceptance remain open. Fixes merged after that source commit are not part of the published beta until another exact artifact is released.

## Reporting a Vulnerability

If you discover a vulnerability in **The Cleaners**, report it privately through GitHub's private vulnerability reporting or security advisory workflow. Do not include exploitable details, credentials, customer data, or live cleanup paths in a public issue or pull request.

The maintainer will review the report and may follow up privately for reproduction details. Include the affected version or commit, supported Windows/PowerShell runtime, impact, and a safe fixture-based reproduction when possible. Redact personal paths and secrets.

We will evaluate the report and, if necessary, release a fix or mitigating steps. Please do not disclose the vulnerability publicly until a fix is released or the maintainer has confirmed coordinated disclosure.

The module is Windows-only and its IIS/Exchange commands are preview-only in the 1.0 preparation work. Reports involving deletion, path containment, identity races, ACLs, reparse points, or package publication should say whether the behavior was observed in an isolated fixture or a disposable lab. Do not test a vulnerability by running cleanup against real user, Windows, IIS, Exchange, or production data.
