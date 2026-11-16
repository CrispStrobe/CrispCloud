# SSH forwarding and output triggers — local acceptance

This continues the terminal work after PR #140 was merged, on
`codex/terminal-screen-workspace` in draft PR #160. Source, regression fixes and
evidence are saved through incremental remote commits. No GitHub Actions result
was queried, awaited or required; all new commits carry `[skip ci]`.

## Verified result

**676 native tests passed, two platform tests skipped, zero failures across
60 files.** The separate actual OpenSSH run passed **six tests**, with one
optional interactive SSH PTY case skipped. Static analysis and formatting are
clean across **99 terminal-related Dart files**. These are the normal production
dependency graph and native hooks, using pinned Flutter **3.47.8** / Dart
**3.13.7** and an unchanged lockfile.

| Check | Result | Record |
| --- | --- | --- |
| Full terminal regression cohort | 676 passed; two platform skips; zero failures; 60 files | [Command, counts and source identity](native.json), [complete log](native.log.gz) |
| Static analysis | 99 Dart files; zero issues | [Record](analysis.json), [log](analysis.log.gz) |
| Formatting | Same 99 files; zero changes needed | [Record](format.json), [log](format.log.gz) |
| Actual loopback OpenSSH | Six passed; one optional interactive PTY skip | [Record](live.json), [log](live.log.gz) |
| Production-widget visual inspection | Four PNGs, including 320×320 manager/editor/validation | [Receipt](visual/receipt.json), [capture test log](visual/tests.log.gz) |
| Managed Office source identity | All 2,391 managed-file hashes and tracked modes match | [Verifier output](vendor-verification.txt) |
| Browser runtime | Zero tests; Chromium failed before startup with a socket permission denial | [Receipt](browser/receipt.json), [stderr](browser/startup.stderr.txt) |
| Full web release compilation | Initial compiler process killed with exit -9; isolated retry pending | [First attempt](web-attempt-1.json), [log](web-attempt-1.log.gz) |

