# Excel fidelity audit — 14 November 2026

The spreadsheet side of the Office work was measured against Microsoft Excel
16.100 on 787 private workbooks (776 `.xlsx`, 9 `.xls`, 2 `.xlsm`, 179 MB).
The harness, recipes and full write-up live in
[CrispStrobe/excel-steering](https://github.com/CrispStrobe/excel-steering);
private workbooks and converted copies never enter a repository.

## What was measured

| Path | Median fidelity | Note |
| --- | ---: | --- |
| Quds open → save | **1.000000** | 35 sampled workbooks, no edits |
| Excel open → save (baseline) | 0.9995 | shows comparator noise |
| Legacy worker `.xls` → `.xlsx` | **0.722** (min 0.055) | display grid only |

The legacy path is a **preview reader**, not a conversion path:

- values are rendered strings (`" 204,392.00 € "`), so numeric types and
  number formats are gone;
- formulas are absent entirely (0/19,629 preserved);
- number formats, defined names, validations, conditional formats, pivots,
  charts and print settings never cross its API boundary;
- hard limits: 100k rows, 512 columns, 1e6 cells, 32 MiB, 30 s. A 5 MB
  workbook is rejected outright (`worksheet layout limit exceeded`).

CrispCloud has no `.xls` writer and Quds has no BIFF reader, so legacy Excel
must be converted on import. That policy should stay explicit in the UI.

## Defects fixed in the Quds fork

Pinned at `5d57de3bff3fd8946936220b8983addc2ce0c638`:

1. cell comments wrote an invalid `CT_Comments` part (no `<authors>` /
   `<commentList>`, wrong content type, missing relationship);
2. every save recalculated formulas with the approximate evaluator, silently
   changing native caches;
3. frozen panes were anchored on positional `xSplit` instead of `topLeftCell`,
   and `frozenSplit` was ignored;
4. authored custom number formats referenced `numFmtId` values that were never
   written as `<numFmts>` entries.

Each has a regression test in `packages/quds_office_engine/test/` and is
recorded in [`packages/QUDS_FORKS.md`](../packages/QUDS_FORKS.md).

## Residual

- Character-based column widths differ from Excel by ~0.12 character units
  (~1 px): Excel's unit comes from a per-workbook font measurement the
  headless engine cannot make. Recipes should use `points`/`px` when exact.
- Excel stores a formula entered into a Text-formatted cell as literal text;
  Quds always writes a formula. Set `General` first in recipes that compute.
- The preview's hard failure on large sheets should become a bounded window or
  an explicit "preview unavailable" state.

Re-run a stage at any time from the harness; work is keyed by content hash and
resumes where it stopped.
