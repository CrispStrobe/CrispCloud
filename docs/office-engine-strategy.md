# Office engine strategy

Status: CrispCloud ships the patched Quds engine. BetterOffice remains a
time-boxed proof-of-concept candidate, not a migration decision.

## Decision summary

| Option | Decision |
|---|---|
| Quds fork | Shipping engine. Keep fixing preservation defects and expanding independent checks. |
| BetterOffice | Bounded PoC only. Upstream is Apache-2.0, Rust/WASM, with npm and Python packages, but still has no Dart/Flutter package. |
| L’Office | Deferred. Its documented Go-server ownership model does not fit a local-first app. |
| Folio Office | Excluded. Too little maintenance history and an old Dart constraint. |
| New in-house engine | Rejected. Targeted fixes plus independent verification are the rational investment. |

## What ships today

- **Word/Excel/PowerPoint editing** through the patched Quds editor.
- **PDF editing and operations** through the separately pinned, Apache-2.0
  `dart_pdf_editor`/`pdf_operations` stack.
- **F3 viewer → F4 editor** handoff for text/code, PDF, DOCX, XLSX and PPTX.
- **Read-only fallbacks** for legacy Office formats and archive members.

The Office engine has no access to the network and does not own file identity,
bookmarks, conflicts or saves. CrispCloud supplies those.

## Quds baseline and test commands

Tests are vendored because upstream excludes `test/` from published archives.

```bash
# Engine (pure Dart)
cd packages/quds_office_engine
dart pub get
dart test

# Editor (Flutter). Force the patched local engine first.
cd packages/quds_office_editor
printf 'dependency_overrides:\n  quds_office_engine:\n    path: ../quds_office_engine\n' \
  > pubspec_overrides.yaml
flutter pub get
flutter test
rm pubspec_overrides.yaml
```

`pubspec_overrides.yaml` is gitignored. Without it, the editor tests resolve the
published engine and can report false footnote regressions.

Local baseline (5 November 2026):

- engine: **454 passed, 6 skipped, 1 failure** — the failure is
  `pdf_widgets_test.dart: RTL MultiPage short line starts on the right`
  (`lastLeft` 90.9 vs expected >200). It is outside the DOCX save path but is
  the next Quds defect to investigate.
- editor: **220 passed, 1 skipped, 0 failures** against the patched engine.
- CrispCloud Office regressions: green.

## Save preservation gate

For every supported format and every save path:

1. **Display** — the document renders acceptably.
2. **Edit** — input, selection, undo/redo, formatting and formulas behave.
3. **Preserve** — the requested edit and unrelated content survive.

Quds regenerates XML from its model, so keeping the original ZIP is not proof
that unsupported content survives. Compare semantic package parts, not whole
file hashes. Check body text, styles, relationships, media, numbering,
headers/footers, footnotes/endnotes, fields and formulas. Cover untouched save
and minimal-edit save separately.

### Word footnote regression fixed

Quds previously rewrote `word/footnotes.xml` and dropped note chrome. The
vendored serializer now:

- recreates `separator` (`w:id=-1`) and `continuationSeparator` (`w:id=0`);
- inserts a `footnoteRef`/`endnoteRef` mark in each note body;
- applies direct superscript formatting to the automatic mark;
- inserts the conventional space before the note text.

Verified on 5 November 2026 with:

```bash
~/miniconda3/bin/python tool/verify_word_roundtrip.py \
  build/quds_roundtrip/unedited.docx \
  build/quds_roundtrip/minimal.docx
```

The verifier stages files in Word’s own sandbox container
(`~/Library/Containers/com.microsoft.Word/Data/tmp/crispcloud-word-verify`), so
Word does not prompt for folder access on every run. It opens and saves the
DOCX in Microsoft Word, exports a PDF, and checks:

- body paragraph text;
- footnote text and count;
- `footnoteRef` markers;
- separator/continuation-separator chrome;
- rendered PDF body and footnote text.

Both untouched and minimal-edit files passed. Word rendered small superscript
note numbers with a space before the text.

Excel has the same container-staged round-trip in
`tool/verify_excel_roundtrip.py`:

```bash
~/miniconda3/bin/python tool/verify_excel_roundtrip.py   build/quds_roundtrip/sample-quds.xlsx
```

