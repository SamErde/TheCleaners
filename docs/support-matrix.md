# Support policy and validation matrix

**Windows client/server, IIS, Exchange, and profile lab validation is deferred future work, not underway.** Hosted fixture/package results below remain scoped to their exact tested commits and do not establish product acceptance.

The 1.0 support contract is Windows-only: Windows PowerShell 5.1 plus Microsoft-supported PowerShell 7 releases on Windows. The manifest minimum remains 5.1. Core and Desktop edition compatibility does not imply Linux or macOS support. Exact TC-008 runtime evidence below is for merged commit `fdadbee08f854b1af6fdc7654ae4532ebbf605df`; it does not apply automatically to a later commit.

## Historical runtime evidence

| Runtime | Contract | Evidence required before 1.0 RC |
| --- | --- | --- |
| Windows PowerShell 5.1 | Minimum supported runtime for all read-only and temp commands. | Hosted `5.1.26100.33296` passed 215 source unit tests plus 4 package integration tests with 0 failures, skips, or not-run tests. The four integration tests exercised the exact downloaded 7.6.6 package artifact. |
| PowerShell 7.6 LTS | Supported current LTS line. | Hosted `7.6.6` passed 215 unit and 4 integration tests with 0 failures, skips, or not-run tests and 83.48% coverage. |
| PowerShell 7.5 stable | Supported stable line through November 10, 2026; Microsoft supports only the latest servicing update. | Hosted `7.5.9` passed 215 unit and 4 integration tests with 0 failures, skips, or not-run tests and 83.48% coverage. Microsoft now lists `7.5.11` as current, so the hosted lane must be refreshed before RC. |
| PowerShell 7.4 LTS | Still Microsoft-supported through November 2026. | No exact-commit hosted lane. Add the latest supported 7.4 patch or obtain explicit maintainer approval to narrow the stated policy before RC. |
| Other PowerShell versions | No promise is made for unsupported, historical, preview, or future versions. | Optional diagnostic runs must not be presented as release acceptance. |

Check Microsoft's [PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle) when this matrix is refreshed. As of this sweep, 7.4, 7.5, and 7.6 are all supported release lines. [Build run 35129434807](https://github.com/SamErde/TheCleaners/actions/runs/35129434807) supplies the exact historical evidence above, but it does not include 7.4 and its 7.5.9 lane is older than Microsoft's current 7.5.11 servicing update, so TC-008 remains open.

## TC-008 merged runtime evidence

Microsoft's lifecycle page and official release inventory were checked on September 16, 2026. The latest supported servicing releases are [7.4.20](https://github.com/PowerShell/PowerShell/releases/tag/v7.4.20), [7.5.11](https://github.com/PowerShell/PowerShell/releases/tag/v7.5.11), and [7.6.6](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.6), all published September 8. No support-policy narrowing was approved. [Build run 35152376944](https://github.com/SamErde/TheCleaners/actions/runs/35152376944) identifies exact merged commit `fdadbee08f854b1af6fdc7654ae4532ebbf605df` and supplies the machine-readable evidence below.

| Runtime | Exact merged evidence |
| --- | --- |
| Windows PowerShell 5.1 | [Job 104984394144](https://github.com/SamErde/TheCleaners/actions/runs/35152376944/job/104984394144) used `5.1.26100.33296` Desktop on Windows Server 2025 Datacenter build `26100`. The combined report passed `226/226` tests with `0` failures, skips, inconclusive, invalid, or not-run tests. It downloaded and tested the canonical 7.6.6 artifact/ZIP; it did not produce coverage or a canonical PS5.1 archive. |
| PowerShell 7.4 LTS | [Job 104983565483](https://github.com/SamErde/TheCleaners/actions/runs/35152376944/job/104983565483) used `7.4.20` Core on .NET `8.0.31` and Windows Server 2025 `10.0.26100`. Pester `5.7.1` passed `222/222` unit and `4/4` integration tests with `0` failures, skips, or not-run tests; source coverage was `83.48%` (`1,551/1,858` commands across 16 files). |
| PowerShell 7.5 stable | [Job 104983565445](https://github.com/SamErde/TheCleaners/actions/runs/35152376944/job/104983565445) used `7.5.11` Core on .NET `9.0.20` and Windows Server 2025 `10.0.26100`. Pester `5.7.1` passed `222/222` unit and `4/4` integration tests with `0` failures, skips, or not-run tests; source coverage was `83.48%` (`1,551/1,858` commands across 16 files). |
| PowerShell 7.6 LTS | [Job 104983565518](https://github.com/SamErde/TheCleaners/actions/runs/35152376944/job/104983565518) used `7.6.6` Core on .NET `10.0.12` and Windows Server 2025 `10.0.26100`. Pester `5.7.1` passed `222/222` unit and `4/4` integration tests with `0` failures, skips, or not-run tests; source coverage was `83.48%` (`1,551/1,858` commands across 16 files). |

Each PS7 lane built and tested its own exact artifact, then repeated ZIP generation. The [dependent comparison job](https://github.com/SamErde/TheCleaners/actions/runs/35152376944/job/104984394111) downloaded all three archives, checked every content record and sidecar, and verified identical original/repeated and cross-runtime bytes. Windows PowerShell 5.1 downloaded the selected canonical 7.6.6 artifact and archive; it never rebuilt that package. Its source tests also exercised the archive helper's PS5.1 API compatibility on isolated fixtures, without making PS5.1 a canonical archive producer.

The runtime-matrix subgate is validated only for `fdadbee08f854b1af6fdc7654ae4532ebbf605df`. The historical table above remains evidence only for `037c27a81234361620a633f68a33bfb370f0a03e`; candidate PR evidence retains its separate head identity. Publication, a clean install of the published version, uncovered-branch risk review, broader Windows/product acceptance, and maintainer release acceptance remain open. See [packaging](packaging.md).

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
