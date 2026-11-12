# Table and list fidelity

The parser keeps source character positions and never rewrites the input DOC.
The following behavior is covered by independently assembled binary fixtures
and by inspection of the emitted WordprocessingML.

## Nested tables

`LegacyWordTableCell.blocks` preserves paragraphs and nested tables in source
order. The existing `paragraphs` getter/field remains the direct paragraphs of
the cell; a complete-content consumer should visit `blocks` recursively.

The parser applies `sprmPItap` and signed `sprmPDtap` changes in order. It checks
the depth-specific cell and row markers, row cell definitions and the limit of
63 nesting levels and 63 cells per row. Incomplete rows and inconsistent markers
fail explicitly. A child table may be the first content in its enclosing cell.
HTML and DOCX retain that structure, and DOCX cells ending in a table receive
the required final paragraph.

This follows [MS-DOC, Overview of Tables](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5b45f0e7-7760-4fdb-af88-0146de2feb4c)
and [Direct Paragraph Formatting](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/61b635c3-2c44-4155-bf17-fec281b30c71).

Tests: `test/legacy_word_nested_tables_test.dart`. The binary fixture is
assembled without using the production parser or DOCX writer.

## Row origins and a shared table grid

`LegacyWordTableRow.originTwips` retains the signed first `rgdxaCenter` edge
from `sprmTDefTable`. The ordered `sprmTDxaLeft` and `sprmTDxaGapHalf` properties
can subsequently move that origin without changing individual cell widths.
Negative origins remain negative: the native fixture's 108-twip outdent must
not silently become zero and shift every cell's text by 5.4 points.

DOCX constructs its grid from the absolute edges of all rows. Under the legacy
Word placement used by this conversion, a top-level table's `w:tblInd` equals
the boundary origin plus the first cell's effective leading margin. Nested
tables use the boundary origin directly. Rows beginning or ending inside that grid retain their
missing leading or trailing cells through `w:gridBefore`/`w:gridAfter` and
`w:wBefore`/`w:wAfter`. Differently split and indented rows therefore share a
grid without inventing content cells. This is property preservation; exact
placement still needs an independently rendered comparison.

The authored native-origin probe checks zero and nonzero default margins,
per-cell overrides, negative and positive origins, an independent half-gap,
and nested tables. On LibreOfficeDev 26.8.0.0.alpha0
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, all nine cases retained the native
DOCX indents and produced zero measured horizontal cell-text drift relative
to the surrounding paragraph. The original fixture's implicit page and font
defaults differ between binary and OOXML consumers, so these are relative
table-position measurements, not whole-page goldens. The reviewed measurements
are in `test/fixtures/word_native/table-origin-golden.json`; the probe never
updates them automatically.

```sh
dart run tool/fidelity/table_origin_fixture.dart build/table-origin-fixtures
python tool/fidelity/table_origin_probe.py --office /path/to/soffice \
  --fixtures "$PWD/build/table-origin-fixtures" \
  --output "$PWD/build/table-origin-native" \
  --golden test/fixtures/word_native/table-origin-golden.json
```

References: [TDefTableOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/de06ec41-a0ac-4046-9096-cdfaa0091ad9)
and [Table Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b39a6648-501c-4361-8366-4f042f579469).
Tests: `test/legacy_word_table_origin_test.dart`.

## Cell formatting and conditional table styles

The parser now reads `StkTableGRLPUPX` table styles and retains their names,
identities, parent relationships, band sizes, and all twelve `CNFOperand`
conditions. Supported cell properties include shading, table and cell borders,
vertical alignment, no-wrap preference, and per-side cell margins. The native
DOCX includes table style definitions, `w:basedOn`, `w:tblLook`, band sizes and
`w:tblStylePr` conditional rules, as well as resolved cell properties.

