# Terminal qualification after incoming agent/profile and native tmux work

The merged terminal source passed **402 selected unit/widget tests**, **17 real
OpenSSH tests**, and **three shell smoke scenarios**. There were no failures in
those final selections. The two live skips are explicit: the optional PTY case
and the real Unix-agent socket case. The passing test total is **419 distinct
tests**; shell scenarios are recorded separately.

Five additional UI/transport/workspace suites were attempted with the complete
production dependency graph. Its unchanged `crisp_catalog` native build hook
requires `cargo`, which was unavailable. Flutter stopped during native-assets
preparation before executing any of those tests. This attempt contributes **zero
test passes**. Neither hooks nor production imports were disabled or replaced.

The gate includes incoming terminal head
`6e11d2d6fda1486dc6968e01137ba7466356398f`, integrated by actual two-parent merge
`de1259080074ca7918122d4790e9255269944b25`. Earlier agent/profile work at
`ce386fd6` is contained by that merge. Source identity, ancestry and the current
byte comparisons are in the [delivery source proof](delivery-source-proof.json).

## Final executed checks

| Selection | Result | Evidence |
| --- | ---: | --- |
| Terminal/session/forwarding/agent/profile/public-key and native tmux core, 29 files | **402 passed; 0 failed; 0 skipped** | [Receipt](receipt.json), [counts by file](core-test-counts.json), [raw JSON-protocol log](terminal-tests.log) |
| Disposable OpenSSH route and forwarding, plus agent authentication/rekey | **17 passed; 0 failed; 2 explicit skips** | [Live receipt](loopback/receipt.json), [counts by file](loopback/live-test-counts.json), [raw log](loopback/terminal-loopback.log) |
| Bash scalar/array prompt hooks and Zsh precmd hook | **3 scenarios passed; 0 failures; 0 skipped shells** | [Shell log](terminal-shell-smoke.log) |
| Tracked vendored `dartssh2` source/provenance guard | Passed: 96 upstream files and four reviewed runtime patches | [Vendor log](dartssh2-vendor.log) |
| Focused locked dependency graph | Passed: all 117 hosted archive hash markers match the enforced lock | [Dependency inputs](dependency-inputs.json), [enforced-lock log](pub-get-offline-enforce.log) |
| Five disjoint full-graph UI/transport/workspace suites | **Blocked before test execution: missing `cargo`** | [Attempt receipt](supplemental/receipt.json), [interpretation](supplemental/interpretation.json), [raw log](supplemental/terminal-supplemental.log) |

The focused cohort retains the previous arrangement, config-import, key-binding,
input-routing, broadcast, session, jump-route, forwarding and trigger checks. It
adds the current agent-channel, agent-route, agent-profile, local-agent protocol,
asynchronous public-key authentication, forwarding-profile and destination
profile tests. These execute the actual production services and vendored SSH
implementation with controlled fixtures.

The incoming native tmux coverage adds protocol decoding, control-client
lifecycle and cancellation, queued-input budgets, profile/arrangement
persistence, and session-option validation. The existing broadcast and session
checks were also rerun on the merged source. The exact test filenames and
per-file counts are retained; neither the earlier 355-pass pre-tmux run nor the
initial partial run is added to the final total.

## Real OpenSSH scope and skips

The live runner creates disposable keys and loopback jump/target OpenSSH
servers, then removes its fixtures. It verifies both server host keys, Unicode
execution through a jump route, altered-key rejection, local/remote/SOCKS
forwarding, half-close and large-response preservation, listener cleanup and
disconnect behavior. The agent cohort covers Ed25519 and RSA SHA-2 signing,
approval before signing, independent jump-hop approval, revocation/cancellation
and data preservation across actual OpenSSH rekey.

Those 11 agent cases use a framed in-memory **local agent protocol fixture**
with the real SSH transport and servers. The separate actual `ssh-agent`
acceptance was requested, but the host rejected Unix-socket creation with
`Operation not permitted`; its skip reason is retained in the raw protocol
log. The optional PTY test was not requested because this fixture does not
establish login-record permissions. Neither skip is counted as a pass.

The final live selection passed on its first run in **60.424 seconds**, after
the unrelated heavy compilation attempt finished. No test timeout, source file,
transport guard or dependency was changed for that run. There were no private
credentials, accounts or external SSH destinations.

## Source and dependency identity

The focused and live gates fingerprint **221 files**, including every selected
test, its transitive local Dart imports and conditional imports, all tracked
`dartssh2` vendor/provenance files, the storage hook, relevant production
manifests and lock, and the smoke/vendor runners. The aggregate stayed:

```text
072ddd78a68e0fd2e3083ed56490b22c9ac65d7cb6052666ff5df1e8dc5abd4f
```

