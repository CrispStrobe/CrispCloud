# Office fidelity scenarios

This suite drives real DOCX, XLSX and PPTX imports, edits and asynchronous saves,
then checks the resulting packages with independently authored expectations.
Normal checks do not regenerate source fixtures or accept new goldens.

## Run the suite

Use the repository's pinned Flutter 3.44.0 / Dart toolchain. From
`packages/quds_office_engine`:

```sh
dart pub get
bash tool/fidelity/check.sh
```

The command produces Office exports under `build/fidelity*`, checks ZIP/XML
semantics and image pixels, and runs deliberate corruption controls. These
controls must pass a positive fixture before proving that damaged output fails.
`audit_operations.py` also requires a committed executable scenario for every
public operation. Operation coverage measures exercised commands, not complete
OOXML support or all possible parameter combinations.
Scenarios cover the original 18 cross-format exports plus rich notes, style
cascades/toggles, independently produced native spreadsheets/decks, pivot
creation, image replacement and opaque body XML (`w:altChunk` and any other
unmodeled body element, with its relationship provenance). The editor adds
layout exports and the async controller export.

The authored manifests require **241 engine files** and **22 editor files**.
The engine has 73 complete three-save series and 22 standalone inputs/exports;
the editor has seven complete three-save series and one standalone export.
Exact inventory checks reject missing, extra, empty or invalid packages and
retain SHA-256 receipts. Authored source/edited baselines also participate in
external render comparisons; exports without a declared comparison baseline
still require their own schema and render checks.

## Import, inspect, edit and export

```sh
dart run tool/fidelity/office_steps.dart operations
dart run tool/fidelity/office_steps.dart inspect input.docx
dart run tool/fidelity/office_steps.dart export input.docx output.docx
dart run tool/fidelity/office_steps.dart modify input.docx steps.json edited.docx
dart run tool/fidelity/office_steps.dart roundtrip edited.docx build/my-document 3
```

All five commands accept `.docx`, `.xlsx` and `.pptx` where an input is needed.
`operations` prints the exact operation/field catalog as JSON. `inspect` prints
model content, indexes, notes, stories, cells or slide shapes. `export` saves in
the input format using the host's `OfficeIsolateSave` implementation.
`roundtrip` exports and reimports repeatedly, writing `roundtrip-1` through the
requested cycle count (default 3, allowed 1–100). It does not convert formats.

`modify` reads a JSON array. Each step must succeed before the output is written
through a temporary file and rename. Failure reports the numbered step, exits
nonzero and leaves an existing output unchanged. Unknown operations/fields,
invalid indexes/types/ranges, malformed colors and unsupported image bytes fail
explicitly. Use a distinct output filename to keep the original after success.

Paragraph, run, table, cell row/column, image, sheet and slide indexes are
zero-based. Text offsets use UTF-16 code units; offsets within a surrogate pair
or an atomic note reference are rejected. Word and slide measurements are
points; sheet row heights and column widths are **pixels**. RGB colors contain
six hex digits without `#`. Image files are PNG or JPEG; relative asset paths
are resolved against **the step file's directory**, regardless of the current
working directory. Inspect a document before choosing indexes, since each edit
can change the indexes used by later steps.

### DOCX: 49 operations

For paragraph/run/image operations that accept a story selector, `story`
defaults to `body`. Other values are `header`, `footer`, `firstHeader`,
`firstFooter`, `evenHeader`, `evenFooter`, `footnote`, `endnote`, and `comment`. Header/footer
stories use `section` (default 0); note stories require the actual `note` ID; comment stories require the actual `comment` ID.
`addNote`, paragraph structure and list commands target the body.

