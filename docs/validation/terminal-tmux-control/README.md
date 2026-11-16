# Native tmux workspace acceptance

This continuation adds opt-in tmux 3.2+ control-mode windows and panes on
`codex/terminal-screen-workspace`, draft PR #160. The accepted source candidate is
**`60bc3a4155c3c1e1b7107cc087647ac79938b0d6`**. It includes the final remote
Zotero/Office head `fc09d3f5`, the complete native tmux implementation and the
correctness fixes below. Later evidence/documentation checkpoints preserve the
same watched application, dependency and test inputs.

**No GitHub Actions were queried or awaited.** Checkpoints carry `[skip ci]`.

## Local acceptance

Validation uses pinned **Flutter 3.47.8 / Dart 3.13.7**, normal native build hooks
and the enforced production lockfile. No substitute dependency graph or disabled
native hook was used for the terminal acceptance phases.

| Check | Result | Record |
| --- | --- | --- |
| Complete terminal regression cohort | **896 passed, 2 platform skips, 0 failures across 75 files**; 153.922 seconds | [native.json](native.json), [native.log.gz](native.log.gz) |
| Static analysis | **142 Dart files**, no issues; 25.648 seconds | [analysis.json](analysis.json), [analysis.log](analysis.log) |
| Formatting | **142 Dart files**, no changes | [format.json](format.json), [format.log](format.log) |
| Actual loopback OpenSSH | **17 passed, 2 explicit skips, 0 failures across three files**; 93.066 seconds | [live.json](live.json), [live.log](live.log) |
| Production-widget visual inspection | **Four** desktop/320x320 captures; all regenerated on the accepted UI and inspected | [visual receipt](focused/visual-receipt.json), [screenshots](focused/screenshots) |
| Office provenance | **2,409 managed files**, tracked modes and hashes pass at Quds `ca4011de` | [postmerge provenance](remote-cutoff/postmerge-vendor-verification.json) |
| SSH provenance | **96 dartssh2 4.1.0 upstream files and four reviewed patches** pass | [postmerge provenance](remote-cutoff/postmerge-vendor-verification.json) |
| Full optimized application web release | **Running; not yet accepted at this checkpoint** | Final result will be recorded in `web.json` |

All **5,535 watched source/dependency/test files** have identical hashes across
native, analysis, formatting and live OpenSSH phases. Each phase also checks
before/after equality. The inventories are retained as losslessly compressed
`*-source-sha256.json.gz` files. [Pre-web source verification](pre-web-source-verification.json)
records their identity. Final web/source verification follows after the build.

The new deterministic suites are registered in the applicable browser/native
workflow lists and the 75-file local runner. All **33 workflow YAMLs** parse with
duplicate-key checks, all referenced new test paths exist, and the SSH vendor
guard remains registered in CI, nightly and release workflows. These are local
registration checks, not GitHub Actions results. See
[workflow verification](audit-final/workflow-entrypoints.json).

### Scope of the passing runs

The regression cohort covers the prior terminal workspace, SSH agents,
forwarding profiles, triggers, shell integration and ordinary tmux/Screen
behaviors together with the native tmux protocol, pane UI, persistence and
lifecycle work. Focused development counts overlap this cohort and are not added
to the acceptance total.

Actual OpenSSH coverage uses disposable loopback servers and verified direct/jump
routes. Local, remote and SOCKS5 forwarding each transfer an exact **3 MiB binary
payload plus Unicode**. Agent and rekey interoperability includes disposable
keys, framed in-memory agent requests, trust-before-signing, refusal, cancellation
and revocation, plus **512 KiB binary and Unicode across actual rekey**. The
actual Unix-agent/remote `ssh-add` case is explicitly skipped because this host
denies Unix sockets. The other live skip is the optional interactive SSH PTY
fixture; actual local Linux PTYs pass in the native cohort.

The visual test uses the production workspace widget with injected pane
connections. Its desktop split, local zoom, compact 320x320 and pane-picker
captures verify layout, not a live daemon, browser runtime or complete font
coverage. Behavior tests additionally cover 160-pixel outer splits, actual
selection/scroll/copy gestures after closure, hidden/focus ownership and visible
input-budget failures. The four final PNGs are byte-identical to the captures
previously inspected by the root reviewer.

## Integration and remote checkpoints

The continuation began at `ce386fd6`. The initial fresh fetch contained **38
branch heads and 151 PR heads**, all 189 already actual ancestors, including main
and PR #161. No initial merge was required; see [integration.json](integration.json).

