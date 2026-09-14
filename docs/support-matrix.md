# Support policy and validation matrix

The 1.0 support contract is Windows-only: Windows PowerShell 5.1 plus Microsoft-supported PowerShell 7 releases on Windows. The manifest minimum remains 5.1. Core and Desktop edition compatibility does not imply Linux or macOS support.

## Runtime matrix

| Runtime | Contract | Evidence required before 1.0 RC |
| --- | --- | --- |
| Windows PowerShell 5.1 | Minimum supported runtime for all read-only and temp commands. | Native Windows CI run with parser, unit, source-import, clean-install, and package probes. |
| PowerShell 7 supported LTS | Supported when the release is within Microsoft's lifecycle. | CI run records the exact PSVersionTable, package import, unit, and install results. |
| PowerShell 7 supported current stable | Supported when distinct from the LTS line and within Microsoft's lifecycle. | Same evidence as the LTS lane. |
| Other PowerShell versions | No promise is made for unsupported, historical, preview, or future versions. | Optional diagnostic runs must not be presented as release acceptance. |

Check Microsoft's [PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle) when this matrix is refreshed. The release ledger requires the exact supported LTS/current pair at RC time; this branch does not claim that a local run substitutes for CI.

## Windows product matrix

| Product | 1.0 contract | Current state |
| --- | --- | --- |
| Windows client | Temp commands use the actual current-user temp root. Fixture tests cover path and identity behavior; system-root acceptance must use a disposable client. | Open OS acceptance. |
| Windows Server 2019 | Windows PowerShell 5.1 and supported PowerShell 7 runtime lane; Clear-WindowsTemp remains fixture-tested only. | Open elevated/non-elevated OS acceptance. |
| Windows Server 2022 | Same contract as Server 2019. | Open elevated/non-elevated OS acceptance. |
| Windows Server 2025 | Same contract as Server 2019. | Open elevated/non-elevated OS acceptance. |
| NTFS | Native FILE_ID_INFO identity behavior is required. | Fixture evidence exists; lab acceptance open. |
| ReFS | Native FILE_ID_INFO identity behavior is required. | Lab acceptance open; do not infer from NTFS. |

The server rows are validation targets, not a claim that every edition or servicing level has passed. Record the exact OS build, filesystem, elevation state, and runtime for each run.

## IIS matrix

| Product/configuration | Contract | Current state |
| --- | --- | --- |
| IIS 10 on supported Windows client/server | Discovery only; explicit WhatIf; Web/FTP format-specific allowlists; protected inetsrv configuration/history paths. | Preview-only; mocked fixtures pass, product lab open. |
| WebAdministration unavailable or IIS not installed | Report the optional dependency/product state without treating it as an empty validated cleanup. | Fixture coverage exists; OS/product matrix open. |
| Custom log roots and formats | Expand, normalize, deduplicate, and apply a declared format allowlist. | Draft implementation; lab evidence open. |

IIS cannot become destructive by changing a label. The preview lock remains until exact product/version, path, format, and service-health gates pass.

## Exchange matrix

| Product/configuration | Contract | Current state |
| --- | --- | --- |
| Exchange Server v15 family | Discovery only; explicit WhatIf; no removal switch or persistent activation. | Experimental preview; exact build matrix open. |
| Message Tracking | Allow only known MSGTRK* names under the validated root. | Draft implementation; lab evidence open. |
| Search/Ceres ETL and diagnostic logs | Apply separate ETL/log filename rules and skip reparse points. | Draft implementation; lab evidence open. |
| Mailbox database and transaction-log paths | Always protected, including custom paths returned by Exchange management discovery and overlaps with proposed log roots. | Draft protection helper; live product validation open. |

No Exchange deletion support is claimed for 1.0. A later minor release may revisit a per-invocation opt-in only after the product, path, lock/access, and service-health gates are recorded and approved.

## Unsupported

Linux, macOS, arbitrary remote paths, profile deletion, scheduling installation, and automatic all-service orchestration are outside the 1.0 contract.
