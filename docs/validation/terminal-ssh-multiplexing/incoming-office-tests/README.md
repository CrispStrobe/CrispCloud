# Targeted incoming Office regression acceptance

This directory preserves focused post-merge checks for incoming ODS numeric,
date, and text-length validation support. The three-file cohort exercises the
ODS reader, shared validation model, XLSX serializer/deserializer, and the
application's ODS edit-and-save-copy workflow. It is not full Office
qualification.

## Recorded result

The [post-merge attempt](post-merge/receipt.json) passed **116 tests, with zero
failures and zero skips**, on integrated source
`2ca566a3a386b5876274d36ff7d93ea21c93fa80`. The full command completed in
**52.507 seconds**. Its [complete log](post-merge/run.log),
[source inventory](post-merge/source-before-sha256.json), and
[exact adapter diff](post-merge/adapters.patch) are retained.

All **5,544 watched source hashes** matched before and after the run. Both
original engine tests, both ODS fixtures, the original host test, production
manifests and package configuration, the vendor manifest, and generated adapters
also retained their recorded bytes and modes. The script used the existing
production graph and normal native hooks. No dependency resolution ran.

## Production graph and test-only adapters

The two engine test files import `package:test/test.dart`, which is absent from
the application's production package configuration. The ODS test also eagerly
loads two fixtures using paths relative to the engine package directory.

[run.py](run.py) preserves the vendored tests and fixtures. It creates temporary
copies under `build/office-incoming-tests/` using only these substitutions:

1. In both copies, replace the single `package:test/test.dart` import with
   `package:flutter_test/flutter_test.dart` from the application's existing graph.
2. In the ODS copy, prefix the two existing `legacy-sheet.ods` and
   `legacy-sheet-edge.ods` fixture paths with `packages/quds_office_engine/`.

Every substitution must occur exactly once. The script reverses the declared
substitutions and verifies that they recover every original byte. It preserves
the exact adapter diff, original/adapted hashes, fixture identities, production
manifests and package-configuration hash. Assertions and fixture bytes remain
unchanged. The existing host test executes directly from its original path.

## Reproduction

Run from the repository root after integrating the incoming changes and
resolving their canonical vendor pin:

```sh
python3 docs/validation/terminal-ssh-multiplexing/incoming-office-tests/run.py \
  --expected-head FULL_INTEGRATED_COMMIT_SHA \
  --label post-merge \
  --run
```

Omit `--run` to prepare adapters and provenance without invoking the SDK.
The expected commit must match the current HEAD. Each label creates a new
evidence directory; an existing directory is refused so earlier attempts and
their logs cannot be overwritten. `--toolchain-wrapper` may select another
existing environment wrapper; the default is `../toolchain/run`.

The recorded command executes the equivalent of:

```sh
../toolchain/run flutter test --no-pub --concurrency=1 --reporter=expanded \
  build/office-incoming-tests/ods_sheet_reader_test.dart \
  build/office-incoming-tests/sheet_formula_test.dart \
  test/widget/ods_editor_workflow_test.dart
```

No package resolution, dependency override, fixture rewrite, native-hook
disablement, GitHub Actions query, or CI wait is involved. Full combined
stdout/stderr is retained in the attempt's `run.log`. A `.log` file may need
explicit force-add because the repository ignores log files.

## Source identity and acceptance boundary

Each attempt records its source HEAD and working-tree status, plus an inventory
of the same production/test source categories used by the terminal acceptance
runner. The script compares that inventory after the command and separately
checks both original tests, the fixtures, the host test, manifests, production
package configuration, vendor manifest, and generated adapters. Passing requires
a successful test result with no changes to these recorded inputs.

The upstream ODS regression covers four validation kinds, their selected bounds
and comparison operators, XLSX operator attributes, and reopening. Existing ODS
tests cover list validation and source-range work limits; the formula suite
covers validation through `SmlAnalysis.validateInput` and direct XLSX saving.
The host workflow checks editing, readable copy creation, source preservation,
and canceled or superseded save outcomes. This cohort does not establish every
operator edge case, arbitrary malformed numeric/date input, external-application
interoperability, or comprehensive Office fidelity.

Result counts belong to the individual attempt receipt; the recorded result above
summarizes that targeted execution without claiming full Office qualification.
