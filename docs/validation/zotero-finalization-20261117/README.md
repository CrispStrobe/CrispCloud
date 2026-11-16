# Zotero integration finalization — 17 November 2026

**Fresh local qualification passed: 1,128 disjoint tests, zero failures and zero skips.** This comprises 1,036 canonical tests, 23 supplemental Harper tests, 41 actual-host tests and 28 Python sync/verifier tests. The independent final review verified terminal results, retained log hashes, unchanged input maps and current source bytes against the published Git blobs.

This continuation recovers the completed remote Zotero work, incorporates the bounded incoming Office branch snapshot, closes the English hyphenation notice gap in host distribution, and qualifies the resulting canonical and actual-host source locally.

The exact canonical implementation is [`5b05664357eead5ddc86922bab248224dbd4da6d`](https://github.com/CrispStrobe/quds_office_suite/commit/5b05664357eead5ddc86922bab248224dbd4da6d). The companion host implementation is [`342b744a3cb66e3ee9387733ebcf8613cdb23a33`](https://github.com/CrispStrobe/CrispCloud/commit/342b744a3cb66e3ee9387733ebcf8613cdb23a33). The evidence commits retain these implementation identities and measured input sets; they change documentation only.


## Receipts and complete evidence

| Record | Contents |
| --- | --- |
| [Machine-readable summary](qualification-summary.json) | Exact source pins, fresh totals, archive hashes and scope |
| [Canonical receipt](canonical-receipt.json) | All 12 completed canonical commands, counts and integrity gates |
| [Harper/Studio receipt](harper-studio-receipt.json) | All five supplemental commands and restored workspace graph |
| [Host receipt](host-receipt.json) | All ten actual-host commands and both vendor guards |
| [Independent final review](quds-independent-review.json) | Recomputed log hashes, current source SHA-256 values and Git blobs |
| [Canonical raw evidence](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/canonical-evidence.tar.gz) | Complete logs, runner, invocation, source/dependency maps and generated synthetic PDF fixtures |
| [Harper/Studio raw evidence](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/harper-studio-evidence.tar.gz) | Complete separate stdout/stderr logs, runner and input inventories |
| [Host raw evidence](https://github.com/CrispStrobe/CrispCloud/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/host-evidence.tar.gz) | Complete host logs, runner, before/after maps and host incoming audit |
| [Setup archive](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/setup-evidence.tar.gz) | Original scripts, locked manifests, package graphs, runtime identities and setup logs |
| [Incoming audit archive](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/incoming-audit-evidence.tar.gz) | All frozen refs, ancestor/exact-tree proofs, vendor plans and host preservation checks |

Each archive includes a per-file SHA-256 index. Gzip/tar packaging was checked by reading every member back and comparing its bytes. Follow the [setup and reproduction instructions](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/REPRODUCE.md); the archive preserves its relative `setup/` layout. The two assembled setup helpers are explicitly labeled as static-reviewed, while the actual used setup and qualification scripts remain available. No binaries or dependency cache are required in the evidence archive.

The first completed command logs were also saved remotely in [an intermediate journal checkpoint](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/checkpoints/progress.json) before the full run completed. That checkpoint is part of the same execution and adds no extra test cases.

## Zotero behavior retained

The existing Zotero improvements remain intact:

- Complete URI-alias components identify one embedded source, including late and transitive bridges and bridges without their own CSL snapshot. Selection preserves the first available original snapshot and keeps unrelated libraries and local profiles distinct.
- The document tab reuses its parsed field list for action availability. The earlier 1,000-citation control measured one field scan instead of four; that is a historical traversal-count result, not a fresh latency benchmark.
- Online client replacement, reconnection and dialog reopening share the maximum unexpired server pause deadline. A later response cannot shorten it; desktop clients retain independent pause state.
- Metadata refresh remains bounded and atomic: deduplicate by durable library identity, request at most 50 item keys per batch, validate all staged results and the edit target, then apply a single undoable document operation. Existing rich fields, saved-search handling and stale-target guards remain covered by the selected regression suites.

All **50 Zotero source, example, test and fixture paths** at the current implementation have the same Git blobs as completed recovery head `b4647f1c3aa60300116b27c3bce741b80ee39328`. The source-preservation audit records every path and both blob identities. No Dart source changed after adopting the incoming integration head `becfa07c1be62429a8bcf78910aa1ffb46248b1a`; subsequent canonical changes comprise the original notice files, their deterministic generator/checker, documentation and the recovery audit.

## Incoming work reconciled

The frozen local audit contains **189 named references at 128 distinct commits**: the fetched fork and original-upstream branch and PR-head snapshot. Every reference is an ancestor of the current canonical implementation. This is a bounded inventory, not a claim that concurrent branches cannot advance later.

The integrated rendering head `becfa07c1be62429a8bcf78910aa1ffb46248b1a` already contains recovery PR #85, English/German proofing PR #87, current main `fb62dbfc3a0fff95325a9a95b62e32f85f1abb80` through PR #86, and original upstream main `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`. The existing recovery branch was advanced to this reviewed head without rewriting another working branch.

Compared with the earlier Zotero recovery source, this integration brings English hyphenation, conservative German proofing improvements, Harper source mapping and the later spreadsheet work. Compared with the latest separately qualified rendering integration `c6aab884eb478672d36da5c03cd20873d7e8c42c`, the remaining production delta is four spreadsheet files and explanatory proofing-dialog text; the English/German/Harper implementations are unchanged. The selected fresh checks nevertheless cover the combined source and its dependency graphs.


## Actual host integration and retained differences

The host audit records **274 refs: 81 branch heads and 193 PR heads**. All are accounted for by **214 ancestors** of the published host source and **60 exact whole-tree aliases** to integrated ancestors. There are no outstanding refs in this bounded snapshot. Frozen host main `e18e92c44e1b80d250469feed130615571d5845f` and documentation PR #203 at `a8edc699641da3e3b3f1452b5db59bec52a5717d` are retained in merge ancestry.

Both snapshots were audited on **17 November 2026 at approximately 00:16 Europe/Berlin** (the JSON observations retain exact UTC timestamps). Later arrivals are outside this inventory until explicitly audited.

The guarded updater verifies **2,521 managed files: 664 canonical-managed files and 1,857 standalone parser files**. All 664 canonical-managed Git content blobs match their pinned Quds source. The parser remains pinned to `4895712158127b2fc930d796e17035c3ca0dac62`; its entire tracked tree is unchanged. All 14 inherited unmanaged content differences and six host-only localization files preserve their baseline blobs and modes.

An auxiliary comparison that requires canonical executable modes still identifies the **same eight inherited mode differences**. They are preserved by the updater's existing permission contract, recorded in the retained evidence, and are not reclassified as full-tree identity. No guard was relaxed and no host permission was normalized.

The production Flutter bundle and license registry now include six original notices. Both English notices are checked byte-for-byte against their pinned source preambles by the actual-host asset tests; the American permission is kept distinct from the British MIT grant. Existing test cases were extended, without splitting assertions to inflate the counts.

## Original English notices reach the host

The incoming English pattern data already retained its original terms in the full TeX sources and generated Dart prefaces. The host asset bundle and license registry needed small standalone notice files. The existing guarded vendor boundary already covers the hyphenation directory.

`ENGLISH_US_LICENSE` and `ENGLISH_GB_LICENSE` now contain the **verbatim original source preambles before the pattern section**. They preserve the copyright, permission, provenance and word-list statements without rewriting their terms. The American grant retains its existing `LicenseRef-Kuiken-permissive` identification; the British notice retains MIT. The original source's restriction on redistribution of the underlying OUP word list is preserved; that list is not bundled.

| Notice | Bytes | SHA-256 |
| --- | ---: | --- |
| `ENGLISH_US_LICENSE` | 2,234 | `1011c22144f360184ed86200fa2d2ca9df9ac19dd2ab4a31c0b4c94d998bb6f1` |
| `ENGLISH_GB_LICENSE` | 3,475 | `8a9d78cb8e3aa30383acc91fb05962035eed59877016263bd97be63c63341977` |

The existing generator now regenerates and verifies these notices alongside the two pattern-data files. `--check` requires exact source-preface bytes after validating the pinned source hashes. Generation and checking passed; the generated Dart data is unchanged. Isolated negative controls rejected altered notices in both languages. These controls are excluded from the Dart/Flutter test totals.

The companion host includes both notices in its guarded manifest, production asset declarations and existing license registry. The production sync whitelist is unchanged. Its existing license and sync tests now exercise the incoming notices. No new runtime dependency was added.

## Fresh local qualification

The runtime is genuine pinned **Flutter 3.47.8 / Dart 3.13.7**, framework `737ba8f885dc774b53b442759999a312c9461e4e`, engine `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`.

Canonical qualification uses **63 disjoint test files**. The supplemental Harper cohort adds three files in a different package. The actual-host and Python sync/verifier checks are counted separately. No earlier run, interrupted progress counter, setup check, negative control or overlapping historical cohort contributes to fresh totals.

| Current cohort | Files | Passed |
| --- | ---: | ---: |
| Engine Zotero | 19 | 390 |
| Editor Zotero | 13 | 186 |
| Engine German/office proofing and hyphenation | 4 | 84 |
| ODS reader | 1 | 102 |
| Word layout and styles | 2 | 31 |
| Editor proofing and platform spelling | 6 | 107 |
| Editor hyphenation, painting and caret behavior | 4 | 30 |
| Engine English, incoming sheets, contextual measurement and focused PDF controls | 11 | 94 |
| Editor wrapping, subset rendering and hidden-sheet navigation | 3 | 12 |
| **Canonical subtotal** | **63** | **1,036** |
| Harper adapter/source mapping | 3 | 23 |
| Actual CrispCloud host | 4 | 41 |
| Python sync/verifier | 2 modules | 28 |
| **Combined disjoint fresh total** | — | **1,128** |

Strict analysis and formatting cover **49 canonical targets**, **five Harper targets**, **one Studio integration target**, and **34 actual-host/vendored targets**. The Studio file is analyzed with the full production workspace graph because it imports Harper and other Studio dependencies; it is not analyzed using the smaller editor graph.

The supplemental full workspace contains **108 resolved packages**, all nine current workspace manifests copied byte-for-byte, and the published lock with SHA-256 `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.

| Integrity or completion gate | Result |
| --- | --- |
| All required canonical commands completed | Passed |
| Canonical source equals published Git blobs before and after | Passed |
| Canonical source, dependencies/runtime, harness and observed fixtures unchanged | Passed |
| Actual-host source/vendor/tracked-input guards | Passed |
| Actual-host source/dependency/runtime inputs unchanged | Passed |
| Supplemental source/workspace/dependency/runtime inputs unchanged | Passed |
| Original analyzer configurations restored | Passed |
| Test failures, errors and skips | Zero |


The completed canonical receipt binds **1,582 source inputs**, **3,857 external dependency/runtime inputs**, locked harness inputs and four separately observed system-font fixtures. All four optional fixture paths were present and unchanged. The actual-host receipt binds **3,744 selected source inputs**, **5,841 dependency files** and its runtime; its source/tracked vendor guards verify **2,521 managed files**. The supplemental receipt binds **1,597 canonical source inputs**, **5,195 external dependency files**, seven runtime artifacts and 13 harness inputs. These source sets overlap intentionally for integrity checks; they are not added together or presented as test-case counts.

The independent terminal review recomputed the retained command-log hashes, checked zero successful-command exit codes and terminal test markers, compared the before/after source and dependency maps, and matched every current selected source input against its published Git blob. It found no scope or attribution error. All three original analyzer configurations were restored.

Every command has a 600-second timeout, process-group termination on timeout, retained logs and 15-second heartbeat reporting. A passing test command requires a successful exit and a terminal completed-test marker. Supplemental qualification acquires the canonical qualification lock and runs after canonical completion so the two cannot overwrite each other's temporary analyzer graph. Host qualification uses a separate checkout.

The current canonical runner differs from its historical copy only in run metadata: obsolete local attempt-directory references were replaced by an explicit historical receipt and a declaration that its counts are not reused. The host runner adds ten incoming production analysis/format targets; its existing success gates remain intact. Exact runner bytes, deltas, invocations and hashes accompany the receipts.

## Historical evidence retains its original attribution

The recovered branch already contains a completed **1,104-test canonical qualification** at `b87f9d6c3a2532c9695024adf48ca9fbd3c0927a`, plus **41 actual-host and 28 Python tests** at host `07083d1983db87a9868c3e8ba0cda1efd283b445`. Their combined 1,173 is a historical result, not this run's total. The independent rendering branch's **626 tests** remain attributed to `c6aab884eb478672d36da5c03cd20873d7e8c42c`.

The selected fresh suite is narrower than those broad historical font/PDF cohorts in some areas and adds the current incoming integration coverage. Untouched PDF widget/template/toolbox cases remain in their original receipts; their passing counts are not copied into this run. Historical external Poppler verification is likewise not presented as a fresh execution.

## Remote preservation and limits

Source and integration checkpoints were saved incrementally to `codex/zotero-recovery-20261116`. This continuation retained the existing completed recovery evidence, incorporated the bounded incoming head, saved the incoming audit in `1cbbfbd`, and saved canonical notice integration in `5b056643`. The companion host source is preserved at `342b744a`. Final evidence commits retain these implementation pins. Review is available in [Quds PR #85](https://github.com/CrispStrobe/quds_office_suite/pull/85) and [CrispCloud PR #201](https://github.com/CrispStrobe/CrispCloud/pull/201).

This is scoped local engine/widget/host qualification and source-bound integration analysis. It does not establish a new full application build, live Zotero account/private-key acceptance, desktop picker or platform URL-launch acceptance, native keychain interaction, Microsoft Word/LibreOffice interoperability, or fresh native/Wasm Harper acceptance. Synthetic supplementary-Unicode PDF fixtures do not establish real emoji/CJK font coverage or shaping parity.

No GitHub Actions jobs, workflow runs, check/status endpoints, CI artifacts, waits or reruns were used. New checkpoints use `[skip ci]`.
