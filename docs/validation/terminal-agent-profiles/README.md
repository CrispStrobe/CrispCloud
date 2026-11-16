# SSH agent and saved forwarding profiles: acceptance record

This continuation adds native SSH-agent authentication, explicit final-host
agent forwarding, and reusable forwarding profiles to the existing terminal.
It continues `codex/terminal-screen-workspace` from `e6cb6eee` and retains draft
PR [#160](https://github.com/CrispStrobe/CrispCloud/pull/160).

**Acceptance status: the complete terminal regression cohort passed 813 tests,
with two platform skips and no failures. The combined live OpenSSH rerun passed
17 tests with two explicit skips. Static analysis/formatting, dependency
provenance verification and the full optimized web release build also passed.
All five acceptance phases used the same 5,511 unchanged watched inputs.**
The final remote snapshot contains all 189 advertised branch/PR heads.
Focused counts below overlap the complete terminal cohort.

The user requested incremental remote checkpoints and instructed that GitHub
Actions must not be queried or awaited. Work was saved to the continuation
branch with `[skip ci]`; validation uses local tools. No GitHub Actions result
is part of this record.

Usage and current feature coverage are maintained separately in
[the terminal guide](../../terminal.md) and
[the parity assessment](../../terminal-parity.md).

## Integration before implementation

The [initial integration receipt](integration.json), captured at
**2026-11-16 05:55:56 UTC**, records **38 branch heads and 151 available PR
heads**, a total of **189 references**. Every reference is an actual ancestor
of integration checkpoint
`7203aa28382fbe6ad14523548b71113ee1e4519b`; `uncontained` is empty.

The only newly advertised source head missing from the preceding terminal
checkpoint was `cf442dd2aab29211ab8b9c80f0767373b91a3c94`, shared by
`codex/zotero-support-20261116` and PR #161. Its three incoming commits were
`e5dc3dc5`, `91064098`, and `cf442dd2`. The ordinary merge integrated the newer
Zotero/Office work without replacing the terminal source. Its reviewed merge
tree is `e70f63eef11208aa7b871eba77d48edb582883b9`.

The integration advances the canonical Quds pin to
`b24718cc1468c34f494805eb7fb433a87f565503`. All **2,399 managed Office/vendor
entries** passed the source-hash and tracked-mode guards: 542 Quds entries and
1,857 standalone parser entries. This inventory is separate from the newly
checked-in `dartssh2` runtime described below.

A later [remote advertisement and ancestry check](remote-refresh/remote-heads-062410.json),
captured at **06:24:10 UTC**, again found 38 branch heads and 151 PR heads, all
contained by `13756a8f9231f17173e6b0deb8ebca0c729d4510`. Its
[raw advertisement](remote-refresh/remote-heads-062410.tsv) is retained. This
is a dated snapshot. The [final remote audit](final-remote-audit.json), captured
at **06:37:52 UTC**, again contains 38 branch heads and 151 PR heads, all actual
ancestors of evidence checkpoint `793bf628`. No additional objects or merges
were needed. The [raw final advertisement](final-remote-advertisement.tsv) is
preserved with the exact cutoff references.

### Incremental remote checkpoints

These are saved implementation checkpoints, not interchangeable validation
source identities. Later acceptance receipts must name their actual source.

| Checkpoint | Purpose |
| --- | --- |
| `7203aa28382fbe6ad14523548b71113ee1e4519b` | Integrate the latest Zotero/Office work before terminal implementation. |
| `8a204be242081a1db88e99e2cfde0026ec15c7a5` | Preserve the complete remote integration inventory. |
| `9449b86e89ffc01fddddc3545d3e5a4111e4536c` | Save the SSH-agent and forwarding-profile foundations. |
| `13756a8f9231f17173e6b0deb8ebca0c729d4510` | Bound agent channels and preserve initial agent/profile regression coverage. |
| `d5876720d714e4b78d86dac1f68a06fe8c37349f` | Preserve usable profile management across disconnects and agent-route checks. |
| `9753a980f6bfe94abe7940f59bd19287e4f65c57` | Freeze combined authentication/channel hardening and provenance for full local acceptance. |
| `793bf62821cd8234b3fcb7e8c5d17c880651a963` | Save the passing native/live/static checks, exact input inventories, and seven inspected visual outputs. |

Subsequent commits retain acceptance source `9753a980` and add evidence,
documentation and workflow registration. The [source comparison](final-source-verification.json)
checks every accepted input against the Git source checkpoint and final working
source, and the final remote snapshot records all advertised references. Remote
updates use the expected prior branch SHA and are fetched back for exact tree
verification; application work was never replaced by a stale branch snapshot.

## Production dependency identity

The application still uses **`dartssh2` 4.1.0**, with the same package version
and runtime dependency constraints. Its runtime now resolves permanently to
the checked-in `packages/dartssh2` through the root `dependency_overrides`
entry, and `pubspec.lock` records that path at version 4.1.0. This is a deliberate
production dependency change. It applies to terminal SSH, other SSH/SFTP
consumers, native hooks, tests, and release builds.

The copied upstream archive is:

```text
https://pub.dev/api/archives/dartssh2-4.1.0.tar.gz
SHA-256: 39359aceafcf5940b868249e3c9c6d86e4e0f989eec7417d033c943157c84c51
License: MIT
```

[UPSTREAM.md](../../../packages/dartssh2/UPSTREAM.md),
[UPSTREAM.json](../../../packages/dartssh2/UPSTREAM.json),
[PATCHED.json](../../../packages/dartssh2/PATCHED.json), and the local patch
record identify **96 copied upstream files and four modified runtime files**.
Local hardening covers agent-channel admission/framing/backpressure, send
completion, transport flush behavior during rekey, and asynchronous public-key
authentication. The [vendor verification receipt](vendor-verification.json)
binds the combined source at `9753a980`: both tracked-file guards passed, and
applying the local patch to the exact upstream source reproduces all four
current runtime files. Earlier three-file inventories describe earlier source.

The normal application graph resolved successfully with the vendored runtime,
including lockfile enforcement. The original
[dependency-resolution log](environment/app-pub-get-vendored.log) and
[enforced-lockfile log](environment/app-pub-get-vendored-enforced.log) are
retained. These successful dependency checks do not substitute for application
tests. The accepted tracked-file verification commands were:

```sh
python3 tool/verify_dartssh2_vendor.py --require-tracked
python3 tool/verify_office_fidelity.py --require-tracked
```

The unchanged Office guard initially rejected the new override's position
because its strict manifest check expects `legacy_doc_parser` first. Restoring
that existing entry order preserved the same dependency graph and allowed the
unchanged guard to verify all 2,399 managed entries. No managed Office source
was modified for this terminal feature.

All local Flutter/Dart validation uses the repository's pinned **Flutter
3.47.8 / Dart 3.13.7**. Temporary local cache preparation is environment setup;
the checked-in override and lockfile are the application dependency inputs.

## Implemented behavior and boundaries

### SSH-agent authentication and forwarding

The native Linux/macOS backend uses the exact `SSH_AUTH_SOCK` inherited by the
application. It snapshots supported public identities and requests signatures
from the local agent. It does not import private keys, start an agent, search
key files, or fall back to password authentication when agent authentication
fails. Host-key approval precedes signing for each independently authenticated
jump server and the final server.

**Forward SSH agent** is a separate, default-off permission, usable with
password, private-key, or agent authentication. Only the final SSH client
receives the forwarded handler. Jump hosts never receive forwarded agent
authority. The form explains that final-server programs can request signatures
while connected; saved destinations and arrangements preserve this explicit
choice and show it again on reconnect.

Forwarded requests can list the original supported keys or ask those keys to
sign. New agent keys do not appear in an existing connection. Mutations,
locking/unlocking requests, extensions, unknown keys, unsupported algorithms,
and RSA/SHA-1 requests fail. Route cancellation, disconnect, replacement, and
remote closure revoke local agent operations before asynchronous transport
cleanup finishes. Socket paths, key comments, and private-key material are not
persisted.

Bounds include 64 listed keys, four simultaneous local transactions, 256 KiB
frames, a 10-second local transaction deadline, and 32 forwarded requests per
second. Incoming SSH agent channels have separate admission, receive-window,
framing, stalled-operation, and output bounds. Final low-level limits and source
identity are recorded by the completed dependency provenance and channel tests.

### Saved forwarding profiles

Profiles retain a name, local/remote/SOCKS5 settings, and an explicit Auto-start
choice. Identity is the exact host, port, username, gateway, and ordered jump
route, copied without credentials. Authentication and shell/tmux/Screen launch
mode do not select a different forwarding route. Storage is bounded to 50
profiles overall and 16 per route.

Saving or enabling Auto-start does not open a listener immediately. Manual
**Start** reuses an equal active/ad-hoc listener, including a requested port of
zero. Auto-start runs at most once per new forwarding manager, only after the
verified connection and shell succeed. It rereads each eligible recipe before
opening it and cancels stale queued work. **Stop** keeps the current connection
stopped; a later reconnect can honor the saved Auto-start choice.

Changing forwarding settings stops matching owned listeners before saving;
changing only the name or Auto-start metadata leaves active listeners running.
**Delete and stop** cancels starts and stops matching listeners across related
open sessions. A cleanup failure preserves the saved recipe and its visible
error. Shared store locking, duplicate checks, optimistic edit snapshots,
strict versioned parsing, and bounded storage prevent lost updates and
overwriting corrupt/future data.

An open manager/editor remains usable for saved edits and deletion after
disconnect, while listener creation is disabled. The panel retains its
coordinator until the owned dialog route finishes its reverse transition;
connection identity still revokes start authority immediately. All newly added
controls and stable error messages have translations in the existing eight
non-English locales.

## Completed focused checks — intermediate and overlapping

**Do not add these counts together.** Suites overlap, some were rerun after
fixes, and they describe different source snapshots. Historical focused passes
do not establish the final combined dependency/application state.

| Check | Observed result | Retained evidence and scope |
| --- | --- | --- |
| Forwarding profile cohort | **67 passed, 0 failed, 0 skipped** | [Receipt](forwarding-profile-focus/receipt.json), [raw log](forwarding-profile-focus/focused.log): 28 model/store/coordinator, 10 profile-widget, 10 panel, 15 existing forwarding-widget, and 4 opt-in visual cases. |
| Forwarding focused analysis | **No issues found** | [Raw analyzer log](forwarding-profile-focus/analyzer.log); 12 relevant source/test files. The receipt snapshots 13 source/test files used by this focused cohort. |
| Initial agent/application cohort | **121 passed** | [Historical raw log](agent-focus/agent-tests.log), with [focused analysis](agent-focus/agent-analysis.log). This precedes later protocol review fixes. |
| Agent visual/protocol rerun | **24 passed, 0 failed** | [Original receipt](agent-focus/agent-visuals-receipt.json) and [raw log](agent-focus/agent-visuals.log): 3 visual cases plus 21 agent-protocol cases, overlapping the other agent cohort. |
| Channel regression checkpoint | **20 passed** | [Historical raw channel log](channel-focus/ssh-agent-channel.log); the combined source is also covered by the final 813-test terminal cohort. |
| Public-key sequencing and localized errors | **32 passed, 0 failed, 0 skipped** | [Intermediate review receipt](agent-focus/auth-review-receipt.json): 19 public-key packet cases, 11 agent-widget cases, and 2 mount-localization cases. It retains exact commands and observed output tails; that run was not redirected to a complete raw log. |

The forwarding cohort exercises corrupt/future preservation, concurrency,
route isolation, requested port zero, duplicate prevention, cancellation,
late-result cleanup, failed stops, and reconnect behavior. Its panel tests use
the production panel/session/connection objects with gated transport fixtures
to prove that failed authentication, failed shell startup, session replacement,
and delayed profile reads cannot start unauthorized listeners.

Independent review found and corrected an automatic-start race: a competing
refresh could supersede the first refresh, leaving its caller to inspect an
empty shared cache and consume the only automatic attempt. Selection now uses
its own loaded snapshot, with a deterministic two-read regression. Review also
found that disconnect disposed the coordinator while its manager/editor was
still mounted. The retained lease and reverse-transition tests cover saved
editing, deletion, and late action completion after disconnect.

Separate agent review found that PK_OK was not matched to the algorithm/key
actually probed, and a delayed signer could complete after another key attempt
or authentication success. The fix snapshots the probed bytes, validates the
reply, consumes the probe, and checks an authentication-attempt token for both
signatures and errors. A reused identity object cannot authorize an older
attempt. Known `SSHInternalError`/`SSHAuthAbortError` wrappers ending in an
`SshAgentException` now retain localized messages; unrelated errors keep their
existing presentation. These changes received the focused 32-case check above
and passed in the final combined terminal cohort.

## Seven inspected production-widget captures

Both sets use real production widgets, bundled fonts/icons, and simulated
agent/listener availability. The captures establish layout, visible disclosure,
and viewport behavior. They do not certify native sockets, browser execution,
physical devices, or external agent integration.

| Capture | Dimensions | Inspection focus |
| --- | --- | --- |
| [Agent desktop](visuals/agent-desktop.png) | 800×900 | Independently authenticated jump host, final-host forwarding disclosure, and separate opt-in control. |
| [Agent narrow](visuals/agent-narrow.png) | 320×320 | Readable forwarding disclosure and accessible controls in a short viewport. |
| [Agent unavailable](visuals/agent-unavailable-narrow.png) | 320×320 | Missing-agent guidance and available form actions. |
| [Profile manager desktop](visuals/forwarding-profiles-manager-desktop.png) | 900×900 | Exact route, saved profile, Auto-start label, allocated listener port, and profile actions. |
| [Profile editor desktop](visuals/forwarding-profiles-editor-desktop.png) | 900×900 | Name, explicit next-connection Auto-start description, forwarding settings, and Save. |
| [Profile manager narrow](visuals/forwarding-profiles-manager-narrow.png) | 320×320 | Readable saved-listener details and fixed dialog actions with a scrollable body. |
| [Profile editor narrow](visuals/forwarding-profiles-editor-narrow.png) | 320×320 | Readable Auto-start explanation and available Cancel/Save actions. |

All seven outputs were inspected. No overflow or overlapping controls was
observed. Scrolling is expected at 320×320; one image does not show every field
simultaneously. The [explicit source comparison](visual-source-comparison.json)
confirms that all five recorded agent-visual inputs and all 13 recorded
forwarding-profile inputs match acceptance source `9753a980` exactly.

## Live OpenSSH and system-agent boundary

**The final combined live rerun passed 17 tests with two explicit skips and no
failures across three files.** The [receipt](live.json) and [complete log](live.log)
record source `9753a980`, 74.929 seconds, and all 5,511 watched inputs unchanged.
Local, remote and SOCKS5 forwarding each carried an exact 3 MiB binary payload
plus Unicode through the independently verified jump route. Agent tests cover
direct and jumped Ed25519/RSA SHA-512 authentication, host-trust rejection before
signing, refusal, cancellation and disconnect. A real final-server rekey
preserved an exact 512 KiB binary payload plus Unicode through the jump route,
without a new trust prompt or agent signature.

The live runner starts disposable loopback OpenSSH servers and generates
temporary Ed25519 and RSA keys. Agent interoperability cases use real
`SSHSocket` connections and production host-key/authentication handling. The
local agent socket is replaced by a framed in-memory agent-protocol fixture
that signs with the invocation's temporary key. This can establish SSH
algorithm/route/trust behavior, revocation, and rekey interoperability; it does
not establish access to a real `SSH_AUTH_SOCK`, a hardware token, or forwarded
Unix-socket use by a remote program.

A separate opt-in case uses an actual disposable `ssh-agent` and remote
`ssh-add`. The host rejected its Unix-socket prerequisite with **`EPERM` /
`[Errno 1] Operation not permitted`**. The optional interactive SSH PTY case
also requires an sshd allowed to write login records. These boundaries are
explicit skips, not successful native-agent/PTY acceptance.

The [retained earlier live receipt](historical-live/agent-live-attempt-2.json)
and [raw log](historical-live/agent-live-attempt-2.log) are historical failure
evidence: **16 passed, 2 skipped, 1 failed** on the source identified there.
The rekey case reported `Cannot add event while adding a stream`; its fixture
and the related send/transport behavior were subsequently revised. This run
must not be described as a successful final live run. The first rekey test
incorrectly wrote directly to a channel whose stream was already owned by
`SSHSession`; the corrected case uses the production session write/flush API.
That attempt also exposed enqueue-error cleanup in the new bounded send API,
which now has a deterministic regression. The passing final rerun uses the
updated suite and combined source.

## Combined acceptance

| Final check | Status and required record |
| --- | --- |
| Complete terminal regression cohort | **Passed: 813 tests, 2 platform skips, 0 failures across 69 files.** [Native receipt](native.json) records source `9753a980`, 5,511 watched inputs with no changed sources, and 132.006 seconds. The suite includes the new public-key authentication tests. |
| Full selected static analysis | **Passed: 123 files, exit 0.** [Analysis receipt](analysis.json) records source `9753a980`, 5,511 watched inputs, and no changed sources. Focused analysis above is a separate overlapping result. |
| Formatting | **Passed: 123 files, exit 0.** [Format receipt](format.json) records the same source and 5,511 watched inputs, with no changed sources. |
| Live OpenSSH | **Passed: 17 tests, 2 explicit skips, 0 failures across three files.** [Live receipt](live.json) and [log](live.log), source `9753a980`, 5,511 unchanged watched inputs. The system-agent and interactive SSH PTY cases are the two skips. |
| `dartssh2` and managed Office provenance | **Passed at `9753a980`.** [Verification receipt](vendor-verification.json): 96 upstream files, four reproduced runtime patches, and all 2,399 tracked Office entries. The dependency/runtime-manifest hashes are retained. |
| Full optimized application web build | **Passed: standard release O4 and minification, 290.588 seconds.** [Web receipt](web.json), [log](web.log), and [bundle verification](web-bundle-verification.json). Source `9753a980`; all 5,511 watched inputs unchanged. |
| Final source and remote identity | **Passed.** [Source comparison](final-source-verification.json) and [remote audit](final-remote-audit.json): exact accepted inputs, all five phase inventories equal, and all 189 advertised refs contained. |
| Future workflow registration | **Verified locally.** [Entrypoint record](workflow-entrypoints.json): YAML parses, referenced tests exist, native/portable browser lists include the new deterministic suites, and the SSH vendor guard is registered in CI/nightly/release. No Actions run was queried or awaited. |

The [full web resource record](web-resource-run.json) records a 3,072 MB compiler
VM heap cap with unchanged Flutter release arguments, O4 optimization and
minification. The runner took 291.034 seconds including cleanup. All three
pinned SDK executable/snapshot hashes and file modes were restored exactly.
[Complete sampled observations](web-resource-observations.json.gz) preserve the
actual compiler arguments and process memory; [runner output](web-resource-runner.log)
preserves the ordinary validation result. The optional Wasm compatibility probe
was disabled. This is JavaScript release compilation, not browser runtime or
WebAssembly acceptance.

The resulting `main.dart.js` is **29,354,418 bytes**, SHA-256
`b1cdd2dd9cc020382e1bffa6bc7f4714b17b4c5edb7f36e1cb2e0d85ddad1bc0`.
The bundle contains app version `1.3.4+28` and source label `9753a980`.
Preparation remains separately documented by
[the no-mutation preflight](web-resource-preflight.json) and
[restoration checks](web-resource-restoration-check.json), which exercised a
disposable SDK copy after child exit 23 and runner SIGTERM. Those setup checks
are not counted as application tests.

## Evidence relocation and reproducibility

[evidence-copy-manifest.json](evidence-copy-manifest.json) records the original
path, retained path, byte count, and SHA-256 of every copied intermediate file.
The original receipts and raw logs are copied byte-for-byte; commands,
timestamps, source hashes, and original output locations were not rewritten.
This explains why a receipt can still name a workspace/build path while the
corresponding retained file lives below this directory. All seven PNG hashes
were checked against their original receipts during copying.

Source hashes in focused receipts apply to those runs. The visual-source
comparison above establishes the recorded visual inputs' identity with the
accepted source. Earlier protocol-focused runs remain intermediate; the
813-test native cohort and the 17-test live run validate the combined source.
Completed source inventories are preserved as gzip archives; decompression
returns the exact original JSON bytes, and each phase receipt names its archive.

The forwarding command is preserved in its receipt. With the pinned toolchain
active, the same focused check can be run with:

```sh
flutter test --no-pub --timeout 30s \
  --dart-define=SSH_FORWARDING_PROFILE_VISUALS=true \
  test/ssh_forwarding_profiles_test.dart \
  test/ssh_forwarding_profiles_widget_test.dart \
  test/ssh_forwarding_panel_test.dart \
  test/ssh_port_forwarding_widget_test.dart \
  test/ssh_forwarding_profiles_visual_test.dart
```

The complete acceptance driver is
[`tool/run_terminal_validation.py`](../../../tool/run_terminal_validation.py),
with separate `native`, `analysis`, `format`, `live`, and `web` phases and an
explicit evidence directory. The live fixture is
[`tool/run_terminal_live_smoke.py`](../../../tool/run_terminal_live_smoke.py).
The receipts preserve the actual commands. This workspace supplied the pinned
toolchain through `../toolchain/run`; its versions, native compiler probes,
normal build-hook behavior and lockfile checks are retained under `environment/`.
The complete local reproduction sequence is:

```sh
flutter pub get --enforce-lockfile --offline
python3 tool/verify_dartssh2_vendor.py --require-tracked
python3 tool/verify_office_fidelity.py --require-tracked
python3 tool/run_terminal_validation.py native --evidence docs/validation/terminal-agent-profiles
python3 tool/run_terminal_validation.py analysis --evidence docs/validation/terminal-agent-profiles
python3 tool/run_terminal_validation.py format --evidence docs/validation/terminal-agent-profiles
python3 tool/run_terminal_validation.py live --evidence docs/validation/terminal-agent-profiles
python3 docs/validation/terminal-agent-profiles/web-resource-runner.py --run
```

Offline resolution assumes the pinned packages are already cached. The final
web command uses the prepared toolchain layout; its runner also accepts explicit
repository/toolchain locations. The workflow additions register future platform
checks; they do not establish Windows, macOS or Chrome acceptance in this run.

## Remaining parity work and acceptance limits

The agent backend currently supports native Linux/macOS Unix agents and
ordinary Ed25519, RSA SHA-256/SHA-512, and NIST P-256/P-384/P-521 ECDSA identities.
RSA/SHA-1, SSH certificates, FIDO `sk-*` algorithms, and agent extensions are not
implemented. Destination-restricted OpenSSH agent keys that require session
binding therefore remain unsupported. Windows, browser, and mobile agent
backends, external/hardware agents, and packaged/sandboxed macOS need separate
implementation or acceptance work.

Saved forwarding profiles do not establish unattended SSH authentication or
background reconnect. Their Auto-start applies to a newly successful verified
connection; listener ownership, loopback bind choices, and local/remote/SOCKS5
limitations remain those documented in the terminal guide. Port forwarding
still requires a native socket-capable backend.

The major remaining iTerm parity areas include native tmux control mode,
independent terminal windows, automatic process/session restoration, richer
trigger actions and automation, and broader platform integration. Windows
ConPTY, packaged/signed macOS, physical mobile devices, browser runtime, and
external gateway/tmux/Screen deployments retain their own acceptance needs.
Neither this feature increment nor the focused checks above constitutes full
iTerm2 parity.