The condition cascade follows the binary specification: horizontal bands,
vertical bands, edge columns, edge rows, then corner cells. Enabled header rows
and the first column are excluded from their respective band counts. First-row
and first-column rules take precedence over the corresponding last-row and
last-column rules in one-row or one-column tables. Each condition retains its
own inherited properties; style cycles and malformed or nested conditions are
rejected within the existing limits.

Modern `sprmTInsert` rows can inherit cell formatting from the table style.
Direct `TC80` borders and alignment, ordered `sprmTSetBrc80` / `sprmTSetBrc`
updates, and `CSSA` default and per-cell margins survive as editable cell
properties. A nil border explicitly removes a border; it does not inherit.
Raw nil shading inherits the style, whereas raw automatic shading clears the
fill. These two nil meanings are deliberately separate.

The source default cell margins are 108 twips at each horizontal side and zero
at the top and bottom. Conversion emits them explicitly, instead of depending
on a consumer's DOCX defaults. The source `halfGapTwips` remains a separate
origin offset and is never reused as padding. Zero margins and explicit nil
widths retain their distinct native representations.

Conditional paragraph and character differences are now applied before source
character-run segmentation. A structural paragraph prepass identifies each
paragraph's innermost table, row, and cell. The parser then applies the table
base, matching `PCnf`/`CCnf` differences, paragraph styles, and direct properties
in order. No already-coalesced runs are restyled, and the prepass does not emit
fields, media, references, or revisions a second time. Explicit false values,
source-relative `0x80`/`0x81` toggles, and character-style changes are evaluated
against the active table and paragraph context.

Supported text differences include alignment, indents, spacing, paragraph
pagination flags, borders/shading, font size/name/color, emphasis, underline,
character spacing and vertical position. An encountered highlight in a source
table-style definition is nonconforming (`UpxChpx` excludes properties preserved
across `CIstd`). Its value remains on resolved runs and in conversion evidence,
with a partial-formatting diagnostic; no invalid `w:highlight` is written into
native `StyleRunProperties`. The public model records
which properties the source actually specified. Native `w:pPr`/`w:rPr` style
rules emit only those differences, preserving the distinction between absence
and an explicit default. Conditional tab-change operators and additional text
properties remain diagnosed as unsupported. Source-relative toggles inside
table-style definitions resolve current cell text correctly; their raw operands
are retained as conversion evidence and reported as partial formatting because
overlapping conditional contexts cannot be represented by one context-free
native toggle rule. This limitation does not apply to the ordinary CHPX toggles
whose resolved runs remain explicit native text.
Differently styled rows retain their resolved cell formatting; the first row's
style supplies the table-wide native style reference. Floating tables,
cell-spacing geometry, and additional incremental row operators still require
further work. This is not a claim of complete conditional-style equivalence.

Primary references:

- [StkTableGRLPUPX](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/1bf37486-85c7-469b-a817-6204bbb7ed32)
- [Determining Formatting Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d8b66123-1a3d-4e06-94c5-5ab16e9b6417)
- [CNFOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/8c71d6a6-35dd-4462-9471-d376adebfe98)
- [Fatl](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/c2b2c89f-4ba1-4013-a459-b66caa1171c2)
- [TC80](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/9dd62a79-8c0b-4b11-99ee-05742ae7cf6d),
  [Brc80MayBeNil](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/8458edbd-c81c-4ec7-b5ff-c99c50575301),
  and [BrcMayBeNil](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/4e2ba2c9-8763-4b29-b81c-ce0123df689e)
- [CSSA](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/6c5d3dfc-988d-4e2b-a9dd-72b62cb64356)
- [TInsertOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/082d49fd-8f96-4fd9-ac6e-61bd7c00b90d)

Tests: `test/legacy_word_conditional_table_test.dart`,
`test/legacy_word_table_text_test.dart`, and
`test/legacy_word_table_format_test.dart`. The native Office fidelity runner
remains the independent check for actual border pixels and cell text positions.

### Nonconforming exporter recovery

