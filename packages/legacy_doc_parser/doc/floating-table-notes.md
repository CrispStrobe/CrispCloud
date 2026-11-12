# Floating tables and note boundaries

The retained native corpus at `doc/evidence/native-corpus-7308125` showed
13.45 pt of additional displacement on every DOC round trip for
`table-borders` and `note-markers`. Inspection of the archived binary and
OOXML artifacts identified two distinct causes.

The `table-borders` footnote ends at a closed table-row mark. The writer added
an empty paragraph after that source table. Footnotes and endnotes permit a
table as their final block, so this paragraph was new editable content. When
exported again, native Office supplied another table anchor paragraph. The
note writer now preserves the original final block; it still writes every
actual source paragraph, including deliberately empty paragraphs.

The final `note-markers` footnote contains a floating table. Its row properties
specify `sprmTPc=0xA0`, centered horizontal placement and top vertical placement.
The next regular paragraph at CP 188–189 is its real anchor. Previously those
positioning properties were used only to distinguish adjacent tables. The
writer consequently created an inline table followed by a visible empty
paragraph, and each native DOC export added another anchor. The parser now
retains physical table anchors, relative placements or signed twip offsets,
four wrapping distances and overlap behavior. The writer emits `w:tblpPr`
and `w:tblOverlap` while preserving the existing anchor paragraph.

`test/legacy_word_table_position_test.dart` covers the source-native binaries,
all nine anchor combinations, alignment sentinels, signed `*_plusOne` values,
wrapping directions, malformed operands and both note kinds with authored
empty or nonempty trailing paragraphs. The two native fixtures reproduce the
original archived source bytes; `note-table-provenance.json` records their
hashes and exact archive members. The existing layout, table-operation,
header/footer-boundary and story tests remain controls.

This preserves table structure and source content. It does not turn the native
DOCX interpretation into a structural oracle: the installed Office build
flattens one note table and converts the other into a drawing frame. Initial
source-render discrepancies and native bridge changes are measured separately
from repeat stability; the old reports and source goldens remain unchanged.

The property mapping follows [MS-DOC table properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b39a6648-501c-4361-8366-4f042f579469),
[PositionCodeOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/4adae037-8747-471a-a1a0-082a5244ebc7),
[XAS_plusOne](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/e7215f9f-d29c-4c53-8ac4-3c1df1f0b517)
and [YAS_plusOne](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5740209e-2844-4452-bf30-14c041732cc8).
OOXML floating-table positioning uses the next regular paragraph as its
anchor, as specified by [TablePositionProperties](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.tablepositionproperties).
