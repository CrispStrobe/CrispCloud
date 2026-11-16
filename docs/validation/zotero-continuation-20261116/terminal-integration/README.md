# Terminal qualification after the final incoming reconciliation

The reconciled terminal source passed **226 selected core tests**, **six real
loopback SSH tests**, and **three shell smoke scenarios**. The core selection
had no skips. One existing optional real PTY test remained explicitly skipped.
The final staged [receipt](receipt.json) reports `qualified: true` and counts
**232 distinct passing tests**; overlapping diagnostic runs are not added.

This qualifies the terminal work discovered at the final incoming-work cutoff
of **2026-11-16 05:17:13 UTC**: draft PR #160 and the pinned branch head
`49d63f78d0b854ba76289dba69fdb6584f8a1260`. The remote integration merge
`d916a841c54ddcca8f6327e45939c4372ba1d3a9` preserves both parents. Its complete
tree matches the original local merge. The complete incoming ref accounting is
in [final-integration.json](../final-integration.json).

## Executed checks

| Selection | Result | Evidence |
| --- | ---: | --- |
| Prior nine-suite terminal integration selection | 124 passed | [Core log](terminal-tests.log) |
| Terminal session lifecycle | 14 passed | [Counts by file](core-test-counts.json) |
| Six new forwarding/trigger model, service, session and dialog suites | 88 passed | [Core log](terminal-tests.log) |
| Real OpenSSH route and forwarding through disposable loopback jump/target servers | 6 passed; optional PTY case skipped | [Final loopback log](final-loopback/terminal-loopback.log) |
| Bash 5.2 scalar/array prompt hooks and Zsh 5.9 precmd hook | 3 passed; no skips | [Shell log](terminal-shell-smoke.log) |
| Genuine locked Pub graph, including all 115 hosted archive hash markers | Passed | [Dependency inputs](dependency-inputs.json), [enforced-lock log](pub-get-offline-enforce.log) |

The six incoming suites cover local/remote/SOCKS forwarding, resource limits,
timeouts and cancellation, late channel/listener ownership, connection cleanup,
dialog behavior, bounded trigger processing, trigger persistence and session
integration. The older selection checks layouts, saved arrangements, OpenSSH
config import, key bindings, input routing, broadcast and mocked jump transport.

The real loopback tests verify both host keys, reject an altered target key,
execute Unicode through a jump route, preserve binary responses after request
half-close for local/remote/SOCKS forwarding, stop listeners, and close active
connections on disconnect. The payload exceeds the SSH library's initial
2 MiB channel window. All servers, client keys and trust records are disposable;
the fixture connects only to loopback and cleans up its daemons. No private
account, credential or external SSH destination is used.

## Retained first-pass timeout and diagnostic

The first loopback selection had five passes, one optional PTY skip, and one
failure: the SOCKS large-payload case exceeded its unchanged **20-second**
response timeout. That run occurred from approximately **05:24:38 to 05:25:46
UTC**, while the separate Office and host qualifiers were running. Their
concurrent load also slowed other local qualification work.

After those gates finished, the exact unchanged SOCKS case passed on one
diagnostic retry, and the full loopback selection then passed in **51.641
seconds**. Runtime contention is the supported explanation; this was not an
isolated measurement proving a causal mechanism. No production source, test
source, timeout, dependency or guard was changed to obtain the final result.

The failure remains in [first-pass/receipt.json](first-pass/receipt.json) and
[its raw log](first-pass/terminal-loopback.log). The single diagnostic has its
own [receipt](diagnostic-socks.json) and [log](diagnostic-socks.log). The final
full loopback [receipt](final-loopback/receipt.json) and raw log are separate.
Only the final six loopback passes contribute to the 232-test total. The
already-passing core and shell selections were not repeated.

## Source and dependency evidence

The gate fingerprints **93 actual source/test/input files**, including the
selected tests, their transitive local Dart imports and conditional imports,
the local storage build hook and relevant manifests, and both smoke runners.
The aggregate SHA-256 remained
`c52da77dc58e4aca5b6a56a3210b6177e8874098b84467c09df42f9e818b2549`
through every stage. The [first source snapshot](source-before.json) and
[final snapshot](final-loopback/source-after.json) contain the individual hashes.
Unrelated checkpoint commits moved HEAD, but all recorded terminal bytes and
resolved dependency inputs stayed identical. Office vendor qualification is
recorded separately.

The official runtime is Flutter **3.47.8** and Dart **3.13.7**. The restored
focused graph contains **126 locked dependencies** (115 hosted, six local path
packages and five SDK packages), plus the harness root package. It retains the
production `pointycastle: ^4.0.0` override, `dartssh2` **4.1.0**, `xterm2`
**5.4.0** and `web_socket_channel` **3.0.3**. The saved prior terminal manifest
and lock were changed only by rebasing absolute workspace paths. Genuine
network Pub resolution completed; offline `--enforce-lockfile` then passed.

The harness uses the actual CrispCloud `lib` and `test` directories through
symlinks and the supported Dart SSH storage path. Optional Rust bridge flags
remain unset. No library, build hook or production dependency constraint was
replaced or relaxed. [pubspec.yaml](pubspec.yaml) and [pubspec.lock](pubspec.lock)
are the complete restored inputs. The stage receipts retain the resolved
package configuration, SDK artifact hashes, commands, exit codes and log hashes.

## Reproduction

Place the Quds and CrispCloud checkouts as sibling directories named
`quds_office_suite` and `CrispCloud`. Reconstruct the saved host package graph
using Quds' continuation setup scripts and provision its recorded official SDK.
The terminal preparation script expects that host graph and only rebases paths:

```sh
python3 quds_office_suite/docs/validation/zotero-continuation-20261116/setup/reconstruct-harnesses.py \
  --workspace /absolute/workspace \
  --toolchain /absolute/workspace/zotero-toolchain

python3 CrispCloud/docs/validation/zotero-continuation-20261116/terminal-integration/prepare-harness.py \
  --workspace /absolute/workspace

source /absolute/workspace/zotero-toolchain/env.sh
cd /absolute/workspace/zotero-toolchain/crisp-terminal-harness
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
  "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" pub get --enforce-lockfile

cd /absolute/workspace/CrispCloud
python3 docs/validation/zotero-continuation-20261116/terminal-integration/run-checks.py \
  --source /absolute/workspace/CrispCloud \
  --harness /absolute/workspace/zotero-toolchain/crisp-terminal-harness \
  --output /absolute/workspace/terminal-replay \
  --with-loopback
```

Provide writable `PUB_CACHE` and `TMPDIR`. Real loopback checks also require
`sshd` and `ssh-keygen`; omitting `--with-loopback` runs only core and shell
checks. The runner uses the direct Dart binary and official Flutter snapshot.
Its `--loopback-only --with-loopback` selection reproduces the final separate
loopback gate without repeating the core tests. Avoid running unrelated heavy
qualifiers concurrently with these deliberately bounded large-transfer checks.

## Qualification boundaries

The optional real PTY case requires `--with-pty` and an sshd environment allowed
to write login records; it was visibly skipped here. The full native app and
full terminal panel/backend dependency graph were not built by this focused
harness. The saved production test-tag configuration was not copied into the
isolated harness, so the raw live log contains a tag-declaration warning; the
existing live-test response bounds stayed unchanged. No GitHub Actions were
queried, awaited, rerun or used as an acceptance gate.