| Operation | Fields besides `op` | Result |
| --- | --- | --- |
| `replaceText` | `paragraph`, `text`; optional `start`, `end`, story selector | Replace a text range; defaults to the whole paragraph |
| `heading` | `paragraph`, `level`, story selector | Set heading level 0–9; referenced built-in styles are exported |
| `applyStyle` | `paragraph`, `style`, story selector | Apply a paragraph style from this document |
| `characterStyle` | `paragraph`, `run`, `style`, story selector | Apply a source character style |
| `tableStyle` | `table`, `style` | Apply a source table style |
| `styleDefinition` | `style`; optional `type`, `rPr`, `pPr`, `tblPr`, `tcPr` | Edit sparse source style properties |
| `paragraphFormat` | `paragraph`; optional `alignment`, `before`, `after`, `lineSpacing`, `lineSpacingRule`, `left`, `right`, `firstLine`, `hanging`, `tabs`, `keepTogether`, `pageBreakBefore`, `columnBreakBefore`, `dropCapLines`, `shading`, `border`, `rtl`, story selector | Change supplied properties, preserving explicit defaults |
| `runFormat` | `paragraph`; optional `start`, `end`, `bold`, `italic`, `strike`, `underline`, `color`, `highlight`, `font`, `size`, story selector | Format a range; explicit false/black/default-size values stay direct |
| `addNote` | `paragraph`, `text`; optional `offset`, `endnote` | Insert a footnote/endnote at the caret offset, or the end if omitted |
| `editNote` | `id`, `text`; optional `endnote` | Replace the note body; use story run operations for rich formatting |
| `deleteNote` | `id`; optional `endnote` | Delete the note and its actual reference runs |
| `imageSize` | `image`; `width` and/or `height`, story selector | Resize a picture |
| `imageReplace` | `image`, `file`, story selector | Replace picture data while preserving owning-part relationships |
| `imageAdd` | `file`, `width`, `height`; optional `section`, `index`, `title` | Insert a body picture at a block index, or append |
| `imageRemove` | `image`, story selector | Remove the selected picture |
| `paragraphInsert` | `text`; optional `section`, `index`, `style` | Insert at a block index, or append |
| `paragraphSplit` | `paragraph`, `offset` | Split rich content at a valid offset |
| `paragraphDelete` | `paragraph` | Delete the selected paragraph |
| `list` | `paragraph`, `numbered`; optional `level` | Apply a document-local list definition; levels 0–8 |
| `listClear` | `paragraph` | Remove list formatting |
| `listRestart` | `paragraph`; optional `at` (default 1) | Restart a numbered list without mutating unrelated instances |
| `hyperlink` | `paragraph`, `run`, `target`, story selector | Set a run hyperlink |
| `tableCellText` | `table`, `row`, `column`, `text` | Replace the selected cell's entire story with one plain paragraph |
| `headerFooterText` | `story`, `text`; optional `section`, `paragraph` | Replace/add text in one of the six header/footer variants |
| `sectionFormat` | optional `section`, `width`, `height`, `top`, `bottom`, `left`, `right`, `header`, `footer`, `columns`, `columnSpace`, `columnSep`, `breakKind`, `differentFirstPage`, `differentOddEven` | Edit page/section geometry and flags |

### Word structure operations

These 24 additional commands use body indexes shown by `inspect`. `tableMerge`
uses logical grid columns; `tableUnmerge`, `tableCellText` and `tableCellFormat`
use physical cell indexes within the selected row. TOC indexes follow depth-first
body traversal, including controls, tables and frames. Exact required
fields and accepted optional fields are available from `operations`.

