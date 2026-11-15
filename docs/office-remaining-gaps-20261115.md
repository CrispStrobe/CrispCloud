# Office viewer/editor remaining gaps — 15 November 2026

This is the current backlog for the Office/ODF work. It records what is
verified, what is intentionally read-only, and what remains before the viewer
and editor can claim full format coverage.

## Verified state

- CrispCloud `main`: `01f7fc77`
- Vendored Quds source: `b01455fa415f9411411d06c7c2ab66947630af1a`
  (`packages/QUDS_FORKS.md`, 2,363 managed files)
- Quds sheet/ODS cohort: **495 tests**
- CrispCloud vendored ODS reader: **80 tests**
- CrispCloud combined F3/F4/ODF suite: **51 tests**
- ODT parser/image suite: **37 tests**
- Live corpus smoke tests: **20 ODF**, **9 XLS**, **1 ODS**
- Live ODS → XLSX fidelity against LibreOffice: **0.9981**
  (2,098 compared fields; no data, formula, format, alignment or geometry
  mismatches in the measured BOM workbook)
- Golden checks: exact macOS and Linux references; the last completed
  `office-fidelity` and `quds_office_editor` runs succeeded
- No private workbook corpus is tracked. Local-only tests read `$HOME` at
  runtime and skip when the directories are absent.

## Closed in this cycle

- ODS preview grid with typed values, formulas, formats, comments, pictures,
  hidden rows/columns/sheets, and a Table fallback.
- `.xlsm` and `.xltx` editing with VBA/template package preservation and signed
  package refusal.
- ODS pictures as worksheet drawings; ODS default Normal font, default column
  width and row height.
- ODS conditional formats: numeric comparisons, between/not-between,
  contains-text, begins/ends-with, duplicate, with generated dxf fill/font.
- ODS literal list validations and correct Excel list formula quoting.
- ODT named styles from `styles.xml`, inline pictures, text boxes, header/footer
  text, tables, lists and footnotes.
- Exact host goldens for the reviewed Word pages.

## Remaining backlog

### OG-01 — `.xlsb` editing

**Status:** Open / blocked on format work\
**Impact:** `.xlsb` remains available for preview and Source/Hex only.\
**Next step:** A BIFF12 reader/writer or an explicit, reviewed conversion path.
Do not approximate BIFF12 with the BIFF8 reader.\
**Acceptance:** open a real `.xlsb`, edit values/formulas/styles, save, and reopen
in Excel with the same sheet/cell content and no package-type change.

### OG-02 — ODS conditional-format breadth

**Status:** Partial\
**Covered:** `>`, `<`, `=`, `>=`, `<=`, `<>`, `between`, `not-between`,
`contains-text`, `begins-with`, `ends-with`, `duplicate`.\
**Remaining:** arbitrary expression rules, top/bottom rules, color scales, data
bars, icon sets, date/time conditions, and non-contains text conditions.\
**Next step:** extend `SmlConditionalRule` with the missing kinds or preserve
native ODS rule XML without a modeled projection.\
**Acceptance:** import and paint each supported rule family, save a valid XLSX
cfRule + dxf, and reopen in Excel.

### OG-03 — ODS data-validation breadth

**Status:** Partial\
**Covered:** literal `cell-content-is-in-list(...)` with `allow-empty-cell`.\
**Remaining:** range-source lists, whole/decimal/date/text-length/custom
conditions, input prompts, error titles/messages, error styles, and cross-sheet
ranges.\
**Next step:** retain validation definitions until all sheets are built so
range sources can be resolved, then map ODF conditions to
`SmlDataValidationKind`.\
**Acceptance:** list, numeric and date rules survive ODS → XLSX, with the same
source ranges, bounds, blank policy and messages.

### OG-04 — ODS workbook metadata

**Status:** Partial\
**Remaining:** named expressions/defined names, autofilter/database ranges,
print areas and repeat titles, sheet tab colors, row/column outline grouping,
cell hyperlinks, and several page-style properties.\
**Next step:** add the corresponding model fields or preserve/rebase native
ODS metadata.\
**Acceptance:** an ODS with each feature opens, saves as XLSX, and reopens with
the feature intact and no unrelated data movement.

### OG-05 — ODS package/theme parity

**Status:** Cosmetic / comparator-visible\
**Current:** Quds writes `sheet1_drawing.xml`/`sheet1_image1.png` where
LibreOffice writes `drawing1.xml`/`image1.png`, and ODS has no theme part to
copy.\
**Impact:** the visual/data result matches; only exact package-part names and
the theme part differ in the fidelity report.\
**Next step:** either normalize drawing/media names and synthesize a minimal
theme, or normalize package-part identity in the audit comparator. Do not hide
real semantic differences.\
**Acceptance:** package comparison distinguishes semantic content from
arbitrary part names.

