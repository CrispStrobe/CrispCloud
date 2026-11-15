# PNG carving continuation — 15 November 2026

## Recovered starting point

The interrupted turn left `integration/storage-carving-20261115` at
`22f4d709dff82447ea80fe6bcdd2f10d076e0c93`. GitHub confirms that this commit
contains the initial Office reconciliation only. The quoted 158-test run and
PNG implementation from that turn were not present in the remote tree and are
not reused as evidence for this continuation.

All current branches, PR heads and tags were fetched before implementation.
Office reconciliation is being saved on
`integration/office-reconcile-storage-20261115`, including later Excel import
and worksheet-navigation changes. Canonical Quds integration is preserved on
`integration/office-storage-reconcile-20261115` in its own repository.

## Increment

Implement Stage 6's first bounded content-carving profile: complete supported
PNG images found inside a user-selected regular file, reviewed by source byte
offset, exported with a JSON evidence report into a new ZIP. Scanning does not
write. Only validated candidates may be selected. The existing shared queue,
private staging, source/stage hashing and exclusive new-file publication own
the admitted operation. Restart requires a fresh scan and review.

This is a 64 MiB captured-input profile, not physical-device rescue imaging,
filesystem undelete, arbitrary fragment reconstruction or a broader image
format claim. It adds no runtime dependency. First development checkpoints
are intentionally saved before qualification; successful checks will be
recorded with their exact source commit once completed.

## Validation plan

- PNG structure, CRC, zlib completion/Adler, exact scanline shape and filter
  bytes, damaged regions, unsupported profiles, bounded work and cancellation.
- Independently generated Python fixtures and independent ZIP/PNG readback.
- Captured identity, changed source/stage, collisions, pause/Stop, queue
  ownership and restart review, with real UI selection/layout checks.
- Dart/Flutter analysis and relevant existing archive/queue regressions.
- Portable VM and actual compiled JavaScript core execution.

Pending test and platform work is not a passing claim. Linux local gates,
hosted CI and other-platform/live-provider qualification remain distinct.
