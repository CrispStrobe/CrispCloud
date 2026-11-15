# Observed main 08296ed qualification

The explicit app source `41885d7d1d67348f5abe3579b99d9d2951fc909f` pins canonical parser `08296edbee08da013a8ff718798972552ccd03f7`. Compared with the last complete qualification evidence head `57442c79239fb4d483e274e0ebb04f34686beb6c`, exactly one of 1,832 tracked paths changed: `test/recovery_reconciliation_bounds_test.dart` gained 29 lines containing one additional typed compound-error recovery regression and its import. No existing assertion was removed or weakened. The other 1,831 paths, including every production/dependency blob and all other tests, are identical.

`source-equivalence.json`, `tracked-git-objects.json.gz`, and `observed-test-delta.patch` preserve the comparison. Resolved package lock/config/graph bytes and all recorded tool hashes also match the prior complete run.

## Fresh changed-suite gate

`changed-suite/` records **18 tests passed**, zero failures, errors or skips, at exact saved pin `08296edbee08da013a8ff718798972552ccd03f7`. Those 18 comprise the previous 17 reconciliation tests plus one added test. The gate snapshots confirm unchanged source, HEAD, resolution inputs and tools.

`strict-analysis/` records a clean strict analysis of the changed test file with fatal infos enabled, also on exact pin `08296edbee08da013a8ff718798972552ccd03f7`. It reports no issues, and source, HEAD, resolved inputs and tools remained unchanged. Both fresh gates are complete.

## Retained complete-run scope

The earlier **144-suite, 4,131-test full run** remains recorded in `../directory-all-parser-final/`. Its applicability to the unchanged runtime and other tests is established by exact Git blob/mode and resolution-input identity. The changed suite is freshly tested as above. No fresh complete 4,132-test run is claimed or performed for this additive test-only delta.

The app-facing source pin remains `08296edbee08da013a8ff718798972552ccd03f7`; newer receipt commits are tracked separately. No production code, dependency declarations, package resolution or app source was modified. No GitHub Actions run was awaited or polled.

Receipts are saved on `qualification/parser-observed-08296ed-20261115`. The prior integration branch was observed at `09a4a531a4aa210a638a220de45c9d53d44c84e1` during the publication lease check and was left untouched; its concurrent changes were not taken into this qualification scope.