| Operations | Purpose and important fields |
| --- | --- |
| `tableAdd`, `tableFormat` | Create a table with `rows`, `columns`, `width`; edit alignment, RTL and uniform border properties |
| `tableRowInsert`, `tableRowDelete`, `tableColumnInsert`, `tableColumnDelete` | Edit a rectangular grid by zero-based `row` or `column`; merged grids must be unmerged first |
| `tableMerge`, `tableUnmerge` | Merge the inclusive rectangle `row`, `column`, `endRow`, `endColumn`; retain ordered rich blocks |
| `tableRowFormat`, `tableCellFormat` | Change row `height`/`cantSplit`, or cell `fill`/`width` |
| `tocAdd`, `tocUpdate`, `tocRemove` | Insert, refresh or remove native TOCs; set `title`, `minLevel`, `maxLevel`, `showPageNumbers` |
| `bookmarkSet`, `reference` | Set one paragraph bookmark `name`; replace a distinct paragraph with a native REF field targeting `bookmark` |
| `commentAdd`, `commentReply`, `commentEdit`, `commentResolve`, `commentDelete` | Anchor a nonempty text range, maintain thread replies and resolved state, and remove a thread |
| `imageWrap` | Set `wrap`, distances `top`/`bottom`/`left`/`right`, `rotation`, `altTitle`, `altDescription` |
| `frameAdd`, `frameFormat`, `frameRemove` | Create and position a text frame with `x`, `y`, `width`, `height`, `anchor`, `wrap`, `fill`, `stroke` |

Paragraph tab stops are arrays of `{ "position": 72, "alignment": "right",
"leader": "dot" }`. Distances are points. `firstLine` and `hanging` cannot both
be supplied. Comment `date` values, when supplied, are ISO-8601 timestamps.
Bookmark creation rejects duplicate names and replacement of a differently named
bookmark, preventing silent breakage of existing references. The import/edit/export
model also preserves native partial, multiple, overlapping and cross-paragraph
bookmark ranges; `reference` uses their exact marked text. `bookmarkSet` remains
a paragraph-wide creation operation. The editor's rich clipboard insertion
rejects native-ID collisions. The scripted `paragraphDelete`, `tableRowDelete`,
`tableColumnDelete` and `tocRemove` commands, plus note-pane edits that remove
paragraphs, reject removal of only one native bookmark endpoint before mutation.
These guarantees cover the named edit paths. The note-pane guard also runs before
controller history changes. The CLI `editNote` operation intentionally replaces
the rich note body; use paragraph/run operations for rich edits.

Frame `wrap` accepts `none`, `square` and `topBottom`. Body paragraphs and TOCs
following a frame reflow around it; native coordinates, wrap values and colors
are checked independently. Arbitrary picture contours and floating table
exclusions remain outside that acceptance scope.

Imported block content controls retain live children and exact metadata in
body, notes, tables and frames. Headers, footers and comments also retain
single-paragraph block controls, including nested wrapper shells. Paired inline
controls retain their positions. Supported paragraph operations use the actual
container. Unsupported inline drawings/equations, multi-paragraph or
non-paragraph auxiliary controls, table row/cell wrappers and edits crossing
control boundaries fail before mutation. UI lock and data-binding semantics are
not implemented.

The independently authored `word_structure_source.xml`,
`word_structure_expected.json`, and `scripts/word-structure-{create,edit,remove}.json`
cover all three phases and three save/reopen cycles. Run
`dart test test/word_structure_steps_test.dart`, then
`python3 tool/fidelity/word_structure_oracle.py` and its corruption controls.
The XML oracle checks comment anchors and thread metadata, native REF and TOC
fields, grid spans, paragraph geometry, positioned frames, picture relationships
and original image bytes. Normal validation never rewrites expected values.

`endnote` defaults to false. Alignment, underline and break-kind strings use the
model enum names printed in the source. `highlight: null` clears a highlight.
`styleDefinition` values are maps from OOXML property names to attribute maps;
a null property removes it. The style ID must already exist; a supplied type
must match its native type. The command retains sparse source definitions and
re-evaluates inherited formatting.

A small edit script:

```json
[
  {"op":"heading","paragraph":0,"level":2},
  {"op":"runFormat","paragraph":0,"bold":false,"color":"000000","size":11},
  {"op":"addNote","paragraph":1,"offset":0,"text":"Source note"},
  {"op":"imageReplace","image":0,"file":"replacement.png"},
  {"op":"sectionFormat","columns":2,"columnSpace":18}
]
```

