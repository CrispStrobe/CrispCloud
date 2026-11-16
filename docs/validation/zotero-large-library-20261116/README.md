# CrispCloud Zotero large-library integration

## Qualified source

App implementation: `07c54fe650d5dbcba664cedd8e5324176f5c7ada` on
`codex/zotero-optimization-20261116`, continuing PR #167. Its Office manifest pins
canonical Quds `98079023680a549cb126752c1d4f539749f46938`. Subsequent commits in
this delivery add validation records only.

## User-visible changes

Basic citation refresh accepts up to **1,000 distinct linked sources**, fetched
in sequential batches of at most 50 per durable library scope. For one library,
51 sources need two requests, 101 need three and 1,000 need twenty. Repeated
citations share metadata; equal keys in separate libraries retain separate
identities. Every response is verified and all batches apply in one undo step.
Missing CSL, server errors, API backoff, a changed editor target or a closed
dialog prevent partial document changes and further requests. The 1,001-source
case is rejected before fetching metadata.

Collection pages now contain one entry per key. Renamed and repeated entries
update in place, preserving selection. A late collection response cannot enter
a different library or a closed dialog. Formatted bibliography output retains
its existing 50-source single-request boundary, so global CSL order and
disambiguation are not split across separate renderings.

The existing host transport, credentials and native citing behavior are
retained. The standalone legacy parser remains pinned at
`4895712158127b2fc930d796e17035c3ca0dac62`.

## Current local qualification

| Cohort | Passed |
| --- | ---: |
| Actual host Zotero services, transport, credentials, targets and ribbon | 39 |
| Incoming terminal sessions, tmux client and control protocol | 70 |
| **Companion total** | **109** |
| Canonical Quds editor and engine/ODS cohorts | 348 |
| **Current test executions across both repositories** | **457** |

All **2,412 managed Office files** pass the normal/source and tracked-index
verification against the canonical source. The actual host harness points to
CrispCloud's vendored packages. Strict analysis of the five incoming terminal
source/test targets is clean. The canonical dialog, widget tests and incoming
ODS targets separately pass strict analysis and declared-language formatting.

[receipt.json](receipt.json) records exact commands, test lists, hashes, graph
inputs and source pins. [logs/](logs/) retains final output. Earlier smoke tests
and overlapping development runs are excluded from these counts. Flutter
3.47.8 / Dart 3.13.7 and the original enforced harness locks were used; production
dependency declarations were not edited.

## Incoming work and persistence

The [ref inventory](incoming-refs.json) accounts for **46 branch heads and 158
advertised PR heads**. The working branch preserves main through #168, existing
Zotero #161/#167 and terminal recovery #160. Later terminal changes through
`71256dbf` are also included: correct resize callback geometry and one hard
deadline per active pane capture, without consuming queued panes' timeout
budgets. Their complete session/client/protocol suites were run locally here.

Canonical ODS tab colors (#57) and named expressions (#58) are both vendored.
The latter landed during this pass and was reconciled before final testing.
Squash-equivalent source heads are recorded without duplicating their code.

Remote checkpoints include reconciliation `9cce5411` and the integrated source
`07c54fe6`. Checkpoint commits use `[skip ci]`; GitHub Actions were not queried,
awaited or rerun.

## Reproduction and scope

Use Quds' existing
`docs/validation/zotero-continuation-20261116/setup/bootstrap-local-tests.sh`
with the workspace containing both checkouts, then source
`zotero-toolchain/env.sh`. The host Zotero harness is `crisp-host-harness`.
The separate terminal graph is restored from this repository's
`docs/validation/zotero-fidelity-20261116/terminal-integration/` manifest and
lock, rebasing workspace paths only. It uses the actual vendored `dartssh2`
source and xterm2 5.4.0. Exact reconstruction and dependency hashes are retained
in [terminal-setup.json](terminal-setup.json).

Run the exact commands in the receipt from those harnesses. This pass does not
claim a full application build, a live Zotero account session, live SSH/tmux
daemon acceptance, Word/LibreOffice interoperability or private keychain
acceptance. The local tests exercise real production code with synthetic
fixtures and mocked network/protocol responses.