### OG-06 — ODT embedded pictures

**Status:** Partial\
**Current:** supported raster pictures are embedded as data URIs, capped at
2 MiB total; larger/unsupported media remains a textual marker.\
**Remaining:** larger images, image positioning/cropping, captions, linked
images and vector formats.\
**Next step:** move from data URIs to a bounded image registry with a viewer
image builder, so the 4 MiB Markdown cap no longer limits pictures.\
**Acceptance:** a multi-image ODT renders every supported picture without
leaking payloads into plain text/search.

### OG-07 — ODT/ODP writers

**Status:** By design / not planned in the current editor\
**Current:** ODT and ODP are read-only previews; ODS edits save a new `.xlsx`
copy and leave the `.ods` untouched.\
**Next step:** only start if in-place ODF editing is a product requirement; it
is a serializer project, not a small gap.\
**Acceptance:** preserve unknown XML, styles, metadata and drawings through an
edited round trip.

### OG-08 — ODP slide fidelity

**Status:** Partial\
**Current:** page size, frames/custom shapes, text styles/colors, fills,
images, backgrounds and speaker notes.\
**Remaining:** transitions/animations, charts, embedded objects, tables as
tables, master/placeholder inheritance, and some grouped-shape geometry.\
**Next step:** add native shape/table/chart models or preserve untouched native
slide XML around edited text.\
**Acceptance:** a real deck reopens with unchanged layout and media after a
text-only edit.

### OG-09 — XLSX/XLSM F3 preview route

**Status:** Deferred / product decision\
**Current:** File Viewer renders F3 for OOXML sheets; F4 editing uses Quds.
XLS/ODS use the Quds grid with a fallback.\
**Next step:** decide whether the File Viewer grid or the Quds grid is the
default for `.xlsx`. Do not add a third inconsistent route casually.\
**Acceptance:** one documented default and one explicit fallback for every
spreadsheet family.

### OG-10 — `.xls` BIFF residuals

**Status:** Partial\
**Remaining:** NAME-token formula names, shared-formula edge cases beyond the
covered corpus, and character-width precision from native font metrics.\
**Next step:** resolve the BIFF NAME table and add targeted fixtures. Do not add
a BIFF writer.\
**Acceptance:** the residual `.xls` oracle cases match Excel’s own
`.xls` → `.xlsx` conversion.

### OG-11 — Qualification/CI operations

**Status:** Operational\
**Current:** exact host goldens; Linux references are authoritative for CI. The
full editor suite has older macOS/Linux page-golden differences outside this
work, and GitHub Actions has periodically left runs queued.\
**Next step:** keep host references per platform; investigate runner capacity
separately from product failures. Do not relax exact comparisons to hide host
rasterization.\
**Acceptance:** CI failures name an attributable regression or a known
host-reference mismatch.

## Suggested order

1. OG-03 and OG-04 for spreadsheet metadata completeness.
2. OG-02 conditional-format breadth.
3. OG-06 ODT image registry.
4. OG-08 ODP fidelity.
5. OG-01 `.xlsb` only if editing is required.
6. OG-07 ODF writers only as a separate product decision.

## Verification commands

```bash
# Quds engine sheet/ODS cohort
cd quds_office_suite/packages/quds_office_engine
dart test test/sheet_*_test.dart test/legacy_sheet_reader_test.dart \
  test/ods_sheet_reader_test.dart test/sml_styles_date_test.dart \
  test/sheet_macro_preservation_test.dart

# CrispCloud targeted host suite
cd CrispCloud
flutter test test/office_document_service_test.dart \
  test/widget/odt_image_viewer_test.dart \
  test/widget/ods_viewer_grid_test.dart \
  test/widget/office_editor_dialog_test.dart \
  test/widget/ods_editor_workflow_test.dart \
  test/local_odf_corpus_test.dart

# Live corpus smoke tests (local only)
flutter test test/local_odf_corpus_test.dart
cd packages/quds_office_engine && dart test test/local_spreadsheet_corpus_test.dart
```

See also:

- [File-format routes](file-format-viewers.md)
- [Office engine strategy](office-engine-strategy.md)
- [Quds fork pin and fixes](../packages/QUDS_FORKS.md)
- `excel-steering` private audit and live-fidelity harness (not part of this repository)
