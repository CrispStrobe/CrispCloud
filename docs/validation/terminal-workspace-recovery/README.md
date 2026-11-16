# Automatic terminal workspace recovery

This continuation starts from `74fbdd5a9a17399237b54512877dc6700c0d76b2`
on `codex/terminal-screen-workspace` (draft PR #160). It adds opt-in automatic
workspace recovery and a separate choice to relaunch fresh local shells.
Full iTerm2 feature parity remains unfinished.

## User-visible behavior

Open **Terminal layout → Session recovery**, enable **Remember terminal
workspace**, and save. Both recovery and local-shell relaunch default off.
Enabling commits the current layout and settings in one preference write.
Subsequent structural changes are debounced for 350 milliseconds. Recovery
finishes before the default shell can start on the next first terminal mount.

The checkpoint includes all eight supported tabs, their order and names, nested
split topology and proportions, active pane, per-pane font size, and sanitized
SSH/jump/agent/tmux/Screen destination metadata. Named arrangements are separate.
Recovered panes start disconnected. Their ready-state controls explicitly start
a local shell or reopen the ordinary SSH authentication flow. The separate
**Relaunch local shells** choice starts fresh shells only for tabs without an
SSH destination, using the existing verified current folder or safe fallback.

Disable retains the last checkpoint. Confirmed **Forget saved workspace** clears
it and resets both preferences while leaving current terminals open. Storage
errors pause autosaves and expose Retry. A failed startup read does not block
opening terminals or overwrite unseen saved data; Retry reveals settings, and
an explicit Save selects the current workspace. Closing the settings dialog
while a write is pending leaves that accepted operation running.

Passwords, private keys, passphrases, output, commands, working directories,
filesystem grants, staged-workspace authority, broadcast membership and live
route ownership are not stored. SSH always requires explicit reconnection.
The store is one versioned local preference value bounded to 128 Ki UTF-16 code
units. An abrupt process kill can still lose an unfinished preference write.
This does not resurrect operating-system processes or terminal scrollback.

[Usage and limits](../../terminal.md#automatic-session-recovery) ·
[Feature coverage](../../terminal-parity.md)

## Correctness established during implementation

- Startup waits for a bounded read before mounting any terminal panel. Timed-out
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
  to a previous layout during that write cannot leave the saved checkpoint stale.
- Output and focus notifications do not write identical layouts. Normal
  lifecycle transitions and orderly disposal flush pending structural changes.
- Recovery never restarts SSH or restores broadcast authority. Explicit local
  and SSH actions retain the existing focus, origin, authentication and trust
  paths. Hidden panels cannot invoke their new ready-state button.
- The settings dialog remains usable at 320×320. The explicit start/reconnect
  controls are exercised at 160 pixels, including longer German labels. New
  recovery copy is translated into all eight existing non-English locales.

## Incoming source reconciliation

The initial fetch contained **40 branch heads and 153 PR heads**, all already
ancestors of the starting head. This retained the shared SSH-shell and ODS
validation work beyond the pasted native-tmux handoff.
[Initial inventory](initial-integration.json).

A later refresh found PRs #164–#166 and main `5d3a020d`. Integration
`3ab3323da81d265d338337d2dee4214e5b9daafb` merges main's changes and preserves
all three original PR tips as parents after proving full-tree identity with
their squash commits. All **43 branches + 156 PR heads = 199 references** at that
cutoff are actual ancestors. The incoming manifest predates 18 newer Zotero
entries, so it was combined with the retained inventory instead of replacing it.

Canonical Quds commit `be2c3a91b0dd5b4abb1b9a7baa8f5e10769bc87a` on
`codex/terminal-recovery-office-20261116` is the exact clean two-parent merge of
the retained and incoming source pins. It changes only four ODS files. All
**2,409 managed hashes and index modes**, **552 canonical Quds blobs/modes** and
**1,857 unchanged standalone-parser blobs/modes** pass verification.
[Complete integration proof](incoming-audit/README.md).

## Local qualification

Fresh acceptance uses the enforced production lockfile, Flutter **3.47.8** and
Dart **3.13.7**. Dependency manifests and runtime package sources are not replaced
to obtain test results. The incoming vendor files have the explicit integration
and canonical-source proof above.

The current host has no Rust/Cargo installation and cannot fit the required
native build toolchain in the available scratch capacity. A normal native test
attempt stops in the unrelated catalog native hook before any test executes.
The same host hook blocks Flutter's ordinary Chrome test command. Local Chromium
also cannot create its required Unix socket, and no supported browser route can
reach the local preview. These are recorded blockers, not passing platform tests.

Isolated Dart/widget checks use Flutter's documented per-command feature
switches:

```sh
FLUTTER_NATIVE_ASSETS=false FLUTTER_DART_DATA_ASSETS=true \
  flutter test --no-pub --concurrency=1 --reporter=expanded TEST_FILES
```

Data hooks still run, while code-asset configuration is omitted so unrelated
native bridges do not compile. No persistent Flutter setting, production
manifest, app/test assertion, native hook source or SDK binary is changed for
this test mode. This qualifies the exercised Dart/widget behavior only; it
cannot qualify native bridges, real local shells, packaged applications, live
SSH/tmux, or browser execution.

The final combined run, static checks, production web build, source-identity
proof and reviewed captures are being recorded. Development attempts and their
failures are retained under [development](development/), and environment
prerequisites and omissions under [environment](environment/). Earlier terminal
acceptance totals belong to their original commits and are not reused here.

## Remote checkpoint policy

Implementation and evidence are saved incrementally to the remote feature
branch. Each checkpoint verifies the exact staged Git tree and the expected
previous remote head; the integration also preserves its reviewed parents.
New commits carry `[skip ci]`. **No GitHub Actions are queried, awaited or rerun.**

## Remaining acceptance and parity boundaries

Normal native build/runtime qualification, browser runtime, packaged macOS and
Windows, physical mobile devices and external gateways remain separate work.
Actual tmux-daemon qualification remains blocked by the host's Unix-socket
restriction. This continuation does not repeat the prior loopback SSH or native
PTY acceptance and does not claim those historical results for the new source.

Independent operating-system windows, live process/scrollback/working-directory
restoration, automatic SSH reconnect, idle connection masters after the final
owner closes, cross-process pooling, richer trigger/coprocess automation and
broader platform/agent integration remain open. Existing native tmux history and
terminal-state reconstruction limits remain documented in the feature guide.
