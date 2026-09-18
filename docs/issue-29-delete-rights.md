# Issue #29: deletion rights and native file identity

This note records the bounded non-lab closure evidence for
[issue #29](https://github.com/SamErde/TheCleaners/issues/29). It applies to the
exact source and test results recorded below. It does not establish Windows
client/server product acceptance, actual Windows-root cleanup, or ReFS runtime
acceptance; those remain TC-003/004 release gates.

No executable runtime source changed in this packet. The base implementation
already met the selected native contract; the new work supplies the missing
both-command ACL, error, identity, and reconciliation evidence.

## Native contract

Both temp commands discover a candidate and capture its volume serial number,
128-bit file ID, attributes, logical length, UTC last-write time, and parent
identity. After `ShouldProcess`, the command opens the current literal path with
`CreateFileW` using these values:

| Field | Value | Reason |
| --- | --- | --- |
| Desired access | `DELETE | FILE_READ_ATTRIBUTES` | Permit same-handle metadata validation and disposition without `FILE_READ_DATA`. |
| Share mode | `FILE_SHARE_READ` | Permit readers while preventing content/data-write, rename, or other delete opens during validation and disposition. |
| Creation disposition | `OPEN_EXISTING` | Never create a missing candidate. |
| Flags | `FILE_FLAG_OPEN_REPARSE_POINT` | Inspect the link itself and reject reparse points instead of following them. |

The requested share-read/write/delete combination from the issue comment was
reviewed and intentionally narrowed. Microsoft documents that
`FILE_SHARE_WRITE` permits later write opens and `FILE_SHARE_DELETE` permits
later delete or rename opens for the lifetime of the handle. Those operations
would weaken the race boundary after identity and retention validation. The
safer contract allows concurrent reads while excluding content/data writers and
delete/rename opens. An existing incompatible content writer or delete/rename
handle produces a sharing violation, which the owning command reports as
`TempFileRemovalFailed`; it does not force deletion.

Windows does not apply share-mode conflicts to attribute-only access. A caller
with `FILE_WRITE_ATTRIBUTES` can therefore change a timestamp while this handle
is open. The command reads the final retention timestamp from the deletion
handle immediately before setting disposition, but Windows offers no atomic
check-and-delete operation for this sequence. Issue #30 owns the exact
concurrent timestamp observation contract and its deterministic regressions;
this share-mode decision does not claim full object or timestamp immutability.

The command reads `FILE_ID_INFO`, `FILE_STANDARD_INFO`, `FILE_BASIC_INFO`, and
`FILE_ATTRIBUTE_TAG_INFO` from that opened handle. It compares volume serial
number plus all 16 file-ID bytes with the discovery snapshot, rejects a
directory, reparse point, different identity, or now-recent file, and only then
calls `SetFileInformationByHandle(FileDispositionInfo)`. It never reopens the
path between validation and disposition. Any native open, identity, metadata,
or disposition failure throws and is reported through the command error stream.

Microsoft's Win32 documentation defines
[`FILE_ID_INFO`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_id_info)
as a volume serial number plus a 128-bit file ID and directs callers to compare
both values to determine whether two handles represent the same file. The
[`SetFileInformationByHandle`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfileinformationbyhandle)
documentation requires `DELETE` access for `FileDispositionInfo` and lists ReFS
as supported. The
[`CreateFile` documentation](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)
defines the share flags, `OPEN_EXISTING`, and
`FILE_FLAG_OPEN_REPARSE_POINT`, and also lists ReFS as supported.

## Deterministic acceptance mapping

`src/Tests/Unit/TempDeletionRights.Tests.ps1` runs each command against its own
isolated fixture beneath Pester's temporary directory:

| Issue requirement | Evidence |
| --- | --- |
| Delete an old candidate when content reads are denied | An explicit current-token deny ACE for `ReadData` and allow ACE for `Delete` are verified; a real `FileStream` read must throw `UnauthorizedAccessException`, including when the process is elevated; the native metadata/deletion handle succeeds and the command reports one removal and four reclaimed bytes. |
| Report denied deletion and honor `-ErrorAction Stop` | The file denies `Delete` and its parent denies `DeleteSubdirectoriesAndFiles`, closing both Windows authorization routes. The non-terminating case reports one `PermissionDenied` error and reconciles failure/removal/skip/byte counters; the terminating case must throw `TempFileRemovalFailed`. |
| Preserve a directory replacement | The read-denied file is removed after real discovery and replaced by a directory. The command preserves it and reports one skip. |
| Reconcile disappearance | The read-denied file disappears after real discovery. The command reports one skip, no failure, and no reclaimed bytes. |
| Use a 128-bit identity and fail closed | A real native identity must expose 32 hexadecimal file-ID digits. Synthetic identities prove equality compares the volume serial and every one of the 16 file-ID bytes, including each byte in the upper 64 bits; otherwise identical IDs compare unequal when any byte changes. Equal cloned arrays compare equal, while length, timestamp, and attribute differences do not change the intentionally volume-plus-file-ID equality contract. The source contract requires a 16-byte `FILE_ID_INFO` buffer, and an invalid handle must produce the underlying `Win32Exception` instead of a path or partial identity fallback. |
| Avoid provider path deletion | The existing `TempCandidateSafety.Tests.ps1` AST regression verifies that neither owning command calls `Remove-Item` for candidate deletion and that both use `OpenForDeletion` plus `MarkForDeletion`. |

The ACL is restored before fixture cleanup whenever the denied candidate remains.
Every opened stream, safe handle, Windows identity, and redirected `TEMP`/`TMP`
value is disposed or restored in test cleanup.

The same-type recent/old replacement, post-preflight reparse substitution,
rename/relink, and concurrent content/timestamp observation cases are owned by
issue #30 rather than duplicated here. [PR #42](https://github.com/SamErde/TheCleaners/pull/42)
merged them as `3d07e9ccbfd441c388b1a3a69edc92fc326a4a66` and closed issue #30.
Its exact reviewed head `719750ce8c7fd3142b24261b8b75d09499e9f840` passed
[build 35330950539](https://github.com/SamErde/TheCleaners/actions/runs/35330950539):
333 unit plus four integration tests on each supported PS7 lane and 337 combined
tests on PS5.1, with zero failures/skips/not-run. That is PR-head evidence;
merge-source verification remains separate. This packet is based on the merge
and will run the combined suite on its own final head before closure.

## ReFS disposition

The implementation does not use the legacy 64-bit file index. It marshals the
documented 16-byte `FILE_ID_128`, combines it with the volume serial number, and
compares every byte. `GetFileInformationByHandleEx` failure is not converted to
a path identity or an empty result: it throws a native error, and the command
preserves the candidate. Microsoft documents ReFS support for the open and
same-handle disposition APIs used by this design.

The validation host exposed NTFS volumes only. The focused tests therefore
establish NTFS behavior and the 128-bit/fail-closed API contract, but they do not
claim an executed ReFS filesystem result. A later approved ReFS TC-003/004 lane
must still record the volume/build, raw `FILE_ID_INFO` behavior, ACL cases, race
cases, results, and recovery. No ReFS volume was provisioned or substituted for
this non-lab issue packet.

## Local validation

The PR review follow-up working tree based on exact head
`5f93ae011e1117eb1030b814ca6e059829708f8f` passed **12/12** focused
`TempDeletionRights` tests on PowerShell **7.6.6** and Windows PowerShell
**5.1.26100.9444** with pinned Pester **5.7.1**. Both runs had zero
failures/skips/not-run. The machine-readable reports are
`TestResults/issue-29-review-pwsh7.xml` and
`TestResults/issue-29-review-winps51.xml`. The tested CRLF-normalized test file
SHA-256 is `50d67f3a8cbe8e008815b02045c58183e2afaf4e505edee28cb2598884e90037`.
This is dirty-working-tree review evidence until the follow-up is committed and
validated at its immutable PR head.

After integration onto issue #30's merge, exact clean commit `51ef3783f8f89c15b870042579c09a6073e816f3` passed **15/15** tests (11 new cases plus four documentation contracts) on PowerShell **7.6.6** and Windows PowerShell **5.1.26100.9444**, with Pester **5.7.1** on Windows **10.0.26200.0**. Both runs had zero failures/skips/not-run. Strict Zensical **0.0.62** and the complete PR-range whitespace check passed. The tested new file's SHA-256 was `29fb813d9d3cccab6599fd8fcdc7bbbedbfc98700e8bc91a2d6dd455cf331764`. Final-head hosted validation and merged-source verification remain separate gates.

The earlier implementation checkpoint below is retained as historical evidence.

The tested boundary starts at base commit
`af330858b41335366476f0b845e3f73a3c1497d1` with only this issue's new test and
evidence document dirty. Both focused runs used the exact Pester 5.7.1 module
that CI pins, imported by absolute manifest path. Native interop was initialized
in each host before Pester created its test scopes.

| Runtime | Pester | Report | Result |
| --- | --- | --- | --- |
| PowerShell 7.6.6 Core | 5.7.1 | `TestResults/issue-29-pwsh7.xml` | 11 passed, 0 failed, 0 skipped, 0 not run |
| Windows PowerShell 5.1.26100.9444 Desktop | 5.7.1 | `TestResults/issue-29-winps51.xml` | 11 passed, 0 failed, 0 skipped, 0 not run |

An immediately preceding supporting run also passed all 95 tests in
`TempDeletionRights`, `TempCandidateSafety`, `TempFailureBranches`,
`CleanupBehavior`, and `IdentitySafety` under each host. That broader result was
recorded before the new test file received its mechanical LF-to-CRLF workspace
normalization, so it is historical regression evidence rather than exact-byte
evidence for the final working copy. The two 11-test XML reports above were
regenerated after normalization and are the exact local evidence for this
packet.
