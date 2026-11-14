# Ribbon style history baseline — 2026-11-14

Both focused host cases reproduced their intended failures on app `bd910b1454e30afd1793ea20ae3977821bf5cdb2`, with the original app `_CellStyleCommand`. All 4,742 recorded inputs remained unchanged and the SQLite helper restored `pubspec.yaml`. The five-case worksheet-state test was not changed or rerun.

The first case selected Budget A1:D1 and clicked the actual Bold control. Its first real upload passed the native fill, font and cell-content checks. After navigating to Reference through the public controller, the real Edit → Undo and toolbar Save left Budget!A1 bold. The test failed at that persisted target-ownership assertion.

The second case applied Bold and then Undo on Budget. All four modeled bold flags returned to false, and a real toolbar Save completed. The saved A1 gradient was replaced by `patternType="none"`, so the case failed at the native-fill assertion. Neither case reached Redo. These are product failures, with no finder or fixture-compilation failure in this attempt.

## Additional inspection of the captured bytes

`inspect_style_baseline.py` reads the retained ZIP/XML directly, without Quds or package rewriting. Its hash-bound `attempt-1/native-inspection.json` additionally records:

- The cross-sheet Undo changed Reference's native styles and colors while Budget remained bold.
- In the same-sheet Undo upload, Budget B1's dark-grid pattern became a solid black fill.
- Budget's native font `theme="4" tint="0.25"` became explicit `rgb="FF7BA1CE"` after Undo.
- C1's explicit `s="0"` and D1's omitted style became generated style overrides `s="8"` and `s="9"`.

These are observations of the exact saved files, separate from the reached test assertions. The later font/style/model-provenance assertions were not reached after the fill failure. In particular, this does not establish a separate defect in the `hasExplicitStyleIndex` model flag.

The directly authored source keeps the independent seed and native fill definitions, adds native font theme/tint metadata, explicit and implicit style-zero cells, and a distinct Reference worksheet. It never passes through the Quds writer. `schema-source/` retains its passing OpenXML SDK 3.3.0 validation and preceding validator self-test, including the exact source hash `ce064557d720146d4184e441e1c0d1aaa73ef05eb41964493cad660eb25ed466`.

## Retained evidence and replay

`attempt-1/` contains the full native test log, exact command/environment, source hash map, compressed changed test and generated dependency/config bytes, committed/collected pubspec views, four emitted workbooks, and the failed collection's compressed raw LCOV. No successful collection receipt or coverage percentage is claimed.

`run_validation.py` retains the capture harness, `environment-source-receipt.json` its environment recipe, and `native-launchers/` the task-local compiler wrappers. `replay_recorded_run.py INPUTS_JSON CHECKOUT FRESH_BUILD_DIRECTORY` verifies the full recorded input map before replaying the exact command in a prepared checkout. The recorded dependency/toolchain paths describe the actual workspace rather than a hermetic or portable environment.

Only worksheet navigation uses `setActiveSheet`, because this host has no worksheet selector. Styling, Undo/Redo and Save use actual controls. The following positive run must complete both cases, including Redo, and emit all six declared style-history artifacts. `manifest.json` binds every retained file in this baseline bundle.
