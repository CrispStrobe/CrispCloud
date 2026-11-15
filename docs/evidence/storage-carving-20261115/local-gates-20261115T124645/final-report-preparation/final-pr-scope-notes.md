# PR #111 — final scope and limitations notes

Prepared read-only while final host gates were running. This is source/fix narrative, not a final acceptance statement; no current host runtime totals are inferred. Evidence paths below are repository-relative. The recorded app checkpoint used to bind the source documents is `40d9bf353150c05b81b4f9c70ab044e20b315e1a`; it is not labeled the final evidence head.

## Suggested narrative

- **Close the observed integration boundary.** The last individually observed integration input is `3e9560c9` (source commit `b99a31c5`), which adds comment relationship/namespace serialization and coverage. Its five non-evidence changes are the writer, namespace test, fixture producer, canonical documentation and vendor manifest; dependencies and committed locks are unchanged. It is preserved through pending merge `2083d2c2`, followed by corrected canonical source `47e44e0a`. The earlier 53-head closure remains a finite inventory, with subsequent exact observations documented separately; this does not claim a newer rolling upstream refresh.

- **Preserve native spreadsheet geometry.** The saved baseline demonstrated an ODS-to-XLSX copy changing an 81px default column to 64px. The correction retains default/base character widths, precision and native `sheetFormatPr` properties through save/reopen, including direct and isolate saves. The baseline is failure evidence, not acceptance.

- **Restore supported ODS coverage without relaxing bounds.** Source `9bb71983` restores the exact three deleted cases for currency-symbol copy/save, sparse inherited styled padding, and native-column geometry: 93 added lines, no production edit or deleted assertion. Its 70-case focused suite and strict reader/test analysis passed. Those cases remain byte-identical and ancestral in `47e44e0a`; incoming covered-cell and 10,000-comment limits remain intact. The 70 focused cases overlap the host engine cohort and are not added again.

- **Correct comment ownership and preserve unrelated package data.** On incoming `4e8c8f80`, newly allocated worksheets could delete/overwrite unowned legacy-named comments parts, or fail after package mutation when such an orphan had an invalid root. Four failure cases were saved before the correction. Source `47e44e0a` captures existing ownership before writes and preserves a separate empty authority through save/reopen/add/clear. Orphan XML, content type and outgoing relationships stay intact. All 28 focused comment tests and strict analysis of the three changed files pass; complete evidence is saved at `9f60ab2a`.

- **Complete underline support in both host controls.** The ribbon and Font dialog now cover all 18 supported styles, with distinct labels in all eight translated locale maps. This fixes the non-exhaustive switch and the imported-style dropdown invariant. Coverage selects each real menu option, opens Font, applies unchanged, and verifies DOCX save/reopen; the independent imported/mixed-format fidelity suite remains included. Eighteen styles is a feature count, not an additional runtime total.

- **Keep damaged Word recovery explicit and bounded.** The parser routes the specific typed `CfbfException` from a damaged compound directory through the existing opt-in, text-only DOCX fallback, preserving strict/default, DOCM, encryption, input/work and source-tail refusals. The host retains unknown source inventory as unknown, requires review of text-only losses, preserves prepared bytes on save retry, and saves a separate create-only copy. The earlier two host failures and all classified loading failures remain diagnostic receipts.

- **Use the audited full parser result once.** Exact parser source `08296edb` has independently verified evidence at `09a4a531`: 4,132 visible tests across all 144 suites, zero failures/errors/skips, and clean strict analysis of 18 files. The audit verifies 32 archive members, 23 inner-index entries, 937 tracked source files and stable 949-entry snapshots. The same SDK and standalone lock are verified; normalized graphs agree despite workspace serialization differences. This is standalone Dart qualification, distinct from the host graph; do not add earlier 4,131-test or focused 18-test totals.

- **Retain exact Linux image checks and independent output checks.** The five reviewed Linux references keep standard exact golden comparisons, bundled Office fonts and DPR 1; no tolerance, skipped comparison or reference regeneration is introduced. The comments generator now emits nine actual XLSX packages plus two authored expectation files. The separate Python/openpyxl check verifies explicit relationships, plain-comment namespaces/text/authors, empty authority and unrelated byte preservation. Passing counts for final host gates and this oracle must come from their final raw receipts, not historical or preparatory reports.