The committed `test/fixtures/fidelity/scripts/word.json` combines styles,
explicit defaults, caret notes, rich note text, split hyperlinks, images,
paragraph insertion/deletion, list restarts, table text and header/footer edits.
It has a separately authored semantic expectation in `scripts/expected.json`.

### Preserving native Word structure during edits

Native bookmarks retain exact ordered start/end markers, including overlapping
and cross-paragraph ranges. Native block/inline content controls retain wrapper
metadata around their ordinary editable blocks/runs. Imported footnote/endnote
body markers retain their original positions, run properties and absence.
Independently authored fixtures and Python oracles cover untouched, inside-edit
and three-save cases; actual editor tests also cover split and undo/redo.

Use story `replaceText`/`runFormat` for rich note edits. `editNote` deliberately
replaces the whole rich body and retains only the first original automatic marker
as a leading marker; an originally unmarked note stays unmarked. Unconventional
source marker placement is preserved in exported XML, while the canvas still
uses its conventional note-label layout.

Unsupported Word structure fails explicitly: paragraph-external bookmark
endpoints, invalid/duplicated range identities, unsupported content-control
containers, and a paragraph split through an inline-only control. The script
keeps an existing output unchanged on rejection; export preflight checks native
identities and wrapper nesting before changing package parts. Retention does not
implement content-control data binding or control-specific UI.

The original adjacent-edit data-loss reproducers are part of the passing gate:

```sh
python3 tool/fidelity/unsupported_word_audit.py
```

The historical failing report is retained separately from the current result.
Legacy private `qudsFrame` conversion has its own cycle checks, so it is not used
as an unchanged native-layout baseline.

### XLSX: 10 operations

Every operation accepts `sheet` (default 0). Cell addresses/ranges use A1
notation and must stay within Excel row/column bounds.

| Operation | Other fields | Result |
| --- | --- | --- |
| `cellValue` | `cell`, `value` | Set string/number/boolean/null and clear an existing formula |
| `cellFormula` | `cell`, `formula` | Set a formula; a leading `=` is optional |
| `cellFormat` | `cell`; optional `bold`, `color`, `fill`, `size`, `alignment` | Edit formatting while retaining imported style properties |
| `mergeCells` | `range` | Merge and center a multi-cell range |
| `unmergeCells` | `range` | Unmerge the selected range |
| `freeze` | `rows` and/or `columns` | Set frozen row/column counts |
| `renameSheet` | `name` | Atomically rename a sheet and rewrite supported local references |
| `sheetOrder` | `to` | Move the sheet to a new index |
| `rowHeight` | `row`, `height` | Set row height in pixels |
| `columnWidth` | `column`, `width` | Set column width in pixels |

After all edits, the engine recalculates supported formulas. Unsupported external,
three-dimensional, whole-row/column and qualified-name expressions retain their
imported cached values; preservation does not establish evaluation support.

`renameSheet` uses the shared `SheetRename` plan also exposed to editor history.
It rewrites local quoted/unquoted and three-dimensional sheet qualifiers in
modeled and native formulas, defined/print names, validation and conditional
rules, internal hyperlinks, consolidation sources, charts and pivot sources.
Formula strings, structured references and external workbook qualifiers are
retained. A unique valid name is required. Opaque executable/data-model owners,
unrecognized reference-bearing XML, stale edits, incomplete shared formulas,
array/data-table formulas and lossy native projections reject before mutation.
Undo patches only the reference fields owned by the rename, preserving later
edits and save-generated cached results. See `scripts/sheet.json` and the
independently authored `sheet-rename-native.xlsx` fixture and XML oracle.

### PPTX: 8 operations

Every operation accepts `slide` (default 0). Shape indexes follow `inspect`.

