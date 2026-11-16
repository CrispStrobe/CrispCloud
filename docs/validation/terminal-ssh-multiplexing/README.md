# Explicit SSH connection sharing

This continuation extends `codex/terminal-screen-workspace`, draft PR #160,
with independent shell tabs and panes on one explicitly selected, already
verified SSH route. Forwarding and permitted agent access belong to that route
until its last owner closes. The complete application source accepted below is
**`2ca566a3a386b5876274d36ff7d93ea21c93fa80`**.

[User guide](../../terminal.md#share-an-existing-ssh-connection) ·
[Feature coverage](../../terminal-parity.md) ·
[Production-widget captures](screenshots/README.md)

## Implemented behavior

On a connected SSH terminal, **Terminal layout** offers **New SSH shell**,
**Split SSH side by side**, and **Split SSH top and bottom**. A new logical
session opens a plain shell on the selected connection without another login,
TCP/gateway connection or jump-host authentication sequence. Starting from a
native tmux workspace or ordinary tmux/Screen attachment also opens a plain
shell. Existing ordinary new-tab and split actions keep their local-shell
behavior.

Each shell owns its channel, input, output, emulator, geometry, exit status and
broadcast identity. Credential-free destination metadata and font size are
copied; secrets, multiplexer launch options and broadcast membership are not.
Sharing never chooses a route merely because a host name or saved profile
matches. Up to eight logical sessions share each route, and the application
still limits distinct routes, including pending authentication, to five.

The shared-route badge reports its logical owners. Closing one shell closes
its channel and owned commands while sibling channels remain usable. The last
owner closes the authenticated route, listeners and permitted agent access.
Activity from any shell or forwarded connection updates the route's 30-minute
idle clock. Transport failure and global disconnect revoke all logical owners.
The new actions and ownership/limit messages cover all eight existing
non-English locales.

## Correctness established during review

- **Pending-open ownership:** reservation occurs before asynchronous shell
  creation. Closing the source cannot revoke a reserved sibling. Canceling,
  replacing or disposing the target releases the reservation promptly, even
  while the server has not answered. Late channels are closed. Opening
  descriptors have one claimant and one factory use; stale menus cannot use a
  replacement connection. Failed cleanup remains owned and retryable.
- **Complete channel cleanup:** the SSH library's ordinary session close can
  leave a quiet output side open. Logical-session teardown now destroys its
  full SSH channel without closing the transport retained by siblings. Real
  channel-controller regressions cover explicit close, output cancellation,
  commands, native control, replacement and late completion.
- **Bounded unanswered work:** new terminal requests have a 32-slot admission
  budget. Pending requests retain their slots until the peer answers. The
  client also exposes its retained-channel count, including locally closed
  entries awaiting peer acknowledgement. Other retained channel types count
  conservatively when admitting a new terminal request. An actual SSH client
  packet-dispatch test fills the table with one live keeper and 31 canceled
  commands, verifies rejection before another protocol open, keeps the keeper
  usable, and frees exactly one slot on peer CLOSE.
- **Final-output publication:** a transport can close in the same event turn
  that a channel finishes opening. Ownership now covers pending and
  materialized-but-unpublished channels. Queued final shell/command/control
  output and exit status drain without granting fresh input authority. A
  completed command cannot prematurely revoke another pending command owned
  by the same logical session.
- **Shared forwarding profiles:** coordinators use one runtime per exact
  forwarding manager. Duplicate starts coalesce; automatic startup can hand
  off after its initiating terminal closes; a joined manual start retains its
  authority. Stop, edit and delete still own pending cleanup after panels
  dispose. Late results cannot recreate stopped or deleted listeners. The
  focused forwarding cohort passes 54 tests, including 16 new regressions.

The final cleanup cohort passes 14 tests. The earlier two-failure publication
reproduction is retained in `focused/shared-channel-publication-race.log`.
Other focused executions and fixture-development attempts are preserved under
`focused/`; their overlapping counts are not added to complete acceptance.

## Recent repository work integrated

The initial fresh fetch contained **38 branch heads and 151 PR heads**, all
189 already actual ancestors of starting checkpoint `042a24e7`. The exact
[initial inventory](integration.json) was saved before implementation.

A later independent snapshot completed at **08:46:21 UTC on 16 November 2026**
and found **40 branch heads and 153 PR heads**. New main `c7463402` brought in
PRs #162/#163 with ODS whole-number, decimal, date and text-length validation.
Integration checkpoint `2ca566a3` includes all **193 captured references as
actual ancestors**, including the original PR heads whose trees exactly match
their squash commits. The final fresh cutoff at **08:59:14 UTC** still contains
those 193 refs, all actual ancestors of `951b2450`, with no new incoming heads.
[Complete incoming audit](incoming-audit/README.md) ·
[Final remote cutoff](final-cutoff/README.md).

The host merge's only conflict was the canonical Office source pin. The
published Quds commit
[`4235e690`](https://github.com/CrispStrobe/quds_office_suite/commit/4235e690602195cc504438a6b937972c71f1ad39)
combines the existing Zotero pin `428679a3` with ODS pin `4ffdf113` on
`codex/terminal-sharing-office-20261116`. Its content delta is exactly the four
incoming ODS runtime/test files. All **2,409 managed Office hashes and index
modes** pass: 552 Quds entries match that canonical commit's blobs and modes,
and 1,857 separately pinned legacy-parser entries remain unchanged. A
pre-existing executable bit on `pdf_canvas.dart` is corrected to the canonical
mode without changing its bytes.

## Local acceptance on the combined source

The normal production graph uses **Flutter 3.47.8 / Dart 3.13.7**, the enforced
lockfile and all normal native build hooks. No dependency constraints, feature
flags or native hooks were weakened for these runs.

| Check | Result and evidence |
| --- | --- |
| Complete terminal cohort | **980 passed, 2 platform skips, 0 failures across 81 files**; [receipt](native.json), [log](native.log.gz) |
| Static analysis and formatting | **153 application/test Dart files clean**; [analysis](analysis.json), [format](format.json); the four patched SSH runtime files also pass their separate vendor analysis |
| Actual loopback OpenSSH | **22 passed, 3 explicit environment skips, 0 failures across four files**; [receipt](live.json), [log](live.log.gz) |
| Incoming Office regression cohort | **116 passed, 0 skips, 0 failures across three files**; [targeted acceptance](incoming-office-tests/README.md) |
| Production-widget inspection | **Five** actual desktop 1180×700 and compact 320×320 PNGs inspected by the implementation and root reviewers; synthetic transport and font limitations are recorded in the [visual receipt](screenshots/review.json) |
| Vendor provenance | All **2,409 Office entries**, **96 original SSH files and four reviewed patched runtime files** verified; the SSH patch reproduces exact pinned outputs |
| Workflow registration | **33 YAMLs** parse, **229 test references** resolve in their declared working directories, and all six new deterministic suites occur in the three portable/native workflow cohorts; [local receipt](workflow-registration.json) |
| Full optimized web release | **Passed** with standard O4/minification in **236.500 seconds** and a 4,096 MB compiler heap; [receipt](web.json), [resource/restoration proof](web-resource-run.json) |

Actual shared-connection tests use a verified jump route with **one outer TCP
transport and two authenticated hop clients**. Concurrent sessions report the
same remote `SSH_CONNECTION` tuple. Canceling an owned command leaves a sibling
usable. Local, remote and SOCKS5 listeners each transfer an exact **3 MiB binary
payload plus Unicode after the source logical session closes**; the final owner
closes their listeners and both clients. Existing trust, signing refusal,
cancellation, revocation and actual rekey tests remain in the live cohort.
Rekey preserves an exact 512 KiB binary payload plus Unicode.

The three live skips are the actual Unix-agent case, because this host denies
Unix sockets, and the two optional SSH PTY cases, because the fixture sshd cannot
write the required login records. Actual local Linux PTYs pass in the terminal
cohort. A channel-close assertion proves local/protocol cleanup; it does not
independently establish remote operating-system process termination.

The targeted Office run preserves every upstream assertion and fixture byte.
Reversible test-only adapters replace `package:test` with `flutter_test` and
prefix two fixture paths so the original engine tests run through the unchanged
application dependency graph. The root ODS editor save/cancel workflow runs
directly. This is targeted incoming-change acceptance, not a full Office-suite
qualification.

## Reproduction and source identity

Run from the application root with the prepared pinned toolchain:

```sh
../toolchain/run python3 tool/run_terminal_validation.py native --evidence docs/validation/terminal-ssh-multiplexing
../toolchain/run python3 tool/run_terminal_validation.py analysis --evidence docs/validation/terminal-ssh-multiplexing
../toolchain/run python3 tool/run_terminal_validation.py format --evidence docs/validation/terminal-ssh-multiplexing
../toolchain/run python3 tool/run_terminal_validation.py live --evidence docs/validation/terminal-ssh-multiplexing
python3 tool/verify_office_fidelity.py --require-tracked
python3 tool/verify_dartssh2_vendor.py --require-tracked
```

The standalone web resource runner and launcher are reused from
`../terminal-tmux-control/`. Their preflight verifies the pinned SDK and a tiny
O4/minified probe before the full build. The build uses the ordinary production
O4/minification settings with a compiler-only **4,096 MB heap cap**, and restores
the exact original SDK executable, snapshot hashes and modes. Its SDK use is
exclusive and follows completion of the other Flutter/Dart runs.

Source inventories and large logs are deterministically gzip-compressed. The
[pre-web proof](pre-web-source-verification.json) ties the four completed phases,
the targeted Office run and all **5,544 watched files** to accepted Git source
`2ca566a3`, including exact current bytes and Git modes. The [final source proof](final-source-verification.json) verifies all five
acceptance inventories, the targeted Office inputs, the produced JavaScript
bundle and restored SDK identities. The release embeds `951b2450`, whose runtime
inputs are identical to accepted source `2ca566a3`; later commits contain
evidence and documentation only. Recheck a delivered checkout without changing
its receipt using `python3 docs/validation/terminal-ssh-multiplexing/verify-final-source.py --check-only`. Visual packaging hashes match the delivered UI sources and original
images; the visual receipt explicitly distinguishes that packaging snapshot
from execution-time whole-application acceptance.

The earlier full passing run at `ea560e8c`, before the incoming Office merge,
is retained under [pre-integration](pre-integration/README.md). It is not added
to the final acceptance counts. Environment restoration records preserve the
322 verified hosted archives, compiler identities and original production
manifest hashes. [Environment receipt](environment/environment-current.json).

## Incremental remote preservation

| Checkpoint | Preserved work |
| --- | --- |
| `743801e2` | Initial complete remote-ref audit |
| `688c4011` | Shared route service, independent shells, UI and translations |
| `050c326f` | Cancelable pending opens and real OpenSSH sharing regressions |
| `ea560e8c` | Channel cleanup/bounds, output publication, forwarding coordination and production-widget captures |
| `01e231b5` | First complete local acceptance before incoming Office integration |
| `2ca566a3` | New main and original PR #162/#163 histories, combined canonical source pin |
| `951b2450` | Complete post-integration terminal/OpenSSH/Office acceptance and provenance |
| Final evidence checkpoint | Passing O4 web release, exact source/SDK verification, final remote cutoff and completed documentation |

Every application checkpoint uses the connected Git data API, verifies the
exact staged tree, and advances the existing branch only if its expected old
head still matches. Checkpoints carry `[skip ci]`. **No GitHub Actions were
queried, awaited or rerun.** The final evidence checkpoint preserves build results, source identity and
documentation. This continuation saves eight application checkpoints and the
separate canonical Quds combination commit.

## Remaining scope and qualification

Sharing is explicit and lasts while at least one owner retains the authenticated
route. There is no idle master after the last owner closes, automatic reconnect,
cross-process pooling, or recovery of shared ownership/processes after restart.
Saved arrangements retain independent credential-free destinations. Use tmux or
Screen for remote processes that must survive attachment lifetimes.

The new work does not establish browser-runtime, packaged macOS/Windows,
physical-mobile, external-gateway or actual Unix-agent acceptance. Existing
native tmux real-daemon qualification remains blocked by this host's Unix-socket
policy; its separate protocol/widget results remain distinct from a successful
real tmux-server run. Full iTerm2 parity remains unfinished, including independent
OS windows, automatic session restoration, broader persistent connection
management, richer trigger/coprocess automation and wider platform integration.
