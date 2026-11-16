> **Recovery update — 16 November 2026:** a complete fresh qualification of **1,173 tests** at Quds `b87f9d6c` and CrispCloud `07083d19`, with raw logs and reproduction evidence, is published in the [recovery report](../zotero-recovery-20261116/README.md). This file remains a historical record with its original source attribution. Missing historical post-PR raw archives have not been recovered.

# Final observed Zotero qualification checkpoint — 16 November 2026

**The final implementation and regression tests are saved remotely. Final local qualification passed: 923 distinct tests (895 Dart/Flutter and 28 Python).**

This checkpoint preserves the observed final result independently of the executor. The complete accepted raw receipts, logs, input maps and updated incoming audits were written and checked in the workspace, but their final Git publication was interrupted by disk exhaustion. The sandbox launcher could no longer start even a cleanup command; its approval policy also disallowed escalated cleanup. This document does not claim those final raw archives are already present on this branch. Earlier complete qualification archives remain committed.

## Exact qualified source pair

| Repository | Published implementation | Qualified tree |
| --- | --- | --- |
| Quds Office | `9de43669088c3719d541c9fe1c7dcb3ffbf86df3` | `6967cc3475a14cbbd8eabb21f6141da797c939c8` |
| CrispCloud | `24486b7df6a523cbfa4e5f2680efd3e1c188067e` | `7c79590b74c5a6a8020ef7882e9846171f26b422` |

The locally executed checkpoints `b77d990f7192fc3fa548bda78b54aa497341d406` (Quds) and `8c2bb8d08477b832fd150e0ada538729703167cc` (CrispCloud) were verified to have exactly these published trees. Production inputs were also matched individually against the published Git blobs.

Branches: `codex/zotero-capabilities-20261116` in both repositories.
Review: [Quds draft PR #63](https://github.com/CrispStrobe/quds_office_suite/pull/63) and [CrispCloud draft PR #176](https://github.com/CrispStrobe/CrispCloud/pull/176).

## Final disjoint results

| Cohort | Passed |
| --- | ---: |
| Engine Zotero | 390 |
| Editor Zotero | 186 |
| Engine proofing and hyphenation | 59 |
| ODS reader, outline and filter integration | 101 |
| Word layout and styles | 31 |
| Comment proofing/style inheritance | 4 |
| Editor proofing and platform spelling | 63 |
| Hyphenation painting and caret behavior | 19 |
| Hidden-sheet navigation | 1 |
| **Canonical total** | **854** |
| Actual CrispCloud host tests | 41 |
| Python vendor/sync/verifier tests | 28 |
| **Combined distinct total** | **923** |

The canonical selection contains 48 disjoint test files, with zero skips: 576 Zotero cases and 278 integration cases. The host selection contains 39 Zotero cases and two actual bundled-license cases. Development reruns, expected-failure controls, initial invocation failures, and the earlier 894-test source pair are excluded.

Strict analysis passed for **21 canonical targets and 15 host/vendored targets**. Dart 3.12 formatting passed for 15 selected canonical and 15 host/vendored targets with zero changes.

- Quds: all **1,507 canonical inputs** and **3,857 external dependency/runtime inputs** remained unchanged and matched the recorded source/graph.
- CrispCloud: all **3,687 source inputs** and **5,827 dependency files across 96 packages** remained unchanged.
- Locked harness manifests, package graphs and configurations remained unchanged; temporary analyzer configurations were restored.
- Both vendor guards verify **2,470 managed Office files** against the exact Quds pin above.
- The standalone parser remains at `4895712158127b2fc930d796e17035c3ca0dac62`.
- Runtime: genuine Flutter 3.47.8 / Dart 3.13.7, framework `737ba8f885dc774b53b442759999a312c9461e4e`, engine `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`.

The accepted final host receipt has SHA-256 `1ef317de210445c0c609de333852aa515164bfbe82fc35264a1b240a71b50bba`. An initial canonical launch without the workspace environment failed before loading tests; it was preserved separately and contributes zero tests. The accepted run used the existing workspace environment and locked graph.

## Zotero improvements

1. **Alias-aware source identity.** Shared embedded-CSL and basic-bibliography selection joins complete URI alias components, including late/transitive bridges, and retains the first available snapshot. Unrelated libraries and local profiles remain distinct. The same old/new fixture produces two bibliography sources before and one after the fix, with citation metadata and DOCX persistence preserved.
2. **One full document-tab field scan.** The real 1,000-citation widget fixture performs one field scan per build instead of four, while bibliography-only action availability stays correct. This is a traversal-count measurement, not an application latency benchmark.
3. **Online session backoff.** Server-requested pauses survive reconnects, key changes, public-library changes, forgetting credentials and reopening within the same session. Late responses cannot shorten a longer pause. The state contains only a deadline; local desktop clients remain independent.
4. **Protected document behavior during incoming proofing work.** Nine new editor regressions cover direct document replacement, tracked correction boundaries, empty complex fields, grapheme boundaries and undo after switching comments or headers/footers. Four imported comment-style cases cover the exact noProof inheritance correction. These bounded ports preserve the integrated session architecture.

The prior 1,000-source refresh capability, 50-item metadata batches, native citing, saved searches, rich citation fields, one-step undo and stale-document guards remain covered.

## Final observed incoming cutoff

Quds main is integrated through `47aa74ab2c45a5ce514343b44296a1a14fa3ae95` (PR #64), together with primary proofing `f4d52e5b0f04aa0a57cef2074f0b5ee3d2868f48`. The final frozen inventory contains **124 refs: 113 ancestors, ten exact ODS/documentation squash or patch equivalents, and one alternate proofing head with selected fixes adapted**. Our branch and PR #63 are excluded. Earlier outline aliases were compared with their exact squash counterpart, rather than with later filter-modified files.

The alternate `ca294cf8668706b45f40031ed9a2db52e5737cd2` retains a separate session/rendering architecture and distinct segmentation/retry policies. Its remote branch is preserved; this continuation does not claim that entire architecture was merged. The committed late proofing disposition records the selected ports and retained differences.

CrispCloud main is integrated through `8e8099e171c31eadb66e812147fc9be600057cab` (PR #175). Its final frozen inventory contains **218 refs: 208 ancestors and ten exact squash-equivalent branch/PR aliases**. Our branch and PR #176 are excluded. The keychain/favorites work remains included. During the vendor merge, the prior managed files and manifest were kept consistent, then immediately synchronized from the final canonical commit without bypassing the sync guard.

The snapshots are explicit cutoffs, not a claim that other branches stopped changing.

## Raw archive publication status and limits

The pending final archive directories already exist locally under each repository's `docs/validation/zotero-capabilities-20261116/`:

- Quds: `post-pr-canonical/`, updated current incoming audit, updated parent report, and the final noProof control inventory.
- CrispCloud: `post-pr-host/`, updated current incoming audit, `late-host-reconciliation.md`, and updated parent report.

The canonical archive contains the accepted runner, receipts, fourteen command logs, compressed fingerprints and separately preserved failed-launch evidence. The host archive contains 22 original artifacts, ten raw logs and four lossless maps, plus its archive inventory. Copy/decompression checks were completed; the final publication step awaits recovery of normal local execution.

No GitHub Actions jobs, workflow runs or CI status checks were queried, awaited or rerun. Checkpoint messages contain `[skip ci]`. This increment does not claim a fresh full application build or live Zotero/Word/LibreOffice/keychain acceptance. Earlier platform-specific and live evidence retains its original scope.
