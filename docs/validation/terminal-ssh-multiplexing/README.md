# Explicit SSH connection sharing

This continuation extends `codex/terminal-screen-workspace`, draft PR #160,
with independent shell tabs and panes on one explicitly selected, already
verified SSH route. Every logical session owns its own channels and terminal
state. Forwarding and permitted agent access belong to the route until its
last owner is released. See [the user guide](../../terminal.md#share-an-existing-ssh-connection).

## Integration and incremental preservation

The initial complete fetch contains **38 branch heads and 151 PR heads**.
All 189 are actual ancestors of starting checkpoint `042a24e7`; no missing
incoming source needed merging. [integration.json](integration.json) retains
each ref and SHA. The initial audit is saved as `743801e2`; the first source,
translations and UI regression checkpoint is `688c4011`.

Remote checkpoints use the connected Git data API, verify the exact staged Git
tree and update the existing branch only if its previous head still matches.
They carry `[skip ci]`. **No GitHub Actions are queried, awaited or rerun.**

## Development verification

The focused service suite currently passes **25 tests**; the new real-loopback
suite passes **five tests with one explicit optional-PTY skip**. These are
development checks; final acceptance will record a frozen source inventory and
the complete terminal cohort separately.

Real loopback checks exercise a verified jump route with one outer TCP transport
and exactly two authenticated hop clients. Concurrent logical sessions report
the same remote `SSH_CONNECTION` tuple. Canceling one command leaves the sibling
usable. Local, remote and SOCKS5 forwards each transfer an exact **3 MiB binary
payload plus Unicode** after the source logical session closes, and close when
the final owner releases the route. The optional SSH PTY case requires an sshd
permitted to write login records and is explicitly skipped in this environment.

Focused logs and retained fixture-development failures are under `focused/`.
The earlier 90-test transport/jump/agent/discovery check and 20-test UI/backend
check are diagnostic subsets and must not be added to the final cohort total.

## Environment

The exact production graph resolves with `flutter pub get --enforce-lockfile
--offline`, using **Flutter 3.47.8 / Dart 3.13.7** and unchanged manifests and
lockfile. All normal native hooks compile. The environment prerequisite passed
six actual Linux PTY tests with one Windows-only skip.
[Environment identities and restoration](environment/RESTORATION.md) and
[the machine-readable receipt](environment/environment-current.json) preserve
SDK hashes, 322 verified hosted archives, native compiler identities, production
manifest hashes and the explicit socket limitations. Unix sockets remain denied;
ordinary TCP loopback is available. No policy workaround was used.

## Scope

The workflow provides live authenticated SSH transport reuse, with up to eight
logical sessions per route and five distinct routes including handshakes.
It does not retain a master connection after its last owner closes, reconnect
automatically, preserve a process across restart, or share connections across
application processes. Native tmux sharing opens an independent plain shell;
its established tmux-server qualification limitations remain separate.

Browser runtime, packaged macOS/Windows, physical mobile devices, external
gateways, actual Unix agents and live tmux daemons require their own acceptance.
The local protocol/widget and Linux/OpenSSH results do not establish those
platform outcomes.
