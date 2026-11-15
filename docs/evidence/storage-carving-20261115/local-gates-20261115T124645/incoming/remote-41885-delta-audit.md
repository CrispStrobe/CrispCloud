# Observed 41885 source delta audit

**The new canonical mirrors are exact. The audit found and corrected a concrete loss of three ODS regression tests; it found no additional production defect in the narrow incoming source delta.**

## Exact observed scope

App `41885d7d1d67348f5abe3579b99d9d2951fc909f` descends from `137c95de221a0e30b14b59613b2f23447dcc57da` and changes 74 paths: 57 additions and 17 modifications. It pins Quds `6e4c3b16b4310f2c21b6d8b5e412af9850eb17ea` and parser `08296edbee08da013a8ff718798972552ccd03f7`. Both retain the previously qualified canonical pins as ancestors. No new remote branch inventory was requested.

All **2,334 managed files** (502 Quds; 1,832 parser) match their pinned canonical Git blobs, object types, file modes and manifest SHA-256 hashes. Parser `UPSTREAM.json` agrees and declares no patches. The Quds merge retains both current main and `c17098d6` as parents.

## Source behavior and preservation

The only production-code change is in the ODS reader: ordinary cells now require pending horizontal covered placeholders to be explicit, and expanded annotations are limited to 10,000 across the workbook. Both are explicit refusal paths. Existing expanded text, grid, cell, style and merge budgets remain. Native geometry, authored date literals, annotation namespace/author handling and linear comment serialization are preserved. Parser and host production files are unchanged. Engine development dependencies add `archive: ^4.0.0`; the app parser ref advances.

The ODS suite moves existing formula cases and adds annotation-coordinate/count coverage. It intentionally replaces omitted-placeholder compatibility assertions with explicit-covered/refusal tests. The live-corpus test now accepts explicit unsupported-profile refusals, so its success cannot be described as importing every corpus file.

## Coverage correction saved separately

Three prior tests were deleted rather than moved: currency-symbol copy/save fidelity, inherited styled-padding sparsity, and native-column geometry through a new XLSX copy. Their **exact predecessor bodies** were restored at Quds **`9bb71983a4ae6bc7bb3372fd931e724ddd102fc8`**, on `integration/ods-regression-restore-20261115T1246`, rooted at observed `6e4c3b16`. This changes only the ODS test file: 93 added lines, with no production edit or weakened incoming bound. Subsequent runtime/analysis evidence commits are separate from that source pin.

The incoming test also relaxes two inherited-column width assertions to `1e-5`; the restored native-geometry regression preserves its original `1e-10` check.

## Evidence and golden scope

The four saved incoming records describe a prior-source audit and sequential Office/parser syncs. Their intermediate managed count 2,309 grows to 2,334 after 25 parser evidence files are added; it is not the final count. Their prior gate claims remain bound to `20ee83ff` and must not be treated as acceptance of this new ODS behavior.

Independent golden review verified all five Linux PNG hashes/dimensions, exact comparison selectors, bundled fonts and DPR1. Provenance uses prose instead of an immutable source SHA and lacks a linked raw revalidation receipt; fresh exact comparisons provide current acceptance. Existing overlap in the dense fixture is also present in the qualified predecessor.

The JSON records all 74 changed paths, exact canonical identities, incoming-record hashes, preservation checks and correction details. The app checkout/index/HEAD was not modified by this audit. Canonical alignment and the separate correction branch were expressly authorized.
