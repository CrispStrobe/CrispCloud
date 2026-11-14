# Bounded binary comparison of captured files

The existing Compare dialog's **Binary** mode compares bytes at the same
offsets, groups contiguous unequal positions, and navigates their Hex windows.
The continuation on `integration/storage-binary-20261114` binds that interface
to verified, owned input copies. Review: [PR #104](https://github.com/CrispStrobe/CrispCloud/pull/104).
Qualification records and the exact tested revisions are kept separately in
[`evidence/storage-binary-20261114/`](evidence/storage-binary-20261114/).

## User-visible behavior

Use the existing file comparison command and select Binary. Files larger than
the text comparison's 8 MiB limit start in Binary mode. The dialog first prepares
and verifies the copies, then reports compared bytes, unequal byte positions,
changed ranges and the current range. First/previous/next/last controls and a
decimal or `0x` hexadecimal address navigate the existing side-by-side windows.

The result is explicitly labelled **Verified captured copies**, together with
the applicable per-file limit. It describes the captured bytes. A later live
rewrite cannot silently change the bytes behind the saved difference index.
Available metadata changes and account/source revocation invalidate navigation.
If content changes while preserving all available metadata after capture,
the view continues to show its original owned bytes; compare again to observe
the new content.

Closing, swapping files, changing modes or reloading releases the private
copies. Stop cancels preparation or navigation and retires that comparison;
the dialog remains open. Failed or obsolete asynchronous operations cannot
publish an earlier result into a newer dialog state. No comparison action writes
to either source.

## Capture and identity

Each input is admitted as a regular file with a path. Directories and declared
symbolic links are refused. Capture retains the backend/account identity, path,
available object and version metadata, measured byte length and SHA-256 digest.
Version/ETag tokens retain their comparison semantics; none is treated as a
universal content hash. Mutable provider metadata cannot rewrite a saved token.

1. Check the selected file against current metadata and reject known oversize
   inputs before starting a byte read.
2. Read into private storage while enforcing actual length, byte, chunk, empty
   chunk and elapsed-work allowances. Hash the same owned bytes being captured.
3. Check metadata again and read the source a second time, bounded by the exact
   captured length and the same allowances.
4. Require an identical SHA-256 digest and matching available metadata before
   admitting the capture. A newly available size must equal the measured size.
5. Build the comparison and all subsequent rescans/windows from the owned
   copies. No live-source byte range is reopened during navigation.

Native copies reuse the private transfer spool and positional file-source
primitives. Browser copies use bounded memory. Returned byte buffers are owned
by the caller and cannot mutate the retained snapshot. The second read detects
observed content changes that timestamps and sizes alone would miss.

Two matching complete reads do **not** prove an atomic snapshot from a provider
without snapshot/conditional-read support. They also do not capture both files
at one instant: inputs are prepared sequentially. This profile does not promise
that original content stays unchanged after the capture was verified.

## Resource profile

| Resource | Default bound |
| --- | --- |
| Native captured input | 8 GiB per file, up to two private disk copies |
| Browser captured input | 32 MiB per file, up to two retained copies; construction has additional transient allocations |
| Declared length | Exact; both early EOF and overrun are errors |
| Unknown length | Measured during the first read and enforced exactly on the second |
| Provider chunks | 1,048,576 per input per complete read/scan |
| Empty chunks | 1,024 total per input per complete read/scan |
| Capture/read parts | At most 64 KiB per owned part |
| Hex window | 1 KiB by default; explicit requests at most 64 KiB |
| Sparse index | 2–4,096 configured checkpoints, plus a retained last range |
| Recent resolved ranges | At most 128 |
| Overall opening work | 30 minutes across capture, verification, scan and final checks |
| Individual source inactivity | 30 seconds; empty chunks do not count as progress |
| Cooperative scheduling | Yield when 64 input chunks or 1 MiB of byte work has accumulated; byte checks occur after parts of at most 64 KiB |

The browser byte ceilings bound retained input payloads, not the process heap.
Consolidating accumulated chunks can temporarily require an additional
input-sized contiguous allocation, alongside provider chunks and runtime
overhead. Closing a browser capture drops its retained buffer even if the
closed session object remains referenced.

Input producers must respect stream pauses and keep the current buffer stable
while paused. The comparison opts into synchronous cancellation-wrapper
delivery so a pull consumer's pause reaches a producer before it resumes and
reuses that buffer. Other transfer-queue callers retain their existing delivery
behavior. Providers that mutate a buffer independently of stream backpressure
are outside this input contract.

Callers may lower input ceilings; they may not enlarge the platform ceiling.
Chunk/time options are explicit finite budgets, not promises that every file
under the byte ceiling is admissible. A provider emitting extremely small or
empty chunks may exhaust its work allowance. Metadata waits and pending provider
reads observe cancellation/account invalidation through periodic checks.

Native allocation, flush, open, close and removal are awaited to preserve
resource ownership. A blocked operating-system filesystem call is not forcibly
interrupted by a Dart timeout. Failed or cancelled captures remove private
storage after ownership can be resolved. Normal failures and successful close
are covered by cleanup tests; a process/host crash does not constitute completed
cleanup. These temporary copies are not durable recovery jobs.

## Comparison semantics

A changed range is a maximal contiguous run of differing byte positions. An
unmatched tail belongs to the last contiguous run if it follows differing
positions without an equal-byte separator. Files of equal length with identical
bytes have zero ranges; empty/nonempty inputs produce one unmatched tail.

This is same-offset comparison. An insertion near the start can make many later
positions differ; the scanner does not infer shifted matching sequences,
filesystem equivalence, semantic document changes or patch instructions.

The index remains sparse as the number of ranges grows. Missing ranges are
resolved by rescanning captured bytes from the nearest saved predecessor.
This trades bounded memory for additional local reads. The stream-only
`compareBinaryStreams` utility also enforces the byte/work/time profile and
optional exact lengths, but does not itself establish file/account identity;
the file/session API supplies that capture contract.

## Failures and capability boundaries

Limit exhaustion, source changes and cancellation have separate typed errors;
inactivity/elapsed-work failures use `TimeoutException`. Underlying read errors
remain read errors. They do not trigger a fallback to unbounded or live-source
navigation. Any operational navigation failure, including Stop, retires the
session. Invalid navigation arguments are rejected before beginning work.

No new runtime package, imported third-party implementation or license grant is
added. Existing SHA-256, transfer spooling and positional-source primitives are
reused. The new work does not introduce patch application/export, deleted-file
recovery, carving, rescue imaging, repair, journal replay, physical-device
access, partition editing or filesystem writes. Those remain independently
scoped stages in the [storage roadmap](storage-capabilities-20261114.md).
