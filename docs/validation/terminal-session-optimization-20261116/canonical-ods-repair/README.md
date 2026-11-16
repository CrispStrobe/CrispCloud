# ODS tab colour and picture integration correction

Canonical parent: `18c76e886623ae3be9a41addd80e7f6837c2d3b0`.
Continuation branch: `codex/terminal-integration-ods-20261116`.

The newly integrated worksheet tab-colour serializer emitted `sheetPr` before
adding the worksheet drawing relationship namespace. When a worksheet contained
both a tab colour and a picture, the namespace write happened after the root
start tag closed and save threw `StateError`. The correction writes the root
namespace before emitting any worksheet children.

The combined ODS colour/picture regression imports an actual package, saves it
as XLSX through `OfficeIsolateSave`, reopens it, and checks the colour, picture
bytes and dimensions. The existing `imageTests()` group had not been called
from `main`; registering it restores its previous plain-picture regression
alongside the new combination case. No existing assertion was weakened.

## Local qualification

- Unchanged production source plus the registered new regression fails with
  `Attributes can only be written on an open start tag`.
- The corrected complete ODS suite passes **91 tests**, with zero skips or failures.
- Analysis of both changed files passes; formatting reports zero changes.
- The canonical workspace resolves normally with its existing declarations.
  No production or test dependency constraint is changed and no substituted
  package graph is used. The generated lock is preserved here.

Run commands from `packages/quds_office_engine` after resolving the workspace:

```sh
dart test --concurrency=1 --reporter=expanded test/ods_sheet_reader_test.dart
dart analyze lib/src/sheet/serial/sheet_serial.dart test/ods_sheet_reader_test.dart
dart format --output=none --set-exit-if-changed lib/src/sheet/serial/sheet_serial.dart test/ods_sheet_reader_test.dart
```

`receipt.json` records exact executed commands, runtime versions, input hashes,
resolution details and separate setup diagnostics. Its sibling logs preserve
the baseline failure and fixed qualification. These are local results; no
GitHub Actions jobs were queried, awaited or rerun.
