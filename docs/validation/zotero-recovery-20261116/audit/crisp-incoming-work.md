# CrispCloud incoming work and recovery — 16 November 2026

The recovered host implementation is **[`07083d1983db87a9868c3e8ba0cda1efd283b445`](https://github.com/CrispStrobe/CrispCloud/commit/07083d1983db87a9868c3e8ba0cda1efd283b445)**, tree `55349829d109305288ee241d29bd358d3d966038`. Its Office manifest pins canonical Quds **[`b87f9d6c3a2532c9695024adf48ca9fbd3c0927a`](https://github.com/CrispStrobe/quds_office_suite/commit/b87f9d6c3a2532c9695024adf48ca9fbd3c0927a)** and manages **2,509 files**. The host checkout was fast-forwarded to this exact remote commit, its tree and pin were read back, and the working tree was clean before qualification.

The final source has two parents:

- `05834b276c69ee45bdf72e9d7819ac58f448d786` — the saved recovery implementation, including the incoming font/PDF work and its host notice fix.
- `553f3be64da9ad3c35730f1b6a67d79f1ac54b72` — the single bounded late-main observation, retaining the worksheet page setup and ODS header/footer work through PR #200.

The source-adoption checks are in [host-qualification-source-adoption.json](host-qualification-source-adoption.json). Subsequent evidence-only publication does not replace these immutable implementation identities.

## Original observed inventory

The raw `git ls-remote` snapshot finished at **2026-11-16T19:38:45.364268+00:00** and contains **258 advertised refs: 73 branch heads and 185 PR heads**. Its exact content hash is `8b7fd56269c358a839c7b4c86b8b11e7fa32b12ebffcb06d72a4f709b47475e0`. The local ancestry evaluation was recorded at `2026-11-16T19:49:04.573598+00:00`; that evaluation timestamp does not redefine the remote observation cutoff.

The inventory is evaluated against frozen main **`bf0255a168576b0d9993d8b668f2a7d0d943fd4f`**:

| Disposition | Refs | Evidence |
| --- | ---: | --- |
| Actual ancestor of frozen main | 210 | Local Git commit ancestry |
| Exact whole-tree equivalent to a merged ancestor | 48 | 24 branch/PR pairs, each with identical head and merged Git tree IDs |
| Unresolved incoming ref | 0 | Every observed ref has an explicit disposition |
| **Total** | **258** | **73 branches + 185 PR heads** |

The 48 equivalence entries are two aliases each for PRs #171–#195, excluding #176. The original head commits of those 24 squash-merged PRs were read through the GitHub Git commits API. Their complete tree IDs equal the corresponding merged commits, and each merged counterpart is an actual local ancestor of frozen main. This records full-tree equality; it does not substitute a whitespace-normalized patch comparison. Older, closed-unmerged draft histories are included in the 210 actual ancestors.

The earlier Zotero continuation PR #176 was already merged before recovery and is an actual ancestor of the frozen main. Its source changes are retained. The new outgoing `codex/zotero-recovery-20261116` branch and later review PR were not present in this original incoming snapshot and are not added to its counts.

The proof can be reviewed or reproduced from:

- [crisp-remote-refs.txt](crisp-remote-refs.txt): exact advertised names and commit IDs.
- [crisp-pr-metadata.json](crisp-pr-metadata.json): metadata for all 185 observed pull requests.
- [crisp-incoming-audit.json](crisp-incoming-audit.json): one disposition for every ref.
- [crisp-remote-squash-equivalence.json](crisp-remote-squash-equivalence.json): all 24 head/merged tree identities and parents.
- [audit_crisp_refs.py](audit_crisp_refs.py): local ancestry and tree-equality replay, with the recorded GitHub tree proofs available for heads omitted by a partial clone.

With the evidence files together, replay the frozen inventory against a local checkout containing the recorded history:

```sh
GIT_NO_LAZY_FETCH=1 python audit_crisp_refs.py \
  --repo /absolute/path/to/CrispCloud \
  --evidence-dir /absolute/path/to/this/evidence
```

The replay does not fetch refs or query CI. It checks saved exact-tree proofs when the original squash heads are absent from a partial clone.

## One bounded later main observation

After the initial inventory, one further main observation was recorded at **2026-11-16 20:04:10 UTC**. That observation found **`553f3be64da9ad3c35730f1b6a67d79f1ac54b72`**, exactly five commits ahead of the frozen main. No further moving-ref inventory or branch/PR sweep was performed.

| PR | Incoming result |
| --- | --- |
| #196 | Vendored worksheet page setup round-trips |
| #197 | Worksheet page setup documentation |
| #198 | Restored the ODT registry and ODS page-setup documentation |
| #199 | Vendored ODS header/footer round-trips |
| #200 | ODS header/footer documentation |

The production changes are confined to `ods_sheet_reader.dart`, `ods_sheet_writer.dart`, `sml_workbook.dart`, and `sheet_serial.dart`, together with `ods_sheet_writer_test.dart` and `sheet_save_cache_and_freeze_test.dart`. The host documentation and vendor manifest also changed. No Zotero service, host notice registry, notice test, asset declaration, or sync-helper file overlapped the bounded incoming delta.

The exact observation and file list are saved in [crisp-bounded-final-main.json](crisp-bounded-final-main.json). This is an explicit supplement to the earlier 258-ref inventory; it does not claim that every other remote branch stopped changing afterward.

## Guarded final reconciliation

The bounded main used Quds source `c6a7eff46bcfcb806ee7c43252636b06c088963c` (`vendor/ods-header-footer`) with 2,503 managed files. The saved font/PDF recovery checkpoint used Quds `c6b9856ccd5264602d709b747decbd9631263574` with 2,509 entries. All standalone parser metadata and file hashes matched between them.

The six additional managed paths were `pdf_document.dart`, four new font/PDF regression or support files, and `third_party/fonttools/LICENSE`. The existing font/PDF changes and later sheet changes affected separate source areas. [crisp-late-manifest-comparison.json](crisp-late-manifest-comparison.json) records the exact sets and all twelve differing shared hashes.

The final tree was built from the intact bounded-main checkout. The five host helper/asset/notice files and recovery documents were carried over from the saved recovery checkpoint, then the existing guarded updater synchronized the final reconciled canonical commit. The managed files and manifest therefore stayed consistent throughout the merge. The final merge retains both original parents. Source and tracked-file vendor guards verified all 2,509 managed entries before host qualification.

The independent parser remains pinned to **`4895712158127b2fc930d796e17035c3ca0dac62`**. Its source boundary was retained; the Quds sync did not overwrite it.

## Host attribution fix accompanying the recovered font work

Incoming Quds font subsetting uses Unicode-range data transcribed from FontTools 4.61.1. Its original notice is now part of the guarded `third_party/fonttools` inventory, is bundled as a production Flutter asset, and is exposed through the existing Office license registry. No FontTools runtime dependency was added.

The existing source-sync regression now checks inclusion, exact bytes, idempotence, exclusions for similarly named or wrong-package directories, and refusal to overwrite edited FontTools or Wortliste notices. The existing actual-bundle regression verifies that all four Office notices equal their on-disk sources and appear in the Flutter license registry, including the specific FontTools version and copyright. The existing test cases were extended; their case counts were not inflated.

The final focused host runner selects 41 host tests and 28 Python sync/verifier tests, together with 24 strict-analysis and formatting targets: eight actual-host targets, the seven original vendored targets, five font/PDF production targets, and four bounded late-main sheet production targets. The fresh qualification receipt records the executed result separately; historical qualification totals and intermediate development checks are not added to it.

## Evidence and limits

The interrupted session's published implementation and summary were recovered from GitHub. Its unpublished final raw archives are not relabeled as recovered files. Fresh qualification is run against the exact current source pair above with new logs and before/after fingerprints.

No GitHub Actions jobs, workflow runs, status checks, CI waits, or reruns were used. Incremental checkpoints use `[skip ci]`. This recovery report concerns source integration and focused local qualification; it does not establish a fresh full application build or live Zotero, Word/LibreOffice, private-account, or operating-system keychain acceptance.
