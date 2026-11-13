# Archive operation queue and background packing

Implementation branch: `feature/archive-operation-queue-20261113`.
The continuation retains current main `3d9a8823e9e9d0830af433241dcc09bdc73a3901`
and the previous archive acceptance documentation through
`8d17b8d28b45d987a1bb6bf8d6dae62ee000bfa2`.

## Delivered workflow

| Action | Result |
| --- | --- |
| Create archive → Start | Admit a durable job to the shared queue and observe it in the dialog |
| Create archive → Queue in background | Save the recipe and return to the file manager after admission |
| Running creation → Run in background | Detach the progress view while the existing job continues |
| Edited workspace → Save in background | Confirm the current draft changes, then queue packing, verification and publication |
| Pause / Resume | Keep the live encoder and temporary candidate at cooperative checkpoints |
| Stop / Stop all | Wake paused jobs, cancel workers and settle unpublished work; preserve already-confirmed publication |
| Operations menu | Use the existing queue priority, ordering, concurrency and scheduled-start controls |
| History and recovery | Review an interrupted creation recipe or an available session draft using archive-specific recovery |

Archive jobs share the existing transfer scheduler and journal. They reserve
selected source paths for reading and the destination directory/output for
writing, so a conflicting copy, move or another archive job waits. An active
paused job retains its worker slot and reservations. Queue pause controls new
admissions; selected-row pause controls also affect eligible active jobs.

The application owns admitted jobs. Closing a progress dialog or navigating a
pane does not cancel them. Completion refreshes already-open panes, and a failed
refresh or observer does not change a verified publication into failure.
Completed scheduler tasks release their closures rather than keeping passwords,
backend clients or closed draft buffers alive in a second history cache.

The background entry points cover native archive creation and explicit workspace
Save. Paired archive moves, archive imports and folder synchronization retain
their existing reviewed transaction coordinators and authority checks. Browser
packing controls do not claim a native worker. Jobs run while the app is alive;
this is not an operating-system service or unattended restart mechanism.

## Worker and storage boundaries

The native worker runs the codec in a separate isolate. The main isolate keeps
the captured backend clients, input stream factories and unpublished output
sink. The request/acknowledgement protocol permits one outstanding request and
limits payload messages to 256 KiB. Writers that need multiple source passes,
such as stored RAR, request fresh streams. Writer and sink backpressure remain
bounded; there is no whole-archive isolate message.

The writer bridge supports the existing streamed and buffered writers, including
ZIP/7z/TAR/TGZ, stored RAR, ISO, DMG, raw HFSX creation, compression wrappers and
package profiles. It preserves compression and protection options. Opaque
verified DMG filesystem profiles cross the same-code isolate boundary as their
actual objects; the bridge never turns verification authority into JSON flags.

Pause checkpoints cover source scanning, input/output, codec work, candidate
verification and publication preparation. Stop interrupts stalled input and
paused checkpoints and terminates the writer. A private directory owned by the
parent holds worker codec spools and is cleaned after worker exit, including a
crash. Cancellation listeners are detached on completion.

The short original-to-backup/install-or-restore publication transaction is not
suspended with the original absent. Before that boundary, a pause invalidates
stale source/candidate proofs and triggers revalidation. Verification deadlines
exclude intentional pause time. A returned publication receipt is authoritative:
a late Stop or completion observer error produces a separate warning while the
archive remains completed.

Existing format, metadata, protection and size policies still apply. Eligible
native ZIP/7z/TGZ and container paths retain their configured 8 GiB bounds;
protected/buffered profiles retain their existing smaller bounds. Background
execution does not make unsupported layouts writable or imply unlimited size.

## Saved jobs and recovery

Creation recipes are flushed before admission. They contain the original
storage references, selected roots, destination name, format, compression and
whether a password is required. Passwords and authentication objects are never
written to the journal. Publication checkpoints add the packed length/SHA-256,
entry count, backend stage information and a sorted source-manifest digest.

After interruption, recovery requires the exact original storage and a reviewed
recipe. It checks selected-source witnesses, then starts a fresh private
candidate. Once a source manifest has been recorded, the restart also refuses
changed source bytes even when their size and modification time are restored.
It does not append to a partly compressed stream at a guessed offset.

An occupied destination is never silently replaced. An existing output can be
reconciled only by a complete matching length/hash proof against the recorded
candidate. A pause during this proof requires a full reread from byte zero after
Resume. Generic copy/move execution and backup restoration refuse archive job
markers, including a damaged archive recipe.

Background workspace jobs retain their draft and handles while the application
is running. Failed/stopped drafts remain available for review and retry in that
session, or explicit dismissal. An already-started publication continues to use
the durable archive publication journal. Arbitrary in-memory draft reconstruction
after process exit is not implemented. A restored job is never automatically
started solely because its saved scheduled time has arrived.

## Verification

The direct worker receipt is [archive-writer-worker-verification.json](archive-writer-worker-verification.json).
Its six focused probe groups passed: streamed formats/raw HFSX, buffered options
and protection, opaque DMG preservation, pause/backpressure, stalled/paused
cancellation, and protocol/codec/sink failure cleanup. Targeted static analysis
passed; the receipt records the exact Dart SDK and source hashes.

Each large worker probe packed and completely reread **2,147,483,665 bytes**
(2 GiB plus 17), with a matching fixed SHA-256:
`b5c0eee7c54826eeb55e9625703f26d88693a678318e5a8534bfc570de17d5af`.

| Worker | Packed bytes | Observed packing time | Sampled process RSS growth |
| --- | ---: | ---: | ---: |
| ZIP | 2,087,416 | 8.018 s | 130,588,672 bytes |
| 7z | 925,826 | 44.649 s | 44,199,936 bytes |
| TGZ | 2,087,363 | 10.441 s | 23,142,400 bytes |

These are highly compressible logical-payload checks, not physically >2 GiB
archive files. They ran sequentially in one warmed Dart process; RSS sampling
is observational rather than an exact peak-memory guarantee. The earlier
[archive container runtime acceptance](archive-containers-runtime-verification.md)
retains separate physical-container and complete publication evidence.

Hosted acceptance is in progress for source
`c7523ab53447b19d461b7c759b90191c1b59ede8` in
[run 43383115342](https://github.com/CrispStrobe/CrispCloud/actions/runs/43383115342).
The workflow combines archive and transfer regressions, the new queue/recovery
and widget suites, and three explicit worker gates above 2 GiB. Its artifacts
record exact commands, dependency hashes, completed test events and receipts;
large cases must finish without being skipped. No local Flutter run is claimed.

## Commander comparison

Double Commander documents queue admission, reordering, pause/continue, stop
and minimizing progress into an operations panel. Total Commander explicitly
documents packing large archives in a separate background thread. This
continuation implements the requested shared-queue controls and native
background packing for the workflows described above. It does not claim every
external packer/plugin feature or cross-process reconstruction of a live encoder.

Primary references checked on 13 November 2026:

- [Double Commander operation queue and progress controls](https://doublecmd.github.io/doc/en/copymove.html).
- [Total Commander background archive packing](https://www.ghisler.com/featurel.htm).
- [CrispCloud shared queue semantics](transfer-queue.md).
- [Remaining archive-format and plugin parity limits](archive-parity-large-continuation.md).
