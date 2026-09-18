# Temp retention and deletion-handle contract

This packet records the bounded deterministic fixture and contract work in
[issue #30](https://github.com/SamErde/TheCleaners/issues/30). The runtime already
uses native same-handle deletion at source base
`af330858b41335366476f0b845e3f73a3c1497d1`; this packet adds evidence and states its
concurrency limits. It does not enable stable status or replace the deferred
Windows client/server, actual-root, ReFS, filesystem-filter, or hostile-driver labs.
See the [release ledger](release-plan-1.0.md) for current acceptance gates.

## Retention decision

Both temp commands discover a candidate's volume/file identity and use a single
inclusive UTC cutoff. After the command's `ShouldProcess` approval, path/type and
ancestry checks, they open that path using `OpenForDeletion`. Acquisition requests
`DELETE | FILE_READ_ATTRIBUTES`, shares only `FILE_SHARE_READ`, opens the reparse
point itself, and **does not schedule deletion**. It adds no file-content read
permission; the independent permissions evidence belongs to
[issue #29](https://github.com/SamErde/TheCleaners/issues/29).

Each command passes the resulting `$CurrentHandle` to `ReadIdentity`, rejects a
directory, reparse point, missing identity, different volume/file identity, or a
last-write time newer than the plan cutoff, and passes that same handle to
`MarkForDeletion`. The length used for `BytesReclaimed` also comes from this handle,
not discovery or a second pathname lookup. Every exit disposes the candidate
handle; the command's outer `finally` releases retained directory handles.

Retention is defined by the last-write metadata observed from the deletion handle.
It is **not an atomic comparison-and-delete operation**. The following contract is
intentional and tested:

| Change | Result |
| --- | --- |
| Recent or different old regular file replaces the approved object before acquisition | Its file identity differs, so it is skipped and contributes no removed count or bytes. Keeping the original object alive in fixtures avoids accidental file-ID reuse. |
| The same object becomes recent before handle metadata is read | It is skipped, including when content was also changed. |
| The same object remains eligible, including exactly at the cutoff | It may be removed. Bytes are its current observed logical length; stale discovery length is not used. |
| A data writer is already open, even when that writer shares deletion | Deletion-handle acquisition fails with a sharing violation. The result records a file failure and emits `TempFileRemovalFailed`; `-ErrorAction Stop` terminates and releases plan handles. |
| A new ordinary data writer or rename is attempted while the deletion handle is held | Windows sharing rules block it. This includes access through other hard-link names for the same object. |
| An attribute-only writer updates last-write time while the handle is held | Windows can allow it. A later handle metadata read sees the update, but an update after the command's read does not revoke its earlier eligibility decision. |
| The approved path disappears or its file is renamed before acquisition | The command skips the missing name and does not chase the object to its new name. |
| The approved name is relinked to the same approved object | Identity still matches. Removing that name preserves the other hard link; logical bytes counted are not proof of physically freed space. |
| Directory or reparse substitution | It is preserved. Path preflight and same-handle type/reparse checks remain in place. Failures to acquire or inspect are never treated as successful removal. |

The native regression intentionally updates the timestamp after observing an old
timestamp, then requests disposition on the held fixture handle. Deletion succeeds:
`FILE_SHARE_READ` does not make timestamps immutable. A second timestamp check
would only move this race; it would not create an atomic predicate.
Microsoft documents the access/share rules in
[CreateFile](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)
and the distinct `FILE_WRITE_ATTRIBUTES` requirement in
[SetFileTime](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfiletime).

## Threat model and limits

These guards address ordinary user-mode path replacement, rename, traversal and
handle-sharing races on a Windows filesystem that provides the required stable
volume/file identities. Retained ancestor handles prevent a checked parent from
being renamed during mutation; its separate contract and fixtures are tracked in
[issue #28](https://github.com/SamErde/TheCleaners/issues/28). The final component is
opened with `FILE_FLAG_OPEN_REPARSE_POINT` and its handle attributes are checked.
No path-based deletion fallback is permitted.

An actor able to set timestamps can deliberately backdate content before the
observation or change the timestamp afterward using attribute-only access. The
cleaner is not a hostile-writer transaction system. File-ID recycling after an
object is destroyed, filesystem filters, kernel/administrator interference,
pre-existing writable mappings, unusual delayed timestamp behavior, and
filesystems without the expected identity/sharing semantics are outside this
bounded guarantee. No test here establishes atomic metadata snapshots across the
separate native information queries or atomicity between metadata and disposition.

Byte totals describe logical lengths for successfully reconciled removed names.
Hard links, allocation, and concurrent deletion-pending behavior can make actual
free-space changes differ. Existing post-close failure reconciliation remains in
place; DELETE-PENDING, ROOT-RACE and HANDLE-RECOVERY hostile drivers remain deferred.

## Deterministic acceptance evidence

The new [TempRetentionHandle.Tests.ps1](https://github.com/SamErde/TheCleaners/blob/main/src/Tests/Unit/TempRetentionHandle.Tests.ps1)
suite inserts a synchronous mutation at the last path resolver return before
native acquisition. Discovery, approval and path preflight have already occurred;
the public command and native deletion implementation remain unmodified. The
tests assert that the barrier ran exactly once. This avoids timing sleeps,
probabilistic races, production instrumentation, and replacing native deletion
with a mock. Windows-root resolution is mocked to the disposable fixture root;
environment variables and held writers are restored after every test. Junctions
are removed as links before fixture teardown.

| Issue criterion | Evidence |
| --- | --- |
| Recent and different old regular replacement | Both commands reject each replacement at the acquisition barrier, preserve the original renamed object and replacement bytes, and reconcile skips/bytes. |
| Same-handle age, identity and type; acquisition without disposition | Public command/native call-chain review; native open/read/close preserves bytes; replacement, timestamp and current-length behavioral cases fail if stale discovery values authorize removal. Existing `TempCandidateSafety.Tests.ps1` covers native file and directory rename denial while held. |
| Concurrent metadata/content updates | Both commands test same-object timestamp/content updates before acquisition and the inclusive cutoff/current length. Native tests verify data-writer denial, allowed attribute-only writes, fresh handle observations, and the non-atomic disposition limit. |
| Disappearance, directory/reparse swaps, renamed paths and hard links | New acquisition-barrier renamed-path, directory/junction substitution and same-object relink fixtures for both commands; existing `TempCandidateSafety.Tests.ps1` and `IdentitySafety.Tests.ps1` retain disappearance and link guards. Junction target contents are checked; this is not a privileged file-symbolic-link or filesystem-filter lab. |
| Sharing errors, Stop, counters and bytes | Both commands verify late writer failure with native error 32, stable error ID/category, zero removals/bytes, and Stop unwinding with a successful root rename afterward. Access-mask/ACL cases remain independently evidenced in issue #29. |
| Approval and permissions boundaries | Both commands prove WhatIf never reaches acquisition. Existing Confirm tests and the native no-content-read access mask are unchanged. |

### Local checkpoint

Local evidence is recorded against base `af330858b41335366476f0b845e3f73a3c1497d1`
plus the uncommitted new test and this document, using isolated Pester **5.7.1**.
It is draft fixture evidence, not an exact merged-commit or hosted-matrix claim.
The native helper is explicitly initialized before Pester in the Windows
PowerShell 5.1 process. Both runtimes are launched with `-NoProfile -NonInteractive`.

| Runtime | Total | Passed | Failed | Skipped | Not run |
| --- | --- | --- | --- | --- | --- |
| PowerShell 7.6.6 | 28 | 28 | 0 | 0 | 0 |
| Windows PowerShell 5.1.26100.9444 | 28 | 28 | 0 | 0 | 0 |

The tested new file's SHA-256 is
`a8d0a1be296e8618ae7ce47174218b777506913b9711d88381529c9af887d429`.
`git diff --check` and the new files' whitespace checks passed. No runtime source
behavior was changed; the integration also clarifies comment-based help. This local checkpoint does not claim execution on PowerShell 7.4 or
7.5; the exact-head hosted matrix remains the integrator's next validation gate.

The retained machine-readable reports are `src/Reports/issue30/ps7-final.xml`,
`ps7-final.json`, `ps51-final.xml`, and `ps51-final.json` (ignored local evidence).
The integrator records exact final-commit and hosted runtime evidence in the
release ledger before issue closure or any stability decision.

### Committed integration checkpoint

Exact clean commit `1f6a28e1da328440f1942c66648e9991ba3c5522` passed the 28 new
cases plus four documentation-contract tests: **32/32** on PowerShell **7.6.6**
and Windows PowerShell **5.1.26100.9444**, using Pester **5.7.1** on Windows
**10.0.26200.0**. Both runs had zero failures, skips and not-run tests. The new
test hash remained the value above. The strict clean Zensical **0.0.62** build
and configuration validation passed. This is local exact-commit evidence; the
PR's final-head hosted matrix and merge results must be verified separately.
