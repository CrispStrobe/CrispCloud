# CrispCloud: completed source-bound Office qualification

The fresh host run passed **125 substantive Dart/Flutter cases and 28 Python controls**, with no failures or skips. All **12 required gates** passed. The previously failing real DOCX-to-ODT column-break case passed with its original assertions and source bytes unchanged.

This result qualifies published host source [`5d99ecb79ab316058b2db2813932cf2a4849128a`](https://github.com/CrispStrobe/CrispCloud/commit/5d99ecb79ab316058b2db2813932cf2a4849128a), pinning canonical Quds source [`6a32a919325d71c121c63e3879cfd1b28d64312e`](https://github.com/CrispStrobe/quds_office_suite/commit/6a32a919325d71c121c63e3879cfd1b28d64312e). The run started at 19:13:12 UTC and completed at 19:16:17 UTC on 17 November 2026. The later evidence checkpoint changes documentation only; its implementation, dependency and runtime inputs remain bound to these source identities.

| Identity | Exact value |
| --- | --- |
| Host source tree | `343251381590c1c41f3bb546b485d4c0683f2ead` |
| Canonical source tree | `a2f4cb57a6a99a0506546419cc904bf873b32bca` |
| Published host parents | `131c93a000690de256f24fcc7ab1e3cb2d105eba`, `fd0cc5de6de1ef9328bf44084ef38ace52765916` |
| Equivalent local merge | `1ba0a6c5b16a7616049947e8b059371a4a69a471` |
| Standalone parser pin | `4895712158127b2fc930d796e17035c3ca0dac62` |
| Final runner SHA-256 | `80b418d54ca4a9cc9920a3fafc76b17d339329150ec7026e68d8bf76a6d63ec3` |

## Source reconciliation and preservation

The continuation first fetched all captured branch and PR heads and their reachable history, then integrated the fixed source snapshots. Host main was merged at `1cd2a18f`, then at `9eced5ce`, and finally at the superseding continuation merge `fd0cc5de`. The final merge retains both parents. PR #238 was superseded by merged PR #249; the later qualified continuation has its own review target.

Canonical changes were applied through `tool/sync_office_fidelity.py`. The final sync from `48b6998b` to `6a32a919` wrote eight managed paths: five additions and three existing-file changes, with zero deletions. It brings in the canonical bookmark model/writer corrections, imported inline-column segmentation, safe native-field handling and their controlled regressions. No vendor fix was implemented only in the host.

The complete independent Git audit verifies **2,620 managed files: 763 canonical files and 1,857 unchanged standalone parser files**. It retains all **20 audited host customizations**, all **six original notices and the engine license**, all **50 canonical and 46 host Zotero paths**, and the exact **12 inherited executable-mode differences**, with no new mode differences. The Unicode notice and app registration remain present. Protected dependency declarations, lockfile and parser metadata are unchanged. The optional AOT/GECToR/Harper packages remain outside the existing host managed-package boundary.

The local-to-published mapping is checked by identical Git tree and an empty diff. Source resolution details are in [the merge record](host-superseding-main-resolution.json), [the guarded sync plan](vendor-superseding-plan.json) and [its applied result](vendor-superseding-applied.json). Full blob, mode and protected-path evidence is in the archive's `independent/` directory.

## Fresh runtime scope

The run contains **119 repository cases across 11 files** and **six separately recorded writer-to-host probes**. Administrative loading/setup events are excluded. Every substantive start has a terminal event, both streams finish successfully, and neither stream contains duplicate starts, duplicate terminal records, failures or skips. Prior results are not added to this total.

| Repository cohort | Passed |
| --- | ---: |
| Annotation preview and privacy | 8 |
| Office document service | 41 |
| Proofing licenses | 2 |
| Zotero host workflows | 21 |
| Zotero citing transport | 16 |
| Zotero ribbon | 2 |
| Actual ODT/ODP menu export workflows | 11 |
| Actual ODT native-field and fallback menu workflow | 1 |
| Existing Office editor dialog lifecycle | 11 |
| ODT image viewer | 1 |
| ODS editor workflows | 5 |
| **Repository subtotal** | **119** |
| Archived writer-to-host probes, rerun unchanged | 6 |
| **Dart/Flutter total** | **125** |

### Actual editor, menu and preview coverage

The new menu cases open the real `OfficeEditorDialog`, import through the actual controller, invoke its registered export action, run the canonical writer and parse the resulting copy through the host service. Captured cloud storage and the destination callback are controlled boundaries. This tests the app's registered menu callback, not an operating-system menu click or native picker.

The independently authored DOCX case checks body text, tabs, distinct paragraph decorations, table content, notes, headers, section columns and the leading run-level column break. Annotation XML and comment content are retained while body preview/search excludes hidden payloads. The two plain paragraphs surrounding the kept column-break paragraph check that its pagination style does not contaminate their styles. That entire eleven-case file is byte-identical to the failed `83cc5b7c` attempt: SHA-256 `164f54855d5fc6580fb8b66b78577bbd83327e75b23742cb32e9fa154b991b7a`.

The ODP cases retain pending authored slide text and verify independently authored chart labels and numeric values first in the imported model, then in the exported chart-data table and host preview. Eight delayed destination outcomes cover saved copy, download, cancellation and failure for both ODT and ODP. They require immutable captured export bytes, preserved newer edits, duplicate-export blocking, an unchanged original target, and a subsequent ordinary Save that retains the newer edits.

The separate twelfth case authors complex DOCX fields directly as XML. It requires one empty native PAGE, NUMPAGES, DATE, TIME and TITLE placeholder under the existing export contract. The four schema-valid styled fields retain their outside bold/color spans; plain NUMPAGES is a direct paragraph child. Styled NUMPAGES keeps its cache and style through conservative fallback. Nested and unterminated fields retain their exact cached content, authored double spaces and following ordinary text in both plain-text and Markdown preview. Replaced native caches and hidden instructions are absent. Original DOCX bytes and clean state remain unchanged, with no upload. Its SHA-256 is `38d3563d44670d40860d5d50e7f591aa74b06b16fa457c8425e67046ecc68f0b`.

Two unexecuted test drafts were corrected before this case's first runtime execution: the first required a schema-invalid styled `text:page-count`, and the second preserved caches that the existing native-field contract replaces. Both drafts, static-check records and correction reasons remain in `setup/`; they are not negative runtime evidence. The [contract preparation record](host-field-contract-review.json) retains that history.

## Static, dependency and restoration gates

All twelve gates passed: vendor guard before execution, repository Flutter tests, supplemental probes, host strict analysis, vendor strict analysis, host formatting, viewer formatting, vendor formatting, Python vendor controls, offline Apple technical-source binding, whitespace, and the final vendor guard.

Strict analysis covers **18 host targets** and **62 vendor targets**. Every prior 17-host/61-vendor target remains selected; the additions are the separate host field case and canonical `word_bookmarks.dart`. The vendor selection retains the prior mandatory scope and includes all changed production Dart paths. Canonical development-only `package:test` units are analyzed in their canonical dependency graph; they are still included in the host's source hashes and changed-test formatting scope. The production host dependency graph was not altered to add a development-only package.

Formatting passed for the 18 host targets, the dedicated viewer target, and **86 handwritten vendor targets**. Both generated-data manifests authenticate **34 generated entries**. Their **18 selected generated Dart outputs** remain in strict analysis and source fingerprints; they are excluded from formatting only after verifying each exact manifest hash and generator header. No directory-wide formatting exemption was introduced.

The runtime is Flutter **3.47.8**, framework revision `737ba8f885dc774b53b442759999a312c9461e4e`, with Dart **3.13.7**. The harness resolves the exact production lock: **274 locked packages plus the root application**. Its top-level source links point at the actual checkout. Existing Rust hooks compiled with the recorded workspace-local Rust 1.100.0 toolchain; the required C hook compiled with Clang 19.1.7. No native hook was disabled and no application or native source was substituted.

The repository's existing system-SQLite helper temporarily configures the isolated harness manifest and restores it afterward. The loaded library is SQLite 3.46.1, with binary SHA-256 `14c4418a06c5c2e30f5fb57bc8add93762236ae17898c6708984cf15e680ca71`. Production manifests and lockfiles remain unchanged. The native compiler/component receipts record immutable URLs and hashes; large dependency and compiler binaries are not duplicated in the archive.

The accepted run records identical before/after maps for **8,604 source files**, **13,535 dependency files**, **six runtime inputs**, and **128 native-hook/tool inputs**. It also checks declarations, package roots, probe hashes and exact analyzer-configuration restoration. The source aggregate is `27c4d1f3487fced1e076641ac469e0c15c7eb978a78e318494f68253acbec79b`; the dependency aggregate is `95eb7aae4be9dca9d882c9a8bbdc414a3c7170dc72885fa270916f05657171da`.

The Apple policy update changes only `reviewed_source_sha256`. Independent recomputation checks all 954 reviewed paths. Relative to `83cc5b7c`, only the managed manifest changes within that inventory; relative to captured main `fd0cc5de`, the manifest and two previously qualified dialog formatting wraps differ. Encryption and distribution decisions, inventory, lock and policy checker are unchanged. [Technical review](apple-superseding-source-review.json).

## Earlier failures remain preserved

The [first attempt](host-attempt1-summary.json) at `78a4ccbb` is explicitly failed: its runtime streams passed, but its vendor analysis selection incorrectly included canonical development-only unit tests in the production host graph, and newly selected dialog formatting needed two wraps. The corrected scope preserves every mandatory vendor target and adds changed production targets; canonical unit analysis remains independently required in the canonical graph. The original runner, logs, before/after maps and failure receipt are preserved in [its archive](host-qualification-attempt1-78a4ccbb.tar.xz) and [hash index](host-qualification-attempt1-78a4ccbb-index.json).

The [second attempt](host-attempt2-summary.json) at `83cc5b7c` is also explicitly failed. It produced 123 passing cases and one genuine failure: a valid run-level DOCX column break became `WmlBreak.column`, but the ODT writer used only the paragraph property for a real break. The original case was retained unchanged, the repair was made canonically, and the whole final host scope was rerun. All other eleven gates had passed in that failed attempt; those passes are not reused as final results. [Preserved archive](host-qualification-attempt2-83cc5b7c.tar.xz) · [Hash index](host-qualification-attempt2-83cc5b7c-index.json).

Setup failures for missing loader aliases or native compilers, the initial full-graph diagnostic, and the chart diagnostic are retained separately. Their counts are never added to the accepted qualification.

## Evidence and reproduction

The [final evidence archive](host-final-qualification-5d99ecb7.tar.xz) and [its size/hash index](host-final-qualification-5d99ecb7-index.json) contain the complete raw streams, gate logs, receipt, source/dependency maps, exact runner and helper bytes, all six probe cases, qualified host test sources, independent source and runtime audits, setup records, native compiler metadata, and earlier unexecuted drafts. Every archived member was fully read back and checked against its recorded length and SHA-256. The archive contains **93 members**, is **1,066,316 bytes**, and has SHA-256 `e3d822d299a46b28e849722eb444e6652bf5f59b8b5c907410bc7e2cfc3bbd4b`. Independent recount separately verified every raw result, all twelve log hashes, all scoped Git/disk source bytes and modes, all dependency/runtime/native inputs, seven declarations and analyzer restoration. The [machine-readable final summary](host-final-summary.json) mirrors the completed receipt.

For the recorded workspace, the complete invocation is:

```sh
python3 /workspace/scratch/44ccebb41cba/host-runtime/scripts/run-full-host-qualification.py \
  --repo /workspace/scratch/44ccebb41cba/CrispCloud \
  --harness /workspace/scratch/44ccebb41cba/host-runtime/full-harness \
  --quds-source /workspace/scratch/44ccebb41cba/quds_office_suite \
  --flutter /home/agent/.codex/skills/remote-skills/.quds-gector-work/runtime/flutter-sdk \
  --shared-runtime /home/agent/.codex/skills/remote-skills/.quds-gector-work/runtime \
  --setup-receipt /workspace/scratch/44ccebb41cba/host-runtime/setup/full-host-setup.json \
  --source-commit 5d99ecb79ab316058b2db2813932cf2a4849128a \
  --quds-commit 6a32a919325d71c121c63e3879cfd1b28d64312e \
  --output /workspace/scratch/44ccebb41cba/host-runtime/qualification-5d99ecb7-reproduction
```

Use a clean checkout at the qualified source, not the later documentation commit, and a new output directory. A fresh environment must restore the recorded production lock, exact dependency/runtime inputs and native toolchain first. The included `prepare_full_harness.py` creates a source-linked harness from a clean checkout, and `prefetch_pub.py` verifies hosted archives against the lockfile. Setup logs preserve the successful `pub get --offline --enforce-lockfile` resolution. The original wrappers and recorded setup receipt use their shown directory layout; relocation requires explicit path rebinding and a freshly verified setup receipt, not a claim that the historical receipt describes a different environment.

These results cover the selected real editor, dialog, registered menu callback, service, transport and viewer paths with controlled storage/destination boundaries. They are not a platform release build, native picker acceptance, live Zotero/account acceptance, Microsoft Word field evaluation, or functional acceptance of every unrelated native bridge. Canonical engine/editor tests and real LibreOffice consumer acceptance have separate source-bound evidence. No GitHub Actions, workflow, check-run or CI-status endpoint was queried or awaited.
