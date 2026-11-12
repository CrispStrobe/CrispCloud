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

DOCX writes the origin as `w:tblInd` and constructs its grid from the absolute
edges of all rows. Rows beginning or ending inside that grid retain their
missing leading or trailing cells through `w:gridBefore`/`w:gridAfter` and
`w:wBefore`/`w:wAfter`. Differently split and indented rows therefore share a
grid without inventing content cells. This is property preservation; exact
placement still needs an independently rendered comparison.

References: [TDefTableOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/de06ec41-a0ac-4046-9096-cdfaa0091ad9)
and [Table Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b39a6648-501c-4361-8366-4f042f579469).
Tests: `test/legacy_word_table_origin_test.dart`.

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

## Table styles and cell geometry

The parser reads table-style TAPX, PAPX and CHPX in stylesheet order. It resolves
inheritance and the conditional regions selected by `sprmTTlp`: horizontal
bands, vertical bands, edge columns, edge rows, then corner cells. Leading header
rows are excluded from horizontal band counts when first-row formatting is
enabled. Paragraph styles and direct formatting still apply after the table
style. Nested content uses its innermost table's style.

`sprmTIstd` resets represented table overrides while retaining the properties
explicitly exempted by MS-DOC. `sprmPTableProps` follows bounded Data-stream
indirection and ends processing of the containing property array; its legacy
fallback does not overwrite the modern properties. `TInsert`, `TDelete`,
`TDxaCol`, `TMerge` and `TSplit` update the cell definitions and shift existing
cell overrides. Invalid ranges, cycles, conditional flags, property groups,
forbidden style properties and oversized bands fail explicitly.

The resolved model and DOCX output retain logical table origin, row height,
repeating-header and no-split controls, direction, cell widths/merges, vertical
alignment, supported borders, shading, and default/style/direct cell margins.
Raw shading `Nil` inherits the table style; `Auto` explicitly clears shading.
Adjacent rows with different style, group, direction or floating-position
identity are separated. The authored `formatting.doc` fixture retains its
−108-twip left origin and 108-twip horizontal cell margins.

The binary outer edge remains separate from the DOCX leading text indentation:
the writer adds the first logical cell's margin and emits an explicit zero when
they cancel. The native `formatting.doc` check places both first-row cell texts
at the original x coordinates with this mapping. Known grid widths use fixed
layout unless the source explicitly enables `TFAutofit`; no blanket application
compatibility mode is inferred. A native DOC importer/exporter can itself move
unbordered tables or flatten note tables, so those differences are recorded as
renderer/bridge disagreement rather than repaired by dropping source cells.

DOCX materializes these resolved properties rather than inventing a reusable
table-style definition. Source style ID/name/look remain in the conversion
evidence. HTML keeps the cell hierarchy, simple border/color/spacing and
alignment, and marks unsupported border effects as approximate.

Sources: [Determining Formatting Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d8b66123-1a3d-4e06-94c5-5ab16e9b6417),
[Table Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b39a6648-501c-4361-8366-4f042f579469),
[TDefTableOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/de06ec41-a0ac-4046-9096-cdfaa0091ad9),
and [TCGRF](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/11bf5b1c-943f-421d-bbf3-39088cd1b8dd).
Tests: `test/legacy_word_table_styles_test.dart` and
`test/legacy_word_decorations_test.dart`, including independently assembled
binary style records and XML inspection of generated packages.

## Residual scope

Floating-table placement, cell spacing, preferred percentage sizing,
cell text rotation/fit/nowrap, table backdrop shading, and some border layout
effects remain partial and report unsupported formatting when encountered.
Table boundary distinctions involving paragraph frames or protection bookmarks
are not reconstructed. Conditional formatting is resolved for current content;
later editing in Word does not dynamically reapply the source binary style.
These changes do not establish page-layout equivalence to Microsoft Word.

## List instances, continuation and restarts

`LegacyWordNumberingDefinition.startOverrides` preserves explicit LFOLVL
restart values separately from each resolved level's default formatting. The
existing `levels[].startAt` remains compatible with earlier callers. When both
formatting and start flags are set, the overriding LVL supplies the value; the
otherwise undefined LFOLVL integer is not interpreted.

The additive `continuationOf` compatibility field identifies identical,
unmodified instances that can share a native numbering definition. The parser
sets it only when the complete LSID group has no overrides; malformed public
references are rejected. Those aliases share one editable `w:num`. Other
instances keep the bounded counter interpreter and explicit restart metadata.

The shared interpreter processes paragraphs in source CP order, including
nested cells. Compatible list instances with the same original LSID continue
one level sequence. Different LSIDs remain independent. A level's restart
threshold and never-restart setting control resets after more significant
levels; ancestor placeholders use the closest preceding paragraph from the
same ILFO. Story scopes are independent. Legal numbering retains an inherited
`decimalZero` format, as required by LVLF, while changing other numeric formats
to decimal.

DOCX preserves editable numbering. If another source instance advanced a
shared sequence, resuming the earlier instance creates a new `w:num` with
explicit starts for the required current and ancestor values. It does not
prepend literal numbers to document text. Formatting-only instance changes
retain their number formats and marker properties, including hidden markers.
Generated numbering parts and label expansion have explicit complexity limits.

The independently assembled binary tests cover shared instances, restart and
resume, formatting overrides, higher-level resets, ancestor identity, separate
stories, invalid override metadata, and malformed binary list records. Native
LibreOffice renders also confirm these two complete source/conversion cases:

| Source instance sequence | Configuration | Native labels before and after conversion |
| --- | --- | --- |
| 1, 1, 2, 2, 1 | Shared LSID; no overrides | 1, 2, 3, 4, 5 |
| 1, 1, 2, 2, 1, 2 | Shared LSID; instance 2 explicitly starts at 7 | 1, 2, 7, 8, 3, 9 |

The published MS-DOC algorithm has ambiguous ordering around the first
`fStartAt` occurrence and the excluded current paragraph. Therefore shared-LSID
restart combinations retain `numberingNotReconstructed` / `fieldsLists`
limitations even when the native cases above agree. Incompatible base-start or
restart policies also stay explicit instead of receiving guessed continuation.
The minimal multilevel/formatting fixtures are checked against primary field
definitions and generated OOXML; the native binary importer did not interpret
all their details, so they are not claimed as native-fidelity evidence.

Sources: [Determining List Formatting](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/1a0bc623-211f-44f6-828b-51993f16e586),
[Determining Level Number](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/361e48e1-ae56-4b62-a950-01664b2cc006),
[LFOLVL](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/2555c6ec-604b-48fd-8484-a2fdbb95b42c),
[LVLF](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/500d1b05-cd15-46af-bc8f-03bc290d1bdd),
and [Microsoft Open Specifications support's LSID confirmation](https://learn.microsoft.com/en-ca/answers/questions/944238/word-doc-binary-file-format-query-regarding-preser).
Tests: `test/legacy_word_list_sequences_test.dart`,
`test/legacy_word_lists_test.dart`, and `test/legacy_word_preview_parity_test.dart`.
The binary fixture builder is `test/support/list_sequence_fixture.dart`.
The version, source/package/PDF hashes and extracted labels for the two native
cases are recorded in [list-sequence-native-check.json](list-sequence-native-check.json).
