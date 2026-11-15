# Frozen integration return audit

## Result and current status

The single integration-branch observation is **`3e9560c9b4bd617b5346bacd8b5039493f0f2dc1`**. It contains a new spreadsheet comment serializer correction, additional regression coverage and evidence. It is not an evidence-only continuation of qualified source `966345971a50ef93bcb67ed32060c8176b4d2949`.

Root has since merged that observed state as pending at **`2083d2c2bdd53e9243e5f07fcc3b43a979559239`**. Its non-evidence tree is identical to the observed incoming tree: **True**. A concrete comment-ownership defect in canonical `4e8c8f80` is being corrected on a separate branch before final host qualification. This audit does not present the pending source as fully accepted.

## Exact source and pin differences

Only five non-evidence paths differ from source `96634597`:

- `packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart`: SpreadsheetML comment text/namespace output, actual relationship-target lookup and validation, shared-part handling and repeated-save deletion behavior.
- `packages/quds_office_engine/test/sheet_comments_namespace_test.dart`: new regression suite.
- `packages/quds_office_engine/tool/fidelity/comment_schema_fixture.dart`: new independent-reader fixture producer.
- `packages/QUDS_FORKS.md`: canonical pin and behavior documentation.
- `tool/office_fidelity_manifest.json`: canonical pin and managed-file identities.

The incoming source commit is `b99a31c5a8f92df48d52bb545c4d461d9e08afcd`. Quds changes from `9bb71983a4ae6bc7bb3372fd931e724ddd102fc8` to `4e8c8f80f206e93be8530a94da478e06c0f87608`; parser remains `08296edbee08da013a8ff718798972552ccd03f7`. Dependencies and committed locks are unchanged.

Canonical `4e8c8f80` has parents `fd14d8a68477165e7ca3317b647f403f2308e353` and `9bb71983a4ae6bc7bb3372fd931e724ddd102fc8`. The restoration commit is therefore an ancestor. All three restored ODS regressions already have identical bytes on both app branches; no test restoration is lost.

## Object-only merge proof

The common base is `6a5603236c9f3f9e186c5eb3ba5fd76a085b1df6`. A merge-tree simulation against saved receipt tip `b1af46116cdc6636ab602d78b54bf425e802eb1a` has exactly two content conflicts: `packages/QUDS_FORKS.md` and `tool/office_fidelity_manifest.json`. There is no managed source/test conflict.

Following root's decision to take the observed incoming versions of both conflicted metadata files, the proposal tree is `24a8e8a4ea1c9eeeb14f4b0f13364bf1514995d8`. Its complete non-evidence tree equals the incoming source. Every one of the **2,336** managed-file SHA-256 entries verifies, and all **111** current local-gate receipt paths from the simulated isolated tip remain byte-identical. `resolved-merge-tree-proof.json` and the raw merge-tree outputs retain the proof. The isolated scratch index created only Git objects; this agent made no merge commit, ref update, checkout or repository-index change.

## Existing incoming qualification

The incoming host tree contains exactly three complete, independently verified strict-analysis labels:

| Label | Files | Tested saved head |
| --- | ---: | --- |
| analysis-app-final | 76 | `b99a31c5a8f92df48d52bb545c4d461d9e08afcd` |
| analysis-engine-final | 19 | `3e764dc2f95e5d449782aefe3b63890ec03a2e9c` |
| analysis-editor-final | 6 | `564d88d45b71bc50ab9f3dc672c4b8ec9363d41d` |

All passed with stable 8,621-entry source/resolution snapshots, common digest `fac95c4fce0b6e6265be9112571e03915253c2391df235d7f1beaec4f7a439b0`, and source trees equal to observed `3e`. All 21 compressed members and inner indexes were verified. The Dart binary and recorder match this workspace; the gate runner/environment differ, and six config/graph entries differ. Relevant lockfiles are byte-identical. These are valid source-bound incoming-workspace passes, not a complete final host cohort or automatically interchangeable snapshot.

No final CLI analysis, app/engine/editor runtime, source-integrity, portable PNG, navigation, scripted Office oracle or comments oracle receipt appears under that incoming final-receipts base. The incoming checkpoint status explicitly leaves final host qualification pending. A three-test native bootstrap is on earlier `41885d7d` and is setup scope.

Canonical comments evidence records 139 tests across eight suites, three-file analysis and a three-cycle openpyxl/XML oracle on earlier `25c373626368c4a800dbaff2024c7972ba8a6e50`. Its serializer and test bytes differ from `4e8c8f80`; the app also retains a two-case focused decoy review at `fd14d8a6`. Preserve those recorded scopes. They are not a complete final host run on the new merged source.

## Verified parser full-run scope

The app references existing parser evidence `09a4a531a4aa210a638a220de45c9d53d44c84e1`. Its exact raw archive was independently audited: **4,132 passing visible tests across all 144 suites**, no failures/errors/skips, plus clean strict analysis of 18 files, all on exact source `08296ed`. The 144 hidden loader tests are excluded. All 32 archive members, 23 inner-index entries, 937 tracked non-evidence files and stable 949-entry snapshots verify. The lock and SDK binaries match locally; graph nodes normalize identically despite workspace/serialization differences.

The complete copy-ready linkage bundle is `parser-09a4/`. Retain our earlier 18-test/one-file records at `84264525` and earlier 4,131-test run at `57442c79` unchanged, and exclude their overlapping counts from additional totals.

## Scope boundaries

There was one integration-ref observation, frozen at `3e`. Exact canonical `4e8c8f80` and parser evidence `09a4a531` materialization were separately authorized by root as already-observed references. No broad branch/PR refresh or CI observation occurred. Root advances its own evidence heads between completed gates; this agent used immutable comparisons and did not alter active worktrees or dependencies.