The **07:26:39 UTC** refresh found PR #161 at `e980293c`. A clean merge brought in
saved searches, small caps and bibliography layout. The final pre-acceptance
advertisement, completed at **07:44:13.637994 UTC on 16 November 2026**, found
`fc09d3f5`, adding typography/bibliography hardening and qualification evidence.

The second incoming merge had two merge bases because the parallel Zotero branch
had itself incorporated an earlier tmux checkpoint. Ordinary Git merge preserved
the newer tmux source. The effective incoming delta was inspected against the
prospective merged tree, rather than relying on an ambiguous single-base diff.
It changed no terminal source, dependency manifests, lockfiles, workflows or
terminal runner. The resulting merge tree is
`0874a6271d01922565d5edbe96b0b83d1f7879c4`.

**All 189 heads in the 07:44 cutoff are actual ancestors of published
`60bc3a41`.** Exact refs, both incoming reviews, merge trees, provenance guards and
postmerge ancestry are retained in [the first refresh](audit-final/README.md)
and [the final cutoff](remote-cutoff/README.md).

| Published checkpoint | Purpose |
| --- | --- |
| `8625aad7` | Initial complete branch/PR ancestry audit |
| `aa8c736f` | Incremental protocol, raw SSH transport and native workspace |
| `6e11d2d6` | Screen restoration, ownership, regression coverage and visual evidence |
| `4316f7fc` | Merge newer Zotero/Office head `e980293c` |
| `359e3997` | Detached-buffer browsing, cleanup retry and integration evidence |
| `e61256c2` | Resize/output synchronization, bounded snapshot ownership and final focused fixes |
| `60bc3a41` | Merge final incoming typography/bibliography head `fc09d3f5`; source used by full acceptance |

GitHub checkpoints are created through the connected Git data API because the
local Git remote lacks push credentials. Every published tree is compared with
the exact local Git tree; branch updates check the expected previous head and
never force through another writer. Both incoming merges retain their actual
parents. Local reconciliation uses the identical committed tree and preserves
working changes.

### Incoming Office acceptance remains separately scoped

The earlier local production-graph Office transport run passed **16 tests**.
The incoming final qualification separately reports **39 tests across three host
suites**, using a focused 96-package host graph. These counts overlap and are not
added. All seven imported step-log hashes, all **417 archived Office package
source/config files**, all eight host analysis/test targets and all 2,409 manifest
hashes match the final integrated Office bytes. Four later tmux files differ in
the broader incoming host inventory and are outside that Office qualification.
See [the source/evidence comparison](remote-cutoff/incoming-office-acceptance-comparison.json).
This is not new live Zotero, keychain, Word-refresh or complete Office acceptance.

## Implemented behavior

Enable **Native tmux panes** in the SSH form after selecting create/attach tmux.
The option is off by default. The existing verified destination and ordered jump
route, independent authentication choices, explicit agent permission and
forwarding controls remain in effect. Control mode uses one non-PTY SSH execution
channel; stdout remains raw protocol bytes and stderr is separately bounded.

Remote windows appear as native tabs within the current terminal tab. Remote
pane geometry maps to independent emulators. Selection, new windows, both split
directions, overall client resize, local zoom, compact pane picking, literal
search and explicit clipboard actions are available. Custom key bindings and
saved output triggers apply to individual panes. New UI text is translated into
all eight existing non-English locales.

Profile and arrangement envelope v4 retains native mode without credentials.
Closing the control client releases its exact SSH route without issuing remote
kill commands. Server settings such as `destroy-unattached` still apply. Hiding
or remounting a caller-owned panel preserves the connection. After closure,
retained windows/panes remain locally navigable, scrollable, selectable and
copyable; remote input and paste are revoked.

## Correctness fixes established during review

- Per-pane streaming UTF-8 preserves characters split across different `%output`
  records. Protocol blocks correlate exact guards; startup/hooks do not consume
  replies belonging to commands sent on stdin.
- Screen captures and live output use different backslash escaping rules. Their
  decoders are distinct, avoiding corruption of literal backslashes.
- Initial capture restores active/saved primary screens, pending parser bytes,
  cursor, scroll region and common input modes. Capture replay completes before
  subsequent output in the same packet. tmux answers application queries; the
  additional emulator's automatic replies are suppressed.
- A layout notification gates affected output synchronously before stale-size
  rendering can corrupt a redraw. Revision checks reject superseded metadata or
  captures, and dimensions sampled with the screen prevent stale publication.
  Unchanged geometry preserves history; valid input still reaches its pane
  during resynchronization.
- Superseded, never-published panes are promptly disposed. Published views retain
  their buffers until replacement. Owned current/replacement snapshots have a
  hard 128-session cap, in addition to the 64-pane published workspace limit.
