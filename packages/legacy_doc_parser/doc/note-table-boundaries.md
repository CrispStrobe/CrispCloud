# Footnote and endnote table boundaries

Footnote and endnote output preserves the parsed block sequence when a note ends
in a table. The writer no longer appends an empty paragraph after that table.
The Open XML `CT_FtnEdn` content model permits table children, as reflected by
Microsoft's [FootnoteEndnoteType](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.footnoteendnotetype)
schema type. A final-table note therefore does not need the paragraph fallback
used by other story contexts. Empty stories still receive a valid paragraph.

This changes only the writer's fallback. All actual paragraphs, including empty
ones, remain present. No note CP is subtracted and no blank paragraph is trimmed.
[MS-DOC PlcffndTxt](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b30472e7-569e-4c9c-a8ca-07fd5432f365)
includes the final CR in each note range; the story's second-to-last PLC CP ends
the final range. These note ranges differ from textbox/header separator rules.
The existing bounded recovery for a native final table ending at a row mark
still requires the final story boundary, an external CR and a structurally
closed table, and still reports `recoveredTableStoryBoundary`.

## Portable controls

`test/support/note_boundary_fixture.dart` assembles literal binary note ranges,
reference PLCs and table PAPX records independently of the parser. Each footnote
and endnote has eight controls: plain, empty, one trailing blank, two trailing
blanks, final table, table plus one blank, table plus two blanks, and table plus
following text. They verify exact model CP extents, block sequences, note marker
counts and emitted OOXML. Malformed table closure and terminators remain errors.

Generate the sixteen DOC/DOCX controls for independent schema validation with:

```sh
dart run tool/fidelity/note_boundary_fixture.dart build/note-boundary
```

Output names are `{footnote,endnote}-{plain,empty,trailing-blank,
two-trailing-blanks,table,table-blank,table-two-blanks,table-text}.docx`.
The corresponding DOCs and `cases.json` retain literal expected content, rather
than deriving expected block counts from converted output.

## Native bridge attribution

The existing `table-borders` corpus case exposed the unnecessary writer
paragraph. Separate independently authored table-followed-by-text controls also
show a native-generated CR **before** the following text. That CR is inside the
note range; it is not the final note terminator or an external story guard.
Native DOCX playback represents the table in a frame-anchor paragraph in these
controls. The parser retains that additional in-range paragraph rather than
guessing that it can be discarded. The
[pinned LibreOffice note exporter](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/filter/ww8/wrtw8sty.cxx)
writes its extra story-ending CR after the final note range endpoint.

Removing our synthesized paragraph must be measured separately from this native
table/frame representation change. It does not establish exact pagination for
all note tables, nor authorize removing intentional blank note paragraphs.

## Measured three-cycle result

The [sealed native receipt](evidence/note-boundary-d622754/README.md) retains
sixteen authored controls, all 64 initial/cycle imports, the exact binary inputs,
DOCX outputs and PDFs. Every parser output preserves its actual source note
blocks. The real `table-borders.docx` final-table footnote remains `[p,tbl]` and
matches its authored original exactly in RGB, text and word rectangles through
three cycles, with the note marker fixed at 682.10 points on the recorded renderer.
Both final-table note kinds remain structurally stable. All 64 parser outputs
and 16 authored controls pass independent SDK validation.

The receipt also retains the failures: six controls with paragraphs following a
table gain a native interior paragraph per cycle, endnote controls have an
original-to-binary bridge layout difference, and the sixteen native DOCX
projections have 48 schema errors. Native playback and the parser's preserved
table are different representations. None of those differences is hidden by
trimming a source CR, adopting native output as an authored golden, or changing
the original red reports.