The [source-before map](source-before.json), [source-after map](source-after.json)
and [live final map](loopback/source-after.json) retain individual hashes.
Documentation/checkpoint commits moved HEAD during later work; the actual
qualified inputs and resolved harness inputs remained unchanged. The delivery
proof also compares the supplemental attempt's 6,987 recorded canonical inputs
with current source and checks both executed runner hashes.

The runtime is official Flutter **3.47.8** / Dart **3.13.7**. The focused graph
contains **129 locked dependencies**: 117 hosted, seven local path packages and
five SDK packages, plus the harness root. It uses the actual checked-in
`packages/dartssh2` at 4.1.0, the production `pointycastle` override, genuine
hosted packages, and the actual CrispCloud `lib`/`test` directories through
symlinks. The complete [manifest](pubspec.yaml) and [lock](pubspec.lock) are saved.
Each final gate ran offline `pub get --enforce-lockfile` and verified that
production and harness manifests/locks did not change.

The initial restored graph lacked `uuid`, now imported by the forwarding
dialog. The bounded [harness update](harness-update.json) added only
`uuid` 4.5.1, `fixnum` 1.1.1 and `sprintf` 7.0.0. All three new lock entries
exactly match the production lock; every pre-existing package entry stayed
unchanged. No production dependency constraint was edited.

## Retained incomplete and superseded runs

The [initial attempt](first-pass/receipt.json) recorded 330 passes and four
compilation-loader failures, with unchanged inputs. Two forwarding-widget
failures came from the missing `uuid` entry. The agent-widget and mount
localization suites imported the larger filesystem/archive/backend graph,
which the focused harness did not contain. Their full errors remain in the
[initial raw log](first-pass/terminal-tests.log).

After the bounded dependency repair, the [pre-tmux run](pre-tmux/receipt.json)
passed 355 tests and three shell scenarios. A final incoming-work audit then
found the newer native tmux head. That source was merged before the final
29-suite gate. These historical runs are evidence of their own input versions;
they do not increase the 419-test total.

Once the complete production graph became available, the five omitted current
suites were attempted without stubs:

- `ssh_agent_widget_test.dart`
- `terminal_mount_localization_test.dart`
- `ssh_terminal_transport_test.dart`
- `ssh_tmux_panel_lifecycle_test.dart`
- `tmux_control_workspace_test.dart`

The [full application dependency/build record](../full-app-build/receipt.json)
provides the genuine 275-package graph. Before the supplemental attempt, all
**1,188 isolated application-library files were byte-identical** to canonical
source. The selected tests and their fixture were actual canonical files; local
packages, including the vendored SSH library, retained their production paths.
The attempt ended after **14.443 seconds** at the required missing-Cargo hook,
before any test completion event. All **6,987 canonical input hashes**, the
isolated library and dependency inputs stayed unchanged. Its temporary test
symlink was restored. Full-graph test acceptance is therefore still unverified.

There was no installed `tmux` executable in this workspace, so no live native
tmux-server acceptance was attempted or counted. The focused protocol/client
tests do not substitute for that interoperability check. The
[scope/prerequisite record](exclusions.json) preserves the exact omitted suite
hashes and this limitation. The full compiled native application and real
OS-keychain behavior are outside this terminal gate.

## Reproduction

Recreate the saved official SDK and the sibling Office host package graph
first. The preparation script rebases the saved focused manifest/lock and links
actual source; it does not change production dependencies.

```sh
python3 CrispCloud/docs/validation/zotero-fidelity-20261116/terminal-integration/prepare-harness.py \
  --workspace /absolute/workspace

source /absolute/workspace/zotero-toolchain/env.sh
cd /absolute/workspace/CrispCloud

python3 docs/validation/zotero-fidelity-20261116/terminal-integration/run-checks.py \
  --source /absolute/workspace/CrispCloud \
  --harness /absolute/workspace/zotero-toolchain/crisp-terminal-harness \
  --output /absolute/workspace/terminal-core-replay

python3 docs/validation/zotero-fidelity-20261116/terminal-integration/run-checks.py \
  --source /absolute/workspace/CrispCloud \
  --harness /absolute/workspace/zotero-toolchain/crisp-terminal-harness \
  --output /absolute/workspace/terminal-live-replay \
  --with-loopback --loopback-only --with-unix-agent
```

The live runner requires `sshd`/`ssh-keygen` and requests `ssh-agent`/`ssh-add`
for its optional real-agent case. Keep unrelated heavy qualifiers idle during
the existing bounded large-transfer tests. The core and live phases can be
replayed independently without double-counting their selections.

The [supplemental runner](run-supplemental.py) expects an isolated full production
project with an exact copy of the canonical `lib`, unchanged manifests/lock,
genuine local package paths, and the complete normal dependency graph. Its
`--baseline` argument can use the persisted
[full application source map](../full-app-build/source-before.json). The default
process bound is 150 seconds; it preserves the normal native build hooks.
On this host it failed before tests because `cargo` was unavailable.

No GitHub Actions were queried, polled, awaited or rerun for any phase.
