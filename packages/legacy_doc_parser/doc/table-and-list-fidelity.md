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

Table nesting is scoped to the content story. A textbox anchored in a body or
header table has its own top-level table origin; it does not inherit the
anchor cell's nesting depth. Entering the textbox and returning to its anchor
preserves both contexts, including genuinely nested tables in either story.
`test/legacy_word_textbox_table_test.dart` compares identical textbox content
anchored in a paragraph and in a table, across body/header placement,
default/zero/explicit margins and nested content. The independent binary
fixtures and converted packages can be produced with
`tool/fidelity/textbox_table_fixture.dart`. These controls verify the emitted
indentation and content without claiming arbitrary textbox pagination.

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

## Incremental row operations and table boundaries

`PTableProps` reads the referenced bounded `Data` record and stops its containing
property array. Older inline table properties after that pointer are not applied
or decoded as current properties. The same rule applies when multiple rows reuse
a cached record. Records shorter than ten bytes, cycles, excessive chains, and
out-of-range extents fail explicitly.

Rows now apply `TInsert`, `TDelete`, `TDxaCol`, `TMerge`, and `TSplit` in source
order. Cell widths, TC80 formatting, borders, shading, margins, and alignment move
with their cell definitions; deleting a cell cannot accidentally move its direct
formatting onto an unrelated cell. Empty deletion results, invalid cell ranges,
and excessive widths are rejected. Merge flags remain native editable `hMerge`
properties. The preview keeps continuation text visible, which is intentionally
not a claim of exact Word merged-cell layout.

Style application replaces supported row defaults while retaining the existing
cell definitions and direct cell formatting. It also retains TIstd's documented
exceptions such as direction, origin-related positioning, half-gap, row height,
auto-fit, style options, and review metadata. This distinction is independently
tested with Apache POI's Word-authored `simple-table2.doc`: its modern Data rows
contain `TInsert → TDxaCol → TIstd`, without another cell definition. Clearing
the cell structure at TIstd would destroy that valid three-column table. The
same fixture has an explicit two-byte `istd` prefix in both table-style PAPX
records; the reconciled implementation retains that framing. See
`doc/table-upx-native-evidence.md` for the source hashes and raw evidence.

Adjacent rows with different table-style, direction, or retained group/position
identities form separate tables before conditional text is resolved. Physical
`TJc90` values and logical `TJc` values remain distinct, including in right-to-left
tables. DOCX writes native `bidiVisual`, justification, width, and fixed/automatic
layout properties. Later rows can explicitly restore left alignment and fixed
layout through `tblPrEx`; defaults on a later row do not silently inherit the
first row's nondefault setting. PGP hierarchy interpretation and floating table
placement remain unsupported and diagnosed.

Table style UPXs are decoded without following Data-stream references. Property
groups, known forbidden structural operators, and nested conditions are checked
before application. Supported conditional text/cell formatting keeps its existing
precedence and explicit-reset semantics; other visual style properties continue
to report partial formatting.

Tests: `test/legacy_word_table_operations_test.dart`,
`test/legacy_word_table_properties_test.dart`, and the independently assembled
`tool/fidelity/table_operations_fixture.dart`. All twelve authored outputs are
registered by exact identity in the independent Open XML SDK schema corpus.
Schema validity does not establish native pagination or mirrored-table equivalence.

The HTML preview now uses resolved cell borders, margins, vertical alignment,
no-wrap, table direction, origin, alignment and sizing preferences. It no longer
invents a gray grid or four-pixel cell margins. Exact row heights, unequal row
origins, vertical cell text, fit-text, and hide-mark behavior remain explicitly
marked as approximate when encountered. Tests are in
`test/legacy_word_table_preview_test.dart`.

References: [Table Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b39a6648-501c-4361-8366-4f042f579469),
[Paragraph Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/484822ee-a9d9-4af4-8423-29fda67a6a58),
[UpxTapx](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/eed2eef0-2943-4c2f-b348-3f1d1af59fdf),
and [UpxPapx](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/659f448a-473a-44c6-8b69-a25984af3645).

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
A cell border of type none inherits the applicable style or row default.
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
Differently styled adjacent rows become separate tables, each retaining its own
native style reference and resolved cell/text formatting. Bounded preferred
cell widths retain their percentage and other source units independently of
the physical grid. Floating tables, cell-spacing geometry, table-wide preferred
widths, complete automatic-layout behavior and additional incremental row
operators still require further work. This is not a claim of complete
conditional-style equivalence.

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

The reconciled shared resolver also retains explicit LFOLVL `startOverrides`,
shares counters across compatible formatting-only changes, and resolves
multilevel restarts and ancestor references in source character order. Ancestor
placeholders use the same source `ilfo`, while compatible counters share `lsid`.
Each body, header, note, comment, or textbox story starts its own scope. When a
resumed sequence needs different counters or ancestor values, conversion emits
a real editable `w:num` with `w:startOverride`, rather than baking a label into
text. Paragraph numbering-change and insertion revisions reference that actual
native instance.

The two retained source fixtures `list-continue.doc` and `list-restart.doc` have
independent single-level render receipts in `doc/list-sequence-native-check.json`
from recovered branch `b03747396878518d0d623599baf9b376df776e3d`. These are historical
receipts, not regenerated results for every later converter revision. Their
source/converted labels are respectively `1, 2, 3, 4, 5` and
`1, 2, 7, 8, 3, 9`. Authored binary tests additionally exercise Roman formatting
changes, same-instance ancestors, never-restart lower levels, story isolation,
hidden markers and numbering revisions on a resumed instance.

