# Shared HTTP transfer bandwidth continuation

## Preserved baseline

- Main source: `022ac6c91ccaa86f1d36a4d8cc1b20733037a67d`.
- Remote continuation: `integration/storage-bandwidth-20261114`.
- The earlier captured-comparison continuation and evidence checkpoint
  `f69427d5` are already incorporated in this baseline.
- Root `CLAUDE.md` pins Flutter 3.47.8 / Dart 3.13.7. Production manifests,
  source identity rules and the storage roadmap's dependency policy remain
  unchanged.

The previous storage workflow now provides actual hosted Chrome evidence for
comparison source `22bd67b8`: 31 browser cases passed, as did its 1,373-test
native storage cohort. The overall workflow later failed because the external
FatFs reference archive server timed out. The independent
[`hosted-22bd67b8` evidence](../storage-binary-20261114/hosted-22bd67b8/README.md)
preserves that distinction without relabelling the whole workflow successful.

## This increment

Advance stage 7 and G29 through a bounded, usable foreground HTTP profile:

1. A pure shared allocator with independent upload/download pools, fairness by
   stable operation ID, bounded quanta, no idle burst credit and cancellable
   lifecycle. Batch tasks under one operation share one fair identity.
2. Captured operation context propagated through queued execution and retained
   across stream creation/subscription. Pausing/cancelling an operation wakes
   its requests; queue pause continues to control admission only.
3. Bind supported native HTTP request bodies after preparation/encryption,
   including buffered and multipart bodies, and bounded response/download
   streams at the existing common helpers. Retries consume budget again.
4. Persist independent limits atomically, with zero meaning unlimited. Use one
   policy owner for existing Network settings and Activity controls. Display
   covered HTTP payload rates separately from logical file progress.
5. Qualify the allocator deterministically on Dart VM and JavaScript, HTTP
   handoff/loopback behavior, queue lifecycle, persistence and localized UI.

The claim is limited to covered HTTP helper paths in this foreground runtime.
Unhooked provider methods, FTP/SFTP/SMB, separate background runtimes and browser
uploads remain outside enforcement. Browser request-body collection must not be
described as upload throttling. Local spooling/hashing and server-side payload
copies do not acquire a transport budget. Existing per-operation logical-copy
pacing keeps its separate contract.

## Ownership and checkpoints

Root owns transport hooks, queue integration, evidence and all Git mutations.
The pure allocator/context and the policy/UI have separate implementation
owners. Toolchain restoration uses scratch-local verified tooling and the
unchanged original lockfile.

Every coherent increment is saved remotely as an ordinary descendant commit.
This initial checkpoint contains the scope and prior hosted evidence only;
no new bandwidth implementation or passing gate is claimed yet.

## Implementation checkpoint

The allocator, captured queue context, finalized HTTP request and response
hooks, persistent policy owner, Network settings and Activity controls are now
implemented. The independent allocator driver has passed 24 deterministic
cases on Dart VM and the same 24 cases after actual JavaScript compilation and
execution. Scoped analysis is clean for the allocator and UI-owned files.
These are working-tree development checks; source-bound qualification follows
a saved implementation revision.

The restored native toolchain has completed a 22-case queue/control/logical
limiter warmup. The new queue, HTTP and widget cohorts are still being checked;
this checkpoint does not claim their acceptance. Native HTTP tests and the
final coverage document will be saved in a subsequent checkpoint.
