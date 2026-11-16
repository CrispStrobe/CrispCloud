# Terminal session optimization, 16 November 2026

This continuation starts at `0c43c476ff33638306425c1427cf1d04a170a912`
and saves incremental checkpoints to
`codex/terminal-session-optimization-20261116`. Commits carry `[skip ci]`.
GitHub Actions are not queried, polled, awaited or rerun.

## Integrated baseline

The independent initial remote inventory contains all 43 branch heads and all
156 advertised PR heads. Every head is an actual ancestor of the starting
commit, including main `5d3a020d`, terminal PR #160 and Zotero PR #161.
No content merge or dependency-pin replacement is required. The saved
[inventory](integration-snapshot.json) also includes the newly created
continuation branch: 44 branches plus 156 PR heads, all 200 included.

A fresh cutoff found later recovery evidence and Zotero optimization. Merge
`94857cf415965826b8ed08eafd3b05dafc29b353` integrates `b48a58fa`, which also
contains terminal head `3fb3eed4`. All **45 branch heads and 156 PR heads** at
that cutoff are now actual ancestors. Its tree matches the independently
reviewed clean merge. The [post-integration audit](final-integration.json)
records exact refs, parents, and canonical source comparisons. The Office
inventory now verifies 2,411 files at Quds `91c725fe`, with all seven changed/new
files matching the canonical Git blobs and modes.

## Changes and checkpoint status

- Ordinary terminal sessions keep one in-flight resize and the latest pending
  dimensions. Same-turn layout events coalesce, completed dimensions are not
  resent, and replacement/disconnected sessions revoke stale work.
- Screen exact attachment preserves full listing identifiers and validates
  listing completeness before selecting a target. Unsupported names must not
  be truncated into a different selectable session.
- Native tmux serializes resize requests, retains the last requested geometry
  even when it equals the previous completed size, and shares one completion
  per pending generation. The viewport also cancels an obsolete debounce when
  its dimensions return to the previously sent size.
- Native tmux captures up to eight panes per synchronous command group while
  retaining reply ordering and atomic workspace publication. A controlled
  20-pane fixture requires three capture writes instead of twenty. This is a
  protocol count comparison, not a measured end-to-end speed claim.
- Grouped captures preserve one hard response budget per pane at the reply
  queue head. Later panes and queued input do not age behind a progressing
  snapshot, while partial replies cannot extend the active pane's deadline.
  The 256-command admission limit remains in place.

The first implementation checkpoint is intentionally saved before the complete
Flutter qualification. Local commands and outcomes will be added as they finish;
historical acceptance from earlier commits is not counted as new validation.

The [Screen resolver before/after proof](screen-resolver-regression.json) runs the
extracted production shell through actual `/bin/sh` and `awk` with controlled
Screen listings. It qualifies command resolution, not a live GNU Screen daemon.

## Development findings retained

The first full native run passed 1,064 tests with two platform skips and seven
failures, all in terminal resize handling. xterm invokes its callback before
updating the stored viewport dimensions; capturing those fields synchronously
used the previous size. The corrected implementation uses the callback's
dimensions, and the unchanged 20-test session suite passes. The first complete
run and its unchanged source inventory remain under
[`development/first-native`](development/first-native/).

The first incoming Office command ran pure-Dart engine tests through the root
Flutter graph, which does not declare `package:test`: four files failed to
load while all 39 editor-dialog tests passed. The engine is being qualified
through its own declared development graph without changing the application's
production manifests or lockfile. That runner mismatch is preserved separately
from feature-test outcomes.
