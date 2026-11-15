# Incoming Office source review

Reviewed source: `e0221c2034cf56cac6c9566c8ff7b65ed41518a2`.

Scope: the incoming ODF service, ODS reader, Office editor routing, and their tests. This was a read-only source review during the source-integrity gate. No package resolution, compilation, or test execution was performed. The duplicate `odfTests()` declaration has been removed. The referenced ODS export, workbook/style APIs, and sheet-controller construction APIs are present in the combined source.

## 1. Repeated empty rows can discard later ODS data

**Definite source defect; not yet runtime-tested.**

- Engine: `packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_reader.dart:151-152` executes `break` whenever a row has no content and `number-rows-repeated > 1`, before advancing `rowIndex`.
- App preview: `lib/services/office_document_service.dart:903-904` executes `continue` for the same case, omitting those rows from the CSV/table position.
- A table containing a value in row 1, an empty row repeated twice, and a value in row 4 therefore loses the final value entirely in the editable engine model; the preview shifts it to row 2.
- The condition does not inspect whether the empty run is actually trailing. ODS input can encode internal blank runs with the same repeat attribute. The importer already tracks explicit row positions, so this is not an intentional model limitation.

Required regression: an internal two-row blank run followed by a nonempty row and a formula referencing that row. Preserve the later cell at A4 through import and XLSX serialization. Only proven trailing padding should be omitted; bounded skipping must still advance the logical row index.

Source: [engine reader](https://github.com/CrispStrobe/CrispCloud/blob/e0221c2034cf56cac6c9566c8ff7b65ed41518a2/packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_reader.dart), [app extraction](https://github.com/CrispStrobe/CrispCloud/blob/e0221c2034cf56cac6c9566c8ff7b65ed41518a2/lib/services/office_document_service.dart).

## 2. Covered cells after a horizontal merge count the span twice

**Definite source defect; not yet runtime-tested.**

- Engine reader lines 124-148 advances the column by the origin cell's entire span, then advances again for each `covered-table-cell`.
- App extraction lines 878-897 inserts span padding and then also inserts each covered cell.
- For a row containing an origin spanning A:B, one covered-cell placeholder, and numeric value 7, both implementations place 7 in column D rather than C. The app yields `Wide,,,7` rather than `Wide,,7`.
- The checked-in `packages/quds_office_engine/test/fixtures/fidelity/legacy-sheet.ods` directly confirms the origin-plus-covered encoding: its Data row 8 contains a two-column merged origin, a covered-cell placeholder, then an ordinary cell.
- Existing engine tests assert the merge but place no nonempty value immediately after it. The app's synthetic merge test omits the covered-cell placeholder, so it does not cover the actual fixture encoding.

Required regression: retain the covered-cell placeholder and add a nonempty cell after it; check both CSV position and engine cell reference before and after XLSX serialization. Each physical covered position must be consumed once.

Source: [existing engine regression](https://github.com/CrispStrobe/CrispCloud/blob/e0221c2034cf56cac6c9566c8ff7b65ed41518a2/packages/quds_office_engine/test/ods_sheet_reader_test.dart), [existing app regression](https://github.com/CrispStrobe/CrispCloud/blob/e0221c2034cf56cac6c9566c8ff7b65ed41518a2/test/office_document_service_test.dart).

## 3. Formula translation changes quoted string contents

**Definite source defect; not yet runtime-tested.**

`OdsSheetReader._translateFormula` applies `replaceAll(';', ',')` to the entire formula at lines 335-337, including quoted string literals. For example, the ODF formula `of:="a;b"` becomes the XLSX formula `"a,b"`; the intended string value has changed. Its regular-expression reference rewrite also operates without a quoted-string boundary, so literal bracketed text can be rewritten.

Required regression: a formula containing a quoted semicolon and a formula containing literal bracketed reference-like text. Translate argument separators and reference syntax only outside quoted strings, preserving escaped double quotes.

## Verification boundary

These findings are source-derived and do not claim that the existing suites were run or failed. Engine changes belong to the canonical Quds source and should retain the managed-source synchronization and manifest requirements. No source, fixture, manifest, or workflow was modified by this review.
