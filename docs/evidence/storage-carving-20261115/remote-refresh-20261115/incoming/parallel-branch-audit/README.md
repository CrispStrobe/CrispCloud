# Concurrent incoming branches — read-only audit

Three new branch heads were fetched into isolated bare audit clones. Canonical app, Quds and parser checkouts, indexes and refs were not modified by this audit. All fetched tips matched the supplied immutable SHAs. Initial main tips were outside this task's refresh scope. No GitHub Actions call was made.

## Incoming changes and merge results

| Repository | Incoming branch / head | Unique delta | Audited merge base | Result |
| --- | --- | --- | --- | --- |
| CrispCloud | `integration/storage-carving-local-20261115124645` / `6a5603236c9f3f9e186c5eb3ba5fd76a085b1df6` | One commit, 13 evidence paths only | `41885d7d1d67348f5abe3579b99d9d2951fc909f` | Clean scratch merge with app `7d0de79eeb5932e355e66af0be073d58f9fcf3c4`; zero product differences |
| Quds | `integration/ods-regression-restore-20261115T1246` / `9bb71983a4ae6bc7bb3372fd931e724ddd102fc8` | One commit, one test file, three restored cases | `6e4c3b16b4310f2c21b6d8b5e412af9850eb17ea` | Clean scratch merge with Quds `9d1f6755a21c5d9936fd89532a4ebdbb510e9a2d`; only the ODS test file changes |
| Parser | `qualification/parser-observed-08296ed-20261115` / `84264525417b924476af3a9c8cfa9bbe19b6437b` | Two commits, 21 new evidence files only | `08296edbee08da013a8ff718798972552ccd03f7` | Clean scratch merge with parser `09a4a531a4aa210a638a220de45c9d53d44c84e1`; zero product differences |

`merge-simulations.json` records all merge-tree commands, exact resulting tree IDs, exit codes and complete path inventories. These simulations wrote only Git objects in the isolated audit clones.

## Quds regression detail

The incoming change adds 93 lines exclusively to `packages/quds_office_engine/test/ods_sheet_reader_test.dart`, inside the existing `defaultAndTimeTests()` group invoked by `main`. It restores three cases:

1. `currency symbols survive namespaced import and XLSX saves`: ignores a wrong-namespace currency symbol and preserves positive/negative USD and EUR formatting through export/import.
2. `inherited styled padding stays sparse while explicit blanks survive`: repeated inherited padding remains sparse, default row heights stay implicit, and two actual cells retain inherited font and explicit blank-cell fill through roundtrip.
3. `ODS native column geometry survives a new XLSX copy`: preserves a single explicit width and the 81 px implicit native column default through roundtrip.

There is no production-code change. Preserve all newer comments namespace, relationship ownership, and cleared-note fixes in our branch. The actual three-way merge does so; replacing whole files from the older incoming tree would discard those newer changes. Run the existing ODS suite on the merged source; the three restored cases are included automatically and add no new suite path. `ods-regressions.patch` contains the exact patch.

## App historical evidence scope

All 13 incoming app paths are under `docs/evidence/storage-carving-20261115/local-resume-20261115T1150/`. The change updates its README and adds the final acceptance index, four independent-review files plus their manifest, concurrent-main closure, final incoming closure supplement, and saved visual-review records. The JSON audit contains every exact path.

These records explicitly qualify historical source `20ee83ff965d5433aeb528ae84debdb304edcf4a` and source-identical descendants through `137c95de`. They explicitly mark that scope superseded for current-branch acceptance once `41885d7d` changes source. Keep this scope labeling. The historical primary total is 1,253 app/Office tests (903 app + 249 engine + 101 editor); it must not be represented as fresh qualification of the current joined source.

The new independent-review manifest's four files verified. Its references to 16 prior artifact indexes and 160 artifact files also all verified by exact bytes, sizes and SHA-256 using immutable incoming Git objects. The linked current-refresh README exists. `app-evidence-audit.json` records these checks. Saved visual-review claims were preserved; this audit did not repeat visual inspection or runtime execution.

## Parser evidence scope

All 21 incoming parser files are under `doc/evidence/storage-carving-reconcile-20261115/observed-main-08296ed/`. Both new gates ran at exact source `08296edbee08da013a8ff718798972552ccd03f7`:

- The changed `recovery_reconciliation_bounds_test.dart` suite: 18 tests passed, no failures, skips or errors; raw machine events independently confirm 19 start/end pairs including one hidden loader event and one successful final done event.
- Strict analysis of that changed test: exit zero, no issues.

Both gates have equal before/after snapshots covering 1,844 recorded inputs and equal tool identities. The top-level index verifies 20 files; nested gate indexes also verify. All 34 indexed checks pass (nested counts overlap the top-level files).

The exact comparison from prior full-run evidence head `57442c79239fb4d483e274e0ebb04f34686beb6c` to source `08296ed` changes only `test/recovery_reconciliation_bounds_test.dart`; this audit verified that Git delta. The incoming documentation therefore retains the older 4,131-test full run with a fresh 18-test changed-suite gate and explicitly makes no fresh 4,132-test full-run claim. Preserve our independent fresh full-run evidence at `09a4` alongside it. Do not add repeated focused tests to full-run totals.

## Pull requests and preservation

Both exact-head GitHub searches and direct REST pull-list calls with `state=all` returned no PR for any of the three branches. `pr-checks.json` records the direct exact-head queries and empty responses. Existing unrelated/draft PRs were not modified.

Use history-preserving merges of these heads after source freezes release. All three were clean in the scratch merge simulations, with no incoming deletions or production changes. At the final read-only ancestry check, the parent had already integrated all three heads into the local checkouts; `end-of-audit-ancestry.json` records the then-current heads and positive ancestor checks. Remote publication remains the parent's checkpoint verification step.
