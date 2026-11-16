# Combined CrispCloud host qualification

The final combined host cohort passed on 2026-11-16 from **13:44:41 to 13:45:45 UTC**, using the actual CrispCloud sources and their actual vendored Office files.

| Source identity | Value |
| --- | --- |
| Published CrispCloud implementation | `27f001d60777d27f412d9984b62dbdb05019b9eb` |
| Local HEAD at both start and completion | `84955ca66662f7fdf638487dd4691e5c2fa018d0` |
| Exact Git tree shared by both commits | `ab5fe16a2289ea67ae4d4c72a542f233d178305f` |
| Canonical Quds pin | `8e017e8c148517fea61f8d55eaafc7f070b82bba` |
| Canonical tree | `17eecf8b8c8558c78dbbefe9ffc9b1249e2455cf` |
| Standalone legacy parser pin | `4895712158127b2fc930d796e17035c3ca0dac62` |

Only the continuation branch was fetched to obtain the published commit object. The local branch was not reset. Before execution, the runner verified the full published commit identities, equality of the local and published host trees, the canonical manifest pin, and absence of tracked qualification-input differences from the published commit.

## Accepted results

| Check | Result |
| --- | ---: |
| Host Zotero transport, credentials, target and ribbon tests | 39 passed |
| Actual bundled German notice tests | 2 passed |
| Final distinct host cohort | **41 passed** |
| Python Office and standalone-parser sync/verifier regressions | **28 passed** |
| Strict analysis of actual host source and all four host test files | 8 targets, no issues |
| Strict analysis of vendored Zotero, caret, painter and caret regression | 7 targets, no issues |
| Declared-language formatting | 15 files, zero changes |
| Office source and tracked-index guards | 2,468 managed files verified |
| Production source, assets and configuration inventory | 3,685 files unchanged |
| Resolved dependency library/configuration inventory | 5,827 files unchanged |
| Genuine resolved packages | 96 |

The vendor guard passed against canonical source before testing; the tracked-index guard passed both before and afterward. Strict analysis used `dart analyze --fatal-infos`. The additional vendored analysis targets are `caret_engine.dart`, `paint_run_text.dart`, and `word_hyphenation_caret_test.dart`. The caret regression's runtime tests belong to the separate canonical qualification and are not counted again here.

No dependencies or locks were resolved or changed. The temporary package configuration used to analyze the actual host checkout was restored. The canonical checkout's package configuration was not modified. Flutter **3.47.8**, Dart **3.13.7**, resolved dependency roots, declarations, locks, and relevant runtime binary hashes are recorded in the evidence.

## Source and dependency integrity

| Inventory | Aggregate SHA-256, identical before and after |
| --- | --- |
| Source inventory | `eb31b19bb7ce6b746dd38a6bc87003a31d8514b84b04e1ecfe8c5f2ad48723d8` |
| Dependency inventory | `bd69cdd0d26c14afdd1c16b2ddfb14bc33ac92cacd3115229438559f15b21ccd` |

[receipt.json](receipt.json) contains commands, UTC times, counts, source identities, precise target lists, and log hashes. Its SHA-256 is **`9fadc14f01ecbb99d6b379f54211108a7d32115175c0088fefbc55e3d8ca3c16`**. The before/after JSON inventories preserve individual file hashes; the dependency snapshots also preserve the locked declarations and resolved package paths. [artifact-inventory.json](artifact-inventory.json) lists each evidence artifact and its hash, excluding itself.

The earlier qualification in `../final-host-qualification` remains separate and unchanged. Its receipt still has SHA-256 `9c44b1a6580b961dba808df80e29c4d2cdb30fcaa6fac3e2dade4fb1bd84cbdc`. Earlier and current host test runs must not be added together as distinct tests. [preparation.json](preparation.json) records runner changes and the prior evidence identity; it describes the preparation state before this accepted run.

## Genuine harness and assets

The locked harness links its application and Office libraries to the actual CrispCloud checkout. It has the same three German notice asset entries as production:

- `packages/quds_office_engine/third_party/hyphenation/LICENSE`
- `packages/quds_office_engine/third_party/proofing/WORTLISTE_LICENSE`
- `packages/quds_office_engine/third_party/proofing/QUDS_WORDS_LICENSE`

The engine `third_party` directory and the license test are linked to the real host files. The license tests read the actual Flutter bundle, compare it with source bytes, verify license registry exposure, and compare the hyphenation notice against the complete source-header text. [harness-assets.json](harness-assets.json) preserves the original asset-only harness amendment and unchanged dependency-lock hashes. No new harness amendment or `pub get` was needed for this run.

## Reproduce

Restore immutable checkouts of the published CrispCloud and canonical Quds commits above. Restore the pinned SDK and original enforced harness locks using `docs/validation/zotero-continuation-20261116/setup/bootstrap-local-tests.sh` in the Quds repository. Add the three production asset entries above to the harness's `flutter.assets`, link the actual host engine's `third_party` directory, and link the actual `office_proofing_licenses_test.dart`, as recorded in `harness-assets.json`.

With the same workspace layout and a fresh output directory:

```sh
source /absolute/workspace/zotero-toolchain/env.sh
python3 run-expanded-host.py \
  --repo /absolute/workspace/CrispCloud \
  --harness /absolute/workspace/zotero-toolchain/crisp-host-harness \
  --quds-source /absolute/workspace/quds_office_suite \
  --source-commit 27f001d60777d27f412d9984b62dbdb05019b9eb \
  --quds-commit 8e017e8c148517fea61f8d55eaafc7f070b82bba \
  --output /absolute/workspace/new-host-qualification
```

The runner requires full commit identities, derives the expected host tree from the published commit, rejects dirty tracked qualification inputs, and refuses to overwrite existing receipt/input snapshots. It uses the existing locked dependency graph, executes only the recorded cohort and gates, captures before/after evidence, and restores the temporary host analyzer configuration on failure as well as success.

## Scope

This evidence covers focused local host behavior and analysis through a genuine locked dependency graph. It does not establish a full application compile or a fresh full production dependency resolution. Network, credentials, and desktop protocol interactions use test doubles. No live Zotero account/picker, Word/LibreOffice interoperability, or operating-system keychain acceptance is claimed. The concurrently integrated keychain features were not added to this host cohort. Canonical engine/editor runtime tests are qualified separately. No GitHub Actions, statuses, workflows, jobs, waits, or reruns were queried or used.
