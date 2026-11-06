# Hex editor integration validation

## Verified source — 2026-11-06

The initial integration was merged through PR #16. Follow-up reliability work
is preserved on `feature/madedit2-hex-editor`; this follow-up does not merge or
deploy changes.

Tested application revision: `9de95342e009e84e4448cf9e25e8ad1e13ce09bd`.
Pinned reusable package revision: `50d033cc70d9121819c890fe587f8b3dc4c82311`
in [CrispStrobe/madedit2](https://github.com/CrispStrobe/madedit2), branch
`feature/crispcloud-hex-package`, path `packages/madedit2_hex`.

[GitHub Actions run 42272446143](https://github.com/CrispStrobe/CrispCloud/actions/runs/42272446143)
completed successfully with Flutter 3.47.8. These are executed results from the
job logs, not an inference from test source or a workflow being configured.

| Environment | Package tests | Application tests | Result |
| --- | ---: | ---: | --- |
| Ubuntu | 24 | 44 native | Passed |
| Chrome on Ubuntu | — | 33 browser | Passed |
| Windows | 24 | 39 native | Passed |
| macOS | 24 | 39 native | Passed |

The Chrome application run includes all three editor-page lifecycle tests,
all eleven storage-session tests, and nineteen text-document tests. The host
tests are enabled; none of those suites are skipped. Native job totals differ
because the Ubuntu job also exercises code-editor widgets and the status bar.

The standalone fork's Linux job also passed the package in Chrome at the same
pinned revision. Its Linux and Windows package jobs passed; macOS package
execution is independently verified by the application run above, after the
vendored-source fingerprint check succeeded.

Local checks passed 24 standalone package tests and the focused 14-test native
host/session suite. Package and focused application analysis reported no errors
or warnings; existing informational style lints remain. `git diff --check` and
`python3 tool/verify_hex_vendor.py` passed. The latter compares source, tests,
license and configuration with the pinned fork's Git blob fingerprints.

## Behavior covered

- Raw-byte insert, overwrite and delete, randomized edits against a reference
  model, immutable snapshots, saved revisions, and two-nibble single-step undo.
- Original-range edits against a synthetic 4 TiB source without reading it;
  exact offsets beyond 32 bits; short-read failures instead of zero padding.
- A shared 64 MiB undo/redo byte budget, including sliced/shared buffers,
  eviction, branching, coalesced edits and externally retained snapshots.
- Search across chunks, cancellation after navigation, queued clipboard/search
  races, keyboard interaction and horizontal caret reveal on narrow screens.
- Immutable native staging, verified saves, external content changes,
  cancellation, copy collisions, and account changes before and during writes.
- Closing during a staged save, rejecting new writes after close begins,
  preserved unsaved edits after conflicts, explicit discard, and read-only
  behavior for backends that cannot verify a staged replacement.

The first attempt to restore the host tests exposed a test readiness race:
absence of a progress indicator could be observed before navigation completed.
The tests now wait for a positive editor or error-page state and yield to real
file I/O. The successful run above includes that correction.

## Practical limits and remaining acceptance checks

Browser editing is capped at 32 MiB and native editing/saving at 8 GiB. Native
preparation copies and verifies the original before editing; it is not an
instant-open remote view. Saving verifies content and rewrites the full result.
The undo byte budget covers retained inserted buffers in history, not current
content, live snapshots, original storage or all process memory.

Providers without server-side conditional replacement retain a final
check/commit race. No universal atomic compare-and-swap guarantee is made.
Physical-device touch, IME and accessibility acceptance, real-provider save
checks, throughput benchmarks and release-binary builds remain separate from
the headless tests recorded here. Editor chrome currently uses English labels.

## Preserved work and maintenance

The GitHub fork is verified as a fork of `madedit/madedit2`. Reusable fixes are
committed there first and then copied into CrispCloud with the pin and source
fingerprints updated together. Host storage policy and routing remain in
CrispCloud. The vendored path dependency avoids a moving Git dependency.

An alternate implementation developed before the shared branch advanced is
retained at commit `f2534d892fbffca9a7e1e95ccaf7faeb02769ea1` on
`feature/madedit2-hex-editor-session-checkpoint`. Its different public API must
not be merged wholesale over the active integration. It preserves the session's
earlier source and tests so no edits are lost.

See `packages/madedit2_hex/UPSTREAM.md` for MIT provenance and the maintenance
pin, and `docs/hex-editor-integration.md` for entry points and save behavior.
