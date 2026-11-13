# Footnote-table oracle attribution

The remaining initial **74.427-point** `table-borders` measurement is a native
DOC-import limitation, not a parser table-placement defect. The parser output
at `0c3e59682952cce0e11301afec789e7ae2a1256a` has exactly the same page geometry,
word boxes, layout text, and RGB raster as the authored DOCX. The native bridge
renders the footnote table as an ordinary paragraph; its DOCX export contains
no `w:tbl` in the footnote. All main-body table word boxes already agree.

The binary source itself retains the table. It is byte-identical to the checked
fixture `test/fixtures/word_native/note-table-ending.doc`, SHA-256
`1ee6343bf51ce1dda4d9ef14eb106ac5826386f7530601d0f4d2c2a2b9b96115`.
Independent CLX and PAPX decoding gives these source anchors:

| Source location | Literal evidence |
| --- | --- |
| CLX text piece | CP 0–149, UTF-16, `WordDocument` byte 2048 |
| Footnote table | CP 124–147; cell mark U+0007 at CP 145 and row mark at CP 146 |
| Cell PAPX, FC 2296–2340 | `sprmPFInTable=1` at byte 3256; `sprmPItap=1` at 3259 |
| Row PAPX, FC 2340–2342 | `sprmPFInTable=1` at 3967; `sprmPFTtp=1` at 3970; `sprmPItap=1` at 3973 |
| `sprmTDefTable`, byte 3979 | One cell, grid edges 0 and 2000 twips |
| `sprmTCellPaddingDefault`, bytes 4061 and 4079 | Left and right margins each 108 twips |

`source-attribution.json` records the raw operation operands, exact word boxes,
hashes, and comparisons. The complete unchanged source, DOCX outputs, PDFs,
rasters, and repeat runs remain in
`../native-corpus-0c3e596/sealed/04-table-borders/`. No reference artifact or
golden has been replaced.

The fixture's existing table-ended-note test now also checks these literal
source-derived boundaries, width, and margins, including the emitted 2000-twip
table and grid width. Flattening the table to imitate the native import would
lose source structure and break the exact authored rendering. No runtime
compensation is needed for this case.

Validation: `dart test test/legacy_word_table_position_test.dart` passes all
19 tests on Dart 3.13.7, including the new source-width/margin assertions and
the existing floating-origin, border, alignment, and note-boundary controls.

The source interpretation follows [MS-DOC Table Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b39a6648-501c-4361-8366-4f042f579469)
and the cell/row terminal structure already covered by the parser's table tests.
