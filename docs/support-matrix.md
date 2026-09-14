# Support policy and validation matrix

The 1.0 target is **Windows PowerShell 5.1 or a Microsoft-supported PowerShell 7 release on Windows**. The manifest minimum remains 5.1. `Desktop` and `Core` edition compatibility does not imply Linux or macOS support.

| Environment | Current implementation evidence required | 1.0 gate |
| --- | --- | --- |
| Windows PowerShell 5.1 | Dedicated Windows CI parses runtime files and runs unit/API/source-import tests. Consult the PR for actual results. | Full unit and packaged-module integration/install checks. |
| PowerShell 7 on Windows | Existing Windows build includes substantive package-import probes. The runner reports its actual version. | Pin/test supported LTS and supported current stable when distinct. |
| Supported Windows client/server | Fixture-based CI is not an OS acceptance matrix. | Record supported releases and elevated/non-elevated acceptance results. |
| IIS | Structurally preview-only with explicit `-WhatIf`; no deletion path or call to the legacy generic helper. Discovery remains experimental. | Stable only after exact path/format rules and declared server-matrix acceptance pass. Otherwise retain the preview lock. |
| Exchange | Experimental read-only discovery with explicit `-WhatIf`; no deletion. Directory roots are type-checked. | Guard must pass; no production cleanup support is claimed. Product matrix required before a later removal-enabled release. |
| Linux/macOS | Not supported by the 1.0 policy. | No non-Windows cleanup behavior. |

Consult Microsoft's [PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle) when updating the runtime matrix. Do not infer support for every older 7.x version or promise future major releases without validation.
