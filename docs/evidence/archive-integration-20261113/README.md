# Combined archive integration evidence

This directory retains exact-source results for the continuation described in
[the reconciliation guide](../../recovery/archive-integration-20261113.md).
The original 12 branch heads and 89 PR heads are recorded separately from
later implementation and evidence checkpoints.

**Final qualified runtime:** `a065ee6e7c2aa18574a72ac6232d4d01845bdee9`.
Its merged app gate, canonical-source qualification and JavaScript release build
passed. Later commits contain evidence and documentation only.

## Initial combined gate

`baseline-receipt.json` records candidate
`5d0814fdf8dfa2257e3000d1d3e3792864a4901e` and tree
`a607513135a1aa5515dee19caa773a73fe41b556`. All dependency, source, help, strict
analysis, portable JavaScript and independent ISO/DMG gates passed. The 165-file
Flutter run finished with **3,107 passing tests, one failing test and 13 explicit
large-archive opt-in skips**. This initial run is retained as a failure rather
than being relabeled after a later correction.

The failure was `changed sources require explicit exclusion and fit narrow
windows` in `transfer_history_dialog_test.dart`. A fixed scroll distance moved
the checkbox under the dialog title, so its tap missed and the completion action
never appeared. The same failure reproduced in isolation, without a layout
overflow. Follow-up verification must retain the narrow viewport, an actual
checkbox tap, the explicit-exclusion requirement and both source/destination
content assertions.

`baseline-test-files.txt` and `baseline-analysis-inputs.txt` preserve the complete
selected file sets. `baseline-logs.tar.gz` contains the original command logs and
machine-readable test events; `baseline-logs.json` records all hashes. Generated
JavaScript and reproducible fixture binaries are omitted from the log archive.

The local native profile used verified Clang, SQLite and pinned libsmb2, plus
real installed 7-Zip 23.01/RAR 7.23. Independent disk-image checks used 7-Zip
26.06. The optional native ebook hook was disabled only during the local Flutter
test command; both manifests were restored byte-for-byte and the tested worktree
was clean afterward. The receipt includes the precise tools, commands, source
pins, skip identities and all results.

## Source attribution

Subsequent implementation checkpoint `e2d48cae` fixes encrypted split-7z member
reads after password acceptance. Candidate `67cd81fe` also pins canonical ebook
reconciliation `a18b93c1`; its runtime, package, test and CI bytes equal the
baseline's ebook pin `ac9925c4`, with only two upstream documentation files
different. The shared dependency was merged through
[Crisperbooks PR #1](https://github.com/CrispStrobe/crisperbooks/pull/1) at
`505d3d7bfb922e5f0d77b7230cd38b0e266d0606`, whose tree equals `a18b93c1`.

The exact parser qualification remains in the separate
[parser receipt](../parser-lineage-integration-20261113/README.md). Historical
and focused test counts overlap and must not be summed as a single run.

## Passing follow-up before concurrent main advanced

`pre-main-receipt.json` records `09cb60be` with **60 passing tests and no
failures/skips** across the archive viewer, spool lifetime, transfer recovery
and operations-localization suites. It includes the corrected narrow-window
interaction and all three new split-password regressions. Strict analysis,
dependency resolution and Office/document/ebook/technical-inventory checks
passed. Manifests were restored exactly and the worktree was clean.

The standard JavaScript release build passed using the original production
manifest, `APP_VERSION=1.2.9+22` and `GIT_HASH=09cb60be`. Those values were verified
in the resulting JavaScript. The optional Wasm dry run was disabled; no Wasm
qualification is claimed. `pre-main-logs.tar.gz` and its JSON hash manifest retain
the original logs and test events.

During this build, app main advanced to `e13fb727`, already incorporating the
earlier `5d0814fd` archive checkpoint and adding newer canonical parser/Quds
sources and viewer/pane improvements. Genuine merge `a065ee6e` preserves both
histories. Its affected UI and document paths require a separately attributed
gate and build; the passing `09cb60be` result is not relabeled as that result.

`historical-ci-triage.json` records the earlier localization-assertion failure
and unrelated iOS source-download failure, with exact job links and revision.

## Final merged qualification

`final-receipt.json` qualifies `a065ee6e` and source tree
`1338fc761f25271a9b8139c3bca4499263d46302`. All **173 tests across 15 app files
passed, with no failures or skips**. The selected paths cover incoming image
choices, empty-folder navigation, syntax/editor behavior, archive passwords and
reader ownership, legacy Word previews, Office PDF/font bridges, transfer
recovery, localized operations and spool cleanup. The corrected narrow-window
case and new split-password regressions are included.

Dependency resolution preserved the lockfile. Source guards verified **1,925
Office files, 158 document-runtime records and 283 resolved ebook files**;
technical inventory checks passed. The expanded app analyzer had **no errors or
warnings** and seven inherited style infos. Exact blame and the initial strict
diagnostic are retained, along with the rejected CLI-option attempt before the
successful errors/warnings-fatal invocation. This expanded result is not labeled
fatal-info clean. The earlier strict archive and focused viewer results retain
their original source/scope.

The production-manifest JavaScript release build passed in 210.160 seconds:

```sh
flutter build web --release --no-pub --no-wasm-dry-run \
  --dart-define=APP_VERSION=1.2.9+22 \
  --dart-define=GIT_HASH=a065ee6e
```

Both identifiers were verified in the output. `main.dart.js` is 27,494,207 bytes,
SHA-256 `e67f6a33256db81ce676e0c69b7fb682d45afd86453c3b6238f6ae8804af8da0`.
The complete web output has 245 files totaling 111,121,998 bytes. Manifests were
restored byte-for-byte and the validation worktree was clean.
`final-logs.tar.gz` and `final-logs.json` retain raw logs, machine test events,
diagnostic attempts and their hashes. This is a build result, not deployment,
browser execution, WebAssembly or native-device acceptance.

The [new canonical qualification](canonical-qualification/README.md) separately
records **1,422 parser tests, 184 Python controls, 18 actual compiled-JavaScript
acceptance groups, 16 Quds/app host tests and seven engine conversion tests**.
They use parser `0f9f085f`, Quds `05a581de` and the app's locked `archive 4.6.0`
runtime graph. Strict parser/changed-editor analysis and immutable-source checks
passed. Its compact archive retains the real narrow bilingual-menu/font probe,
runtime-resolution mappings and all setup attempts. Earlier native/golden/Mac
Chrome acceptance remains attributed to its original source.

`qualified-ancestry.json` verifies that all **12 original branch heads, 89
original PR heads and concurrent main `e13fb727`** are ancestors of the qualified
runtime revision. These source and test receipts deliberately preserve their
individual scopes; overlapping counts are not a synthetic whole-suite total.
