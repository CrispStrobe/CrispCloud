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

The final fixed inventory, recorded at **10:47:11 UTC**, contains **46 branch
heads and 159 PR heads (205 references)**. Integration `df18aed3` preserves every
one as an actual ancestor, including latest main `b9772e1a`, the original
squash-equivalent ODS PR #168, Zotero PR #167 and the newer terminal recovery
evidence. Its tree and four ordered parents match the reviewed ordinary merge.
[Cutoff review](main-refresh-review.json) and
[actual ancestry proof](final-cutoff-merge-audit.json) retain the complete refs.
Later validation uses this fixed inventory rather than continually moving its
source inputs.

Review of that incoming ODS change found that a sheet with both a tab colour
and a picture tried to write its drawing namespace after the worksheet start
tag had closed. The new combined regression fails on canonical `18c76e88` and
passes after moving the existing namespace declaration before child elements.
Canonical commit `4fadcc68` is saved on
`CrispStrobe/quds_office_suite:codex/terminal-integration-ods-20261116`; its
complete ODS suite passes **91 tests**, with clean analysis and formatting of
both changed files. CrispCloud contains those exact two Git blobs, and all
**2,411 managed Office files** verify against the updated pin. The standalone
parser pin and application dependency declarations remain unchanged.
[Canonical reproduction, fix and vendor receipts](canonical-ods-repair/README.md).

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

Implementation and evidence are saved in separate incremental remote
checkpoints. The final focused tmux suite passes **64 tests with no skips or
failures**, including hard per-pane deadlines, queued input behind a progressing
capture and resize reversals. The complete final terminal cohort also passes,
as recorded below. Historical acceptance from earlier commits is not counted
as new validation.

The [Screen resolver before/after proof](screen-resolver-regression.json) runs the
extracted production shell through actual `/bin/sh` and `awk` with controlled
Screen listings. It qualifies command resolution, not a live GNU Screen daemon.

Independent review also reproduced a remaining trailing-tab ambiguity. GNU
Screen emits one separator tab and preserves tabs inside session names. The
final parser removes exactly one separator at each boundary, retaining trailing
tabs, repeated tabs and tab/space combinations in unsupported names. All **32
actual shell cases** in [the additional before/after proof](screen-tab-regression.json)
pass; 12 reproduce the defect in checkpoint `bb300164`. The
[runnable harness](screen-tab-regression.py) records the producer source used
to confirm the format. Formatting both changed Dart files requires no changes.

## Final local qualification

Frozen application source is commit `047adfb944ad9f46acc65e0c8c38376b3949f3da`.
The independent [source audit](final-source-audit.json) verifies that all **5,556
watched files** match that commit's blobs and modes, all 205 fixed-cutoff refs
are ancestors, and root `pubspec.yaml`, `pubspec.lock` and `.fvmrc` are identical
to the initial baseline. It also verifies all 554 canonical Quds files and all
1,857 unchanged standalone parser files. The [vendor guards](vendor-verification.json)
pass against the final pin and SSH dependency.

| Completed check | Result | Evidence |
| --- | --- | --- |
| Full terminal/SSH/tmux native cohort | **1,075 passed, 2 skipped, 0 failed**, 85 files; 294.615 seconds | [Native receipt](native.json), [log](native.log.gz) |
| Actual loopback OpenSSH | **22 passed, 3 skipped, 0 failed**, 4 files; 156.502 seconds | [Live receipt](live.json), [log](live.log.gz) |
| Final vendored Office/Zotero engine cohort | **209 passed, 0 skipped, 0 failed**, 5 files; 6.472 seconds | [Engine receipt](engine-final.json), [log](engine-final.log.gz) |
| Static analysis | **164 Dart files**, no errors or warnings; three existing informational lints | [Analysis receipt](analysis.json), [log](analysis.log.gz) |
| Formatting | **164 Dart files**, zero changes | [Format receipt](format.json), [log](format.log.gz) |
| Production-widget capture tests | **2 passed**, nine desktop/320×320 PNGs, no test failures | [Visual receipt](visual.json), [captures](visuals/) |
| Exact Screen resolver | 15 initial shell cases and 32 additional tab-boundary cases pass | [Initial proof](screen-resolver-regression.json), [tab proof](screen-tab-regression.json) |
| Standard optimized web release | **Passed**, O4 and minification retained; 219.762 seconds | [Web receipt](web.json), [log](web.log.gz), [resource/restoration record](web-resource-run.json) |