| Operation | Other fields | Result |
| --- | --- | --- |
| `shapeText` | `shape`, `text` | Replace text, preserving actual paragraph boundaries |
| `shapeFormat` | `shape`; optional `size`, `color`, `fill`, `alignment`, `rtl` | Change supplied text/fill settings |
| `shapeGeometry` | `shape`; optional `x`, `y`, `width`, `height`, `rotation` | Edit points/degrees, keeping visual geometry synchronized |
| `slideNotes` | `text` | Replace speaker notes |
| `slideHidden` | `hidden` | Set visibility |
| `slideOrder` | `to` | Move a slide, preserve its owning parts and update section membership |
| `slideTransition` | `kind`; optional `direction`, `durationMs`, `advanceOnClick` | Set a schema-valid transition |
| `slideImageReplace` | `shape`, `file` | Replace picture bytes |

Text replacement refuses picture/table shapes. Section-aware slide reordering
retains native section GUIDs, order, empty sections, membership metadata and
namespace bindings. The moved slide adopts the original destination slide's
section; every other membership stays unchanged. Malformed, ambiguous,
nonconsecutive or stale section membership and unresolved native slide targets
reject before mutation. The same reversible plan is used by editor history.
See `scripts/slide.json` for combined operations and the independently authored
`slide-sections.pptx` corpus for three-save direct/isolate permutations. Native
acceptance compares the complete rendered page text and RGB fingerprints with
the corresponding source-page order.

## Evidence layers

| Layer | Independent expectation and failure detected |
| --- | --- |
| Authored DOCX ZIP/XML | Note IDs/bodies/markers, native bookmark ranges, content-control wrappers, direct styles, lists, links, tables, media, section and compatibility semantics |
| openpyxl / python-pptx inputs | Retained source templates/styles, live charts, pivots, speaker notes, media ownership and reorder behavior |
| Python semantic oracles | Read output ZIP/XML directly, compare authored values, decode picture pixels, verify relationships and selected child ordering |
| Mutation controls | Deliberately break content, note marks, style flags, list starts, formulas, media, namespaces or inventories and require rejection |
| Flutter goldens | Notes and continuation, first/even/default story pictures, columns, tall tables, structure recipes, three frame wrap modes and rich nested cells, before and after saves |
| Real CrispCloud widget tests | Open the real editor dialog, edit during an upload, capture saved bytes, retry failures and check dirty/close behavior |
| Open XML SDK | Validate exact package bytes against the external OOXML schema validator, report SHA-256 receipts, and prove the validator rejects an invalid control |
| LibreOffice / Poppler | Render supported inputs to retained PDF/page PNGs; compare text and decoded RGB pixels against native sources and complete save-cycle groups; separately report strictly qualified native-only limitations |
| VM line coverage | List every uncovered instrumented line and every absent source file; execution coverage does not establish correctness |

The Python package oracle is not a general OOXML validator. The Open XML SDK
checks structural validity, not application rendering. LibreOffice repeated-save
comparisons check stability in that renderer, not pixel identity with Microsoft
Office. These layers answer different questions and are all retained.

The authored block-control-in-comment source is currently refused by
LibreOffice. Its original seven packages are still required by the semantic and
SDK gates. Only the specific raw-source importer refusal plus successful
exact-path, exact-byte SDK receipts can qualify them as `native_schema_only`;
they count as zero visual successes. A separate seven-file header/footer-control
corpus is rendered strictly against its source. See `FID-065` in
`docs/office-fidelity-gaps.json` at the repository root for this acceptance limit.

## Full checks

From `packages/quds_office_engine`:

```sh
dart analyze
# Use an empty directory; never combine coverage from different source revisions.
rm -rf coverage/vm
dart test --coverage=coverage/vm
bash tool/fidelity/check.sh
python3 tool/fidelity/coverage_report.py coverage/vm
cd ../quds_office_editor
python3 ../quds_office_engine/tool/fidelity/inventory.py clean \
  --package quds_office_editor --package-root . \
  --manifest ../quds_office_engine/tool/fidelity/editor_output_manifest.json
flutter test --no-pub
python3 ../quds_office_engine/tool/fidelity/corpus.py verify build/fidelity
python3 ../quds_office_engine/tool/fidelity/bookmarks_oracle.py --editor-dir build/fidelity-bookmarks
python3 ../quds_office_engine/tool/fidelity/content_controls_oracle.py --editor-dir build/fidelity-content-controls
python3 ../quds_office_engine/tool/fidelity/inventory.py verify \
  --package quds_office_editor --package-root . \
  --manifest ../quds_office_engine/tool/fidelity/editor_output_manifest.json
```

