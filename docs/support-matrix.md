# Support policy and validation matrix

**Windows client/server, IIS, Exchange, and profile lab validation is deferred future work, not underway.** Hosted fixture/package results below remain scoped to their exact tested commits and do not establish product acceptance.

The 1.0 support contract is Windows-only: Windows PowerShell 5.1 plus Microsoft-supported PowerShell 7 releases on Windows. The manifest minimum remains 5.1. Core and Desktop edition compatibility does not imply Linux or macOS support. Current exact merged runtime evidence is for `6fd8af169da631d17579a3c7eb3fa0aa8b285be0`; it does not apply automatically to later commits.

## Current exact merged runtime evidence

[Build run 35340908362](https://github.com/SamErde/TheCleaners/actions/runs/35340908362) and independent inspection of all eleven retained artifacts validate exact merged source `6fd8af169da631d17579a3c7eb3fa0aa8b285be0`:

| Runtime | Exact merged evidence |
| --- | --- |
| Windows PowerShell 5.1 | `5.1.26100.33296` Desktop passed 363 combined tests with zero failures, skips or not-run tests and consumed the canonical 7.6.6 artifact. |
| PowerShell 7.4 LTS | `7.4.20` passed 359 unit and 4 integration tests with zero failures, skips or not-run tests; coverage was 88.05% (1,636/1,858). |
| PowerShell 7.5 stable | `7.5.11` passed 359 unit and 4 integration tests with zero failures, skips or not-run tests; coverage was 88.05% (1,636/1,858). |
| PowerShell 7.6 LTS | `7.6.6` passed 359 unit and 4 integration tests with zero failures, skips or not-run tests; coverage was 88.05% (1,636/1,858). |

All three PS7 producers generated identical original and repeated 19-file archives: 224,558 bytes, SHA-256 `5153966aaef9f194fdf60fe8793989f4693dcd3310b10c4223d6208865d0135f`. Independent inspection matched all eleven artifact wrappers, source/runtime reports, NUnit results, ACL and local-feed evidence, and repeated/cross-runtime archives. Merged-source analyzer run [35340908372](https://github.com/SamErde/TheCleaners/actions/runs/35340908372) and documentation run [35340908280](https://github.com/SamErde/TheCleaners/actions/runs/35340908280) also passed. The distinct published `0.0.15-beta` artifact remains 224,050 bytes with SHA-256 `1c8e061278e68c2e1537186709f79606735c6dda2e48b5cf65a4a877699e3383` from exact source `345f06c861b6d4074e5896e0b27a19f869dfa7e3`; current untagged source changes are not part of that Gallery package. The bounded PR #35 baseline review is complete, while its native, platform and product cases remain assigned to deferred labs. Final 1.0 release acceptance remains open.

## Historical runtime evidence

| Runtime | Contract | Evidence required before 1.0 RC |
| --- | --- | --- |
| Windows PowerShell 5.1 | Minimum supported runtime for all read-only and temp commands. | Hosted `5.1.26100.33296` passed 215 source unit tests plus 4 package integration tests with 0 failures, skips, or not-run tests. The four integration tests exercised the exact downloaded 7.6.6 package artifact. |
| PowerShell 7.6 LTS | Supported current LTS line. | Hosted `7.6.6` passed 215 unit and 4 integration tests with 0 failures, skips, or not-run tests and 83.48% coverage. |
| PowerShell 7.5 stable | Supported stable line through November 10, 2026; Microsoft supports only the latest servicing update. | Hosted `7.5.9` passed 215 unit and 4 integration tests with 0 failures, skips, or not-run tests and 83.48% coverage. Microsoft now lists `7.5.11` as current, so the hosted lane must be refreshed before RC. |
| PowerShell 7.4 LTS | Still Microsoft-supported through November 2026. | No exact-commit hosted lane. Add the latest supported 7.4 patch or obtain explicit maintainer approval to narrow the stated policy before RC. |
| Other PowerShell versions | No promise is made for unsupported, historical, preview, or future versions. | Optional diagnostic runs must not be presented as release acceptance. |

Check Microsoft's [PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle) when this matrix is refreshed. As of this sweep, 7.4, 7.5, and 7.6 are all supported release lines. [Build run 35129434807](https://github.com/SamErde/TheCleaners/actions/runs/35129434807) supplies the exact historical evidence above, but it does not include 7.4 and its 7.5.9 lane is older than Microsoft's current 7.5.11 servicing update, so TC-008 remains open.

## Historical TC-008 merged runtime evidence

Microsoft's lifecycle page and official release inventory were checked on September 16, 2026. The latest supported servicing releases are [7.4.20](https://github.com/PowerShell/PowerShell/releases/tag/v7.4.20), [7.5.11](https://github.com/PowerShell/PowerShell/releases/tag/v7.5.11), and [7.6.6](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.6), all published September 8. No support-policy narrowing was approved. [Build run 35152376944](https://github.com/SamErde/TheCleaners/actions/runs/35152376944) identifies exact merged commit `fdadbee08f854b1af6fdc7654ae4532ebbf605df` and supplies the machine-readable evidence below.

| Runtime | Exact merged evidence |
| --- | --- |
| Windows PowerShell 5.1 | [Job 104984394144](https://github.com/SamErde/TheCleaners/actions/runs/35152376944/job/104984394144) used `5.1.26100.33296` Desktop on Windows Server 2025 Datacenter build `26100`. The combined report passed `226/226` tests with `0` failures, skips, inconclusive, invalid, or not-run tests. It downloaded and tested the canonical 7.6.6 artifact/ZIP; it did not produce coverage or a canonical PS5.1 archive. |
| PowerShell 7.4 LTS | [Job 104983565483](https://github.com/SamErde/TheCleaners/actions/runs/35152376944/job/104983565483) used `7.4.20` Core on .NET `8.0.31` and Windows Server 2025 `10.0.26100`. Pester `5.7.1` passed `222/222` unit and `4/4` integration tests with `0` failures, skips, or not-run tests; source coverage was `83.48%` (`1,551/1,858` commands across 16 files). |
| PowerShell 7.5 stable | [Job 104983565445](https://github.com/SamErde/TheCleaners/actions/runs/35152376944/job/104983565445) used `7.5.11` Core on .NET `9.0.20` and Windows Server 2025 `10.0.26100`. Pester `5.7.1` passed `222/222` unit and `4/4` integration tests with `0` failures, skips, or not-run tests; source coverage was `83.48%` (`1,551/1,858` commands across 16 files). |
| PowerShell 7.6 LTS | [Job 104983565518](https://github.com/SamErde/TheCleaners/actions/runs/35152376944/job/104983565518) used `7.6.6` Core on .NET `10.0.12` and Windows Server 2025 `10.0.26100`. Pester `5.7.1` passed `222/222` unit and `4/4` integration tests with `0` failures, skips, or not-run tests; source coverage was `83.48%` (`1,551/1,858` commands across 16 files). |

Each PS7 lane built and tested its own exact artifact, then repeated ZIP generation. The [dependent comparison job](https://github.com/SamErde/TheCleaners/actions/runs/35152376944/job/104984394111) downloaded all three archives, checked every content record and sidecar, and verified identical original/repeated and cross-runtime bytes. Windows PowerShell 5.1 downloaded the selected canonical 7.6.6 artifact and archive; it never rebuilt that package. Its source tests also exercised the archive helper's PS5.1 API compatibility on isolated fixtures, without making PS5.1 a canonical archive producer.

This section is historical evidence for `fdadbee08f854b1af6fdc7654ae4532ebbf605df`; the earlier table is historical evidence for `037c27a81234361620a633f68a33bfb370f0a03e`. Current exact merged evidence appears above. At this historical checkpoint, publication and installed-package verification were open. The bounded PR #35 baseline review is now complete; its remaining native/platform/product cases belong to deferred labs, and final maintainer release acceptance remains open. See [packaging](packaging.md).

## Windows product matrix

| Product | 1.0 contract | Current state |
| --- | --- | --- |
| Windows client | Temp commands use the actual current-user temp root. Fixture tests cover path and identity behavior; system-root acceptance must use a disposable client. | Open OS acceptance. |
| Windows Server 2019 | Windows PowerShell 5.1 and supported PowerShell 7 runtime lane; Clear-WindowsTemp remains fixture-tested only. | Open elevated/non-elevated OS acceptance. |
| Windows Server 2022 | Same contract as Server 2019. | Open elevated/non-elevated OS acceptance. |
| Windows Server 2025 | Same contract as Server 2019. | Hosted Server 2025 build 26100 passed the runtime/package matrix and an elevated isolated ACL fixture; real system-root and non-elevated acceptance remain open. |
| NTFS | Native FILE_ID_INFO identity behavior is required. | Exact-commit hosted ACL fixture passed on NTFS; broader client/server and non-elevated acceptance remain open. |
| ReFS | Native FILE_ID_INFO identity behavior is required. | Lab acceptance open; do not infer from NTFS. |

The server rows are validation targets, not a claim that every edition or servicing level has passed. Record the exact OS build, filesystem, elevation state, and runtime for each run.

## IIS matrix

| Product/configuration | Contract | Current state |
| --- | --- | --- |
| IIS 10 on supported Windows client/server | Discovery only; explicit WhatIf; Web/FTP format-specific allowlists; protected inetsrv configuration/history paths. | Preview-only; mocked fixtures pass, product lab open. |
| WebAdministration unavailable or IIS not installed | Report the optional dependency/product state without treating it as an empty validated cleanup. | Fixture coverage exists; OS/product matrix open. |
| Custom log roots with built-in formats | Expand, normalize, deduplicate, and apply the declared W3C/IIS/NCSA allowlist. | Merged implementation; product lab evidence open. |
| Custom or unknown logging formats | Do not infer safety from a `.log` extension. | Fail closed; no product-lab acceptance. |

IIS cannot become destructive by changing a label. The preview lock remains until exact product/version, path, format, and service-health gates pass.

## Exchange matrix

| Product/configuration | Contract | Current state |
| --- | --- | --- |
| Exchange Server v15 family | Discovery only; explicit WhatIf; no removal switch or persistent activation. | Experimental preview; exact build matrix open. |
| Message Tracking | Allow only known MSGTRK* names under the validated root. | Merged preview implementation; lab evidence open. |
| Search/Ceres ETL and diagnostic logs | Apply separate ETL/log filename rules and skip reparse points. | Merged preview implementation; lab evidence open. |
| Mailbox database and transaction-log paths | Always protected, including custom paths returned by Exchange management discovery and overlaps with proposed log roots. | Merged protection helper; live product validation open. |

No Exchange deletion support is claimed for 1.0. A later minor release may revisit a per-invocation opt-in only after the product, path, lock/access, and service-health gates are recorded and approved. The exact merged commit has no IIS or Exchange product/build lab record; mocked fixtures do not change either preview-only state.

## Unsupported

Linux, macOS, arbitrary remote paths, profile deletion, scheduling installation, and automatic all-service orchestration are outside the 1.0 contract.