The native skips are the macOS-only shell case and Windows ConPTY on this Linux
host. Actual Linux PTY allocation, resizing, Unicode input/output, Ctrl+C and
disposal run in the complete cohort. Native and engine source fingerprints match
exactly, and neither run changed a watched file. Live SSH uses disposable local
servers and keys. It passes jump-route authentication, forwarding, rekeying and
shared-route cleanup; two optional SSH PTY tests and one real Unix-agent test
are skipped with their reasons retained in the log. **All seven completed
phases have identical source fingerprints and no changed watched files.**
The [final acceptance verification](acceptance-source-verification.json) binds
the immutable frozen path set, every committed blob/mode, required commands and
suite counts, successful web-attempt timestamps/checksums, compiler arguments,
output hash and fixed SDK identities. Its [reproducible verifier](verify-final-source.py)
passes, and an independent review confirms those checks.

The captured recovery dialog keeps its actions visible while its compact body
scrolls; native tmux retains a pane picker when only one pane fits. Captures use
in-memory connections and disconnected recovery sessions, so they establish
widget layout rather than a live multiplexer or browser runtime. The desktop
tmux fixture lacks a Chinese font fallback and displays two missing-glyph boxes;
these images do not qualify complete Unicode glyph coverage. The independent
[nine-image review](visual-review.json) records exact image hashes, dimensions,
scrolling/picker observations and the limits of visual accessibility checks.

The first full standard O4/minified web attempt ended with compiler exit `-9`
(SIGKILL) after 127.3 seconds. Peak measured process-tree RSS was 3,399,552 kB;
available system memory reached 1,287,524 kB. These observations show an external
kill during memory pressure but do not identify its precise cause or actor;
cgroup memory counters are unavailable. All watched sources stayed unchanged,
and SDK binaries and modes were restored exactly. The complete attempt is
preserved under [`development/web-4096-sigkill`](development/web-4096-sigkill/).

The current [resource runner](web-resource-runner.py) and
[launcher](web-resource-launcher.sh) retain the original SDK verification,
implicit compiler arguments, release flags, lock and restoration paths while
allowing only 2,048/3,072/4,096 MB compiler heap caps. The
[3,072 MB preflight](resource-3072-preflight/web-resource-preflight.json) verifies
the effective VM flag and compiles/runs an O4/minified probe without replacing
SDK files. The full 3,072 MB attempt then reports compiler exit **253**, explicitly
exhausting its heap during global type inference. That separate result is kept
under [`development/web-3072-heap-exhaustion`](development/web-3072-heap-exhaustion/).

The final **4,096 MB** retry succeeds under the reduced system memory pressure:
219.762 seconds for validation and 220.337 seconds including resource monitoring
and cleanup. The observed compiler command retains **`-O4 --minify`**. Peak owned
RSS is 3,416,720 kB and minimum available memory is 3,804,452 kB. All three pinned
SDK binaries/snapshots and their modes are restored exactly. The final output is
**29,534,676 bytes**, SHA-256
`a52c8d5fbab1980585e815d2ee5108a8aa1c8c33a9a5a8d88e87c3e649d88e69`.
It embeds application version `1.3.4+28` and source-equivalent build commit
`e4c559af`. Flutter is **3.47.8** and Dart is **3.13.7**. No optimization flag,
application source, dependency declaration or lockfile was weakened to obtain
the successful build.

## Remaining platform checks

These are limits of this host and the selected local qualification:

- The macOS shell and Windows ConPTY cases require their respective operating
  systems. The two optional live-SSH PTY cases were not enabled on this host.
- The host rejects Unix-socket creation. The actual Unix-agent case is skipped,
  and the [real tmux probe](live-tmux/live-tmux.json) completes **zero feature
  tests**. Screen shell fixtures do not claim a live GNU Screen daemon run.
- Production-widget captures and a successful optimized web compile do not
  establish packaged-platform or browser-runtime acceptance. The capture-font
  and visual-accessibility limits are recorded in the image review.

Focused development test counts overlap the final cohorts and must not be
added to them. No GitHub Actions run was queried, awaited or rerun.

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
load while all 39 editor-dialog tests passed. The engine's own declared
development graph then passes **118 tests with no skips or failures**. Its ten
runtime dependencies match the application graph exactly; no application
production manifest or lockfile changed. [Engine commands and dependency
identity](incoming-engine-README.md) preserve that qualification separately from
the initial runner mismatch.

A second two-worker native run stopped progressing after 185 passing tests
without reporting an assertion failure. It was interrupted with exit 130;
[`development/stalled-native`](development/stalled-native/) preserves its exact
command, last-progress timestamp and source inventory. The last printed test is
not evidence of the cause. The validation runner now accepts `--concurrency 1`
so the final full cohort can run serially on this constrained host.

The first final live-SSH launch stopped before executing a feature test because
a normal native Cargo hook tried to refresh the registry and the host rejected
the network tunnel. Its complete source inventory and diagnostic are retained
under [`development/live-cargo-registry`](development/live-cargo-registry/).
The retry sets `CARGO_NET_OFFLINE=true` and uses the already populated verified
cache, retaining the normal build hooks and unchanged sources, manifests and
lockfiles. This prerequisite failure is separate from SSH test outcomes.
