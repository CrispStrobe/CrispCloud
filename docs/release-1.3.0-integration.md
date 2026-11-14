# CrispCloud 1.3.0 integration

Version: 1.3.0+23. This checkpoint integrates remote developments reviewed on 14 November 2026; later branch edits require another checkpoint.

## Integrated sources

- CrispCloud storage branch `integration/storage-capabilities-20261114`, through `03f37893819ee999a9a660f029306f53ed7f2d0f` (PR #101): FAT/UDF and partition-image browsing, supported LZFSE decoding and reviewed ZIP recovery, alongside the catalogue GUI.
- Canonical legacy DOC parser main `544a50e7f8ad095a618b6206ccece7e0cb335f4b` (PR #10 merged), consumed unchanged by Quds and CrispCloud. Quds main `cda2a076f2821ee3e4f587e73d84e213e59aca93`; Office verification checks 2,158 managed files and executable modes.
- CrisperBooks main `505d3d7bfb922e5f0d77b7230cd38b0e266d0606` was already consumed exactly; the all-heads fetch found no additional remote branches or open PRs.
- CrispSorter shared catalogue implementation remains pinned to `c1881142b0d4ffecb10f26d51fab2cda2f53588e`; no unmerged branch contains further catalogue/CLI changes.
- Catfish main `f318108` integrates PR #2's cancellable metadata scanning, safe CAF persistence and changing-file hash checks while preserving exact modern zero-byte sizes.

All remote heads were fetched explicitly, including repositories originally cloned with a single-branch refspec. The legacy parser's unresolved floating-table-origin investigation checkpoint is retained as an investigation, not substituted for the validated parser. CrispCloud's old local macOS merge-only branch adds no new feature implementation. No recently edited branches were deleted.

## Observed local checks

- Combined storage and catalogue host regression: **1,005 passed**.
- Canonical legacy DOC parser: **4,063 passed**, analyzer clean.
- Quds engine under the Dart runner: **1,634 passed**, three conditional font skips; engine analyzer clean. An initial Flutter-runner invocation was inappropriate for the pure-Dart subprocess tests; the complete Dart-runner rerun passed.
- Catfish: **201 passed**.
- LZFSE, partition inspection, FAT, UDF and ZIP recovery: all five acceptance drivers passed both VM execution and actual compiled JavaScript in Node.
- Deployment verifier accepts an exact source receipt and rejects a stale receipt. Workflow YAML parses.

The CLI now reports 1.3.0 under both executable names. The release workflow builds standalone CLI bundles alongside web, macOS, Windows, Linux, Android and iOS artifacts. Pages and Vercel use the exact successful CI source, expose `deployment.json`, and verify that receipt before reporting success. Manual dispatch can target an exact reviewed release ref.

Hosted CI, platform artifacts, final native build/signing and actual deployment receipts remain separate operational results, rather than inferred from these focused checks. Export policy classification, excluded territories and TestFlight group policy are unchanged.
