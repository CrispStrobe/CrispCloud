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

## Remote checkpoints

- `dad7a232d22a0bb3863feff4304eac249be943e6`: recovered PNG scanner,
  workflow, queue/UI and initial tests. Development save; no qualification.
- `c1494c40c8b0624b2ee1344b233c8128c54f5183`: merged the full Office
  reconciliation at `59b6a50990c4a368e03cd4d03b8075248edc6ffb`, including
  navigation `8c7f8ac7` and canonical Quds `01f167cc`. All observed app/PR
  heads at that first snapshot are contained in this merged history.

- `229c6a8609b9f78ebe1bff1e4f8e7e9e0fea6417`: complete PNG profile,
  independent fixtures, guarded native publication and regression tests.
  Saved before final qualification.

The complete implementation checkpoint adds independent fixtures/portable drivers,
strict parser tests, native guard regression tests and a guard that rechecks
identity/cancellation synchronously after the final asynchronous path read.
A pause epoch comparison also detects pause-and-resume within that final read;
publication repeats the full source/stage proof before continuing.

Development evidence: eight independent source cases pass 248 assertions on
Dart VM and actual compiled JavaScript; Python separately verifies eight ZIPs
and ten PNGs. These observations precede final guard qualification and do not
qualify the whole app. The initial scoped analysis reported 29 style infos,
which were corrected. The first baseline native attempt passed 132 tests then
hit an in-progress API mismatch while compiling the final UI suite; that suite
will run again against the complete checkpoint.

## Latest-source reconciliation and qualification boundary

A final remote cutoff at 06:34:41–06:37:21 UTC found newer main and worksheet
navigation work. The combined candidate incorporates app main `fa030137`,
navigation `7e5af83c`, Quds main `eae58542` and DOC parser `d422fa99`.
`remote-cutoff-audit.json` retains the exact heads, advertised refs, PR states
and CI observations. The managed-source check passes for all 2,214 files.

The first source-bound native gate at `229c6a86` stopped before any test ran:
the optional system-SQLite launcher requested an unversioned `libsqlite3.so`
that this host does not provide. Its receipt is retained as a bootstrap failure,
not a failed test assertion. Qualification uses the default native hooks that
already compiled and ran the baseline cohort on this host.

Final gates will identify the saved source commit and tree, hash the local
source and package-resolution inputs before and after each command, and retain
raw logs. Resolved external dependency-cache payloads are not archived; these
are source-bound local results, not a hermetic execution claim. Hosted CI,
complete Office rendering/schema acceptance and other platforms remain
separate qualification scopes.