From the repository root, with .NET 8, LibreOffice and Poppler available:

```sh
# After both exact inventories pass, collect both packages for external checks.
# Use a new directory so an earlier corpus cannot supply missing evidence.
python3 - <<'PYTHON'
from pathlib import Path
import shutil
target_root = Path('build/office-evidence')
target_root.mkdir(parents=True, exist_ok=False)
for package in Path('packages').glob('quds_office_*'):
    for source in package.glob('build/fidelity*'):
        target = target_root / package.name / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            shutil.copy2(source, target)
PYTHON
dotnet run --project tool/office-validation -- --self-test
dotnet run --project tool/office-validation -- build/office-evidence build/external/schema-report.json
python3 -m unittest discover -s tool/office-validation -p 'test_*.py'
python3 tool/office-validation/render.py build/office-evidence build/external-render \
  --schema-report build/external/schema-report.json
```

CI runs full engine/editor suites, retains the semantic reports, exports,
coverage, PDF/PNG render evidence and image diffs, and runs external gates.
CrispCloud pins shared files with `tool/office_fidelity_manifest.json`; its host
check also opens the actual saved DOCX with the independent oracle.

## Intentional fixture and golden maintenance

Source fixture generators are maintenance commands, not part of normal checks.
`corpus.py seed`, `native_fixtures.py`, and the authored fixture scripts must be
run deliberately, followed by review of the XML/JSON/content changes. Never
replace an expected value solely because the current exporter produced it.
Generated IDs, ZIP timestamps, compression and harmless XML whitespace are not
semantic goldens. Image pixels and opaque retained payloads are checked.

For visual maintenance, use Flutter **3.44.0 on Linux**:

```sh
cd packages/quds_office_editor
flutter test --no-pub test/office_fidelity_golden_test.dart test/office_story_golden_test.dart test/office_layout_goldens_test.dart
# Only after an intentional design/layout change:
flutter test --no-pub test/office_story_golden_test.dart --update-goldens
# Inspect all changed PNGs, then rerun without --update-goldens.
```

The layout goldens compare the original and each of three sequential native
save/reopen states to the same reviewed baseline for RTL/Arabic, columns,
sections/page breaks, continued notes, and a four-page table with a late note;
expected page counts are asserted explicitly.

The picture assertions must pass before capturing a golden, so an undecoded or
blank page cannot become an accepted baseline. Use the
[current coverage guide](../../../../docs/office-fidelity-coverage-20261112.md)
and [gap ledger](../../../../docs/office-fidelity-gaps.json) for current fixes
and remaining limits. The
[historical audit](../../../../docs/office-fidelity-audit.md) retains earlier
measurements and probe results.

## Native fixtures

The independent `native.xlsx` (openpyxl 3.1.5) and `native.pptx`
(python-pptx 1.0.2) fixtures are committed. Regenerate explicitly with
`python3 tool/fidelity/native_fixtures.py`; normal runs never overwrite inputs.
`native_spreadsheet_test.dart` and `native_presentation_test.dart` emit files
under `build/fidelity-native`. `native_oracle.py` checks owned relationships,
master/theme preservation, decoded picture pixels, chart data/references, number
formats, borders, fonts, hyperlinks, pivot/cache wiring, notes and motion XML.
`edge_oracle.py` checks replaced image pixels and opaque body XML across three
save cycles.

The external renderer accepts either the `libreoffice` (Linux) or `soffice`
(macOS) executable. External engine agreement is evidence for this corpus; it
does not establish identical layout for every Office document.
