# Terminal feature coverage

CrispCloud reuses xterm2 for terminal emulation and owns its transports, session
lifecycle and file-browser integration. This records application-level progress
toward desktop terminal workflows. It does not claim complete iTerm2 compatibility.

## Current status

The current continuation adds **local, remote and SOCKS5 SSH forwarding** and
**persistent output triggers with marks and in-app alerts**, in draft PR #160.
The implementation and exact behavior are described in the
[terminal guide](terminal.md#output-triggers). Current local validation and
integration evidence are recorded in
[the forwarding/trigger evidence directory](validation/terminal-forwarding-triggers/README.md).

The preceding continuation started at `4cd8065a` in PR #140, now merged. It added **up to
eight nested panes, OpenSSH destination import and custom terminal key bindings**,
and validated the previously unexecuted jump-route, arrangement, broadcast,
shell-integration and session-discovery work on the normal application graph.
The recovered environment has pinned Flutter 3.47.8 and Dart 3.13.7, working
native dependencies and actual Linux PTYs. The earlier out-of-disk attempt is
historical evidence; it no longer describes the current validation environment.

Source changes are saved incrementally to `codex/terminal-screen-workspace`.
GitHub Actions results are neither queried nor awaited; checkpoints carry
`[skip ci]`. Local validation and its explicit platform limits are recorded below
and in [the evidence directory](validation/terminal-parity-continuation/README.md).

## Integration baseline and refresh

The 16 November continuation first advanced the branch from `01b3f609` to main
`45ed126a`, bringing in the newer terminal fixes, canonical Office/Zotero work
and build-28 release changes. All **37 live branch heads** and **149 available
PR heads** were checked. Only the original heads of #158 and #159 were absent
from main's ancestry; both had exact tree identity with their already-merged
squash commits. Checkpoint `5c2dbea9` retains those heads as additional parents
and contains every audited head. No newer source was reverted to an old branch
snapshot. The [integration record](validation/terminal-forwarding-triggers/integration.json)
contains the exact refs and tree comparisons. The previous snapshots below are
retained as historical evidence.

At **15 November 2026, 22:12:24 UTC**, all **32 live branch heads** and the
**100 recent PR heads** were audited before new implementation. The branch
incorporated Zotero through `64030d55` and main through `01f7fc77`, including
PRs #153 and #154. Exact squash-tree comparisons account for their original
branch heads without replacing newer work. The remote integration checkpoint is
`ba838043`.

The two overlapping vendor records were reconciled against canonical Quds
`3304f42ee17b52659a82d5714dcc730184050960`. All **2,384** managed files were
freshly SHA-256 checked. All **527** Quds entries matched the complete canonical
Git tree by blob, mode and size; the **1,857** standalone parser files retained
their existing source pin and matching digests.

The final refresh found **34 branch heads**, PRs #155 and #156, and later Zotero
work. The integrated Zotero head `6a53294ad086e2a1c6475d888fbed7dcc2591449`
already includes main `d1add32cf5f4a14379ae35ca30b123e781558549` and terminal
checkpoint `a965bfd4`. It merges cleanly with the newer terminal fixes. The
incoming vendor manifest advances canonical Quds to
`55d46a0fb5f7392dab1a604bc3c15126bd3e380d` with 2,391 managed files; its exact
source verification is recorded in the final integration receipt. All 2,391
managed SHA-256 hashes and all 534 canonical Quds blob/mode/size comparisons
match. The merge checkpoint `454f8a4d` contains all 34 branch and 100 PR heads
as actual ancestors, including the verified squash-equivalent original heads.

These vendor checks establish source identity, not new Office feature acceptance.
Earlier feature evidence retains its original source cutoff. Records:

- [Initial branch and PR snapshot](validation/terminal-parity-continuation/branch-pr-snapshot.json)
- [PR ancestry checks](validation/terminal-parity-continuation/pr-head-ancestry.json)
- [Initial canonical reconciliation](validation/terminal-parity-continuation/canonical-integration.json)
- [Initial complete managed-source verification](validation/terminal-parity-continuation/canonical-source-verification.json)
- [Latest remote snapshot and comparisons](validation/terminal-parity-continuation/remote-cutoff-refresh.json)
- [Latest complete managed-source verification](validation/terminal-parity-continuation/canonical-source-cutoff-verification.json)
- [All 134 snapshot references contained](validation/terminal-parity-continuation/refresh-ancestry-verification.json)

## Implemented coverage

| Area | Current behavior |
| --- | --- |
| Terminal workspace | Up to eight independent tabs and eight nested visible panes; per-divider sizing and balancing; directional/cyclic pane selection; temporary zoom; compact active-pane fallback; retained hidden sessions |
| Saved arrangements | Up to 20 named arrangements with full split topology, ratios, tab order/names, active pane, font sizes and sanitized SSH routes; reads legacy schema v1 and writes v2 |
| SSH authentication | Password and encrypted/unencrypted key login, verified host keys, explicit gateway, up to three independently authenticated and verified jump hosts |
| SSH forwarding | Native local, remote and SOCKS5 TCP CONNECT listeners on existing verified routes; actual assigned ports; per-listener clients and errors; bounded ownership and cleanup |
| Saved destinations | Up to 50 secret-free profiles; shell/tmux/Screen modes and jump-route persistence; atomic import from a bounded OpenSSH configuration subset |
| Key bindings | Capture, add, edit, enable/disable and delete exact shortcuts; explicit text or complete terminal-key taps; recipient-specific keyboard protocols and broadcast integration |
| tmux and GNU screen | Create/attach, exact targets, non-evicting detach, manual reconnect and authenticated bounded session discovery |
| Navigation | Unicode/wrap-aware literal scrollback search, per-tab font size, OSC 133/633 command history, previous/next marks, manual/iTerm2 marks and completed-command output selection |
| Shell status and setup | Shell-reported directory/status/duration, one-shot in-app completion notification, review-and-copy Bash 4.4+/Zsh helpers preserving prompt hooks |
| Output triggers | Up to 50 persistent literal/limited-pattern rules; line-specific marks and in-app alerts; preview, cooldowns, per-connection one-shot state and bounded matching work |
| Multiple-session input | Explicit 2–8-tab broadcast groups, visible banner/Stop, per-recipient encoding and queued-input cancellation |
| Lifecycle | Generation-bound transport ownership, pending-opener/cleanup tracking, shared close futures and input provenance excluding terminal replies |
| Localization | New controls translated into all eight existing non-English locales |

## Behavior and limits

### Panes and arrangements

Splitting adds a new session beside or below the active leaf. Hidden-tab selection
replaces that leaf while preserving its siblings. Closing a pane collapses only
its parent split; **Single pane** hides other tabs without closing them. Each
branch keeps its own 20–80% proportion. Geometry respects minimum pane sizes and
falls back to the active pane when the complete topology cannot fit. Temporary
size clamps and zoom do not rewrite the saved layout. Blocked divider movement
must preserve the stored proportion for when the window is enlarged again.

Arrangements save tab order/names, the complete nested topology, active pane,
font sizes and sanitized SSH destinations/modes/routes. Restoring asks before
replacing tabs, waits for owned cleanup and opens replacements disconnected.
It does not restore local folder grants, staged-workspace authority, processes,
credentials, scrollback, command history or broadcast membership. Records use
local preferences; corrupt/newer versions remain intact. Legacy v1 two-pane
records migrate only on a successful write. There are at most eight tabs and
eight visible panes, with five concurrent SSH routes across the application.

### Custom key bindings

**Terminal actions → Key bindings** stores up to 50 exact logical-key/modifier
mappings. Actions send literal text (maximum 4,096 UTF-16 code units) or a
complete terminal-key tap. Text does not append Enter; intentional tabs and line
breaks are accepted, while raw escape/control bytes are rejected. The editor
states that mapping text is stored locally as plain text. It is not a credential
store, script runner or output-trigger system.

Printable shortcuts require Ctrl, Alt or Meta. Workspace navigation, search,
copy/paste, zoom, command navigation, Ctrl+C and the configured terminal-toggle
shortcut retain priority. Mappings require the active visible connected pane's
keyboard focus. One physical press runs an action once; repeats and release are
consumed across pane focus changes. Each broadcast recipient independently
encodes its own cursor/keyboard protocol, including Kitty release reporting.
Native IME input remains separate. Unknown/corrupt stores and duplicate chords
reject before a write.

### OpenSSH destination import

**Saved SSH profiles → Import OpenSSH config** previews pasted text and selected
literal positive Host aliases. It supports case-sensitive wildcard/negated Host
patterns, case-insensitive directive names, scalar first-value precedence,
HostName (including `%h`), User, Port, ordered ProxyJump and additive IdentityFile
hints. Jump aliases resolve their own options. Identity paths are displayed only;
they are never read, expanded or persisted. Credentials are requested normally
when connecting.

Match or Include anywhere in the paste blocks every alias until the complete
configuration is flattened. Command execution and unsupported routing/security
directives block the aliases to which they apply. Diagnostics explain both. The
importer handles OpenSSH proxy precedence, including `none`; nested proxy routes
must be flattened explicitly before import. It is not a complete OpenSSH
evaluator or live config watcher.

The input bounds are 128 Ki UTF-16 code units, 2,048 lines, 4,096 characters per
line and 100 literal aliases. A paste over the total text-size limit rejects the
entire edit and invalidates an earlier preview. Other size/count limits preserve
the pasted text but reject the complete preview. Import uses one storage lock
and one write: collisions or the 50-profile capacity limit save none of the
selection.

### SSH and session discovery

A complete route uses one of the five SSH session slots and retains the existing
30-minute activity timeout. Up to three jump hosts precede the final destination;
a configured gateway reaches the first hop. The final verified client now also
supports native local/remote/SOCKS5 forwarding controls. Intermediate direct-TCP
channels and forwarding do not provide SSH-agent authentication or agent forwarding.
Empty key passphrases normalize to absent passphrases so unencrypted jump keys
behave like direct connections; nonempty passphrases remain exact.

Discovery uses fixed locale-pinned commands, a separate no-PTY channel, a
ten-second deadline, a 256 KiB combined stdout/stderr budget and a 512-session
limit. It waits for output EOF and channel status. Canceling or invalidating a
picker releases its connection; stale results cannot launch a target. Screen
uses full PID.name and the exact resolver rechecks it before attach. Unsupported
names remain visible but disabled. Listing and attachment are subject to remote
rename/exit races.

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

## Previous continuation verification

The final normal-application run passed **585 tests with two platform skips and
zero failures across 54 files**, using Flutter 3.47.8 / Dart 3.13.7 and unchanged
production manifests. All 132 watched source hashes stayed unchanged during the
run and match remote source checkpoint `710422b5`. Intermediate targeted runs
overlap and are not added to that total.

| Check | Actual result |
| --- | --- |
| Native terminal cohort | 585 passed, 2 platform skips, 0 failed; actual Linux PTY TTY/ANSI/final-output/resize/Unicode/Ctrl+C/disposal checks included |
| Analyzer and formatter | 79 terminal-related Dart files; no analyzer issues and no formatting changes |
| OpenSSH import oracle | 14 comparisons with local `ssh -G` passed; portable runner and fixtures preserved |
| Bash/Zsh setup | 3 real interactive-shell scenarios passed: Bash scalar/array and Zsh hook behavior |
| Production widget captures | 4 scenarios passed; 16 inspected PNGs cover desktop/narrow panes, importer and key-binding controls |
| Workflow references | YAML parses and every referenced test resolves under its configured working directory |
| Full web release build | Passed at standard release/O4 settings with optional Wasm probe disabled; 4,173 input hashes unchanged |
| GitHub Actions | No result queried, awaited or required |

The native skips are the macOS-only shell fixture and Windows ConPTY. The
[complete local evidence](validation/terminal-parity-continuation/README.md)
contains commands, source identities, logs and the exact 54-file inventory.

The actual-loopback SSH runner uses disposable client/server keys and two
loopback-only sshd servers. Two normal-application tests pass: a jump route with
independent host verification, Unicode command execution and reconnect; and
changed target-host-key rejection. The interactive SSH PTY case is explicitly
skipped in this environment because the unprivileged sshd aborts while attempting
to write login records. This restriction does not affect the separate actual
local Linux PTY tests.

The browser attempt completed zero tests: Chromium failed before startup because
its Unix socket could not be created. Linux widget/native and compile results do
not establish Windows ConPTY, signed macOS, physical Android/iOS, an external SSH
gateway or a real tmux/Screen deployment. No GitHub Actions result is required.

Reproduction commands and manual checks are in
[the terminal guide](terminal.md#build-and-smoke-test-guide).

## Remaining larger parity areas

- Native tmux control-mode mapping of remote windows and panes.
- SSH-agent authentication/forwarding, reusable forwarding profiles and
  persistent connection multiplexing.
- Independent terminal windows and layouts beyond the current eight-tab limit.
- Automatic process/session restoration and secure reusable credential/identity
  integration beyond secret-free destination stores.
- Script/coprocess trigger actions, command automation, richer key-binding
  actions and broader shell integration beyond the current Bash/Zsh helpers.
- Qualification of graphics/file-transfer protocols and their app-level controls.
- Browser runtime, packaged Windows/macOS, physical mobile and external
  SSH/jump/tmux/Screen acceptance.

Ordinary tmux PTY attachment and browsing do not provide iTerm2's native tmux
control-mode integration. The next parity work should address these distinct
capabilities without describing the current terminal as fully equivalent.

## Historical validation boundaries

The prior continuation ending at `4cd8065a` authored the jump-route, arrangement,
broadcast, shell and discovery tests but completed **zero Flutter feature tests**:
disk exhaustion interrupted the first kernel load and the environment was then
lost. Remote checkpoints preserved that source. That limitation is retained in
[the original runtime attempts](validation/terminal-20261115/runtime-attempts.md),
[continuation checks](validation/terminal-20261115/continuation-checks.json) and
[source review](validation/terminal-20261115/source-review.json); it is not the
current result.

Earlier workspace checkpoint `44434bad` had **229 passing native tests and two
platform skips across 22 files**, with actual Linux PTY checks, clean analysis
of 28 changed files and synthetic desktop/narrow-widget inspection. Those counts
belong to that earlier source and are not added to the new cohort.

The earlier integration snapshots of 27, then 30 branch heads are retained in
[the initial audit](validation/terminal-20261115/integration.json),
[refresh record](validation/terminal-20261115/integration-refresh.json) and
[cutoff record](validation/terminal-20261115/integration-cutoff.json). The latest
34-head refresh above supersedes those repository cutoffs.

## Primary references

- iTerm2 [feature highlights](https://iterm2.com/documentation-highlights.html),
  [shell integration](https://iterm2.com/documentation-shell-integration.html),
  [tmux integration](https://iterm2.com/documentation-tmux-integration.html) and
  [profile key actions](https://iterm2.com/documentation-preferences-profiles-keys.html).
- GNU [Bash 5.1 announcement](https://lists.gnu.org/archive/html/info-gnu/2020-12/msg00003.html)
  and [Zsh hook documentation](https://zsh.sourceforge.io/Doc/Release/Functions.html).
- Pinned [xterm2 5.4.0 terminal API](https://github.com/SoFluffyOS/xterm2/blob/9d9901ee43ace000ef3dcbf0283db72cc0be1f70/core/lib/src/terminal.dart)
  and [CellAnchor implementation](https://github.com/SoFluffyOS/xterm2/blob/9d9901ee43ace000ef3dcbf0283db72cc0be1f70/core/lib/src/core/buffer/line.dart).
