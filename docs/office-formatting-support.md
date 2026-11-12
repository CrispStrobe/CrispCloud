# Office formatting support

This is the current support matrix for the CrispCloud Office editor. “UI”
means exposed in the ribbon/dialog; “model” means the Quds engine can represent
it; “round-trip” means the vendored serializer preserves it.

## Word (DOCX)

### Font / character formatting

| Feature | UI | Model | Round-trip | Notes |
|---|---|---|---|---|
| Font family | ✅ | ✅ | ✅ | Common Office families plus the current imported family |
| Font size | ✅ | ✅ | ✅ | 6–96 pt picker |
| Bold / italic | ✅ | ✅ | ✅ | |
| Underline | ✅ | ✅ | ✅ | Single, double, dotted, wavy |
| Strikethrough | ✅ | ✅ | ✅ | |
| Font color | ✅ | ✅ | ✅ | Office palette + hex |
| Highlight | ✅ | ✅ | ✅ | Word named highlight colors (hex is mapped on save) |
| Superscript / subscript | ✅ | ✅ | ✅ | Baseline resets to normal |
| Clear formatting | ✅ | ✅ | ✅ | Resets the run properties exposed by the ribbon |
| Letter spacing / kerning | — | — | — | Not in the current model |
| All caps / small caps | — | — | — | Not in the current model |
| Double strikethrough | — | — | — | Model has a single strike flag |

### Paragraph formatting

| Feature | UI | Model | Round-trip | Notes |
|---|---|---|---|---|
| Alignment | ✅ | ✅ | ✅ | Left, center, right, justify |
| Line spacing | ✅ | ✅ | ✅ | Multiple presets plus numeric value |
| Line-spacing rule | ✅ | ✅ | ✅ | Multiple/single, exact, at least |
| Space before/after | ✅ | ✅ | ✅ | Presets and numeric dialog |
| Left/right indent | ✅ | ✅ | ✅ | Ribbon nudge + dialog |
| First line / hanging indent | ✅ | ✅ | ✅ | Dialog |
| Tab stops | ✅ | ✅ | ✅ | Comma-separated positions in the paragraph dialog |
| Keep lines together | ✅ | ✅ | ✅ | |
| Page break before | ✅ | ✅ | ✅ | |
| Paragraph borders | ✅ | ✅ | ✅ | Border color in the paragraph dialog; layout tab has shading |
| Paragraph shading | ✅ | ✅ | ✅ | Layout tab |
| Drop cap | ✅ | ✅ | ✅ | 0–10 lines; OOXML order is schema-checked |
| Bullets / numbering | ✅ | ✅ | ✅ | Two built-in list definitions |
| Text direction | ✅ | ✅ | ✅ | LTR/RTL |
| Keep with next / widow control | — | — | — | Not in the current model |
| Custom tab leaders | — | ✅ | ✅ | UI exposes positions; existing alignment/leaders survive unrelated edits and retained positions |

### Styles

- Paragraph styles exposed: Normal, Title, Subtitle, Quote, Intense Quote,
  Heading 1–9 and document-local imported paragraph styles. Imported custom
  names remain authored text; style IDs identify selections.
- Character styles, custom style creation and table-style selection are not
  exposed in the CrispCloud ribbon yet.
- Imported style definitions retain their source properties while explicit
  supported edits update the corresponding values; built-in and custom style
  IDs survive a save/reopen.
- Direct formatting is preserved independently of styles.

### Other Word features

Page size, margins, columns, section/page/column breaks, headers/footers,
page numbers, tables, comments, tracked changes, protection and watermarks are
available from the ribbon. This document focuses on paragraph/font/style
settings; those features have their own controls and tests.

## Sheet (XLSX)

| Feature | UI | Model | Notes |
|---|---|---|---|
| Font size | ✅ | ✅ | |
| Bold | ✅ | ✅ | |
| Font color | ✅ | ✅ | |
| Fill color | ✅ | ✅ | |
| Horizontal alignment | ✅ | ✅ | General, left, center, right |
| Merge / unmerge | ✅ | ✅ | |
| Cell borders | — | ✅ | Model has border color/width; UI needs a control |
| Font family / italic / underline | — | — | Not in the current sheet cell model |
| Number formats / styles | limited | partial | Uses the engine/SML style index |

## Slides (PPTX)

| Feature | UI | Model | Notes |
|---|---|---|---|
| Font size | ✅ | ✅ | |
| Text color | ✅ | ✅ | |
| Shape fill | ✅ | ✅ | |
| Text alignment | ✅ | ✅ | Left, center, right |
| Bold / italic / underline / family | — | — | Not in the current `PmlShape` model |
| Theme/design editing | limited | partial | Outside this pass |

## Verification

The [host fidelity audit](office-host-fidelity-20261112.md) adds actual ribbon and
dialog tests for fractional values, custom styles, tab metadata, header story
selection, page margins and hyperlink history. Its independent ZIP/XML
assertions and repeated exports supplement the model-oriented checks below.

The formatting round-trip is covered by
`test/office_formatting_preservation_test.dart`:

- font family, size, bold, italic, underline, strike, color, highlight,
  superscript;
- alignment, multiple/exact/at-least spacing, before/after, all indents;
- tab stops, borders, shading, drop caps, keep-lines, page-break-before;
- built-in paragraph style assignment;
- strict `w:pPr`, `w:rPr`, `w:sectPr`, `w:lvl` and `w:numbering` child order.

Strict OOXML validation caught defects that XML parsers and LibreOffice
accepted: inverted `pPr`/`rPr` order, `sectPr` order, invalid hex highlight
values, and abstract-numbering order. The vendored serializer now passes the
Open XML SDK validator and the Python order validator:

```bash
~/miniconda3/bin/python tool/verify_ooxml_order.py \
  build/quds_roundtrip/formatted.docx
```

Word, LibreOffice and the Open XML SDK were used during development:

- Word 16.111 reopened the fully formatted document and preserved body/note
  text and rendered PDF text.
- LibreOffice headless opened and exported all generated DOCX files.
- Open XML SDK `DocumentFormat.OpenXml` validation reports zero errors for the
  current generated fixtures.

The automated CrispCloud suite does not require Word or LibreOffice; the
Python/Dart order checks and `python-docx`/`pandoc` checks are the CI-friendly
oracles.
