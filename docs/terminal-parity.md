# Terminal feature coverage

CrispCloud reuses xterm2 for terminal emulation and owns its transports, session
lifecycle and file-browser integration. This tracks application-level progress
toward desktop terminal workflows. It is not a claim of complete iTerm2
compatibility.

## Current status and validation boundary

The current continuation starts from terminal checkpoint `064bd3ce` in draft
PR #140. It adds jump routes, saved arrangements, broadcast input, shell
integration and authenticated tmux/Screen session discovery.

**The final continuation has not passed its Flutter regression suites or static
analysis.** The local filesystem exhausted its capacity while Flutter was
loading the first test kernel; zero feature tests completed. The execution
environment subsequently became unavailable. Source work and regression tests
were then preserved through immutable GitHub blobs and incremental commits.
A source/API review is not a substitute for running those suites.

The historical 229-test result below belongs to the earlier `44434bad`
implementation. It must not be presented as qualification of this continuation.

## Integration baseline and refresh

Before new feature work, all **27 live remote branch heads** and the **50 recent
PR heads (#100–#149)** were audited. Most changes were already on main or had
exact squash-merge tree equivalents. The newer Zotero PR #149 was merged into
the terminal branch at `b6ca0b1f`, and retained equivalent branch heads were
included as history parents without reverting current code. The superseded
UTF-16 bibliography branch already matched the current implementation/tests;
its obsolete vendor pin was not restored.

During development, the repository advanced again. The refresh integrated:

- Main through **`ecb21989` / PR #152**, including PRs #150 and #151.
- Zotero draft #149 through **`7d4d5640`**, including desktop library support and
  its source-bound evidence.
- All **30 branch heads** in the refreshed snapshot. The new PR #150/#151 branch
  trees exactly match their squash merges; PR #152's branch is an actual parent
  of main.

The refresh merge is `52e7205f`. Terminal changes were disjoint from the incoming
Office/Zotero paths. The overlapping Word deserializer was taken from combined
canonical Quds **`875064341656ad9e74daec64f8f8d7befdb48368`**, retaining both Zotero
handling and the trailing content-control section-break fix. All 517 managed
Quds file blobs/modes match that canonical source; the 1,857 standalone parser
files retain their existing tree and pin. The manifest keeps all 2,374 managed
paths. A stray conflict marker inherited from main's vendor documentation was
removed during reconciliation.

At the final integration snapshot, **15 November 2026 at 20:51:07 UTC**, the
Zotero branch had advanced to **`dcd8d58d`**, a direct descendant of that merge.
The terminal branch then fast-forwarded to include its four additional commits
and nine Office/evidence paths without changing any terminal source. That
continuation advances canonical Quds to **`df824e4351b7df7f8b7d6df2deb64f95bfe2ef2d`**
and records 2,375 managed files. The source comparisons above retain their
`52e7205f` cutoff; the later identity work keeps its own evidence.

These are Git-tree/source comparisons, not new Office runtime qualification.
Detailed records:

- [Initial integration audit](validation/terminal-20261115/integration.json)
- [Refresh, exact tree entries and reconciliation](validation/terminal-20261115/integration-refresh.json)
- [Final integration cutoff and ancestry](validation/terminal-20261115/integration-cutoff.json)

## Implemented coverage

| Area | Previously available | Added in this continuation |
| --- | --- | --- |
| Terminal workspace | Eight independent tabs; two visible panes; close confirmation; retained hidden sessions | Tab ordering, draggable/balanced divider and up to 20 named saved arrangements |
| SSH authentication | Password/encrypted-key login, verified host keys, explicit gateway | Up to three ordered jump hosts with independent credentials and host verification, nested direct TCP channels and route cleanup |
| Saved destinations | Up to 50 local secret-free profiles | Jump-route persistence; profile schema v2 prevents older versions silently dropping hops |
| tmux and GNU screen | Create/attach, exact targets, non-evicting detach and manual reconnect | Authenticated bounded discovery, local filtering, exact-target selection and attach-only reconnect retention |
| Navigation | Unicode/wrap-aware literal scrollback search and per-tab zoom | OSC 133/633 command history, previous/next marks, manual/iTerm2 marks and completed-command output selection |
| Shell status | Emulator output and channel exit status | Shell-reported directory, command status/duration and opt-in one-shot in-app completion notification |
| Shell setup | Compatible hosts could emit their own sequences | Review-and-copy Bash 4.4+/Zsh setup, preserving prompt hooks; no startup-file modification or automatic script execution |
| Multiple-session input | Focus isolation, direct keys and explicit paste | Explicit 2–8-tab broadcast groups, persistent banner/Stop, per-recipient encoding and queued-input cancellation |
| Lifecycle | Generation-bound transport ownership | Pending-opener/cleanup tracking, shared close futures and input provenance that excludes terminal replies |
| Localization | Existing terminal controls | New controls translated into the eight existing non-English locales |

## Behavior and limits

### Arrangements

Arrangements save tab order/names, active and visible panes, split direction and
proportion, font sizes, and sanitized SSH destinations/modes/routes. Restoring
asks before replacing existing tabs, waits for owned cleanup and opens the
replacement tabs disconnected. It does not restore local folder grants,
staged-workspace authority, processes, credentials, scrollback or command
history. Records use local preferences; corrupt or newer versions are preserved.
There are still at most eight tabs and two simultaneously visible panes.

### SSH and session discovery

Each complete route uses one of the existing five SSH session slots and retains
the existing 30-minute activity timeout. A route may contain up to three jump
hosts plus the final destination. A configured gateway reaches the first hop.
No SSH-agent or general port-forwarding UI is added by the nested route channels.

Discovery uses fixed locale-pinned commands, a separate no-PTY channel, a
ten-second deadline, a 256 KiB combined stdout/stderr budget and a 512-session
limit. It waits for output EOF and channel status. Canceling or invalidating a
picker releases its connection; it cannot launch a stale target. Screen uses
the full PID.name and the existing exact resolver rechecks it before attach.
Unsupported names are displayed but disabled. Listing and attachment remain
subject to concurrent remote rename/exit races.

### Shell integration

The app observes xterm2's decoded OSC callbacks. It does not introduce another
terminal escape parser. Metadata is display-only and cannot execute commands,
authorize filesystem access, navigate the file panel or access the clipboard.
History stays with the current in-memory connection, has at most 500 marks, and
limits labels to 2,048 UTF-16 code units. Buffer anchors follow reflow and
expire with scrollback; completion can survive prompt eviction without enabling
selection through invalid anchors. Alternate-screen markers are ignored.

The helpers cover interactive Bash 4.4+ and Zsh. Bash 4.4–5.0 uses a scalar
PROMPT_COMMAND fallback; Bash 5.1+ supports the array form. Zsh emits the
captured exit status and returns success from its hook to preserve subsequent
hooks. Other shells and multiplexer passthrough still need their own compatible
configuration. Notifications are one-shot, in-app messages, not OS alerts.

### Broadcast input

Groups contain 2–8 explicitly selected connected tabs and bind to their exact
connection identities. Only explicit text/key/character/paste input from the
active visible focused source is mirrored. Each recipient uses its own terminal
modes. Protocol replies, mouse reports and focus events are not broadcast.
The group disarms on hide, close, restore approval, connection changes,
forwarding failure or an oversized input operation. The per-event bound is
262,144 UTF-16 code units, not a byte count. Stop also revokes pending deliveries
that have not reached their transports. Groups are never persisted.

## Current continuation verification

| Check | Actual result |
| --- | --- |
| Initial/refresh Git integration | Ancestry, exact squash-tree comparisons and canonical managed-source reconciliation recorded |
| Pure Dart SSH model smoke | 24 assertions passed against the production jump-host/configuration models |
| Initial Bash/Zsh helper smoke | Nine checks per shell, 18 total, passed in piped interactive shells before final review corrections |
| Final helper corrections | Zsh downstream-hook status behavior and Bash 4.4–5.0 fallback reviewed against primary shell documentation; final scripts have not been executed |
| Early Dart formatting/parsing | Completed for initial locally authored sources; this does not qualify later reconstructed or remote-only edits |
| Pinned emulator API review | Constructor/input overrides, public key-event types and idempotent anchor disposal checked against official xterm2 5.4.0 source |
| Native Flutter feature tests | **0 completed**: first kernel compiled, then cache-copy creation failed with ENOSPC before assertions ran |
| Final formatting/analyzer/full app build | **Not executed** after environment loss |
| Browser, physical devices and live SSH/jump/tmux/Screen | **Not executed in this continuation** |
| GitHub Actions | No result queried, awaited or required; checkpoints use `[skip ci]` |

The initial shell smoke covered prompt/command markers, success/failure status,
existing hooks, Unicode-directory encoding and repeated setup. It used pipes
with interactive Bash/Zsh rather than a PTY and predates final hook corrections.
Do not use it as acceptance evidence for the final helper source.

New regression coverage is preserved in the repository: jump model/transport/
dialog tests; arrangement model/store/dialog/workspace tests; shell marker and
directory tests; explicit-input and cleanup tests; broadcast service/dialog
tests; multiplexer parser/service/picker tests; and additional reconnect/panel
boundary cases. The existing profile tests include schema-v2 compatibility.
These are **authored tests, not a reported pass count**.

See [runtime setup and failed attempt](validation/terminal-20261115/runtime-attempts.md),
[structured runtime evidence](validation/terminal-20261115/runtime-attempts.json)
[continuation checks](validation/terminal-20261115/continuation-checks.json),
and [source/API review and remote read-back](validation/terminal-20261115/source-review.json).
Run the commands in [the terminal guide](terminal.md#build-and-smoke-test-guide)
against a fresh checkout of the current branch. The old local checkout became
stale when remote recovery commits continued and must not be used to qualify
the current sources without synchronizing them first.

## Historical validation — earlier workspace implementation

The implementation at `44434bad` was checked with pinned Flutter 3.47.8 / Dart
3.13.7 on Linux on 15 November 2026, before the current continuation.

| Check | Historical result |
| --- | --- |
| Native terminal cohort | 229 passed, 2 platform-specific skips across 22 files |
| Actual Linux PTY | TTY allocation, ANSI/final output, resize, Unicode input/output, Ctrl+C and disposal passed |
| Screen resolver fixtures | Exact IDs/names, duplicate/missing/unavailable sessions, prefix collisions, bounds and quoting passed |
| Static analysis/formatting | All 28 then-changed Dart files clean |
| Dependency resolution | Pinned resolution succeeded; manifests and lockfile unchanged |
| CI configuration | YAML parsed; referenced tests verified |
| Visual layout | Actual desktop/narrow Android widgets inspected with synthetic connections |
| Browser execution | Chromium aborted before startup: socket creation denied; no browser tests ran |

The two historical native skips were Windows ConPTY and a macOS-only interactive
shell smoke test. Historical visual fixtures are not live SSH/tmux/Screen or
physical-device acceptance. Live tmux/Screen attempts were blocked by the earlier
workspace's Unix-socket restrictions.

## Remaining larger parity areas

- Native tmux control-mode mapping of remote windows and panes.
- SSH-agent authentication/forwarding, local/remote/dynamic forwarding controls,
  OpenSSH config import and connection multiplexing.
- More than two visible panes, nested split layouts and independent windows.
- Automatic process/session restoration and secure reusable credential/identity
  integration beyond the current secret-free destination stores.
- User-defined key maps, triggers, command automation and broader shell support.
- Qualification of graphics/file-transfer protocols and their app-level controls.
- Final runtime, visual, browser and packaged-platform qualification of this
  continuation.

Ordinary tmux PTY attachment and session browsing do not provide iTerm2's native
tmux control-mode integration. Reference workflows are described in iTerm2's
[feature highlights](https://iterm2.com/documentation-highlights.html),
[shell integration guide](https://iterm2.com/documentation-shell-integration.html)
and [tmux integration guide](https://iterm2.com/documentation-tmux-integration.html).

The helper compatibility review uses GNU's
[Bash 5.1 announcement](https://lists.gnu.org/archive/html/info-gnu/2020-12/msg00003.html)
and the [Zsh hook documentation](https://zsh.sourceforge.io/Doc/Release/Functions.html).
Pinned emulator API checks use the
[xterm2 5.4.0 terminal source](https://github.com/SoFluffyOS/xterm2/blob/9d9901ee43ace000ef3dcbf0283db72cc0be1f70/core/lib/src/terminal.dart)
and [CellAnchor implementation](https://github.com/SoFluffyOS/xterm2/blob/9d9901ee43ace000ef3dcbf0283db72cc0be1f70/core/lib/src/core/buffer/line.dart).
