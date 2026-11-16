# Native tmux workspace acceptance

This continuation starts from `ce386fd6` on
`codex/terminal-screen-workspace` / draft PR #160. It adds an opt-in tmux 3.2+
control client and native window/pane workspace while retaining the preceding
SSH-agent, forwarding, trigger, ordinary PTY and saved-arrangement work.

## Integration and remote checkpoints

Before implementation, all **38 remote branch heads and 151 available PR heads**
were fetched. All 189 references were already actual ancestors of the starting
commit, including main and PR #161. No merge was required. Exact refs are in
[`integration.json`](integration.json).

| Checkpoint | Purpose |
| --- | --- |
| `8625aad7` | Fresh complete branch/PR ancestry audit |
| `aa8c736f` | Incremental native tmux protocol, raw SSH transport and workspace implementation |
| `6e11d2d6` | Screen restoration, ownership, focused regression coverage and visual evidence |
| `4316f7fc` | Clean merge of the newer Zotero/Office head `e980293c` |
| `359e3997` | Detached-buffer browsing, retryable cleanup and integrated provenance evidence |

The 07:26:39 UTC refresh found new PR #161 work after the initial snapshot.
Checkpoint `4316f7fc` merges that exact head and contains all 189 refreshed refs.
The incoming delta was confined to 33 Office/Zotero files and evidence; dependency
pins and terminal code were unchanged. Its application transport suite passed
16 tests. The updated Office guard verifies 2,407 files at Quds `9b31295b`;
the SSH guard verifies 96 upstream files and four patches. All 33 workflow YAMLs
parse, and the six new deterministic suites are registered in the applicable
platform lists and the 75-file local cohort. See [`audit-final/README.md`](audit-final/README.md).

Further implementation and acceptance checkpoints are recorded after the
combined local validation finishes. Every checkpoint carries `[skip ci]`.
**GitHub Actions were not queried or awaited.**

## Implemented behavior

- A default-off **Native tmux panes** option in SSH create/attach settings.
- A non-PTY SSH execution channel with raw protocol bytes and separately bounded
  diagnostics. Existing host-key verification, jump routes and agent permissions
  remain in the connection path.
- Strict bounded tmux framing, command-response correlation, streaming pane UTF-8,
  metadata refresh, screen capture and per-pane input queues.
- Remote windows as native tabs and remote cell geometry as independent terminal
  panes. Selection, new window, splits, client resizing, local zoom, compact pane
  picker, search and explicit clipboard actions are available.
- Active and saved primary screen restoration, pending parser bytes and common
  cursor/input modes on initial attachment. Emulator protocol replies are
  suppressed because tmux handles the remote application's queries.
- Credential-free v4 profile/arrangement persistence, custom key bindings and
  output triggers, plus all eight existing non-English locales.
- Non-killing detach, exact channel-generation ownership, pending-connect
  cancellation, caller-owned session remount and retained disconnected buffers.

## Validation status at the implementation checkpoint

Focused development runs passed: 83 SSH/configuration/persistence/broadcast
tests; 35 protocol/client tests; 12 workspace behavior tests plus one visual
capture; 36 ownership/broadcast/session tests; and three input-budget tests.
These runs overlap and are **not** a combined acceptance count. The frozen-source
cohort, static analysis, formatting, loopback OpenSSH checks and optimized web
release build are still pending at this checkpoint. Their final records will
replace this status once completed.

A later 42-test SSH transport run covers cleanup retry and release even if a
stream cancellation fails. The final workspace test additionally exercises real
wheel/selection/copy gestures and local window/pane navigation after disconnect,
with remote commands and input revoked. Additional protocol tests cover output
crossing a size change, superseded metadata/captures, unchanged-layout history,
continued input during capture, and an absent older-tmux paste-mode format.
The UI's final 13-test run includes visible failure after exceeding the bounded
input budget. Final combined acceptance remains pending below.

Four production-widget fixture captures were inspected: desktop split panes,
local zoom, 320x320 compact layout and the compact pane picker. They verify
layout with injected pane connections; they do not establish live tmux behavior
or complete font coverage. The deterministic widget tests also exercise a
160-pixel outer split.

The pinned Flutter 3.47.8 / Dart 3.13.7 environment, normal native build hooks,
enforced offline production lockfile and dependency provenance are documented in
[`environment/README.md`](environment/README.md).

## Actual tmux acceptance boundary

The unmodified tmux 3.5a server probe failed with **Operation not permitted** on
its Unix socket. The opt-in live harness therefore completed **zero actual tmux
feature tests**. [`live-tmux/live-tmux.json`](live-tmux/live-tmux.json) records the
command, exit code and skip reason. This is an environment limitation, not a
passing daemon run. No socket-policy workaround was attempted.

On a host that permits ordinary Unix sockets, run:

```sh
python3 tool/run_tmux_control_live_smoke.py
```

The runner uses a dedicated tmux socket and an isolated server, then checks
Unicode pane input/output, window and split creation, external layout changes,
remote selection and geometry, alternate-screen reattachment, saved primary
screen restoration and detachment without destroying the remote session.

## Remaining limits

This is an initial bounded native workspace, not complete iTerm2 tmux parity.
Limits are 16 windows, 64 panes and bounded geometry, buffers and queued input.
Initial history is at most 200 lines within the pane buffer budget. Original
history can also be reduced to that capture budget after a real pane-size
change; unchanged-geometry notifications preserve it. On older tmux versions
without `bracket_paste_flag`, initial attachment cannot infer an already-enabled
paste mode; modes observed from live output survive later recaptures. Original
soft-wrap metadata, custom tab stops and every terminal/SGR mode are not restored.
Direct pane input does not render tmux's interactive prefix/copy-mode interface;
ordinary PTY mode remains available for that workflow. Mouse/focus forwarding,
full command-history/status controls and the ordinary mobile prefix row are not
mapped to native panes. Remote pane/window destruction is not exposed.

Independent operating-system windows, automatic process/session restoration,
unattended reconnect, general persistent SSH connection multiplexing and broader
trigger/coprocess automation remain separate parity work. Actual tmux servers,
browser runtime, packaged macOS/Windows and physical mobile devices need their
own acceptance runs. Linux actual system-agent acceptance also remains blocked
by this host's Unix-socket policy.

See the [native tmux guide](../../terminal.md#native-tmux-windows-and-panes) and
[feature coverage](../../terminal-parity.md) for user-facing behavior.
