# Office fidelity scenarios

From `packages/quds_office_engine`, with Dart on `PATH`:

```sh
dart pub get
bash tool/fidelity/check.sh
```

The check runs the oracle's negative tests, focused Dart regressions, six DOCX
exports and twelve XLSX/PPTX exports (three unchanged cycles and three edited
cycles per format), then an example DOCX edit script. Exported files and
machine-readable reports are written under `build/fidelity*`.

## Import, inspect, edit and export

```sh
dart run tool/fidelity/office_steps.dart inspect input.docx
dart run tool/fidelity/office_steps.dart export input.docx output.docx
dart run tool/fidelity/office_steps.dart modify input.docx steps.json output.docx
```

`inspect` imports a DOCX and prints paragraphs, headings, note IDs and image
sizes. `export` uses the asynchronous save implementation used by the host.
`modify` applies a JSON array of steps before saving. All steps must succeed
before the output is written. Existing output files are replaced on success;
choose a different filename to retain the input.

`example_steps.json` is a runnable example. Paragraph/image indices are
zero-based, following `inspect` order. Text offsets are UTF-16 code units;
measurements and font sizes are points. Relative image paths are relative to
the command's working directory.

| Operation | Fields besides `op` | Behavior |
| --- | --- | --- |
| `replaceText` | `paragraph`, `text`, optional `start`, `end` | Replace a range; defaults to the whole paragraph |
| `heading` | `paragraph`, `level` | Apply heading level |
| `applyStyle` | `paragraph`, `style` | Apply a style from the document catalog |
| `paragraphFormat` | `paragraph`, optional `alignment`, `before`, `after`, `lineSpacing`, `keepTogether`, `pageBreakBefore` | Change supplied paragraph settings |
| `runFormat` | `paragraph`, optional `start`, `end`, `bold`, `italic`, `color`, `highlight`, `font`, `size` | Change supplied text settings; colors are RGB hex strings |
| `addNote` | `paragraph`, `text`, optional `endnote` | Append a reference and create its body; editor tests separately cover caret insertion |
| `editNote` | `id`, `text`, optional `endnote` | Replace note body |
| `deleteNote` | `id`, optional `endnote` | Remove note and references |
| `imageSize` | `image`, optional `width`, `height` | Resize existing picture |
| `imageReplace` | `image`, `file` | Replace existing picture bytes |

`endnote` defaults to false. Unknown operations, missing note IDs and invalid
indices fail explicitly. This developer CLI exposes only the listed operations.

## Independent expectations

- `corpus.py` authors deterministic DOCX input with Python ZIP/XML tools,
  independently of the Quds serializer. `imported.json` and `edited.json` in
  `test/fixtures/fidelity` describe expected semantics from authored XML.
- `scenarios.dart` imports that fixture, edits it and produces repeated exports.
  `corpus.py verify` reads exported ZIP/XML directly, without using the Quds
  reader to decide whether the Quds writer is correct.
- Checks cover note identity/body, hyperlink ownership, headings, numbering,
  style types/list indents, table text, image size/byte hashes, header/footer,
  opaque parts, relationship targets, duplicate IDs, namespace bindings and
  selected OOXML child order. This is not complete XSD validation.
- `cross_format.dart` imports directly authored sheet/slide XML.
  `cross_oracle.py` compares exported cells/formulas/caches/merges/frozen rows
  and slide text/geometry with separately authored JSON expectations.
- `notes.dart` produces an authored rich-note source and six repeated exports.
  `notes_oracle.py` independently checks ordered paragraphs/tables/drawings,
  run formatting, owning-part hyperlinks and image extents against JSON goldens.
  It decodes PNG scanlines and checks the expected pixel hash, so accidentally
  reusing the body picture's relationship cannot pass through a byte-copy check.
- `test_oracles.py` deliberately corrupts fixtures to prove missing links/media/
  note marks, changed text/numbering, invalid namespaces and property ordering
  are rejected.

Goldens are semantic: generated IDs, XML whitespace, ZIP timestamps and
compression are not compared byte-for-byte. Picture/opaque content is hashed.

```sh
python3 tool/fidelity/corpus.py inspect input.docx
python3 tool/fidelity/corpus.py verify build/fidelity
python3 tool/fidelity/cross_oracle.py build/fidelity
```

The Python snapshot expects this corpus's parts; use the Dart `inspect` for
general documents. `verify` expects scenario outputs; DOCX names beginning
with `edited` use the edited expectation.

## Reviewed golden maintenance

Normal checks never refresh expectations. After deliberately changing the
authored fixture, run `python3 tool/fidelity/corpus.py seed`, review the DOCX/JSON
diff, and rerun checks. Sheet/slide JSON is authored separately, not regenerated.

The editor golden renders the fixture before and after export against the same
reviewed full-page PNG. It requires actual picture pixels before capture, and
includes notes and footer. Use pinned Flutter **3.44.0** on Linux:

```sh
cd ../quds_office_editor
flutter test test/office_fidelity_golden_test.dart --no-pub
# Intentional maintenance only: inspect the PNG, then rerun without this flag.
flutter test test/office_fidelity_golden_test.dart --no-pub --update-goldens
```

## Full checks and gap inventory

```sh
# From packages/quds_office_engine; use a fresh coverage directory each time.
dart analyze
dart test --coverage=coverage/fresh-run
python3 tool/fidelity/coverage_report.py coverage/fresh-run
cd ../quds_office_editor
flutter test --no-pub
python3 ../quds_office_engine/tool/fidelity/corpus.py verify build/fidelity
```

The report merges hits and lists every unhit instrumented engine line plus files
absent from instrumentation. Never mix coverage from different source revisions.
Coverage measures execution, not correctness. See the repository's
`docs/office-fidelity-audit.md` and `docs/office-coverage-gaps.json`.

The GitHub workflow runs full engine/editor checks and uploads exports, reports,
coverage and failed-image diffs. CrispCloud runs the portable corpus plus root
host save regressions and checks a SHA-256 manifest for shared vendored files.

Style steps preserve sparse source definitions and inherited values:

```json
[
  {"op":"styleDefinition","style":"Accent","type":"character","rPr":{"color":{"val":"008844"},"sz":{"val":"32"}}},
  {"op":"characterStyle","paragraph":2,"run":0,"style":"Accent"},
  {"op":"tableStyle","table":0,"style":"Regional"}
]
```

`styleDefinition` accepts `rPr`, `pPr`, `tblPr`, and `tcPr` maps. Keys are
OOXML property names; values are attribute maps, or null to remove a property.
The operation rejects unknown styles and type mismatches. Source defaults,
basedOn chains, theme fonts/colors, character styles, table run/paragraph
formatting, direct zero/false values, and cyclic source definitions are covered
by `style_cascade_test.dart` and six independent sparse-XML oracle checks.

The independent `native.xlsx` (openpyxl 3.1.5) and `native.pptx`
(python-pptx 1.0.2) fixtures are committed. Regenerate explicitly with
`python3 tool/fidelity/native_fixtures.py`; normal runs never overwrite inputs.
`native_spreadsheet_test.dart` and `native_presentation_test.dart` emit fifteen
files under `build/fidelity-native`. `native_oracle.py` checks owned relationships,
master/theme preservation, decoded picture pixels, chart data/references, number
formats, borders, fonts, hyperlinks, pivot/cache wiring, notes and motion XML.