- **Report the practical acceptance limits.** Final host acceptance is the selected Linux Flutter/Dart/native-hook scope; snapshots establish before/after source and resolution identity, not a hermetic cache or proof against transient writes. The output readers do not certify broad Open XML schemas, rich/VML comment geometry, external Office rendering, or other operating systems. PNG recovery remains the bounded complete-PNG subset and reviewed new-ZIP publication; fragmented recovery, original-name inference, other formats, physical devices and browser/cloud publication are outside this change. Optional private corpus scans remain excluded. All checkpoints and gate receipts are saved incrementally with no GitHub Actions polling, restart or wait.

## Exact evidence paths

- **incoming_boundary**: `docs/evidence/storage-carving-20261115/local-gates-20261115T124645/integration-return-audit/README.md`
- **incoming_merge_proof**: `docs/evidence/storage-carving-20261115/local-gates-20261115T124645/integration-return-audit/resolved-merge-tree-proof.json`
- **geometry_failure**: `docs/evidence/storage-carving-20261115/local-resume-20261115T1150/ods-geometry-baseline-2/summary.json`
- **earlier_fixes_and_scope**: `docs/evidence/storage-carving-20261115/local-resume-20261115T1150/README.md`
- **ods_restoration**: `docs/evidence/storage-carving-20261115/local-gates-20261115T124645/canonical-ods-restoration/linkage.json`
- **comments_correction**: `docs/evidence/storage-carving-20261115/local-gates-20261115T124645/canonical-comments-ownership/linkage.json`
- **comments_independent_review**: `docs/evidence/storage-carving-20261115/local-gates-20261115T124645/comment-ownership-review/README.md`
- **underline_review**: `docs/evidence/storage-carving-20261115/local-resume-20261115T1150/underline-overlay-independent-review.json`
- **host_failure_classification**: `docs/evidence/storage-carving-20261115/local-resume-20261115T1150/app-runtime-failure-classification.json`
- **host_recovery_review**: `docs/evidence/storage-carving-20261115/local-resume-20261115T1150/incoming/host-recovery-independent-review.md`
- **parser_full_run**: `docs/evidence/storage-carving-20261115/local-gates-20261115T124645/integration-return-audit/parser-09a4/canonical-parser-full-qualification.json`
- **parser_full_audit**: `docs/evidence/storage-carving-20261115/local-gates-20261115T124645/integration-return-audit/parser-09a4/independent-verification.json`
- **linux_golden_review**: `docs/evidence/storage-carving-20261115/local-gates-20261115T124645/incoming-review/README.md`
- **comments_oracle_scope**: `docs/evidence/storage-carving-20261115/local-gates-20261115T124645/COMMENTS-ORACLE-PLAN.md`

Canonical source/evidence links for the last corrections:

- ODS source `9bb71983a4ae6bc7bb3372fd931e724ddd102fc8`; evidence `64d4c5687856554f3a86cf3c0a7c3d73e3091f8f`, under `CrispStrobe/quds_office_suite:docs/evidence/ods-regression-restore-20261115T1246/`.
- Comments source `47e44e0ae35adcc406eee2a2ae2118dd2a4a082a`; evidence `9f60ab2a47c2ebcef3d322a608d690178ff9b22f`, under `CrispStrobe/quds_office_suite:docs/evidence/comments-ownership-20261115T132154/`.
- Parser source `08296edbee08da013a8ff718798972552ccd03f7`; full evidence `09a4a531a4aa210a638a220de45c9d53d44c84e1`, archive `CrispStrobe/legacy-doc-parser:doc/evidence/incoming-reconcile-20261115/artifacts.tar.xz` (206,644 bytes; SHA-256 `353e4386a5e0a9fec060e2f75ff113a08a392febd565c32c2edcec074981c95d`).

Historical READMEs and audit reports retain their original pending/completed source scope. Use the final gate auditor to fill the final app source/evidence heads, source-resolution digest, current host totals and current oracle totals. No runtime, repository write or upstream refresh was performed to prepare these notes.