It opens/saves/exports through Microsoft Excel and checks sheet names, cell
values/formulas and rendered PDF text. The Quds-generated sample passed. A Quds
PPTX fixture can be checked structurally with `python-pptx`; PowerPoint’s
AppleScript dictionary lacks the same save-as/open API as Word and Excel, so
native PPTX save/export currently needs UI automation or LibreOffice.

## CLI verification stack

Use layers, fastest first:

| Layer | Tools | Purpose |
|---|---|---|
| Structural | `python-docx`, `openpyxl`, `python-pptx`, `lxml`, `zipfile` | Parts, rels, styles, numbering, notes, formulas |
| Semantic | `pandoc`, `pdftotext` | Text and footnote semantics independent of Quds |
| Native consumers | Word/Excel/PowerPoint AppleScript | Actual open/save/render acceptance |
| Visual | `pdftoppm`, ImageMagick `compare`, SSIM | Page-level rendering regressions |
| Package diff | canonical XML diff | Detect loss without false whole-ZIP hashes |
| Cross-suite | LibreOffice headless (`soffice`) if installed | Extra independent converter/rendering check |

Word/Excel 16.111 and PowerPoint 16.100 are installed on this machine.
LibreOffice 26.8 is now installed and works headless. `docx2pdf` is not
installed and is unnecessary now that the AppleScript path works.

For strict package validation without Word:

```bash
~/miniconda3/bin/python tool/verify_ooxml_order.py file.docx
```

The Open XML SDK (`DocumentFormat.OpenXml`) is the definitive schema oracle
when a local .NET runtime is available. It caught corruption that LibreOffice
and XML parsers accepted. The current generated DOCX fixtures pass it with zero errors. The fixes it
drove were: `w:pPr`/`w:rPr`/`w:sectPr` child order, `w:lvlRestart` and
`w:numbering` order, and mapping `w:highlight` hex values to Word's named
highlight enum.

### Precedents from other Crisp repos

- **CrispSorter** (Tauri/Rust): `scripts/verify_docx_independent.py` is the
  right pattern — author fixtures independently, run the real CLI, verify with
  python-docx and raw ZIP/XML. Its `scripts/testflight_distribute.py` is also a
  reusable TestFlight workflow.
- **CrispTranslator** (Python): `debug_format.py` already has strong DOCX
  diagnostics for footnotes, separators, `footnoteRef`, styles, rsid hygiene
  and relationships. Reuse its assertions or port the useful checks.

Neither is a Dart library. Reuse the fixtures, assertions and CLI design, not
the runtime.

## BetterOffice proof of concept

Status: upstream (`openooxml/betteroffice`) is active and Apache-2.0 with Rust
crates, npm packages, Python wheels and WASM builds. There is no Dart/Flutter
package. The framework-free `@betteroffice/docx` npm core is about 37 MB
unpacked before the host’s WASM/worker/font bundle.

A real PoC still requires:

1. **Packaged offline runtime** — JS, WASM, workers, dynamic chunks, CSS and
   fonts bundled with the app; open DOCX/XLSX/PPTX with networking disabled.
2. **Native persistence** — CrispCloud owns file identity, bookmarks, access,
   conflicts, recovery and confirmation; the editor only owns bytes and its
   model.
3. **Comparative quality** — untouched and minimal-edit saves compared with
   patched Quds, reopened in Word/Excel/PowerPoint.
4. **Product cost** — keyboard/touch/IME/clipboard, startup, memory, bundle
   size, localization, accessibility and updates.

Gate 1 should be tested on macOS and physical iOS hardware. It has not been run
yet because the runtime is not packaged and no iOS device is available to this
session. Do not start a migration until the first two gates pass.

## Next engineering work

1. Fix the Quds RTL PDF layout failure.
2. Extend `tool/verify_word_roundtrip.py` to XLSX and PPTX with
   Excel/PowerPoint AppleScript plus openpyxl/python-pptx checks.
3. Add representative real-world DOCX/XLSX/PPTX fixtures and keep the Word /
   Excel / PowerPoint round-trip outputs as CI artifacts.
4. Package and test a BetterOffice DOCX-only WebView PoC on macOS/iOS.