Interleaved explicit-start groups and incompatible base policies still report
`numberingNotReconstructed`; the published fStartAt algorithm is ambiguous for
some restart/resume combinations. The two native examples do not establish
identical behavior across all Word versions or all multilevel overrides.

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

## Row height, page splitting and cell text layout

`sprmTDyaRowHeight` retains its signed value: zero selects automatic height,
positive values establish a minimum, and negative values specify an exact
height. The native writer emits `w:trHeight` with the corresponding `auto`,
`atLeast` or `exact` rule. Values outside the MS-DOC YAS range of
-31680 to 31680 twips are rejected. `sprmTFCantSplit` takes precedence over
`sprmTFCantSplit90` regardless of record order; a lone legacy flag is retained.
Explicit false and absent flags remain distinct. These rules come from
[MS-DOC table properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b39a6648-501c-4361-8366-4f042f579469)
and [YAS](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/cc683bcd-0c67-4002-9317-53e92a4d793d).

TC80 cell descriptors now preserve the five legal text directions, `fitText`
and `hideMark`. Invalid text-flow codes are rejected. These are editable native
`w:textDirection`, `w:tcFitText` and `w:hideMark` properties, with explicit
`on`/`off` reset values. The mapping follows
[TCGRF](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/11bf5b1c-943f-421d-bbf3-39088cd1b8dd)
and [TextFlow](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/91341630-00bb-4b5f-891e-0ea68a069d9a).
Row properties inside table-style differences and separate range-update
operators for text flow, fit text and hide mark remain outside this increment.

`tool/fidelity/table_layout_fixture.dart OUTPUT_DIR` independently assembles
five height fixtures, two page-boundary split fixtures, and a cell-layout
fixture. Its inputs specify a font, exact line spacing and page dimensions;
the expected row heights do not depend on the parser's own XML writer.
`test/fixtures/word_native/table-layout-golden.json` records the reviewed
source hashes, native row properties and text positions. Run:

```sh
dart run tool/fidelity/table_layout_fixture.dart build/table-layout-inputs
python3 tool/fidelity/table_layout_probe.py \
  --office /path/to/soffice \
  --fixtures build/table-layout-inputs \
  --output build/table-layout-measurements \
  --golden test/fixtures/word_native/table-layout-golden.json
```

On LibreOfficeDev 26.8.0.0.alpha0
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, all five measured row extents agreed
to 0.0 points. An allowed split placed the first three lines of a six-line row
on page 1 and the remaining three on page 2; `cantSplit` moved all six lines
to page 2. Source DOC and converted DOCX matched these positions and page
assignments. The SDK independently validated all eight generated packages.
This renderer drops fit/hide properties and simplifies the East Asian rotated
flow variants when exporting native DOCX, so those fields have structural
preservation assertions rather than an exact-rendering claim. The probe checks
both the current native source projection and the parser output against the
reviewed golden and exits unsuccessfully on a mismatch.

Tests: `test/legacy_word_table_layout_test.dart` and
`tool/fidelity/test_table_layout_probe.py`. These bounded cases do not establish
exact pagination for arbitrary tables, other fonts or other renderers.

## Direct row-wide borders

Both `sprmTTableBorders80` and `sprmTTableBorders` preserve all six row defaults:
top, left, bottom, right, horizontal interior and vertical interior. Record
lengths are checked exactly. Row defaults survive whether they occur before
or after `TDefTable`; later row-default records replace earlier values.
Native output retains the defaults in `w:tr/w:tblPrEx/w:tblBorders` and also
emits the resolved physical borders on each cell.

Explicit non-none TC80 and range-update borders still take precedence. Nil
suppresses an edge; none requests inheritance. A later range update to none
can therefore restore a row default that an earlier explicit cell border
overrode. Conditional cell-style borders are considered before row defaults;
direct row defaults replace the base table-style defaults. The interpretation
follows [MS-DOC TableBordersOperand80](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/e334b793-1c10-4fed-8fac-69c3f8fb41b6),
[TableBordersOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/203adfdf-332c-4f4e-b3d9-3a809d4b275b)
and [Word's documented border-resolution rules](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/7c791c5d-44c3-4fe8-abdd-8f136761bb93).

The independent producer `tool/fidelity/table_borders_fixture.dart OUTPUT_DIR`
contains twelve cases: old/current row records, both application orders,
explicit cell overrides, nil suppression, none inheritance, a whole-row reset,
and differently colored and weighted outer/interior edges. Run
`tool/fidelity/table_borders_probe.py` with the same `--office`, `--fixtures`,
`--output` and `--golden` interface as the layout probe, using
`test/fixtures/word_native/table-borders-golden.json`.

On the renderer version recorded above, all twelve native source/converted
border projections agreed and their colored border masks matched exactly at
144 DPI. Positive fixtures contain 2,748–11,916 colored pixels; nil/reset
controls contain zero. The comparison excludes grayscale text and is a
border-rendering check, not a whole-document pixel claim. All twelve generated
packages pass the independent Open XML SDK schema check, including row
exceptions. Eight binary/model/XML tests and five probe failure-control tests
cover the increment in `test/legacy_word_row_borders_test.dart` and
`tool/fidelity/test_table_borders_probe.py`.

## Residual scope

Floating-table placement, additional conditional text operators, native relative
table-style toggle rules, adjacent-row table boundaries that depend on style or
floating-position changes, and unverified list-instance
restart combinations need their own property-level interpretation. Retaining nested
content alone does not establish page-layout equivalence to Microsoft Word.
