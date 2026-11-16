# Automatic terminal workspace recovery and integrated terminal updates

This continuation starts from `74fbdd5a9a17399237b54512877dc6700c0d76b2`
on `codex/terminal-screen-workspace` (draft PR #160). It adds opt-in automatic
workspace recovery and a separate choice to relaunch fresh local shells, and
brings in the newer terminal/tmux/Screen and Office work.

Final integrated implementation source: `fdc262e112aa29dd1e60a76cff9a2dfb5f2d7b4f`.
Full iTerm2 feature parity remains unfinished.

## User-visible behavior

Open **Terminal layout → Session recovery**, enable **Remember terminal
workspace**, and save. Recovery and local-shell relaunch default off. Enabling
commits the current layout and settings together. Subsequent structural changes
are debounced for 350 milliseconds. Recovery finishes before the default shell
can start on the next first terminal mount.

The checkpoint includes up to eight tabs, their order and names, nested split
topology and proportions, active pane, per-pane font size, and sanitized
SSH/jump/agent/tmux/Screen destination metadata. Named arrangements are separate.
Recovered idle panes show readiness with an explicit local-start or SSH-reconnect
action. The idle SSH header shows its remembered user/host and non-default port.
**Relaunch local shells** starts fresh shells only for tabs without an SSH
destination, using the existing verified current folder or safe fallback.

Disable retains the last checkpoint. Confirmed **Forget saved workspace** clears
it and resets both preferences while leaving current terminals open. Storage
errors pause autosaves and expose Retry. A failed startup read does not block
opening terminals or overwrite unseen saved data. Retry reveals settings;
Save with recovery enabled explicitly selects the current workspace. Closing
settings while a write is pending does not cancel an already accepted operation.

Passwords, private keys, passphrases, output, commands, working directories,
filesystem grants, staged-workspace authority, broadcast membership and live
route ownership are not stored. SSH always requires explicit reconnection.
The store is one versioned local preference value bounded to 128 Ki UTF-16 code
units. An abrupt process kill can still lose an unfinished preference write.
This does not resurrect operating-system processes or terminal scrollback.

The incoming optimization work also bounds terminal/native tmux resize queues,
preserves final geometry through rapid reversals, batches native tmux pane
captures in groups of up to eight, and hardens exact GNU Screen attachment.

[Usage and limits](../../terminal.md#automatic-session-recovery) ·
[Feature coverage](../../terminal-parity.md)

## Correctness checks

- Startup waits for a bounded read before mounting terminal panels. Timed-out
  or superseded reads cannot later replace newly opened workspaces.
- Serialized writes and exclusive owner leases preserve invocation order.
  Acquiring a replacement owner captures and queues the prior owner's final
  checkpoint before the successor loads, including same-frame keyed remounts.
- Settings and activation snapshots are atomic. Configuration changes and
  Forget invalidate pending saves; stale panels and dialogs cannot change a
  replacement workspace. Writes remain ordered until the backend settles.
- An idle storage queue starts in the caller's scheduler, avoiding a
  constructor-zone dependency exposed by unchanged widget assertions.
- After a pending save settles, the current layout is checked again. Reverting
  to a previous layout during that write cannot leave the checkpoint stale.
- Output and focus notifications do not write identical layouts. Normal
  lifecycle transitions and orderly disposal flush pending structural changes.
- Recovery never restarts SSH or restores broadcast authority. Explicit local
  and SSH actions keep the existing focus, origin, authentication and trust
  paths. Hidden panels cannot invoke their ready-state action.
- Settings remain usable at 320×320; ready-state actions are exercised at
  160 pixels, including longer German labels. Recovery copy covers the eight
  existing non-English locales.
- Terminal resize transport work is deferred out of layout and keeps one
  in-flight request plus the latest pending size. Old connection completions
  cannot clear a successor's resize state.
- Native tmux cancels unsent intermediate sizes when a drag returns to its
  previous size. Incoming client/deadline and exact-Screen regressions are part
  of the integrated-source qualification, not inferred from recovery tests.

## Incoming source reconciliation

The initial fetch contained **40 branch heads and 153 PR heads**, all already
ancestors of the starting head. This retained shared SSH-shell and ODS work
beyond the pasted native-tmux handoff.
[Initial inventory](initial-integration.json).

The earlier integration at
`3ab3323da81d265d338337d2dee4214e5b9daafb` merged main's PR #164–#166 changes
and retained all three original PR tips after proving full-tree identity with
their squash commits. At that cutoff, **43 branches + 156 PR heads =
199 references** were actual ancestors. Its canonical Quds merge was
`be2c3a91b0dd5b4abb1b9a7baa8f5e10769bc87a`, with **2,409** managed Office
entries verified. Those proofs retain their original cutoff.
[Earlier integration record](incoming-audit/README.md).

The **10:43:14 UTC on 16 November 2026** refresh found newer main `b9772e1a` and PRs #167–#169.
Its inventory contains **46 branches + 159 PR heads = 205 references**.
The newer incoming Office pin is
`18c76e886623ae3be9a41addd80e7f6837c2d3b0`, with **2,411** managed entries.
The merged terminal guide retains PR #169's latest guidance; feature coverage
retains the shared PR #167/#169 baseline. Resize, native tmux and exact-Screen
instructions are preserved.

Final integration is `fdc262e112aa29dd1e60a76cff9a2dfb5f2d7b4f`, with
**205 of 205** cutoff references verified as actual
ancestors. The final Quds pin is `18c76e886623ae3be9a41addd80e7f6837c2d3b0`; its managed-source and
canonical provenance result is **2,411 Office entries rehashed with tracked modes; 96 SSH upstream files and four reviewed patches verified**.
[Final integration proof](completion-incoming/post-integration.json) ·
[Exact clean-merge preview](completion-incoming/merge-preview.json) ·
[Canonical vendor provenance](late-incoming/vendor-remote-proof.json).

## Qualification on the final integrated source

| Check | Result on the final integrated source |
|---|---|
| Frozen implementation source | `fdc262e112aa29dd1e60a76cff9a2dfb5f2d7b4f` |
| Static analysis and formatting | 175 semantic targets: **0 errors, 0 warnings, 3 pre-existing info diagnostics**. All 175 original files pass formatting with zero changes. |
| Recovery, related terminal and incoming regression cohorts | **701 passed, 1 skipped, 0 failed across 44 suites** in 184.272 seconds, using the explicitly isolated Dart/widget mode described below. |
| Standard optimized full application web build | **Not accepted.** The normal O4/minified release compiler received external SIGKILL (-9); no JavaScript release artifact was produced. No Dart source diagnostic was emitted; the signal's cause is not established. |
| Source identity across recorded phases and frozen Git input | All **5,673 watched inputs** match byte-for-byte and mode-for-mode across all 12 before/after inventories from six recorded phases. **5,664 tracked inputs** match frozen Git source `fdc262e1`. |
| Production-widget captures and visual inspection | **Five saved PNGs inspected**: two 1180×700 captures using the Linux widget target and three 320×320 scroll positions using the Android widget target. Controls and disclosures remain usable; no unintended overflow observed. Physical-device qualification remains outstanding. |

The [analysis](final-acceptance/analysis/receipt.json),
[formatting](final-acceptance/format/receipt.json),
[vendor](final-acceptance/vendor/receipt.json),
[combined test](final-acceptance/combined/receipt.json) and
[web](final-acceptance/web/receipt.json) receipts record exact commands, source
identity and qualification. The [final source verification](final-acceptance/final-source-verification.json)
re-enumerated the inputs after all work and compares them with every phase.
The [capture manifest](screenshots/manifest.json) and
[visual review](screenshots/review.json) identify the exact inspected PNGs.

The targeted combined run comprises:

| Cohort | Files | Passed | Skipped | Failed |
|---|---:|---:|---:|---:|
| New recovery persistence, settings, lifecycle and idle actions | 4 | 76 | 0 | 0 |
| Related terminal regressions, including incoming resize, tmux deadline and Screen checks | 30 | 329 | 1 | 0 |
| Incoming ODS regressions | 3 | 119 | 0 | 0 |
| Incoming Zotero client, identity, batching, scaling, citing and editor regressions | 6 | 176 | 0 | 0 |
| Production-widget visual fixture | 1 | 1 | 0 | 0 |
| Total | 44 | 701 | 1 | 0 |

[Per-suite counts](final-acceptance/combined/per-suite-summary.json) independently
sum to the same final counters in the complete compressed test log. The one
[platform skip](final-acceptance/combined/platform-skip.json) is the existing
macOS-only real-PTY shell case in `test/terminal_panel_test.dart`; this worker is
Linux. Counts from the earlier source are not added to this run.

Seven Office engine tests use declared host adapters that change only their
test-framework import and three fixture-path prefixes. Reversing each
substitution recovers every original byte, with all test/assertion call sites
preserved. The editor suite is unchanged. Three of those adapters are also used
for analysis because the root production graph does not expose the engine's
standalone `package:test` dependency. Formatting checks original source files.
[Adapter proof](final-acceptance/incoming-office/preparation.json) ·
[175 semantic targets](final-acceptance/static-targets.json).

### Final release attempt

After the successful combined run and remote capture checkpoint, recorded
cleanup reclaimed **783,364,096 bytes** of reproducible generated caches and
already-remote document materializations. It preserved all watched inputs, Git
history and active SDK binary identities.
[Cleanup record](final-acceptance/resource-cleanup/receipt.json).

The final full application web attempt used normal web hooks, standard O4
optimization and minification, and the unchanged **4,096 MB compiler heap**.
Both isolated-test feature overrides were absent. It ended after **84.263 seconds**
including verification, with dart2js terminated externally by signal 9. No
release JavaScript artifact was produced, and the cause of the signal was not
established. This attempt is **not a passing release build**.
[Outcome](final-acceptance/web/outcome.json).

The original Dart executable, AOT runtime and dart2js snapshot were restored
exactly; an independent post-process hash/mode check and the final cross-phase
verification both confirmed that restoration.
[SDK restoration proof](final-acceptance/web/independent-sdk-restoration.json).
No build or test was rerun after this result. Full web release and normal native
qualification remain outstanding.

## Preserved qualification for the earlier recovery source

The following completed work belongs to
`3cd501798794dcb74de5dca912b498a4c0a7e39b`, before the latest runtime
integration. Flutter **3.47.8** and Dart **3.13.7** were used with the enforced
production dependency graph.

| Check | Observed result and evidence status |
|---|---|
| Replacement-worker static analysis | **164 selected Dart files; 0 errors, 0 warnings, 3 pre-existing infos.** Original [receipt](static/analysis.json), compressed log and source inventories are preserved. |
| Replacement-worker formatting | **164 files, 0 formatting changes.** Original [receipt](static/format.json), log and source inventories are preserved. |
| Static source identity | **5,665 watched inputs unchanged** in each completed static phase; **5,661 tracked inputs** match frozen `3cd50179`, including modes. |
| Vendor provenance | **2,409 Office entries; 96 SSH upstream files and four reviewed patches verified.** Original [receipt and logs](vendor/receipt.json) are preserved. This does not qualify the newer 2,411-entry Office inventory. |
| Original-worker isolated test run | **462 passed, 1 platform skip, 0 failed across 36 files.** The result is reconstructed from retained tool output; the original complete log and inventories were lost. |
| Standard application web attempts | **Two failed attempts terminated by external SIGKILL.** Neither is a passing web build. |

The three analyzer infos are in two test files whose Git blobs are unchanged
from the starting source: one brace-style info in
`test/ssh_shared_channel_cleanup_test.dart`, plus brace-style and
constant-declaration infos in `test/terminal_mount_localization_test.dart`.
The static receipt records their exact locations and unchanged blob identities.
Static checks used the normal pinned Dart CLI with no feature overrides.

The first [archived standard web attempt](web-attempt-sigkill/receipt.json)
used the normal full application entrypoint, standard O4 optimization and
minification, normal web hooks, and a **4,096 MB compiler heap**. It ran for
225.204 seconds, produced no accepted `main.dart.js`, preserved all watched
inputs, and verified exact SDK restoration. The [second attempt](web-retry-sigkill/receipt.json) retained the
same heap and optimization settings after cache cleanup, ran for 110.899 seconds,
and was also externally killed. These results do not establish a Dart source error or identify the
external kill's cause. The final integrated attempt is separately recorded above and also did not
complete; none of these three attempts is counted as a passing build.

### Interrupted-worker result

The original isolated run's recorded breakdown was:

| Cohort | Files | Passed | Skipped | Failed |
|---|---:|---:|---:|---:|
| Recovery persistence, settings, lifecycle and idle actions | 4 | 76 | 0 | 0 |
| Related terminal regressions | 28 | 267 | 1 | 0 |
| Incoming Office regressions at that cutoff | 3 | 118 | 0 | 0 |
| Production-widget visual fixture | 1 | 1 | 0 | 0 |
| Total | 36 | 462 | 1 | 0 |

The command reported **5,664 watched inputs unchanged**, exit code 0, and
155.155 seconds elapsed. The worker became unavailable after returning the
result and before its complete log, final source inventories or final PNGs
could be saved remotely. Implementation and earlier evidence were already
preserved through checkpoint `0c43c476`.

[Interrupted-worker provenance](recovered-worker/README.md) and the
[reconstructed observation record](development/worker-reset-observations.json)
identify the retained facts, exact command and reported hashes. These records
are reconstructed from the transcript; they are not the original receipt or
log bytes. The final integrated run above has its own preserved receipts, raw log,
source inventories and inspected captures.

Two earlier five-image sets were inspected during development. They exposed
the false idle “Starting” message, an unintended Android target for the large
capture, and then the misleading “Local shell” header on an idle SSH pane.
All three issues were corrected before `3cd50179`. The final five PNGs generated
by the interrupted worker were not inspected or archived; no final PNG hashes
were recovered. Earlier image observations do not constitute final-source
visual acceptance.

## Test modes, environment constraints and archived helpers

Isolated Dart/widget checks use these per-command feature switches:

```sh
FLUTTER_NATIVE_ASSETS=false FLUTTER_DART_DATA_ASSETS=true \
  flutter test --no-pub --concurrency=1 --reporter=expanded TEST_FILES
```

Data assets remain enabled; native code-asset building is omitted for that test
command. The application dependency graph, production manifests, lockfile,
test assertions and native-hook source are retained. This qualifies the
exercised Dart/widget behavior only. It does not qualify native bridges, real
local shell processes, live SSH/tmux, packaged applications, or browser runtime.
Normal static checks and standard web builds do not use these isolated-test
feature overrides.

On the original worker, normal native tests and Flutter's ordinary Chrome test
command stopped in the catalog native hook before running tests because the
required Rust/Cargo toolchain was unavailable. Local Chromium could not create
its required Unix socket, and the available browser route could not reach the
local preview. These are recorded [environment blockers](environment/), not
passing platform tests or assumptions about another machine.

The [archived acceptance helper](replacement-worker/accept_recovery.py) and
its accompanying wrappers are exact audit copies of scripts executed from the
sibling **`<workspace>/toolchain/`** directory beside
**`<workspace>/CrispCloud/`**. The helper derives its repository, SDK wrapper and
evidence paths from its own location. The archived
[toolchain-run.sh](replacement-worker/toolchain-run.sh) corresponds to the
executable named `run` in that sibling directory. The
[web launcher](replacement-worker/web-resource-launcher.sh) and
[resource runner](replacement-worker/web-resource-runner.py) have their own
recorded setup and SDK-restoration steps.

The final run's [acceptance helper](final-acceptance/accept_final_recovery.py)
is also preserved byte-for-byte. Its recorded SHA-256 matches every executed
final-phase receipt. The separate
[preparation helper](final-acceptance/prepare_final_recovery.py) is a reproduction
helper: it uses the identical committed 164-target list in place of the locally
archived historical analysis receipt. The
[reproduction note](final-acceptance/preparation-helper-reproduction.json)
records that equality; its seven adapter substitutions and eleven added targets
are the exact operations used for this run.

**These archive copies are not runnable in place under `docs/`.** Reproduction
requires the original sibling-directory layout and dependencies, or an explicit
translation of the recorded commands and paths to another provisioned checkout.
The absolute paths in receipts identify the actual run; they are not portable
installation instructions. The reusable application test fixture remains
`test/terminal_workspace_recovery_visual_test.dart`, enabled with
`--dart-define=TERMINAL_RECOVERY_VISUALS=true` and skipped by default.

The visual fixture uses production widgets, an in-memory recovery record and
idle sessions, with bundled fonts. It creates two 1180×700 captures using the
Linux widget target and three 320×320 captures using the Android widget target.
It starts no real backend and does not qualify a packaged Linux or Android app.

## Remote checkpoint policy

Implementation and evidence are saved incrementally to the remote feature
branch. Each checkpoint verifies the intended Git tree and expected previous
remote head; integration retains its reviewed parent histories. New commits
carry `[skip ci]`. **No GitHub Actions are queried, awaited or rerun.**

## Remaining acceptance and parity boundaries

Normal native build/runtime qualification, browser runtime, packaged macOS and
Windows, physical mobile devices and external gateways remain separate work.
Actual tmux-daemon acceptance remains outstanding. This continuation does not
repeat the prior loopback SSH or native PTY acceptance and does not claim those
historical results for the changed integrated source.

Independent operating-system windows, live process/scrollback/working-directory
restoration, automatic SSH reconnect, idle connection masters after the last
owner closes, cross-process pooling, richer trigger/coprocess automation and
broader platform/agent integration remain open. Native tmux history and
terminal-state reconstruction limits remain in the feature guide.