A LibreOffice bridge fixture (`word-compatibility.doc`) contains a `cb=0`
PAPX ending with one stray byte after otherwise complete properties. The
parser accepts exactly this case and reports
`recoveredNonconformingProperties` plus `unsupportedFormatting`. It does not
retain the orphan's value as a supported property or claim this is legal
padding. The recovery does not apply to CHPX, styles or indirect properties,
and never repairs a truncated operand or extended-length record.

[PapxInFkp](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/580510b8-df7a-467e-a51c-0d71eb15c7cd)
declares the entire two-byte-aligned extent, while
[GrpPrlAndIstd](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/bd96f2aa-1318-4066-9723-4db035ef412b)
requires whole property records. The warning therefore identifies an exporter
compatibility recovery, not a change to those extents. Focused positive and
negative cases are in `test/legacy_word_fkp_recovery_test.dart`.

## Shared list-instance continuation

The source `lsid` identifies the number sequence even when paragraphs alternate
between distinct `ilfo` instances. When every instance for an `lsid` has no
level overrides, the parser records the shared sequence using
`LegacyWordNumberingDefinition.continuationOf`. Original instance ids and signed
paragraph `listId` values remain intact. HTML shares its counter and DOCX maps
the instances to one editable `w:num`; conversion evidence records that mapping.
Numbering continues across intervening paragraphs and does not depend on which
instance is encountered first.

Groups that include start or formatting overrides still report
`numberingNotReconstructed`. The first-use override and per-level restart rules
require more than grouping by `lsid`; those instances are not silently merged.

## Marker font inheritance and the indentation oracle

An unlinked list level with no explicit marker font leaves the native font
unspecified, so its number can inherit the authored paragraph mark's font.
Previously the parser supplied the stylesheet's default font even for an empty
LVL character-property array. This could replace an Arial paragraph mark with
Times New Roman. Explicit marker fonts and fonts from a linked list style remain
authoritative; no replacement family is guessed.

The native `word` corpus bridge demonstrates this separately from indentation.
Its source DOC and native DOCX render the `1.` marker using Liberation Sans,
the installed substitution for the authored Arial. The old conversion rendered
it using Liberation Serif. With the absent marker override preserved, the
conversion renders it using Liberation Sans too. Exact source/package/PDF
hashes, rendered bounds and the binary properties are recorded in
`doc/evidence/list-marker-font-native.json`.

That fixture still has an 18-point indentation disagreement. Its positive
`ilfo=1` selects a level whose paragraph properties explicitly set both indents
to zero. Its paragraph style and direct properties specify left 720 and first
line -360 twips. [MS-DOC formatting order](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d8b66123-1a3d-4e06-94c5-5ab16e9b6417)
applies the [list level properties last](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/1a0bc623-211f-44f6-828b-51993f16e586),
whereas this LibreOffice import retains the paragraph indents. The parser keeps
the documented order. A negative `ilfo` still preserves the paragraph's logical
left and first-line indents, as [sprmPIlfo requires](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/484822ee-a9d9-4af4-8423-29fda67a6a58).
The disagreement remains open; the font correction is not reported as exact
pagination or as a reason to reverse all list/style precedence.

`test/legacy_word_list_precedence_test.dart` independently assembles font tables,
linked and unlinked list styles, direct indentation and both signs of `ilfo`.
It checks native font inheritance and explicit overrides, invalid font indices,
and the contrasting positive/negative indentation contracts in model and XML.
Public continuation references must name an unchained definition with the same
source id and shared level objects, preventing a continuation from discarding
different formatting.

Reference: [Determining Level Number of a Paragraph](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/361e48e1-ae56-4b62-a950-01664b2cc006).
Tests: `test/legacy_word_list_continuation_test.dart`.

## Residual scope

Floating-table placement, additional conditional text operators, native relative
table-style toggle rules, and list-instance
continuation with overrides need their own property-level interpretation. Retaining nested
content alone does not establish page-layout equivalence to Microsoft Word.
