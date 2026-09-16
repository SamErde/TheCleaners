# Packaging and archive reproducibility

## Contract

The TC-008 candidate requires identical ZIP bytes for identical staged file paths and contents across the pinned, supported PS7 Windows builders: 7.4.20, 7.5.11 and 7.6.6. This is a tested contract for those Windows runtimes and dependency pins, not a promise about future .NET writers, other operating systems, different source line endings, or changed help generators. Refreshing a runtime must pass the same comparison gate.

`src/New-DeterministicZipArchive.ps1` writes files in ordinal relative-path order with `/` separators, explicit UTF-8 entry names, a fixed 1980-01-01 ZIP timestamp and zero external attributes. PS7 uses stored entries (`NoCompression`), avoiding Deflate implementation differences. Stored archives are larger; content manifests and SHA-256 sidecars continue to verify every byte. Manifests are outside the ZIP and deliberately include runtime identity, so manifests themselves are not byte-identical between runtime lanes.

Windows PowerShell 5.1 remains supported for module use and tests the exact downloaded canonical 7.6.6 artifact and ZIP. The helper uses PS5.1-compatible syntax/APIs and has fixture tests there, but the .NET Framework ZIP writer is not included in the cross-producer byte contract. No separate PS5.1 package is built for validation or publication.

## Historical investigation

Both archives were downloaded from [run 35129434807](https://github.com/SamErde/TheCleaners/actions/runs/35129434807) for commit `037c27a81234361620a633f68a33bfb370f0a03e` and inspected with Python's standard ZIP parser and raw compressed-payload comparison.

| Producer | Archive | Bytes | SHA-256 |
| --- | --- | --- | --- |
| 7.5.9 | `TheCleaners_0.0.15.zip` | 43,051 | `31f710cd62fd04d4b0e41261054158df7527b9bc84a425755fd436044d89164d` |
| 7.6.6 | `TheCleaners_0.0.15.zip` | 43,141 | `adf7d3fb6e693a0e559ce560fc5c83ee8254d7ecad9115061c836d293a6705f4` |

All 19 entries have the same names/order, uncompressed lengths, SHA-256 file hashes, CRCs, epoch timestamps, zero attributes, version fields, encoding flags, and empty extra/comment fields. Both use Deflate method 8. Six compressed payloads differ; four have different lengths:

| Entry | 7.5.9 compressed bytes | 7.6.6 compressed bytes |
| --- | --- | --- |
| `en-US/TheCleaners-help.xml` | 4,059 | 4,132 |
| `Private/Initialize-TheCleanersNativeFileInterop.ps1` | 2,999 | 3,000 |
| `Public/Clear-CurrentUserTemp.ps1` | 3,162 | 3,162 |
| `Public/Clear-OldExchangeLog.ps1` | 2,652 | 2,658 |
| `Public/Clear-OldIISLog.ps1` | 5,795 | 5,805 |
| `Public/Clear-WindowsTemp.ps1` | 2,845 | 2,845 |

The compressed-length differences sum to exactly 90 bytes. Header offsets and the central-directory offset consequently move. This establishes runtime-dependent compressed output as the cause, rather than file-content or entry-metadata drift. It does not identify a specific upstream compressor patch. Microsoft documents the [runtime compression implementation](https://learn.microsoft.com/dotnet/core/whats-new/dotnet-9/libraries#compression) and [.NET 10 ZIP changes](https://learn.microsoft.com/dotnet/core/whats-new/dotnet-10/libraries); neither promises stable compressed bytes across runtime updates.

## Build and evidence flow

1. Check out the exact PR head or push commit. Record and verify the actual Git commit; a PR synthetic merge SHA must not label artifacts built from another checkout.
2. Every PS7 lane runs unit/coverage, analyzer, formatting, generated-help and drift gates, stages the source-layout module, builds one archive, and performs exact-archive integration and isolated clean-install tests.
3. The integration gate verifies the commit, producer, sidecar, archive digest, complete file set, lengths and hashes in the staging directory, extracted ZIP and clean installation. It repeats quiet import, help, aliases and preview-lock probes against the extracted module.
4. Repeat archive generation from the same staged bytes without replacing the tested archive. Keep the second ZIP and `ArchiveRepeat.json` evidence.
5. Upload the exact tested artifact with hidden files included. Windows PowerShell 5.1 downloads the canonical 7.6.6 artifact/archive and runs its source and package tests without invoking the build.
6. The comparison job downloads all three producer archives and runs `.github/scripts/Compare-Archives.py`. Missing lanes, wrong commit/producer, altered file content, sidecar mismatch, noncanonical metadata, compressed entries, repeat mismatch or cross-runtime byte mismatch fail the job. `ArchiveComparison.json` records sizes/hashes and counts.
7. The protected publisher depends on the full reusable workflow, including comparison and strict documentation validation. It stages and verifies the selected tested artifact without rebuilding. This stage does not invoke publication.

Local build: `Invoke-Build -File ./src/TheCleaners.build.ps1`. Use a separate worktree when existing generated outputs need preservation: the build's Clean task removes its own Artifacts, Archive, Reports and GeneratedHelp directories. Never use real cleanup data as fixtures.

## Artifact action and acceptance boundary

The historical Windows PowerShell job annotation identified `actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093` as targeting deprecated Node 20. GitHub's [v8.0.1 release](https://github.com/actions/download-artifact/releases/tag/v8.0.1) resolves to `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c`; its [immutable action manifest](https://github.com/actions/download-artifact/blob/3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c/action.yml) declares `node24` and defaults digest mismatches to errors. The candidate updates both build and protected publish downloads. Successful hosted downloads must verify the changed action; publication itself remains unexecuted.

A PR run is candidate evidence only. After merge, record the exact main SHA and its own job URLs, runtime/OS versions, test totals/failures/skips, coverage and archive comparison before marking runtime/reproducibility subgates validated. TC-008 as a whole remains open for protected publication, published clean install and maintainer release acceptance. Windows/IIS/Exchange product labs and TC-009 hosting/metadata gates remain separate; IIS and Exchange retain their explicit-WhatIf preview locks.