- Older tmux releases omit `bracket_paste_flag`. Only that field may be absent;
  the last observed live paste mode is preserved, initially off. Fixtures expand
  actual requested formats so an unsupported field is exercised.
- Exact channel-generation leases prevent an old client from writing to or
  closing a replacement. Pending SSH exec/handshake cancellation, caller-owned
  remount, closed-buffer lifetime and failed-close retries are covered.
- A stream cancellation error cannot skip route cleanup. Pending pane input is
  bounded before queue admission; a failed pane visibly requests reconnection
  while its retained output and other healthy panes remain usable.
- Clipboard results arriving after pane, connection, visibility or focus changes
  are rejected. Native pane identities never silently retarget cross-tab
  broadcast membership.

Focused logs and screenshots are retained under [focused/](focused) and the
[ownership review](focused-ownership/README.md). These are diagnostic stages;
the combined 896-test run above is the final native acceptance result.

## Actual tmux and platform boundary

The unmodified tmux **3.5a** server prerequisite failed with **Operation not
permitted** on its Unix socket. The live harness completed **zero actual tmux
feature tests**. [The receipt](live-tmux/live-tmux.json) records the exact command,
exit code and skip reason. No socket-policy workaround was attempted.

On a host that permits ordinary Unix sockets, run:

```sh
python3 tool/run_tmux_control_live_smoke.py
```

The harness uses a dedicated socket and isolated server. It checks the real
client's Unicode input/output, window/split creation, external layout changes,
selection, requested 120x40 client size, server geometry, alternate-screen
reattachment, saved primary screen restoration and non-killing detach. Cleanup
attempts the dedicated server shutdown even after client/probe failure and
reports unsuccessful cleanup. The optional harness was statically checked;
its feature assertions have not executed on this host.

This remains an initial bounded workspace, not complete iTerm2 tmux parity:

- At most **16 windows and 64 published panes**, with bounded geometry, protocol
  records, buffers, command queues and input.
- Attachment and real pane-size changes recapture up to **200 history lines**
  plus the visible screen within the local budget. A size change can therefore
  trim older locally retained history. Unchanged geometry preserves it.
- Original soft-wrap metadata, custom tab stops, exact current SGR and all
  terminal modes are not reconstructed. Already-enabled bracketed paste cannot
  be inferred at initial attach on tmux versions without the snapshot format;
  live mode changes are subsequently learned and retained.
- Direct pane input does not render tmux's interactive prefix/copy-mode
  interface. Ordinary PTY tmux remains available for that workflow. Mouse/focus
  reports are suppressed, and advanced keyboard modes need broader qualification.
- Full command-history/status controls and the ordinary mobile prefix row are
  not mapped to native panes. Remote pane/window destruction is not exposed.
- Independent operating-system windows, automatic process/session restoration,
  unattended reconnect, general persistent SSH connection multiplexing and
  broader trigger/coprocess automation remain separate work.
- Browser runtime, packaged/signed macOS, Windows ConPTY, physical mobile
  devices, external gateways and real tmux/Screen deployments still need their
  own acceptance. Actual system-agent acceptance remains blocked here too.

## Reproduction and environment

The restored toolchain and verified downloads are recorded in
[environment/README.md](environment/README.md). With that toolchain available,
run from the repository root:

```sh
../toolchain/run python3 tool/run_terminal_validation.py native --evidence docs/validation/terminal-tmux-control
../toolchain/run python3 tool/run_terminal_validation.py analysis --evidence docs/validation/terminal-tmux-control
../toolchain/run python3 tool/run_terminal_validation.py format --evidence docs/validation/terminal-tmux-control
../toolchain/run python3 tool/run_terminal_validation.py live --evidence docs/validation/terminal-tmux-control
```

The full web build uses the existing
[`web-resource-runner.py`](../terminal-agent-profiles/web-resource-runner.py)
with `--run` and this evidence directory. It applies a compiler-only 3,072 MB VM
heap cap to the standard O4/minified release build and verifies exact SDK binary,
snapshot and mode restoration. It must run after other SDK users finish.

Protocol compatibility was reviewed against upstream
[Control Mode](https://github.com/tmux/tmux/wiki/Control-Mode),
[tmux 3.2 formats](https://github.com/tmux/tmux/blob/3.2/format.c),
[capture options](https://github.com/tmux/tmux/blob/3.2/cmd-capture-pane.c), and
[refresh commands](https://github.com/tmux/tmux/blob/3.2/cmd-refresh-client.c).
See the [user guide](../../terminal.md#native-tmux-windows-and-panes) and
[feature coverage](../../terminal-parity.md) for the available workflow.
