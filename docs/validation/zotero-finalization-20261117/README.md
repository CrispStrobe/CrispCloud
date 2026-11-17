# Zotero integration finalization — 17 November 2026

**The final source checkpoints are Quds `732fc3d0` and CrispCloud `084815b6`.** They preserve the recovered Zotero improvements, the audited incoming Office integration, original English hyphenation notices, and the subsequent bounded main updates. The host amendment also fixes independent display geometry for repeated ODT pictures and rejects invalid converted image dimensions.

**Current integration status:** the verified source includes the captured mains through Quds `f57d8f5d` and CrispCloud `b852bc00`. A separate ODT writer/export feature subsequently landed on both mains. That newer production work is outside this qualification, and CrispCloud PR #201 currently reports conflicts with the newer main. The cutoff and exact later commits are recorded below.

The initial broad local qualification passed **1,128 disjoint tests, zero failures and zero skips** at the original implementation pair. That run comprises 1,036 canonical tests, 23 supplemental Harper tests, 41 actual-host tests and 28 Python sync/verifier tests. Its complete receipts remain attached to those exact source pins. The bounded follow-up passed 126 test executions against the final source pair, with its overlapping counts reported separately below.

| Source identity | Quds Office | CrispCloud host |
| --- | --- | --- |
| Initial broad qualification | [`5b05664357eead5ddc86922bab248224dbd4da6d`](https://github.com/CrispStrobe/quds_office_suite/commit/5b05664357eead5ddc86922bab248224dbd4da6d) | [`342b744a3cb66e3ee9387733ebcf8613cdb23a33`](https://github.com/CrispStrobe/CrispCloud/commit/342b744a3cb66e3ee9387733ebcf8613cdb23a33) |
| Final source amendment | [`732fc3d0bc7a1118f3eb86e6c762fe70182c4fd2`](https://github.com/CrispStrobe/quds_office_suite/commit/732fc3d0bc7a1118f3eb86e6c762fe70182c4fd2) | [`084815b665df7779357155d86c5fff9bd31bfc43`](https://github.com/CrispStrobe/CrispCloud/commit/084815b665df7779357155d86c5fff9bd31bfc43) |
| Frozen incoming main used by amendment | [`f57d8f5debd8c27fe7cb9b9322c84fb284ff2c49`](https://github.com/CrispStrobe/quds_office_suite/commit/f57d8f5debd8c27fe7cb9b9322c84fb284ff2c49) | [`b852bc0010b227f4ade321a63d6cfc8ba769b98b`](https://github.com/CrispStrobe/CrispCloud/commit/b852bc0010b227f4ade321a63d6cfc8ba769b98b) |

The canonical package delta between the two implementation pairs is exactly two production Dart files and one test file for spreadsheet differential styles. The host carries those canonical updates plus ODT image geometry changes. Documentation, vendor identity metadata and retained evidence account for the other changes. Subsequent evidence commits preserve these final implementation identities.

## Receipts and complete evidence

| Record | Contents |
| --- | --- |
| [Initial qualification summary](qualification-summary.json) | Original source pins, 1,128-test totals, archive hashes and scope |
| [Initial canonical receipt](canonical-receipt.json) | All 12 completed canonical commands, counts and integrity gates |
| [Initial Harper/Studio receipt](harper-studio-receipt.json) | All five supplemental commands and restored workspace graph |
| [Initial host receipt](host-receipt.json) | All ten actual-host commands and both vendor guards |
| [Initial independent review](quds-independent-review.json) | Recomputed log hashes, source SHA-256 values and Git blobs for the initial source pair |
| [Bounded late-main audit](late-main-canonical-review.json) | Exact incoming main changes, host blob correspondence and PR #89 tree equivalence |
| [Final canonical identity review](late-main-canonical-final.json) | Final ancestry, 50 unchanged Zotero paths and exact three-file package delta |
| [Canonical raw evidence](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/canonical-evidence.tar.gz) | Complete logs, runner, invocation, source/dependency maps and generated synthetic PDF fixtures |
| [Harper/Studio raw evidence](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/harper-studio-evidence.tar.gz) | Complete separate stdout/stderr logs, runner and input inventories |
| [Host raw evidence](https://github.com/CrispStrobe/CrispCloud/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/host-evidence.tar.gz) | Complete host logs, runner, before/after maps and host incoming audit |
| [Setup archive](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/setup-evidence.tar.gz) | Original scripts, locked manifests, package graphs, runtime identities and setup logs |
| [Incoming audit archive](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/incoming-audit-evidence.tar.gz) | All frozen refs, ancestor/exact-tree proofs, vendor plans and host preservation checks |

The initial archives above retain their original names and contents. Each archive includes a per-file SHA-256 index. Gzip/tar packaging was checked by reading every member back and comparing its bytes. Follow the [setup and reproduction instructions](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/REPRODUCE.md); the archive preserves its relative `setup/` layout. The two assembled setup helpers are explicitly labeled as static-reviewed, while the actual used setup and qualification scripts remain available. No binaries or dependency cache are required in the evidence archive.

The first completed command logs were also saved remotely in [an intermediate journal checkpoint](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/checkpoints/progress.json) before the full run completed. That checkpoint is part of the same execution and adds no extra test cases.

## Zotero behavior retained

The existing Zotero improvements remain intact:

- Complete URI-alias components identify one embedded source, including late and transitive bridges and bridges without their own CSL snapshot. Selection preserves the first available original snapshot and keeps unrelated libraries and local profiles distinct.
- The document tab reuses its parsed field list for action availability. The earlier 1,000-citation control measured one field scan instead of four; that is a historical traversal-count result, not a fresh latency benchmark.
- Online client replacement, reconnection and dialog reopening share the maximum unexpired server pause deadline. A later response cannot shorten it; desktop clients retain independent pause state.
- Metadata refresh remains bounded and atomic: deduplicate by durable library identity, request at most 50 item keys per batch, validate all staged results and the edit target, then apply a single undoable document operation. Existing rich fields, saved-search handling and stale-target guards remain covered by the selected regression suites.

All **50 Zotero source, example, test and fixture paths** at final canonical source `732fc3d0` have the same Git blobs and file modes as both initial qualified source `5b056643` and completed recovery head `b4647f1c3aa60300116b27c3bce741b80ee39328`. The final identity review records every path and all three blob identities. The initial integration added the original English notice files and their deterministic checker without changing the incoming Dart implementation; the later main amendment changes only the three spreadsheet package paths described below.

## Incoming work reconciled

The frozen local audit contains **189 named references at 128 distinct commits**: the fetched fork and original-upstream branch and PR-head snapshot. Every reference remains an ancestor of final canonical source `732fc3d0`. The identity review rechecked all 128 distinct commits against that final source. This inventory captures the references at the audit timestamp; later branch movement is recorded separately.

The integrated rendering head `becfa07c1be62429a8bcf78910aa1ffb46248b1a` already contains recovery PR #85, English/German proofing PR #87, the then-current main `fb62dbfc3a0fff95325a9a95b62e32f85f1abb80` through PR #86, and original upstream main `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`. The existing recovery branch was advanced to this reviewed head without rewriting another working branch.

Compared with the earlier Zotero recovery source, this integration brings English hyphenation, conservative German proofing improvements, Harper source mapping and the later spreadsheet work. Compared with the latest separately qualified rendering integration `c6aab884eb478672d36da5c03cd20873d7e8c42c`, the remaining production delta is four spreadsheet files and explanatory proofing-dialog text; the English/German/Harper implementations are unchanged. The initial broad checks cover that combined source and its dependency graphs.

## Bounded main amendment

After the initial broad run and evidence publication, canonical main advanced by four commits and host main by five. The amendment freezes Quds main at `f57d8f5d` and host main at `b852bc00`, merges them into the existing recovery branches, and applies the guarded Office sync. The final canonical tree is `44b88a75c7f9a5d5fe12cd099299256d59c4d219`.

The canonical main delta has five paths: README cleanup, remaining-gap documentation, and these three package paths:

| Canonical path | Resulting behavior |
| --- | --- |
| `packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart` | Restore differential fill/font colors and serialize styles when conditional formats require them |
| `packages/quds_office_engine/lib/src/sheet/styles/sml_styles.dart` | Parse differential fill/font style collections |
| `packages/quds_office_engine/test/sheet_save_cache_and_freeze_test.dart` | Check that distinct conditional fill colors survive a save/reload round trip |

All five paths were unchanged between the original main, initial tested source and evidence checkpoint, so the merge had no overlapping recovery edits. The final three package blobs exactly match the frozen host main. Original PR #89 head `31a26383639dc7f751cfb0ea543ec7454a537ff6` and main squash `281b5d4cd705c1f32d98a741233ebb836d1ef20a` share complete tree `c8fb98b5cc4426c7de728693d89a76657424c4ed`, accounting for the original branch's content despite squash ancestry.

Host main adds ODT frame dimensions to image metadata and uses them when displaying registry-backed pictures. The integration review found that frames referencing the same image could otherwise overwrite one another's geometry. The final host gives every repeated frame its own display alias while all aliases share the same `Uint8List` image bytes. Frames without explicit dimensions preserve natural sizing independently of neighboring frames. Parsed dimensions are accepted only when the final converted pixel value is finite and positive; conversion overflow is rejected as well as malformed, zero or unsupported input. Width and height remain independently optional.

Two new service regression tests exercise repeated landscape/portrait/natural-size frames sharing one picture and invalid or non-finite dimensions, including conversion overflow. Existing assertions also check ordinary inch-to-pixel conversion. Their executed counts and gates belong to the follow-up receipt below.

The later observed [PR #72](https://github.com/CrispStrobe/quds_office_suite/pull/72) snapshot `ac295d4b3f247aee53b13b4b3f7e4fffc9d66600` remains separate incoming work. Relative to the initial tested source it changes 18 production Dart paths and 11 test Dart paths across further rendering, PDF parsing/export, proofing and conditional-rule behavior. It is outside both the original frozen 189-ref snapshot and this bounded main amendment. Its observed identity is retained in the late audit so the inclusion claims cannot be mistaken for a continuously moving branch guarantee.

## Actual host integration and retained differences

The host audit records **274 refs: 81 branch heads and 193 PR heads**. The initial audit accounts for all of them as **214 ancestors** of the initial host source and **60 exact whole-tree aliases** to integrated ancestors. Final host `084815b6` descends from that source and retains this captured inventory. There are no outstanding refs within the original snapshot. Frozen host main `e18e92c44e1b80d250469feed130615571d5845f` and documentation PR #203 at `a8edc699641da3e3b3f1452b5db59bec52a5717d` are retained in merge ancestry.

Both snapshots were audited on **17 November 2026 at approximately 00:16 Europe/Berlin** (the JSON observations retain exact UTC timestamps). The bounded late-main audit described above supplements this inventory; its newer observed PR #72 head remains separately identified.

The guarded updater verifies **2,521 managed files: 664 canonical-managed files and 1,857 standalone parser files**. The guarded amendment preserves that inventory and aligns the 664 canonical-managed Git content blobs with final Quds source `732fc3d0`. The parser remains pinned to `4895712158127b2fc930d796e17035c3ca0dac62`; its entire tracked tree is unchanged. All 14 inherited unmanaged content differences and six host-only localization files preserve their baseline blobs and modes.

An auxiliary comparison that requires canonical executable modes still identifies the **same eight inherited mode differences**. They are preserved by the updater's existing permission contract, recorded in the retained evidence, and are not reclassified as full-tree identity. No guard was relaxed and no host permission was normalized.

The production Flutter bundle and license registry now include six original notices. Both English notices are checked byte-for-byte against their pinned source preambles by the actual-host asset tests; the American permission is kept distinct from the British MIT grant. Existing test cases were extended, without splitting assertions to inflate the counts.

## Concurrent production work after the qualified cutoff

The initial frozen inventory is fully accounted for, and the bounded main amendment is included. Subsequent production changes are identified separately:

| Repository | Later observed main | Separate feature |
| --- | --- | --- |
| Quds | `8a3f5a9de14c556fd01ffacb3897629c51f4fa7e` | PR #92: public engine export, new `OdtDocumentWriter`, and its tests |
| CrispCloud | `8fe921d030d7623046e28127abec5949c4d8b991` | PR #208 adds host **Export as ODT**; PR #209 documents it |

The [canonical observation](quds-later-main-observation.json) records three changed package paths and 670 added lines. The [host movement receipt](post-qualification-main-movement.json) records fifteen changed paths, including production code, tests, documentation and a different canonical source pin. That newer host manifest has 2,505 managed files; this recovery branch retains its qualified 2,521-file inventory and original notices. Integrating the new export feature requires a combined guarded source sync and qualification of those changed inputs.

These commits arrived after the qualified source was frozen. They are neither included in the original timestamped ref counts nor represented as covered by the final receipts. The included ODT changes preserve imported picture geometry; the later export feature remains separate. Both recovery PRs are open for review. PR #201 currently reports conflicts with the newer host main, so this report does not claim a merge-ready combined export/Zotero tree.

## Original English notices reach the host

The incoming English pattern data already retained its original terms in the full TeX sources and generated Dart prefaces. The host asset bundle and license registry needed small standalone notice files. The existing guarded vendor boundary already covers the hyphenation directory.

`ENGLISH_US_LICENSE` and `ENGLISH_GB_LICENSE` now contain the **verbatim original source preambles before the pattern section**. They preserve the copyright, permission, provenance and word-list statements without rewriting their terms. The American grant retains its existing `LicenseRef-Kuiken-permissive` identification; the British notice retains MIT. The original source's restriction on redistribution of the underlying OUP word list is preserved; that list is not bundled.

| Notice | Bytes | SHA-256 |
| --- | ---: | --- |
| `ENGLISH_US_LICENSE` | 2,234 | `1011c22144f360184ed86200fa2d2ca9df9ac19dd2ab4a31c0b4c94d998bb6f1` |
| `ENGLISH_GB_LICENSE` | 3,475 | `8a9d78cb8e3aa30383acc91fb05962035eed59877016263bd97be63c63341977` |

The existing generator now regenerates and verifies these notices alongside the two pattern-data files. `--check` requires exact source-preface bytes after validating the pinned source hashes. Generation and checking passed; the generated Dart data is unchanged. Isolated negative controls rejected altered notices in both languages. These controls are excluded from the Dart/Flutter test totals.

The companion host includes both notices in its guarded manifest, production asset declarations and existing license registry. The production sync whitelist is unchanged. Its existing license and sync tests now exercise the incoming notices. No new runtime dependency was added.

## Initial broad local qualification

The initial run uses genuine pinned **Flutter 3.47.8 / Dart 3.13.7**, framework `737ba8f885dc774b53b442759999a312c9461e4e`, engine `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`.

Canonical qualification uses **63 disjoint test files**. The supplemental Harper cohort adds three files in a different package. The actual-host and Python sync/verifier checks are counted separately. No earlier run, interrupted progress counter, setup check, negative control or overlapping historical cohort contributes to the initial 1,128 total.

| Initial cohort at `5b056643` / `342b744a` | Files | Passed |
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
| **Combined disjoint initial total** | — | **1,128** |

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

The initial completed canonical receipt binds **1,582 source inputs**, **3,857 external dependency/runtime inputs**, locked harness inputs and four separately observed system-font fixtures. All four optional fixture paths were present and unchanged. The actual-host receipt binds **3,744 selected source inputs**, **5,841 dependency files** and its runtime; its source/tracked vendor guards verify **2,521 managed files**. The supplemental receipt binds **1,597 canonical source inputs**, **5,195 external dependency files**, seven runtime artifacts and 13 harness inputs. These source sets overlap intentionally for integrity checks; they are not added together or presented as test-case counts.

The independent terminal review recomputed the retained command-log hashes, checked zero successful-command exit codes and terminal test markers, compared the before/after source and dependency maps, and matched every selected source input at review time against its initial qualified Git blob. It found no scope or attribution error. All three original analyzer configurations were restored.

Every command has a 600-second timeout, process-group termination on timeout, retained logs and 15-second heartbeat reporting. A passing test command requires a successful exit and a terminal completed-test marker. Supplemental qualification acquires the canonical qualification lock and runs after canonical completion so the two cannot overwrite each other's temporary analyzer graph. Host qualification uses a separate checkout.

The initial canonical runner differs from its historical copy only in run metadata: obsolete local attempt-directory references were replaced by an explicit historical receipt and a declaration that its counts are not reused. The host runner adds ten incoming production analysis/format targets; its existing success gates remain intact. Exact runner bytes, deltas, invocations and hashes accompany the receipts.

## Follow-up qualification on the final source pair

The final amendment is attributed to canonical `732fc3d0bc7a1118f3eb86e6c762fe70182c4fd2` and host `084815b665df7779357155d86c5fff9bd31bfc43`. The independent final identity review has passed: all 189 original canonical refs remain ancestors, the frozen late main and original evidence are retained, all 50 Zotero paths are unchanged, and the canonical package delta is exactly the three spreadsheet files above.

Follow-up execution covers the changed spreadsheet behavior and production analysis, actual-host integration, ODT service regressions, guarded vendor identity, and the relevant source/dependency/runtime inputs. Repeated cohorts retain their separate execution counts; those counts are not added to 1,128 as new disjoint coverage.

**The final bounded run passed all 126 test executions, with zero failures and zero skips.** All three canonical commands and all twelve host commands completed successfully at the final source pair above.

| Final bounded cohort | Passed |
| --- | ---: |
| Canonical sheet cache/save and style-namespace fidelity | 18 |
| Existing actual-host Zotero and notice tests | 41 |
| Office document service, including the two new ODT regressions | 39 |
| Python Office/parser sync and verifier tests | 28 |
| **Final bounded execution total** | **126** |

These are separately recorded executions, including repeated cohorts from the initial qualification. They are not added to the initial 1,128 as a unique-test total. The final receipt is [late-main-receipt.json](late-main-receipt.json), its compact summary is [late-main-summary.json](late-main-summary.json), and the independent terminal review is [late-main-independent-review.json](late-main-independent-review.json).

Strict analysis and formatting passed for four canonical targets, ten host targets and twenty-seven vendored targets. The imported viewer also passed formatting after applying the genuine Dart formatter's layout changes. Its exact delivered blob is bound by the receipt; this pass does not compile, analyze or execute the complete viewer widget graph. The ODT parsing and geometry regressions execute through the actual document-service code.

The canonical run binds 1,582 source inputs and 1,770 dependency/runtime inputs. The actual-host run binds 3,745 source inputs and 5,983 dependency/runtime inputs. All before/after maps, harness inputs, observed fixtures, published-source comparisons and analyzer restoration gates passed. The final source/tracked guards again verified all 2,521 managed Office files. The [final host audit](late-main-host-final.json) independently preserves the parser, notices, twenty host customizations and eight inherited mode differences.

The dedicated service graph contains 107 packages. Every one of its 97 hosted packages matches the production lock's version and archive SHA-256. Its eleven added archives retain production-locked identities; the earlier 96-package harness and SDK remain unchanged. The first enforced setup resolution rejected two stale local engine/editor paths with exit 65. Correcting only those paths was followed by two successful offline enforced-lock resolutions. That recovered setup diagnostic is retained separately and contributes no test count. The revised fresh-run preparation helper is explicitly static-reviewed and was not rerun end to end; the accepted graph came from the initial preparation and the executed recovery helper. The provenance addendum retains exact locks/logs and labels the reconstructed initial helper accurately.

The first bounded attempt at host `4ed1baac3c4ead54d1ba033287c86ef809126e86` completed 98 test executions but failed the required viewer-format gate; four later gates were therefore unexecuted. Its [status record](https://github.com/CrispStrobe/CrispCloud/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/checkpoints/late-main-attempt-1.json), [complete raw archive](https://github.com/CrispStrobe/CrispCloud/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/checkpoints/late-main-attempt-1.tar.gz) and [independent failed-attempt review](late-main-attempt-1-review.json) remain intact. The formatter correction was saved at `084815b6`, then all bounded checks were repeated successfully in a fresh output directory. Failed-attempt counts do not enter the accepted 126.

[The complete late-run evidence archive](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/late-main-evidence.tar.gz) contains the final receipts, raw logs, input maps, exact runners and deltas, service setup records, locked harness inputs, formatter application proof, independent audits and reproduction notes. Its member index is checked by reading every archived byte back; the archive SHA-256 and size are recorded in [late-main-summary.json](late-main-summary.json). [Late-run reproduction](LATE-REPRODUCE.md) supplements the original runtime setup instructions.


## Historical evidence retains its original attribution

The recovered branch already contains a completed **1,104-test canonical qualification** at `b87f9d6c3a2532c9695024adf48ca9fbd3c0927a`, plus **41 actual-host and 28 Python tests** at host `07083d1983db87a9868c3e8ba0cda1efd283b445`. Their combined 1,173 remains a historical result with those original source pins. The independent rendering branch's **626 tests** remain attributed to `c6aab884eb478672d36da5c03cd20873d7e8c42c`.

The initial broad suite is narrower than those historical font/PDF cohorts in some areas and adds the captured incoming integration coverage. Untouched PDF widget/template/toolbox cases remain in their original receipts; their passing counts are not copied into either current receipt set. Historical external Poppler verification is likewise not presented as a fresh execution.

## Remote preservation and limits

Source and integration checkpoints were saved incrementally to `codex/zotero-recovery-20261116`. This continuation retained the existing completed recovery evidence, incorporated the bounded incoming head, saved the incoming audit in `1cbbfbd`, and saved canonical notice integration in `5b056643`. The initial companion host source is preserved at `342b744a`. The late-main checkpoints preserve final canonical source at `732fc3d0` and final host source at `084815b6`; both descend from the earlier implementation/evidence history. Final evidence commits retain both the initial and amended implementation pins with their corresponding receipts. Review is available in [Quds PR #85](https://github.com/CrispStrobe/quds_office_suite/pull/85) and [CrispCloud PR #201](https://github.com/CrispStrobe/CrispCloud/pull/201).

This is scoped local engine/widget/host qualification and source-bound integration analysis. It does not establish a new full application build, live Zotero account/private-key acceptance, desktop picker or platform URL-launch acceptance, native keychain interaction, Microsoft Word/LibreOffice interoperability, or fresh native/Wasm Harper acceptance. Synthetic supplementary-Unicode PDF fixtures do not establish real emoji/CJK font coverage or shaping parity.

No GitHub Actions jobs, workflow runs, check/status endpoints, CI artifacts, waits or reruns were used. New checkpoints use `[skip ci]`.
