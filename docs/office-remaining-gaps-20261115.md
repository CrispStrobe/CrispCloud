# Office viewer/editor remaining gaps — 15 November 2026

Last updated: 16 November 2026.

This is the current backlog for the Office/ODF work. It records what is
verified, what is intentionally read-only, and what remains before the viewer
and editor can claim full format coverage.

## Current continuation

The 16 November integration reconciles CrispCloud's terminal forwarding/trigger
and Zotero continuation branches with canonical Quds, preserving the standalone
legacy parser pin. See `validation/repo-integration-20261116/` for the exact
source cutoff, branch ancestry and fresh local validation. Earlier qualification
counts and live-corpus results below retain their original source identities.

Shared spreadsheet-level ODS definitions and validation rules on blank input
cells are now imported. Whole-number, decimal, date and text-length validation
operators are integrated alongside list rules. Dynamic list links, custom and
formula-driven validation, and full native prompt/error metadata remain open.
Current qualification is recorded in `validation/terminal-ods-refresh-20261116/`.
The final local follow-up passed 507 spreadsheet/ODS engine tests, 53 host
viewer/editor workflow tests, and the local ODS import check (one workbook,
no unsupported-profile refusal). These results qualify the supported import
profile and XLSX-copy workflows; they do not establish complete ODF fidelity.
See `validation/terminal-ods-refresh-20261116/summary.json` for exact source
identities, commands and the separately qualified terminal results.

## Earlier verified state

- CrispCloud `main` snapshot: `514f7457`
- Vendored Quds source checkpoint: `33a0508a502f5809aa997928e8428bdec3e02503`
  (`packages/QUDS_FORKS.md`, 2,413 managed files)
- Quds sheet/ODS cohort: **505 tests**; the last clean full engine run was
  **2,205 tests** (two unrelated CLI bookmark/content-control tests currently
  fail on main)
- CrispCloud vendored ODS reader: **100 tests**
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
- ODS list/range-source, whole, decimal, date, text-length and custom-formula
  validations; operators, date serials, prompts, error title/message/style and
  XLSX attribute round-trips.
- ODS print areas/titles, named ranges/expressions, database-range
  autofilters, tab colours, cell hyperlinks and row/column outline groups,
  including XLSX round-trips.
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
**Covered:** literal list rules and bounded range-source snapshots, shared
spreadsheet-level definitions, blank input cells, and literal whole-number,
decimal, date and text-length bounds with comparison/between operators.
Supported custom formula conditions translate into XLSX rules; native prompt/error
text, titles and modeled error styles are retained.\
**Remaining:** arbitrary condition grammar, dynamic source-range links, complete
native validation semantics and unmodeled cross-sheet filter cases.\
**Next step:** extend condition coverage without approximating unsupported
expressions and qualify dynamic range behavior.\
**Acceptance:** list, numeric and date rules survive ODS → XLSX, with the same
source ranges, bounds, blank policy and messages.

### OG-04 — ODS workbook metadata

**Status:** Partial\
**Covered:** print areas, print-title rows/columns, global and sheet-local
named ranges, and a basic database-range autofilter.
**Covered additionally:** modeled named expressions and sheet tab colors, including
namespace-correct XLSX copies when drawings coexist.\
**Remaining:** unmodeled named-expression semantics, database filter conditions,
row/column outline grouping, cell hyperlinks, and several page-style
properties.\
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
