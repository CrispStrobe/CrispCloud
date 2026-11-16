# Zotero capabilities in CrispCloud — 16 November 2026

The combined CrispCloud implementation at
[`27f001d60777d27f412d9984b62dbdb05019b9eb`](https://github.com/CrispStrobe/CrispCloud/commit/27f001d60777d27f412d9984b62dbdb05019b9eb)
passed **41 actual-host tests and 28 Python sync/verifier tests** after current
main and the qualified Quds implementation were combined. Its exact Git tree
is `ab5fe16a2289ea67ae4d4c72a542f233d178305f`.

The Office manifest pins canonical Quds
[`8e017e8c148517fea61f8d55eaafc7f070b82bba`](https://github.com/CrispStrobe/quds_office_suite/commit/8e017e8c148517fea61f8d55eaafc7f070b82bba),
tree `17eecf8b8c8558c78dbbefe9ffc9b1249e2455cf`, which separately passed
**825 distinct canonical tests**. The three disjoint final cohorts therefore
contain **894 distinct tests**. Earlier development runs, historical evidence,
and expected-failure controls are excluded from this total.

Work is saved incrementally on `codex/zotero-capabilities-20261116` in both
repositories. Later delivery commits contain documentation and evidence;
the immutable implementation pins above identify the tested production code.
Checkpoint messages include `[skip ci]`. **No GitHub Actions jobs, workflow
runs, check statuses or CI status checks were queried, awaited or rerun.**

## Three shared Zotero improvements

**Linked URI aliases contribute one embedded source.** The shared source
selection joins complete alias sets before choosing CSL snapshots, including
late and transitive bridges. Citations with aliases `[A]`, `[B]`, and `[A, B]`
now contribute one bibliography source. Bridges without embedded CSL still
establish identity; the first available snapshot is retained. Unrelated
personal, group, local-profile, opaque-URI and offline identities remain
separate. Citation fields, locators and unknown metadata are preserved.
The implementation is in
[`WordZotero.distinctEmbeddedItems`](https://github.com/CrispStrobe/quds_office_suite/blob/8e017e8c148517fea61f8d55eaafc7f070b82bba/packages/quds_office_engine/lib/src/word/model/word_zotero.dart),
shared by embedded CSL export and bibliography formatting.

**The document tab reuses its field list.** Opening the real widget on the
canonical 1,000-citation fixture performs one complete field scan instead of
four. Action availability uses the already collected fields, including the
existing distinction between bibliography-only and citation-bearing
documents. This avoids repeated traversal within a build without adding a
persistent document cache. It is a measured scan-count improvement; it is
not an end-to-end latency claim. The implementation is in the
[shared dialog](https://github.com/CrispStrobe/quds_office_suite/blob/8e017e8c148517fea61f8d55eaafc7f070b82bba/packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart).

**Online server pauses survive client replacement.** An online session owns
the shared backoff deadline, so reconnecting, changing credentials or public
library, forgetting credentials, or reopening the dialog within that session
does not bypass a server pause. Older responses cannot shorten a longer
deadline. Local desktop clients retain independent state. This adds no
persisted credentials, automatic retries or timers. The implementation spans
the shared dialog and
[`ZoteroBackoffState`](https://github.com/CrispStrobe/quds_office_suite/blob/8e017e8c148517fea61f8d55eaafc7f070b82bba/packages/quds_office_engine/lib/src/zotero/zotero_client.dart).

The [canonical report and isolated behavioral controls](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-capabilities-20261116/docs/validation/zotero-capabilities-20261116/README.md)
record the before/after fixtures, source identities and limits for these
changes. Existing verified refreshes of up to 1,000 distinct linked sources,
using batches of at most 50 per library, remain integrated alongside native
citing, saved searches, rich citation fields, local profiles, undo and stale
document guards.

## Incoming work and guarded source delivery

The [incoming-work audit](incoming-work.md) accounts for **208 observed
CrispCloud refs: 48 branch heads and 160 PR heads**. Every observed incoming
head is an ancestor of the recorded integration. Its
[machine-readable inventory](incoming-refs.json) records the exact observed
refs, cutoff and ancestry evidence. The original inventory and narrative
remain preserved separately; these counts do not imply that remote branches
stopped changing after the observation.

Current main
[`f7353bf5cdbdd1a3e1b5d02615b051eaa0dae644`](https://github.com/CrispStrobe/CrispCloud/commit/f7353bf5cdbdd1a3e1b5d02615b051eaa0dae644)
is retained, including persistent keychain lock controls and direct pane
favorites. Its
[earlier acceptance report](../keychain-favorites-settings-20261116/README.md)
retains its original source and platform scope. Those keychain/native results
were not rerun or added to this Zotero qualification count.

Canonical Quds includes the latest observed ODS hyperlink and proofing work,
plus the reviewed caret fixes for authored soft hyphens and generated
hyphens. Its
[separate incoming audit](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-capabilities-20261116/docs/validation/zotero-capabilities-20261116/incoming-work.md)
accounts for 113 observed Quds/upstream refs, including explicit behavioral
supersession and alternate-proofing dispositions. It does not claim every
change on the competing proofing architecture was merged.

The host vendor guards verify **2,468 managed Office files** against the exact
Quds pin. The independent legacy parser retains
`4895712158127b2fc930d796e17035c3ca0dac62`. The
[immutable host manifest](https://github.com/CrispStrobe/CrispCloud/blob/27f001d60777d27f412d9984b62dbdb05019b9eb/tool/office_fidelity_manifest.json)
records both source boundaries.

The sync boundary now includes the engine's `third_party/hyphenation` and
`third_party/proofing` source/data/notice directories. Tests cover boundary
exclusions, idempotence, and refusal to overwrite a changed managed notice.
The host bundles and registers exactly the three production German data
notices, including a standalone hyphenation license extracted from the
complete source header. Actual-bundle tests verify byte equality and license
registry exposure. The optional Harper backend remains outside CrispCloud's
runtime dependencies in this increment.

## Final qualification and integrity

| Distinct final cohort | Passed |
| --- | ---: |
| Canonical Quds engine/editor, Zotero, ODS, proofing, layout and caret cases | 825 |
| Actual CrispCloud Zotero host cases | 39 |
| Actual bundled German notice cases | 2 |
| Python Office/parser sync and verification cases | 28 |
| **Combined distinct total** | **894** |

Strict analysis with `--fatal-infos` passed for **15 host-context targets**:
eight actual host sources/tests and seven vendored Zotero/caret/painter
sources/tests. Formatting checked the same 15 files with zero changes.
The canonical report separately records its 12 strict-analysis targets; those
lists need not be disjoint and are not combined into a unique target count.

The accepted host run verified **3,685 production source/asset/configuration
inputs unchanged** and **5,827 resolved dependency library/configuration
inputs unchanged**, across **96 genuine packages**. The harness declarations
and locks remained fixed; no `pub get` was rerun. Its actual library links
resolve to the real host sources. The temporary host analyzer configuration
was restored, and canonical package configuration was untouched. Runtime was
Flutter 3.47.8 / Dart 3.13.7.

The run began and ended at local commit
`84955ca66662f7fdf638487dd4691e5c2fa018d0`. Its tree exactly matches the
published `27f001d6` implementation. The runner checked this relationship and
tracked input equality before execution. Only the continuation branch was
fetched to obtain the published object; this verification did not perform
another incoming-ref refresh.

The [final host report](final-host/README.md),
[execution receipt](final-host/receipt.json),
[original artifact inventory](final-host/artifact-inventory.json), and
[archive inventory](final-host/archive-inventory.json) preserve exact
commands, exit codes, logs, identities and hashes. The receipt's SHA-256 is
`9fadc14f01ecbb99d6b379f54211108a7d32115175c0088fefbc55e3d8ca3c16`.
Earlier host qualification remains unchanged under
[pre-concurrent-host](pre-concurrent-host/README.md); its test counts are not
added again.

## Evidence layout and reproduction

`final-host/` copies the accepted runner, README, receipt, package
configuration, harness asset record, provenance, and every command log
unchanged. The four large source/dependency maps are stored losslessly as
`.json.gz`; their original uncompressed hashes remain in both inventories.
Run `gzip -dk *.json.gz` within that directory to restore the exact original
JSON filenames and bytes referenced in the receipt. The archive inventory
also records compressed-file hashes.

For reproduction, restore immutable checkouts named `CrispCloud` and
`quds_office_suite` beside `zotero-toolchain/`. Restore the genuine pinned SDK
and enforced harness locks using the Quds bootstrap documented in the
[final host report](final-host/README.md). Apply only the three production
notice asset entries and real-source symlinks recorded in
[harness-assets.json](final-host/harness-assets.json). Place the runner and
restored evidence under `zotero-toolchain/expanded-host-qualification` if
recreating the recorded layout; choose a fresh output directory for each run.

```sh
source /absolute/workspace/zotero-toolchain/env.sh
python3 /absolute/workspace/zotero-toolchain/expanded-host-qualification/run-expanded-host.py \
  --repo /absolute/workspace/CrispCloud \
  --harness /absolute/workspace/zotero-toolchain/crisp-host-harness \
  --quds-source /absolute/workspace/quds_office_suite \
  --source-commit 27f001d60777d27f412d9984b62dbdb05019b9eb \
  --quds-commit 8e017e8c148517fea61f8d55eaafc7f070b82bba \
  --output /absolute/workspace/new-host-qualification
```

The runner requires complete commit SHAs, checks the published tree and
canonical pin, rejects changed tracked qualification inputs, and refuses to
overwrite existing receipts or input snapshots. It restores the host
analyzer configuration after either success or failure.

## Practical limits

This is focused local qualification through a genuine locked dependency
graph. It does not establish a fresh full application build or full production
dependency resolution. Network, credentials and desktop protocol responses
use test doubles. No new live Zotero account/picker, Word/LibreOffice, or
operating-system keychain acceptance is claimed. Historical desktop,
terminal and keychain evidence retains its own source and platform scope.
No GitHub Actions, workflow/job/status queries, CI waits or reruns were used.
