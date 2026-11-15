# Restored ODS source and focused acceptance

**PASS. Source pin: [`9bb71983a4ae6bc7bb3372fd931e724ddd102fc8`](https://github.com/CrispStrobe/quds_office_suite/commit/9bb71983a4ae6bc7bb3372fd931e724ddd102fc8). Final evidence head: [`64d4c5687856554f3a86cf3c0a7c3d73e3091f8f`](https://github.com/CrispStrobe/quds_office_suite/commit/64d4c5687856554f3a86cf3c0a7c3d73e3091f8f).**

The separate remote branch is `integration/ods-regression-restore-20261115T1246`. QudsCanonical is now clean and detached at the source pin; the local and remote evidence branch remain at the final evidence head. No further runtime is needed from this agent.

## Source-only restoration

The source commit has parent `6e4c3b16b4310f2c21b6d8b5e412af9850eb17ea` and changes only `packages/quds_office_engine/test/ods_sheet_reader_test.dart`: **93 added lines, zero deletions, no production edits**. The exact 3,975-byte predecessor block restores currency-symbol copy/save fidelity, inherited styled-padding sparsity, and native-column geometry through a new XLSX copy. New covered-cell/comment bounds and incoming golden behavior are unchanged. The attached patch and JSON identify the exact Git blob and restored-block hash.

## Verified gates

| Gate | Saved evidence | Verified result |
| --- | --- | --- |
| Restored ODS suite | [`ods-suite-final/`](https://github.com/CrispStrobe/quds_office_suite/tree/64d4c5687856554f3a86cf3c0a7c3d73e3091f8f/docs/evidence/ods-regression-restore-20261115T1246/ods-suite-final) | **70 passed**, zero failures/errors/skips; exactly one requested suite, none missing/unexpected |
| Strict analysis | [`strict-analysis/`](https://github.com/CrispStrobe/quds_office_suite/tree/64d4c5687856554f3a86cf3c0a7c3d73e3091f8f/docs/evidence/ods-regression-restore-20261115T1246/strict-analysis) | ODS reader and restored suite: **no issues**, fatal infos and warnings enabled |
| Excluded initial recording attempt | [`ods-suite-path-binding-attempt/`](https://github.com/CrispStrobe/quds_office_suite/tree/64d4c5687856554f3a86cf3c0a7c3d73e3091f8f/docs/evidence/ods-regression-restore-20261115T1246/ods-suite-path-binding-attempt) | 70 behavioral passes, but excluded from accepted totals because relative and repository-relative suite paths did not bind |

Both accepted gates preserve source, commit identity, resolution inputs and tool hashes before/after execution. This package independently rechecks each raw receipt's SHA-256, byte length and exact Git blob at the saved evidence head. It also parses the raw machine stream, verifies the final success event, and observes all three restored test names passing. The corrected runtime uses an absolute suite argument; the initial raw attempt remains intact.

**Do not add 70 to the primary host total.** These focused tests are included in the coming engine cohort. The excluded attempt contributes zero accepted tests. Wider host acceptance belongs to the parent's current-source gates.

## Package contents

- `linkage.json`: source/evidence identities, exact restoration proof, accepted and excluded gate results, checkout state and counting rules.
- `raw-gates-sha256.json`: all 25 raw receipt/artifact file hashes, sizes and Git blobs across the accepted and excluded attempts.
- `source-restoration.patch`: the sole source-checkpoint diff.

The complete raw inputs and logs, explicit derived package graph, original dependency lock, immutable 41885 audit and gate drivers remain remotely saved under [`docs/evidence/ods-regression-restore-20261115T1246/`](https://github.com/CrispStrobe/quds_office_suite/tree/64d4c5687856554f3a86cf3c0a7c3d73e3091f8f/docs/evidence/ods-regression-restore-20261115T1246/). No GitHub Actions run was polled or awaited.