The test/analyzer source checkpoint is
[`ea9a5463`](https://github.com/CrispStrobe/CrispCloud/commit/ea9a546397629ba002a6bf0452be9e2db7105b7e).
Every one of **5,388 watched source/dependency/test files** remained unchanged
during those runs. Their exact SHA-256 inventory is
[source-sha256.json.gz](source-sha256.json.gz). Subsequent integration
[`4a6a03b9`](https://github.com/CrispStrobe/CrispCloud/commit/4a6a03b94550378e77ba7b863d4dcbbaf19fcfcd)
added only two Zotero audit documents, preserving every tested input. Intermediate
targeted test counts overlap the final cohort and are not added to its total.

## What the new tests establish

The forwarding model/native cohort covers local, reverse and SOCKS5 behavior,
listener allocation and refusal, half-close/final-response delivery, explicit
Stop, active and pending client cleanup, late channels/listeners, a server which
never replies to remote creation, failed cancellation, the 16/32 resource caps,
fragmented SOCKS messages, pipelined application data, IPv4/IPv6/DNS targets,
unsupported protocol requests and handshake expiry.

Four new actual OpenSSH cases use two disposable loopback-only sshd servers and
independently verified jump/final host keys. Local, remote and SOCKS paths each
transfer an exact **3 MiB binary payload plus Unicode**, exceeding the initial
SSH channel window. Request half-close preserves the full final response.
Listener Stop leaves ordinary SSH command execution working; disconnect closes
active client sockets and both listener kinds. The runner removes its temporary
keys and servers. Two retained actual SSH cases cover verified jump execution,
reconnect and changed-host-key rejection.

Trigger tests compare the supported pattern language against an independent
regular-expression oracle on bounded fixtures, exercise adversarial repeated
quantifiers, every UTF-16 split of control/Unicode output, CR redraw/erase,
alternate-screen suppression, command-input separation, cooldowns, one-shot
reset, action/matching-work budgets and concurrent/corrupt persistence. Session
tests verify line-specific marks and natural EOF/reconnect behavior. Dialog
tests cover edits, preview, disabling/deleting rules, invalid input, all eight
translations and a 320×320 viewport. Forwarding dialog tests additionally cover
all three modes, actual allocated ports, pending operations, connection expiry,
the listener cap and actionable remote-cleanup explanations.

## Integration

The initial refresh brought in main `45ed126a` and audited **37 live branches
and all 149 available PR heads**. The only absent original heads were #158 and
#159; both exactly matched their already-merged squash trees. Checkpoint
`5c2dbea9` retains those original heads as parents without reverting newer code.
[The original snapshot](integration.json) contains every ref and comparison.

The final advertised snapshot at **2026-11-16 05:21:54 UTC** contains **38 branch
heads and 150 PR heads**. It found a new Zotero continuation branch at
`d916a841`, which cleanly contributes two audit documents. Merge `4a6a03b9`
contains **all 188 snapshot references as actual ancestors**. The merge tree
matches `git merge-tree` exactly. All 2,391 vendor blob IDs and modes, the vendor
manifest and source pins are identical across current, incoming and merged
trees. See [the final remote audit](final-remote-audit.json).

## Repairs exposed by verification

The [first full run](attempt-1/native.json) passed 668 tests and exposed six
reconnect failures: opening terminal actions asked an alternate SSH service for
a forwarding manager it did not own. Capability lookup now returns unavailable
without creating a manager or throwing. The full 60-file rerun passes. The
original log and source identity are preserved in `attempt-1`.

Review also found that an unanswered remote-create request could leave a server
listener whose allocated port was unknown. Timeout/Stop now closes that SSH
transport, just as an unconfirmed remote cancellation does. Native regressions
cover servers that never reply. Known forwarding errors retain their specific,
translated explanation; unexpected errors use a generic message. The refined
error-expectation run is preserved alongside the
[27-test successful fix check](focused-fixes.log.gz).

The original formatting pass found two inherited unformatted test blocks in
the newer main work. Those blocks were formatted before the final source
checkpoint; the final 99-file formatting check is clean.

## Environment and limits

[Environment receipt](environment.json) and [lock-enforced dependency log](dependency-resolution.log.gz)
record the exact SDK/native tools and unchanged application manifests. Native
hooks were built normally. A scratch launcher invoked the already-bootstrapped
pinned Flutter tool snapshot directly to avoid a concurrent SDK bootstrap temp
filename collision between isolated exec sessions. This did not alter SDK
sources, the application graph, compiler settings or native hooks.

The two native skips are the macOS-only shell fixture and Windows ConPTY. The
OpenSSH runner's optional interactive PTY case was not enabled. Separate real
Linux PTYs passed within the native cohort. Packaged/signed macOS, Windows,
physical Android/iOS, external gateways and a real tmux/Screen deployment still
require their own acceptance. Chromium's startup probe exited 134 because Unix
socket creation was denied, so no browser-runtime test result is claimed.

Visual captures use production widgets and a synthetic forwarding manager,
with real Roboto fonts. They establish layout, not live connectivity or physical
device behavior. The receipt records their earlier exact widget hashes; final
runtime-error presentation changes are covered by the final widget regressions.

## Reproduction

With the pinned SDK/native prerequisites on PATH:

```sh
flutter pub get --enforce-lockfile
python3 tool/run_terminal_validation.py native
python3 tool/run_terminal_validation.py analysis
python3 tool/run_terminal_validation.py format
python3 tool/run_terminal_validation.py live
python3 tool/run_terminal_validation.py web
python3 tool/verify_office_fidelity.py --require-tracked
```

The wrapper stores exact commands, source inventories, unchanged-input checks
and logs. `live` creates only disposable loopback SSH fixtures. `web` uses normal
release optimization, the version from `pubspec.yaml`, the tested Git hash and
`--no-wasm-dry-run`; it does not claim WebAssembly qualification. Archived logs
and input inventories here are gzip-compressed without changing their contents.
